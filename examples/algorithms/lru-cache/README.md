# LRU cache

A least-recently-used cache, generic over its key and value types: a
`HashMap` from key to slot, and a doubly linked list threaded through a
`Vec` of slots by index. 12 million requests through caches of three
sizes take about 230 ms, under 20 ns a request.

```sh
tachyonc examples/algorithms/lru-cache/main.tach -o lru && ./lru
```

## The problem

A cache keeps the results of slow lookups (a disk read, a network call,
a long computation) in a bounded amount of memory. When it is full and
a new result arrives, something must go: the LRU policy evicts the
entry that was used longest ago, betting that what was used recently
will be used again soon. Both operations, `get(key)` and `put(key,
value)`, should take O(1) time whatever the cache's size.

The program traces a cache of three entries with text keys, then
serves a skewed stream of 4,000,000 integer requests (a few keys are
very popular, most are rare, as with web pages or words) through caches
of 1,000, 10,000 and 100,000 entries, computing the value on a miss.
The stream comes from a seeded generator, so the output is the same on
every run.

## The algorithm

Two structures, each covering what the other cannot do in O(1):

- a **hash map** from each key to its entry's slot: finds an entry;
- a **doubly linked list** of the entries in order of use, the most
  recent at the head, the least recent at the tail: moving an entry to
  the front is unlinking it and linking it at the head, and the entry
  to evict is the tail.

`get` looks the key up and moves its entry to the front. `put` of a key
that is there updates it and moves it to the front; of a new key, it
takes a free slot while there is one, else unlinks the tail, removes
its key from the map and reuses its slot.

The list's links are **indices into a `Vec`**, not pointers: the
entries are allocated once (the `Vec` of `capacity` slots), nothing is
allocated or freed per request, and the whole cache is freed with three
calls. An "intrusive" list: the links live in the entries themselves.

| | |
|---|---|
| `get`, `put` | O(1) expected (one hash lookup, a few link updates) |
| memory | O(capacity): one node and one map slot per entry |
| here | 3 x 4,000,000 requests |

## The code

**The entries** are a generic struct; `NIL` (-1) ends the list. The
cache's key type needs `Hash + Eq` for the map, the value type nothing:

```tach
const NIL: i32 = -1;

struct Node<K, V> { key: K, value: V, prev: i32, next: i32 }

struct LruCache<K: Hash + Eq, V> {
    capacity: i64,
    slots: HashMap<K, i32>, // key -> its node's index in `nodes`
    nodes: Vec<Node<K, V>>,
    head: i32, // the most recently used, or NIL
    tail: i32, // the least recently used, or NIL
    stats: Stats,
}
```

**The list operations** write the nodes in place through the `Vec`
(`self.nodes[prev].next = next` changes the node where it is). An `i32`
indexes it directly:

```tach
fn unlink(self: &mut LruCache<K, V>, i: i32) {
    let (prev, next) = (self.nodes[i].prev, self.nodes[i].next);
    if prev == NIL { self.head = next; } else { self.nodes[prev].next = next; }
    if next == NIL { self.tail = prev; } else { self.nodes[next].prev = prev; }
}
```

**`get`** uses `match` as an expression whose `None` arm counts the
miss and returns early:

```tach
fn get(self: &mut LruCache<K, V>, key: K) -> Option<V> {
    let i = match self.slots.get(key) {
        Some(i) => i,
        None => {
            self.stats.misses += 1;
            return None;
        }
    };
    self.stats.hits += 1;
    if i != self.head {
        self.unlink(i);
        self.push_front(i);
    }
    Some(self.nodes.as_slice()[i].value)
}
```

**`put`** returns the evicted entry, if any, as `Option<(K, V)>`; when
full, it recycles the tail's slot:

```tach
let i = self.tail;
self.unlink(i);
let n = self.nodes.as_slice();
let old = (n[i].key, n[i].value);
self.slots.remove(old.0);
n[i].key = key;
n[i].value = value;
self.slots.insert(key, i);
self.push_front(i);
```

