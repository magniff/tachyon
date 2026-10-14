# Traits

A trait declares functions; `Self` stands for the implementing type; a
function may have a default body. `impl Trait for Type` defines them for
any type (`i64`, `[u8]`, `Vec<T>`, a struct). Its functions become the
type's methods. Dispatch is static: a trait is not a type.

```tach
use std::{HashMap, hash_u64};

trait Shape {
    fn area(self: *Self) -> i64;
    fn name(self: *Self) -> [u8] { "shape" }   // a default
}

struct Square { side: i64 }
struct Rect { w: i64, h: i64 }

impl Shape for Square {
    fn area(self: *Square) -> i64 { self.side * self.side }
    fn name(self: *Square) -> [u8] { "square" }
}

impl Shape for Rect {
    fn area(self: *Rect) -> i64 { self.w * self.h }
}

fn report<T: Shape>(s: *T) {
    print(s.name());
    print(" ");
    std::print_int(s.area());
    println("");
}

// Operators: + - * / and unary - through Add Sub Mul Div Neg,
// == through Eq, < <= > >= through Ord's cmp.
struct V2 { x: i64, y: i64 }

impl Add for V2 {
    fn add(self: V2, o: V2) -> V2 { V2 { x: self.x + o.x, y: self.y + o.y } }
}

impl Ord for V2 {
    fn cmp(self: *V2, o: *V2) -> i64 { (self.x + self.y) - (o.x + o.y) }
}

impl Hash for V2 {
    fn hash(self: *V2) -> u64 { hash_u64((self.x * 31 + self.y) as u64) }
}

trait Double { fn double(self: Self) -> Self; }
impl Double for i64 { fn double(self: i64) -> i64 { self * 2 } }

fn main() -> i32 {
    let sq = Square { side: 3 };
    let r = Rect { w: 2, h: 5 };
    report(&sq);                          // &place: a temporary has no address
    report(&r);
    let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
    if v > (V2 { x: 0, y: 0 }) { std::print_int(v.x * 10 + v.y); }
    let mut seen: HashMap<V2, bool> = HashMap::new();   // a struct key: Hash + Eq
    defer seen.free();
    seen.insert(v, true);
    if seen.contains(V2 { x: 4, y: 6 }) { print(" found "); }
    std::print_int(21.double());
    println("");
    0
}
```
```out
square 9
shape 10
46 found 42
```

- Bounds: `fn f<T: A + B>`, `impl<T: Hash> Hash for Pair<T>`, `struct
  Map<K: Hash + Eq, V>`. A call with a type that lacks the trait is an
  error naming the bound.
- At most one impl per trait and type (a generic impl counts for all
  its instances).
- `Eq`: every type with structural `==` has it (structs, enums, tuples,
  arrays whose parts have `==`); an `impl Eq` replaces structural `==`.
  `Ord`: numbers, pointers, fieldless enums have it.
- Methods are called `x.m()` or `Type::m(&x)`; a trait's function
  without `self` is called `Type::f()`.
- Associated types (0.14): `type Item;` in a trait, `type Item = i64;`
  in each impl, named `Self::Item` and `T::Item`; no defaults or bounds
  on them, no `<T as Tr>::Item`.
- Not there: `dyn Trait` (use generics, or an enum of the cases),
  supertraits, associated constants, generic traits, `impl Trait` in
  argument or return position, blanket impls over all `T`,
  `#[derive]`.
