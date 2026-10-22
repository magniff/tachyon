# 9. Traits and generics

You've already used code that works for many types: `Vec<i64>` and
`Vec<str>` are one `Vec`, and `sort` sorts numbers and words alike. In
this chapter you'll write code like that yourself.

By the end you'll be able to write *generic* functions and types, which
take types as parameters; define *traits*, which say what a type can
do, and implement them for your types and for std's; make `+`, `<` and
`{x}` work on your own types; and handle a list of mixed kinds of things
with an enum, since vole has no trait objects. The running example is a
small geometry library: points, circles and rectangles.

## Generic functions

Here is a function that finds the largest element of a slice. Save it as
`largest.vl`:

```vole largest.vl
fn largest<T: Ord>(items: [T]) -> T {
    var best = items[0];
    for x in items {
        if x > best {
            best = x;
        }
    }
    best
}

fn main() {
    let scores = [3, 9, 4];
    let words: [str; 3] = ["pear", "fig", "plum"];
    println(largest(scores));
    println(largest(words));
    println(largest::<f64>([1.5, 0.5]));
}
```

```out
9
plum
1.5
```

`<T: Ord>` after the name makes `T` a *type parameter*: a stand-in for
a type, chosen at each call. `items: [T]` is a slice of `T`s, and the
result is a `T`. The `: Ord` part is a *bound*: it says `T` must be a
type whose values can be ordered, which is what `x > best` needs.
Numbers and `str` are; you'll see how to make your own types ordered
later in the chapter.

At each call, the compiler works out `T` from the arguments: `i64` for
the scores, `str` for the words. When you want to say it yourself, write
it after `::`, as in `largest::<f64>(...)`. You met this *turbofish* in
chapter 2, with `parse::<i64>()`. As in chapter 7, an array or a `Vec`
goes where a slice is wanted as it is: `largest(scores)` reads the
array's elements in place, and works out `T` from them.

A generic function is a template. For each type it's used with, the
compiler makes a separate copy, with `T` replaced by that type, and
compiles it as if you had written it by hand. So `largest::<i64>` is as
fast as a `largest` written only for `i64`s, and there's nothing to look
up while the program runs.

## Generic types

Structs and enums can take type parameters too. `Option<T>` and
`Vec<T>` are written this way in std. Here is a stack of anything:

```vole
struct Stack<T> {
    items: Vec<T>,
}

impl<T> Stack<T> {
    fn new(gpa: Gpa) -> Stack<T> {
        Stack { items: Vec::new_in(gpa) }
    }

    fn push(inout self, x: sink T) {
        self.items.push(x);
    }

    fn pop(inout self) -> Option<T> {
        self.items.pop()
    }

    fn len(self) -> i64 {
        self.items.len()
    }
}

impl Stack<i64> {
    fn sum(self) -> i64 {
        var t = 0;
        for x in self.items {
            t += x;
        }
        t
    }
}

fn main(gpa: Gpa) {
    var numbers: Stack<i64> = Stack::new(gpa);
    numbers.push(4);
    numbers.push(9);
    println(f"{numbers.len()} {numbers.sum()} {numbers.pop():?}");

    var names: Stack<str> = Stack::new(gpa);
    names.push("ada");
    println(f"{names.len()} {names.pop():?}");
}
```

```out
2 13 Some(9)
1 Some("ada")
```

`impl<T> Stack<T>` gives methods to every `Stack`, whatever `T` is.
`push` takes its value `sink`, because the stack keeps it (chapter 4).
`impl Stack<i64>` gives a method only to stacks of `i64`s: `sum` adds
numbers, so it wouldn't make sense for a `Stack<str>`, and calling
`names.sum()` is an error.

A *type alias* gives a type a shorter name: `type Pair<T> = (T, T);`
makes `Pair<i64>` mean `(i64, i64)`. It's the same type, under another
name.

## Traits

`largest` needed its `T` to be ordered, and `Ord` is how it said so.
`Ord` is a *trait*: a named set of functions that a type can provide.
Let's write a trait of our own. Start `shapes.vl`:

