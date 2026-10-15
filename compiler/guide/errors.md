# Errors and their fixes

`tachyonc check`, and a build whose output is not a terminal (an
agent's shell, a pipe; `--diagnostics=short` anywhere): one line per
error, `FILE:LINE:COL: error[KIND] MESSAGE | help: HELP | note: NOTE |
try: TRY`, every error of every file at once (up to 50), sorted by
position. A `try:` (0.17) is text to use as it is: code to paste where
the error is (`a as i32`, `std::trim(s)`, the missing match arms), a
`use` line, or a `tachyonc` command to run (`tachyonc fix --only unsafe
main.tach`, `tachyonc edit new-file util.tach main.tach`); VALUE in it
is yours to fill in.
KIND is `tokenizer error`, `parser error`, `module error`, `type error`
or `unsafe`. Fix the first errors first: a parser error can hide
type errors in the same function. `tachyonc query show FILE:LINE` prints
the item at an error's position. Below: what a newcomer writes, the
error (short form, without the position), and the fix.

## Rust habits

```tach
let s: String = String::new();
```
```err
error[type error] unknown type 'String' | help: text is `[u8]`, a slice of bytes (string literals are one); text you build is a `std::Buf` (`Buf::new_in(gpa)`, `b.push_str(s)`, `b.as_slice()` is its `[u8]`) | try: [u8]
```
The `try:` is the type to write. Also `str` (`[u8]`), `char` (`u8`),
`Box`, `Rc` (`*T`), `HashSet` (`HashMap<K, bool>`), `BTreeMap`,
`VecDeque`, `RefCell`.

```tach
use std::collections::HashMap;
```
```err
error[type error] no 'collections' in module 'std' | help: tachyon's std is one module, without 'collections': its items are `std::NAME` | try: use std::HashMap;
```
std has no submodules: `use std::{HashMap, read_line};`. `use std::io;`
gets what reads stdin (`read_line`, `read_stdin_in`, `Scanner`).

```tach
fn main() -> i32 { let s = "  a "; let t = s.trim(); 0 }
```
```err
error[type error] no method 'trim' on type '[u8]' | help: 'trim' is no method: std's function `trim` takes the value as its first argument | try: std::trim(s)
```
A method std has as a function (`trim`, `sort`, `parse` as `parse_int`,
`split_whitespace` as `split_whitespace_in(s, gpa)`) gets the call to
write; another unknown method, the type's nearest methods and `tachyonc
query items TYPE`, which lists them all.

```tach
fn get(x: &i64) -> i64 { *x }
```
```err
error[parser error] expected type, got '&' | help: write `*T`: one pointer type for `&T` and `&mut T`
```
`*i64`; `&str` is `[u8]`. In an expression, `&mut x` is `&x`.

```tach
struct P { x: i64 }
impl P { fn get(&self) -> i64 { self.x } }
```
```err
error[parser error] expected identifier, got '&' | help: write the type of self: `self: *T` (a pointer: `&self`, `&mut self`) or `self: T` (a copy)
```
`fn get(self: *P) -> i64`; `fn get(self)` is an error too: write
`self: P` for a copy.

```tach
println!("{}", 1);
```
```err
error[parser error] 'println!' is a macro call: tachyon has no macros | help: write `println(f"{1}")`
```
`println(f"{x}")` (0.15, `tachyonc guide formatting`). The help names
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
`let x = match o { Some(x) => x, None => return 1 };` (no `let else`).

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
fn f<T>(x: T) -> T where T: Ord { x }
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
error[type error] cannot assign to immutable variable 'x' | help: make it mutable: `let mut x`
```

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
either (`tachyonc edit delete main.tach:3 main.tach`); to change an item
in place, `tachyonc edit replace f < new.tach` instead of adding a second.

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
let mut v: Vec<i64> = Vec::new_in(gpa);
v.push(1);
let a = v[0];
```
```err
error[type error] cannot index type 'Vec<i64>'
```
`v.get(0)`, `v.set(0, x)`, `v.as_slice()[0]`.

```tach
let n = 3;
for x in n { }
```
```err
error[type error] 'for' iterates over ranges, slices, arrays, iterators and types with an 'iter' method, got 'i64'
```
`for x in 0..n`. A type of yours iterates with `impl Iterator for T`, or
an `iter` method returning one (`tachyonc guide iterators`).

```tach
let s = "abc";
let n = s.len();
```
```err
error[type error] no method 'len' on type '[u8]' | help: `len` is a field of slices: `s.len`
```
(`Vec` has the method `len()`.) A misspelt method, field or item gets
the nearest name of its kind:

```tach
use std::Buf;
fn main(gpa: Gpa) -> i32 { let mut b = Buf::new_in(gpa); b.push_string("x"); 0 }
```
```err
error[type error] no method 'push_string' on type 'Buf' | help: did you mean 'push_str'?
```

```tach
fn sum(s: [i64]) -> i64 { s[0] }
fn main() -> i32 { let a = [1, 2, 3]; sum(a) as i32 }
```
```err
error[type error] expected '[i64]', got '[i64; 3]'
```
`sum(a[..])`. An array has no `.len` either: `a[..].len`.

```tach
let b = Buf::new_in(gpa);
```
```err
error[type error] unknown type 'Buf'
```
`use std::Buf;` (only the prelude names need no import).

```tach
use std::HashMap;
struct K { a: i64 }
fn main(gpa: Gpa) -> i32 { let m: HashMap<K, i64> = HashMap::new_in(gpa); 0 }
```
```err
error[type error] the trait 'Hash' is not implemented for 'K' | help: required by the bound 'K: Hash' of 'HashMap'
```
`impl Hash for K { fn hash(self: *K) -> u64 { std::hash_u64(self.a as u64) } }`.

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
fn apply<F: Fn(i64)>(f: F) { f(1); }
fn main() -> i32 {
    let mut total = 0;
    apply(|x| { total += x; });
    total as i32
}
```
```err
FnMut
```
`Fn` takes closures that assign no captured variable: bound `F:
FnMut(i64)` (and call it from a `mut f: F`).

```tach
fn apply<F: Fn(i64) -> i64>(f: F) -> i64 { f(1) }
fn main() -> i32 {
    let f = {
        let mut j = 1;
        |x: i64| x + j
    };
    apply(f) as i32
}
```
```err
write `move`
```
The closure borrows `j` (a `let mut`), which ends with the block: `move
|x: i64| x + j` takes a copy, or declare `j` before the block.

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
use std::{ParseIntError, parse_int};
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
impl Into<M> for i64 { fn into(self: i64) -> M { M { m: self } } }
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
Implement it (`impl Display for P { fn fmt(self: *P, f: *std::Fmt) {
f.write(f"P({self.x})"); } }`), or print with `{p:?}` and
`#[derive(Debug)]`. Rust's `fn fmt(&self, f: &mut Formatter) ->
fmt::Result` is `fn fmt(self: *P, f: *Fmt)`, with nothing to return.

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
fn biggest<T>(a: T, b: T) -> T { if a > b { a } else { b } }
struct P { x: i64 }
fn main() -> i32 { let p = biggest(P { x: 1 }, P { x: 2 }); 0 }
```
```err
error[type error] comparison requires numeric type, got 'P' | note: in instantiation of 'biggest<P>'
```
A generic body is checked per use; the note names the instance.
Implement `Ord` for `P`, or bound `T: Ord` to say what it needs.

```tach
trait A { fn a(self: *Self) -> i64; fn b(self: *Self) -> i64; }
struct S { }
impl A for S { fn a(self: *S) -> i64 { 1 } }
```
```err
error[type error] the impl of trait 'A' is missing 'b' | help: it has no default: write it in the impl
```

```tach
trait A { fn a(self: *Self) -> i64; }
fn f(x: *dyn A) -> i64 { 0 }
```
```err
error[parser error] 'dyn' is a reserved keyword
```
No trait objects: `fn f<T: A>(x: *T)`, or an enum of the cases.

## Modules and imports

```tach
use std::*;
```
```err
error[module error] wildcard imports are not allowed
```
`use std::{Buf, HashMap};`; `tachyonc fix --only imports` writes them.

```tach
mod m { pub fn helper() -> i64 { 1 } }
fn main() -> i32 { helper() as i32 }
```
```err
error[type error] undefined variable 'helper' | help: add `use crate::m::helper;`
```
Add the `use` line the help names, or run the `try:` line, `tachyonc fix
--only imports main.tach`, which adds every missing one.

In a module other than the root, a path starts in that module: `use
table::Table;` in check.tach is `unknown module 'table'` when `mod
table;` is in main.tach; the help says `crate::table::...` and the
`try:` is the `use` line so written. `mod util;` with no util.tach is
`cannot find the file of module 'util'`, whose `try:` makes it:
`tachyonc edit new-file util.tach main.tach < util.tach` (the text on
stdin; the `mod` line that is there stays). A `mod` line for a file that
is next to a submodule's file belongs in the root.

```tach
fn main() -> i32 { let text = read_to_string(); 0 }
```
```err
error[type error] undefined variable 'read_to_string' | help: std reads stdin: `std::read_stdin_in(gpa)` (all of it, a Buf), `std::read_line(&buf)` (one line, Ok(false) at the end), `std::Scanner` (tokens)
```
std's items get their `use` line (`add `use std::read_line;``) or the
nearest std name; an unknown function with neither points to `tachyonc
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
The help gives the declaration with `pub` and where it is (`tachyonc fix
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
`unsafe { abs(-3) }`. The error's `try:`, `tachyonc fix --only unsafe
main.tach`, wraps every such place; the check hook prints it once at the
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
the `try:`, `tachyonc fix --only alloc016 main.tach`, threads main's
`gpa` down to every such call.

```tach
struct P { x: i64 }
fn main() -> i32 {
    let mut p = P { x: 1 };
    let q = &p;
    q.x = 9;
    0
}
```
```err
error[unsafe] access to a field through a raw pointer is unsafe
```
A local holding a pointer is raw. Use `p.x = 9;`, or pass `&p` to a
function taking `*P` (a borrow, safe there).

```tach
struct P { x: i64 }
fn get(p: *P) -> i64 { p.x }
fn main() -> i32 { get(&P { x: 1 }) as i32 }
```
```err
error[type error] cannot take address of non-lvalue expression
```
`&` takes the address of a place (a variable, a field, an element):
`let p = P { x: 1 }; get(&p)`.

```tach
fn first(p: *i64) -> i64 { p[1] }
```
```err
error[unsafe] indexing a raw pointer is unsafe
```
A pointer is one value; for many, take a slice `[i64]`.

```tach
fn read(x: *i64) -> i64 { *x }
struct H { p: *i64 }
fn get(h: H) -> i64 { read(h.p) }
```
```err
error[unsafe] passing a raw pointer to a pointer parameter is unsafe
```
Only `&place` and pointer parameters are borrows; vouch for others in
`unsafe { read(h.p) }`.

```tach
fn add(p: *i64, x: i64) { *p += x; }
fn main() -> i32 { let f = add; 0 }
```
```err
error[unsafe] using an `unsafe fn`, or a function with pointer parameters, as a value is unsafe
```
`let f = unsafe { add };` and call it in `unsafe` too.

```tach
fn main() -> i32 { std::print_cstr(c"x"); 0 }
```
```err
error[unsafe] calling an `unsafe fn` is unsafe
```
`std::panic`, `print_cstr` and `Buf::push_cstr` take C strings and are
`unsafe fn`; for literals use `print("x")`.

## At run time

A failed check prints one line on stderr and exits with code 101:
`index out of bounds: index I, length N`, `slice range out of bounds:
...`, `called unwrap on None`, `called unwrap on Err`, `invalid value V
for enum E`. Arithmetic never fails (it wraps; `/ 0` is 0). Runaway
recursion is stopped by the operating system (a signal, no message).

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
invalid value 3 for enum Level
```
