# The tachyon guide (tachyon 0.13)

Tachyon is a compiled systems language. Its syntax is close to Rust's,
its model close to C's: structs, enums with exhaustive `match`, traits
and generics (monomorphized), modules, checked slices, raw pointers,
`unsafe`, exact C interop. There is no borrow checker, no lifetimes, no
destructors, no macros. Closures and iterators are new in 0.14; `?`,
f-strings, widening, `#[derive]`, named and default arguments in 0.15.
Safe code has no undefined behaviour. This text matches this compiler;
`tachyonc guide TOPIC` gives the detail (topics at the end).

## Build and run

```sh
tachyonc hello.tach -o hello && ./hello   # executable (cc links it)
tachyonc hello.tach -o hello.o            # object; `-o x.s`: assembly
tachyonc check hello.tach                 # errors only, one per line
```

```tach
fn main() -> i32 {
    println("hello");
    0
}
```
```out
hello
```

`main` returns the exit status (`fn main()` with no result is 0);
`fn main(argc: i32, argv: **u8) -> i32` takes the arguments. Several
files on the command line make one program; `mod name;` loads
`name.tach`.

## Rust habits and what tachyon has instead

| Rust | tachyon |
|---|---|
| `String`, `&str` | `[u8]`, a byte slice: `"text"` is a `[u8]`; build text with `std::Buf`; `c"text"` is a NUL-terminated `*u8` for C |
| `&T`, `&mut T`, `Box<T>` | `*T`, one raw pointer type; `&x` takes an address; no lifetimes, no borrow checker |
| `fn f(&self)`, `fn f(&mut self)` | `fn f(self: *T)` (may write through it); `fn f(self: T)` takes a copy |
| `use m::*;` | not allowed: `use m::{a, b};`, or the path `m::a` |
| `println!("{}", x)`, `format!` | no macros: `println(f"x = {x:>4} {v:?}")`, `format(f"..")` (a `Buf`) (0.15, `guide formatting`) |
| `v[i]` on a `Vec` | `v.get(i)`, `v.set(i, x)`, `v.as_slice()[i]` |
| closures, `.iter().map()` | the same (0.14): `\|x\| x + k`, `v.iter().map(\|x\| x * 2).sum()`; `F: Fn(i64) -> i64` bounds; no `dyn Fn`, `FnOnce`, `iter_mut` (`guide closures`, `guide iterators`) |
| `x?` | the same on `Option` and `Result` (0.15); `impl From<E> for F` converts the error; `main` may return `Result<(), E>` (`guide conversions`) |
| `impl Trait for T`, `T: Trait` | the same; `type Item;` associated types (0.14); `#[derive(Eq, Ord, Hash, Debug, Clone)]` (0.15); no `dyn`, `where`, supertraits |
| `Drop`, RAII | none: call `free()`, usually `defer v.free();` |
| `'outer: loop`, `break 'outer` | `outer: loop`, `break :outer`, `continue :outer` |
| `!x` on integers | `~x`; `!` is for `bool` only |
| `i64::MAX`, `x.abs()`, `x.pow(2)` | `i64::MAX`, `u8::MIN` the same (0.15); no methods on numbers: write the expression, or call C |
| `x as usize` to index | lengths and indices are `i64` (`s.len`); any integer indexes |
| overflow panics, `/ 0` panics | integers wrap; `x / 0 == 0`, `x % 0 == x`; no panic |
| `match s { "add" => ... }` | strings are not patterns: `if s == "add" { ... }` |
| `char` | none: `'a'` is a `u8` (one ASCII byte) |
| `P { x, ..base }` | `P { x, y }` (0.15); no `..base`: `P { x, y: base.y }` |
| `let x;` | every `let` has a value |
| no default or named arguments | `fn f(a: i64, b: i64 = 2)`, `f(1, b: 3)` (0.15): named ones last, in order |
| implicit `i32` -> `i64` | the same: lossless widening (0.15); `a as i32` narrows; `From`/`Into` |

