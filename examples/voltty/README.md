# voltty

The terminal emulator of vole 0.23 (docs/design/terminal.md),
measured against Alacritty. One folder per part:

| part | what |
|---|---|
| [core](core/) | the parser, the terminal state, scrollback and reflow, the input encoders, the pty; headless, checked against alacritty_terminal |
| render/ | Core Text glyphs in an atlas, and the renderer: one instanced draw of 16-byte cells per frame on std::gpu, its shader `cells.wgsl` compiled by std::gpu::wgsl; damage tracking (tests/voltty-render) |
| app/ | the parts assembled: a std::window window, the renderer on its surface, the terminal, a shell on a pty, one event loop (a first cut of E7: no selection, scrollback view or config yet) |

```sh
target/volec -O2 examples/voltty/app/main.vl tests/window/frameworks.c -l objc -o voltty
./voltty                      # your shell in a window
./voltty -- htop              # a program instead
```

app/'s other modules are links to core/ and render/ (a program's
modules sit under its root).

## The renderer on std::gpu

tests/voltty-render/run.sh -v (120x40 cells of Menlo 14 at 2x, the
median of 190 frames, the median of six runs taken in turns on a busy
Apple-silicon Mac), the Metal stand-in it replaced against std::gpu:

| frame | Metal stand-in | std::gpu |
|---|---|---|
| full redraw, CPU (update, encode, submit) | 41 us | 43 us |
| one-line scroll, CPU | 14 us | 15 us |
| full redraw to the GPU's end | 1219 us | 1234 us |
| 5510 CJK glyphs into the atlas | 82 ms | 80 ms |
| allocations per frame | 0 | 0 |
