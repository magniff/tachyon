# Shortest paths

Answer shortest-path queries in a weighted directed graph.

## Input

All numbers are integers separated by spaces and newlines.

- The first line: `n m q`, the number of vertices (1 <= n <= 100000),
  edges (0 <= m <= 300000) and queries (1 <= q <= 50). Vertices are
  numbered `0` to `n - 1`.
- `m` lines `u v w`: a directed edge from `u` to `v` of weight `w`
  (0 <= w <= 1000000000). There may be several edges between the same two
  vertices, and edges from a vertex to itself.
- `q` lines `s t`: a query for the length of the shortest path from `s` to
  `t`.

## Output

One line per query: the length of the shortest path from `s` to `t` (the
smallest sum of the weights along a path), `0` when `s == t`, or `-1`
when `t` cannot be reached from `s`. Path lengths can exceed 2^32: use
64-bit integers.

## Example

Input:

```
5 6 4
0 1 4
0 2 1
2 1 2
1 3 5
2 3 10
3 0 1
0 3
3 1
0 4
2 2
```

Output:

```
8
4
-1
0
```

## Notes

- The largest test has tens of thousands of vertices and edges and many
  queries, each from a different source: a search that scans every vertex
  to find the next closest one is too slow; use a priority queue (binary
  heap). Each query must cost about O(m log n).
- Weights can be 0.