The prelude, in every module without `use`: `Option`, `Some`, `None`,
`Result`, `Ok`, `Err`, `Vec`, `print`, `println`, `eprint`, `eprintln`,
`format`, and the traits `Add`, `Sub`, `Mul`, `Div`, `Neg`, `Eq`, `Ord`,
`Hash`, `Display`, `Debug`, `Clone`, `From`, `Into`. The rest of std is used
by path (`std::print_int(n)`) or imported (`use std::{Buf, HashMap};`).
Calling C or an `unsafe fn`, and dereferencing or indexing a raw
pointer, are allowed only in `unsafe { }` (`tachyonc guide rust`: the
full list).

## Values and types

```tach
let a = 42;               // i64: an integer literal is i64 unless the context says
let b: u8 = 255;          // i8 i16 i32 i64 u8 u16 u32 u64 isize usize
let c = 3u32;             // suffixes; 1_000, 0xff, 0b1010
let d = 2.5;              // f64; 2.5f32 is f32
let e = 'A';              // u8: a byte, ASCII only
let f = true;             // bool
let s = "bytes";          // [u8]: s.len (an i64 field, not a method), s[0], s[1..3]
let p = c"for C";         // *u8, NUL-terminated
let t = (1, "two");       // a tuple: t.0, t.1
let arr = [0; 8];         // [i64; 8]; also [1, 2, 3]; arr[i] is checked
let mut n = a as i32;     // `as` converts numbers; nothing converts implicitly
n += c as i32 + b as i32 + e as i32;
```

Bindings are immutable unless `mut`. Shadowing (`let x = x + 1;`) is
allowed. `const N: i64 = 10;` and `static mut COUNT: i64 = 0;` are items
(statics are safe to use: there are no threads).

## Functions and control flow

```tach
fn classify(n: i64) -> [u8] {
    if n < 0 { "negative" } else if n == 0 { "zero" } else { "positive" }
}

fn main() -> i32 {
    let mut total = 0;
    for i in 0..10 {              // 0..10 and 0..=9: ranges exist only in `for`
        if i % 2 == 0 { continue; }
        total += i;
    }
    let mut k = 0;
    while k < 3 { k += 1; }
    let found = loop {            // loop's value comes from `break value`
        k += 1;
        if k * k > 50 { break k; }
    };
    outer: for i in 0..5 {        // a label: `name:`, then `break :name`
        for j in 0..5 {
            if i * j == 6 { break :outer; }
        }
    }
    println(classify(total - found));
    0
}
```
```out
positive
```

The last expression of a block, without `;`, is its value; `if`, `match`,
`loop` and blocks are expressions. There are no nested functions.
Trailing parameters may have defaults; named arguments follow the
positional ones, in parameter order (0.15):

```tach
fn greet(name: [u8], times: i64 = 1, sep: [u8] = " ") {
    for _ in 0..times { print(f"hi {name}{sep}"); }
    println("");
}

fn main() -> i32 {
    greet("ann");
    greet("bob", times: 2, sep: "! ");
    0
}
```
```out
hi ann
hi bob! hi bob!
```

## Structs, enums, match, methods

```tach
struct Point { x: i64, y: i64 }

enum Shape { Circle(Point, i64), Rect(Point, Point), Empty }

impl Point {
    fn new(x: i64, y: i64) -> Point { Point { x: x, y: y } }   // Point::new(1, 2)
    fn shift(self: *Point, dx: i64) { self.x += dx; }           // writes through self
    fn sum(self: Point) -> i64 { self.x + self.y }              // a copy
}

fn area(s: Shape) -> i64 {
    match s {
        Shape::Circle(_, r) => 3 * r * r,
        Shape::Rect(a, b) => (b.x - a.x) * (b.y - a.y),
        Shape::Empty => 0,
    }
}

fn main() -> i32 {
    let mut p = Point::new(1, 2);
    p.shift(10);                          // passes &p
    let shapes = [Shape::Rect(Point::new(0, 0), p), Shape::Circle(p, 2), Shape::Empty];
    for s in shapes {
        std::print_int(area(s));
        print(" ");
    }
    std::print_int(p.sum());
    println("");
    let o: Option<i64> = Some(7);
    if let Some(v) = o { std::print_int(v); }
    match 15 {
        0 => println(" zero"),
        1..=9 => println(" digit"),
        n if n % 5 == 0 => println(" fives"),
        _ => println(" other"),
    }
    0
}
```
```out
22 12 0 13
7 fives
```

