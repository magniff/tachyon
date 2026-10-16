# Traits

A trait declares functions; `Self` stands for the implementing type; a
function may have a default body. `impl Trait for Type` defines them for
any type (`i64`, `[u8]`, `Vec<T>`, a struct). Its functions become the
type's methods. Dispatch is static: a trait is not a type.

```tach
use std::hash_u64;

trait Shape {
    fn area(self: &Self) -> i64;
    fn name(self: &Self) -> [u8] { "shape" }   // a default
}

struct Square { side: i64 }
struct Rect { w: i64, h: i64 }

impl Shape for Square {
    fn area(self: &Square) -> i64 { self.side * self.side }
    fn name(self: &Square) -> [u8] { "square" }
}

impl Shape for Rect {
    fn area(self: &Rect) -> i64 { self.w * self.h }
}

fn report<T: Shape>(s: &T) {
    print(s.name());
    print(" ");
    std::print_int(s.area());
    println("");
}

// Operators: + - * / and unary - through Add Sub Mul Div Neg,
// == through Eq, < <= > >= through Ord's cmp. std's traits take
// `self: *Self` (a reference, as a `*T` parameter is), so their impls do.
struct V2 { x: i64, y: i64 }

impl Add for V2 {
    fn add(self: V2, o: V2) -> V2 { V2 { x: self.x + o.x, y: self.y + o.y } }
}

impl Ord for V2 {
    fn cmp(self: &V2, o: &V2) -> i64 { (self.x + self.y) - (o.x + o.y) }
}

impl Hash for V2 {
    fn hash(self: &V2) -> u64 { hash_u64((self.x * 31 + self.y) as u64) }
}

trait Double { fn double(self: Self) -> Self; }
impl Double for i64 { fn double(self: i64) -> i64 { self * 2 } }

fn main(gpa: Gpa) -> i32 {
    let sq = Square { side: 3 };
    let r = Rect { w: 2, h: 5 };
    report(&sq);                          // &place: a temporary has no address
    report(&r);
    let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
    if v > (V2 { x: 0, y: 0 }) { std::print_int(v.x * 10 + v.y); }
    let mut seen: HashMap<V2, bool> = HashMap::new_in(gpa);   // a struct key: Hash + Eq
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
  arrays, slices whose parts have `==`; a `[u8]` by bytes); an
  `impl Eq` replaces structural `==`, also for a part.
  `Ord`: numbers, pointers, fieldless enums have it.
- Methods are called `x.m()` or `Type::m(&x)`; a trait's function
  without `self` is called `Type::f()`.
- A default function is checked, and compiled, only for the impls
  that use it (in a non-generic impl).
- Not there: `dyn Trait` (use generics, or an enum of the cases),
  supertraits, associated constants, `impl Trait` in argument or return
  position, blanket impls over all `T`.
- (0.15) Traits may take type parameters, `trait From<T>`; bounds take
  arguments, `T: From<i64>` (`tachyonc guide conversions`).
  `#[derive(Eq, Ord, Hash, Debug, Clone)]` writes impls (`tachyonc
  guide formatting`).

## Associated types (0.14)

A trait declares `type Name;`, each impl defines it, and `T::Name` (or
`Self::Name`) is that type. A bound can fix it: `I: Iterator<Item =
i64>`. Slices get impls too: `impl<T> [T] { ... }`, `impl<T> Tr for [T]`.

```tach
use std::print_int;

struct Countdown { n: i64 }

impl Iterator for Countdown {           // std's trait, in the prelude
    type Item = i64;
    fn next(self: *Countdown) -> Option<i64> {
        if self.n == 0 { return None; }
        self.n -= 1;
        Some(self.n + 1)
    }
}

fn first<I: Iterator>(it: I) -> Option<I::Item> {
    let mut it = it;
    it.next()
}

fn total<I: Iterator<Item = i64>>(it: I) -> i64 {
    it.sum()                            // a default of Iterator
}

impl<T> [T] {
    fn second(self: [T]) -> T { self[1] }
}

fn main() -> i32 {
    print_int(first(Countdown { n: 3 }).unwrap());
    print(" ");
    print_int(total(Countdown { n: 4 }));
    print(" ");
    print_int(Countdown { n: 5 }.count());
    print(" ");
    let c: [u8; 1] = ["xyz".second()];
    print(c[0..1]);
    println("");
    0
}
```
```out
3 10 5 y
```

- Every declared name must be defined: "the impl of trait 'Iterator' is
  missing 'type Item'".
- `X::Name` needs `X` to be a type parameter or `Self`; two traits
  defining the name for one type is an ambiguity error. No defaults or
  bounds on associated types, no `<T as Tr>::Name`.
- A constraint that does not hold: "'Small::Item' is 'u8', but the bound
  'I: Iterator<Item = i64>' of 'total' requires 'i64'".
- `F::Output` is the result type of a fn type (or a closure).
