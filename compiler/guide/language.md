# The language, the long form (tachyon 0.17)

Tachyon is a compiled systems language. Its syntax is close to Rust's,
its model close to C's: structs, enums with exhaustive `match`, traits
and generics (monomorphized), modules, checked slices, raw pointers,
`unsafe`, exact C interop. There is no borrow checker, no lifetimes, no
destructors, no macros. Closures and iterators are new in 0.14; `?`,
f-strings, widening, `#[derive]`, named and default arguments in 0.15;
explicit allocation and effects in 0.16. Safe code has no undefined
behaviour. This text matches this compiler;
`tachyonc guide` is the short core of this text, `tachyonc guide TOPIC`
the detail (topics at the end); `tachyonc guide --full` prints this
topic with std's API in its place.

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

`main` returns the exit status (`fn main()` with no result is 0).
`fn main(gpa: Gpa)` takes the program's allocator (below), `fn
main(argc: i32, argv: **u8, gpa: Gpa)` the arguments too. Several files
on the command line make one program; `mod name;` loads `name.tach`.

## Rust habits and what tachyon has instead

| Rust | tachyon |
|---|---|
| `String`, `&str` | `[u8]`, a byte slice: `"text"` is a `[u8]`; build text with `std::Buf`; `c"text"` is a NUL-terminated `*u8` for C |
| `&T`, `&mut T`, `Box<T>` | `&T`, `&mut T` (0.17): `&x`, `&mut x`, checked and safe; no lifetimes; `*T` is the raw pointer: dereferencing it needs `unsafe`, parameter or not (0.18.1); no `Box` |
| `fn f(&self)`, `fn f(&mut self)` | `fn f(self: &T)`, `fn f(self: &mut T)` (0.17); `fn f(self: T)` takes the value (an owned one moves) |
| `use m::*;` | not allowed: `use m::{a, b};`, or the path `m::a` |
| `println!("{}", x)`, `format!` | no macros: `println(f"x = {x:>4} {v:?}")`, `format_in(f"..", gpa)` (a `Buf`) (`guide formatting`) |
| `Vec::new()`, a global allocator | `Vec::new_in(gpa)`: nothing allocates without an allocator; `gpa` comes from `fn main(gpa: Gpa)`, passed down as a parameter (0.16, `guide allocators`) |
| `Box<T>`, arenas | a `Vec`; `arena_scope(gpa, \|a\| ..)` frees all it allocated at its end; `--check-alloc` traps a use after free |
| `const fn`, purity | `#[pure]`, `#[no_alloc]`: checked declarations; `tachyonc query effects f` (0.16, `guide effects`) |
| `v[i]` on a `Vec` | the same (0.17): `v[i]`, `v[i] = x`, `v[a..b]` index its slice, checked, also through a reference (`v: &mut Vec<i64>`); `v.get(i)`, `v.set(i, x)` too |
| closures, `.iter().map()` | the same (0.14): `v.iter().map(\|x\| x * k).sum()`; `F: Fn(i64) -> i64` bounds; no `dyn Fn`, `iter_mut` (`guide closures`, `guide iterators`) |
| `x?` | the same on `Option` and `Result` (0.15); `impl From<E> for F` converts the error; `main` may return `Result<(), E>` (`guide conversions`) |
| `impl Trait for T`, `T: Trait` | the same; `type Item;` associated types (0.14); `#[derive(Eq, Ord, Hash, Debug, Clone)]` (0.15); no `dyn`, `where`, supertraits |
| `Drop`, RAII | the same (0.17): values are dropped at the end of their scope; `impl Drop for T`, `drop(x)`, `std::forget(x)`; no `free` calls (`guide memory`) |
| `!x` on integers | `~x`; `!` is for `bool` only |
| `i64::MAX`, `x.abs()`, `x.pow(2)` | `i64::MAX`, `u8::MIN` the same (0.15); no methods on numbers: write the expression, or call C |
| overflow panics, `/ 0` panics | integers wrap; `x / 0 == 0`, `x % 0 == x`; no panic |
| `match s { "add" => ... }` | strings are not patterns: `if s == "add" { ... }` |
| `char` | none: `'a'` is a `u8` (one ASCII byte) |
| no default or named arguments | `fn f(a: i64, b: i64 = 2)`, `f(1, b: 3)` (0.15): named ones last, in order |
| `usize`, implicit `i32` -> `i64` | lengths and indices are `i64`; lossless widening (0.15), `a as i32` narrows |

