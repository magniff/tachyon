# Topological sort and cycle detection

Kahn's algorithm orders a directed graph so that every edge goes
forward; a depth-first search with three colours finds a cycle when
there is no such order. A build plan given as text is sorted and then
broken; a random DAG of 1,000,000 nodes and 4,000,000 edges sorts in
about 30 ms, as fast as the same loop in C.

```sh
volec examples/algorithms/toposort/main.vl -o toposort && ./toposort
```

## The problem

Tasks depend on other tasks: a module on the modules it imports, a
course on its prerequisites, a spreadsheet cell on the cells in its
formula. In what order can they run, so that each runs after everything
it needs? As a graph, with an edge from each dependency to the task
that needs it, this is a **topological order**: a list of the nodes in
which every edge goes from an earlier node to a later one.

An order exists exactly when the graph has no directed cycle (a task
that, through its dependencies, needs itself). A useful tool does not
just say "there is a cycle": it shows one.

The program reads a small build plan, lines like `net: io tls`, sorts
it, then sorts a plan with a loop in it and reports the loop, and a
line that does not parse. Then it generates a random DAG of a million
nodes (from a seeded generator: the same on every run), sorts it,
checks that every edge goes forward, finds a longest path, adds an edge
from the end of that path back to its start, and detects the cycle.

## The algorithm

**Kahn's algorithm** (1962) counts each node's incoming edges (its
in-degree). Nodes with none can go first; put them in a queue. Take a
node from the queue, append it to the order, and remove its outgoing
edges: every node whose in-degree drops to zero joins the queue. If the
queue empties before every node is placed, the remaining nodes all have
an incoming edge from another remaining node, so they contain a cycle.