A match must cover every value; arms can have `|`, ranges `a..=b` and
guards `if`. `use Shape::{Circle, Empty};` lets variants be written
without `Shape::`. `==` compares structs, enums, tuples and arrays field
by field; `[u8]` compares by bytes, a `Vec` or `HashMap` by contents.

## Generics and traits

```tach
trait Area {
    fn area(self: *Self) -> i64;
    fn describe(self: *Self) {            // a default method
        print("area ");
        std::print_int(self.area());
        println("");
    }
}

struct Square { side: i64 }

impl Area for Square {
    fn area(self: *Square) -> i64 { self.side * self.side }
}

fn total<T: Area>(items: [T]) -> i64 {    // bounds: T: A + B
    let mut sum = 0;
    for it in items { sum += it.area(); }
    sum
}

struct Pair<T> { a: T, b: T }

impl<T: Ord> Pair<T> {
    fn max(self: *Pair<T>) -> T { if self.a > self.b { self.a } else { self.b } }
}

fn main() -> i32 {
    let squares = [Square { side: 2 }, Square { side: 3 }];
    std::print_int(total(squares[..]));   // an array to a slice: a[..]
    println("");
    squares[0].describe();
    let p = Pair { a: 3, b: 9 };
    std::print_int(p.max() + Pair::<i64> { a: 1, b: 0 }.max());
    println("");
    0
}
```
```out
13
area 4
10
```

Generics are templates, checked per instantiation (`max::<i64>(a, b)`
is the turbofish). Operators go through the prelude's traits: `impl Add
for V` makes `a + b` work; `Ord`'s `cmp` gives `<`. There are no trait
objects: dispatch is static.

## Modules and imports

```tach
mod geometry {                            // or `mod geometry;` for geometry.tach
    pub struct Rect { pub w: i64, pub h: i64 }
    pub fn area(r: Rect) -> i64 { r.w * r.h }
    fn helper() {}                        // private: only this module and its children
}

use geometry::{Rect, area};               // by name; never `*`
use std::Buf;

fn main() -> i32 {
    let mut b = Buf::new();
    defer b.free();
    b.push_int(area(Rect { w: 2, h: 3 }));
    println(b.as_slice());
    0
}
```
```out
6
```

Paths start with a name in scope, `crate`, `self`, `super` or `std`.
Items are private unless `pub`; `pub use` re-exports. A missing import's
error says which `use` line to add, and `tachyonc fix` adds it.

## Slices, arrays, text

```tach
fn sum(xs: [i64]) -> i64 {
    let mut t = 0;
    for i in 0..xs.len { t += xs[i]; }    // indices are i64; checked
    t
}

fn main() -> i32 {
    let mut a = [5, 1, 4];
    a[1] = 2;
    std::print_int(sum(a[..]) + sum(a[1..]));   // a[lo..hi], a[..hi], a[lo..]
    println("");
    let s = "hello world";
    println(s[6..]);
    if s[0..5] == "hello" { println("starts with hello"); }
    let words = [0; 4];
    std::print_int(words[4]);             // out of bounds: a message, exit 101
    0
}
```
```out (exit 101)
17
world
starts with hello
index out of bounds: index 4, length 4
```

An array `[T; N]` is a value (copied by `=`, no `.len`); a slice `[T]`
is a pointer and a length (`.ptr`, `.len`) viewing an array, a `Vec` or
memory. Writing through a slice needs no `mut`.

## std: Vec, HashMap, Buf

```tach
use std::{Buf, HashMap, sort};