```vole shapes.vl
trait Shape {
    fn area(self) -> f64;

    fn name(self) -> str {
        "shape"
    }
}

struct Circle {
    radius: f64,
}

struct Rect {
    width: f64,
    height: f64,
}

impl Shape for Circle {
    fn area(self) -> f64 {
        3.14159 * self.radius * self.radius
    }

    fn name(self) -> str {
        "circle"
    }
}

impl Shape for Rect {
    fn area(self) -> f64 {
        self.width * self.height
    }
}

fn main() {
    let c = Circle { radius: 2.0 };
    let r = Rect { width: 3.0, height: 4.0 };
    println(f"{c.name()} {c.area():.2}");
    println(f"{r.name()} {r.area():.2} {Rect::area(r)}");
}
```

```out
circle 12.57
shape 12.00 12
```

The trait declares two functions. `area` has no body, so every type
that implements `Shape` must write one. `name` has a body, a *default*,
used by any type that doesn't write its own: `Circle` does, `Rect`
doesn't, so a `Rect`'s name is `"shape"`.

`impl Shape for Circle` is where `Circle` provides the functions. Once
it has, they are `Circle`'s methods: `c.area()`. You can also call them
by the type's name, `Rect::area(r)`.

Leave out a function that has no default, and the compiler says which
one:

```vole
trait Shape {
    fn area(self) -> f64;

    fn name(self) -> str {
        "shape"
    }
}

struct Square {
    side: f64,
}

impl Shape for Square {
    fn name(self) -> str {
        "square"
    }
}

fn main() {
    let s = Square { side: 2.0 };
    println(s.name());
}
```

```err
error[type error]: the impl of trait 'Shape' is missing 'area'
 --> main.vl: line 13, column 1
  = help: it has no default: write it in the impl
```

A type implements a trait at most once, so there's never a question of
which `area` a call means. A second `impl Shape for Square` is an
error, `conflicting impls of trait 'Shape' for 'Square'`.

You can implement your own traits for std's types too, such as `i64` or
`str`:

```vole
trait Describe {
    fn describe(self) -> str;
}

impl Describe for i64 {
    fn describe(self) -> str {
        if self < 0 {
            "negative"
        } else {
            "not negative"
        }
    }
}

fn main() {
    println(f"{(-5).describe()} {7.describe()}");
}
```

```out
negative not negative
```

> **If you know Go:** traits are like interfaces, but a type has a
> trait only when there's an `impl` that says so, and every call is
> resolved when the program is compiled.

## Bounds

With a trait, we can write a function that works on any shape:

```vole skip
fn total_area<T: Shape>(items: [T]) -> f64 {
    var t = 0.0;
    for s in items {
        t += s.area();
    }
    t
}
```

`T: Shape` is a bound, like `T: Ord` was. Inside the function, all the
compiler knows about `T` is that it's a `Shape`, so you may call
`area` and `name` on it, and nothing else. A type parameter can have
several bounds, joined with `+`: `T: Shape + Display` is a shape that
can also be printed.

Calling a bounded function with a type that doesn't have the trait is
an error that names the bound:

```vole
fn largest<T: Ord>(items: [T]) -> T {
    var best = items[0];
    for x in items {
        if x > best {
            best = x;
        }
    }
    best
}

struct Point {
    x: i64,
    y: i64,
}

fn main() {
    let points = [Point { x: 1, y: 2 }, Point { x: 3, y: 0 }];
    println(largest(points).x);
}
```

```err
error[type error]: the trait 'Ord' is not implemented for 'Point'
 --> main.vl: line 18, column 13
  = help: required by the bound 'T: Ord' of 'largest'
```

Which point is larger? Vole doesn't guess. You'll see two ways to tell
it in the next section: write `impl Ord for Point`, or derive one.

### Generics without bounds

A type parameter doesn't have to have a bound. Then the body is checked
again for each type it's used with, and an error in one of those copies
says which copy it was:

```vole
fn bigger<T>(a: T, b: T) -> T {
    if a > b {
        a
    } else {
        b
    }
}

struct Point {
    x: i64,
    y: i64,
}

fn main() {
    println(bigger(3, 7));
    let p = bigger(Point { x: 1, y: 2 }, Point { x: 3, y: 4 });
    println(p.x);
}
```

```err
error[type error]: comparison requires numeric type, got 'Point'
 --> main.vl: line 2, column 8
  = note: in instantiation of 'bigger<Point>' at main.vl: line 16, column 13
```

`bigger(3, 7)` is fine; `bigger::<Point>` isn't, and the `note:` line
points at the call that made it. A bound moves that error to the call
and says what's missing, which is usually clearer. Use bounds for
functions other people will call.

