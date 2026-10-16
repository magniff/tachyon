# tachyon 0.23 design: windows and input in std (`std::window`), and a terminal emulator (`examples/term`)

This document builds on the 0.22 design (docs/design/gpu.md, same
branch): `std::objc`, `std::gpu`, the OS-specific module files (C1), std
submodules (C2) and `include_str` (C3) are defined there. I read the
language as described in gpu.md's introduction. I also ran a Core Text
spike (§1.2), imported `util.h` (forkpty) on the Mac, and probed the
linux/arm64 container for Xvfb, weston, xkbcommon, FreeType, fontconfig
and libvterm (gpu.md §1.3). Alacritty 0.17.0 (94e7c88) is installed in
/Applications and is the baseline. I modified nothing but the two design
documents.

The user is away and asked for autonomous work through 0.23: every choice
below is taken as recommended and listed in the last section.

## 1. The current state

### 1.1 What exists

- **No window, no event loop, no text rendering.** examples/life draws
  with ANSI escapes in an existing terminal and reads the size with
  `ioctl`. That is the only terminal code in the tree.
- **C interop reaches everything a terminal needs:**
  - `forkpty` and `ioctl` (`import "util.h"`: 1,281 lines of
    declarations, read cleanly);
  - Core Text, Core Graphics and Core Foundation, once their headers can
    be found (C4 in gpu.md);
  - AppKit through `std::objc` (gpu.md §2.9).
- **`u8` text.** There are no `char` or `String` types, and display width
  arrives in 0.20 ("chars, graphemes and display width (needed by the
  terminal)").
- **No threads before 0.21.** A pty can still be served on one thread
  with `poll`, inside the window's event loop.

### 1.2 Spike: Core Text rasterization from tachyon (2026-10-16)

`import "CoreText/CoreText.h" as c;` with `-I` pointing at a directory of
symlinks to the SDK's framework `Headers` (C4 makes this automatic). The
program does the following:
- `CFStringCreateWithCString`, then `CTFontCreateWithName("Menlo", 24)`;
- `CGColorSpaceCreateDeviceGray`, then `CGBitmapContextCreate` over a
  tachyon array of 20×30 bytes;
- `CTFontGetGlyphsForCharacters`, then `CTFontDrawGlyphs` at
  `(2, descent)`;
- it prints the coverage as ASCII art.

The result is a correct, antialiased "g" with its descender; glyph id 74,
descent 5.66. The import took 0.17 s for 16,218 lines. Every Core Text
type, constant and function the atlas needs was imported, with
`CGPoint`'s and `CGAffineTransform`'s C layout. **Glyph rasterization
works on today's compiler.**

### 1.3 What the container gives the Linux side

- Xvfb 21.1 and weston 10.0.1 with the headless backend: the X11 and
  Wayland window backends run in CI without a display.
- lavapipe exposes `VK_KHR_xcb_surface`, `xlib_surface` and
  `wayland_surface`, so swapchains are testable too.
- xkbcommon 1.5 (with `-x11`), libwayland and wayland-protocols, xcb
  1.15.
- FreeType 2.12.1, fontconfig 2.14.1 and fonts-dejavu-core.
- libvterm 0.1.4, a possible second oracle for the parser (§4.2).

## 2. `std::window` (decided)

### 2.1 Shape: pull events, winit's objects

```tach
use std::window::{App, Event, Key, WindowDesc};

fn main(gpa: Gpa) -> Result<(), window::Error> {
    let mut app = App::new_in(gpa)?;
    let win = app.window(&WindowDesc::new("term", 800, 600))?;   // logical points
    let (dev, queue) = gpu::Instance::new_in(gpa).adapter(gpu::Power::Low)?.device()?;
    let surf = dev.surface(&win)?;                               // std::gpu (0.22)
    loop {
        match app.wait()? {                                      // blocks; no busy loop
            Event::Frame(id) => draw(&mut state, &surf),         // only after win.request_frame()
            Event::Key(k) => on_key(&mut state, k),
            Event::Text(t) => send(&mut pty, t.as_slice()),
            Event::Resize(id, size) => resize(&mut state, size), // physical pixels and scale
            Event::Readable(fd) => pump_pty(&mut state),         // a watched fd (before 0.21)
            Event::Close(id) => break,
            _ => {}
        }
    }
    Ok(())
}
```

- **Events are pulled.** `app.wait()`, `app.poll()` and
  `app.wait_timeout(ms)` return one `Event`, a plain enum.
  - winit pushes events into a callback (`run_app`). Under 0.17 that
    needs an owned, long-lived closure holding the application state,
    and agents find it harder to read.
  - With a pull loop, state is ordinary locals, and the borrow rules
    are the usual ones.
- **The macOS exception: live resize.** AppKit runs its own nested loop
  while the user drags a window's edge, so a pull loop stalls there.
  `app.on_live_resize(draw_fn, ctx)` registers one redraw function. The
  view's `setFrameSize:` IMP calls it directly during the drag, so the
  terminal reflows and redraws in step. It is the only callback in the
  API. Before 0.17 it is a plain `fn(*u8)` with a context pointer, and
  after 0.17 a `&mut` closure valid for one call.
- **Text events carry their bytes inline**
  (`Text { len: u8, bytes: [u8; 30] }`, plain). A longer IME commit
  arrives as several events. No allocation per key: the event loop is
  `alloc`-free in steady state.
