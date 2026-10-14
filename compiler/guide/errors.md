# Errors and their fixes

Compile with `--diagnostics=short` (or run `tachyonc check`): one line
per error, `FILE:LINE:COL: error[KIND] MESSAGE | help: HELP | note:
NOTE`, every error of every file at once (up to 50), sorted by position.
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
error[type error] unknown type 'String' | help: text is `[u8]`, a slice of bytes (string literals are one); build it in a `std::Buf`
```
Also `str`, `char` (use `u8`), `Box`, `usize` indices (use `i64`).

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
fn f(r: Result<i64, i64>) -> i64 { let x = r?; x }
```
```err
error[type error] '?' needs 'f' to return Option or Result; it returns 'i64' | help: make it return a Result: '-> Result<i64, i64>'
```
`?` returns the None or the Err from the function, so the function
returns an Option or a Result (an error converted by `From`); `fn main()
-> Result<(), E>` prints an Err and exits with 1.

```tach
println!("{}", 1);
```
```err
error[parser error] 'println!' is a macro call: tachyon has no macros | help: `println(s)` and `print(s)` take a [u8]; numbers: `std::print_int(n)`; or build the text in a `std::Buf` (`push_str`, `push_int`) and print `b.as_slice()`
```
The help names what replaces `vec!`, `format!`, `assert!` and the others.

```tach
'outer: for i in 0..3 { break 'outer; }
```
```err
error[tokenizer error] unterminated character literal
```
Labels have no quote: `outer: for i in 0..3 { break :outer; }`.

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
let big = i64::MAX;
```
```err
error[type error] no associated function 'MAX' in 'i64' | help: std has the limits: 'std::I64_MAX'
```
std has the limits: `std::I64_MAX`, `std::U8_MAX`, ...

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
#[derive(Debug)]
struct P { x: i64 }
```
```err
error[type error] #[derive] attributes are not implemented yet (check.unimplemented)
```
`#[derive(Eq, Ord, Hash, Debug, Clone)]` is coming in 0.15; `==` is
structural without it.

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
No implicit narrowing: `a as i32`. A narrower integer widens (i32 to
i64, u8 to u32 or i16); never signed to unsigned, nor between integers
and floats (`1 + 1.0`).

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
error[type error] non-exhaustive match: 'E::C' is not covered | help: add an arm for it, or a wildcard arm '_ =>'
```

```tach
enum E { A(i64), B }
fn f(e: E) -> i64 { match e { A(x) => x, B => 0 } }
```
```err
error[type error] unknown variant 'A'
```
`E::A(x)`, or `use E::{A, B};` once.

```tach
struct P { x: i64 }
fn main() -> i32 {
    let p = P { x: 1 };
    if p == P { x: 1 } { println("same"); }
    0
}
```
```err
error[parser error] expected ';' or '}' after expression, got ':'
```
In a condition, parenthesize a struct literal: `if p == (P { x: 1 })`.

## Slices, Vec, std

```tach
let mut v: Vec<i64> = Vec::new();
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
fn main() -> i32 { let mut b = Buf::new(); b.push_string("x"); 0 }
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
let b = Buf::new();
```
```err
error[type error] unknown type 'Buf'
```
`use std::Buf;` (only the prelude names need no import).

```tach
use std::HashMap;
struct K { a: i64 }
fn main() -> i32 { let m: HashMap<K, i64> = HashMap::new(); 0 }
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
Add the `use` line the help names, or run `tachyonc fix`.

```tach
fn main() -> i32 { let text = read_to_string(); 0 }
```
```err
error[type error] undefined variable 'read_to_string' | help: std reads stdin: `std::read_stdin()` (all of it, a Buf), `std::read_line(&buf)` (one line, Ok(false) at the end), `std::Scanner` (tokens)
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
`unsafe { abs(-3) }`. `tachyonc fix --only unsafe` wraps every such
place.

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
