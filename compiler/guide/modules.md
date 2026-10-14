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
  its imports, then the prelude (`Option Some None Result Ok Err Vec
  print println`, the operator traits). A program's own `Vec` hides the
  prelude's.
- A C header: `import "stdio.h" as c;` then `c::printf`; in a pattern,
  import a C constant by name: `use c::EOF;`.

## Symbols

An item of module `a::b` has the symbol `a.b.name`; root items keep
their names, as do `extern "C"` items and `#[link_name]`s.

## Tools

- `tachyonc fix --only imports` adds the `use` lines a program is
  missing for its own items (std's are imported by hand: `use std::Buf;`),
  and `--only unused` removes unused ones.
- `tachyonc query items` lists every module; `query items MODULE` its
  items with signatures.
- `tachyonc refactor move a::f --to crate::b` moves items, fixing
  imports and `pub`; `refactor rename`, `refactor new-module`,
  `refactor split` (see `tachyonc guide tools`).