- **The frame clock is on request.** `win.request_frame()` asks for one
  `Event::Frame` at the next display refresh. On macOS this is
  `NSView.displayLinkWithTarget:selector:`: a `CADisplayLink` on the main
  run loop, macOS 14 and later, no thread. On Wayland it is a
  `wl_surface.frame` callback, and on X11 a timer at the monitor's rate.
  When nothing is requested, nothing wakes up: an idle terminal costs
  zero CPU.
- **Watched file descriptors (`app.watch(fd)`)** deliver
  `Event::Readable(fd)`. On macOS this is a `CFFileDescriptor` source on
  the main run loop, and on Linux the same `poll` that waits on the
  Wayland or X11 connection. This is how the pty is served before 0.21.
  It stays useful after 0.21, which adds `app.waker()`, a thread-safe
  handle that wakes `wait()`.

### 2.2 What a window gives

| area | API | macOS (Cocoa) | Wayland | X11 |
|---|---|---|---|---|
| windows | `app.window(&desc)`, title, size, min size, fullscreen, close | `NSWindow` + a runtime `NSView` subclass (`std::objc` `ClassBuilder`) with a `CAMetalLayer` | `xdg_toplevel` (xdg-shell) | xcb window, `WM_PROTOCOLS` |
| scale | `Resize { size, scale }` in physical pixels | `backingScaleFactor`, `viewDidChangeBackingProperties` | `wl_surface.preferred_buffer_scale` (fractional scale later) | Xft.dpi / RandR |
| keys | `Key { code: KeyCode, key: Logical, mods: Mods, repeat: bool, pressed: bool }` | `keyDown:`, `flagsChanged:`; `code` from the hardware keycode | `wl_keyboard` + xkbcommon | xcb + xkbcommon-x11 |
| text and IME | `Text`, `Preedit { text, cursor }`, `win.set_ime_area(rect)` | `NSTextInputClient` (`insertText:`, `setMarkedText:`, `firstRectForCharacterRange:`) via `interpretKeyEvents:` | text-input-v3 (0.23.x) | compose through xkbcommon |
| mouse | `Mouse { pos, button, pressed, mods }`, `Scroll { dx, dy, precise }`, `Cursor(enter/leave)` | `mouseDown:` and friends, `scrollWheel:` (`hasPreciseScrollingDeltas`) | `wl_pointer` (axis, axis_value120) | XInput2 when present, core events otherwise |
| clipboard | `app.clipboard_get_in(gpa) -> Option<Buf>`, `app.clipboard_set(text)` | `NSPasteboard` | `wl_data_device` | selections, with INCR for large ones |
| cursor | `win.set_cursor(Cursor::Text)`, hide while typing | `NSCursor` | cursor-shape-v1, else `wl_cursor` | Xcursor |
| GPU surface | `win.raw_surface() -> gpu::RawSurface`; `dev.surface(&win)` | the `CAMetalLayer` | `wl_display` + `wl_surface` | xcb connection + window |
| focus | `Focus(bool)` | `windowDidBecomeKey:` | `wl_keyboard.enter/leave` | `FocusIn/Out` |

`KeyCode` is a physical key (winit's `KeyCode`, from USB HID usages).
`Logical` is a named key or the produced character. `Mods` covers shift,
control, alt (Option), super (Command) and caps lock, with left and right
distinguished. Where a backend cannot report something, the event says
so (`precise: false`) rather than guessing.

### 2.3 Backends, and how they are reached

- **Cocoa.** It is written with `std::objc`'s tables (`appkit.objc`,
  `quartzcore.objc`) and objcgen, as Metal is (gpu.md §2.9), so every
  prototype is generated and checked against the runtime.
  - The application is set up without a bundle or a nib:
    `NSApplication.sharedApplication`, then
    `setActivationPolicy: Regular`, then a menu with Quit, then
    `activateIgnoringOtherApps:`.
  - Events are drained with
    `nextEventMatchingMask:untilDate:inMode:dequeue:` and `sendEvent:`,
    inside an autorelease pool per batch.
  - The view subclass (`TachyonView`) implements the input methods,
    `NSTextInputClient`, `makeBackingLayer` (a `CAMetalLayer`),
    `acceptsFirstResponder`, `setFrameSize:` (live resize) and the
    display link's selector. Its IMPs push events onto the app's queue,
    a fixed ring that grows only if events are not drained.
  - Everything runs on the main thread, as AppKit requires.
- **Wayland.**
  - libwayland-client is called through `import`.
  - xdg-shell, xdg-decoration and cursor-shape are generated by
    `wayland-scanner private-code`. The C it produces is a link input
    (C files are link inputs today), and its headers are imported. The
    generated C is checked in under compiler/std/window/wayland/proto/,
    so building needs no wayland-scanner.
  - xkbcommon handles keymaps.
  - Decorations are server-side when xdg-decoration is offered. If it is
    not (GNOME), there are none in 0.23.0, and client-side decorations
    are O3.
- **X11.** xcb and xkbcommon-x11, through `import`, the XKB extension and
  `_NET_WM` hints.
- **Each backend is an OS-specific file:** `window/cocoa.macos.tach`,
  and `window/linux.linux.tach`, which picks Wayland when
  `WAYLAND_DISPLAY` is set and X11 otherwise. Both implement
  `trait window::Backend`, the 0.22 pattern.
- **Order and scope:** Cocoa, then Wayland, then X11, all three in
  0.23.0. They are independent tasks that can start now. X11 is the
  easiest to test (Xvfb). If Wayland or X11 is late, it ships in 0.23.x
  and the other Linux backend ships alone, rather than holding the
  release.

