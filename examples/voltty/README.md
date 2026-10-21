# voltty

The terminal emulator of tachyon 0.23 (docs/design/terminal.md),
measured against Alacritty. One folder per part:

| part | what |
|---|---|
| [core](core/) | the parser, the terminal state, scrollback and reflow, the input encoders, the pty; headless, checked against alacritty_terminal |

The window, the fonts and the renderer join it on std::window and
std::gpu.
