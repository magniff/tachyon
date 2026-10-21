# Rust -> tachyon

What a Rust programmer reaches for, and what tachyon has instead.
Tachyon is not Rust: its values are passed by convention (`let`,
`inout`, `sink`), not by reference. A Rust habit compiles to an error
more often than to something else, and each error names the fix.

## Text

| Rust | tachyon |
|---|---|
| `&str`, `String`, `&[u8]` | `[u8]`: a pointer and a length; `"abc"` is one; no UTF-8 type |
| `String::new()`, `push_str`, `format!` | `std::Buf` (`Buf::new_in(gpa)`): `push`, `push_str`, `push_int`, `push_fmt(f"..")` (or `push_str(f"..")`), `as_slice`; `format_in(f"..", gpa)` |
| `s.len()` | the same, an `i64` |
| `s == "x"`, `s < t` | the same (std's `Eq` and `Ord` for `[u8]`, by bytes) |
| `&s[1..3]` | `s[1..3]` (checked) |
| `s.as_bytes()[0]`, `b'a'` | `s[0]`, `'a'` (a `u8`) |
| `CString`, `.as_ptr()` | `c"text"` (a `*u8`); a slice is not NUL-terminated |
| `match s { "a" => .. }` | `if s == "a" { .. } else if ...` |
| `x.to_string()`, `s.parse::<i64>()` | `Buf::push_int`; `std::parse_int(s)` (a `Result<i64, ParseIntError>`, 0.15) |
| `s.trim()`, `s.split(',')`, `s.split_whitespace()` | `std::trim(s)`; `std::split_in(s, ',', gpa)`, `std::split_whitespace_in(s, gpa)`: a `Vec<[u8]>` of views of `s` |

```tach
fn main(gpa: Gpa) -> i32 {
    var b = Buf::new_in(gpa);                  // freed at the end of main
    b.push_str("sum=");
    let parts = split_in("40,2", ',', gpa);
    var sum = 0;
    for p in parts.as_slice() {
        sum += parse_int(p).unwrap_or(0);
    }
    b.push_int(sum);
    println(b.as_slice());
    if parse_int("4x").is_err() { println("not a number"); }
    0
}
```
```out
sum=42
not a number
```

## Parameters, ownership, memory

Tachyon has no references to store: a parameter's convention says what
the function does with its argument, and the argument is used as the
value itself.

| Rust | tachyon |
|---|---|
| `x: &T`, `f(&x)` | `x: T` (let, the default: read-only), `f(x)` |
| `x: &mut T`, `f(&mut x)` | `x: inout T`, `f(&x)`: `&` marks only an inout argument |
| `x: T` (the callee owns it) | `x: sink T`, `f(x)` (moves; a plain value is copied) |
| `mut x: T` | `x: sink T` (a sink parameter is the callee's, so mutable) |
| `&self`, `&mut self`, `self`, `mut self` | `self`, `inout self`, `sink self`; calls lend the receiver: `v.push(1)` |
| `let mut x` | `var x` (also `var` in patterns: `Some(var n)`) |
| `let r = &mut x;` | `inout r = &x;`, passed on as `f(&r)` |
| `let r = &x; f(r)` | `f(x)`: a let argument needs no reference |
| `*r = v`, `*n + 1`, `(*p).f` | `r = v`, `n + 1`, `p.f`: an access is used as its value (`*` is only for raw pointers) |
| `&T` / `&mut T` fields | `let T` / `inout T` fields: `struct P { q: inout Query }`, built with `q: &q` |
| `&str`, `&[T]`, `&mut [T]` | `[u8]`, `[T]` (read-only), `inout [T]` (writable) |
| `move \|\| ..` | `sink \|\| ..` |
| `static mut` | `static var` |
| `match &mut x { .. }` | `match &x { .. }`: binds inout accesses |
| moves, `Clone`, `Copy` | the same idea: an owned value (`Vec`, `Buf`, `HashMap`, a struct holding one) moves; `.clone()` copies; plain values copy (no `Copy` derive) |
| `Drop`, RAII | dropped at the end of the scope, last first; `impl Drop for T { fn drop(inout self) }`; `drop(x)` |
| lifetimes `'a`, `fn f<'a>(x: &'a str) -> &'a str` | none: each function's view summary is inferred (`query views NAME`); `#[views(s)]` pins one (`guide views`) |
| the borrow checker | the own pass: `own.moved`, `own.conflict`, `own.escape`... each with `try:` lines (`tachyonc explain own.conflict`) |
| `Box<T>`, `Rc<T>`, `Arc<T>` | none: a `Vec<T>`, an index, or `malloc` in `unsafe` |
| `Vec::new()`, the global allocator | `Vec::new_in(gpa)`: allocation is explicit (0.16); `gpa: Gpa` comes from `fn main(gpa: Gpa)` and is passed down; `arena_scope(gpa, \|a\| ..)` (`guide allocators`) |
| `Option<&T>` | `Option<T>` of a copy, an index, or a one-element view `[T]` |
| `&mut v[i]`, `m.get_mut(&k)` | `&v[i]` to an inout parameter, `v[i].f = x`; `m.get_mut(k)`: an `Option<[V]>`, a view of one element (`a[0].f += 1`) |
| `*m.entry(k).or_insert(0) += 1` | `m.get_or_insert(k, 0)[0] += 1` |
| `std::mem::take(&mut x)`, `replace` | `std::take(&x)`, `std::replace(&x, v)` |
| `Mutex`, threads | none in tachyon (C's threads are C's business) |

Each Rust spelling above is the error `conv.rust`, whose `try:` line
writes the tachyon form (`tachyonc fix --only conventions` rewrites a
whole program). Pass a container to a function that changes it as
`&v` to an `inout` parameter, to one that reads it as `v`; return a new
one by value (the caller owns it):

```tach
fn fill(v: inout Vec<i64>, n: i64) {     // v.push changes the caller's Vec
    for i in 0..n { v.push(i * i); }
}

fn sum(v: Vec<i64>) -> i64 {             // let: reads it in place
    var s = 0;
    for x in v { s += x; }
    s
}

fn main(gpa: Gpa) -> i32 {
    var v: Vec<i64> = Vec::new_in(gpa);
    fill(&v, 4);
    inout r = &v;                        // an inout access in a local: passed on twice
    fill(&r, 1);
    fill(&r, 1);
    std::print_int(v.len() + sum(v));
    println("");
    0
}
```
```out
20
```

`*T` is Rust's `*mut T` / `*const T`: dereferencing it needs `unsafe`,
a parameter too (0.18.1); `&x` passed where a `*T` is wanted gives its
address.

## Errors and Option

| Rust | tachyon |
|---|---|
| `x?` | the same (0.15), on `Option` and `Result`; the error goes through `From` |
| `panic!("msg")`, `unreachable!()` | `panic("msg")`, `unreachable()` (0.17; exit 101), or `return` an error |
| `.map()`, `.and_then()`, `.ok_or()`, `.map_err()` | the same (0.15), and `unwrap_or_else` |
| `.unwrap()`, `.unwrap_or(d)`, `.is_some()`, `.is_none()` | the same |
| `.is_ok()`, `.is_err()`, `.ok()` | the same |
| `assert!(c)`, `debug_assert!` | `if !c { panic("..."); }` |
| `std::process::exit(n)` | `return n;` from `main`, or C's `exit` in `unsafe` |
| `fn main() -> Result<(), E>` | the same (0.15): `Err(e)` prints `Error: ` and `e`'s Debug, exit 1 |

```tach
enum Error { Empty, TooBig(i64) }

fn check(n: i64) -> Result<i64, Error> {
    if n == 0 { return Err(Error::Empty); }
    if n > 100 { return Err(Error::TooBig(n)); }
    Ok(n * 2)
}

fn twice_checked(n: i64) -> Result<i64, Error> {
    let v = check(n)?;                    // Err(e) returns Err(e)
    Ok(v + 1)
}

fn main() -> i32 {
    match twice_checked(500) {
        Ok(v) => std::print_int(v),
        Err(Error::TooBig(n)) => { print("too big: "); std::print_int(n); }
        Err(Error::Empty) => print("empty"),
    }
    println("");
    std::print_int(twice_checked(4).unwrap());
    println("");
    0
}
```
```out
too big: 500
9
```

## Iteration and closures

| Rust | tachyon |
|---|---|
| `for x in v.iter()`, `for x in &v` | the same (0.14), and `for x in v`: a copy of each element |
| `for (i, x) in s.iter().enumerate()` | the same (0.14) |
| `for x in v.iter_mut() { *x += 1 }` | `for i in 0..v.len() { v[i] += 1; }` |
| `.map()`, `.filter()`, `.sum()`, `.collect()` | the same (0.14); `collect_in(gpa)` makes a `Vec` only (`guide iterators`) |
| `\|x\| x + 1`, `move \|\|` | `\|x\| x + 1`, `sink \|\|` (takes what it captures); a `var` is captured inout, the rest by let access or copy (`guide closures`) |
| `impl Fn(i64) -> i64`, `Box<dyn Fn>` | a generic parameter `F: Fn(i64) -> i64`; none as a result |
| `(0..n).rev()` | the same (0.18.1) |
| `.step_by(2)` | `while` with `i += 2` |
| `sort()`, `sort_by(\|a, b\| ...)` | `std::sort(s)` (`T: Ord`; not stable); `v.sort_by(\|a, b\| b.cmp(a))` (0.14; `a`, `b`: let `T`) |
| `v.sort_by_key(\|x\| x.k)`, `v.retain(..)`, `v.contains(&x)`, `v.first()` | the same on a `Vec` (0.18.1; `sort_by_key` is stable); `contains(x)` takes x by value |
| `BinaryHeap<T>`; a min-heap `BinaryHeap<Reverse<T>>` | `BinaryHeap<T>`; `MinHeap<T>`, no `Reverse` (0.18.1, `guide std#heaps-priority-queues`) |

A function value is `fn(A) -> R`, a plain function, no environment.
Its parameters have conventions (`fn(inout Sum, i64)`); a
function with `*T` parameters is a value like any other (an `unsafe fn`
as a value is unsafe):

```tach
struct Sum { total: i64 }

fn add(s: inout Sum, x: i64) { s.total += x; }

fn each(xs: [i64], f: fn(inout Sum, i64), s: inout Sum) {
    for x in xs { f(&s, x); }
}

fn square(x: i64) -> i64 { x * x }

fn map_sum(xs: [i64], f: fn(i64) -> i64) -> i64 {
    var t = 0;
    for x in xs { t += f(x); }
    t
}

fn main() -> i32 {
    var s = Sum { total: 0 };
    let xs = [1, 2, 3];
    each(xs[..], add, &s);
    std::print_int(s.total + map_sum(xs[..], square));
    println("");
    0
}
```
```out
20
```

## Types and numbers

| Rust | tachyon |
|---|---|
| `usize` for lengths and indices | `i64` (`s.len()`, `v.len()`); indexing takes any integer type |
| implicit widening `i32` -> `i64` | the same (0.15), lossless only; `i64::from(x)`; narrowing is `x as i32` |
| `i32::MAX`, `u8::MIN` | the same (0.15), for the integer types |
| overflow: panic in debug, wrap in release | always wraps (two's complement) |
| `x / 0` panics | `x / 0 == 0`, `x % 0 == x` |
| `!x` (bitwise not) | `~x` |
| `x.pow(n)`, `x.abs()`, `f.sqrt()` | write it, or C's `pow`, `labs`, `sqrt` (`import "math.h" as m;`) |
| `char`, a non-ASCII `char` literal | `u8`, ASCII literals only; `"\u{e9}"` in strings is UTF-8 bytes |
| `()` | `()` |
| `!` (never) | `!`: `fn fail() -> ! { ... }` |
| `#[derive(PartialEq, Eq)]` | `==` is structural for structs, enums, tuples, arrays; `Vec`, `Buf`, `HashMap` by contents (0.15); `#[derive(Eq)]` checks it |
| `#[derive(Clone, Copy, Debug, Default, Hash)]` | `#[derive(Clone, Debug, Hash, Ord)]` (0.15); every value copies, no `Copy`, no `Default` |
| `impl Display`, `{:?}` | `impl Display for T { fn fmt(self, f: inout Fmt) {..} }`, `{x:?}` (0.15, `guide formatting`) |
| `impl From<A> for B`, `.into()` | the same (0.15, `guide conversions`) |
| `type A = B;` | the same (`type Pair<T> = (T, T);` too) |
| `const fn` | none; `const` items take constant expressions |

## Syntax

| Rust | tachyon |
|---|---|
| `fn f(&self)`, `&mut self`, `self` | `fn f(self)`, `fn f(inout self)`, `fn f(sink self)`; `Self` works (`self: *T` is the raw pointer, 0.18.1) |
| `let mut x = 0;` | `var x = 0;` |
| `'a: loop { break 'a; }` | `a: loop { break :a; }` |
| `let x;` then assign | `let x = ...;` always |
| `let Some(x) = o else { .. };` | the same (0.18.1); the block must leave (`return`, `break`, `continue`, `panic`) |
| `P { x, y }` shorthand, `..base` | the shorthand (0.15); no `..base` |
| `where T: Ord` | `<T: Ord>` |
| `pub(crate)`, `pub(super)` | `pub`, or nothing (private to the module and its children) |
| `fn` inside a `fn` | items only at module level |
| `macro_rules!`, `println!`, `vec!` | none: `println(f"{x}")` (0.15) |
| default arguments (none in Rust) | `fn f(a: i64, b: i64 = 2)`, `f(1, b: 3)` (0.15) |
| `impl<T> Trait for Vec<T>` | the same (one impl per trait and type) |
| `dyn Trait`, `impl Trait` in argument position | generics: `fn f<T: Trait>(x: T)` |
| `#[test]`, proptest, cargo-fuzz | `#[test]`, `#[property]`, `#[fuzz]`, run by `tachyonc test` and `tachyonc fuzz` (0.18; guide testing) |
| `assert!`, `debug_assert!`, contracts crates | `assert(c)`, `assert_eq(a, b)`; `requires`/`ensures` clauses (0.18; guide contracts) |
| `use a::b::*;` | `use a::b::{c, d};` |
| `x as T` | the same; `bool as i64` works, an integer to an enum is checked |
| `if let ... else if let ...`, `while let` | the same |
| `match` guards, `a \| b`, `1..=9` | the same; no `x @ pat`, no slice patterns, no string patterns |

## Modules and crates

| Rust | tachyon |
|---|---|
| `mod m;` | the same: `m.tach` or `m/mod.tach` next to the file |
| `use crate::a::b;`, `super::`, `self::` | the same |
| `extern crate`, Cargo dependencies | none: one program from its files; C through headers |
| `pub use` | the same |
| `std::collections::HashMap` | `std::HashMap` |
| `std::io::stdin().read_line(&mut s)` | `std::read_line(&buf)`: the line without its `'\n'`; `Ok(false)` at the end of input |
| `io::read_to_string(io::stdin())` | `std::read_stdin_in(gpa)`, a `Result<Buf, IoError>`; `std::Scanner` for its tokens, numbers and lines |
| `std::env::args()` | `fn main(argc: i32, argv: **u8) -> i32` |

## unsafe and C

| Rust | tachyon |
|---|---|
| `unsafe { }`, `unsafe fn` | the same |
| `extern "C" { fn f(); }` | the same; or `import "stdio.h" as c;` then `c::printf` |
| `#[repr(C)]`, `#[repr(u8)]` | the same; also `packed`, `align(N)` |
| `extern "C" fn cb()` | the same; a plain `fn` is not a C callback |
| `std::ptr::null()` | `0 as *T` |
| `p.add(i)`, `p.offset(i)` | `p[i]`, `&p[i]` (unsafe); no pointer arithmetic |
| `std::mem::size_of::<T>()` | `size_of(T)`, `align_of(T)` |
| `libc::malloc` | `extern "C" { fn malloc(n: u64) -> *u8; }` or `import "stdlib.h" as c;` |