**An iterator** walks the list from the head: a struct holding a view
of the nodes and the current index, and an `impl Iterator` with `type
Item = (K, V)`. Everything iterators have comes with it: `show` uses
`enumerate` and a nested tuple pattern:

```tach
impl<K, V> Iterator for LruIter<K, V> {
    type Item = (K, V);
    fn next(self: *LruIter<K, V>) -> Option<(K, V)> {
        if self.at == NIL { return None; }
        let n = self.nodes[self.at];
        self.at = n.next;
        Some((n.key, n.value))
    }
}
...
for (k, (key, value)) in cache.iter().enumerate() { ... }
```

**Two instances** of the one generic type: `LruCache<[u8], i64>` for
the trace (a `[u8]` key hashes and compares by its bytes) and
`LruCache<i64, i64>` for the workload. Each is compiled separately, as
if written by hand for its types.

**The workload** draws a magnitude, then a key below it, so key 0 is
drawn about once in 10 requests while a key near 10^6 is drawn about
once in 20 million. `serve` has default arguments for the request count
and the seed, and returns its statistics (`#[derive(Debug, Clone)]
struct Stats`) and the sum of the values served in a tuple. The sum is
the same for every capacity: a cache changes how fast an answer comes,
never the answer.

## Output

```text
put a, b, c
  [c=3, b=2, a=1]
get a -> Some(1)
  [a=1, c=3, b=2]
put d -> evicts b=2
  [d=4, a=1, c=3]
get b -> None
put c=30 -> updates c, evicts nothing
  [c=30, d=4, a=1]
Stats { hits: 1, misses: 1, evictions: 1 }
capacity   1000: hit rate 45.84%, 2165200 evictions, sum 1957768245
capacity  10000: hit rate 63.95%, 1432094 evictions, sum 1957768245
capacity 100000: hit rate 82.32%,  607309 evictions, sum 1957768245
```

and on stderr `lru: 12000000 requests in 230 ms` (the time varies).

## Performance

[`reference.c`](reference.c) is the integer workload in C, with a hash
table built the way std's `HashMap` is (open addressing, linear
probing, removed slots marked, the same hash function, growth at 3/4
full), so the two do the same work. It prints the same three lines. On
an Apple M-series machine:

| | time |
|---|---|
| tachyon 0.15, `-O2` (the default) | 230 ms |
| tachyon 0.15, `-O1` | 330 ms |
| tachyon 0.15, `-O0` | 2.0 s |
| C, `clang -O2` | 155 ms |

The whole request path, `HashMap::get` included, is inlined into
`serve`'s loop; the gap is in register allocation around the hash
table's probe loop, which reloads constants and shuffles registers on
each probe. Most of the time, in both languages, is cache misses in the
map and the node array.

## Language features

| feature | where | guide |
|---|---|---|
| a generic struct with bounds, `impl<K: Hash + Eq, V>` | `LruCache` | `tachyonc guide generics`, `guide traits` |
| `HashMap` with `[u8]` and `i64` keys | `LruCache` | `tachyonc guide std` |
| your own `impl Iterator`, `type Item`, `enumerate` | `LruIter`, `show` | `tachyonc guide iterators` |
| `match` as an expression with an early `return` | `get`, `serve` | `tachyonc guide syntax` |
| `Option<(K, V)>`, tuple patterns in `for` and `if let` | `put`, `main` | `tachyonc guide syntax` |
| `#[derive(Debug, Clone)]`, `{x:?}` | `Stats`, `main` | `tachyonc guide formatting` |
| default arguments | `serve` | `tachyonc guide core` |
| f-strings: `{rate:.2}`, `{n:>7}` | `main` | `tachyonc guide formatting` |
| `defer` to free | `serve`, `main` | `tachyonc guide memory` |
| a C header: `import "time.h" as c;` | `now_ns` | `tachyonc guide c-interop` |

## Try

- Count evictions per key, or add `peek(key)` that does not change the
  order of use.
- Make the workload uniform (`rng.below(1 << 20)`) and watch the hit
  rate fall to `capacity / 2^20`.
- Replace LRU by CLOCK: a "referenced" bit per slot and a hand that
  sweeps the `Vec`, no list at all.
