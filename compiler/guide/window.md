# Windows: std::window (0.23)

`std::window` opens windows and reads their input, winit's objects with
events pulled rather than pushed. 0.23.0 runs on macOS (Cocoa); Wayland
and X11 come in 0.23.1 behind the same API.

```text
use std::window::{App, Event, WindowDesc};

fn main(gpa: Gpa) -> i32 {
    var app = App::new_in(gpa).unwrap();              // Err(NoDisplay) under ssh
    let desc = WindowDesc::new("demo", 800, 600);     // logical points
    var win = app.window(desc).unwrap();
    win.request_frame();
    loop {
        match app.wait().unwrap() {                   // blocks; nothing busy-waits
            Event::Frame(_) => draw(win),             // once per request_frame
            Event::Key(k) => if k.pressed && !k.ime { on_key(k) },
            Event::Text(t) => typed(t.bytes[0..t.len as i64]),  // UTF-8, inline
            Event::Resize(_, s) => resize(s.w, s.h, s.scale),   // physical pixels
            Event::Readable(fd) => read_more(fd),     // a watched fd (app.watch)
            Event::Close(_) | Event::Quit => break,
            _ => {}
        }
    }
    0                                                 // win, then app, dropped
}
```

- **Events**: `Frame`, `Key` (physical `KeyCode`, logical `Logical`,
  `Mods` with left and right, `repeat`, `ime`, `text_follows`), `Text`,
  `Preedit` (`app.preedit()` is the composition), `Resize` (physical
  pixels and the scale), `Mouse` (press, release, move; pixels from the
  top-left; `clicks`), `Scroll` (`precise`: pixels, else lines),
  `Cursor` (enter, leave), `Focus`, `Readable`, `Close`, `Quit`.
- **Calls**: `app.wait()`, `poll()`, `wait_timeout(ms)`; `app.watch(fd)`;
  `app.clipboard_get_in(gpa)`, `clipboard_set(text)`;
  `app.on_live_resize(f, ctx)` (`ctx` a raw `*u8`; macOS runs its own loop while a window
  edge is dragged: `f` is called there and may `poll` and draw).
  `win.request_frame()`, `size()`, `raw_surface()` (the CAMetalLayer),
  `set_title`, `set_cursor`, `hide_cursor_while_typing`,
  `set_ime_area(x, y, w, h)`, `set_fullscreen`, `focused`, `close`.
- **Keys and text**: a key that types something is a `Key` with
  `text_follows`, then a `Text`. Encode keys that do not (arrows, Return,
  Control-letters); send `Text` as it is. `ime` marks keys an input
  method took.
- **Linking** (until tachyonc takes `-framework`): link AppKit,
  QuartzCore, Metal, CoreText, CoreGraphics, CoreFoundation and libobjc,
  e.g. with `tests/window/frameworks.c` on the command line
  (`tachyonc main.tach tests/window/frameworks.c -o app`).
- **Tests**: `tests/window/run.sh`; the checks that need a display skip
  without one (`TACHYON_NO_DISPLAY_TESTS=1` too).
