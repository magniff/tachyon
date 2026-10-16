# traits-generics

A small geometry and units library and a program that uses it: traits
with default methods, generic functions with bounds, a trait with an
associated type, an iterator of the library's own, `#[derive]`d and
hand-written impls, operator overloading (`+ - * ==` and `<`), and
`From`/`Into` between units of length. The library is two modules,
`geometry.tach` and `units.tach`, loaded by `mod` lines in `main.tach`.

## Build and run

From this folder (with `tachyonc` on your `PATH`, or `../../target/tachyonc`):

```sh
tachyonc main.tach -o traits-generics && ./traits-generics
```

Only `main.tach` is named: `mod geometry;` and `mod units;` load
`geometry.tach` and `units.tach` next to it.

## Expected output

```text
== vectors (operators, derive)
a + b = (2, 6), a - b = (4, 2), -a = (-3, -4)
a.dot(b) = 5, |a| = 5, a == b: false, a > b: true
debug: Vec2 { x: 3, y: 4 }
rotate a by 90: (-4, 3), by 180: (-3, -4)
rotating twice is a half turn: true, Mat2 { a: -1, b: 0, c: 0, d: -1 }
== sorting and hashing (derive(Ord, Hash))
sorted: (-3, 3) (0, 5) (0, 5) (2, 0) (2, 1)
distinct: 4, (0, 5) seen 2 times
largest point: Some(Vec2 { x: 2, y: 1 }), of nothing: None
== shapes (a trait, defaults, generics)
circle   area   12.57  perimeter  12.57
rect     area   12.00  perimeter  14.00
shape    area    6.00  perimeter  12.00
total area of the rects: 14.00
total area of everything: 30.57
stretched clone: area 12.0, the original: 6.0
Polygon { points: [Vec2 { x: 0, y: 0 }, Vec2 { x: 8, y: 0 }, Vec2 { x: 0, y: 3 }] }
== units (From, Into, an associated type)
5000.00 m is 16404.20 ft; 1063.00 ft is 324.00 m
taller than 300.00 m? true
difference: 4676.00 m, negated: -4676.00 m
two laps: 600.00 m, in metres already: 5324.00 m
diagonal   5.00 m
rect       12.00 m2
```

## How it works

**derive writes the routine impls.** One line gives `Vec2` structural
`==` (`Eq`), an order field by field (`Ord`: by `x`, then `y`, which is
what `sort` and `<` use), a hash (so it can be a `HashMap` key), Rust's
Debug text, and `.clone()`:

```tach
#[derive(Eq, Ord, Hash, Debug, Clone)]
pub struct Vec2 { pub x: i64, pub y: i64 }
```

**Operators are traits.** `a + b` calls `Add::add`, `-a` calls
`Neg::neg`, `<` calls `Ord::cmp`. `Mat2` implements `Mul` as the
composition of two linear maps, so `ROTATE_90 * ROTATE_90` is a half
turn:

```tach
impl Add for Vec2 {
    fn add(self: Vec2, o: Vec2) -> Vec2 { Vec2 { x: self.x + o.x, y: self.y + o.y } }
}

impl Mul for Mat2 {
    fn mul(self: Mat2, o: Mat2) -> Mat2 { ... }
}
```

`Meters` has floating-point contents, so its `Ord` is written by hand:
`cmp` returns negative, zero or positive, and `<`, `<=`, `>`, `>=`
follow from it.

**A trait with default methods.** `Shape` requires `area` and
`perimeter`; `name` and `describe` have bodies that an impl may keep or
replace. `Circle` and `Rect` write their own `name`; `Polygon` keeps the
default, which is why the triangle prints as `shape`:

```tach
pub trait Shape {
    fn area(self: *Self) -> f64;
    fn perimeter(self: *Self) -> f64;
    fn name(self: *Self) -> [u8] { "shape" }
    fn describe(self: *Self) {
        println(f"{self.name():<8} area {self.area():>7.2}  perimeter {self.perimeter():>6.2}");
    }
}
```

**Generic functions with bounds.** A bound says what the body may call;
each use with a new type compiles a copy for that type
(monomorphization), so there is no dynamic dispatch:

```tach
fn total_area<T: Shape>(shapes: [T]) -> f64 {
    let mut total = 0.0;
    for s in shapes { total += s.area(); } // s: each element in place
    total
}

fn largest<T: Ord>(xs: [T]) -> Option<T> { ... }
```