fn main() -> i32 {
    let mut v: Vec<i64> = Vec::new();
    defer v.free();                        // no destructors: free explicitly
    v.push(30);
    v.push(10);
    v.push(20);
    sort(v.as_slice());                    // in place
    v.set(0, v.get(0) + 1);                // get/set are checked
    for x in v { std::print_int(x); print(" "); }   // also &v, v.iter()
    println("");
    let last = v.pop();                    // Option<i64>
    std::print_int(last.unwrap_or(-1));
    println("");

    let mut m: HashMap<[u8], i64> = HashMap::new();
    defer m.free();
    m.insert("a", 1);
    m.insert("b", 2);
    match m.get("a") { Some(x) => std::print_int(x), None => print("none") }
    println("");
    for (k, _) in m.iter() { print(k); }   // (K, V) pairs, in slot order
    println("");

    let mut b = Buf::new();                // text builder
    defer b.free();
    b.push_str("n=");
    b.push_int(m.len());
    b.push('!');
    println(b.as_slice());
    0
}
```
```out
11 20 30
30
1
ab
n=2!
```

`Vec`, `Buf` and `HashMap` are handles: copying one (`let w = v;`,
passing it by value) copies the pointer, not the contents. Pass `&v` to
a `*Vec<T>` parameter to let a function push. A slice from `as_slice`
is valid until the vector grows or is freed. The whole of std, made
from its source in this compiler (every item is `pub`):

```text
@STD-API@
```

## Input, output, arguments

std prints and reads stdin: `read_stdin()` (all of it, a
`Result<Buf, IoError>`), `read_line(&buf)` (the next line, without its
`'\n'`; `Ok(false)` at the end), `Scanner` (tokens, numbers, lines of a
text), `parse_int` (a `Result`), `split`, `trim` (`guide conversions`:
Option means absent, Result failed). Files go through C (`fopen`):

```tach
import "string.h" as c;
use std::{Scanner, read_stdin};

fn main(argc: i32, argv: **u8) -> i32 {
    let mut input = read_stdin().unwrap(); // all of stdin
    defer input.free();                   // the caller frees it
    let mut sc = Scanner::new(input.as_slice());
    let mut total = 0;
    while let Ok(n) = sc.next_int() {     // Err(ScanError::End) at the end
        total += n;
    }
    std::print_int(total);
    println("");
    for k in 1..argc as i64 {             // argv[0] is the program
        let arg = unsafe { argv[k] };     // a C string
        let len = unsafe { c::strlen(arg) } as i64;
        println(unsafe { arg[0..len] });  // as a [u8]
    }
    0
}
```
```in
12
30
```
```out
42
```

## unsafe and C

```tach
import "stdio.h" as c;                   // a C header, its names under c::

extern "C" {                              // or declare C functions yourself
    fn abs(x: i32) -> i32;
}

#[repr(C)]                                // C's layout, for passing to C
struct Pair { a: i32, b: i32 }

extern "C" fn add(p: Pair) -> i32 { p.a + p.b }   // callable from C

