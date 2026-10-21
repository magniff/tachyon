# Dijkstra's shortest paths

Single-source shortest paths with a binary heap, on a generated grid
graph of a million nodes and four million weighted edges: about 40 ms,
within 1.2x of the same program in C.

```sh
tachyonc examples/algorithms/dijkstra/main.tach -o dijkstra && ./dijkstra
```

## The problem

Given a directed graph whose edges have non-negative weights and a
source node `s`, find for every node `v` the smallest total weight of a
path from `s` to `v`, and one path that achieves it.

The graph here is a `W x H` grid. Each cell is a node with an edge to
each of its (up to four) neighbours; every edge gets a weight from 1 to
9 from a seeded generator (xorshift64*), so the graph, and the output,
are the same on every run and every machine. The program solves a
10 x 6 grid and draws it, then a 1000 x 1000 one, timed.

## The algorithm

Dijkstra's algorithm grows a set of *settled* nodes whose distance is
final. Every node starts at distance infinity, the source at 0. Each
step takes the unsettled node `v` with the smallest tentative distance
(it is final: every other path to `v` passes through a node at least as
far) and *relaxes* its edges: for an edge `v -> u` of weight `w`, if
`dist[v] + w < dist[u]`, then `u` gets the shorter distance and `v` as
its predecessor.

A binary min-heap finds the closest node. Instead of a "decrease key"
operation, this version pushes a new entry each time a distance
improves and ignores entries that are out of date when they come off
the heap ("lazy deletion"): simpler, and usually faster.

| | |
|---|---|
| time | O((V + E) log V): each edge pushes at most one entry, each entry costs O(log V) |
| memory | O(V + E): the graph, the distances, the heap |
| here | V = 10^6, E = 3,996,000 |

## The code

**The graph** is in compressed sparse row (CSR) form: the edges leaving
`v` are `targets[start[v]..start[v + 1]]`, with their weights at the
same indices. Three flat arrays instead of a `Vec` per node: one
allocation each, and the edges of a node are adjacent in memory.

```tach
struct Graph { n: i64, start: Vec<i64>, targets: Vec<i32>, weights: Vec<i32> }
```

`Graph::grid` builds it, looping over the four directions with a tuple
pattern:

```tach
let steps = [(0, 1), (1, 0), (0, -1), (-1, 0)];
...
for (dr, dc) in steps {
    let (nr, nc) = (r + dr, c + dc);
    if nr >= 0 && nr < h && nc >= 0 && nc < w {
        targets.push((nr * w + nc) as i32);
        weights.push(rng.range(1, 9) as i32);
    }
}
```

**The heap** is generic over any `T: Ord`: the children of slot `i` are
`2i + 1` and `2i + 2`. `pop` uses `?` on the `Option` that `Vec::pop`
returns, so an empty heap returns `None` in one token:

```tach
struct MinHeap<T: Ord> { items: Vec<T> }

fn pop(inout self) -> Option<T> {
    let last = self.items.pop()?;         // empty: None
    let s = self.items.as_mut_slice();
    ...
}
```

Both sift loops take the Vec's slice once (`as_slice()`) and index it:
indexing is bounds-checked, and the checks are cheap compared to the
cache misses of a heap.

**An entry is one `i64`**: `(dist << 32) | node`. Comparing two entries
compares distances first and nodes second, exactly as a
`#[derive(Ord)] struct Entry { dist: i64, node: i32 }` would, but in
one instruction, and the heap moves 8 bytes per entry instead of 16.
Distances here stay far below 2^31, so the packing is exact.

```tach
fn entry(dist: i64, node: i64) -> i64 { (dist << 32) | node }
```

**The search** is the loop described above. `while let` pops until the
heap is empty; a stale entry (its distance is larger than the node's
current one) is skipped:

