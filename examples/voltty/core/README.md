# voltty/core: a terminal's core, headless

The parser, the terminal state, the input encoders and the pty of
voltty, the terminal emulator of vole 0.23 (docs/design/terminal.md;
the window and the renderer are std::window's and std::gpu's, elsewhere).
It behaves as Alacritty does: a Rust harness over `alacritty_terminal`
0.26.0, the crate Alacritty 0.17.0 is built on, is its oracle, and a
differential fuzzer holds the two to the same state, byte for byte.

Build it from the root of the repository:

```sh
target/volec -O2 examples/voltty/core/main.vl -o voltty
printf 'hi \033[1;31mthere\033[0m\r\n' | ./voltty --dump 4 20 100   # the state
./voltty --run 24 80 -- ls -l /                  # a program on a pty, then the screen
printf 'key Up shift\n' | ./voltty --keys       # what a key sends: \x1b[1;2A
examples/voltty/core/bench/run.sh                # against alacritty_terminal (cargo)
tests/voltty/run.sh                              # against the oracle (cargo)
```

## The parts

| file | what |
|---|---|
| vt/ | the escape-sequence parser: vte 0.15's state machine (Paul Williams' DEC parser), `Perform` statically dispatched; printable ASCII and runs of UTF-8 handed over in bulk; no allocation in `advance` |
| term/mod.vl | the terminal: two grids, modes, tab stops, the scroll region, charsets, colours, title; `feed` with synchronized updates (2026) as vte holds them |
| term/ops.vl | the control functions: Alacritty's set of CSI, ESC and OSC sequences, quirks included |
| term/grid.vl | the ring of rows: Alacritty's `Storage` step by step, 16-byte cells (Alacritty's are 24), 10,000 lines of scrollback allocated as they fill |
| term/reflow.vl | resize: wrapped lines re-wrapped, the cursor kept on its character; the alternate screen cut, not reflowed |
| term/extra.vl | combining characters, underline colours and hyperlinks of cells, in a side table collected by mark and sweep |
| term/dump.vl | the state as text (oracle/FORMAT.md) |
| input/ | keys with modifiers, the keypad, mouse reporting (X10, SGR, UTF-8), the wheel, bracketed paste, focus events |
| pty.vl | a child program on a pseudo-terminal through std::sys: a fork that does only async-signal-safe work, a non-blocking controller, queued writes |
| oracle/ | the Rust harness over alacritty_terminal (dump, script, bench, width table); allowed.txt lists the deliberate differences |
| bench/ | the workloads and the benchmark against alacritty_terminal |

Display width is std::unicode's (Unicode 18): oracle/allowed.txt notes
where it differs from the older tables of alacritty_terminal.

## Throughput

`bench/run.sh`: the same bytes through each, in 64 KiB chunks, to a
120x40 terminal with 10,000 lines of scrollback, the two in turns, the
best of five rounds, on a busy Apple-silicon Mac (load average 31). The
ratio is voltty's throughput over alacritty_terminal's: above 1, voltty
is faster.

| workload | voltty | alacritty_terminal | ratio |
|---|---|---|---|
| ascii (cat of a text) | 386 MiB/s | 149 MiB/s | 2.59x |
| sgr (every cell coloured) | 396 MiB/s | 305 MiB/s | 1.30x |
| cjk (wide characters, combining marks) | 232 MiB/s | 144 MiB/s | 1.61x |
| region (scrolling in a region) | 376 MiB/s | 138 MiB/s | 2.72x |
| motion (cursor moves) | 316 MiB/s | 239 MiB/s | 1.32x |

## Alacritty's quirks, kept

The oracle defines "the same", so voltty does what Alacritty does where
it surprises: modes 47 and 1047 are not the alternate screen (only 1049
is); a row reset clears only the cells written since its last reset
unless its last cell's background differs; a UTF-8 character cut by a
read boundary loses the valid bytes after it when an invalid one follows
within four; `ED 1` on line 1 leaves line 0; CHA in origin mode adds the
region's top twice; the DA2 version is Alacritty's (2600). The design's
departures are listed in oracle/allowed.txt.
