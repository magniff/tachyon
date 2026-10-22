# Errors and their fixes

`volec check`, and a build whose output is not a terminal (an
agent's shell, a pipe; `--diagnostics=short` anywhere): one line per
error, `FILE:LINE:COL: error[KIND] MESSAGE | help: HELP | note: NOTE |
try: TRY`, every error of every file at once (up to 50), sorted by
position. A `try:` (0.17) is text to use as it is: code to paste where
the error is (`a as i32`, `std::trim(s)`, the missing match arms), a
`use` line, or a `volec` command to run (`volec fix --only unsafe
main.vl`, `volec edit new-file util.vl main.vl`); VALUE in it
is yours to fill in.
An error whose fix the compiler knows exactly (0.18: a did-you-mean with
one name that near, a conversion, a path from `crate::`, a Rust type or
label respelled, a missing `use` or `pub`, a missing `gpa` argument)
also has `try: volec fix --suggested main.vl`: one command makes
all of them, as one checked edit (`--dry-run` shows the diff, `volec
undo` takes it back, `--at FILE:LINE` fixes one line's), then prints the
errors left. Run it instead of editing those lines by hand or with sed.
KIND is `tokenizer error`, `parser error`, `module error`, `type error`
or `unsafe`. Fix the first errors first: a parser error can hide
type errors in the same function. `volec query show FILE:LINE` prints
the item at an error's position. Below: what a newcomer writes, the
error (short form, without the position), and the fix.

## Rust habits

```tach
let s: String = String::new();
```
```err
error[type error] allocation is explicit: pass an allocator (try: String::new_in(gpa)) | help: this function's `gpa` is the allocator to pass
```
`String` and `str` are std's (0.20, `guide text`); what allocates
takes an allocator: `String::new_in(gpa)`, `s.to_uppercase_in(gpa)`.
A Rust type vole does not have gets the type to write as its `try:`:
`char` (`u8`), `Box`, `Rc` (`*T`), `VecDeque`, `RefCell`.

```tach
use std::cmp::max;
```
```err
error[type error] no 'cmp' in module 'std' | help: vole's std has no such module: std's items are all `std::NAME` too
```
std has a few of Rust's modules (0.20: `std::collections::HashMap`,
`std::fmt::Display`, `std::io::read_line`, `std::iter`, `std::ops`,
`std::slice`, `std::num`, `std::convert`, `std::clone`, `std::string`,
`std::fs`, `std::path`, `std::env`, `std::process`), and every item is
`std::NAME` as well: `use std::{IoError, is_digit};` (`HashMap`,
`read_line` and std's most used names are in the prelude: no `use`).

```tach
fn main() -> i32 { let s = "  a "; let t = s.trim(); 0 }
```
```err
error[type error] no method 'trim' on type '[u8]' | help: 'trim' is no method: std's function `trim` takes the value as its first argument | try: trim(s)
```
`s` is a `[u8]` here: bytes. A `str` has `trim`, `split`, `parse` (0.20):
`let s: str = "  a ";`, or `"  a ".trim()` on the literal itself. A
method std has as a function (`trim`, `sort`, `parse` as `parse_int`,
`split_whitespace` as `split_whitespace_in(s, gpa)`) gets the call to
write; another unknown method, the type's nearest methods and `volec
query items TYPE`, which lists them all.

`fn count(s: str)` takes a `str` (0.20: Rust's `&str` is `str`, as
`&[T]` is `[T]`), and a literal, a `str` or a String goes there. A
parameter is read-only by default (let: `s: str`, `v: Vec<i64>`,
nothing to write); `x: inout T` may change the caller's value, called
with `&x`; `x: sink T` takes it. `*T` is the raw pointer.

```tach
struct P { x: i64 }
impl P { fn get(&self) -> i64 { self.x } }
```
```err
error[parser error] expected identifier, got '&' | help: `self` for `&self`, `inout self` for `&mut self`, `sink self` for `self` (0.19: `self: &Self`, `self: &mut Self`, `self: Self`)
```
`fn get(self) -> i64`; `fn bump(inout self)` to change it, `fn
finish(sink self)` to take it (`self: *P` is the raw pointer).

```tach
fn main() -> i32 { let mut x = 1; x += 1; x as i32 }
```
```err
error[conv.rust] 'let mut' is Rust's spelling; a mutable binding is 'var x'
```
`var x = 1;`. Each of Rust's spellings is `conv.rust` with the
replacement in its `try:` (`fix --suggested` makes them all): `&T` and
`&mut T` in a type (`x: T`, `x: inout T`), `&mut x` (`&x`), `*r` on an
access (`r`), `move ||` (`sink ||`), `static mut` (`static var`), `mut
x: T` (`x: sink T`).

```tach
fn main() -> i32 { var x = 1; let r = &mut x; 0 }
```
```err
error[conv.rust] '&mut x' is Rust's spelling; an inout argument (the callee may change it) is marked '&x'
```
`&x` lends `x` inout, to an `inout` parameter or an `inout r = &x;`
local; nothing else takes `&`.

```tach
println!("{}", 1);
```
```err
error[parser error] 'println!' is a macro call: vole has no macros | help: write `println(f"{1}")`
```
`println(f"{x}")` (0.15, `volec guide formatting`). The help names
what replaces `vec!`, `format!`, `assert!` and the others.

```tach
'outer: for i in 0..3 { break 'outer; }
```
```err
error[tokenizer error] unterminated character literal | help: a label has no quote: `outer: loop { break :outer; }` | try: outer: for i in 0..3 { break :outer; }
```
Labels have no quote: `outer: for i in 0..3 { break :outer; }` (the
try: line is yours, respelled).

```tach
let o: Option<i64> = Some(1);
let Some(x) = o;
```
```err
error[type error] refutable pattern in 'let'
```
`let Some(x) = o else { return 1; };` (0.18.1, the else block must
leave), or `let x = match o { Some(x) => x, None => 0 };`.

```tach
let n = 5;
let m = !n;
```
```err
error[type error] expected 'bool', got 'i64'
```
Bitwise not is `~n`.

```tach
let big = i64::MAX();
```
```err
error[type error] no associated function 'MAX' in 'i64' | help: a constant, without (): 'i64::MAX'
```
`i64::MAX`, `u8::MIN`, ... are constants (0.15); integer types have no
other associated items, and floats no limits (yet).

```tach
let s = "add";
match s { "add" => println("a"), _ => println("b") }
```
```err
error[parser error] expected a pattern, got 'string literal'
```
`if s == "add" { ... }`: patterns are integers, bytes, bools, variants,
tuples.

```tach
#[derive(PartialEq, Debug)]
struct P { x: i64 }
```
```err
error[type error] cannot derive 'PartialEq' (derivable: Eq, Ord, Hash, Debug, Clone)
```
`#[derive(Eq, Ord, Hash, Debug, Clone)]` (0.15): Eq is Rust's PartialEq
and Eq, Ord its PartialOrd and Ord; there is no Copy (every type copies).

```tach
fn f<T>(x: sink T) -> T where T: Ord { x }
```
```err
error[parser error] expected '{', got 'where'
```
Bounds go in the list: `fn f<T: Ord>(x: T) -> T`.

```tach
fn main() -> i32 {
    fn helper() -> i64 { 3 }
    helper() as i32
}
```
```err
items cannot be nested in blocks
```
Move `helper` to the module level.

## Types

```tach
let x = 1;
x = 2;
```
```err
error[type error] cannot assign to immutable variable 'x' | help: make it mutable: `var x`
```
`var x = 1;`: a `let` binding does not change.

```tach
let a: i64 = 1;
let b: i32 = a;
```
```err
error[type error] expected 'i32', got 'i64'
```
Only widening is implicit (0.15: `i32` to `i64`, `u8` to `u32`, ...):
narrowing is `a as i32`. The same for `1 + 1.0`, `u32` to `i32`, and
for `main` returning an `i64` (`n as i32`).

```tach
let b: u8 = 300;
```
```err
error[type error] integer literal 300 does not fit in type 'u8'
```
An unsuffixed literal takes the type the code around it gives: `if ok {
line[i] } else { 0 }` is a `u8`, from the other branch; so are match arms
and array elements beside a `u8`. Alone, a literal is `i64` (`f64`).

```tach
const ORIGIN: (i64, i64) = (0, 0);
fn main() -> i32 { 0 }
```
```err
error[type error] constant 'ORIGIN' has type '(i64, i64)'; constants must be integers, floats, bool or string literals | help: a `static` holds other values: `static ORIGIN: (i64, i64) = ...;`
```
`const GREETING: [u8] = "hello";` is a constant (0.14).

```tach
let x = 1;
if x { }
```
```err
error[type error] expected 'bool', got 'i64'
```
`if x != 0`.

```tach
let a = 1;
if 0 < a < 2 { }
```
```err
error[parser error] comparison operators cannot be chained; use parentheses
```
`if 0 < a && a < 2`.

```tach
fn f() -> i64 { 1; }
```
```err
error[type error] function 'f' body has type '()', expected 'i64'
```
The value is the last expression without `;`: `fn f() -> i64 { 1 }`.

```tach
let x: i64;
```
```err
error[parser error] 'let' without an initializer is not supported
```

```tach
struct P { x: i64, y: i64 }
fn make() -> P { P { x: 1 } }
```
```err
error[type error] missing field 'y' in struct 'P' constructor
```

```tach
fn f(a: i64, b: i64) -> i64 { a + b }
fn g() -> i64 { f(1) }
```
```err
error[type error] function 'f' expects 2 arguments, got 1
```

```tach
enum E { A, B, C }
fn f(e: E) -> i64 { match e { E::A => 1, E::B => 2 } }
```
```err
error[type error] non-exhaustive match: 'E::C' is not covered | help: add an arm for it (try:), or a wildcard arm '_ =>' | try: E::C => VALUE,
```
The `try:` lists every missing pattern as an arm to paste (integers as
ranges: `201..=255 => VALUE,`). An unreachable arm's help gives the line
of the arm above that already matches all it matches.

```tach
fn f() -> i64 { 1 }
fn main() -> i32 { 0 }
fn f() -> i64 { 2 }
```
```err
duplicate function 'f'
```
The help says where the other one is, and the two `try:` lines delete
either (`volec edit delete main.vl:3 main.vl`); to change an item
in place, `volec edit replace f < new.vl` instead of adding a second.

```tach
enum E { A(i64), B }
fn f(e: E) -> i64 { match e { A(x) => x, B => 0 } }
```
```err
error[type error] unknown variant 'A'
```
`E::A(x)`, or `use E::{A, B};` once.

```tach
enum Ev { Key { code: i64, shift: bool }, Quit }
fn main() -> i32 {
    let e = Ev::Key(1, false);
    match e { Ev::Key(c, _) => c as i32, Ev::Quit => 0 }
}
```
```err
error[type error] variant 'Ev::Key' has named fields; give them by name | try: Ev::Key { code: 1, shift: false }
```
A struct-like variant (0.17) is built and matched by name, as in Rust:
`Ev::Key { code: 1, shift: false }`, `Ev::Key { code, .. } => code`.

```tach
enum Ev { Key { code: i64, shift: bool }, Quit }
fn code(e: Ev) -> i64 {
    match e { Ev::Key { code } => code, Ev::Quit => 0 }
}
```
```err
error[type error] the pattern of 'Ev::Key' does not mention field 'shift' | help: match it too, or end the pattern with '..' to leave the rest out | try: Ev::Key { code, .. }
```

```tach
enum Ev { Key { code: i64, shift: bool }, Quit }
fn code(e: Ev) -> i64 { e.code }
```
```err
error[type error] cannot access field 'code' on type 'Ev' | help: a variant's fields are read through a pattern (no '.field' on an enum) | try: if let Ev::Key { code, .. } = e { ... }
```

## Slices, Vec, std

```tach
var m: HashMap<i64, i64> = HashMap::new_in(gpa);
let a = m[0];
```
```err
error[type error] cannot index type 'HashMap<i64, i64>'
```
`m.get(0)` (an Option), `m.insert(0, x)`. A `Vec` and a `Buf` index as
their slice (0.17): `v[0]`, `v[0] = x`, `v[1..3]` are
`v.as_slice()[0]`, ..., checked.

```tach
let n = 3;
for x in n { }
```
```err
error[type error] 'for' iterates over ranges, slices, arrays, iterators and types with an 'iter' method, got 'i64'
```
`for x in 0..n`. A type of yours iterates with `impl Iterator for T`, or
an `iter` method returning one (`volec guide iterators`).

A misspelt method, field or item gets the nearest name of its kind:

```tach
fn main(gpa: Gpa) -> i32 { var b = Buf::new_in(gpa); b.push_string("x"); 0 }
```
```err
error[type error] no method 'push_string' on type 'Buf' | help: did you mean 'push_str'?
```

An array, a Vec or a Buf goes where a slice of its elements does:
`sum(a)` for `fn sum(s: [i64])` (0.20; `sum(&v)` for `s: inout [T]`).
An array's length is `a.len()`.

```tach
let e: IoError = IoError::Read;
```
```err
error[type error] unknown type 'IoError'
```
`use std::IoError;` (the prelude's names need no import: `volec guide
modules`).

```tach
struct K { a: i64 }
fn main(gpa: Gpa) -> i32 { let m: HashMap<K, i64> = HashMap::new_in(gpa); 0 }
```
```err
error[type error] the trait 'Hash' is not implemented for 'K' | help: required by the bound 'K: Hash' of 'HashMap'
```
`impl Hash for K { fn hash(self) -> u64 { std::hash_u64(self.a as u64) } }`.

## Closures and iterators (0.14)

```tach
let f = |x| x + 1;
```
```err
error[type error] cannot infer the type of closure parameter 'x'
```
`|x: i64| x + 1`: in a `let`, nothing says what `x` is; as an argument
for `F: Fn(i64) -> i64` or `fn(i64) -> i64` the type comes from there.

```tach
fn run(f: fn(i64) -> i64) -> i64 { f(1) }
fn main() -> i32 {
    let k = 2;
    run(|x| x + k) as i32
}
```
```err
make the parameter generic
```
A closure that captures is no plain `fn`: `fn run<F: Fn(i64) -> i64>(f:
F) -> i64`. One that captures nothing converts.

```tach
fn apply<F: Fn(i64) -> i64>(f: F) -> i64 { let x = 1; f(x) }
fn main() -> i32 { apply(|a: *i64| 1); 0 }
```
```err
error[type error] expected 'i64', got '*i64'
```
A `*T` is a raw pointer, not a way to pass: a closure parameter is let
as any other, so annotate the type the bound gives (`|a: i64|`), or
leave it untyped.

```tach
fn apply<F: Fn(i64)>(f: F) { f(1); }
fn main() -> i32 {
    var total = 0;
    apply(|x| { total += x; });
    total as i32
}
```
```err
FnMut
```
`Fn` takes closures that assign no captured variable: bound `F:
FnMut(i64)` (and take it `f: sink F`, which may be called).

```tach
fn apply<F: Fn(i64) -> i64>(f: F) -> i64 { f(1) }
fn main() -> i32 {
    let f = {
        var j = 1;
        |x: i64| x + j
    };
    apply(f) as i32
}
```
```err
which does not live outside this block
```
The closure captures the `var j` inout, and `j` ends with the block:
`sink |x: i64| x + j` takes a copy, or declare `j` before the block.

## ?, conversions, arguments, formatting, derive (0.15)

```tach
fn first(v: Option<i64>) -> i64 { let x = v?; x }
```
```err
'?' needs 'first' to return Option or Result; it returns 'i64'
```
Return `Option<i64>` (or `Result<i64, E>`), or `match` on the value.
`?` on an Option inside a function returning a Result needs the error:
`v.ok_or(MyError::Missing)?`.

```tach
use std::ParseIntError;
enum AppError { Bad }
fn read(s: [u8]) -> Result<i64, AppError> { let n = parse_int(s)?; Ok(n) }
```
```err
'?' cannot convert the error 'ParseIntError' into 'AppError'
```
The help is the impl to add: `impl From<ParseIntError> for
AppError { fn from(e: ParseIntError) -> AppError { ... } }`.

```tach
struct M { m: i64 }
impl Into<M> for i64 { fn into(self) -> M { M { m: self } } }
```
```err
From
```
Implement `From<i64> for M`; `Into` comes with it. `x.into()` needs the
type it converts to: `let y: M = x.into();`.

```tach
fn f(a: i64, b: i64) -> i64 { a + b }
fn main() -> i32 { f(b: 1, 2) as i32 }
```
```err
a positional argument after a named one: the named arguments come last
```
Named arguments follow the positional ones, in the parameters' order
(`f(1, c: 3, b: 2)` is an error whose `try:` is `f(1, b: 2, c: 3)`); a
missing one without a default gets `try: f(1, b: VALUE)`, a misspelt
name the nearest.

```tach
trait T { fn f(x: i64 = 1) -> i64; }
```
```err
a default value is for a parameter of a function or an inherent method, not of a trait function
```
Defaults go on trailing parameters of `fn` items and inherent methods,
not on trait or extern functions, closures or `fn` types.

```tach
struct P { x: i64, y: i64 }
fn main() -> i32 { let x = 1; let p = P { x, y }; p.x as i32 }
```
```err
undefined variable 'y'
```
The shorthand `P { x, y }` takes locals of the fields' names: write
`y: VALUE`.

```tach
#[derive(Debg)]
struct P { x: i64 }
```
```err
did you mean 'Debug'
```
Derivable: `Eq`, `Ord`, `Hash`, `Debug`, `Clone` (Display is written by
hand). Deriving a trait and implementing it too is a coherence error
whose help is `remove Ord from #[derive]`; deriving `Eq` needs `==` on
every field.

```tach
struct P { x: i64 }
fn main() -> i32 { let p = P { x: 1 }; println(f"{p}"); 0 }
```
```err
'P' does not implement Display
```
Implement it (`impl Display for P { fn fmt(self, f: inout std::Fmt) {
f.write(f"P({self.x})"); } }`), or print with `{p:?}` and
`#[derive(Debug)]`. Rust's `fn fmt(&self, f: &mut Formatter) ->
fmt::Result` is `fn fmt(self, f: inout Fmt)`, with nothing to return.

```tach
fn main() -> i32 { let x = 1; println(f"{f"{x}"}"); 0 }
```
```err
f-strings cannot be nested
```
Compute the inner one in a `let` first. A `:` outside brackets ends a
hole (the spec follows): parenthesize, `{(|x: i64| x + 1)(n)}`.

## Generics and traits

```tach
fn biggest<T>(a: sink T, b: sink T) -> T { if a > b { a } else { b } }
struct P { x: i64 }
fn main() -> i32 { let p = biggest(P { x: 1 }, P { x: 2 }); 0 }
```
```err
error[type error] comparison requires numeric type, got 'P' | note: in instantiation of 'biggest<P>'
```
A generic body is checked per use; the note names the instance.
Implement `Ord` for `P`, or bound `T: Ord` to say what it needs.

```tach
trait A { fn a(self) -> i64; fn b(self) -> i64; }
struct S { }
impl A for S { fn a(self) -> i64 { 1 } }
```
```err
error[type error] the impl of trait 'A' is missing 'b' | help: it has no default: write it in the impl
```

```tach
trait A { fn a(self) -> i64; }
fn f(x: &dyn A) -> i64 { 0 }
```
```err
error[parser error] 'dyn' is a reserved keyword
```
No trait objects: `fn f<T: A>(x: T)`, or an enum of the cases.

```tach
struct K { n: i64 }
impl Ord for K { fn cmp(self: *K, o: *K) -> i64 { 0 } }
fn main() -> i32 { 0 }
```
```err
error[type error] 'cmp' does not have the signature trait 'Ord' declares: expected 'fn(K, K) -> i64'
```
An impl takes what the trait declares, as let parameters: `fn cmp(self,
o: K) -> i64` (`*K` is a raw pointer).

## Modules and imports

```tach
use std::*;
```
```err
error[module error] wildcard imports are not allowed
```
`use std::{Buf, HashMap};`; `volec fix --only imports` writes them.

```tach
mod m { pub fn helper() -> i64 { 1 } }
fn main() -> i32 { helper() as i32 }
```
```err
error[type error] undefined variable 'helper' | help: add `use crate::m::helper;`
```
Add the `use` line the help names, or run the `try:` line, `volec fix
--suggested main.vl`, which adds every missing one (and makes the
other errors' exact fixes; `fix --only imports`: the imports alone).

In a module other than the root, a path starts in that module, or with
a sibling module, or one of the root (0.17): `use table::Table;` and
`table::f(x)` in check.vl are `crate::table::...` when `mod table;` is
in main.vl. A module elsewhere (`crate::a::table`) is `unknown module
'table'`, whose help says `crate::a::table::...` and whose `try:` is the
`use` line so written (in code: `use crate::a::table;`). `mod util;` with no util.vl is
`cannot find the file of module 'util'`, whose `try:` makes it:
`volec edit new-file util.vl main.vl < util.vl` (the text on
stdin; the `mod` line that is there stays). A `mod` line for a file that
is next to a submodule's file belongs in the root.

```tach
fn main() -> i32 { let text = read_to_string(); 0 }
```
```err
error[type error] undefined variable 'read_to_string' | help: std reads stdin: `read_stdin_in(gpa)` (all of it, a Buf)
```
std's items outside the prelude get their `use` line (`add `use
std::is_digit;``) or the nearest std name; an unknown function with neither points to `volec
guide std`.

```tach
fn main() -> i32 { let total = 1; std::print_int(totl); 0 }
```
```err
error[type error] undefined variable 'totl' | help: did you mean 'total'?
```
A module and an item of the same name both work, as in Rust: after `mod
eval; use eval::eval;`, `eval(x)` calls the function and `eval::NAME`
goes through the module.

```tach
mod m { fn hidden() -> i64 { 1 } }
fn main() -> i32 { m::hidden() as i32 }
```
```err
error[type error] 'hidden' is private | help: make it public: `pub fn hidden` at
```
The help gives the declaration with `pub` and where it is (`volec fix
--only pub` writes them all). Child modules see their parent's private items, not
the reverse.

## unsafe

```tach
extern "C" { fn abs(x: i32) -> i32; }
fn main() -> i32 { abs(-3) }
```
```err
error[unsafe] calling a C function is unsafe
```
`unsafe { abs(-3) }`. The error's `try:`, `volec fix --only unsafe
main.vl`, wraps every such place; the check hook prints it once at the
head of its report, with how many errors it answers.

```tach
fn helper() -> i64 { let v: Vec<i64> = Vec::new(); v.len() }
fn main() -> i32 { helper() as i32 }
```
```err
add the parameter `gpa: Gpa` to 'helper' and pass it down
```
Allocation is explicit (0.16): the help says where the allocator comes
from here (this function's `gpa`, main's parameter, or one to add), and
the `try:`, `volec fix --only alloc016 main.vl`, threads main's
`gpa` down to every such call.

```tach
struct P { x: i64 }
fn main() -> i32 {
    var p = P { x: 1 };
    let q: *P = &p;
    q.x = 9;
    0
}
```
```err
error[unsafe] access to a field through a raw pointer is unsafe
```
A local declared `*P` holds a raw pointer. Use `p.x = 9;`, an inout
local (`inout q = &p; q.x = 9;`, safe), or pass `&p` to a function
taking `p: inout P`.

```tach
struct P { x: i64 }
fn one() -> i64 { 1 }
fn get(n: i64, p: inout P) -> i64 { n + p.x }
fn main() -> i32 { get(one(), &P { x: one() }) as i32 }
```
```err
error[type error] cannot take address of non-lvalue expression
```
`&` lends a place (a variable, a field, an element) inout. A let
parameter takes a value as it is (`get(one(), P { x: 1 })` for `p: P`);
for an inout one, `&f(x)` or `&P { x: 1 }` makes a temporary (0.18.1),
unless something evaluated before it in the statement (`one()` here, a
call) could see the difference: then name it first: `var t = P { x:
one() }; get(one(), &t)`.

```tach
fn factorial(n: i64) -> i64 { if n < 2 { 1 } else { n * factorial(n - 1) } }
fn main() -> i32 { let f = &factorial; f(5) as i32 }
```
```err
error[type error] cannot take the address of 'factorial': a function's name is already a pointer to it
```
A function's name is a `fn(i64) -> i64` value: `let f = factorial;`,
then `f(5)`; `(*f)(5)` is `f(5)` too. `fix --suggested` drops the `&`
(the `*`).

```tach
fn first(p: *i64) -> i64 { p[1] }
```
```err
error[unsafe] indexing a raw pointer is unsafe
```
A pointer is one value; for many, take a slice `[i64]`. A Vec, Buf or
slice parameter (`v: Vec<i64>`, `v: inout Vec<i64>`) indexes its
elements, checked and safe; through a `*T` it needs `unsafe`. To write
one number for the caller, take `out: inout i64` and write `out = acc`.

```tach
fn read(x: *i64) -> i64 { *x }
```
```err
error[unsafe] dereference of a raw pointer is unsafe: `x` is a `*T` parameter
```
A `*T` parameter is a raw pointer (0.18.1), as in Rust. Take it let,
`x: i64` (`x: inout i64` when written through, called with `&n`;
`volec fix --values` changes such parameters with their calls), or vouch for it in
`unsafe { *x }` (`fix --only unsafe`). The same for a field access, a
method call and an index through it.

```tach
unsafe fn danger() -> i64 { 1 }
fn main() -> i32 { let f = danger; 0 }
```
```err
error[unsafe] using an `unsafe fn` as a value is unsafe
```
Call it in `unsafe`, or wrap it in a safe `fn`.

```tach
fn main() -> i32 { std::print_cstr(c"x"); 0 }
```
```err
error[unsafe] calling an `unsafe fn` is unsafe
```
`std::panic`, `print_cstr` and `Buf::push_cstr` take C strings and are
`unsafe fn`; for literals use `print("x")`, `panic("x")` (the prelude's,
safe).

## Conventions, moves and views (0.17, 0.20)

A parameter is let (read-only, the default), `inout` (it may change
the caller's value: the call marks it `&x`) or `sink` (it takes the
value). The call must say what the parameter says:

```tach
struct P { x: i64 }
fn bump(p: inout P) { p.x += 1; }
fn main() -> i32 { var q = P { x: 1 }; bump(q); q.x as i32 }
```
```err
error[conv.marker] 'q' is lent inout here (the callee may change it): mark it '&q'
```
`bump(&q)`: `&` shows at the call what may change. When the callee only
reads, the help's `volec refactor signature bump --convention p let`
makes it a let parameter, with every call.

```tach
fn total(v: Vec<i64>) -> i64 { v.len() }
fn main(gpa: Gpa) -> i32 { let v: Vec<i64> = Vec::new_in(gpa); total(&v) as i32 }
```
```err
error[conv.marker_extra] '&' marks an argument the callee may change; 'v' is taken let or sink here (read, or moved): pass 'v'
```
`total(v)`: a let parameter borrows `v` for the call, unmarked, and `v`
stays the caller's.

```tach
fn fill(v: Vec<i64>) { v.push(1); }
```
```err
error[own.readonly] writes through 'v'
```
A let parameter is read-only: take it `v: inout Vec<i64>` and call
`fill(&v)` (the `try:`, `volec refactor signature fill --convention
v inout`, changes both); a slice to sort in place is `s: inout [T]`,
passed as `&v` or `&a[..]`.

```tach
fn keep(v: sink Vec<i64>) -> i64 { v.len() }
fn main(gpa: Gpa) -> i32 { let v: Vec<i64> = Vec::new_in(gpa); keep(v); v.len() as i32 }
```
```err
error[own.moved] 'v' is used here after it moved into 'keep(sink v)'
```
A `sink` parameter takes the value; the caller's `v` is dead after the
call. When `keep` only reads, make it let (`v: Vec<i64>`: nothing
moves; `refactor signature keep --convention v let`); else pass
`keep(v.clone())` or use `v` before. An owned value also moves with
`let w = v;`, `return v` and into a struct literal.

The own pass's errors (`own.*`) are one line each, with both positions,
a `help:` with the fix and `try:` lines; `volec explain own.CODE` has
each in full, `volec query own FILE:LINE:COL` the state of every
local there.

```tach
struct T { keys: Vec<i64> }
impl T { fn rehash(inout self) { var old = self.keys; old.push(1); } }
```
```err
error[own.move_out] cannot move 'self.keys' (Vec<i64>) out of a reference
```
`var old = self.keys.take();` leaves an empty Vec on the same allocator
(`std::take(&x)` for a `Default` value, `std::replace(&x, v)`); `let
old = self.keys;` reads it where it is (a `let` of a part borrows it).

```text
error[own.conflict] 'v.push(4)' may move v's elements while 'first' (4:17) views them; 'first' is used at 6:16
error[own.conflict] 'v.push' may move v's elements while the 'for' at 7:1 iterates over them
error[own.conflict] 'a' is lent inout to '&a' and inout again to '&a' in the same call
```
A view (a slice, a let or inout access, a `for` over `v`) is still used
after `v` changes, or one value is lent inout twice at once. Use the
view before the change, or take it again after; keep an index (`for i
in 0..v.len() { let x = v[i]; ... }`); copy a plain value out first
(`let x = v[0];`); `v.swap(i, j)` for two elements; `let n =
rng.next();` before `rng.big(n)`. `guide views` has the rules.

```text
error[own.escape] 'greet' returns a view of 'b', which is dropped when 'greet' returns
```
Return the `Buf` (`-> Buf`, `b`), not `b.as_slice()`; the caller takes
the view.

```text
error[own.readonly] changes 'v' (Vec<i64>), a copy the match on 'e' (2:26) binds: the change would not reach it, and could free memory it points to
error[own.readonly] changes 'w' (Vec<i64>), a copy of an element 'vv.get(0)' reads: ...
```
(0.18.1) `match e`, `v.get(i)` and a `for` loop's element give a copy
of an owned value that stays where it is: read it, do not change it.
Match through an inout access instead (`match &e` binds `v` inout, for
`e: inout E` or a `var e`), or change the element in place
(`vv[0].push(1)`).

## At run time

A failed check prints its message on stderr and exits with code 101:
`index out of bounds: index I, length N`, `slice range out of bounds:
...`, `called unwrap on None`, `called unwrap on Err`, `invalid value V
for enum E`. A note follows (0.17). A program built with `--trace`
prints, instead, the failing line and the calls that led to it
(`volec test` builds so; `guide debug`). Arithmetic never fails (it
wraps; `/ 0` is 0). Runaway recursion is stopped by the operating system
(a signal, no message).

```tach
enum Level { Low, High }

fn main() -> i32 {
    let v: Option<i64> = None;
    std::print_int(v.unwrap_or(5));
    println("");
    let e = 3 as Level;
    std::print_int(e as i64);
    0
}
```
```out (exit 101)
5
main.vl:7:13: invalid value 3 for enum Level
```
