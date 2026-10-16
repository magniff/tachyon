## `tachyonc fuzz NAME` (0.18): a #[fuzz] function run on inputs it
## mutates, built with --coverage: an input that reaches new code is kept.
## Here a crash behind the 4-byte magic "FUZZ", found by the coverage of
## its four comparisons, shrunk and saved.
$ fuzz parse_never_crashes --time 120
FAIL parse_never_crashes (fuzz, after 16001 runs, shrunk in 2 steps): main.tach:9:28: index out of bounds: index 4, length 2
  input: data = "FUZZ"
  saved: .tachyonc/fuzz/parse_never_crashes/crash-c6d0a3857a0d9820 (tachyonc test replays it; test --accept keeps it in tests/fuzz/parse_never_crashes/)
  try: tachyonc test parse_never_crashes main.tach
[exit 1]
% ls .tachyonc/fuzz/parse_never_crashes | grep crash
crash-c6d0a3857a0d9820
## `tachyonc test` replays the saved crash; --accept keeps it in tests/fuzz/
$ test
test main.tach: 0 passed, 1 failed (1 #[fuzz] target; -O0 and -O2 agree)
FAIL parse_never_crashes (fuzz, input .tachyonc/fuzz/parse_never_crashes/crash-c6d0a3857a0d9820): main.tach:9:28: index out of bounds: index 4, length 2
  trace: main.tach:9 parse < main.tach:24 parse_never_crashes
  input: data = "FUZZ"
(outputs: .tachyonc/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
$ test --accept
test main.tach: 0 passed, 1 failed (1 #[fuzz] target; -O0 and -O2 agree)
FAIL parse_never_crashes (fuzz, input tests/fuzz/parse_never_crashes/crash-c6d0a3857a0d9820): main.tach:9:28: index out of bounds: index 4, length 2
  trace: main.tach:9 parse < main.tach:24 parse_never_crashes
  input: data = "FUZZ"
(outputs: .tachyonc/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
% ls tests/fuzz/parse_never_crashes
crash-c6d0a3857a0d9820
## mistakes
$ fuzz nope
error fuzz.unknown: no #[fuzz] or #[property] function 'nope' in main.tach; its targets: parse_never_crashes
try: tachyonc fuzz parse_never_crashes main.tach
[exit 2]
$ fuzz
error fuzz.usage: the #[fuzz] function to fuzz is needed; usage: tachyonc fuzz NAME [ROOT.tach] [--time S]
[exit 2]
## --coverage changes nothing a program prints
% "$COMPILER" main.tach -o plain && "$COMPILER" main.tach --coverage -o counted && ./plain && ./counted
5
5
ok: built plain
ok: built counted
