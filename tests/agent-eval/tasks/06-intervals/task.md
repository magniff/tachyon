# Interval coverage

Merge a set of integer intervals and answer coverage queries about their
union.

## Input

All numbers are integers in -1000000000 to 1000000000.

- A line with `n` (0 <= n <= 100000), then `n` lines `l r` with `l <= r`:
  the closed interval of all integers `x` with `l <= x <= r`. Intervals may
  overlap, nest, repeat, and come in any order.
- A line with `q` (0 <= q <= 100000), then `q` query lines, each one of:
  - `point x`: is the integer `x` covered by some interval?
  - `cover a b` (`a <= b`): is every integer in `a..b` (inclusive)
    covered?
  - `count a b` (`a <= b`): how many integers in `a..b` (inclusive) are
    covered?

Tokens are separated by single spaces; every line ends with a newline.

## Output

First a line `K T`: `K` is the number of intervals in the union after
merging (two intervals merge when they overlap or touch: `1 3` and `4 6`
make `1 6`, because together they cover every integer from 1 to 6), and
`T` is the number of integers covered. Then one line per query: `yes` or
`no` for `point` and `cover`, a number for `count`.

`T` and the counts can exceed 2^31: use 64-bit integers.

## Example

Input:

```
4
5 8
1 3
4 4
10 12
5
point 4
point 9
cover 2 8
cover 8 10
count 0 11
```

Output:

```
2 11
yes
no
yes
no
10
```

(The union is `1 8` and `10 12`.)

## Notes

- Inputs have tens of thousands of intervals and queries, and counts
  over ranges spanning billions of integers: sort the intervals once,
  then answer each query in O(log n) (binary search, prefix sums).
- With `n = 0` the first line is `0 0` and every answer is `no` or `0`.
