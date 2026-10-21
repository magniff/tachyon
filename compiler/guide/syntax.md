# Syntax

The whole grammar is docs/grammar.md; this is what a program uses.

## Lexical

- Comments: `// line`, `/* block, nesting */`. No doc-comment syntax:
  `//` above an item is its comment.
- Identifiers: ASCII letters, digits, `_`; `_` alone is the wildcard.
  `r#type` is the identifier `type` (C names that are keywords).
- Keywords: `as break const continue defer else enum extern false fn for
  if impl import in let loop match mod pub return static struct trait
  true type union unsafe use var while`; `inout` and `sink` (0.20) are
  words where a convention, a binding or a closure starts. Reserved
  (errors): `where`, `dyn`, `@`; `mut` and `move` are Rust's spellings,
  each a `conv.rust` error naming tachyon's (`var`, `sink ||`). `self`,
  `Self`, `super`, `crate` are names.
- Integers: `42`, `1_000`, `0xff`, `0b1010`, with a type suffix
  `255u8`, `7i32`. Floats: `1.5`, `2e10`, `1.5f32`. Chars: `'a'`, `'\n'`,
  `'\x41'`, `'\''` (one byte, a `u8`). Strings: `"a\tb\n\"q\"\\"`,
  `"\x41"`, `"\u{e9}"` (UTF-8 bytes); `c"..."` is NUL-terminated;
  `f"x = {x:>4}"` is an f-string (0.15, `guide formatting`). A
  backslash at the end of a line inside a string continues it, leaving
  out the line break and the next line's indentation.

## Items

```tach
use std::Buf;                       // imports first, by convention
import "stdio.h" as c;              // a C header

const LIMIT: i64 = 100;             // a constant expression
const NAMES: [i64; 3] = [1, 2, 3];  // array constants too
static var COUNTER: i64 = 0;        // a global; safe to use
type Grid = [[u8; 8]; 8];           // an alias; `type P<T> = (T, T);`

pub struct Point { x: i64, y: i64 }
struct Wrapper<T> { inner: T }      // generic
enum Dir { North, South }           // fieldless: compares with ==, casts with `as`
enum Tok { Num(i64), Op(u8), End }  // tuple variants
enum Ev { Key { code: u8, shift: bool }, Quit }   // struct-like variants (0.17)
#[repr(C)] union Bits { i: u32, f: f32 }

pub fn add(a: i64, b: i64) -> i64 { a + b }
fn first<T>(s: [T]) -> T { s[0] }
fn ignore(_: i64) {}                 // `_` ignores an argument
fn bump(n: sink i64) -> i64 { n += 1; n }  // sink: the callee's own, mutable
fn twice(v: inout Vec<i64>) { v.push(v.len()); }   // inout: called as twice(&v)
unsafe fn raw(p: *i64) -> i64 { p[0] }     // callers need unsafe

impl Point {
    fn len2(self) -> i64 { self.x * self.x + self.y * self.y }   // self: let
    fn move_by(inout self, d: i64) { self.x += d; }               // p.move_by(1)
}

trait Named { fn name(self) -> [u8]; }
impl Named for Point { fn name(self) -> [u8] { "point" } }

mod util { pub fn twice(x: i64) -> i64 { x * 2 } }

extern "C" { fn abs(x: i32) -> i32; }
extern "C" fn callback(x: i32) -> i32 { x + 1 }
```

