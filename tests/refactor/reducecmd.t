## `tachyonc reduce` over a program (0.18): it is made small (items, then
## statements, left out) while it stays interesting.
## --differs: -O0 and -O2 disagree (here a test-only switch makes -O2 read
## the literal 12345 as 12346, in one of 30 functions of 428 lines)
% TACHYON_PLANT_MISCOMPILE=1 "$COMPILER" reduce main.tach --differs
reduced main.tach: 428 lines to 12 in 307 runs; written to main.min.tach
fn f17(x: i64) -> i64 {
    let mut t = x;
    t = t + 12345;
    t
}

fn main() -> i32 {
    let mut total = 0;
    total += f17(total % 1000);
    println(f"{total}");
    0
}
% wc -l < main.min.tach | tr -d ' '
12
## --fails TEXT: its build or run prints TEXT
$ reduce crash.tach --fails 'index out of bounds'
reduced crash.tach: 21 lines to 9 in 35 runs; written to crash.min.tach
fn last(v: [i64]) -> i64 {
    v[v.len]
}

fn main() -> i32 {
    let b = [4, 5];
    println(f"{last(b[..])}");
    0
}
## nothing to keep
$ reduce main.tach --differs
error reduce.not-failing: main.tach: -O0 and -O2 agree on it as it is (nothing to keep)
[exit 1]
$ reduce crash.tach --fails 'no such text'
error reduce.not-failing: crash.tach: its build and run do not print the text as it is (nothing to keep)
[exit 1]
