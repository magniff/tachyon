# Iterators

`Iterator` is a prelude trait with one required function and an
associated type:

```text
trait Iterator {
    type Item;
    fn next(self: *Self) -> Option<Self::Item>;
    // and, written once in std: map filter enumerate zip take
    // fold for_each count sum min max collect
}
```

std's sources and adapters are small structs whose methods are
`#[inline]`: a chain of them compiles to the loop written by hand (the
same machine code at -O2, vectorized where the loop would be).

```tach
fn main() -> i32 {
    let mut v: Vec<i64> = Vec::new();
    defer v.free();
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
    let mut w = v.iter().map(|x| 7 - x).collect();      // a Vec<i64>
    defer w.free();
    w.sort_by(|a, b| a.cmp(b));                         // a, b: *i64
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
items are copies, as `for x in slice` gives. To change elements, loop
over the indices: `for i in 0..v.len() { v.set(i, v.get(i) * 2); }`.

## Adapters and consumers

- `map(f)`, `filter(f)` (`f` takes the item by value: `|x| x > 0`, not
  `|&x|`), `enumerate()` (items `(i64, Item)`), `zip(other)` (items
  `(A, B)`, as long as both have one), `take(n)`.
- `fold(init, |acc, x| ...)`, `for_each(f)`, `count()`, `sum()` (from
  `0 as Item`), `min()` and `max()` (an `Option`), `collect()` (a `Vec`
  of the items; free it; there is no other target, and no
  `collect::<Vec<_>>()`).
- `sort_by(s, |a, b| ...)` sorts in place by a comparison of `*T`s
  returning negative, zero or positive (`a.cmp(b)`; `b.cmp(a)`
  descending); also `v.sort_by(...)` and `s.sort_by(...)`.
- An adapter takes its iterator by value, so a chain is one value; to
  call `next` yourself, keep the iterator in a `let mut`.

## Your own iterator

```tach
struct Countdown { n: i64 }

impl Iterator for Countdown {
    type Item = i64;
    fn next(self: *Countdown) -> Option<i64> {
        if self.n == 0 { return None; }
        self.n -= 1;
        Some(self.n + 1)
    }
}

fn first<I: Iterator>(it: I) -> Option<I::Item> {
    let mut it = it;
    it.next()
}

fn total<I: Iterator<Item = i64>>(it: I) -> i64 {
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

Not there: `iter_mut` (use indices and `set`), `rev`, `step_by`,
`chain`, `flat_map`, `peekable`, `collect` into other types, `dyn
Iterator`, returning an iterator built from a closure (0.15).