**Depth-first search with three colours** finds that cycle. White nodes
are unvisited, grey ones are on the current path of the search (entered,
not finished), black ones are finished. An edge to a grey node goes back
to an ancestor on the current path: the path from that ancestor to here,
plus the edge, is a cycle. An edge to a black node is harmless (that
node's descendants are all explored and none led back).

**The longest path** in a DAG takes one pass over a topological order:
a node's depth is one more than the depth of the deepest node with an
edge to it, and the order guarantees those are computed first. That is
the "critical path" of a build: no parallel schedule finishes in fewer
steps.

| | time | memory |
|---|---|---|
| building the graph (CSR, a counting sort) | O(V + E) | O(V + E) |
| Kahn's algorithm | O(V + E) | O(V) |
| the cycle search (DFS) | O(V + E) | O(V) |
| the longest path | O(V + E) | O(V) |
| here | V = 10^6, E = 4 x 10^6 | |

## The code

**The graph** is in CSR form, built from a list of `(from, to)` pairs
with a counting sort: count the edges of each source, turn the counts
into start offsets with a running sum, then drop each edge into its
place. `for (from, _) in edges` destructures each pair; an `i32` indexes
a slice directly:

```tach
var start = Vec::filled_in(n + 1, 0, gpa);
let s = start.as_slice();
for (from, _) in edges { s[from + 1] += 1; }
for v in 0..n { s[v + 1] += s[v]; }
```

`g.edges(v)` returns a node's targets as a slice of the target array,
so `for u in g.edges(v)` reads them with no copying.

**Kahn's algorithm** returns a `Result`: the order, or `Err` with the
number of nodes it could not place. The output `Vec` is also the
queue: the nodes before `head` are done, the ones after it wait:

```tach
var head = 0;
while head < order.len() {
    let v = order.get(head);
    head += 1;
    for u in g.edges(v) {
        deg[u] -= 1;
        if deg[u] == 0 { order.push(u); }
    }
}
```

**The cycle search** keeps its own stack of `(node, next edge)` pairs,
since a recursive search a million nodes deep would overflow the
machine stack. `while let Some((v, k)) = stack.last()` looks at the top
without popping it. When the edge leads to a grey node, the cycle is
the part of the stack from that node on, found with `position` and
collected with an iterator chain; `?` returns `None` from the function
if `position` finds nothing (it cannot: a grey node is on the stack):

```tach
let u = targets[k];
if col[u] == GREY {
    let from = stack.iter().position(|(w, _)| w == u)?; // grey: on the stack
    let cycle = stack.as_slice()[from..].iter().map(|(w, _)| w).collect_in(gpa);
    return Some(cycle);
}
```

**The build plan** shows vole's error handling. Parsing returns
`Result<Plan, PlanError>`; `plan_order` uses `?` twice, once on the
parse and once (inside `order`) on the sort:

```tach
enum PlanError { Syntax([u8]), Cycle(Vec<[u8]>) }

fn plan_order(lines: [[u8]], gpa: Gpa) -> Result<Vec<[u8]>, PlanError> {
    var plan = Plan::parse(lines, gpa)?;
    defer plan.free();
    plan.order(gpa) // the names are views of `lines`, not of the plan
}
```

The sort's error is a `Cycle` of node numbers; `order` turns it into a
`PlanError::Cycle` of task names with `map_err` and a closure that
captures the plan (`order` and `named` only read it: `self`, a `let`
receiver), then `?` returns it:

```tach
var order = sort(g, gpa).map_err(|c| self.named(c, gpa))?;
Ok(order.iter().map(|v| self.names.get(v)).collect_in(gpa))
```

Task names are mapped to numbers with a `HashMap<[u8], i64>`; the names
themselves are views of the input lines (`split_whitespace` returns
slices of its argument), so nothing is copied.

**The random DAG** hides a random permutation of the nodes
(Fisher-Yates) and points each random edge from the lower-ranked node
to the higher-ranked one, so no cycle can form. `main` then checks the
order with an iterator over the edges, `edges.iter().all(|(a, b)|
p[a] < p[b])`, and checks the cycle the same way: each node of it has
an edge to the next.

## Output

```text
order: io math gfx crypto ui tls net app tests
cycle: net needs tls needs crypto needs math needs app needs net
not a dependency line: 'app net'
random DAG: 1000000 nodes, 4000000 edges
sorted: 1000000 nodes, first 5, last 3425, every edge forward: true
longest path: 28 nodes, from 110290 to 375268
with the edge 375268 -> 110290: kahn stuck with 6877 nodes left
cycle found: 28 nodes, every step an edge: true
```

and on stderr `kahn on 1000000 nodes: 30 ms, kahn + cycle search: 32 ms`
(the times vary).

## Performance

[`reference.c`](reference.c) builds the same random DAG in C (the same
generator, permutation, edges and CSR graph) and times the same Kahn
loop; it prints the same first and last nodes. On an Apple M-series
machine, Kahn's algorithm alone:

| | time |
|---|---|
| vole 0.15, `-O2` (the default) | 29-36 ms |
| vole 0.15, `-O1` | 53 ms |
| vole 0.15, `-O0` | 136 ms |
| C, `clang -O2` | 31-36 ms |

The loop is memory-bound (each edge touches a random node's in-degree),
so the bounds checks vole adds cost nothing measurable. The whole
program, generation and checks included, runs in about 0.3 s.

## Language features

| feature | where | guide |
|---|---|---|
| `Result`, `?`, `map_err` with a closure | `plan_order`, `Plan::order` | `volec guide conversions` |
| `Option` and `?` | `find_cycle` | `volec guide conversions` |
| enums with payloads, matched by variant | `PlanError`, `print_plan` | `volec guide syntax` |
| `HashMap<[u8], i64>`, `split_whitespace` (views, no copies) | `Plan` | `volec guide std` |
| tuples in `Vec`s, patterns in `for`, `while let`, closures | `Graph::new`, `find_cycle` | `volec guide syntax`, `guide closures` |
| iterators: `position`, `map`, `collect`, `all`, `any`, `enumerate` | `find_cycle`, `main` | `volec guide iterators` |
| default arguments | `random_dag` | `volec guide core` |
| `defer` to free, on every path out | everywhere | `volec guide memory` |
| f-strings | `print_plan`, `main` | `volec guide formatting` |
| a C header: `import "time.h" as c;` | `now_ns` | `volec guide c-interop` |

## Try

- Make Kahn's queue a min-heap of node numbers: the result is the
  lexicographically smallest topological order.
- Print the critical path itself: keep, for each node, the node its
  depth came from, and follow it back from the deepest node.
- Report every task stuck behind the cycle (`kahn`'s leftover nodes),
  not just the cycle.