**No trait objects: an enum of the cases.** Tachyon has no `dyn Shape`.
A list of different shapes is an enum, and the enum implements the
trait by dispatching with `match`; `total_area(shapes[..])` then works
on the mixed list as on the list of rectangles:

```tach
pub enum AnyShape { C(Circle), R(Rect), P(Polygon) }

impl Shape for AnyShape {
    fn area(self: *AnyShape) -> f64 {
        match *self {
            AnyShape::C(c) => c.area(),
            AnyShape::R(r) => r.area(),
            AnyShape::P(p) => p.area(),
        }
    }
    ...
}
```

**An iterator in the library.** `Polygon::edges` returns an `Edges`,
whose `Item` is a pair of points; the area (the shoelace formula) and
the perimeter are then one chain each:

```tach
impl Iterator for Edges {
    type Item = (Vec2, Vec2);
    fn next(self: *Edges) -> Option<(Vec2, Vec2)> { ... }
}

fn perimeter(self: *Polygon) -> f64 {
    self.edges().fold(0.0, |acc, (a, b)| acc + (b - a).length())
}
```

**A trait with an associated type.** What `measure` returns depends on
the type: a `Segment` measures to `Meters`, a `Rect` to `SquareMeters`.
A generic function names the result `T::Output`. Its body is checked
per instance, so `{m}` needs `Display` only for the outputs actually
used:

```tach
pub trait Measured {
    type Output;
    fn measure(self: *Self) -> Self::Output;
}

impl Measured for Segment {
    type Output = Meters;
    fn measure(self: *Segment) -> Meters { Meters { m: (self.b - self.a).length() } }
}

fn show<T: Measured>(label: [u8], x: *T) {
    let m: T::Output = x.measure();
    println(f"{label:<10} {m}");
}
```

**Units with From and Into.** `Meters` and `Feet` are different types,
so they cannot be mixed by mistake; `From` converts between them, and
`Into` comes for free (`x.into()` is `Meters::from(x)` when a `Meters`
is expected). A bound `T: Into<Meters>` accepts any unit that converts,
`Meters` itself included:

```tach
impl From<Feet> for Meters {
    fn from(f: Feet) -> Meters { Meters { m: f.ft / FEET_PER_METER } }
}

pub fn total<T: Into<Meters>>(lengths: [T]) -> Meters {
    let mut sum = Meters { m: 0.0 };
    for x in lengths {
        let m: Meters = x.into(); // Into needs the target type: here, the let's
        sum = sum + m;
    }
    sum
}
```

**Clone copies deeply.** `Polygon` holds a `Vec`, which owns its points:
assigning or passing the struct moves it (the old name cannot be used
again). The derived `clone` copies the vector's contents, so changing
the clone leaves the original as it was; each is freed when it goes out
of scope. `main` puts a clone of the triangle into the `shapes` array,
because it uses the triangle afterwards.

**Modules.** `main.tach` loads the library with `mod geometry;` and
`mod units;` and imports by name (`use geometry::{Shape, Vec2, ...}`);
items are private unless `pub` (a struct's fields are as visible as the
struct; the `pub` on them is documentation). `geometry.tach` reaches its
sibling with `use crate::units::{Meters, SquareMeters};`.

**A little C.** The square root comes from C's `sqrt`, declared in an
`extern "C"` block. Calling C is `unsafe`, so the library wraps it in a
safe function once: `pub fn square_root(x: f64) -> f64 { unsafe { sqrt(x) } }`.

## Language features

- traits, default methods, operator traits, `impl Ord` by hand: `tachyonc guide traits`
- generic functions and bounds, monomorphization: `tachyonc guide generics`
- associated types (`type Output;`, `T::Output`), `impl Iterator`: `tachyonc guide traits`, `tachyonc guide iterators`
- `#[derive(Eq, Ord, Hash, Debug, Clone)]`, `impl Display`: `tachyonc guide formatting`
- `From`/`Into` and `T: Into<U>` bounds: `tachyonc guide conversions`
- modules, `mod`, `pub`, `use crate::...`: `tachyonc guide modules`
- `static` values of struct type, `extern "C"`: `tachyonc guide syntax`, `tachyonc guide c-interop`

## Going further

- No `dyn Trait`: use generics, or an enum of the cases as `AnyShape`.
- No supertraits (`trait Shape: Display`), associated constants or
  `where` clauses: put each bound on the type parameter.
- A `const` holds numbers, bools and strings; a struct value such as
  `ROTATE_90` is a `static`.
- `Mul<f64> for Vec2` (an operator with another right-hand type) is not
  there: the operator traits take `Self` on both sides; write a method
  (`scale(k)`).
