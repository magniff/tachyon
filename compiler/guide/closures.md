# Closures

A closure is a function written as an expression, that uses the locals
around it: `|x| x + k`. Each closure has its own type, which has no
name: give a closure to a generic parameter bounded by `Fn` or `FnMut`,
or keep it in a `let`. Calls are direct (no allocation, no pointer to a
function), and a closure passed to a generic function is usually
inlined.

```tach
fn apply<F: Fn(i64) -> i64>(f: F, x: i64) -> i64 {
    f(x)
}

fn repeat<F: FnMut(i64)>(n: i64, mut f: F) {
    for i in 0..n { f(i); }
}

fn main() -> i32 {
    let k = 10;
    let add_k = |x: i64| x + k;              // a `let` needs the parameter's type
    std::print_int(apply(add_k, 1));
    print(" ");
    std::print_int(apply(|x| x * 2, 21));    // here F's bound gives x: i64
    print(" ");
    let mut total = 0;
    repeat(4, |i| { total += i; });          // changes `total` (a `let mut`)
    std::print_int(total);
    println("");
    0
}
```
```out
11 42 6
```

## Syntax

- `|a, b| a + b`; `|| 42` takes nothing; `|x: i64| -> i64 { x + 1 }`:
  with a result type, the body is a block. The body takes everything
  after the bars, as `return`'s value does: `|x| x + 1` is
  `|x| (x + 1)`.
- Parameters are patterns: `|(a, b): (i64, i64)| a * b`, `|mut x|`,
  `|_|`; not `|a | b|` (no or-pattern at the top).
- A parameter's type is the annotation, else the one the context
  expects (an `F: Fn(i64) -> bool` bound, an `fn(i64) -> bool`
  parameter). Without either it is an error: `cannot infer the type of
  closure parameter 'x'`, fixed by writing `|x: i64|`.
- `return` in the body returns from the closure; `break` and `continue`
  cannot leave it. An `unsafe { }` around a closure covers its body.
- Messages and `tachyonc query type FILE:LINE:COL` show a closure's type
  as `closure(i64) -> i64 at main.tach:4:15`.

## What a closure captures

Decided per variable, so the meaning never depends on an analysis:

| the variable | captured | the closure sees |
|---|---|---|
| `let x`, a parameter, a `for` variable | by value (a copy) | the value it had; nothing can change it |
| `let mut x` | by reference | `x` itself: its assignments change `x` |
| anything, with `move \|..\|` | by value | a snapshot; assignments change the closure's copy |

A closure capturing `x` by reference is a view of `x` (0.17): while the
closure is still to be called, `x` is not changed another way
(`own.conflict`, as in Rust). Change it after the closure's last call,
or capture a snapshot with `move`.

```tach
fn call<F: FnMut() -> i64>(mut f: F) -> i64 {
    f()
}

fn main() -> i32 {
    let mut n = 1;
    let snap = move || n;              // a copy of n, now
    let bump = || { n += 10; n };      // by reference: changes n
    let b = call(bump);                // 11
    n += 100;                          // bump is done with n
    println(f"{b} {call(snap)} {n}");
    0
}
```
```out
11 1 111
```

A closure that borrows a variable cannot leave that variable's block: a
block's value, a `break` value, a `match` or `if let` arm's value. The
error says to write `move`, or to declare the variable outside the
block. There is nothing else a closure can escape through: closure
types cannot be named, so no struct field, static or return type can
hold one (outside generic parameters).

## Fn, FnMut, fn

- `F: Fn(A, B) -> R` takes a closure with that signature that assigns
  no captured variable, or a plain function `fn(A, B) -> R`.
- `F: FnMut(A, B) -> R` takes any closure with that signature, or a
  plain function. Call `f` from a `mut f: F` parameter or a `let mut`.
- `-> R` may be left out: `FnMut(i64)` returns `()`. There is no
  `FnOnce`.
- A closure that captures nothing is a plain function: it converts to
  `fn(i64) -> i64` where one is expected. A capturing one is an error
  there; make the parameter generic: `fn run<F: Fn(i64) -> i64>(f: F)`.
- In a struct, a closure is a generic field: `struct Button<F> { on: F }`,
  called as `(b.on)(3)`.

```tach
struct Counter<F> { step: F, n: i64 }

fn run(f: fn(i64) -> i64) -> i64 {
    f(4)
}

fn main() -> i32 {
    std::print_int(run(|x| x * x));       // captures nothing: a plain fn
    print(" ");
    let k = 3;
    let mut c = Counter { step: |x: i64| x + k, n: 0 };
    c.n = (c.step)(c.n);
    c.n = (c.step)(c.n);
    std::print_int(c.n);
    println("");
    0
}
```
```out
16 6
```

Not there: `FnOnce`, `Box<dyn Fn>` and `dyn` (use generics), `impl Fn`
in a result (0.15), closures in statics, a closure calling itself.
`tachyonc guide iterators`: closures with `map`, `filter`, `fold`.
