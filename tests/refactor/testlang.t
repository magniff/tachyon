## Tests in the language (0.18): #[test] functions (taking nothing or
## `gpa: Gpa`, returning () or a Result), #[property] functions (values
## generated from their parameters' types, a failure shrunk), functions
## with an `ensures` (tested as properties), snapshots; each at -O0 and
## -O2, built with --trace and --check-alloc (a test that leaks fails).
## The summary first, then one line per failure (and its trace, input,
## try:).
$ test --timeout 5
test main.tach: 7 passed, 4 failed, 1 new snapshot (1 case, 5 #[test], 4 #[property], 1 contract; -O0 and -O2 agree)
FAIL gap_needs_two: checks.tach:14:8: index out of bounds: index 1, length 1
  trace: checks.tach:14 checks::gap_needs_two
FAIL keeps_a_buffer: check-alloc: 1 block of Gpa not freed (14 bytes): block #2 (14 bytes), allocated at ./checks.tach:22:5
FAIL bubble_sorts (property, case 11 of 100, shrunk in 8 steps): not sorted
  input: v = [1, 0]
  try: tachyonc test bubble_sorts --seed 0xf788dd27897d1fed main.tach
FAIL forgets_its_input (property, case 4 of 100, shrunk in 1 step): check-alloc: 1 block of Gpa not freed by the case (32 bytes): block #11 (32 bytes), allocated at <test>:106:21
  input: v = [0]
  try: tachyonc test forgets_its_input --seed 0xaf47b961b6c073b main.tach
(outputs: .tachyonc/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
## a property's failure again, from its seed
$ test bubble_sorts --seed 0xf788dd27897d1fed
test main.tach: 0 passed, 1 failed (1 #[property]; -O0 and -O2 agree)
FAIL bubble_sorts (property, case 11 of 100, shrunk in 8 steps): not sorted
  input: v = [1, 0]
  try: tachyonc test bubble_sorts --seed 0xf788dd27897d1fed main.tach
(outputs: .tachyonc/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
## a snapshot that changed fails with its first differing line; --accept
## writes it
% printf 'Range { lo: 0, hi: 9 }\n' > tests/snapshots/checks__span_snapshot__1.snap
$ test span
test main.tach: 0 passed, 1 failed (1 #[test]; -O0 and -O2 agree)
FAIL span_snapshot: snapshot differs: tests/snapshots/checks__span_snapshot__1.snap line 1: 'Range { lo: 0, hi: 9 }' expected, got 'Range { lo: -2, hi: 9 }'
  try: tachyonc test span_snapshot --accept main.tach
(outputs: .tachyonc/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
$ test span --accept
test main.tach: 1 passed (1 #[test]; -O0 and -O2 agree)
% cat tests/snapshots/checks__span_snapshot__1.snap
Range { lo: -2, hi: 9 }
$ test span
test main.tach: 1 passed (1 #[test]; -O0 and -O2 agree)
## one level only
$ test -O 2 gap_of
test main.tach: 1 passed (1 #[test]; -O2 only)
## the program built without its tests (a #[cfg(test)] module is left out)
% "$COMPILER" main.tach -o prog && ./prog < tests/gaps.in
5 12345
## the levels must agree: a difference is the compiler's bug (here a
## test-only switch makes -O2 read the literal 12345 as 12346)
% TACHYON_PLANT_MISCOMPILE=1 "$COMPILER" test gaps
test main.tach: 0 passed, 1 failed (1 case; -O0 and -O2 differ on 1)
FAIL gaps: stdout differs at line 1 (1 line expected, 1 printed)
  - 5 12345
  + 5 12346
DIFF gaps: -O0 and -O2 differ at stdout line 1: '5 12345' against '5 12346'. A compiler bug, not this program's
  try: tachyonc reduce main.tach --differs --input tests/gaps.in
(outputs: .tachyonc/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
## a test module sees its parent's items: `use super::*` is not needed
## (and wildcard imports are not allowed)
% printf 'use super::*;\n' > extra.tach && cat checks.tach >> extra.tach && mv extra.tach checks.tach
$ check
checks.tach:1:1: error[import.wildcard] wildcard imports are not allowed: 'use super::*;' is not needed | help: a #[cfg(test)] module sees its parent's items, private ones too, without an import | try: tachyonc edit patch checks.tach:1 --old 'use super::*;' --new '' main.tach
[exit 1]
$ edit patch checks.tach:1 --old 'use super::*;' --new ''
patched checks.tach:1	checks.tach	+0 -1 lines
$ check
## a #[test] takes nothing or `gpa: Gpa`
% printf '#[test]\nfn takes(n: i64) {\n}\n' > checks.tach
$ test
test main.tach: its tests do not build (1 error)
checks.tach:2:4: error[test.signature] 'takes' is a #[test] with parameters: a #[test] takes nothing or `gpa: Gpa` | help: a function of generated arguments is ...
[exit 1]
## a property's parameters must be generable
% printf '#[property]\nfn takes(p: *i64) {\n}\n' > checks.tach
$ test
test main.tach: its tests do not build (1 error)
checks.tach:2:10: error[test.generate] no generator for '*i64' (a pointer), parameter 'p' of 'takes' | help: parameters are generated from their types: numbers,...
[exit 1]