> **If you know Java or C#:** generics here are templates, as in C++:
> each type gets its own compiled copy, and nothing is erased.

## std's traits

Much of what feels built in is a trait in std, and your types can join
in. Let's give our geometry a point type, `Vec2`, that can be added,
printed and made from a pair of numbers:

```vole
struct Vec2 {
    x: f64,
    y: f64,
}

impl Add for Vec2 {
    fn add(self, o: Vec2) -> Vec2 {
        Vec2 { x: self.x + o.x, y: self.y + o.y }
    }
}

impl Display for Vec2 {
    fn fmt(self, f: inout Fmt) {
        f.write(f"({self.x}, {self.y})");
    }
}

impl From<(f64, f64)> for Vec2 {
    fn from(p: (f64, f64)) -> Vec2 {
        Vec2 { x: p.0, y: p.1 }
    }
}

fn main() {
    let a = Vec2 { x: 1.0, y: 2.0 };
    let b = Vec2::from((0.5, 0.5));
    let c: Vec2 = (10.0, 0.0).into();
    println(f"{a + b} {a + b + c}");
}
```

```out
(1.5, 2.5) (11.5, 2.5)
```

- **Operators.** `a + b` calls `Add`'s `add`. The other arithmetic
  operators work the same way: `Sub` for `-`, `Mul` for `*`, `Div` for
  `/`, and `Neg` for a minus in front, `-a`.
- **Display** is the plain `{x}` in an f-string. Its `fmt` gets the
  value and an `f: inout Fmt` to write the text to, with `f.write(...)`.
  There is nothing to return.
- **From and Into** convert between types. `impl From<(f64, f64)> for
  Vec2` makes `Vec2::from((0.5, 0.5))` work, and gives you `into()`
  for free, going the other way: `(10.0, 0.0).into()`, where the
  type it's converted into comes from `let c: Vec2`. Chapter 6 used the
  same trait to convert errors for `?`.

### Comparing: Eq and Ord

`==` works on structs out of the box, field by field. `<` and the other
comparisons come from `Ord`, which has one function, `cmp`:

```vole
struct Version {
    major: i64,
    minor: i64,
}

impl Ord for Version {
    fn cmp(self, o: Version) -> i64 {
        if self.major != o.major {
            self.major - o.major
        } else {
            self.minor - o.minor
        }
    }
}

fn main() {
    let old = Version { major: 1, minor: 9 };
    let new = Version { major: 1, minor: 10 };
    println(f"{old < new} {old == new} {old.cmp(new)}");
}
```

```out
true false -1
```

`cmp` returns an `i64`: negative if `self` comes first, zero if they're
equal, positive if `o` comes first. Subtracting the fields is a short
way to write it, fine for numbers like these; for numbers near the ends
of the `i64` range the subtraction would wrap (chapter 3), and
`self.major.cmp(o.major)` is the safe way. With `Ord`, `Version`s can be compared with `<`, sorted
with `sort()`, and given to `largest`.

### Deriving

Writing `Ord`, `Hash` or `Debug` by hand gets old for a struct with
many fields, and the compiler can write them for you:

```vole
#[derive(Eq, Ord, Hash, Debug, Clone)]
struct Version {
    major: i64,
    minor: i64,
}

fn main(gpa: Gpa) {
    var versions: Vec<Version> = Vec::new_in(gpa);
    versions.push(Version { major: 1, minor: 10 });
    versions.push(Version { major: 0, minor: 9 });
    versions.push(Version { major: 1, minor: 2 });
    versions.sort();
    println(f"{versions:?}");

    var notes: HashMap<Version, str> = HashMap::new_in(gpa);
    let current = Version { major: 1, minor: 10 };
    notes.insert(current, "current");
    println(f"{notes.get(current):?}");
}
```

```out
[Version { major: 0, minor: 9 }, Version { major: 1, minor: 2 }, Version { major: 1, minor: 10 }]
Some("current")
```

`#[derive(...)]` before a struct or an enum writes the impls:

- `Eq`: `==`, field by field.
- `Ord`: compares the first field, then the next one if those are
  equal, and so on, in the order the fields are declared. For an enum,
  the earlier variant comes first.
- `Hash`: a hash of all the fields, so the type can be a `HashMap` key
  (with `Eq`).
