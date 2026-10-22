# Iterators

`Iterator` is a prelude trait with one required function and an
associated type:

```text
trait Iterator {
    type Item;
    fn next(inout self) -> Option<Self::Item>;
    // and, written once in std: map filter enumerate zip take
    // fold for_each count sum min max collect
}
```

std's sources and adapters are small structs whose methods are
`#[inline]`: a chain of them compiles to the loop written by hand (the
same machine code at -O2, vectorized where the loop would be).

```tach
fn main(gpa: Gpa) -> i32 {
    var v: Vec<i64> = Vec::new_in(gpa);
    for i in 1..=6 { v.push(i); }
    std::print_int(v.iter().filter(|x| x % 2 == 0).map(|x| x * x).sum());
    print(" ");
    std::print_int(v.iter().map(|x| x * 10).max().unwrap());
    print(" ");
    std::print_int((0..100).filter(|n| n % 7 == 0).count());
    println("");
    for (i, x) in v.iter().enumerate().take(2) {
        std::print_int(i * 100 + x);
        print(" ");
    }
    std::print_int(v.iter().zip(v.iter()).fold(0, |acc, (a, b)| acc + a * b));
    println("");
    var w = v.iter().map(|x| 7 - x).collect_in(gpa);       // a Vec<i64>
    w.sort_by(|a, b| a.cmp(b));                         // a, b: let i64
    for x in w { std::print_int(x); }
    println("");
    0
}
```
```out
56 60 15
1 102 91
123456
```

## Sources

| source | items |
|---|---|
| `v.iter()` (a `Vec<T>`), `s.iter()` (a slice `[T]`; an array variable too, `a.iter()`) | each element, a copy |
| `m.iter()`, `m.keys()`, `m.values()` (a `HashMap<K, V>`) | `(K, V)`, `K`, `V`, in slot order |
| `a..b`, `a..=b` as a value: `(0..n).map(...)` | the integers; `0..=255u8` ends without overflow |
| a type with `impl Iterator` | what its `next` returns |

`for x in E` takes a range, a slice or an array as before, an iterator,
or anything with an `iter` method (`for x in v`, `for (k, n) in m`);
items are let: a copy of a plain element, a read-only access to an owned
one. To change elements, loop over the indices: `for i in 0..v.len() {
v[i] *= 2; }`.

## Adapters and consumers

- `map(f)`, `filter(f)` (`f` takes the item by value: `|x| x > 0`, not
  `|&x|`), `enumerate()` (items `(i64, Item)`), `zip(other)` (items
  `(A, B)`, as long as both have one), `take(n)`.
- `fold(init, |acc, x| ...)`, `for_each(f)`, `count()`, `sum()` (from
  `0 as Item`), `min()` and `max()` (an `Option`), `collect()` (a `Vec`
  of the items, dropped with its scope; there is no other target, and no
  `collect::<Vec<_>>()`).
- `sort_by(&s, |a, b| ...)` sorts in place by a comparison of two let `T`s
  returning negative, zero or positive (`a.cmp(b)`; `b.cmp(a)`
  descending); also `v.sort_by(...)` and `s.sort_by(...)`.
- An adapter and a consumer take the iterator `sink` (0.25): an adapter
  owns the one it wraps, so a chain is one value, and what it did not
  reach drops with it; `it.count()` uses `it` up. `any`, `all`,
  `position` and `find` take it `inout`: they stop at the item that
  decides, and the rest stay in `it`. To call `next` yourself (`inout
  self`), keep the iterator in a `var`.
- Owned items (a `Vec<D>`'s `pop`, `map(|i| make(i))`) are dropped once:
  by `for` at the end of each iteration unless moved, and by an adapter
  or consumer that passes over them (`count`, the ones `filter`
  rejects, `min`'s and `max`'s losers). The items of a borrowing iterator
  (`v.iter()`, a map's `iter`, `keys`, `values`, a set's `iter`) are
  copies of elements the container keeps: read them, or `.clone()` one
  to keep it (`own.move_out` otherwise).

## Your own iterator

```tach
struct Countdown { n: i64 }

impl Iterator for Countdown {
    type Item = i64;
    fn next(inout self) -> Option<i64> {
        if self.n == 0 { return None; }
        self.n -= 1;
        Some(self.n + 1)
    }
}

fn first<I: Iterator>(it: sink I) -> Option<I::Item> {
    it.next()                           // a sink parameter is the callee's: mutable
}

fn total<I: Iterator<Item = i64>>(it: sink I) -> i64 {
    it.sum()
}

fn main() -> i32 {
    let c = Countdown { n: 3 };
    for x in c { std::print_int(x); }
    print(" ");
    std::print_int(total(Countdown { n: 4 }));
    print(" ");
    std::print_int(first(Countdown { n: 9 }).unwrap());
    println("");
    0
}
```
```out
321 10 9
```

- `type Item = T;` in the impl is required; `Self::Item` and `I::Item`
  (for a type parameter `I: Iterator`) name it. `I: Iterator<Item = i64>`
  constrains it.
- The defaults (`map`, `sum`...) come with the trait; one used with an
  `Item` it does not fit (`sum` of `[u8]` items) is an error only when
  it is called.
- `exact_len()` (items left, or -1) and `at(k)` are hooks that let `zip`
  and `enumerate` run as a counted loop; leave them out.

Not there: `iter_mut` (use indices: `v[i] += 1`), `rev`, `step_by`,
`chain`, `flat_map`, `peekable`, `collect` into other types, `dyn
Iterator`, returning an iterator built from a closure (0.15).
