## `tachyonc test` (0.17): a program's cases are tests/NAME.in (stdin)
## with tests/NAME.out (the expected stdout) and NAME.exit (the status);
## the summary's first line has the counts, then each failure, briefly.
$ test --timeout 1
test main.tach: 2 passed, 3 failed (tests/)
FAIL bad: stdout differs at line 2 (3 lines expected, 3 printed)
  - line 2: B
  - line 3: c
  + line 2: b
  + line 3: c
FAIL crash: exit 3 (expected 0)
FAIL hang: no exit after 1 s (--timeout S)
(outputs: .tachyonc/test/NAME.got, NAME.err)
[exit 1]
## filters: cases whose name contains one of them
$ test ok exit
test main.tach: 2 passed (tests/)
## a budget (tokens): the failures that fit, then the rest by name
$ test --budget 20 --timeout 1
test main.tach: 2 passed, 3 failed (tests/)
FAIL bad: stdout differs at line 2 (3 lines expected, 3 printed)
  - line 2: B
  - line 3: c
  + line 2: b
  + line 3: c
(2 more failing: crash, hang; all of them: tachyonc test --timeout 1 --full)
(outputs: .tachyonc/test/NAME.got, NAME.err)
[exit 1]
## --full: every failure, longer differences
$ test bad --full
test main.tach: 0 passed, 1 failed (tests/)
FAIL bad: stdout differs at line 2 (3 lines expected, 3 printed)
  - line 2: B
  - line 3: c
  + line 2: b
  + line 3: c
(outputs: .tachyonc/test/NAME.got, NAME.err)
[exit 1]
% cat .tachyonc/test/bad.got
line 1: a
line 2: b
line 3: c
## one run on an input file, or stdin
$ test --input tests/ok.in
test main.tach: ran on tests/ok.in: exit 0, 3 lines of output
line 1: a
line 2: b
line 3: c
% printf 'x\n' | "$COMPILER" test --input -
test main.tach: ran on -: exit 0, 1 line of output
line 1: x
## the program is built again when a source changes
% printf 'use std::println;\n\nfn main() -> i32 {\n    println("x");\n    0\n}\n' > main.tach
$ test ok
test main.tach: 0 passed, 1 failed (tests/)
FAIL ok: stdout differs at line 1 (3 lines expected, 1 printed)
  - line 1: a
  - line 2: b
  + x
(outputs: .tachyonc/test/NAME.got, NAME.err)
[exit 1]
## mistakes
$ test zzz
error test.no-root: no case in tests/ matches the filters
try: tachyonc test main.tach
[exit 2]
$ test --bogus
error test.usage: unknown option '--bogus'; usage: tachyonc test [FILTER...] [ROOT.tach] [--dir DIR] [--input FILE] [--budget N] [--full] [--timeout S] [-O N]
[exit 2]
$ test --budget lots
error test.usage: --budget takes a number of tokens, not 'lots'; usage: tachyonc test [FILTER...] [ROOT.tach] [--dir DIR] [--input FILE] [--budget N] [--full] [--timeout S] [-O N]
[exit 2]
$ test missing.tach
error test.no-root: no file 'missing.tach'
[exit 2]
% rm -r tests
$ test
test main.tach: builds; no tests in tests/ (a case: NAME.in, its stdin, and NAME.out, the expected stdout; --input FILE: one run)
% printf 'fn main() {\n    let x: i64 = "s";\n}\n' > main.tach
$ test
test main.tach: does not build (1 error)
main.tach:2:18: error[type error] expected 'i64', got '[u8]'
[exit 1]