The prelude, in every module without `use`: `Option`, `Some`, `None`,
`Result`, `Ok`, `Err`, `Vec`, `print`, `println`, `eprint`, `eprintln`,
`format_in`, `Gpa`, `Arena`, `ScopedArena`, `arena_scope`, and the traits
`Add`, `Sub`, `Mul`, `Div`, `Neg`, `Eq`, `Ord`, `Hash`, `Display`, `Debug`,
`Clone`, `From`, `Into`, `Allocator`. The rest of std is used by path
(`std::print_int(n)`) or imported (`use std::{Buf, HashMap};`).
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
let s = "bytes";          // [u8]: s.len() (an i64), s[0], s[1..3]
let p = c"for C";         // *u8, NUL-terminated
let t = (1, "two");       // a tuple: t.0, t.1
let arr = [0; 8];         // [i64; 8]; also [1, 2, 3]; arr[i] is checked
let mut n = a as i32;     // `as` converts numbers; nothing converts implicitly
n += c as i32 + b as i32 + e as i32;
```

Bindings are immutable unless `mut`. Shadowing (`let x = x + 1;`) is
allowed. `const N: i64 = 10;` and `static mut COUNT: i64 = 0;` are items
(statics are safe to use: there are no threads). Integers wrap, `x / 0 ==
0`, `x % 0 == x`; indexing, slicing, `unwrap` and casts to enums are
checked (a message, exit 101): `guide types`.

## Functions and control flow

```tach
fn classify(n: i64) -> [u8] {
    if n < 0 { "negative" } else if n == 0 { "zero" } else { "positive" }
}

fn greet(name: [u8], times: i64 = 1, sep: [u8] = " ") {   // defaults (0.15)
    for _ in 0..times { print(f"hi {name}{sep}"); }
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
    greet("ann");
    greet("bob", times: 2, sep: "! ");    // named arguments: last, in order
    println(classify(total - found));
    0
}
```
```out
hi ann hi bob! hi bob! positive
```

The last expression of a block, without `;`, is its value; `if`, `match`,
`loop` and blocks are expressions. There are no nested functions.

## Structs, enums, match, methods

```tach
struct Point { x: i64, y: i64 }

enum Shape { Circle(Point, i64), Rect { min: Point, max: Point }, Empty }

impl Point {
    fn new(x: i64, y: i64) -> Point { Point { x: x, y: y } }   // Point::new(1, 2)
    fn shift(self: &mut Point, dx: i64) { self.x += dx; }       // writes through self
    fn sum(self: Point) -> i64 { self.x + self.y }              // a copy
}

fn area(s: Shape) -> i64 {
    match s {
        Shape::Circle(_, r) => 3 * r * r,
        Shape::Rect { min, max } => (max.x - min.x) * (max.y - min.y),
        Shape::Empty => 0,
    }
}