Items may come in any order and refer to each other. A parameter's
convention is written before its type: `x: T` (let, the default: read
only, a copy of a plain value or a borrow of an owned one), `x: inout T`
(changed for the caller, who passes `&place`), `x: sink T` (the callee
takes it; an owned argument moves). Receivers: `self`, `inout self`,
`sink self`. Attributes:
`#[repr(C)]`, `#[repr(C, packed)]`, `#[repr(C, align(16))]`,
`#[repr(u8)]` (an enum's tag), `#[inline]`, `#[inline(never)]`,
`#[cold]`; any other is an error.

## Statements and blocks

```tach
let x = 1;                          // immutable
var y: i64 = 2;                     // mutable, with a type
let (a, var b) = (3, 4);            // patterns that always match; `var` per name
b += 0;
inout r = &y;                       // an access to y: r is used as y itself
r += x + a * b;                     // = += -= *= /= %= &= |= ^= <<= >>=
defer println("last");              // runs when the block exits
{
    let inner = y;                  // a block is an expression
    std::print_int(inner);
}
println("");
```
```out
15
last
```

The binding forms: `let x = e` (immutable: takes `e` when this
function owns it, which moves an owned local; borrows a part it cannot
take, such as `v[i]`), `var x = e` (mutable, always owns), `inout x =
&place` (an exclusive access: reading `x` reads the place, `x = v` and
`x.push(1)` change it; it is not re-pointed). There is no uninitialized
`let x;`.

A statement that starts with `if`, `match`, `loop`, `while`, `for`,
`unsafe` or a block ends at its `}`: no `;` is needed, and it is never
continued by an operator. The last expression of a block, without `;`,
is the block's value. There is no `++`/`--`.

## Expressions and precedence

From loosest to tightest (all left-associative except where noted):

| operators | |
|---|---|
| `=` `+=` `-=` ... | right; an assignment is `()` |
| `\|\|` | |
| `&&` | |
| `==` `!=` `<` `>` `<=` `>=` | not chained: `a < b < c` is an error |
| `\|` then `^` then `&` | bits; `a \| b == c` is `(a \| b) == c` |
| `<<` `>>` | arithmetic `>>` on signed, logical on unsigned |
| `+` `-` | |
| `*` `/` `%` | |
| `as` | `-x as i64` is `(-x) as i64`; `a * b as f64` is `a * (b as f64)` |
| prefix `-` `!` `~` `*` `&` | `!` on bool, `~` bitwise not; `&place` lends it inout; `*p` reads a raw pointer |
| `f()` `a[i]` `a[i..j]` `x.f` `x.0` `x.m()` | `*p.x` is `*(p.x)` |

No `**` (power), no ternary (`if c { a } else { b }` is an
expression). `e?` (0.15) is postfix, as tight as a call: `parse(s)?.len()`
(`tachyonc guide conversions`). `return`,
`break`, `continue` have type `!` and fit anywhere:
`let v = if ok { x } else { return 1 };`.

In an `if`, `while`, `match` or `for` head, `Name {` starts the body: put
a struct literal there in parentheses, `if p == (P { x: 1 }) { ... }`
(0.17: `Name { a: ...` with a field's colon is read as a literal there
too).

## Control flow

```tach
fn main(gpa: Gpa) -> i32 {
    let n = 7;
    let parity = if n % 2 == 0 { "even" } else { "odd" };
    println(parity);
    var i = 0;
    while i < 3 { i += 1; }
    for k in 0..=2 { i += k; }          // 0..n excludes n, 0..=n includes it
    for ch in "ab" { i += ch as i64; }  // slices and arrays, by value
    let v = loop { i += 1; if i % 10 == 0 { break i; } };
    rows: for r in 0..3 {
        for c in 0..3 {
            if c == 1 { continue :rows; }
            if r == 2 { break :rows; }
        }
    }
    let o: Option<i64> = Some(3);
    if let Some(x) = o { i += x; } else if n > 0 { i -= 1; }
    var stack: Vec<i64> = Vec::new_in(gpa);
    stack.push(1);
    while let Some(top) = stack.pop() { i += top; }
    std::print_int(v);
    println("");
    0
}
```
```out
odd
210
```

`match`: arms are tried in order; a pattern may be a literal, a range
`'a'..='z'`, alternatives `A | B`, a variant `E::V(x, _)` or `E::K {
code, shift: true }` (`E::K { code, .. }` leaves the other fields out), a
tuple `(a, 0)`, a binding (`n`), `_`, with a guard `n if n > 0`. The arms must
cover every value; a match is an expression. `Some(var n)` binds a
mutable copy. Matched through an access (a let parameter `e: E`), a
pattern binds let accesses into it, used as values: `match e { E::A(n)
=> n + 1, ... }`. `match &e` binds inout accesses, so an arm changes the
field: `match &s { Shape::Line(n) => n += 1, _ => {} }`. Matching an
owned local by value moves its parts out.
