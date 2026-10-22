# The dump format and the script format

`voltty --dump` and `voltty-oracle dump` print a terminal's state in the
same text format; `voltty --script` and `voltty-oracle script` run the
same scripts. Two terminals are the same when their dumps are equal,
byte for byte: that is what tests/voltty/run.sh checks.

## The script

Lines of text, and raw bytes after `D`:

| line | meaning |
|---|---|
| `T LINES COLS HISTORY` | a new terminal (the previous one is dropped) |
| `D N` | the next N bytes (after the newline) are the program's output; a newline follows them |
| `R LINES COLS` | resize (with reflow); a synchronized update is ended first |
| `P` | print a dump; a synchronized update (mode 2026) is ended first |

## The dump

```text
size LINES COLS
cursor LINE COL WRAP                 WRAP: 1 when the next character wraps first
style SHAPE BLINK                    block, underline, beam, hollow, hidden
mode HEX                             Alacritty's TermMode bits
title TEXT | title -                 the last title reported to the window
tmpl ATTRS                           the cursor's template (what is written next)
charsets XXXX                        G0..G3: a ASCII, g DEC special graphics
saved LINE COL WRAP ATTRS XXXX       the saved cursor (DECSC)
color INDEX #RRGGBB                  each colour set by OSC 4, 10, 11, 12
reply BYTES                          what the terminal sent back since the last dump
clip c|s BYTES                       each OSC 52 store since the last dump
history N                            lines of scrollback
row LINE TEXT                        each line, from -N (the oldest) to LINES-1
attr LINE FROM-TO ATTRS              runs of cells whose attributes are not the default's
end
```

- ATTRS is `FG BG FLAGS UL LINK`: colours as `nN` (Alacritty's named
  colours: 0..15, 256 foreground, 257 background, ...), `iN` (indexed,
  `38;5;N`) or `#rrggbb`; FLAGS Alacritty's cell flags in hex (0x10 is
  WRAPLINE, 0x20 WIDE_CHAR, 0x40 its spacer, 0x400 a leading spacer); UL
  the underline colour or `-`; LINK `-` or `ID|URI`, ID `*` when made up.
  The default is `n256 n257 0 - -`.
- TEXT: each cell's character, printable ASCII as itself (`\` as
  `\u{5c}`), U+00A0 and up as UTF-8, the rest `\u{X}`; its combining
  characters after it as `\+{X}`; trailing blank default cells left out.
- BYTES: printable ASCII as itself, the rest `\xNN`.
- Colour queries (OSC 4/10/11/12 `?`) are answered after each `D` (as
  Alacritty's window answers them after a batch), with the colours set,
  else a fixed palette (`default_color` in term/mod.vl).
