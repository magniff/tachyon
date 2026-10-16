## The debugging tools (0.17, guide debug). `tachyonc test` builds with
## --trace: a failed check prints the calls that led to it, a time limit
## where the program was.
$ test --timeout 1
test main.tach: 1 passed, 2 failed (3 cases; -O0 and -O2 agree)
FAIL crash: exit 101 (expected 0): stats.tach:44:17: index out of bounds: index 0, length 0
  trace: stats.tach:44 stats::best < main.tach:25 main
FAIL hang: no exit after 1 s (--timeout S): stopped by signal 14 (SIGALRM: a time limit)
  trace: stats.tach:56 stats::bar < main.tach:28 main
(outputs: .tachyonc/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
## A program built with --trace (at -O1 at least); without it, a failure's
## message has a note.
$ main.tach --trace -o prog
ok: built prog
% ./prog < tests/crash.in; echo "exit $?"
a best 7
exit 101
stats.tach:44:17: index out of bounds: index 0, length 0
trace, innermost call first:
  stats.tach:44  stats::best
  main.tach:25  main
$ main.tach -o plain
ok: built plain
% ./plain < tests/crash.in; echo "exit $?"
a best 7
exit 101
stats.tach:44:17: index out of bounds: index 0, length 0
## probe: values at a line, the source unchanged. Before the statement
## that begins the line; after a `let` (its names visible); in a loop's
## body each time round; at the start of a block that the line opens.
$ probe stats.tach:46 i m 'v[i]' --input tests/ok.in
probe stats.tach:46 (before `if v[i] > m {`): 2 times
  #1  i = 1  m = 3  v[i] = 7
  #2  i = 1  m = 3  v[i] = 7
run: exit 0; stdout 4 lines (.tachyonc/probe/out)
  | a best 7
  | b best 5
  | a best 7
  | ###
$ probe stats.tach:44 v --input tests/crash.in
probe stats.tach:44 (after `let mut m = v[0];`): 1 time
  #1  v = [3, 7]
run: exit 101; stdout 1 line (.tachyonc/probe/out)
  | a best 7
stderr:
  stats.tach:44:17: index out of bounds: index 0, length 0
  trace, innermost call first:
    stats.tach:44  stats::best
    main.tach:25  main
$ probe stats.tach:35 i 'keys[i]' key 'values[i]' --input tests/ok.in --max 2
probe stats.tach:35 (before `if keys[i] == key && values[i] > 0 {`): 9 times, the first 2 (--max N)
  #1  i = 0  keys[i] = "a"  key = "a"  values[i] = 3
  #2  i = 1  keys[i] = "b"  key = "a"  values[i] = 5
run: exit 0; stdout 4 lines (.tachyonc/probe/out)
  | a best 7
  | b best 5
  | a best 7
  | ###
$ probe main.tach:24 i v --input tests/ok.in --max 1
probe main.tach:24 (after `let v = stats::positive(gpa, values.as_slice(), ke...`): 3 times, the first 1 (--max N)
  #1  i = 0  v = [3, 7]
run: exit 0; stdout 4 lines (.tachyonc/probe/out)
  | a best 7
  | b best 5
  | a best 7
  | ###
$ probe main.tach:23 i --input tests/ok.in
probe main.tach:23 (each time round `while i < keys.len() {`): 3 times
  #1  i = 0
  #2  i = 1
  #3  i = 2
run: exit 0; stdout 4 lines (.tachyonc/probe/out)
  | a best 7
  | b best 5
  | a best 7
  | ###
## --count: how often a line runs
$ probe --count stats.tach:46 --count stats.tach:36 --input tests/ok.in
probe stats.tach:46 (before `if v[i] > m {`): 2 times
probe stats.tach:36 (before `out.push(values[i]);`): 5 times
run: exit 0; stdout 4 lines (.tachyonc/probe/out)
  | a best 7
  | b best 5
  | a best 7
  | ###
## the values by type: structs field by field, Option, tuples, slices
% printf 'struct P { x: i64, name: [u8] }\n\nfn main() -> i32 {\n    let p = P { x: 3, name: "ab" };\n    let o: Option<i64> = Some(2);\n    let t = (1, true);\n    let a = [1, 2, 3];\n    std::print_int(p.x);\n    0\n}\n' > one.tach
$ probe one.tach:8 p o t 'a[1..]' '&a[0] == &a[0]' --root one.tach
probe one.tach:8 (before `std::print_int(p.x);`): 1 time
  #1  p = P { x: 3, name: "ab" }  o = Some(2)  t = (1, true)  a[1..] = [2, 3]  &a[0] == &a[0] = true
run: exit 0; stdout 1 line (.tachyonc/probe/out)
  | 3
## mistakes
$ probe stats.tach:1 x
error probe.no-statement: stats.tach:1 begins no statement and opens no block; a probe goes at a line that does
try: tachyonc probe stats.tach:5 x
try: tachyonc probe stats.tach:6 x
[exit 1]
$ probe stats.tach:500 x
error probe.no-line: stats.tach has no line 500
[exit 1]
$ probe nofile.tach:3 x
error probe.no-file: no file 'nofile.tach' in the program (a probe goes in a file of it)
try: tachyonc query items
[exit 1]
$ probe stats.tach:46 nothing
error probe.expr: stats.tach:46: in 'nothing': undefined variable 'nothing'
[exit 1]
$ probe x
error probe.usage: an expression needs a FILE:LINE before it: 'x'; usage: tachyonc probe FILE:LINE [EXPR...]... [--count FILE:LINE] [--max N] [--input FILE] [--timeout S] [-O N] [--root ROOT] [-- ARGS...]
[exit 2]
## reduce: a failing input made small, line by line ({}: the candidate;
## exit 0: it still fails)
% printf 'a 3\nb 4\nc 5\nd -1\ne 6\nf 7\n' > big.in
$ reduce big.in --until './prog < {} > /dev/null 2>&1; test $? = 101'
reduced big.in: 6 lines to 1 in 6 runs; written to big.in.min
d -1
% cat big.in.min
d -1
$ reduce big.in --until 'false'
error reduce.not-failing: the command does not hold (exit 0) on big.in as it is: false
[exit 1]
$ reduce big.in
error reduce.usage: FILE and --until 'CMD' are needed; usage: tachyonc reduce FILE --until 'CMD' [--out FILE] [--max-runs N] [--timeout S] ({} in CMD: the candidate; exit 0: it still fails); tachyonc reduce PROG.tach --differs [--input F] | --fails 'TEXT' | --test NAME [--differs] (a program made small)
[exit 2]
