# std

## The most used

std's most used items (0.17's evals: by how many of 362 sessions used
each), most used first. `v` is a `Vec`, `b` a `Buf`, `m` a `HashMap`,
`sc` a `Scanner`, `o` an `Option` or `Result`. All of these are in the
prelude: no `use` line.

```text
v.push(x: T)                     Vec; Buf: b.push(byte: u8)
v.as_slice() -> [T]              Vec; Buf: -> [u8]
Vec::new_in(gpa) -> Vec<T>       var v: Vec<i64> = Vec::new_in(gpa);
v.len() -> i64                   Vec, Buf, HashMap, slices
v.get(i: i64) -> T               checked, as v[i]; m.get(k) -> Option<V>
b.push_str(s: [u8])
Buf::new_in(gpa) -> Buf          text you build (there is no String)
o.unwrap() -> T                  Option, Result; o.is_some(), o.is_none()
read_stdin_in(gpa) -> Result<Buf, IoError>    all of stdin
print(x), println(x)             any Display; f"{x} {v:?} {v[i]} {s.len()}"
b.push_int(v: i64)
v.set(i: i64, x: T)              checked, as v[i] = x
Scanner::new(text: [u8]) -> Scanner
sc.next_int() -> Result<i64, ScanError>
o.unwrap_or(x: T) -> T           Option, Result
v.clear()                        Vec, Buf
v.sort()                         by Ord: numbers, [u8], tuples, #[derive(Eq, Ord)]
v.sort_by(|a, b| a.x - b.x)      a, b: let T (a - b); < 0: a first; cmp_of(a, b)
HashMap::new_in(gpa) -> HashMap<K, V>
v.pop() -> Option<T>             v.remove(i: i64) -> T; m.remove(k) -> Option<V>
Vec::filled_in(n: i64, x: T, gpa) -> Vec<T>
sort(s: inout [T])               a slice in place: sort(&v[a..b]), v.sort()
for (k, x) in m.iter()           in slot order (not insertion order)
m.get_or_insert(k: K, d: V) -> inout [V]   m.get_or_insert(w, 0)[0] += 1;
sc.next_token() -> Option<[u8]>  sc.next_line() -> Option<[u8]>
parse_int(s: [u8]) -> Result<i64, ParseIntError>
m.insert(k: K, x: V) -> Option<V>     Vec: v.insert(i: i64, x: T)
std::print_int(v: i64)           std::is_digit(b: u8) -> bool
trim(s: [u8]) -> [u8]
read_line(&b) -> Result<bool, IoError>    Ok(false) at the end of input
split_whitespace_in(s: [u8], gpa) -> Vec<[u8]>
split_in(s: [u8], sep: u8, gpa) -> Vec<[u8]>
v.swap(i: i64, j: i64)           m.contains_key(k: K) -> bool
MinHeap::new_in(gpa), h.push(x), h.pop() -> Option<T>   a priority queue, smallest first; BinaryHeap: largest
```

`[u8]` compares with `==`, `<` and `cmp_of` (`'a'` is a `u8`); `for b
in s` yields its bytes. A slice from `as_slice()`, `trim`, `split_in` or
a `Scanner` views its text: keep the `Buf`, and push to it only when
done with them (`guide std#overview`).

An allocator (`gpa`, from `fn main(gpa: Gpa)`, passed down as a
parameter) goes only to constructors and `_in` functions; methods
(`push`, `insert`, `clone`, `sort`) use the container's own. Not in
std: `Box`. (0.20) Text: `str`, `String` and Rust's methods (`guide
text`); files, env, processes: `guide io`. (0.20)
`std::collections::HashSet`: `insert` (false if present), `contains`,
`remove`, `iter()`. `BTreeMap<K, V>` and `BTreeSet<T>`
(`std::BTreeMap`, `K: Ord`) keep their keys in order: `iter()` and
`range(lo, hi)` (`[lo, hi)`; `range_inclusive`) go from the smallest,
`next_back()` from the largest; `first_key_value`, `pop_first`,
`pop_last`.

@PAGE-END@ More, a section at a time: `volec guide std#the-api` (every item, a line each), `std#overview` (ownership, views, HashMap), `std#input` (reading stdin), `std#heaps` (priority queues); one item: `volec guide --find NAME`; all of it: `volec guide std --whole`.

## Overview

The standard library is the module `std`, built into the compiler. The
prelude names need no import: `Option`, `Some`, `None`, `Result`, `Ok`,
`Err`, `Vec`, `print`, `println`, `eprint`, `eprintln`, `format`,
`format_in`, the allocators (`Gpa`, `Allocator`, `Arena`, `ScopedArena`,
`arena_scope`), the traits `Add`, `Sub`, `Mul`, `Div`, `Neg`, `Eq`,
`Ord`, `Hash`, `Iterator`, `Display`, `Debug`, `Clone`, `From`, `Into`,
and (0.17) `Buf`, `HashMap`, `read_line`, `read_stdin_in`, `Scanner`,
`parse_int`, `trim`, `split_in`, `split_whitespace_in`, `sort`,
`sort_by`, `sort_stable`, `sort_stable_by` (and their `_in` forms),
`cmp_of`, `eq_of`, `Fmt`, `panic(msg)` and `unreachable()`; (0.18.1)
the heaps `BinaryHeap` and `MinHeap`.
Anything else is used by path (`std::print_int(n)`) or imported by name
(`use std::{IoError, is_digit};`).

