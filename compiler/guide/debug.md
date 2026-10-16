# Debugging

`query` and `edit` answer where code is and how to change it. These
tools answer what the program does: where it failed, which values a line
saw, which part of an input matters. None of them edits the source.

## The recipe

1. Make the failure a test case: the input in `tests/NAME.in`, the
   output it should give in `tests/NAME.out`. Then run `tachyonc test
   NAME`. Tests are built with `--trace`. A crash prints its line and
   the calls that led to it, and a hang stopped by `--timeout S` prints
   where it was running. For one run without a case: `tachyonc test
   --input FILE`.
2. Read the trace. Its first frame, `FILE:LINE  function`, is the
   failing statement. `tachyonc query show FILE:LINE` prints its item.
3. See the values without editing:
   `tachyonc probe FILE:LINE EXPR... --input FILE`. Probe the lines
   above the failure, then the callers in the trace. `--count FILE:LINE`
   says how often a line runs (a loop that never ends, a branch never
   taken).
4. If the input is too big to reason about, shrink it:
   `tachyonc reduce FILE --until 'CMD'`.
5. Fix the bug (`edit patch`), then run `tachyonc test` again. In the
   tachyon tree, each failing case is also run with
   `target/tools/tachyonc`. A case that fails there too
   (`failing too`) was not broken by your change.

## Failure traces

`tachyonc FILE.tach --trace -o prog` builds with a shadow stack: each
function's frame records the statement it is running. A failed check
prints the frames, innermost first:

```text
index out of bounds: index 0, length 0
trace, innermost call first:
  stats.tach:44  stats::best
  main.tach:25  main
```

The first frame is the line of the failing index (or `unwrap`, `panic`).
The frames below it are the calls that led there, each at the line of its
call. A program stopped by SIGALRM (`tachyonc test --timeout`), SIGINT,
SIGTERM or SIGSEGV prints `stopped by signal N` and the frames. A loop
without calls shows its own line.

`--trace` builds at -O1 or -O2 (with -O0, at -O1). It costs a few
instructions per call and per loop iteration: the compiler runs about
25% slower when built with it, and its binary is larger. Without
`--trace`, a failure is one line, its position and message:

```tach
fn main() -> i32 {
    let v = [1, 2, 3];
    let i = v.len() as i64;
    std::print_int(v[i]);
    0
}
```
```out (exit 101)
main.tach:4:20: index out of bounds: index 3, length 3
```

`tachyonc test` builds with `--trace` (`--no-trace` turns it off). A
failing case shows the first lines of its stderr, so the trace appears
in the summary.

## probe

```text
$ tachyonc probe stats.tach:46 i m 'v[i]' --input tests/ok.in
probe stats.tach:46 (before `if v[i] > m {`): 2 times
  #1  i = 1  m = 3  v[i] = 7
  #2  i = 1  m = 3  v[i] = 7
run: exit 0; stdout 4 lines (.tachyonc/probe/out)
  | a best 7
```

Each `FILE:LINE` starts a probe, and the expressions after it are
printed each time it runs (the first 10 times; `--max N`). Where it goes
depends on the line:

| the line | the probe |
|---|---|
| begins a statement | runs before it |
| begins a `let` | runs after it: the new names are visible |
| begins `while`, `for`, `loop` | runs at the start of the body, each time round |
| opens a block (`} else {`, `X => {`, `fn f(x: T) {`) | runs at the start of that block |

Values are printed by type. Integers, floats and bool print as values,
`[u8]` quoted, arrays and slices up to 16 elements, `Option` and tuples
element by element, pointers as addresses. A struct uses Debug when it
has it, else prints field by field. The program is built from copies of
its files with the probes written in (`--overlay`), so line numbers stay
the same, and with `--trace`. Then it runs with `-- ARGS` and stdin from
`--input FILE` (or the command's own stdin), within `--timeout S` (10).
The report lists each probe's count and values, then the exit status,
the start of stdout and stderr.

Several probes go in one run: `tachyonc probe a.tach:10 x a.tach:20 y`.
`--count FILE:LINE` counts runs without printing. A probe whose name is
not in scope at its line is an error (`probe.expr`), so probe a later
line for a value made later.

In the tachyon tree the program is the compiler itself. To see what it
does when compiling a test:

```text
tachyonc probe compiler/src/front/check/interp.tach:633 h t -- case.tach -o /tmp/p
```

## reduce

```text
$ tachyonc reduce big.in --until './prog < {} > /dev/null 2>&1; test $? = 101'
reduced big.in: 304 lines to 2 in 35 runs; written to big.in.min
```

`{}` is the candidate's path. CMD must exit with 0 while the failure is
still there: `./prog < {} | grep -q wrong` for wrong output,
`test $? = 101` for a crash. For a compiler bug, use
`target/tachyonc {} -o /tmp/p 2>&1 | grep -q 'MESSAGE'`. Lines are left
out in chunks, and the chunks are halved when none can go. A run that
takes longer than `--timeout S` (5) counts as not failing.

## Other questions

| to know | run |
|---|---|
| who changes a field or static | `tachyonc query refs Struct.field --kind write` |
| who calls a function, transitively | `tachyonc query callers NAME`, `query callees FN --transitive` |
| whether optimization changes it | `tachyonc test -O 0`, then `tachyonc test` (-O2) |
| which test a compiler change broke | `tachyonc test FILTER` (tachyon tree): `new` vs `failing too` |
| what an expression gives | `tachyonc try 'STATEMENTS'` |
