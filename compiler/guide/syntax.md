# Syntax

The whole grammar is docs/grammar.md; this is what a program uses.

## Lexical

- Comments: `// line`, `/* block, nesting */`. No doc-comment syntax:
  `//` above an item is its comment.
- Identifiers: ASCII letters, digits, `_`; `_` alone is the wildcard.
  `r#type` is the identifier `type` (C names that are keywords).
- Keywords: `as break const continue defer else enum extern false fn for
  if impl import in let loop match mod mut pub return static struct
  trait true type union unsafe use while move` (0.14). Reserved (errors):
  `where`, `dyn`, `@`. `self`, `Self`, `super`, `crate` are names.
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
static mut COUNTER: i64 = 0;        // a global; safe to use
type Grid = [[u8; 8]; 8];           // an alias; `type P<T> = (T, T);`

pub struct Point { x: i64, y: i64 }
struct Wrapper<T> { inner: T }      // generic
enum Dir { North, South }           // fieldless: compares with ==, casts with `as`
enum Tok { Num(i64), Op(u8), End }  // tuple variants
#[repr(C)] union Bits { i: u32, f: f32 }

pub fn add(a: i64, b: i64) -> i64 { a + b }
fn first<T>(s: [T]) -> T { s[0] }
fn ignore(_: i64) {}                 // `_` ignores an argument
fn bump(mut n: i64) -> i64 { n += 1; n }   // a mutable parameter
unsafe fn raw(p: *i64) -> i64 { p[0] }     // callers need unsafe

impl Point {
    fn len2(self: *Point) -> i64 { self.x * self.x + self.y * self.y }
}

trait Named { fn name(self: *Self) -> [u8]; }
impl Named for Point { fn name(self: *Point) -> [u8] { "point" } }

mod util { pub fn twice(x: i64) -> i64 { x * 2 } }

extern "C" { fn abs(x: i32) -> i32; }
extern "C" fn callback(x: i32) -> i32 { x + 1 }
```

Items may come in any order and refer to each other. Attributes:
`#[repr(C)]`, `#[repr(C, packed)]`, `#[repr(C, align(16))]`,
`#[repr(u8)]` (an enum's tag), `#[inline]`, `#[inline(never)]`,
`#[cold]`; any other is an error.

## Statements and blocks

```tach
let x = 1;                          // immutable
let mut y: i64 = 2;                 // mutable, with a type
let (a, b) = (3, 4);                // patterns that always match
y += x + a * b;                     // = += -= *= /= %= &= |= ^= <<= >>=
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
| prefix `-` `!` `~` `*` `&` | `!` on bool, `~` bitwise not |
| `f()` `a[i]` `a[i..j]` `x.f` `x.0` `x.m()` | `*p.x` is `*(p.x)` |

No `**` (power), no ternary (`if c { a } else { b }` is an
expression). `e?` (0.15) is postfix, as tight as a call: `parse(s)?.len`
(`tachyonc guide conversions`). `return`,
`break`, `continue` have type `!` and fit anywhere:
`let v = if ok { x } else { return 1 };`.

In an `if`, `while`, `match` or `for` head, `Name {` starts the body: put
a struct literal there in parentheses, `if p == (P { x: 1 }) { ... }`.

## Control flow

```tach
fn main(gpa: Gpa) -> i32 {
    let n = 7;
    let parity = if n % 2 == 0 { "even" } else { "odd" };
    println(parity);
    let mut i = 0;
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
    let mut stack: Vec<i64> = Vec::new_in(gpa);
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
`'a'..='z'`, alternatives `A | B`, a variant `E::V(x, _)`, a tuple
`(a, 0)`, a binding (`n`), `_`, with a guard `n if n > 0`. The arms must
cover every value; a match is an expression.
