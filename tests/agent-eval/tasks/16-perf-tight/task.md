# Cells within reach

The workspace holds a working program: it generates a grid of open
cells and walls from a seed, then answers many queries of the form "how
many open cells can be reached from this cell in at most d steps". Its
answers are correct, but it is far too slow on the large inputs: it
spends its time allocating and hashing for every query.

**Make it fast.** The output must stay exactly the same. The largest
inputs (a 2000 x 2000 grid and 200,000 queries) must finish within a
time limit of a few seconds per test, which is several times faster than
the program is now. Each query only touches the cells near its start, so
the work a query does should be proportional to the cells it reaches,
not to the grid, and without a hash table or memory allocation per query.

## Input

One line with six integers: `h w q p dmax seed`, where 1 ≤ h ≤ 2000,
1 ≤ w ≤ 2000, 1 ≤ q ≤ 200,000, 0 ≤ p ≤ 100, 0 ≤ dmax ≤ 30 and
0 ≤ seed ≤ 10^18.

## The generator

A 64-bit unsigned state `x` starts at `seed`. Each call of `next()` does

    x = x * 6364136223846793005 + 1442695040888963407   (mod 2^64)
    return x >> 33                                       (logical shift)

First the grid, row by row (row 0 first), each row from column 0 to
column w-1: the cell is a **wall** when `next() % 100 < p`, and **open**
otherwise. So `p` is the percentage of walls: 0 gives no walls, 100 only
walls.

Then the queries, for j = 0, 1, ..., q-1 in order: `r = next() % h`,
`c = next() % w`, `d = next() % (dmax + 1)` (three calls, in this order).

## The answer to a query

A step moves from a cell to one of its four neighbours (up, down, left,
right) inside the grid; steps never enter or cross a wall. The answer
`a_j` is the number of open cells that can be reached from (r, c) in at
most d steps, counting (r, c) itself. If (r, c) is a wall the answer is
0. With d = 0 the answer is 1 for an open cell.

## Output

- the answers of the first `min(q, 10)` queries, one per line;
- `sum S`, where S is the sum of all q answers;
- `hash H`, where H starts at 0 and, for each answer in query order,
  becomes `(H * 1000003 + a_j) mod 1000000007`.

## Example

Input:

```
5 6 5 25 4 1
```

The grid (`#` a wall, `.` open; row 0 on top) and the queries `(r, c, d)`:

```
......      (2, 4, 3) -> 6
.#..##      (0, 2, 2) -> 8
.#.#..      (1, 4, 1) -> 0   (a wall)
.....#      (4, 5, 2) -> 1   (its two neighbours are walls)
..#.#.      (0, 4, 1) -> 3
```

The first three calls of `next()` from seed 1 return 908834774,
1093944153 and 1392341196 (so cells (0, 0), (0, 1) and (0, 2) are open).

Output:

```
6
8
0
1
3
sum 18
hash 156232621
```

The hidden tests include a 1 x 1 grid (open, and a wall), dmax = 0, a
single row and a single column, a grid of only walls, a grid with no
walls, the largest seed, and several inputs with h and w near 2000,
q = 200,000, dmax = 30 and p from 5 to 30. Each test has a time limit of
2.5 seconds.
<!-- reference times on the task author's machine (Apple silicon, other jobs running), median of 3 on the five large tests (2000 x 2000 or 1500 x 2000, q = 200,000, dmax = 30): solution tachyon 0.41-0.80 s, Rust 0.38-0.94 s; the starter (a Vec of Vecs, and a hash set and a queue allocated per query) tachyon 2.7-8.7 s, Rust 3.0-6.7 s (5.0 s or more on four of the five); a flat grid with a hash set per query is as slow as the starter; limit 2.5 s -->