## 3. `examples/term` (decided)

A terminal emulator in tachyon, measured against Alacritty. It is an
example program: its job is to prove std (0.20–0.23) on a real program,
and to report what the language and tools lacked to the "Toward 1.0"
rework.

### 3.1 Structure

```
examples/term/
  main.tach            options, config, the event loop (pull), wiring
  pty.tach             forkpty, the child, resize, non-blocking reads and writes
  vt/                  the parser: no allocation, no I/O, no knowledge of the grid
    table.tach         the state machine (Paul Williams' DEC parser, as vte), byte classes
    params.tach        CSI parameters and sub-parameters (fixed arrays)
    utf8.tach          the UTF-8 decoder (invalid sequences -> U+FFFD)
    mod.tach           `Parser::advance<P: Perform>(p: &mut P, bytes: [u8])`, `trait Perform`
  term/                the terminal state: implements Perform
    cell.tach          Cell, Color, Flags
    grid.tach          rows, the ring of scrollback, damage
    screen.tach        cursor, modes, scroll regions, tabs, charsets, primary/alternate
    ops.tach           every control function (CSI/ESC/OSC dispatch)
    reflow.tach        resize with reflow
    select.tach        selection (cells, words, lines, blocks)
    width.tach         display width (a generated table until 0.20's std::text)
  input/
    keys.tach          keys -> bytes (xterm encodings, modes)
    mouse.tach         mouse reporting (X10, normal, button, any, SGR 1006)
  render/
    font.macos.tach    Core Text: faces, metrics, fallback, rasterization
    font.linux.tach    FreeType + fontconfig
    atlas.tach         shelf packing into atlas pages (R8 coverage, RGBA8 colour)
    cells.wgsl         the one shader (vertex + fragment)
    renderer.tach      instance buffer ring, damage upload, uniforms, the one draw
  bench/               the headless benches and the latency probe (§5)
  oracle/              the Rust harness over alacritty_terminal (§4.2), with its own Cargo.toml
```

The parser, terminal and input modules are **pure**. They have no `io`
effect, and their only allocation is the grid's, from one allocator. They
are tested without a window or a GPU, and `query effects` proves it.

### 3.2 The parser

- **The state machine** is Williams' DEC/ANSI parser, as vte implements
  it:
  - states: ground, escape, escape intermediate, CSI entry, param,
    intermediate and ignore, DCS (same set plus passthrough), OSC string,
    SOS/PM/APC string;
  - transitions: a 256-entry byte-class table per state;
  - actions: print, execute, collect, param, esc/csi dispatch, hook, put,
    unhook, OSC start/put/end.
- **No allocation.**
  - Parameters: 32 values with colon sub-parameters, in fixed arrays.
  - Intermediates: two bytes.
  - OSC: a buffer with a 1 MiB limit, enough for OSC 52 clipboard
    payloads. Beyond the limit the string is dropped, not truncated.
