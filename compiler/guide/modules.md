# Modules and imports

A file is a module. The files on the command line make the root module
(`crate`); `mod name;` in a module loads its child `name` from
`name.tach` or `name/mod.tach` next to it (from `a.tach`: `a/name.tach`).
`mod name { items }` declares one inline.

```text
main.tach            mod geometry;  use geometry::shapes::{Shape, area};
geometry.tach        pub mod shapes;  pub struct Rect { w: i64, h: i64 }
geometry/shapes.tach pub enum Shape { ... }  pub fn area(s: Shape) -> i64 { ... }
```

```sh
tachyonc main.tach -o prog      # loads the modules main.tach names
```

## Visibility

Every item is private to its module and the modules inside it unless
`pub`. A struct's fields are as visible as the struct (no private
fields). Methods are visible wherever their type is. A `pub mod` can be
reached from outside its parent. `pub use a::b;` re-exports `b`.

## Paths and use

A path starts with a name in scope, `crate`, `self`, `super` or `std`:
`geometry::area(s)`, `crate::util::Vec2 { x: 1, y: 2 }`,
`shapes::Shape::Rect(r)`, `util::Stack::<u8>::new()`.

A `use` path may also start with a sibling module (0.17): in
`parser.tach`, where `main.tach` has `mod lexer; mod parser;`,
`use lexer::{Tok, next};` is `use crate::lexer::{Tok, next};`. The
first segment, when the module has no name of its own for it, is a child
of its parent module, else of the root; when both exist and differ, the
error's `try:` lines are the two `crate::` paths. In an expression a
sibling needs its `use crate::lexer;` (or `crate::lexer::next(..)`).

```tach
mod util {
    pub fn double(x: i64) -> i64 { x * 2 }
    pub fn half(x: i64) -> i64 { x / 2 }
    pub enum Mode { Fast, Slow }
    pub mod inner {
        use super::double;               // the parent's item
        pub fn quad(x: i64) -> i64 { double(double(x)) }
    }
}

use util::{double, half as halve};       // by name, with `as` to rename
use util::inner::quad;
use util::Mode::{Fast, Slow};            // an enum's variants

fn speed(m: util::Mode) -> i64 {
    match m { Fast => 10, Slow => 1 }
}

fn main() -> i32 {
    std::print_int(double(3) + halve(8) + quad(1) + speed(Fast) + crate::util::double(1));
    println("");
    0
}
```
```out
26
```

- No wildcard imports (`use m::*;` is an error): every name a file uses
  is declared there, imported by name, or written as a path.
- The order of items and `use` lines does not matter.
- Name resolution: a local binding, then the module's own items, then
  its imports, then the prelude. A program's own `Vec` (or `trim`) hides
  the prelude's.
- The prelude, std's names used without a `use`: `Option Some None
  Result Ok Err Vec Buf HashMap print println eprint eprintln format
  format_in Gpa Allocator Arena ScopedArena arena_scope read_line
  read_stdin_in Scanner parse_int trim split_in split_whitespace_in sort
  sort_by cmp_of eq_of Fmt Display Debug Clone From Into Iterator Hash
  Eq Ord` and the operator traits, `panic(msg)` (prints `msg`, exits with
  101) and `unreachable()`. The rest of std is `use std::{...}` (or
  `std::name`); a program that names none of it is built without std.
- A C header: `import "stdio.h" as c;` then `c::printf`; in a pattern,
  import a C constant by name: `use c::EOF;`.

## Symbols

An item of module `a::b` has the symbol `a.b.name`; root items keep
their names, as do `extern "C"` items and `#[link_name]`s.

## Tools

- `tachyonc fix --only imports` adds the `use` lines a program is
  missing (its own items', and std's outside the prelude),
  and `--only unused` removes unused ones.
- `tachyonc query items` lists every module; `query items MODULE` its
  items with signatures.
- `tachyonc refactor move a::f --to crate::b` moves items, fixing
  imports and `pub`; `refactor rename`, `refactor new-module`,
  `refactor split` (see `tachyonc guide tools`).
