# Generics

Functions, structs, enums, impl blocks and type aliases take type
parameters. A generic item is a template: each use with new type
arguments makes a separate copy (monomorphization), checked and
optimized as if written by hand. No boxing, no dynamic dispatch.

```tach
struct Stack<T> { items: Vec<T> }

impl<T> Stack<T> {
    fn new() -> Stack<T> { Stack { items: Vec::new() } }
    fn push(self: *Stack<T>, x: T) { self.items.push(x); }
    fn pop(self: *Stack<T>) -> Option<T> { self.items.pop() }
    fn free(self: *Stack<T>) { self.items.free(); }
}

impl Stack<i64> {                          // methods of one instance only
    fn sum(self: *Stack<i64>) -> i64 {
        let mut t = 0;
        for x in self.items.as_slice() { t += x; }
        t
    }
}

fn largest<T: Ord>(s: [T]) -> T {          // a bound: T must implement Ord
    let mut best = s[0];
    for x in s { if x > best { best = x; } }
    best
}

fn swap<T, U>(p: (T, U)) -> (U, T) { (p.1, p.0) }

type Pair<T> = (T, T);

fn sum_pair(p: Pair<i64>) -> i64 { p.0 + p.1 }

fn main() -> i32 {
    let mut s: Stack<i64> = Stack::new();
    defer s.free();
    s.push(4);
    s.push(9);
    std::print_int(s.sum());
    print(" ");
    let a = [3, 8, 1];
    std::print_int(largest(a[..]));
    print(" ");
    std::print_int(largest::<u8>("tachyon") as i64);   // the turbofish
    print(" ");
    let t = swap((1, "one"));
    print(t.0);
    print(" ");
    std::print_int(sum_pair((2, 3)) + s.pop().unwrap());
    println("");
    0
}
```
```out
13 8 121 one 14
```

- Type arguments: after a type's name (`Vec<i64>`, `Option<*u8>`), and in
  expressions after `::` (`Vec::<u8>::new()`, `max::<i64>(a, b)`,
  `Pair::<i64> { a: 1, b: 2 }`, a method's own: `x.m::<u8>()`). They are inferred
  from arguments and from the expected type (`let v: Vec<i64> =
  Vec::new();`); unsuffixed literals are looked at last.
- A generic function used as a value needs its arguments:
  `let f = largest::<i64>;`.
- Without bounds, a body is checked per instance: `a > b` works for
  every `T` that has `>`. An error inside an instance is reported with
  `note: in instantiation of 'f<P>' at ...`. With a bound, only the
  bound's functions may be called on `T`'s values.
- `size_of(T)` and `align_of(T)` work on type parameters.
- Not there: const generics (`[T; N]` with `N` a parameter), generic
  traits (`trait Conv<T>`), associated types, `where` clauses,
  variadic generics.
