## `volec fuzz NAME` (0.18): a #[fuzz] function run on inputs it
## mutates, built with --coverage: an input that reaches new code is kept.
## Here a crash behind the 4-byte magic "FUZZ", found by the coverage of
## its four comparisons, shrunk and saved.
$ fuzz parse_never_crashes --time 120
FAIL parse_never_crashes (fuzz, after 16001 runs, shrunk in 2 steps): main.vl:9:28: index out of bounds: index 4, length 2
  input: data = "FUZZ"
  saved: .volec/fuzz/parse_never_crashes/crash-c6d0a3857a0d9820 (volec test replays it; test --accept keeps it in tests/fuzz/parse_never_crashes/)
  try: volec test parse_never_crashes main.vl
[exit 1]
% ls .volec/fuzz/parse_never_crashes | grep crash
crash-c6d0a3857a0d9820
## `volec test` replays the saved crash; --accept keeps it in tests/fuzz/
$ test
test main.vl: 0 passed, 1 failed (1 #[fuzz] target; -O0 and -O2 agree)
FAIL parse_never_crashes (fuzz, input .volec/fuzz/parse_never_crashes/crash-c6d0a3857a0d9820): main.vl:9:28: index out of bounds: index 4, length 2
  trace: main.vl:9 parse < main.vl:24 parse_never_crashes
  input: data = "FUZZ"
(outputs: .volec/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
$ test --accept
test main.vl: 0 passed, 1 failed (1 #[fuzz] target; -O0 and -O2 agree)
FAIL parse_never_crashes (fuzz, input tests/fuzz/parse_never_crashes/crash-c6d0a3857a0d9820): main.vl:9:28: index out of bounds: index 4, length 2
  trace: main.vl:9 parse < main.vl:24 parse_never_crashes
  input: data = "FUZZ"
(outputs: .volec/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
% ls tests/fuzz/parse_never_crashes
crash-c6d0a3857a0d9820
## mistakes
$ fuzz nope
error fuzz.unknown: no #[fuzz] or #[property] function 'nope' in main.vl; its targets: parse_never_crashes
try: volec fuzz parse_never_crashes main.vl
[exit 2]
$ fuzz
error fuzz.usage: the #[fuzz] function to fuzz is needed; usage: volec fuzz NAME [ROOT.vl] [--time S]
[exit 2]
## --coverage changes nothing a program prints
% "$COMPILER" main.vl -o plain && "$COMPILER" main.vl --coverage -o counted && ./plain && ./counted
5
5
ok: built plain
ok: built counted
