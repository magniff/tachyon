# The language, the long form (vole 0.20)

Vole is a compiled systems language of values: structs, enums with
exhaustive `match`, traits and generics (monomorphized), modules,
checked slices, `unsafe` raw pointers, exact C interop. A value has one
owner and is dropped at the end of its scope; a function says what it
does with each parameter, `let` (the default: it reads it), `inout`
(it changes it: the caller writes `&x`) or `sink` (it takes it), and
the compiler checks that no two accesses of a value conflict. There
are no lifetimes to write and no macros. Nothing allocates without an
allocator, and every function's effects are known (0.16). Safe code
has no undefined behaviour. This text matches this compiler;
`volec guide` is the short core of this text, `volec guide TOPIC`
the detail (topics at the end); `volec guide --full` prints this
topic with std's API in its place.

## Build and run

```sh
volec hello.vl -o hello && ./hello   # executable (cc links it)
volec hello.vl -o hello.o            # object; `-o x.s`: assembly
volec check hello.vl                 # errors only, one per line
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
on the command line make one program; `mod name;` loads `name.vl`.

## Rust habits and what vole has instead

| Rust | vole |
|---|---|
| `String`, `&str` | the same (0.20): `str` (UTF-8 text, a view; `&str` is `str`) and `String` (owned, `String::new_in(gpa)`); bytes are `[u8]`; `c"text"` is a NUL-terminated `*u8` for C |
| `x: &T`, `x: &mut T`, `x: T` | conventions (0.20): `x: T` (let: read; called `f(v)`), `x: inout T` (called `f(&v)`), `x: sink T` (taken; an owned argument moves); no lifetimes; `*T` is the raw pointer: dereferencing it needs `unsafe`; no `Box` (`guide rust`: the whole mapping) |
| `fn f(&self)`, `fn f(&mut self)`, `fn f(self)` | `fn f(self)`, `fn f(inout self)`, `fn f(sink self)` |
| `let mut x`, `move \|\|` | `var x`, `sink \|\|`; `inout r = &x;` keeps an access, used as `x` itself (no `*r`) |
| `use m::*;` | not allowed: `use m::{a, b};`, or the path `m::a` |
| `println!("{}", x)`, `format!` | no macros: `println(f"x = {x:>4} {v:?}")`, `format_in(f"..", gpa)` (a `Buf`) (`guide formatting`) |
| `Vec::new()`, a global allocator | `Vec::new_in(gpa)`: nothing allocates without an allocator; `gpa` comes from `fn main(gpa: Gpa)`, passed down as a parameter (0.16, `guide allocators`) |
| `Box<T>`, arenas | a `Vec`; `arena_scope(gpa, \|a\| ..)` frees all it allocated at its end; `--check-alloc` traps a use after free |
| `const fn`, purity | `#[pure]`, `#[no_alloc]`: checked declarations; `volec query effects f` (0.16, `guide effects`) |
| `v[i]` on a `Vec` | the same (0.17): `v[i]`, `v[i] = x`, `v[a..b]` index its slice, checked, also through an access (`v: inout Vec<i64>`); `v.get(i)`, `v.set(i, x)` too |
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
pointer, are allowed only in `unsafe { }` (`volec guide rust`: the
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
var n = a as i32;         // `as` converts numbers; nothing converts implicitly
n += c as i32 + b as i32 + e as i32;
```

`let` bindings are immutable, `var` ones mutable. Shadowing (`let x =
x + 1;`) is allowed. `const N: i64 = 10;` and `static var COUNT: i64 = 0;`
are items (statics are safe to use; with threads, a `static var` is for
one thread: `guide threads`). Integers wrap, `x / 0 ==
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
    var total = 0;
    for i in 0..10 {              // 0..10 and 0..=9: ranges exist only in `for`
        if i % 2 == 0 { continue; }
        total += i;
    }
    var k = 0;
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

## Parameters: let, inout, sink

```tach
struct Account { balance: i64, log: Vec<i64> }

fn transfer(from: inout Account, to: inout Account, amount: i64) -> bool {
    if from.balance < amount { return false; }
    from.balance -= amount;
    to.balance += amount;
    from.log.push(-amount);
    to.log.push(amount);
    true
}

fn report(a: Account, out: inout i64) { out += a.balance; }   // an access is its value

fn keep(all: inout Vec<Account>, a: sink Account) { all.push(a); }

fn main(gpa: Gpa) {
    var a = Account { balance: 100, log: Vec::new_in(gpa) };
    var b = Account { balance: 5, log: Vec::new_in(gpa) };
    transfer(&a, &b, 30);                 // the call shows what changes
    var sum = 0;
    report(a, &sum);
    report(b, &sum);
    var all: Vec<Account> = Vec::new_in(gpa);
    keep(&all, a);                        // a moves: dead from here
    println(f"{sum} {all[0].log.len()} {b.balance}");
}
```
```out
105 1 35
```

- `let` (nothing written) reads: a plain value (`i64`, `Point`) is
  copied, an owned one (`Vec`, a struct with one) is borrowed for the
  call, so the caller keeps it. `inout` changes the caller's place,
  exclusively: `transfer(&a, &a, 1)` is `own.conflict`. `sink` takes the
  value: the callee owns it, may change it, and drops it.
- Inside the function every parameter is used as the value: `out +=
  a.balance`, `from.log.push(x)`; there is no `*`.
- `inout r = &a;` is a local access to `a`, passed on as `f(&r)`; `let`
  and `var` locals own their value (`guide memory`).

## Structs, enums, match, methods

```tach
struct Point { x: i64, y: i64 }

enum Shape { Circle(Point, i64), Rect { min: Point, max: Point }, Empty }

impl Point {
    fn new(x: i64, y: i64) -> Point { Point { x: x, y: y } }   // Point::new(1, 2)
    fn shift(inout self, dx: i64) { self.x += dx; }             // writes through self
    fn sum(self) -> i64 { self.x + self.y }                     // a copy
}

fn area(s: Shape) -> i64 {
    match s {
        Shape::Circle(_, r) => 3 * r * r,
        Shape::Rect { min, max } => (max.x - min.x) * (max.y - min.y),
        Shape::Empty => 0,
    }
}

fn main() -> i32 {
    var p = Point::new(1, 2);
    p.shift(10);                          // lends p inout: p is a var
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
    fn area(self) -> i64;
    fn twice(self) -> i64 { 2 * self.area() }          // a default method
}

struct Square { side: i64 }

impl Area for Square {
    fn area(self) -> i64 { self.side * self.side }
}

fn total<T: Area>(items: [T]) -> i64 {    // bounds: T: A + B
    items.iter().map(|it| it.area()).sum()
}

struct Pair<T> { a: T, b: T }

impl<T: Ord> Pair<T> {
    fn max(self) -> T { if self.a > self.b { self.a } else { self.b } }
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

`mod geometry;` loads geometry.vl (or `mod geometry { ... }` inline);
`use geometry::{Rect, area};` imports by name, never `*`. Paths start
with a name in scope, `crate`, `self`, `super` or `std`. Items are
private (to their module and its children) unless `pub`; `pub use`
re-exports. A missing import's error says which `use` line to add, and
`volec fix` adds it.

## Slices, arrays, text

```tach
fn sum(xs: [i64]) -> i64 {
    var t = 0;
    for i in 0..xs.len() { t += xs[i]; }    // indices are i64; checked
    t
}

fn main() -> i32 {
    var a = [5, 1, 4];
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
main.vl:16:20: index out of bounds: index 4, length 4
```

An array `[T; N]` is a value (copied by `=`; `a.len()` is N); a slice
`[T]` is a pointer and a length (`.len()`; `.ptr` for C) viewing an
array, a `Vec` or memory. A `[T]` is read-only; `inout [T]`
(`&a[..]`, `v.as_mut_slice()`) writes its elements.

## std: Vec, HashMap, Buf; allocation

```tach
fn evens(n: i64, gpa: Gpa) -> Vec<i64> {  // it allocates: it takes an allocator
    (0..n).map(|i| i * 2).collect_in(gpa)
}

fn main(gpa: Gpa) -> i32 {                 // the program's allocator
    var v: Vec<i64> = Vec::new_in(gpa);      // dropped (freed) when main returns
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

    var m: HashMap<[u8], i64> = HashMap::new_in(gpa);
    m.insert("a", 1);
    m.insert("b", 2);
    match m.get("a") { Some(x) => std::print_int(x), None => print("none") }
    println("");
    for (k, _) in m.iter() { print(k); }   // (K, V) pairs, in slot order
    println("");

    var b = Buf::new_in(gpa);              // text builder
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
`volec fix --only alloc016` moves 0.15 code (`Vec::new()`) over.
Every function's effects are inferred (`alloc(Gpa) io global panic
diverge unsafe`): `volec query effects f --why io` shows where;
`#[pure]` or `#[no_alloc]` on a function is checked (`guide effects`,
`guide allocators`).

`Vec`, `Buf` and `HashMap` own their contents: `let w = v;` or passing
one to a `sink` parameter moves it (`.clone()` copies). Pass `v` to a
`v: Vec<T>` (let) parameter to read it, `&v` to a `v: inout Vec<T>` one
to let a function push. A slice from `as_slice` views the vector: using it after the
vector grew or was dropped is an error (`guide views`). std's API,
made from its source in this compiler, a
line per item: `volec guide std#the-api`; each item with its comment:
`volec guide std#every-item`; one name: `volec guide --find NAME`.
@STD-API-FULL@

A priority queue is a `BinaryHeap` (the largest first) or a `MinHeap`
(the smallest first; Rust's `BinaryHeap<Reverse<T>>`), both in the
prelude (`guide std#heaps-priority-queues`). Dijkstra's shortest paths
with a MinHeap of (distance, node) pairs:

```tach
// Dijkstra: the shortest distances from node 0.
fn main(gpa: Gpa) -> i32 {
    let n = 5;
    var adj: Vec<Vec<(i64, i64)>> = Vec::new_in(gpa);       // adj[u]: (to, weight)
    for _ in 0..n {
        adj.push(Vec::new_in(gpa));
    }
    for (u, v, w) in [(0, 1, 4), (0, 2, 1), (2, 1, 2), (1, 3, 1), (2, 3, 5)] {
        adj[u].push((v, w));
    }
    var dist: Vec<i64> = Vec::filled_in(n, i64::MAX, gpa);
    var heap: MinHeap<(i64, i64)> = MinHeap::new_in(gpa);      // (distance, node)
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
`Result<Buf, IoError>`), `read_line(&buf)` (the next line, without its
`'\n'`; `Ok(false)` at the end), `Scanner` (tokens, numbers, lines of a
text), `parse_int` (a `Result`), `split_in`, `trim` (`guide conversions`:
Option means absent, Result failed). Files go through C (`fopen`):

```tach
import "string.h" as c;

fn main(argc: i32, argv: **u8, gpa: Gpa) -> i32 {
    let input = read_stdin_in(gpa).unwrap(); // all of stdin, a Buf
    var sc = Scanner::new(input.as_slice());
    var total = 0;
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
`p.f`) or indexing (`p[i]`) a raw pointer, reading a union field. An
access (a let or inout parameter, an `inout` local, a `let T` / `inout
T` field) is safe to read and write through wherever it is kept; every
`*T` is raw, a parameter too (`fix --values` makes a parameter an
access).
`volec fix --only unsafe` wraps what needs it; `#[repr(C)]`, callbacks
and linking: `guide c-interop`.

## Errors you will meet first

| error (short form) | fix |
|---|---|
| `unknown type 'char'` (or `Box`) | `u8` (or a `u32` code point), `*T` or `Vec<T>` |
| `expected type, got '&'`; `expected identifier, got '&'` | `str` for `&str`; `self`, `inout self` or `sink self` for `&self`, `&mut self`, `self` |
| `conv.rust: '&mut T' is Rust's spelling` (`let mut`, `&mut x`, `move`) | the `try:` line's form: `inout T`, `var`, `&x`, `sink`; `volec fix --suggested` |
| `conv.marker: 'v' is lent inout here` | `f(&v)`: an inout argument is marked |
| `conv.marker_extra: '&' marks an argument the callee may change` | `f(v)`: a let or sink argument is not |
| `own.readonly: writes through 'v' ... read-only (let)` | take it `v: inout T`, called `f(&v)` |
| `own.readonly: '&n' changes 'n', a let binding` (or `v.push(x)`) | `var n`; a parameter `x: inout T`; `inout self`; `static var` |
| `cannot infer the type of closure parameter 'x'` | `\|x: i64\| ...`, or pass it where an `Fn` bound or `fn` type gives it |
| `'?' needs 'f' to return Option or Result` | `fn f(..) -> Option<T>` or `-> Result<T, E>` |
| `'println!' is a macro call` | no macros: `println(f"{x}")` |
| `cannot assign to immutable variable 'x'` | `var x` |
| `cannot index type 'HashMap<K, V>'` | `m.get(k)` (an Option), `m.insert(k, v)` |
| `allocation is explicit: pass an allocator (try: Vec::new_in(gpa))` | `fn main(gpa: Gpa)`, `gpa` passed down; `volec fix --only alloc016` |
| `'for' iterates over ... got 'i64'` | a range: `for x in 0..n`; a Vec, a HashMap, `v.iter()` and ranges as values iterate too (0.14) |
| `expected '[i64]', got '[i64; 3]'` | pass `a[..]` |
| `expected 'i32', got 'i64'` | `x as i32`: only widening is implicit |
| `non-exhaustive match: 'E::C' is not covered` | an arm, or `_ =>` |
| `error[unsafe] calling a C function is unsafe` | `unsafe { ... }` |
| `undefined variable 'helper' \| help: add 'use ...'` | add the `use` line the help names |

`volec guide errors` has more, each with its fix.

## Tools: read and change code through the compiler

```sh
volec check [ROOT]                   # all errors, one line each: FILE:L:C: error[KIND] MSG | help: ...
volec f.vl -o f                    # the same lines when compiling, off a terminal
volec query show NAME                # an item's source: fn, Type::method, Enum::Variant, FILE:LINE
volec query def NAME                 # where it is defined, its signature
volec query refs NAME                # every resolved use (--count, --in FILE)
volec query items [MODULE]           # a module's items with signatures (std: its API)
volec query context NAME             # source, what it calls, its types and callers, at once
volec query effects NAME             # what it may do: alloc(Gpa) io global panic diverge unsafe
volec try '7 / 2'                    # run a snippet with std: its output, TYPE = VALUE
volec edit patch NAME --old 'a < b' --new 'a <= b'   # change text inside one item
volec edit replace NAME < new.vl   # replace an item; edit insert --after NAME; edit delete NAME
volec fix                            # missing imports, unused, pub, unsafe blocks
volec undo                           # take the last edit back
volec refactor rename main::x total  # a local (or FILE:LINE:COL), an item, a field, with every use
```

They pay off on renames, moves, signature changes, errors across files
and large code; a small file is cheaper read whole (`query show
FILE.vl`). ROOT is `--root FILE`, a last argument ending in `.vl`,
or `./main.vl`. Every edit is checked first: one that adds an error
writes nothing. A problem is one line, `error CODE: message`, then
`try:` lines to run as they are (`guide tools`).

## Topics

`volec guide TOPIC` prints one; `volec guide --list` gives their
sizes; `volec guide --all` prints everything.

@TOPICS@
