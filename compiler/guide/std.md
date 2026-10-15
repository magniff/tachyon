# std

The standard library is the module `std`, built into the compiler. The
prelude names need no import: `Option`, `Some`, `None`, `Result`, `Ok`,
`Err`, `Vec`, `print`, `println`, `eprint`, `eprintln`, `format`,
`format_in`, the allocators (`Gpa`, `Allocator`, `Arena`, `ScopedArena`,
`arena_scope`), the traits `Add`, `Sub`, `Mul`, `Div`, `Neg`, `Eq`,
`Ord`, `Hash`, `Iterator`, `Display`, `Debug`, `Clone`, `From`, `Into`,
and (0.17) `Buf`, `HashMap`, `read_line`, `read_stdin_in`, `Scanner`,
`parse_int`, `trim`, `split_in`, `split_whitespace_in`, `sort`,
`sort_by`, `cmp_of`, `eq_of`, `Fmt`, `panic(msg)` and `unreachable()`.
Anything else is used by path (`std::print_int(n)`) or imported by name
(`use std::{IoError, is_digit};`).

What a Rust programmer will miss: there is no `String` (use `[u8]` and
`Buf`), no file reading (call C; iterators: `tachyonc guide
iterators`), no `HashSet` (a `HashMap<K, bool>`). A `Vec` (and a `Buf`) indexes as
its slice: `v[i]`, `v[i] = x`, `v[a..b]` (0.17), checked. Formatting is 0.15's f-strings,
`println(f"{x:>4}")` (`tachyonc guide formatting`); errors are enums in a
`Result` (`tachyonc guide conversions`). Nothing frees itself: call `free()`, usually right
after creating the value with `defer x.free();`.

- `Vec<T>`, `Buf` and `HashMap<K, V>` are handles: copying one shares its
  memory. Pass `&v` (a `*Vec<T>`) to functions that change it.
- A slice from `as_slice()` is valid until the next push or `free`.
- `get`, `set`, slice indexing and `unwrap` are checked: a failure prints
  a message and exits with 101.
- `HashMap` keys need `Hash` and `Eq` (integers, `bool`, `[u8]` have
  them; for a struct key, write `impl Hash`; `==` is structural). `==` on
  Vecs, Bufs and maps compares their contents (0.15). `get`
  returns a copy of the value in an `Option`. Iterate with
  `for i in 0..m.slots()` and `key_at(i)`/`value_at(i)`, in slot order
  (not the order of insertion).
- To change a value in place, `get_mut(k)` and `get_or_insert(k, d)`
  give a view of one element (`[V]`; `a[0]` is the value), safe to use
  until the map's next insert, remove or free, like `as_slice()`:
  `counts.get_or_insert(word, 0)[0] += 1;` counts.
- `sort(s)` sorts a slice in place by `Ord` (an introsort: O(n log n),
  not stable).

```tach
fn main(gpa: Gpa) -> i32 {
    let mut counts: HashMap<[u8], i64> = HashMap::new_in(gpa);
    defer counts.free();
    let words = ["a", "b", "a", "c", "a"];
    for w in words {
        counts.get_or_insert(w, 0)[0] += 1;
    }
    if let Some(n) = counts.get_mut("c") {
        n[0] *= 10;
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
    if counts.contains_key("b") { println(" has b"); }
    0
}
```
```out
c=10 a=3 b=1
3 has b
```

## Input

`read_line(&buf)` reads stdin a line at a time: the line goes into the
`Buf` without its `'\n'`, and the result is `Ok(false)` at the end of
input (an empty line is `Ok(true)` with an empty `buf`; a read error is
`Err(IoError::Read)`). `read_stdin_in(gpa)` returns all of stdin that is left
(a `Result<Buf, IoError>`); the two share a buffer, so they mix, but not with
C's `getchar` or `scanf`. A `Scanner` reads a text's tokens
(`next_token`; `next_int`, a `Result<i64, ScanError>`) and lines
(`next_line`); `parse_int` (a `Result<i64, ParseIntError>`),
`split_in`, `split_whitespace_in` and `trim` work on any `[u8]`. An Option
means absence (the end, nothing found), a Result a failure: `.ok()`
turns one into the other, `.unwrap_or(x)` gives a default. What they
return are views of the text: keep the `Buf` until done with them. The
next `read_line` overwrites the line, so to keep a part of it (a map's
key), read all of stdin and take lines with `Scanner::next_line`.

```tach
fn main(gpa: Gpa) -> i32 {
    let mut line = Buf::new_in(gpa);
    defer line.free();
    read_line(&line).unwrap();            // the header: "n m"
    let mut header = split_whitespace_in(line.as_slice(), gpa);
    defer header.free();
    let n = parse_int(header.get(0)).unwrap();
    let m = parse_int(header.get(1)).unwrap_or(0);
    let mut rest = read_stdin_in(gpa).unwrap(); // everything after it
    defer rest.free();
    let mut sc = Scanner::new(rest.as_slice());
    let mut sum = 0;
    for _ in 0..n {
        sum += sc.next_int().unwrap();
    }
    std::print_int(sum * m);
    print(" [");
    print(sc.next_line().unwrap());       // the rest of that line
    println("]");
    while let Some(l) = sc.next_line() {  // the lines after it
        print(l);
        println("|");
    }
    0
}
```
```in
3 2
10 20 30 tail
x y

last
```
```out
120 [ tail]
x y|
|
last|
```

## The API

Generated from std's source in this compiler: every public item a
program uses, one line each. Methods take `self: *Self` (called as
`v.push(x)` on a place) or `self: Self` (a copy). Each item with its
comment: `tachyonc guide std#every-item`; one item's source: `tachyonc
query show std::Scanner::next_line`.

```text
@STD-API@
```
@STD-API-DOC@
