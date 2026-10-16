# Tests, properties and fuzzing

Tests are written in the language (0.18) and run by `tachyonc test`,
which builds them at -O0 and at -O2 and compares the two. Other builds
leave test items out; `check` and the queries see them.

## #[test]

```tach
fn gap(v: [i64]) -> i64 {
    let mut best = 0;
    for i in 1..v.len {
        if v[i] - v[i - 1] > best {
            best = v[i] - v[i - 1];
        }
    }
    best
}

#[test]
fn gap_of_three() {
    assert_eq(gap([1, 5, 6][..]), 4);
}

#[test]
fn parses() -> Result<(), std::ParseIntError> {
    let n = std::parse_int("12")?;
    assert(n == 12);
    Ok(())
}

#[test]
fn keeps_nothing(gpa: Gpa) {
    let mut b = Buf::new_in(gpa);
    b.push_str("dropped at the end");
}

fn main() -> i32 {
    std::print_int(gap([2, 9][..]));
    0
}
```
```out
7
```

- A `#[test]` takes nothing or `gpa: Gpa`, and returns `()` or a
  Result (an `Err` fails). Anything else is `test.signature`.
- Test builds use `--check-alloc`: a block left allocated fails the test
  (`check-alloc: 1 block of Gpa not freed ... allocated at FILE:L:C`).
- `#[cfg(test)] mod tests;` (a file, or `mod tests { .. }`) is a module
  only test builds have. It sees its parent's items without an import:
  `use super::*;` is refused (`import.wildcard`; no wildcard imports).
- `assert_snapshot(x)` compares `{x:?}` with
  `tests/snapshots/MODULE__TEST__N.snap`; the first run writes it, a
  change fails with the first differing line, `--accept` rewrites it.

## #[property]

A property's parameters are generated: 100 cases (`--cases N`), sizes
growing, a failure shrunk to a small input and printed with its seed.

```tach
fn clamp(x: i64, lo: i64, hi: i64) -> i64 {
    if x < lo { lo } else if x > hi { hi } else { x }
}

#[property]
fn clamp_stays_in(x: i64, lo: i64, hi: i64) {
    if lo <= hi {
        let c = clamp(x, lo, hi);
        assert(lo <= c && c <= hi);
    }
}

struct Small { n: i64 }

impl std::Arbitrary for Small {
    fn arbitrary(g: &mut std::Gen) -> Small {
        Small { n: g.int_in(0, 9) }
    }
}

#[property]
fn small_is_small(s: Small) {
    assert(s.n >= 0 && s.n <= 9);
}

fn main() -> i32 {
    std::print_int(clamp(12, 0, 9));
    0
}
```
```out
9
```

- Numbers, bool, `Vec<T>`, `[T]`, `Buf`, `Option`, `Result`, tuples
  and the program's structs and enums are generated from their types;
  `impl std::Arbitrary` gives a type its own (`g.int_in(lo, hi)`,
  `g.choose(n)`, `g.bool()`, `g.size()`).
- Each case runs in a child process; its values are dropped after it,
  and a block it leaves allocated fails the case (a leak).
- A function with an `ensures` is tested as a property too, its
  requires filtering the inputs (`--no-contracts`: not).

## tachyonc test

```text
$ tachyonc test
test main.tach: 6 passed, 2 failed (1 case, 5 #[test], 2 #[property], 1 contract; -O0 and -O2 agree)
FAIL gap_needs_two: checks.tach:14:8: index out of bounds: index 1, length 1
  trace: checks.tach:14 checks::gap_needs_two
FAIL bubble_sorts (property, case 11 of 100, shrunk in 8 steps): not sorted
  input: v = [1, 0]
  try: tachyonc test bubble_sorts --seed 0xf788dd27897d1fed main.tach
```

- The summary first, then one line per failure, its trace, its input
  and the command that replays it. `FILTER` runs the tests whose name
  holds it; `tests/NAME.in` with `NAME.out` are cases of the program.
- A test whose -O0 and -O2 runs differ is a `DIFF` line: the compiler's
  bug, not yours (`tachyonc reduce --differs` shrinks it).
- `--seed H` replays a property's failure, `--accept` takes snapshots,
  case outputs and saved fuzz inputs, `-O N` runs one level.

## #[fuzz] and tachyonc fuzz

```tach
fn parse(data: [u8]) -> i64 {
    if data.len >= 2 && data[0] == 'O' && data[1] == 'K' {
        return 1;
    }
    0
}

#[fuzz]
fn parse_never_crashes(data: [u8]) {
    let _ = parse(data);
}

fn main() -> i32 {
    std::print_int(parse("OK"));
    0
}
```
```out
1
```

`tachyonc fuzz NAME [--time S]` builds the test binary with `--coverage`
(every block counts in std's map) and mutates inputs, keeping those that
reach new code. A crash is shrunk, saved under `.tachyonc/fuzz/NAME/`
and replayed by every `tachyonc test` after (`--accept` keeps it in
`tests/fuzz/NAME/`). A `#[fuzz]` takes one `[u8]` (or any generated
types, like a property).

## tachyonc reduce over programs

- `tachyonc reduce PROG.tach --differs [--input F]`: the program cut
  while its -O0 and -O2 runs disagree (a miscompile, to report).
- `--fails 'TEXT'`: while the build or the run prints TEXT.
- `--test NAME`: while test NAME fails as it does now.

Items, then statements, are cut by halves, then one by one; the result
is `PROG.min.tach`. For an input instead: `tachyonc reduce FILE --until
'CMD'` (guide debug).