fn main() -> i32 {
    let mut p = Point::new(1, 2);
    p.shift(10);                          // passes &mut p
    let shapes = [Shape::Rect { min: Point::new(0, 0), max: p }, Shape::Circle(p, 2),
        Shape::Empty];
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

A variant's fields are by position (`Circle(Point, i64)`) or by name
(`Rect { min: Point, max: Point }`, 0.17: made as `Shape::Rect { min: a,
max }` in any order, matched as `Shape::Rect { min, .. }`; a variant's
fields are read only through patterns, as in Rust). A match must cover
every value; arms can have `|`, ranges `a..=b` and guards `if`. `use Shape::{Circle, Empty};` lets variants be written
without `Shape::`. `==` compares structs, enums, tuples and arrays field
by field; `[u8]` compares by bytes, a `Vec` or `HashMap` by contents.

## Generics and traits

```tach
trait Area {
    fn area(self: &Self) -> i64;
    fn twice(self: &Self) -> i64 { 2 * self.area() }   // a default method
}

struct Square { side: i64 }

impl Area for Square {
    fn area(self: &Square) -> i64 { self.side * self.side }
}

fn total<T: Area>(items: [T]) -> i64 {    // bounds: T: A + B
    items.iter().map(|it| it.area()).sum()
}

struct Pair<T> { a: T, b: T }

impl<T: Ord> Pair<T> {
    fn max(self: &Pair<T>) -> T { if self.a > self.b { self.a } else { self.b } }
}

fn main() -> i32 {
    let squares = [Square { side: 2 }, Square { side: 3 }];
    let p = Pair::<i64> { a: 3, b: 9 };   // the turbofish: Pair::<i64>
    println(f"{total(squares[..])} {squares[0].twice()} {p.max()}");   // a[..]: a slice
    0
}
```
```out
13 8 9
```

Generics are templates, checked per instantiation (`max::<i64>(a, b)`
is the turbofish). Operators go through the prelude's traits: `impl Add
for V` makes `a + b` work; `Ord`'s `cmp` gives `<`. There are no trait
objects: dispatch is static.

## Modules and imports

`mod geometry;` loads geometry.tach (or `mod geometry { ... }` inline);
`use geometry::{Rect, area};` imports by name, never `*`. Paths start
with a name in scope, `crate`, `self`, `super` or `std`. Items are
private (to their module and its children) unless `pub`; `pub use`
re-exports. A missing import's error says which `use` line to add, and
`tachyonc fix` adds it.

## Slices, arrays, text

```tach
fn sum(xs: [i64]) -> i64 {
    let mut t = 0;
    for i in 0..xs.len() { t += xs[i]; }    // indices are i64; checked
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
main.tach:16:20: index out of bounds: index 4, length 4
```

An array `[T; N]` is a value (copied by `=`; `a.len()` is N); a slice
`[T]` is a pointer and a length (`.len()`; `.ptr` for C) viewing an
array, a `Vec` or memory. A `[T]` is read-only; `&mut [T]`
(`&mut a[..]`, `v.as_mut_slice()`) writes its elements (0.17).

## std: Vec, HashMap, Buf; allocation

```tach
fn evens(n: i64, gpa: Gpa) -> Vec<i64> {  // it allocates: it takes an allocator
    (0..n).map(|i| i * 2).collect_in(gpa)
}

fn main(gpa: Gpa) -> i32 {                 // the program's allocator
    let mut v: Vec<i64> = Vec::new_in(gpa);  // dropped (freed) when main returns
    v.push(30);
    v.push(10);
    v.push(20);
    sort(v.as_mut_slice());                // in place
    v.set(0, v.get(0) + 1);                // get/set are checked
    for x in v { std::print_int(x); print(" "); }   // also &v, v.iter()
    println("");
    let last = v.pop();                    // Option<i64>
    std::print_int(last.unwrap_or(-1));
    println("");

    let mut m: HashMap<[u8], i64> = HashMap::new_in(gpa);
    m.insert("a", 1);
    m.insert("b", 2);
    match m.get("a") { Some(x) => std::print_int(x), None => print("none") }
    println("");
    for (k, _) in m.iter() { print(k); }   // (K, V) pairs, in slot order
    println("");

    let mut b = Buf::new_in(gpa);          // text builder
    let e = evens(4, gpa);
    b.push_str("n=");
    b.push_int(m.len() + e.len());
    b.push('!');
    println(b.as_slice());
    0
}
```
```out
11 20 30
30
1
ba
n=6!
```

Allocation is explicit (0.16): nothing allocates without an allocator.
A function that allocates takes one, `gpa: Gpa` or `a: A` with `A:
Allocator`, or a container it was given (`push` uses the Vec's own);
main's `gpa` is where they come from. `arena_scope(gpa, |a| ...)` hands out
an arena whose memory is all freed when the closure returns.
`--check-alloc` builds the program with a checking allocator: a use
after free, a double free, a leak are reported where they happen.
`tachyonc fix --only alloc016` moves 0.15 code (`Vec::new()`) over.
Every function's effects are inferred (`alloc(Gpa) io global panic
diverge unsafe`): `tachyonc query effects f --why io` shows where;
`#[pure]` or `#[no_alloc]` on a function is checked (`guide effects`,
`guide allocators`).

`Vec`, `Buf` and `HashMap` own their contents: `let w = v;` or passing
one by value moves it (`.clone()` copies). Pass `&v` to a `&Vec<T>`
parameter to read it, `&mut v` to a `&mut Vec<T>` one to let a function
push. A slice from `as_slice` views the vector: using it after the
vector grew or was dropped is an error (`guide views`). std's API,
made from its source in this compiler, a
line per item: `tachyonc guide std#the-api`; each item with its comment:
`tachyonc guide std#every-item`; one name: `tachyonc guide --find NAME`.
@STD-API-FULL@

A priority queue is a `BinaryHeap` (the largest first) or a `MinHeap`
(the smallest first; Rust's `BinaryHeap<Reverse<T>>`), both in the
prelude (`guide std#heaps-priority-queues`). Dijkstra's shortest paths
with a MinHeap of (distance, node) pairs:

```tach
// Dijkstra: the shortest distances from node 0.
fn main(gpa: Gpa) -> i32 {
    let n = 5;
    let mut adj: Vec<Vec<(i64, i64)>> = Vec::new_in(gpa);   // adj[u]: (to, weight)
    for _ in 0..n {
        adj.push(Vec::new_in(gpa));
    }
    for (u, v, w) in [(0, 1, 4), (0, 2, 1), (2, 1, 2), (1, 3, 1), (2, 3, 5)] {
        adj[u].push((v, w));
    }
    let mut dist: Vec<i64> = Vec::filled_in(n, i64::MAX, gpa);
    let mut heap: MinHeap<(i64, i64)> = MinHeap::new_in(gpa);  // (distance, node)
    dist[0] = 0;
    heap.push((0, 0));
    while let Some((d, u)) = heap.pop() {      // the nearest first
        if d > dist[u] {
            continue;                          // stale: u was reached sooner
        }
        for (v, w) in adj[u].iter() {
            if d + w < dist[v] {
                dist[v] = d + w;
                heap.push((d + w, v));
            }
        }
    }
    println(f"{dist[1]} {dist[2]} {dist[3]} {dist[4] == i64::MAX}");
    0
}
```
```out
3 1 4 true
```

## Input, output, arguments

std prints and reads stdin: `read_stdin_in(gpa)` (all of it, a
`Result<Buf, IoError>`), `read_line(&mut buf)` (the next line, without its
`'\n'`; `Ok(false)` at the end), `Scanner` (tokens, numbers, lines of a
text), `parse_int` (a `Result`), `split_in`, `trim` (`guide conversions`:
Option means absent, Result failed). Files go through C (`fopen`):

```tach
import "string.h" as c;

fn main(argc: i32, argv: **u8, gpa: Gpa) -> i32 {
    let input = read_stdin_in(gpa).unwrap(); // all of stdin, a Buf
    let mut sc = Scanner::new(input.as_slice());
    let mut total = 0;
    while let Ok(n) = sc.next_int() {     // Err(ScanError::End) at the end
        total += n;
    }
    println(total);
    for k in 1..argc as i64 {             // argv[0] is the program; C strings
        println(unsafe { argv[k][0..c::strlen(argv[k]) as i64] });
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

fn main() -> i32 {
    unsafe { c::printf(c"%.1f %d\n", 2.5 * 2.0, abs(-3)); }
    0
}
```
```out
5.0 3
```

Unsafe operations: calling C or an `unsafe fn`, dereferencing (`*p`,
`p.f`) or indexing (`p[i]`) a raw pointer, reading a union field. A
reference (`&T`, `&mut T`) is safe to read and write through wherever
it is kept; every `*T` is raw, a parameter too (0.18.1: `mut` or not;
`fix --values` makes a parameter a reference).
`tachyonc fix --only unsafe` wraps what needs it; `#[repr(C)]`, callbacks
and linking: `guide c-interop`.

## Errors you will meet first

| error (short form) | fix |
|---|---|
| `unknown type 'String'` (or `char`, `Box`) | `[u8]`, `u8`, `*T` or `Vec<T>` |
| `expected type, got '&'`; `expected identifier, got '&'` | `[u8]` for `&str`; `self: &T`, `self: &mut T` or `self: *T` |
| `cannot infer the type of closure parameter 'x'` | `\|x: i64\| ...`, or pass it where an `Fn` bound or `fn` type gives it |
| `'?' needs 'f' to return Option or Result` | `fn f(..) -> Option<T>` or `-> Result<T, E>` |
| `'println!' is a macro call` | no macros: `println(f"{x}")` |
| `cannot assign to immutable variable 'x'` | `let mut x` |
| `cannot index type 'HashMap<K, V>'` | `m.get(k)` (an Option), `m.insert(k, v)` |
| `allocation is explicit: pass an allocator (try: Vec::new_in(gpa))` | `fn main(gpa: Gpa)`, `gpa` passed down; `tachyonc fix --only alloc016` |
| `'for' iterates over ... got 'i64'` | a range: `for x in 0..n`; a Vec, a HashMap, `v.iter()` and ranges as values iterate too (0.14) |
| `expected '[i64]', got '[i64; 3]'` | pass `a[..]` |
| `expected 'i32', got 'i64'` | `x as i32`: only widening is implicit |
| `cannot take address of non-lvalue expression` | `&f(x)` is a temporary (0.18.1) unless a call before it in the statement could see the order: name it, `let t = f(x);` then `&t` |
| `non-exhaustive match: 'E::C' is not covered` | an arm, or `_ =>` |
| `error[unsafe] calling a C function is unsafe` | `unsafe { ... }` |
| `undefined variable 'helper' \| help: add 'use ...'` | add the `use` line the help names |

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
tachyonc query effects NAME             # what it may do: alloc(Gpa) io global panic diverge unsafe
tachyonc try '7 / 2'                    # run a snippet with std: its output, TYPE = VALUE
tachyonc edit patch NAME --old 'a < b' --new 'a <= b'   # change text inside one item
tachyonc edit replace NAME < new.tach   # replace an item; edit insert --after NAME; edit delete NAME
tachyonc fix                            # missing imports, unused, pub, unsafe blocks
tachyonc undo                           # take the last edit back
tachyonc refactor rename main::x total  # a local (or FILE:LINE:COL), an item, a field, with every use
```

They pay off on renames, moves, signature changes, errors across files
and large code; a small file is cheaper read whole (`query show
FILE.tach`). ROOT is `--root FILE`, a last argument ending in `.tach`,
or `./main.tach`. Every edit is checked first: one that adds an error
writes nothing. A problem is one line, `error CODE: message`, then
`try:` lines to run as they are (`guide tools`).

## Topics

`tachyonc guide TOPIC` prints one; `tachyonc guide --list` gives their
sizes; `tachyonc guide --all` prints everything.

@TOPICS@