```tach
while let Some(e) = heap.pop() {
    let (dv, v) = (e >> 32, e & 0xffff_ffff);
    if dv > d[v] { continue; }            // a stale entry: v was settled closer
    settled += 1;
    for k in start[v]..start[v + 1] {
        let u = targets[k] as i64;
        let nd = dv + weights[k];         // i32 widens to i64 by itself
        if nd < d[u] {
            d[u] = nd;
            p[u] = v as i32;
            heap.push(entry(nd, u));
        }
    }
}
```

`Vec::filled_in(g.n, UNREACHED, gpa)` makes the distance array (Rust's
`vec![x; n]`); `d`, `p`, `start`, ... are slices of the Vecs, taken
once, which the loop indexes and writes through.

**The output** follows the predecessors back from the far corner to
mark the path, and prints with f-strings (`{d:>3}` pads to three
columns, `{mark:c}` prints a `u8` as its character, `{checksum:x}` in
hexadecimal). The checksum folds every distance with an iterator:

```tach
let checksum = big.dist.iter().fold(0u64, |h, x| (h ^ x as u64) * 0x100000001B3);
```

**The timing** calls C's `timespec_get` through `import "time.h" as c;`
and goes to stderr, so stdout stays the same on every run.

## Output

```text
 *  0    8   12   16   23   27   24   26   31   35
 *  6 *  9 * 10 * 14 * 18 * 22 * 23   29   32   38
   12   11   18   22   21   25 * 27 * 28 * 30   32
   17   14   16   24   22   26   29   34 * 33 * 35
   18   15   19   25   30   30   36   37   37 * 37
   18   17   24   26   32   31   39   40   41 * 44
cost 44, 14 steps
grid 1000x1000: 1000000 nodes, 3996000 edges, 1000000 settled
corner to corner: 5187, farthest node: 5187
checksum of the distances: 3cce7dd8784eadd5
```

and on stderr, `dijkstra on 1000000 nodes: 41 ms` (the time varies).

## Performance

[`reference.c`](reference.c) is the same program in C (the same
generator, graph, heap and checksum; it prints the same corner distance
and checksum). The search alone, on an Apple M-series machine:

| | time |
|---|---|
| tachyon 0.15, `-O2` (the default) | 41 ms |
| tachyon 0.15, `-O1` | 52 ms |
| tachyon 0.15, `-O0` | 300 ms |
| C, `clang -O2` | 35 ms |

The tachyon version checks every index; the C one checks none.

A heap of `(dist, node)` structs with a derived `Ord` is the more
obvious design, and it works unchanged with this `MinHeap<T: Ord>`; it
measured 85 ms here (C with a struct and a two-field comparison: 45 ms),
because each entry is 16 bytes moved through memory and compared field
by field. The packed `i64` is the classic fix, in either language.

## Language features

| feature | where | guide |
|---|---|---|
| generic struct with a bound, `impl<T: Ord>` | `MinHeap<T: Ord>` | `tachyonc guide generics`, `guide traits` |
| `?` on an `Option` | `MinHeap::pop` | `tachyonc guide conversions` |
| `while let`, `continue`, tuple patterns | `dijkstra` | `tachyonc guide syntax` |
| `Vec::filled`, `as_slice`, slices written through | `dijkstra` | `tachyonc guide std`, `guide memory` |
| widening (`i32` weight + `i64` distance) | `dijkstra` | `tachyonc guide conversions` |
| `defer` to free | everywhere | `tachyonc guide memory` |
| iterators and closures: `iter().max()`, `fold` | `main` | `tachyonc guide iterators`, `guide closures` |
| f-strings with specs: `{d:>3}`, `{x:c}`, `{h:x}` | `draw`, `main` | `tachyonc guide formatting` |
| a C header: `import "time.h" as c;` | `now_ns` | `tachyonc guide c-interop` |

## Try

- Change the seeds or the sizes in `main` (a 3000 x 3000 grid takes
  about half a second).
- Replace the packed entries with `#[derive(Eq, Ord)] struct Entry {
  dist: i64, node: i32 }` and `MinHeap<Entry>`, and time it.
- Weight the cells instead of the edges, or add diagonal moves: only
  `Graph::grid` changes.