- `Debug`: the `{x:?}` form, as in `Version { major: 0, minor: 9 }`.
- `Clone`: `x.clone()`, a copy of every field (a `Vec` field is copied
  too, with all its elements). A plain struct like `Version` is copied
  by `=` anyway, which is why `notes.insert(current, ...)` above needs
  no `clone()`; `Clone` matters for owned types (chapter 4).

`Display` can't be derived: how your type looks to a user is for you to
decide.

A misspelled derive gets a suggestion:

```vole
#[derive(Debg)]
struct Point {
    x: i64,
    y: i64,
}

fn main() {
    let p = Point { x: 1, y: 2 };
    println(f"{p:?}");
}
```

```err
error[type error]: cannot derive 'Debg' (derivable: Eq, Ord, Hash, Debug, Clone)
 --> main.vl: line 1, column 10
  = help: did you mean 'Debug'?
error[type error]: 'Point' does not implement Debug, which '{x:?}' needs
 --> main.vl: line 9, column 16
  = help: derive it: '#[derive(Debug)]' before the type, or write 'impl Debug for Point { fn fmt_debug(self, f: inout std::Fmt) { f.write(f"..."); } }'
```

The second error follows from the first: fix the spelling and both go
away. This is a case for fixing errors from the top, as chapter 1
advised.

std has a few more traits you'll meet: `Default`, for types with an
obvious starting value (`T::default()`, imported with `use
std::Default;`), and `Clone`, which `#[derive(Clone)]` writes and which
`Vec`, `String` and `HashMap` already have.

> **If you know Rust:** `cmp` returns an `i64`, not an `Ordering`. The
> derivable traits are `Eq`, `Ord`, `Hash`, `Debug` and `Clone`. There
> are no supertraits, no `where` clauses and no blanket impls (`impl<T>
> Tr for T`).

## No trait objects: enums instead

Now for a list of mixed shapes: some circles, some rectangles. In many
languages you'd make a list of "anything that is a Shape". Try that in
vole:

```vole
trait Shape {
    fn area(self) -> f64;
}

fn total(shapes: [Shape]) -> f64 {
    var t = 0.0;
    for s in shapes {
        t += s.area();
    }
    t
}

fn main() {}
```

```err
error[type error]: 'Shape' is a trait, not a type (no trait objects: use a type parameter bounded by it, 'T: Trait')
 --> main.vl: line 5, column 19
```

A trait is not a type in vole. Every call to a trait's function is
decided when the program is compiled, never while it runs. A `[T]` with
`T: Shape` is a slice of one kind of shape: all circles, or all
rectangles.

For a list of mixed kinds, use an enum with a variant for each kind,
and implement the trait for the enum by matching. Here is the finished
`shapes.vl`, with everything from this chapter in it:

```vole shapes.vl
struct Vec2 {
    x: f64,
    y: f64,
}

impl Add for Vec2 {
    fn add(self, o: Vec2) -> Vec2 {
        Vec2 { x: self.x + o.x, y: self.y + o.y }
    }
}

impl Display for Vec2 {
    fn fmt(self, f: inout Fmt) {
        f.write(f"({self.x}, {self.y})");
    }
}

trait Shape {
    fn area(self) -> f64;

    fn name(self) -> str {
        "shape"
    }
}

struct Circle {
    center: Vec2,
    radius: f64,
}

struct Rect {
    corner: Vec2,
    size: Vec2,
}

impl Shape for Circle {
    fn area(self) -> f64 {
        3.14159 * self.radius * self.radius
    }

    fn name(self) -> str {
        "circle"
    }
}

impl Shape for Rect {
    fn area(self) -> f64 {
        self.size.x * self.size.y
    }

    fn name(self) -> str {
        "rectangle"
    }
}

impl Display for Circle {
    fn fmt(self, f: inout Fmt) {
        f.write(f"a circle at {self.center} with radius {self.radius}");
    }
}

enum AnyShape {
    Circle(Circle),
    Rect(Rect),
}

impl Shape for AnyShape {
    fn area(self) -> f64 {
        match self {
            AnyShape::Circle(c) => c.area(),
            AnyShape::Rect(r) => r.area(),
        }
    }

    fn name(self) -> str {
        match self {
            AnyShape::Circle(c) => c.name(),
            AnyShape::Rect(r) => r.name(),
        }
    }
}

fn total_area<T: Shape>(items: [T]) -> f64 {
    var t = 0.0;
    for s in items {
        t += s.area();
    }
    t
}

fn describe<T: Shape + Display>(s: T) {
    println(f"{s}: area {s.area():.2}");
}

fn main(gpa: Gpa) {
    let origin = Vec2 { x: 0.0, y: 0.0 };
    let c = Circle { center: origin + Vec2 { x: 1.0, y: 1.0 }, radius: 2.0 };
    describe(c);

    var shapes: Vec<AnyShape> = Vec::new_in(gpa);
    shapes.push(AnyShape::Circle(c));
    shapes.push(AnyShape::Rect(Rect { corner: origin, size: Vec2 { x: 3.0, y: 4.0 } }));
    shapes.push(AnyShape::Circle(Circle { center: origin, radius: 0.5 }));
    for s in shapes {
        println(f"{s.name():<10} {s.area():>6.2}");
    }
    println(f"{"total":<10} {total_area(shapes.as_slice()):>6.2}");
}
```

