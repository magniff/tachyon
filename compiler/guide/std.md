# std

The standard library is the module `std`, built into the compiler. The
prelude names need no import: `Option`, `Some`, `None`, `Result`, `Ok`,
`Err`, `Vec`, `print`, `println`, and the traits `Add`, `Sub`, `Mul`,
`Div`, `Neg`, `Eq`, `Ord`, `Hash`. Anything else is used by path
(`std::print_int(n)`, `std::sort(s)`) or imported by name
(`use std::{Buf, HashMap, sort};`).

What a Rust programmer will miss: there is no `String` (use `[u8]` and
`Buf`), no formatting (`print` takes a `[u8]`; numbers through
`print_int` or `Buf::push_int`; floats through C's `printf`), no file
or stdin reading (call C; iterators: `tachyonc guide iterators`), no `HashSet` (a
`HashMap<K, bool>`), no `Vec` indexing (`get`, `set`, `as_slice()[i]`),
no `Option::map`. Nothing frees itself: call `free()`, usually right
after creating the value with `defer x.free();`.

- `Vec<T>`, `Buf` and `HashMap<K, V>` are handles: copying one shares its
  memory. Pass `&v` (a `*Vec<T>`) to functions that change it.
- A slice from `as_slice()` is valid until the next push or `free`.
- `get`, `set`, slice indexing and `unwrap` are checked: a failure prints
  a message and exits with 101.
- `HashMap` keys need `Hash` and `Eq` (integers, `bool`, `[u8]` have
  them; for a struct key, write `impl Hash`; `==` is structural). `get`
  returns a copy of the value in an `Option`. Iterate with
  `for i in 0..m.slots()` and `key_at(i)`/`value_at(i)`, in slot order
  (not the order of insertion).

```tach
use std::HashMap;

fn main() -> i32 {
    let mut counts: HashMap<[u8], i64> = HashMap::new();
    defer counts.free();
    let words = ["a", "b", "a", "c", "a"];
    for w in words {
        let n = counts.get(w).unwrap_or(0);
        counts.insert(w, n + 1);
    }
    for i in 0..counts.slots() {
        if let Some(k) = counts.key_at(i) {
            print(k);
            print("=");
            std::print_int(counts.value_at(i).unwrap());
            print(" ");
        }
    }
    println("");
    std::print_int(counts.len());
    if counts.contains("b") { println(" has b"); }
    0
}
```
```out
c=1 a=3 b=1
3 has b
```

## The API

Generated from std's source in this compiler: every public item, with
its comment. Methods take `self: *T` (called as `v.push(x)` on a place)
or `self: T` (a copy).

```text
@STD-API@
```
