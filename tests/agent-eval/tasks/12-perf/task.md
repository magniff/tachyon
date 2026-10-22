# Distinct values in many ranges

Generate an array and a list of ranges from a seed, then count the
distinct values in every range. The sizes go up to two million of each,
so the program must be fast: about O((n + q) log n) in total. Checking
each range element by element is far too slow.

## Input

One line with four integers: `n q m seed`, where 1 ≤ n ≤ 2,000,000,
1 ≤ q ≤ 2,000,000, 1 ≤ m ≤ 1,000,000,000 and 0 ≤ seed ≤ 10^18.

## The generator

A 64-bit unsigned state `x` starts at `seed`. Each call of `next()` does

    x = x * 6364136223846793005 + 1442695040888963407   (mod 2^64)
    return x >> 33                                       (logical shift)

First the array: `a[i] = next() % m` for i = 0, 1, ..., n-1, in order.
Then the queries, for j = 0, 1, ..., q-1 in order: `u = next() % n`,
`v = next() % n`, and the range is from `l = min(u, v)` to `r = max(u, v)`,
both included (0-based). The answer `d_j` is the number of distinct values
among `a[l], a[l+1], ..., a[r]`.

## Output

- the answers of the first `min(q, 10)` queries, one per line;
- `sum S`, where S is the sum of all q answers;
- `hash H`, where H starts at 0 and, for each answer in query order,
  becomes `(H * 1000003 + d_j) mod 1000000007`.

## Example

Input:

```
10 5 3 42
```

The array is `1 2 1 0 2 1 2 0 2 2`; the ranges are 0..4, 2..4, 8..9,
0..9 and 4..9 (the first query's u is 4 and v is 0), with 3, 3, 1, 3
and 3 distinct values. The first three calls of `next()` from seed 42
return 1220265334, 484179026 and 886563538.

Output:

```
3
3
1
3
3
sum 13
hash 559672256
```

The hidden tests include n = 1, all values equal (m = 1), q much larger
than n, m = 2, the largest seed, and several inputs with n and q near
2,000,000 and m from 1,000 to 1,000,000,000. Each test has a time limit
of a few seconds.
<!-- reference times on the task author's machine (Apple silicon), largest test (n = q = 2e6): Rust 0.18 s, vole 0.37 s; limit 4 s -->
