# Algorithms in vole

Ten classic algorithms, each a complete program in idiomatic vole
0.15 with a README that explains the problem, the algorithm, its
complexity and the code. Every one works on a deterministic, generated
input (seeded generators, so the output is the same on every run and
machine), checks its own answer, and times its core on stderr. Most
come with `reference.c`, the same program in C, and the README says how
the two compare.

| example | algorithm | complexity | vole features shown | time (-O2) | vs C (clang -O2) |
|---|---|---|---|---|---|
| [dijkstra](dijkstra/) | Dijkstra's shortest paths, binary heap, CSR graph | O((V + E) log V) | generic `MinHeap<T: Ord>`, `?` on Option, `while let`, `Vec::filled`, iterators, f-string specs | 41 ms, 1M nodes | 35 ms |
| [kruskal](kruskal/) | union-find + Kruskal's minimum spanning tree | O(E log E) | `#[derive(Ord)]` sort, union-find, default args, iterators, tuples | 55 ms, 1M edges | 73 ms (`qsort`) |
| [toposort](toposort/) | Kahn's algorithm, three-colour DFS for cycles | O(V + E) | `Result`, `?`, `map_err`, enums with payloads, `HashMap<[u8], i64>` | 30 ms, 4M edges | 31 ms |
| [string-search](string-search/) | naive, Knuth-Morris-Pratt, Boyer-Moore-Horspool | O(n + m); O(n / m) typical for BMH | a trait with a generic method and a default, `FnMut` closures, slice `==`, `[i64; 256]` tables | about 1 GB/s | 0.9-1.1x |
| [huffman](huffman/) | Huffman coding: canonical codes, bit packing, table decoder | O(n + k log k) | `#[derive(Eq, Ord, Debug)]`, generic `MinHeap`, `?`, `main -> Result`, named and default args, `zip`/`fold`/`position` | 500 MB/s encode | within 1.2x |
| [lru-cache](lru-cache/) | LRU cache: `HashMap` + list linked by indices | O(1) per request | generic struct, `HashMap`, custom `Iterator`, `#[derive(Debug, Clone)]` | 230 ms, 12M requests | 155 ms |
| [bigint](bigint/) | big integers: schoolbook and Karatsuba multiplication, fast-doubling Fibonacci | O(n^1.585) multiply | `impl Add/Sub/Mul`, `Ord`, `Display`, `From<u64>`/`.into()`, `#[derive(Eq, Clone, Debug)]` | F(10^6) in 44 ms | 24 ms |
| [quickselect](quickselect/) | quickselect, median of medians (BFPRT) | O(n) expected; O(n) worst | generic over `T: Ord`, re-slicing views, tuple returns, closures capturing a `var`, `collect` | 26 ms, 2M values | 24 ms |
| [sudoku](sudoku/) | backtracking over bitmasks, most-constrained cell first | exponential; ~50 ns per node | fixed arrays in structs, `Result` + `#[derive(Debug)]` errors, default and named arguments | 90 ms, 1.9M nodes | 90 ms |
| [nqueens](nqueens/) | n-queens counting with bitmasks and mirror symmetry | exponential; O(1) per node | unsigned bit tricks, recursion, `const` arrays, `if` in f-strings | 71 ms, n = 1..14 | 70 ms |

The times are from an Apple M-series machine; each README has the full
table (`-O0`, `-O1`, `-O2`, C) and what the gap is, where there is one.

## Running

Each example is one file:

```sh
volec examples/algorithms/NAME/main.vl -o NAME && ./NAME
cc -O2 examples/algorithms/NAME/reference.c -o NAME-c && ./NAME-c   # the C version, where there is one
```

The test suite runs every one and compares its output
(`tests/examples/algorithms-NAME.test`): `tests/run.sh algorithms`.

## What they have in common

- **Deterministic input.** A small seeded generator (xorshift64* or
  similar) makes the graphs, texts and numbers, so the expected output
  can be checked byte for byte.
- **Timing on stderr.** `import "time.h" as c;` and C's
  `timespec_get`; stdout holds only results.
- **Memory without `free`.** Vectors and maps are dropped at the end of
  their scope, or moved to an owner that outlives it (`volec guide
  memory`).
- **Checked indexing.** Every slice access is bounds-checked; the C
  references check nothing, and the times above include the checks.

## What they found

Writing these for speed turned up a few places where vole 0.15's
code is slower than it should be; each README says what was measured
and how the example avoids it:

- 32-bit integer operations are followed by redundant zero extensions
  on arm64 (`nqueens` uses `u64` masks: 71 ms instead of 104 ms).
- No population-count intrinsic: the bit-counting loop clang turns into
  one instruction stays a loop (`sudoku` uses a branch-free popcount).
- Struct-valued heap entries are moved through memory (`dijkstra` packs
  `(dist, node)` into one `i64`: 41 ms instead of 85 ms).
- The `u32 x u32 -> u64` multiply-accumulate loop is not vectorized
  (`bigint`'s schoolbook kernel is 1.7x behind clang's).
- Register shuffling in hash-probe loops (`lru-cache`, 1.5x behind C).
- Fields of a struct updated through `inout self` in a hot loop stay in
  memory (`huffman`'s encoder keeps its bit buffer in locals: 8.7 ms
  instead of 11 ms).