```out
a circle at (1, 1) with radius 2: area 12.57
circle      12.57
rectangle   12.00
circle       0.79
total       25.35
```

`AnyShape` is a `Shape` too, so `total_area` works on a slice of them
like on a slice of circles. Each call to `area` on an `AnyShape` is a
`match` that picks the right function.

Why does vole work this way? A trait object in other languages is a
pointer to the value plus a hidden table of functions, looked up on
every call, and the value usually has to live on the heap. The enum has
no hidden pointers, needs no allocation, and its `match` is checked:
add a `Triangle` variant, and the compiler lists every `match` that
needs a new arm (chapter 5). The cost is that the list of kinds is
closed: someone using your library can't add a shape of their own
without changing the enum. This is a current design choice of a young
language, and may change.

If you write `dyn Shape`, the way Rust spells a trait object, the
compiler stops at the word: `'dyn' is a reserved keyword (reserved for
future use)`.

## Associated types: a short look

A trait can declare a type that each implementation chooses, an
*associated type*. You'll meet the most important one in the next
chapter: `Iterator` declares `type Item;`, the type of the values it
produces. Here is the idea on a small trait of our own:

```vole
trait Inventory {
    type Item;
    fn first(self) -> Option<Self::Item>;
}

struct Shelf {
    books: [str; 2],
}

impl Inventory for Shelf {
    type Item = str;

    fn first(self) -> Option<str> {
        Some(self.books[0])
    }
}

fn first_of<I: Inventory>(inv: I) -> Option<I::Item> {
    inv.first()
}

fn main() {
    let s = Shelf { books: ["Dune", "Emma"] };
    println(f"{first_of(s):?}");
}
```

```out
Some("Dune")
```

`type Item = str;` in the impl says what `Item` is for a `Shelf`, and
`I::Item` in `first_of` means "whatever `Item` is for this `I`".

## Summary

- A generic function or type takes type parameters, `<T>`; the compiler
  infers them, or you write them with the turbofish, `f::<i64>(...)`.
  Each type used gets its own compiled copy, so generics cost nothing
  at run time.
- A trait names functions a type provides; an `impl Trait for Type`
  provides them, once per type. A trait can have default functions.
- Bounds, `T: Shape + Display`, say what a type parameter must have;
  the compiler checks them at each call.
- Operators, printing and conversions are std's traits: `Add`, `Sub`,
  `Mul`, `Div`, `Neg`, `Eq`, `Ord` (`cmp` returns an `i64`), `Hash`,
  `Display`, `Debug`, `From` and `Into`. `#[derive]` writes `Eq`, `Ord`,
  `Hash`, `Debug` and `Clone`.
- There are no trait objects: for a list of mixed kinds, use an enum
  that implements the trait by matching.
- A trait can have an associated type, `type Item;`.

The next chapter puts traits and generics to work, with closures and
iterators.

## Try it yourself

- Add a `Triangle { base: f64, height: f64 }` to `shapes.vl`, as a
  `Shape` and as a variant of `AnyShape`, and see which `match`es the
  compiler asks you to update.
- Implement `Sub` and `Neg` for `Vec2`, and print `-(a - b)`.
- Derive `Eq` and `Ord` for a `struct Card { rank: i64, suit: i64 }`,
  sort a hand of five cards, and print it with `#[derive(Debug)]`.
