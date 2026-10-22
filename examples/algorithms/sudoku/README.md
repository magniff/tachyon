# Sudoku

A sudoku solver by backtracking over bitmasks, filling the most
constrained cell first. It solves the well-known hard puzzles, proves
each solution unique, and runs about 50 ns per search node: the same
speed as the same solver in C.

```sh
volec examples/algorithms/sudoku/main.vl -o sudoku && ./sudoku
```

## The problem

Fill a 9 x 9 grid with the digits 1 to 9 so that each row, each column
and each of the nine 3 x 3 boxes holds every digit once, keeping the
digits given (the *clues*). A proper puzzle has exactly one solution;
17 clues is the fewest that can make one unique.

The program solves seven puzzles: Arto Inkala's "world's hardest
sudoku" (2012), five 17-clue puzzles from the hard lists of Peter
Norvig's essay on solving sudoku, and
the easy one from Wikipedia's article. Then it solves 70 *disguised*
copies of them, each with its digits relabelled and its rows and
columns shuffled, timed, and prints a checksum of their solutions.

## The algorithm

Depth-first search with backtracking:

1. Pick an empty cell.
2. For each digit that does not already appear in its row, column or
   box, write it and search the rest of the grid.
3. If nothing works, erase it and return: the caller tries its next
   digit.

Two choices make it fast.

**Bitmask constraints.** Each row, column and box keeps a 9-bit mask of
the digits it holds, bit `d - 1` for digit `d`. A cell's candidates are
`0x1ff & ~(rows[r] | cols[c] | boxes[b])`: three loads, two ORs, a NOT.
Placing and erasing a digit set and clear one bit in three masks.

**Most constrained cell first** (the "minimum remaining values"
heuristic). Each step scans the empty cells and picks the one with the
fewest candidates. A cell with none means a dead end, found at once; a
cell with one is forced, and filling it costs no guess. Most of a
puzzle's cells end up forced, so the search tree stays small: a few
thousand nodes for most 17-clue puzzles, where a solver that takes the
cells in order visits orders of magnitude more.

The search doesn't stop at the first solution: it stops at the second,
or when the tree is exhausted, so it also proves that the solution is
unique.

| | |
|---|---|
| time | exponential in the worst case (sudoku generalized to n² x n² is NP-complete); here 50 to 170,000 nodes per puzzle |
| per node | O(81): the scan for the most constrained cell |
| memory | O(81) per level of recursion: at most 81 levels |

## The code

**The grid** is a struct of fixed-size arrays, a plain value: copying
it (`self.first = self.grid`) copies the cells and masks, with no
allocation.

```tach
struct Sudoku { cells: [u8; 81], rows: [u64; 9], cols: [u64; 9], boxes: [u64; 9] }

fn candidates(self, i: i64) -> u64 {
    ALL & ~(self.rows[i / 9] | self.cols[i % 9] | self.boxes[box_of(i)])
}
```

**Parsing** returns a `Result`. The error is an enum with a derived
`Debug`, so `{e:?}` prints it as the code that would make it, e.g.
`Conflict(80, 8)`: the digit 8 at index 80 is already in its row:

```tach
#[derive(Debug)]
enum ParseError { Length(i64), BadChar(i64, u8), Conflict(i64, u8) }

fn parse(text: [u8]) -> Result<Sudoku, ParseError> {
    if text.len() != 81 { return Err(ParseError::Length(text.len())); }
    var s = Sudoku::empty();
    for (i, b) in text.iter().enumerate() {
        if b == '.' || b == '0' { continue; }
        ...
```

**The search** is `Search::fill`. It keeps the grid it is filling, the
first solution, and counters; `Search::run` takes the solution limit as
a default argument, so `Search::run(p)` proves uniqueness and
`Search::run(p, limit: 1)` (a named argument) stops at the first:

```tach
fn run(puzzle: Sudoku, limit: i64 = 2) -> Search { ... }
```

The candidate loop takes the lowest bit with `m & (0 - m)`, turns it
into a digit by counting the bits below it (`std::count_ones`), and
undoes its move after the recursive call:

```tach
var m = best_mask;
while m != 0 && self.found < self.limit {
    let bit = m & (0 - m);
    m ^= bit;
    self.grid.place(best, (count_ones(bit - 1) + 1) as u8);
    self.fill();
    self.grid.clear(best);
}
```

**`count_ones`** (std, 0.19) counts the bits of a mask: on AArch64 it is
the processor's population-count instruction (`cnt`), elsewhere a few
branch-free operations. `use std::count_ones;` names it.

**The disguises** map a puzzle to an equivalent one: shuffle the three
bands of rows and the rows inside each band, the same for columns, and
relabel the digits. Each solution maps to a solution, so the puzzle is
as hard as before but the search sees a different grid. The shuffles
are Fisher-Yates over a slice of an array, with a seeded xorshift
generator, so the run is the same every time.

## Output

```text
puzzle        solution
8........     812753649
..36.....     943682175
.7..9.2..     675491283
.5...7...     154237896
....457..     369845721
...1...3.     287169534
..1....68     521974368
..85...1.     438526917
.9....4..     796318452

#  clues   nodes  unique
0     21   24881  yes
1     17    3723  yes
2     17    2030  yes
3     17    2628  yes
4     17  173775  yes
5     17   97524  yes
6     30      52  yes
a broken puzzle: Conflict(80, 8)
70 disguised puzzles: 1925501 nodes, checksum a5f50395f4cb2674
```

and on stderr, `sudoku: 70 puzzles in 90 ms` (the time varies).

## Performance

[`reference.c`](reference.c) is the timed part in C: the same puzzles,
generator, disguises, search and checksum, and it prints the same line.
On an Apple M-series machine:

| | 70 disguised puzzles, 1.9 million nodes |
|---|---|
| vole 0.15, `-O2` (the default), the branch-free popcount | 90 ms |
| vole 0.15, `-O1` | 125 ms |
| vole 0.15, `-O0` | 700 ms |
| C, `clang -O2`, `__builtin_popcountll` | 90 ms |

The popcount matters. Written as the usual loop (`while x != 0 { x &=
x - 1; n += 1; }`), the vole solver took 1.5 times as long as C:
clang recognizes that loop and emits the processor's population-count
instruction, and vole 0.15 had no such intrinsic. A branch-free
popcount (the counts of bit pairs, then nibbles, then bytes, summed by
one multiply) closed the gap; since 0.19 `std::count_ones` is the
instruction itself, about 10% faster again than the branch-free version
(measured with 0.25).

## Language features

| feature | where | guide |
|---|---|---|
| fixed-size arrays in a struct, copied as values | `Sudoku`, `Search` | `volec guide types` |
| `Result` and an error enum with `#[derive(Debug)]`, `{e:?}` | `parse`, `main` | `volec guide conversions`, `guide formatting` |
| `match` on `Ok` / `Err` | `main` | `volec guide syntax` |
| default and named arguments: `limit: i64 = 2`, `run(p, limit: 1)` | `Search::run` | `volec guide core` |
| methods taking `inout self` and writing through it | `place`, `clear`, `fill` | `volec guide core` |
| bit operations on `u64`, `~`, wrapping `0 - m`; `std::count_ones` | `candidates`, `fill` | `volec guide types`, `guide std` |
| iterators and closures: `enumerate`, `filter(\|d\| d != 0).count()` | `parse`, `clues` | `volec guide iterators`, `guide closures` |
| `const` arrays of strings | `PUZZLES` | `volec guide syntax` |
| slices of arrays passed to functions that write them | `Rng::shuffle`, `shuffle_lines` | `volec guide memory` |
| a C header: `import "time.h" as c;` | `now_ns` | `volec guide c-interop` |

## Try

- Add your own puzzle to `PUZZLES` (and its length to the array type).
- Count all solutions of a puzzle with fewer clues: `Search::run(p,
  limit: 1_000_000)` on a puzzle with a few clues erased.
- Pick the cell by a different rule (the first empty one) and compare
  the node counts.
- Add "hidden singles" (a digit with only one possible cell in a row)
  to the propagation and watch the node counts drop.
