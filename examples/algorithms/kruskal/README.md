# Kruskal's minimum spanning tree

Union-find (union by size, path halving) and Kruskal's algorithm, on a
generated graph of 200,000 nodes and 1,000,000 weighted edges: sorting
the edges and building the spanning forest takes about 55 ms, faster
than C with `qsort` and close to C++ with `std::sort`.

```sh
tachyonc examples/algorithms/kruskal/main.tach -o kruskal && ./kruskal
```

## The problem

Given an undirected graph with weighted edges, choose a set of edges
that connects every node that can be connected, with the smallest total
weight: a *minimum spanning tree* (for a connected graph), or a forest
of one tree per connected component. Laying cables, roads or pipes at
the least cost is the classic use; clustering is another (stop before
the last `k - 1` edges and the trees are `k` clusters).

The program solves a small graph of seven towns (the textbook example
from Wikipedia's article) and prints the roads it keeps, then a random
graph: 1,000,000 edges between random pairs of 200,000 nodes, with
weights from 1 to 1,000,000, all from a seeded generator (xorshift64*),
so the output is the same on every run.

## The algorithm

Kruskal's algorithm is greedy: sort the edges by weight, then take each
edge in that order if it joins two different trees of the forest built
so far, and skip it if both ends are already in one tree (it would make
a cycle). The cut property guarantees the result is minimal: the
lightest edge across any cut belongs to some minimum spanning tree.

"Are `u` and `v` already connected?" is answered by a **union-find**
(disjoint-set forest). Every set is a tree of nodes pointing towards a
root; `find(x)` walks to the root, `unite(a, b)` hangs one root under
the other. Two tricks make both nearly constant time:

- **union by size**: the smaller tree goes under the larger one's root,
  so no tree is deeper than log2(n);
- **path halving**: while walking up, each node is pointed at its
  grandparent, flattening the path for the next walk.

Together they cost O(alpha(n)) amortized per operation, where alpha is
the inverse Ackermann function: at most 4 for any n that fits in memory.

| | |
|---|---|
| time | O(E log E) to sort, then O(E alpha(V)) for the union-finds |
| memory | O(V + E) |
| here | V = 200,000, E = 1,000,000; the sort is most of the time |

## The code

**An edge** is a struct with a derived `Ord`, which compares fields in
declaration order. Putting the weight first makes `std::sort(edges)` sort
by weight, with ties broken by `u` then `v`, so the result is
deterministic. `Debug` is derived too, for printing one:

```tach
#[derive(Eq, Ord, Debug)]
struct Edge { w: i64, u: i32, v: i32 }
```

**The generator** has default arguments, so the call in `main` gives
only what differs from the defaults:

```tach
fn random_edges(n: i64, m: i64, max_weight: i64 = 1_000_000, seed: u64 = 7) -> Vec<Edge>
...
let mut edges = random_edges(n, 1_000_000);
```

**The union-find** keeps two `Vec<i32>` (4 bytes a node: better for the
cache than `i64`). `new` builds the identity `parent` array with an
iterator and `collect`:

```tach
fn new(n: i64) -> UnionFind {
    let parent = (0..n).map(|i| i as i32).collect();
    UnionFind { parent: parent, size: Vec::filled(n, 1i32), sets: n }
}
```

`find` takes a slice of the parent array once and halves the path as it
goes. Indexing a slice with an `i32` works directly (any integer type
indexes):

```tach
fn find(self: *UnionFind, x: i64) -> i64 {
    let p = self.parent.as_slice();
    let mut x = x;
    while p[x] as i64 != x {
        let g = p[p[x]];
        p[x] = g;
        x = g as i64;
    }
    x
}
```

`unite` orders the two roots by size with a tuple-valued `if` (tachyon
has no tuple assignment, so `let (ra, rb) = if ... { (y, x) } else {
(x, y) };` replaces `(ra, rb) = (rb, ra)`):

```tach
let (x, y) = (self.find(a), self.find(b));
if x == y { return false; }
let size = self.size.as_slice();
let (ra, rb) = if size[x] < size[y] { (y, x) } else { (x, y) };
self.parent.set(rb, ra as i32);
size[ra] += size[rb];
```

(`union` is a keyword in tachyon, for C-compatible unions, hence the
name `unite`.)

**Kruskal** is then a sort and a loop. It returns a tuple, the forest's
edges and the number of trees, and stops early once `n - 1` edges are
taken (a spanning tree has no room for more). The `i32` fields of the
edge widen to the `i64` parameters of `unite` by themselves:

```tach
fn kruskal(n: i64, edges: [Edge]) -> (Vec<Edge>, i64) {
    std::sort(edges);
    let mut uf = UnionFind::new(n);
    defer uf.free();
    let mut tree: Vec<Edge> = Vec::with_capacity(n - 1);
    for e in edges {
        if uf.unite(e.u, e.v) {
            tree.push(e);
            if tree.len() == n - 1 { break; }
        }
    }
    (tree, uf.sets)
}
```

**The output** destructures that tuple (`let (mut tree, trees) =
kruskal(7, roads[..]);`), sums and maxes weights with iterator chains
(`tree.iter().map(|e| e.w).sum()`), and prints with f-strings,
`{tree.get(0):?}` through the derived `Debug`. The timing goes to
stderr through C's `timespec_get`.

## Output

```text
A - D   5
C - E   5
D - F   6
A - B   7
B - E   7
E - G   9
6 roads, cost 39, 1 tree
cheapest road: Edge { w: 5, u: 0, v: 3 }
random graph: 200000 nodes, 1000000 edges
spanning forest: 199991 edges, 9 components
total weight 24018008108, heaviest edge 994553
```

and on stderr `kruskal on 1000000 edges: 55 ms` (the time varies). The
random graph has 9 components because, with 10 edge ends per node on
average, about `200000 * e^-10`, so 9, nodes get no edge at all.

## Performance

[`reference.c`](reference.c) is the same program in C (the same
generator, sort order, union-find and results). The timed part, sort
plus union-find, on an Apple M-series machine:

| | time |
|---|---|
| tachyon 0.15, `-O2` (the default) | 55 ms |
| tachyon 0.15, `-O0` | 310 ms |
| C, `clang -O2`, `qsort` | 73 ms |
| C++, `clang++ -O2`, `std::sort` (the same file, the sort swapped) | 51 ms |

`std::sort` in tachyon is generic: it is compiled for `Edge` with the
derived `cmp` inlined into the introsort, as C++'s template is, while
C's `qsort` calls the comparison through a function pointer for every
one of the ~20 million comparisons.

## Language features

| feature | where | guide |
|---|---|---|
| `#[derive(Eq, Ord, Debug)]`, sorting by a derived `Ord` | `Edge`, `kruskal` | `tachyonc guide formatting` (derive), `guide std` (sort) |
| default and named arguments | `random_edges` | `tachyonc guide core` |
| ranges as iterators, `map`, `collect`, `sum`, `max` | `UnionFind::new`, `main` | `tachyonc guide iterators`, `guide closures` |
| tuples: returned, destructured, a tuple-valued `if` | `kruskal`, `unite`, `main` | `tachyonc guide syntax` |
| widening (`i32` fields to `i64` parameters) | `kruskal` | `tachyonc guide conversions` |
| `Vec::filled`, `as_slice`, slices written through | `UnionFind` | `tachyonc guide std`, `guide memory` |
| `defer` to free | everywhere | `tachyonc guide memory` |
| f-strings: `{w:>2}`, `{e:?}` | `main` | `tachyonc guide formatting` |
| a C header: `import "time.h" as c;` | `now_ns` | `tachyonc guide c-interop` |

## Try

- Make the random graph denser (`random_edges(n, 5_000_000)`): one
  component, and the early `break` cuts the loop short.
- Replace path halving by full path compression (a second loop that
  points every node on the path at the root) and time both.
- Stop when `uf.sets == k` to split the nodes into `k` clusters.
- Sort with `edges.sort_by(|a, b| b.w.cmp(&a.w))` to get a maximum
  spanning tree.