- **The fast path.** In ground state, a run of printable ASCII is found
  by scanning and handed to `Perform::print_ascii(run: [u8])`, so the
  grid writes cells in bulk. The scan is scalar in 0.23.0 on 0.16-era
  code. From 0.19 it uses 16-byte NEON compares (`vcltq_u8`,
  `vcgtq_u8`, `vmaxvq_u8`; arch.md's byte-search recipe), with `has`
  picking the path.
- **Static dispatch.** `Perform` is a trait and `advance` is generic, so
  the terminal's handlers inline into the parser loop. There is no
  `dyn`.

### 3.3 The terminal state

**Cell: 16 bytes.** `struct Cell { ch: u32, fg: u32, bg: u32, flags:
u16, extra: u16 }`.
- `fg` and `bg` hold a tag (default, indexed 0–255, RGB) plus 24 bits.
- `flags` are: bold, dim, italic, underline (single, double, curly,
  dotted, dashed), strike, inverse, hidden, blink, wide, wide spacer,
  wrapped, has-extra.
- `extra` indexes a per-grid side table: combining characters, the
  underline colour, the OSC 8 hyperlink id.

Alacritty's `Cell` is 24 bytes. The difference is part of the memory goal
(§5).

**Grid.**
- The visible screen plus scrollback is a ring of rows of `cols` cells.
  Rows are allocated lazily as scrollback grows, up to the limit (10,000
  lines by default, as Alacritty's).
- Scrolling the whole screen moves the ring's head, with no copying.
  Scrolling a region shifts rows inside the region.
- Each row has a dirty flag and a dirty column range: that is the damage.

**Screen.**
- The primary and alternate grids. The alternate has no scrollback, and
  modes 47, 1047 and 1049 switch to it (1049 saves and restores the
  cursor).
- The cursor with its pending wrap, the saved cursor (DECSC/DECRC),
  scroll regions (DECSTBM), origin mode, autowrap, insert mode, tab
  stops, G0/G1 charsets with DEC special graphics.
- Synchronized updates (mode 2026): rendering is held until the end
  marker or 150 ms.

**The control functions are Alacritty's set.** The oracle (§4.2) defines
what "the same" means:
- cursor motion: CUU/CUD/CUF/CUB/CNL/CPL/CHA/CUP/HVP/VPA/HPA/REP;
- erasing: ED, EL, ECH, DCH, ICH, IL, DL, SU, SD, DECALN;
- SGR, with both `;` and `:` colour forms;
- modes: DECSET/DECRST 1, 6, 7, 12, 25, 1000, 1002, 1003, 1004, 1005,
  1006, 1007, 1042, 1049, 2004 and 2026;
- reports: DSR (5, 6), DA1 and DA2, DECRQM;
- DECSCUSR;
- OSC 0, 2, 4, 8, 10, 11, 12, 52, 104, 110–112.

Sixel and the kitty graphics protocol are out of scope. The kitty
keyboard protocol is O4.

**Wide and combining characters.**
- A wide character takes two cells: the second is a spacer flagged
  `wide spacer`. A wide character that does not fit at the last column
  wraps, as xterm's does.
- Combining marks attach to the previous cell's `extra`.
- Width comes from `term/width.tach`: a two-level table generated from
  Unicode 16's EastAsianWidth and emoji data by a script in
  examples/term/bench/. It is replaced by 0.20's `std::text` width
  function when that lands (§6.3).

**Reflow.** When the column count changes, rows joined by the `wrapped`
flag are treated as one logical line and re-wrapped into the new width.
The cursor keeps its logical position. The alternate screen is not
reflowed (it is truncated or padded), as in Alacritty. Reflow costs
O(scrollback), done once per resize event, coalesced to one per frame
during a drag.

**Selection** is kept in absolute row coordinates, so it survives
scrolling.
- Modes: cells (drag), words (double click; separators configurable,
  Alacritty's defaults), lines (triple click), block (Option-drag).
- Copy happens on Command-C, to the clipboard.
- Output that writes into the selected range clears the selection.

### 3.4 The pty

- **`forkpty` with the window size.** The child does only
  async-signal-safe work: `execve` of the shell, with an environment
  prepared before the fork (`TERM=xterm-256color`,
  `COLORTERM=truecolor`). By the time the terminal forks, Metal has
  started threads of its own, so the child must not allocate.
- **The shell** is `$SHELL`, else the passwd entry, else `/bin/sh`, run
  as a login shell (`-l`, the macOS convention).
- **The master fd is non-blocking.**
  - Reads take up to 64 KiB at a time.
  - Writes are queued and flushed when the fd is writable, so a large
    paste never blocks the UI.
  - A resize sends `TIOCSWINSZ`, and the kernel delivers `SIGWINCH` to
    the child.
  - On `SIGCHLD`, or a read returning 0, the shell has exited, and the
    window closes.
- **Before 0.21 (one thread):** `app.watch(master)` delivers
  `Readable`. The handler reads and parses until the read would block,
  or for 4 ms if a frame is due, then returns to the loop. Rendering is
  never starved by `cat` of a large file, and throughput stays high
  because parsing is the only work.
- **With 0.21:**
  - the I/O thread reads and parses into the terminal under a
    `Mutex<Term>`, as Alacritty's event loop does;
  - the main thread takes the lock only to copy damaged rows into the
    instance buffer, then requests a frame through `app.waker()`.

  The `Term` API is the same in both modes.

### 3.5 Rendering: fonts, one atlas, one instanced draw

**Fonts (Core Text on macOS).**
- `CTFontCreateWithName` for the regular face. Bold, italic and bold
  italic come from `CTFontCreateCopyWithSymbolicTraits`.
- Metrics: the cell is the advance of "0" by ascent + descent + leading,
  rounded to whole pixels at the backing scale, and the baseline and
  underline position come with them.
- Glyphs come from `CTFontGetGlyphsForCharacters`. A missing glyph is
  looked up with `CTFontCreateForString` (system fallback), and the
  result is cached per character.
- Rasterization goes into a grey `CGBitmapContext` sized from
  `CTFontGetBoundingRectsForGlyphs`, as in §1.2. Colour glyphs (Apple
  Color Emoji, `kCTFontColorGlyphsTrait`) go into an RGBA context.

**Fonts (Linux).** FreeType's `FT_Load_Glyph` with `FT_RENDER_MODE_NORMAL`
renders coverage, `FT_LOAD_COLOR` handles colour fonts, and fontconfig
matches faces and fallbacks.

**The atlas.** Pages of 2048×2048, R8 for coverage and RGBA8 for colour,
packed into shelves. A glyph's entry is its atlas rectangle and bearing,
in a storage buffer indexed by glyph id. Glyphs are rasterized on first
use: ASCII's 95 printable glyphs take under 5 ms. A page that fills up
starts another.

**The draw: one instanced draw per frame, with no blending.**
- **The instances.** There is one instance per cell, 16 bytes: `glyph:
  u32` (an atlas entry, 0 for none), `fg: u32`, `bg: u32`, `flags: u32`.
  The cell's row and column are not stored: the vertex shader derives
  them from `instance_index`, the ring's top row (a uniform) and `cols`.
- **One draw** of `rows × cols` instances, 4 vertices each, covers
  everything:
  - backgrounds, glyphs and decorations (underline styles, strike);
  - inverse;
  - the cursor (block, beam or underline, from a uniform);
  - the selection (a uniform range).

  Moving the cursor or dragging a selection changes no instance data.
- **The fragment shader** samples coverage and mixes `fg` over `bg`, so
  there is no blending and no overdraw.
- **Wide characters** draw their glyph's left half in the first cell's
  instance and the right half in the spacer's (a flag), so quads never
  overlap. A glyph that overhangs its cell, such as an italic, is
  clipped to the cell, as in many terminals.
- **Damage.** The instance buffer is a ring of row slots that mirrors the
  grid's ring. Only dirty rows are rewritten: one `memcpy` per row into
  shared memory on Apple silicon, with no staging.
  - A full-screen scroll moves the ring's head uniform and rewrites one
    row.
  - An unchanged frame is not drawn at all (§2.1, frames on request).
  - Three frames in flight, each with its own uniforms. The instance
    ring is double-buffered per frame in flight, on dirty rows only.
- **The shader is `cells.wgsl`,** translated by `std::gpu::wgsl` (0.22),
  so the terminal exercises the translator on both backends. Until G5
  lands, a hand-written MSL equivalent is used in render tests.
- **Presentation** uses `maximumDrawableCount = 2` and display sync on,
  for the lowest latency without tearing.

### 3.6 Input

- **Keys follow xterm's encoding:**
  - arrows and Home/End as `CSI` or `SS3`, by DECCKM;
  - modifiers as `CSI 1;m X`;
  - F1–F12;
  - keypad modes;
  - Backspace sends DEL;
  - Option as Meta (an `ESC` prefix) is configurable per side, because
    macOS's Option also composes characters;
  - Control with a letter sends C0, and Control with `@[\]^_` and space
    follows xterm.

  The tests are a table of (key, mods, modes) → bytes, checked against
  the oracle's encoder (§4.2).
- **Mouse reporting:**
  - modes 1000, 1002 and 1003;
  - encodings: default (X10, coordinates up to 223), 1006 (SGR) and 1005
    (UTF-8);
  - focus events with 1004;
  - the wheel as buttons 4 and 5, or as arrow keys on the alternate
    screen (1007).

  Shift bypasses reporting so the user can select.
- **Bracketed paste (2004)** wraps the text in `ESC[200~` and `ESC[201~`
  after removing every `ESC` and C1 byte from it, so pasted text cannot
  end the bracket. Without the mode, newlines become CR.
- **Copy** takes the selection's text, with trailing spaces trimmed per
  line and wrapped lines joined, to the clipboard.

## 4. Testing

### 4.1 What runs where

| what | Mac, headless | Mac with a display | container |
|---|---|---|---|
| parser, terminal state, reflow, selection, input encodings (unit and golden tests) | yes | | yes |
| differential parser fuzzing against the oracle (§4.2) | yes | | yes |
| pty: spawn `sh`, echo, resize, exit, large output, paste back-pressure | yes (a pty needs no display) | | yes |
| Core Text atlas: glyphs rasterized and compared with reference coverage (tolerance), fallback, emoji | yes | | |
| FreeType atlas | | | yes |
| renderer: a grid rendered to a texture through the gpu hal and compared with a reference image | yes (Metal, render to texture) | | yes (lavapipe) |
| `std::window` Cocoa: windows, events, IME, clipboard, display link | | yes, by hand or scripted with `CGEventPost` (needs Accessibility permission) | |
| `std::window` Wayland and X11, with surfaces and swapchains | | | yes: weston headless and Xvfb, events injected (X11's XTEST; weston's test protocol or a nested client) |
| the whole terminal, interactive | | yes | yes (Xvfb or weston: a smoke test that types `echo hi` and reads the grid back) |
| throughput, memory, frame time, latency against Alacritty | headless parts: §5 | yes: §5 | |

### 4.2 The oracle and the parser fuzzer

- **The oracle** is `examples/term/oracle/`, a Rust program (cargo is
  installed, 1.98) over the `alacritty_terminal` crate, pinned to the
  revision of the installed Alacritty (v0.17.0). It reads bytes and
  prints a canonical dump of the state:
  - every cell's character and combining marks, flags, and colours (as
    tag + value);
  - the cursor's position, shape and visibility, with the pending-wrap
    state;
  - the active screen, the scroll region, the modes;
  - the title, and the bytes the terminal wrote back (DSR and DA
    replies).
- **`term --headless --dump`** prints the same format from the tachyon
  terminal: the same size, the same scrollback, no window, no GPU.
- **The fuzzer** (tests/term-fuzz/run.sh) feeds both the same input and
  compares the dumps after each chunk. The input comes from:
  1. a generator over the grammar of the sequences §3.3 implements, with
     edge-case parameters (0, 1, maximum, missing, sub-parameters),
     split at random chunk boundaries (a parser bug's favourite place);
  2. mutations of a corpus of recorded sessions: `script -q` logs of
     vim, less, htop, git log with colour, man and tmux, recorded
     headless on the Mac;
  3. invalid UTF-8 and C1 controls.

  A difference is reduced by deleting bytes while it still differs. A
  difference that is deliberate (none are planned) is listed in
  `oracle/allowed.txt` with a reason. libvterm is a second opinion when
  Alacritty's behaviour looks wrong; it is not a gate.
- **The gate** runs 60 s on the Mac and in the container, the corpus
  replay in full, and a regression corpus of every reduced case.

## 5. Measured against Alacritty

Alacritty 0.17.0 is on this machine. Each measurement runs both
terminals with the same font (Menlo 14), the same window size (120×40
cells at 2× scale) and the same scrollback (10,000). Release builds:
tachyon -O2.

| measure | how | display? | goal |
|---|---|---|---|
| **parse and grid throughput** | `term-bench` (headless) against the oracle harness timing `alacritty_terminal` on the same files: 100 MB of ASCII, dense SGR colour, UTF-8 CJK, a scrolling-region workload (vtebench's set) | no | at least Alacritty's on every file; ASCII at memory speed after 0.19's scan |
| **`cat` throughput** | `time cat 100MB.txt` run as each terminal's command (`-e sh -c '...'`), the elapsed time written to a file; the same with vtebench (cargo-built) inside each terminal | yes | no slower than Alacritty |
| **memory** | `footprint` of each process: after start-up, with a full scrollback of 10,000 lines × 120 columns, and after a 100 MB `cat` | yes | at most Alacritty's at each point (16-byte cells against 24) |
| **frame time** | ours: CPU encode time per frame and GPU time (`GPUStartTime`/`GPUEndTime` on the command buffer) under vtebench's dense workload and a full-screen `htop`; Alacritty: the same workloads through the external probe's frame intervals | yes | encode under 0.5 ms for a full redraw of 120×40; frames never miss a 120 Hz deadline under `cat` |
| **input latency** | an external probe (examples/term/bench/latency, in tachyon): posts a key with `CGEventPost` and watches the window's pixels through ScreenCaptureKit (blocks built by `std::objc`, gpu.md §2.9) until the character appears, typometer's method, 200 samples per terminal; plus our internal key-to-present time (`MTLDrawable` presented time) | yes, and the probe needs **Accessibility and Screen Recording permissions, granted by the user once** | median and 99th percentile no worse than Alacritty |
| **idle CPU** | `top -l` sampling of an idle terminal with a blinking cursor off, then on | yes | 0% with the cursor steady; under 0.5% blinking |
| **start-up** | time from exec to the first frame presented (internal), and process start to window (probe) | yes | no slower than Alacritty (the pipeline cache, gpu.md §2.10) |

The headless row runs in the gate. The display rows run by hand before
the release and are recorded in examples/term/README.md with the machine
and both versions, as the algorithm examples record their C comparisons.
If the user has not granted the probe's permissions, the latency row
reports only our internal number and says so.

## 6. Phase 0, then the tasks

### 6.1 Dependencies

| needs | from | parts that wait |
|---|---|---|
| `std::objc`, objcgen, OS-specific files, std submodules, `include_str`, framework headers | 0.22 Phase 0 (start now) | W1 and the Core Text path wait for C4 only for convenience: hand-declared externs work today (§1.2) |
| the gpu hal, MSL writer | 0.22 G2, G5 (start now) | E5 tests its renderer with G2's hal directly and hand-written MSL until G5 lands |
| the gpu API, surfaces | 0.22 G8 | E7 (the assembled terminal) and examples on the public API |
| `Drop`, `&mut`, views | 0.17 | the final shapes: `App`, `Window`, `Term`, `Pty` owned with `Drop` (closing the fd and killing the child); `Perform` methods take `&mut self`; `Event` stays plain |
| contracts | 0.18 | `requires` on the grid's coordinate functions (`row < rows`) instead of `validate`; `#[property]` tests (reflow round-trips, selection invariants) |
| `std::arch` | 0.19 | the NEON fast path of the parser's scan (A19) |
| `std::text` (UTF-8, display width), `String`, collections, `std::process`/`fs` | 0.20 | `width.tach` replaced by std's; the config file read with std's I/O; the OSC buffer and clipboard on `String`/`Buf` as 0.20 defines them |
| threads, `Mutex`, atomics, a waker | 0.21 | the pty I/O thread (§3.4), `app.waker()`, shader compilation off the main thread |

**The start-now list is long.** The parser, the terminal state, the pty,
the Core Text and FreeType atlases, the input encoders, the oracle and
fuzzer, the headless benches, and all three window backends need nothing
from 0.17–0.21. Tasks that need 0.22 build on 0.22's start-now tasks as
those land, so the two releases' work runs in parallel today.

### 6.2 Phase 0 (start now; the lead, serial)

- **`compiler/std/window/mod.tach`**: `App`, `Window`, `WindowDesc`,
  `Event` and the key, mouse and IME types, the `trait Backend`, in the
  0.16 form (`self: *T`, `free`), with stub backends that return no
  events.
- **examples/term's skeleton:**
  - `vt::Perform` with its methods;
  - `term::Term`'s public functions (`new_in`, `resize`, `dump`,
    `damage`, `rows`, `cell`);
  - `render::Renderer`'s interface (`new`, `update(&term)`,
    `draw(&surface)`);
  - `pty::Pty` (`spawn`, `read`, `write`, `resize`);
  - the dump format, documented in examples/term/oracle/FORMAT.md.
- **The oracle harness** (examples/term/oracle/) building on the Mac and
  in the container, with one passing comparison.
- **tests/term-fuzz/run.sh, tests/examples/term-*.test** with their
  first cases, and **tests/window/run.sh** with
  `// NEEDS: display|xvfb|weston`.

### 6.3 Then, in parallel

Every task is **start now** unless marked.

| task | owns | provides | start |
|---|---|---|---|
| **W1 Cocoa** | compiler/std/window/cocoa.macos.tach, window/cocoa/*, objc/tables/{appkit,quartzcore}.objc | §2.2's macOS column: app setup without a bundle, runtime view class, events, `NSTextInputClient`, clipboard, cursor, display link, `CFFileDescriptor` watch, live-resize hook, `CAMetalLayer` | now (on G1's `std::objc`; display for tests) |
| **W2 Wayland** | window/linux.linux.tach (shared), window/wayland/*, wayland/proto/ (scanner output) | §2.2's Wayland column; tests under weston headless | now (container) |
| **W3 X11** | window/x11/* | §2.2's X11 column; tests under Xvfb with XTEST | now (container) |
| **E1 Parser** | examples/term/vt/* | §3.2: the table, parameters, UTF-8, the ASCII fast path; unit tests per state; no allocation (proven with `query effects`) | now |
| **E2 Terminal state** | examples/term/term/* | §3.3: cells, grid ring, damage, screen, every control function, alternate screen, wide and combining characters (generated table), reflow, selection | now; width from std after 0.20 |
| **E3 Pty** | examples/term/pty.tach | §3.4, the single-thread mode; tests with `sh` | now; the thread after 0.21 |
| **E4 Fonts and atlas** | examples/term/render/{font.macos,font.linux,atlas}.tach | §3.5's fonts and atlas: Core Text (hand-declared externs until C4, then `import`), FreeType + fontconfig in the container | now |
| **E5 Renderer** | examples/term/render/{renderer.tach,cells.wgsl} | §3.5's draw: instance ring, damage upload, uniforms, cursor and selection, offscreen golden images | now, on G2's hal with hand-written MSL; on `std::gpu` and `cells.wgsl` when G8 and G5 land |
| **E6 Input** | examples/term/input/* | §3.6's encoders as pure functions with their tables; selection-to-text; paste filtering | now; wiring with E7 |
| **E7 The terminal, assembled** | examples/term/main.tach, config, README | the event loop, config file (font, size, colours, Option-as-Meta), window ↔ term ↔ renderer ↔ pty, live resize, synchronized updates | **needs 0.22 G8 and W1**; the thread after 0.21 |
| **E8 Oracle and fuzzing** | examples/term/oracle/*, tests/term-fuzz/* | §4.2: the dump, the generator, the corpus (recorded sessions), reduction, the gate row | now |
| **E9 Measurement** | examples/term/bench/* | §5: `term-bench` headless against the oracle's timing (now); the latency probe (now, once W1's tables exist); the display runs (after E7) | now / after E7 |

**Where the tasks meet.**
- **E1 and E2** meet at `Perform`, fixed in Phase 0. E2 implements it,
  and E1's tests use a recording `Perform`.
- **E2 and E5** meet at the damage interface: `term.damage() -> rows`
  and `term.row(i) -> [Cell]`. E5 never reads the grid's internals.
- **E2 and E8** meet at the dump, which E8 owns: it is the oracle's
  format.
- **W1 and E7** meet at `std::window`'s API, fixed in Phase 0.
- **E4 and E5** meet at the atlas entry layout (rect, bearing, page).

**Merge order:**
1. Phase 0.
2. E1, E2 and E8: the parser and grid are correct against the oracle
   before anything draws.
3. E3, E6 and E4.
4. W1, W2 and W3, as each passes its tests.
5. E5.
6. E7, after 0.22's G8.
7. E9's display runs.
8. The README last.

**Time.** About three weeks in parallel, overlapping 0.22. E2 is the
largest (the control functions and reflow), and W1 is the riskiest
(AppKit without Xcode, IME).

### 6.4 Adapting the start-now code

| step | when | how |
|---|---|---|
| **A17 values** | after 0.17.0 | `fix --values` on compiler/std/window and examples/term; `impl Drop` for `App`, `Window` (close, release), `Pty` (close the fd, `SIGHUP` the child), `Term`, the atlas; `Perform` methods take `&mut self`; the live-resize hook takes a `&mut` closure |
| **A18 contracts** | after 0.18.0 | leading `validate` statements become `requires`; `#[property]` tests: reflow to a width and back is identity on logical lines; a selection's text is a substring of the dump; parser chunking does not change the dump |
| **A19 SIMD** | after 0.19.0 | the parser's printable-run scan on NEON with a scalar fallback, under `has`; the bench shows the gain |
| **A20 std text and I/O** | after 0.20.0 | `width.tach` deleted for `std::text`'s width; the config read with `std::fs`; the shell path with `std::env`; `String` where 0.20 places it |
| **A21 threads** | after 0.21.0 | the pty I/O thread with `Mutex<Term>` and `app.waker()` (§3.4); the latency and throughput rows measured again in both modes, keeping the faster as the default |

## 7. Alternatives considered

- **winit's push model** (`run_app` with a handler). It is the de facto
  Rust design, but it needs a long-lived closure owning the program's
  state, and on macOS it gains only live resize, which one hook covers.
  Rejected for the pull loop (§2.1).
- **Two draws per frame** (backgrounds, then blended glyphs), as
  Alacritty does. That is simpler with overhanging glyphs, but it costs
  twice the vertex work, blending and overdraw. Rejected: one draw,
  glyphs clipped to their cell, wide glyphs split across their two
  cells.
- **Parsing on the main thread after 0.21** (the I/O thread only reads).
  It needs no lock, but a large `cat` competes with rendering on one
  core. Rejected for Alacritty's model. Both modes exist until 0.21,
  and A21 measures them.
- **libvterm as the oracle.** It is a C library in the container, but
  the comparison target is Alacritty, and agreeing with Alacritty is the
  measurable claim. Kept as a second opinion only.
- **HarfBuzz shaping and ligatures.** Alacritty has none either. Out of
  scope.
- **A compressed scrollback** (trailing blanks trimmed, rows
  run-length-encoded). It saves memory on typical output, but costs
  complexity in reflow and selection. *Proposed* as O2, if the memory
  row shows a need.

## 8. Risks

| # | risk | mitigation |
|---|---|---|
| R1 | **AppKit without a bundle, nib or Xcode:** activation, menus, focus and IME are fussy, and mistakes are silent | objcgen-checked prototypes (gpu.md R1); a minimal app in examples/window first; Apple's documented bundle-less setup; IME tested with the Japanese input source by hand |
| R2 | **Live resize** (AppKit's nested loop) | the one redraw hook (§2.1), tested by scripted resize drags with `CGEventPost` |
| R3 | **Off-main-thread callbacks before 0.21** (display link, Metal) | the main-thread `CADisplayLink`; no completion handlers (gpu.md §2.11) |
| R4 | **`fork` after Metal has started threads** | the child does only async-signal-safe work, with an environment built before the fork |
| R5 | **The oracle's version drifts from the installed Alacritty** | pinned by git tag; the version is printed in every bench report |
| R6 | **The display measurements need the user's permissions** | headless rows in the gate; internal timings always; the probe asks for the permissions once and records when it lacks them |
| R7 | **The Unicode width table differs between terminals** | the oracle compares widths, and the table is generated from the same Unicode version as `alacritty_terminal`'s `unicode-width` crate, then 0.20's |
| R8 | **Wayland without server-side decorations** (GNOME) | 0.23.0 documents it; client-side decorations are O3 |

## 9. Open questions

- **O1. Kitty keyboard protocol and OSC 133 (shell integration).**
  Alacritty supports the keyboard protocol. *Proposed:* 0.23.x, after
  the core matches.
- **O2. Compressed scrollback.** *Proposed:* only if the memory
  measurement shows a need.
- **O3. Client-side decorations on Wayland.** *Proposed:* 0.23.x, simple
  title bar drawn by the terminal itself.
- **O4. A `std::term` library** (the parser and grid as std, for TUI
  programs and tests). *Proposed:* after 0.23, if the "Toward 1.0" review
  wants it; the example's modules are already separable.
- **O5. text-input-v3 and fractional scaling on Wayland.** *Proposed:*
  0.23.x.

### Critical files for implementation

- compiler/std/objc/ and objcgen (0.22 G1): AppKit's tables and
  `ClassBuilder`.
- compiler/std/gpu/ (0.22): `RawSurface`, `Surface`, the hal for
  render-to-texture tests.
- New: compiler/std/window/ (mod.tach, cocoa.macos.tach, cocoa/,
  linux.linux.tach, wayland/, x11/), examples/term/ (§3.1),
  tests/term-fuzz/, tests/window/, tests/examples/term-*.test,
  compiler/guide/window.md.
- compiler/src/front/cpp/directives.tach (C4: framework headers for Core
  Text) and back/objfile/output.tach (`-framework`).

## Decisions taken (for the user's review)

All taken as recommended on 2026-10-16, under the standing instruction to
work autonomously through 0.23. Each can be revisited.

**std::window**
- D1. **Events are pulled** (`app.wait()`), with one live-resize redraw
  hook on macOS. This is not winit's push model.
- D2. **Frames on request** (`request_frame`, then `Event::Frame` at the
  next refresh): `CADisplayLink` on the main run loop (macOS 14 is the
  floor), `wl_surface.frame` on Wayland. An idle application wakes up
  never.
- D3. **Watched fds** (`app.watch(fd)`) serve I/O on the main thread
  before 0.21; `app.waker()` comes with 0.21.
- D4. **Text events are plain, with inline bytes**: no allocation per
  key.
- D5. **Cocoa through `std::objc`'s generated, runtime-checked
  bindings**; Wayland via libwayland with checked-in scanner output and
  xkbcommon; X11 via xcb and xkbcommon-x11. All three are in 0.23.0, and
  a late Linux backend moves to 0.23.x instead of holding the release.
- D6. **Backends are OS-specific files** behind `trait
  window::Backend`, as in 0.22.

**The terminal**
- D7. **vte's state machine,** with no allocation in the parser and a
  bulk path for printable ASCII (NEON from 0.19).
- D8. **16-byte cells,** a lazily allocated ring of rows with 10,000
  lines of scrollback, per-row damage.
- D9. **Alacritty's set of control functions** and its reflow behaviour;
  no sixel, no kitty graphics; the kitty keyboard protocol later.
- D10. **One instanced draw per frame:** one 16-byte instance per cell,
  positions from `instance_index`, cursor and selection in uniforms, no
  blending; wide glyphs split across their cells, overhangs clipped; an
  instance ring that mirrors the grid, so scrolling rewrites one row;
  no frame when nothing changed.
- D11. **Glyphs from Core Text** (FreeType + fontconfig on Linux) into
  R8 and RGBA8 atlas pages; system fallback; colour emoji in 0.23.0.
- D12. **The pty:** `forkpty`, an async-signal-safe child, a
  non-blocking master; one thread with a 4 ms parse budget before 0.21,
  an I/O thread parsing under `Mutex<Term>` after.
- D13. **The oracle is `alacritty_terminal`** at the installed release's
  tag, through a Rust dump harness; a differential fuzzer (grammar,
  recorded sessions, invalid input) in every gate.
- D14. **Measurement against Alacritty** on parse throughput (headless,
  gated), `cat` throughput, memory, frame time, latency (typometer's
  method, needing the user's permissions once), idle CPU and start-up;
  the display rows by hand before release.
- D15. **Everything starts now** except the assembled terminal (E7: 0.22's
  API), the migrations (A17–A21) and the I/O thread (0.21).
