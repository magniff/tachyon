# Rust -> tachyon

What a Rust programmer reaches for, and what tachyon has instead.
Tachyon looks like Rust, so the Rust habit compiles to an error more
often than to something else; each error names the fix.

## Text

| Rust | tachyon |
|---|---|
| `&str`, `String`, `&[u8]` | `[u8]`: a pointer and a length; `"abc"` is one; no UTF-8 type |
| `String::new()`, `push_str`, `format!` | `std::Buf`: `push`, `push_str`, `push_int`, `push_fmt(f"..")`, `as_slice`; `format(f"..")` (0.15) |
| `s.len()` | `s.len` (a field, `i64`) |
| `s == "x"`, `s < t` | the same (std's `Eq` and `Ord` for `[u8]`, by bytes) |
| `&s[1..3]` | `s[1..3]` (checked) |
| `s.as_bytes()[0]`, `b'a'` | `s[0]`, `'a'` (a `u8`) |
| `CString`, `.as_ptr()` | `c"text"` (a `*u8`); a slice is not NUL-terminated |
| `match s { "a" => .. }` | `if s == "a" { .. } else if ...` |
| `x.to_string()`, `s.parse::<i64>()` | `Buf::push_int`; `std::parse_int(s)` (a `Result<i64, ParseIntError>`, 0.15) |
| `s.trim()`, `s.split(',')`, `s.split_whitespace()` | `std::trim(s)`; `std::split(s, ',')`, `std::split_whitespace(s)`: a `Vec<[u8]>` of views of `s` (free it) |

```tach
use std::{Buf, parse_int, split};

fn main() -> i32 {
    let mut b = Buf::new();
    defer b.free();
    b.push_str("sum=");
    let mut parts = split("40,2", ',');
    defer parts.free();
    let mut sum = 0;
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

## References, ownership, memory

| Rust | tachyon |
|---|---|
| `&T`, `&mut T` | `*T`; `&x` is the address of `x`; no lifetimes; `x` need not be `mut` to take `&x` |
| `*r` on a reference | `*p`; safe on a borrow (`&place`, a pointer parameter), else `unsafe` |
| `r.field` through a reference | `p.f` (auto-deref, one level) |
| moves, `Clone`, `Copy` | every value is copied by `=` and by calls (bitwise); no moves |
| `Drop`, RAII, scope guards | `defer stmt;` runs when the block exits; std types have `free()` |
| `Box<T>`, `Rc<T>`, `Arc<T>` | none: a `Vec<T>`, or `malloc` in `unsafe` |
| `Option<&T>` | `Option<*T>`, or an index |
| `&mut v[i]`, `m.get_mut(&k)` | `v.as_slice()[i].f = x`; `m.get_mut(k)`: an `Option<[V]>`, a view of one element (`a[0].f += 1`) |
| `*m.entry(k).or_insert(0) += 1` | `m.get_or_insert(k, 0)[0] += 1` |
| `Mutex`, threads | none in tachyon (C's threads are C's business) |

A `Vec`, `Buf` or `HashMap` value is a handle (a pointer, a length, a
capacity). Copying it shares the memory; a push through one copy is not
seen by the other's length. Pass `&v`:

```tach
fn fill(v: *Vec<i64>, n: i64) {          // v.push works through the pointer
    for i in 0..n { v.push(i * i); }
}

fn main() -> i32 {
    let mut v: Vec<i64> = Vec::new();
    defer v.free();
    fill(&v, 4);
    std::print_int(v.len() + v.get(3));
    println("");
    0
}
```
```out
13
```

## Errors and Option

| Rust | tachyon |
|---|---|
| `x?` | the same (0.15), on `Option` and `Result`; the error goes through `From` |
| `panic!("msg")` | `unsafe { std::panic(c"msg") }` (exit 101), or `return` an error |
| `.map()`, `.and_then()`, `.ok_or()`, `.map_err()` | the same (0.15), and `unwrap_or_else` |
| `.unwrap()`, `.unwrap_or(d)`, `.is_some()`, `.is_none()` | the same |
| `.is_ok()`, `.is_err()`, `.ok()` | the same |
| `assert!(c)`, `debug_assert!` | `if !c { unsafe { std::panic(c"...") } }` |
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
| `for x in v.iter_mut() { *x += 1 }` | `for i in 0..s.len { s[i] += 1; }` |
| `.map()`, `.filter()`, `.sum()`, `.collect()` | the same (0.14); `collect()` makes a `Vec` only (`guide iterators`) |
| `\|x\| x + 1`, `move \|\|` | the same (0.14); a `let mut` is captured by reference, the rest by value (`guide closures`) |
| `impl Fn(i64) -> i64`, `Box<dyn Fn>` | a generic parameter `F: Fn(i64) -> i64`; none as a result |
| `(0..n).rev()` | `let mut i = n; while i > 0 { i -= 1; ... }` |
| `.step_by(2)` | `while` with `i += 2` |
| `sort()`, `sort_by(\|a, b\| ...)` | `std::sort(s)` (`T: Ord`; not stable); `v.sort_by(\|a, b\| b.cmp(a))` (0.14; `a`, `b`: `*T`) |

A function value is `fn(A) -> R`, a plain function, no environment.
Using a function with pointer parameters as a value, and calling it
with a pointer, is `unsafe` (its callee is not checked):

```tach
struct Sum { total: i64 }

fn add(s: *Sum, x: i64) { s.total += x; }

fn each(xs: [i64], f: fn(*Sum, i64), s: *Sum) {
    for x in xs { unsafe { f(s, x); } }
}

fn square(x: i64) -> i64 { x * x }

fn map_sum(xs: [i64], f: fn(i64) -> i64) -> i64 {
    let mut t = 0;
    for x in xs { t += f(x); }
    t
}

fn main() -> i32 {
    let mut s = Sum { total: 0 };
    let xs = [1, 2, 3];
    unsafe { each(xs[..], add, &s); }
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
| `usize` for lengths and indices | `i64` (`s.len`, `v.len()`); indexing takes any integer type |
| implicit widening `i32` -> `i64` | the same (0.15), lossless only; `i64::from(x)`; narrowing is `x as i32` |
| `i32::MAX`, `u8::MIN` | the same (0.15), for the integer types |
| overflow: panic in debug, wrap in release | always wraps (two's complement) |
| `x / 0` panics | `x / 0 == 0`, `x % 0 == x` |
| `!x` (bitwise not) | `~x` |
| `x.pow(n)`, `x.abs()`, `f.sqrt()` | write it, or C's `pow`, `labs`, `sqrt` (`import "math.h" as m;`) |
| `char`, a non-ASCII `char` literal | `u8`, ASCII literals only; `"\u{e9}"` in strings is UTF-8 bytes |
| `()` | `()` |
| `!` (never) | `!`: `fn fail() -> ! { ... }` |
| `#[derive(PartialEq, Eq)]` | `==` is structural for structs, enums, tuples, arrays; `#[derive(Eq)]` checks it |
| `#[derive(Clone, Copy, Debug, Default, Hash)]` | `#[derive(Clone, Debug, Hash, Ord)]` (0.15); every value copies, no `Copy`, no `Default` |
| `impl Display`, `{:?}` | `impl Display for T { fn fmt(self: *T, f: *Fmt) {..} }`, `{x:?}` (0.15, `guide formatting`) |
| `impl From<A> for B`, `.into()` | the same (0.15, `guide conversions`) |
| `type A = B;` | the same (`type Pair<T> = (T, T);` too) |
| `const fn` | none; `const` items take constant expressions |

## Syntax

| Rust | tachyon |
|---|---|
| `fn f(&self)`, `&mut self`, `self` | `fn f(self: *T)`, `fn f(self: *T)`, `fn f(self: T)`; `Self` works |
| `'a: loop { break 'a; }` | `a: loop { break :a; }` |
| `let x;` then assign | `let x = ...;` always |
| `let Some(x) = o else { .. };` | `let x = match o { Some(x) => x, None => return 1 };` |
| `P { x, y }` shorthand, `..base` | the shorthand (0.15); no `..base` |
| `where T: Ord` | `<T: Ord>` |
| `pub(crate)`, `pub(super)` | `pub`, or nothing (private to the module and its children) |
| `fn` inside a `fn` | items only at module level |
| `macro_rules!`, `println!`, `vec!`, `assert!` | none: `println(f"{x}")` (0.15) |
| default arguments (none in Rust) | `fn f(a: i64, b: i64 = 2)`, `f(1, b: 3)` (0.15) |
| `impl<T> Trait for Vec<T>` | the same (one impl per trait and type) |
| `dyn Trait`, `impl Trait` in argument position | generics: `fn f<T: Trait>(x: T)` |
| `#[test]` | none yet (0.18); write a program and check its output |
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
| `io::read_to_string(io::stdin())` | `std::read_stdin()`, a `Result<Buf, IoError>`; `std::Scanner` for its tokens, numbers and lines |
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
