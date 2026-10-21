# N-queens

Count every way to put n queens on an n x n chessboard so that no two
attack each other, for n = 1 to 14: half a million solutions, found by a
backtracking search over bitmasks in about 70 ms, the same time as C.

```sh
tachyonc examples/algorithms/nqueens/main.tach -o nqueens && ./nqueens
```

## The problem

A queen attacks along its row, its column and both diagonals. A
placement of n queens where none attacks another needs exactly one
queen per row and one per column, so a solution is a permutation of the
columns with no two queens on a diagonal. There are 92 for the classic
8 x 8 board, 365,596 for 14 x 14; no formula is known, so the counts
(OEIS A000170) come from searches like this one.

## The algorithm

Backtracking, one row at a time: put a queen on each free square of
the current row and count the completions of the rest. A naive version
checks each square against the queens above (O(n) per square). The bit
version keeps three masks of the current row's attacked columns:

- `cols`: a queen above in the same column;
- `left`: a queen above on the diagonal going down and to the left
  (moving one row down shifts it one column: `<< 1`);
- `right`: the same down and to the right (`>> 1`).

The free squares are `all & ~(cols | left | right)`, one expression, and
the loop takes them lowest first with `free & -free`, the lowest set
bit. Each node of the search is a handful of integer instructions, with
no memory but the call stack.

A board reflected left to right is another solution, and a reflection
moves the first row's queen from column `j` to `n - 1 - j`. So the
search starts only from the left half of the first row and doubles the
count; for odd n the middle column, its own mirror, is counted once.
That halves the work.

| | |
|---|---|
| time | exponential: about n! / c^n nodes; 17 million calls for n = 1..14 here |
| memory | O(n): the recursion's stack |
| per node | O(1): a few AND, OR, NOT and shift instructions |

## The code

**The count** is the whole algorithm. The masks are `u64`, the
operators are C's, and `~` is the integer NOT (`!` is for `bool`):

```tach
fn count(all: u64, cols: u64, left: u64, right: u64) -> i64 {
    if cols == all { return 1; }
    var free = all & ~(cols | left | right);
    var total = 0;
    while free != 0 {
        let bit = free & (0 - free);          // the lowest free column
        free ^= bit;
        total += count(all, cols | bit, (left | bit) << 1, (right | bit) >> 1);
    }
    total
}
```

`0 - free` on an unsigned integer wraps, which is defined in tachyon (it
is the two's complement negation); there is no overflow trap to avoid.
The diagonal masks grow bits above column n as they shift left; `all &`
drops them.

**The symmetry** is in `solutions`:

```tach
for j in 0..n / 2 {
    let bit = 1u64 << j;
    total += count(all, bit, bit << 1, bit >> 1);
}
total *= 2;
if n % 2 == 1 { ... the middle column, once ... }
```

**One board** comes from `first`, the same search writing each row's
column into a slice and stopping at the first complete board. An array
`[0; 8]` is passed as `&queens[..]`, a slice that the function writes
through (an `inout [i64]` parameter, so the call marks it with `&`):

```tach
var queens = [0; 8];
if first(8, 0, 0, 0, 0, &queens[..]) { ... draw(queens[..]); }
```

`draw` uses `if` as an expression inside the call:
`print(if j == q { " Q" } else { " ." });`.

**The check** compares each count with the known values, a `const`
array, and prints `WRONG` next to a mismatch from inside the f-string
(any expression fits in a hole, an `if` too). The exit status is 1 if
one differs.

## Output

```text
the first solution for n = 8, by row: 0 4 7 5 2 6 1 3
 Q . . . . . . .
 . . . . Q . . .
 . . . . . . . Q
 . . . . . Q . .
 . . Q . . . . .
 . . . . . . Q .
 . Q . . . . . .
 . . . Q . . . .
 n  solutions
 1          1
 2          0
 3          0
 4          2
 5         10
 6          4
 7         40
 8         92
 9        352
10        724
11       2680
12      14200
13      73712
14     365596
all match OEIS A000170
```

and on stderr, `n-queens 1..14: 71 ms` (the time varies).

## Performance

[`reference.c`](reference.c) is `count` and `solutions` in C, line for
line. n = 1 to 14, on an Apple M-series machine:

| | time |
|---|---|
| tachyon 0.15, `-O2` (the default) | 71 ms |
| tachyon 0.15, `-O1` | 87 ms |
| tachyon 0.15, `-O0` | 250 ms |
| C, `clang -O2` | 70 ms |

The masks are `u64` rather than `u32` (which would hold any board up to
32 x 32) on purpose: with `u32`, tachyon 0.15 zero-extends the result
of every 32-bit operation on arm64 and the search takes 104 ms; with
`u64` there is nothing to extend. n = 15 (2,279,184 solutions) takes
about 0.4 s, n = 16 about 2.5 s.

## Language features

| feature | where | guide |
|---|---|---|
| unsigned integers, `~`, `<<`, `>>`, `^=`, defined wrapping | `count` | `tachyonc guide types` |
| recursion, early `return` | `count`, `first` | `tachyonc guide syntax` |
| arrays as values, `a[..]` as a slice written through | `main`, `first` | `tachyonc guide types` |
| `const` arrays | `KNOWN` | `tachyonc guide syntax` |
| `if` as an expression, inside a call and an f-string hole | `draw`, `main` | `tachyonc guide syntax`, `guide formatting` |
| `for n in 1..=14`, `for q in queens` | `main`, `draw` | `tachyonc guide syntax` |
| f-strings with widths: `{found:>10}` | `main` | `tachyonc guide formatting` |
| `main`'s value as the exit status | `main` | `tachyonc guide core` |
| a C header: `import "time.h" as c;` | `now_ns` | `tachyonc guide c-interop` |

## Try

- Count n = 15 or 16 (change the loop's bound and add 2279184 and
  14772512 to `KNOWN`).
- Use the other symmetries (rotations) to cut the work further.
- Print every solution for n = 6 (there are 4) with a variant of `first`
  that keeps going.