What a Rust programmer will miss: there is no `String` (use `[u8]` and
`Buf`), no file reading (call C; iterators: `volec guide
iterators`). A `Vec` (and a `Buf`) indexes as
its slice: `v[i]`, `v[i] = x`, `v[a..b]` (0.17), checked. Formatting is 0.15's f-strings,
`println(f"{x:>4}")` (`volec guide formatting`); errors are enums in a
`Result` (`volec guide conversions`). A `Vec`, `Buf` or `HashMap` is
dropped (freed) at the end of its scope (0.17): no `free` calls.

- `Vec<T>`, `Buf` and `HashMap<K, V>` own their memory: `let w = v;`
  moves it, `.clone()` copies. A function that reads one takes it let
  (`v: Vec<T>`, called `f(v)`: borrowed, nothing moves), one that
  changes it `v: inout Vec<T>` (called `f(&v)`), one that keeps it `v:
  sink Vec<T>` (`f(v)` moves it).
- A slice from `as_slice()` views the container: the checker rejects its
  use after the next push, `free` or drop (`volec guide views`).
- `get`, `set`, slice indexing and `unwrap` are checked: a failure prints
  a message and exits with 101.
- `HashMap` keys need `Hash` and `Eq` (integers, `bool`, `[u8]` have
  them; for a struct key, write `impl Hash`; `==` is structural). `==` on
  Vecs, Bufs and maps compares their contents (0.15). `get`
  returns a copy of the value in an `Option`. Iterate with
  `for i in 0..m.slots()` and `key_at(i)`/`value_at(i)`, in slot order
  (not the order of insertion).
- (0.20) A `HashMap` is a Swiss table (hashbrown's design), and std's
  hashes are foldhash with fixed seeds (`std::hash::FixedState`): the
  slot order is the same in every run and on every target. Not proof
  against keys an attacker chooses: `std::hash::SipHashState::new()`
  hashes with SipHash-1-3 and random keys, as Rust's default does.
- To change a value in place, `get_mut(k)` and `get_or_insert(k, d)`
  give a writable view of one element (`inout [V]`; `a[0]` is the value),
  safe to use until the map's next insert, remove or free, like
  `as_mut_slice()`: Rust's `*m.entry(k).or_insert(0) += 1` is
  `counts.get_or_insert(word, 0)[0] += 1;`.
- `sort(s)` sorts a slice in place by `Ord` (an introsort: O(n log n),
  not stable); `v.sort()`, `s.sort()` too.
- (0.17) `sort(&a[..])`, `sort(v.as_mut_slice())`; `v.free()`
  frees now and leaves `v` empty; `v.take()` moves the contents out,
  leaving an empty container with the same allocator;
  `std::take(&x)`, `std::replace(&x, v)`, `std::swap(&a, &b)`;
  `v.iter_ref()` yields let accesses of the elements.

```tach
fn main(gpa: Gpa) -> i32 {
    var counts: HashMap<[u8], i64> = HashMap::new_in(gpa);
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
b=1 a=3 c=10
3 has b
```

## Heaps: priority queues

`BinaryHeap<T>` and `MinHeap<T>` (`T: Ord`; tuples compare field by
field) are priority queues: `push(x)`, `pop() -> Option<T>`, `peek()`,
`len()`, `from_vec(v)`, `into_sorted_vec()`; a BinaryHeap pops the
largest first, a MinHeap the smallest (Rust's `BinaryHeap<Reverse<T>>`:
vole has no tuple structs, so no `Reverse(x)`). Dijkstra with a
MinHeap: `volec guide --find dijkstra`.

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
    var line = Buf::new_in(gpa);
    read_line(&line).unwrap();            // the header: "n m"
    let header = split_whitespace_in(line.as_slice(), gpa);
    let n = parse_int(header.get(0)).unwrap();
    let m = parse_int(header.get(1)).unwrap_or(0);
    let rest = read_stdin_in(gpa).unwrap(); // everything after it
    var sc = Scanner::new(rest.as_slice());
    var sum = 0;
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
program uses, one line each, in std's source spelling (`self` reads;
`inout self` changes, called as `v.push(x)` on a `var`; `sink self`
takes the value). Each item with its
comment: `volec guide std#every-item`; one item's source: `volec
query show std::Scanner::next_line`.

```text
@STD-API@
```
@STD-API-DOC@