fn main() -> i32 {
    let x = 2.5;
    unsafe {
        c::printf(c"%.1f %d\n", x * 2.0, abs(-3) + add(Pair { a: 1, b: 2 }));
    }
    0
}
```
```out
5.0 6
```

Unsafe operations: calling C or an `unsafe fn`, dereferencing (`*p`,
`p.f`) or indexing (`p[i]`) a raw pointer, reading a union field. A
*borrow* is safe to dereference: `&place` passed directly, or a pointer
parameter (`self: *T` included). A local holding a pointer is raw.
`tachyonc fix --only unsafe` wraps what needs it.

## Behaviour that is defined

```tach
let big: i32 = 2147483647;
let zero = 0;
std::print_int((big + 1) as i64);         // wraps: -2147483648
print(" ");
std::print_int(7 / zero + 7 % zero);      // x / 0 == 0, x % 0 == x
print(" ");
std::print_int(-7 / 2);                   // truncates toward zero; -7 % 2 == -1
print(" ");
std::print_int(300.7 as u8 as i64);       // float to int: truncates, then wraps
println("");
```
```out
-2147483648 7 -3 44
```

Indexing and slicing are checked (exit 101 with a message), as are
`unwrap` and casts to enums. A slice used after its memory is freed is
the one hole in safe code (no lifetimes).

## Errors you will meet first

| error (short form) | fix |
|---|---|
| `unknown type 'String'` (or `char`, `Box`) | `[u8]`, `u8`, `*T` or `Vec<T>` |
| `expected type, got '&'` | `*T` for `&T` and `&mut T` |
| `expected identifier, got '&'` in `fn f(&self)` | `self: *T` |
| `cannot infer the type of closure parameter 'x'` | `\|x: i64\| ...`, or pass it where an `Fn` bound or `fn` type gives it |
| `'?' needs 'f' to return Option or Result` | `fn f(..) -> Option<T>` or `-> Result<T, E>` |
| `'println!' is a macro call` | no macros: `println(f"{x}")` |
| `cannot assign to immutable variable 'x'` | `let mut x` |
| `cannot index type 'Vec<i64>'` | `v.get(i)`, `v.as_slice()[i]` |
| `'for' iterates over ... got 'i64'` | a range: `for x in 0..n`; a Vec, a HashMap, `v.iter()` and ranges as values iterate too (0.14) |
| `no method 'len' on type '[u8]'` | `s.len`, a field |
| `expected '[i64]', got '[i64; 3]'` | pass `a[..]` |
| `expected 'i32', got 'i64'` | `x as i32`: only widening is implicit |
| `cannot take address of non-lvalue expression` | `&` needs a place: `let p = P { x: 1 }; f(&p)` |
| `non-exhaustive match: 'E::C' is not covered` | an arm, or `_ =>` |
| `error[unsafe] calling a C function is unsafe` | `unsafe { ... }` |
| `undefined variable 'helper' \| help: add 'use ...'` | add the `use` line the help names |
| `wildcard imports are not allowed` | `use m::{a, b};` |

`tachyonc guide errors` has more, each with its fix.

## Tools: read and change code through the compiler

```sh
tachyonc check [ROOT]                   # all errors, one line each: FILE:L:C: error[KIND] MSG | help: ...
tachyonc f.tach -o f                    # the same lines when compiling, off a terminal
tachyonc query show NAME                # an item's source: fn, Type::method, Enum::Variant, FILE:LINE
tachyonc query def NAME                 # where it is defined, its signature
tachyonc query refs NAME                # every resolved use (--count, --in FILE)
tachyonc query items [MODULE]           # a module's items with signatures (std: its API)
tachyonc query context NAME             # source, what it calls, its types and callers, at once
tachyonc try '7 / 2'                    # run a snippet with std: its output, TYPE = VALUE
tachyonc edit patch NAME --old 'a < b' --new 'a <= b'   # change text inside one item
tachyonc edit replace NAME < new.tach   # replace an item; edit insert --after NAME; edit delete NAME
tachyonc fix                            # missing imports, unused, pub, unsafe blocks
tachyonc undo                           # take the last edit back
tachyonc refactor rename main::x total  # a local (or FILE:LINE:COL), an item, a field, with every use
```

They pay off on renames, moves, signature, field and variant changes,
errors across files and large code; a small file is cheaper read whole
(`query show FILE.tach`, `query text FILE:1-200`) than queried piece by
piece.
ROOT is `--root FILE`, a last argument ending in `.tach`, or
`./main.tach`. Every edit is checked first: one that adds an error
writes nothing. A problem is one line, `error CODE: message`, then
`try:` lines: commands to run as they are. `tachyonc guide tools` has
the rest.

## Topics

`tachyonc guide TOPIC` prints one; `tachyonc guide --list` gives their
sizes; `tachyonc guide --all` prints everything.

@TOPICS@
