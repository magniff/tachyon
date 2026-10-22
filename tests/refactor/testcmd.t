## `volec test` (0.17): a program's cases are tests/NAME.in (stdin)
## with tests/NAME.out (the expected stdout) and NAME.exit (the status);
## the summary's first line has the counts, then each failure, briefly.
$ test --timeout 1
test main.vl: 2 passed, 3 failed (5 cases; -O0 and -O2 agree)
FAIL bad: stdout differs at line 2 (3 lines expected, 3 printed)
  - line 2: B
  - line 3: c
  + line 2: b
  + line 3: c
FAIL crash: exit 3 (expected 0)
FAIL hang: no exit after 1 s (--timeout S): stopped by signal 14 (SIGALRM: a time limit)
  trace: main.vl:12 main
(outputs: .volec/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
## filters: cases whose name contains one of them
$ test ok exit
test main.vl: 2 passed (2 cases; -O0 and -O2 agree)
## a budget (tokens): the failures that fit, then the rest by name
$ test --budget 20 --timeout 1
test main.vl: 2 passed, 3 failed (5 cases; -O0 and -O2 agree)
FAIL bad: stdout differs at line 2 (3 lines expected, 3 printed)
  - line 2: B
  - line 3: c
  + line 2: b
  + line 3: c
(2 more failing: crash, hang; all of them: volec test --timeout 1 --full)
(outputs: .volec/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
## --full: every failure, longer differences
$ test bad --full
test main.vl: 0 passed, 1 failed (1 case; -O0 and -O2 agree)
FAIL bad: stdout differs at line 2 (3 lines expected, 3 printed)
  - line 2: B
  - line 3: c
  + line 2: b
  + line 3: c
(outputs: .volec/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
% cat .volec/test/O2/case-bad.got
line 1: a
line 2: b
line 3: c
## one run on an input file, or stdin
$ test --input tests/ok.in
test main.vl: ran on tests/ok.in: exit 0, 3 lines of output
line 1: a
line 2: b
line 3: c
% printf 'x\n' | "$COMPILER" test --input -
test main.vl: ran on -: exit 0, 1 line of output
line 1: x
## the program is built again when a source changes
% printf 'use std::println;\n\nfn main() -> i32 {\n    println("x");\n    0\n}\n' > main.vl
$ test ok
test main.vl: 0 passed, 1 failed (1 case; -O0 and -O2 agree)
FAIL ok: stdout differs at line 1 (3 lines expected, 1 printed)
  - line 1: a
  - line 2: b
  + x
(outputs: .volec/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
## mistakes
$ test zzz
error test.no-root: no case in tests/ matches the filters
try: volec test main.vl
[exit 2]
$ test --bogus
error test.usage: unknown option '--bogus'; usage: volec test [FILTER...] [ROOT.vl] [--dir DIR] [--input FILE] [--budget N] [--full] [--timeout S] [-O N] [--no-trace] [--against VOLEC] [--accept] [--cases N] [--seed S] [--no-contracts] [--no-check-alloc]
[exit 2]
$ test --budget lots
error test.usage: --budget takes a number of tokens, not 'lots'; usage: volec test [FILTER...] [ROOT.vl] [--dir DIR] [--input FILE] [--budget N] [--full] [--timeout S] [-O N] [--no-trace] [--against VOLEC] [--accept] [--cases N] [--seed S] [--no-contracts] [--no-check-alloc]
[exit 2]
$ test missing.vl
error test.no-root: no file 'missing.vl'
[exit 2]
% rm -r tests
$ test
test main.vl: builds; no tests in tests/ (a case: NAME.in, its stdin, and NAME.out, the expected stdout; a #[test] fn in the program; --input FILE: one run)
% printf 'fn main() {\n    let x: i64 = "s";\n}\n' > main.vl
$ test
test main.vl: does not build (1 error)
main.vl:2:18: error[type error] expected 'i64', got '[u8]'
[exit 1]
