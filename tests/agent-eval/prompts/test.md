## Testing

`volec test` builds and tests in one command and prints a summary
first: for a program, `volec test main.vl` builds it and runs every
`tests/NAME.in` against `tests/NAME.out` (`N passed, M failed; first
failure: NAME (line 3: expected "x", got "y")`; `--full` for every
failure); with no `tests/` directory it builds and runs the program on
`--input FILE`. Put your own cases in `tests/` and run it instead of
`./prog < input` and `diff`. After an edit that checks clean, the hook
also runs the tests and adds their summary line.
