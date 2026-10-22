# 12. Effects: what a function may do

A function's signature tells you a lot: what it takes, what it returns,
which arguments it may change (`inout`) and which it takes for good
(`sink`). It doesn't tell you what else a call might do. Will it
allocate memory? Print something? Read a global variable? Stop the
program? In most languages you find out by reading the function, and
everything it calls, and everything those call.

Vole works it out for you. In this chapter you'll ask the compiler what
a function may do and why, write down promises like "this function
never allocates", and see what happens when a later change breaks one.

## What an effect is

An *effect* is something a call may do beyond computing its result and
changing its `inout` arguments. The compiler knows six of them:

| effect | what it means | where it comes from |
|---|---|---|
| `alloc(Gpa)` | allocates memory, from a `Gpa` | `Vec::push`, `String::from_in`, anything `_in` |
| `io` | reads or writes outside the program | printing, files, stdin |
| `global` | uses a global variable | a `static var`, std's print buffer |
| `panic` | may stop the program | a checked index, `unwrap`, `assert` |
| `diverge` | may never return | `loop`, `while`, recursion |
| `unsafe` | does unsafe operations itself | chapter 15 |

The allocator's type is part of the effect: a function that allocates
from an arena (chapter 8) is `alloc(Arena)`. Threads add three more,
`sync`, `thread` and `tls`, which chapter 14 shows.

The compiler *infers* every function's effects, from its body and
everything the body calls, and you never have to write them. A function
that does none of them, that only computes, has the effects `none`.

## A program to ask about

Here's a small statistics program. Save it as `stats.vl`. It reads
numbers from stdin and prints their mean and a histogram: how many fall
between 0 and 2, between 2 and 4, and so on.

```vole stats.vl
// stats: the mean and a histogram of the numbers on stdin.

fn mean(xs: [f64]) -> f64 {
    var total = 0.0;
    for x in xs {
        total += x;
    }
    total / xs.len() as f64
}

fn bucket(x: f64, lo: f64, hi: f64, n: i64) -> i64 {
    let i = ((x - lo) / (hi - lo) * n as f64) as i64;
    if i < 0 { 0 } else if i >= n { n - 1 } else { i }
}

fn histogram(xs: [f64], lo: f64, hi: f64, buckets: inout [i64]) {
    for x in xs {
        let i = bucket(x, lo, hi, buckets.len());
        buckets[i] += 1;
    }
}

fn main(gpa: Gpa) {
    let input = read_stdin_in(gpa).unwrap();
    let text = String::from_buf(input).unwrap();
    var xs: Vec<f64> = Vec::new_in(gpa);
    for word in text.split_whitespace() {
        xs.push(word.parse::<f64>().unwrap());
    }
    println(f"mean: {mean(xs):.2}");
    var buckets = [0; 5];
    histogram(xs, 0.0, 10.0, &buckets);
    for i in 0..5 {
        println(f"{i * 2:>2} to {i * 2 + 2:>2}: {buckets[i]}");
    }
}
```

```in
1 2 2.5 3 7 9.5 4 4.2 8 0.5
```

```out
mean: 4.17
 0 to  2: 2
 2 to  4: 3
 4 to  6: 2
 6 to  8: 1
 8 to 10: 2
```

The program has the shape most programs have, or should have: a
*core* that computes (`mean`, `bucket`, `histogram`), and a *shell*,
`main`, that talks to the world, reading the input and printing the
results. The core is the part you want to test, reuse and trust. Let's
see what the compiler thinks of it.

## Asking

`volec query effects` prints the effects of a function, or of every
function in a module. `crate` is the root module, the whole program
here:

```console
$ volec query effects crate stats.vl
crate::mean	none
crate::bucket	none
crate::histogram	panic
crate::main	alloc(Gpa) io global panic diverge
```

Each line is a function and its effects. Let's read them.

- `mean` and `bucket` are `none`: they only compute. `mean` loops, but
  a `for` over a slice always ends, so that's not `diverge`.
- `histogram` is `panic`: `buckets[i]` is a checked index, and it stops
  the program if `i` is out of range. (`bucket` keeps `i` in range, but
  the compiler doesn't follow the arithmetic that far.)
- `main` does everything: it allocates (the `Vec`, the `String`), does
  I/O (stdin and printing), uses a global (std keeps its print buffer
  in one), may panic (the `unwrap`s), and may not return.

That last one is surprising: `main` has no loop that could run forever.
When an effect surprises you, ask *why*:

```console
$ volec query effects main --why diverge stats.vl
crate::main	alloc(Gpa) io global panic diverge
  'read_stdin_in(gpa)' at stats.vl:24:17 calls 'std::io::read_stdin_in'
...
```

`--why` prints the chain of calls from the function down to the line
that has the effect. Here `main` calls `read_stdin_in`, and the chain
goes on into the standard library, which reads in a `loop` until the
input ends. The compiler can't know the input ends, so reading all of
stdin may not return.

`--why` works for any effect. Where does the I/O come from?

```console
$ volec query effects main --why io stats.vl | head -2
crate::main	alloc(Gpa) io global panic diverge
  'read_stdin_in(gpa)' at stats.vl:24:17 calls 'std::io::read_stdin_in'
```

And `--has` turns the question around, listing the functions in a
module that have an effect:

```console
$ volec query effects crate --has 'alloc(Gpa)' stats.vl
crate::main	alloc(Gpa) io global panic diverge
```

If you use the editor extension from chapter 1, hovering over a
function's name shows the same effects, with a line on why it has each.

> **If you know Rust:** Rust has nothing quite like this. `const fn`
> is the closest, and it's much narrower; `#![no_std]` keeps allocation
> out of a whole crate, not out of one function. In vole every function
> has an effect set, inferred, and you can query it.

## Making a promise

Knowing what a function does today is useful. Knowing it will stay that
way is better. The core of `stats.vl` should never print, allocate or
touch a global, so let's say so:

```vole stats.vl
// stats: the mean and a histogram of the numbers on stdin.

#[pure]
#[no_panic]
fn mean(xs: [f64]) -> f64 {
    var total = 0.0;
    for x in xs {
        total += x;
    }
    total / xs.len() as f64
}

fn bucket(x: f64, lo: f64, hi: f64, n: i64) -> i64 {
    let i = ((x - lo) / (hi - lo) * n as f64) as i64;
    if i < 0 { 0 } else if i >= n { n - 1 } else { i }
}

#[pure]
fn histogram(xs: [f64], lo: f64, hi: f64, buckets: inout [i64]) {
    for x in xs {
        let i = bucket(x, lo, hi, buckets.len());
        buckets[i] += 1;
    }
}

fn main(gpa: Gpa) {
    let input = read_stdin_in(gpa).unwrap();
    let text = String::from_buf(input).unwrap();
    var xs: Vec<f64> = Vec::new_in(gpa);
    for word in text.split_whitespace() {
        xs.push(word.parse::<f64>().unwrap());
    }
    println(f"mean: {mean(xs):.2}");
    var buckets = [0; 5];
    histogram(xs, 0.0, 10.0, &buckets);
    for i in 0..5 {
        println(f"{i * 2:>2} to {i * 2 + 2:>2}: {buckets[i]}");
    }
}
```

```in
1 2 2.5 3 7 9.5 4 4.2 8 0.5
```

```out
mean: 4.17
 0 to  2: 2
 2 to  4: 3
 4 to  6: 2
 6 to  8: 1
 8 to 10: 2
```

The attributes above a function are its *declared* effects, and the
compiler checks them on every build:

- `#[pure]` means no `alloc`, no `io`, no `global`. A pure function may
  still panic, loop, and change its `inout` parameters: those are in its
  signature, and every call marks them with `&`. That's why `histogram`
  can be pure while it fills in `buckets`.
- `#[no_alloc]`, `#[no_io]` and `#[no_panic]` each rule out one effect.
  `mean` promises both `#[pure]` and `#[no_panic]`.
- `#[effects(...)]` lists exactly what's allowed, such as
  `#[effects(alloc(Gpa), panic)]`, and `#[effects()]` allows nothing.

A declaration is an upper bound. `histogram` is declared `#[pure]`, but
callers still see what it actually does, which is only `panic`. The
promise is what it will never do; the inferred set is what it does
now.

Notice that `bucket` has no attribute, yet `histogram` calls it. A
promise covers everything a function calls, declared or not, so if
`bucket` ever started printing, `histogram` would break its promise.
Let's watch that happen.

## When a promise breaks

Months later, someone is chasing a strange histogram and adds a debug
print to `bucket`. Here is the core with that change:

```vole
fn bucket(x: f64, lo: f64, hi: f64, n: i64) -> i64 {
    println(f"bucket of {x}");
    let i = ((x - lo) / (hi - lo) * n as f64) as i64;
    if i < 0 { 0 } else if i >= n { n - 1 } else { i }
}

#[pure]
fn histogram(xs: [f64], lo: f64, hi: f64, buckets: inout [i64]) {
    for x in xs {
        let i = bucket(x, lo, hi, buckets.len());
        buckets[i] += 1;
    }
}

fn main() {
    let xs = [1.0, 9.5];
    var buckets = [0; 5];
    histogram(xs, 0.0, 10.0, &buckets);
    println(f"{buckets[0]} {buckets[4]}");
}
```

```err
error[effect]: 'histogram' is #[pure], but it does io: 'bucket(x, lo, hi, buckets.len())' at main.vl: line 10, column 17 calls 'bucket'
 --> main.vl: line 8, column 1
  = help: return the data and let the caller print it, or remove #[pure]
  = try: volec query effects histogram --why io
```

The error is at the promise, `histogram`, not at the print: the print
itself is fine, in a function that promised nothing. The message names
the first step towards it, the call to `bucket`, and the `try:` line is
the query that shows the whole chain. The help gives the two honest
ways out: move the printing to the caller, or give up the promise.

Allocation works the same way. Here's a function that promises not to
allocate, but pushes onto a `Vec` it was given:

```vole
#[no_alloc]
fn above(xs: [f64], limit: f64, out: inout Vec<f64>) {
    for x in xs {
        if x > limit {
            out.push(x);
        }
    }
}

fn main(gpa: Gpa) {
    let xs = [1.0, 9.5];
    var big: Vec<f64> = Vec::new_in(gpa);
    above(xs, 5.0, &big);
    println(f"{big.len()}");
}
```

```err
error[effect]: 'above' is #[no_alloc], but it allocates from Gpa: 'out.push(x)' at main.vl: line 5, column 13 grows a Vec<f64>
 --> main.vl: line 2, column 1
  = help: allocate in the caller and pass the memory in, or remove #[no_alloc]
  = try: volec query effects above --why alloc(Gpa)
```

`above` takes no allocator, but `push` may need to grow the `Vec`, and
a `Vec` keeps its allocator inside it. The compiler sees through that:
the effect is `alloc(Gpa)` because `out` is a `Vec` with a `Gpa`. The
fix the help suggests is the one `histogram` uses: the caller makes
the room, and the function only fills it in.

## Effects and closures

A function that takes a closure can't know what the closure will do. It
can say what it allows, in the closure's bound, with `+ effects(...)`:

```vole
fn rescale<F: Fn(f64) -> f64 + effects(panic)>(xs: inout [f64], f: F) {
    for i in 0..xs.len() {
        xs[i] = f(xs[i]);
    }
}

fn main() {
    var xs = [1.0, 2.0, 3.0];
    rescale(&xs, |x| x * 10.0);
    rescale(&xs, |x| {
        println(f"scaling {x}");
        x / 2.0
    });
    println(f"{xs[0]} {xs[2]}");
}
```

```err
error[effect]: the closure for 'F' of 'rescale' does io ('println(f"scaling {x}")' at main.vl: line 11, column 9 calls 'std::fmt::println'); 'F: Fn(f64) -> f64 + effects(panic)' allows panic only
 --> main.vl: line 10, column 5
  = help: do only what the bound allows in the closure, or allow 'io' in the bound
```

The first call is fine: `|x| x * 10.0` does nothing but compute. The
second closure prints, and the error is at the call that passes it,
which is where the fix is. Without the `+ effects(...)` part, a bound
allows anything, and `rescale`'s own effects would simply include
whatever the closure does.

## Effects on traits

A promise on a trait's method binds every implementation of it. The
standard library uses this: the methods of `Eq`, `Ord` and `Hash` are
`#[pure]`. Here's an `Eq` that prints:

```vole
struct Word {
    text: str,
}

impl Eq for Word {
    fn eq(self, other: Word) -> bool {
        println("comparing");
        self.text == other.text
    }
}

fn main() {
    let a = Word { text: "vole" };
    println(f"{a == Word { text: "vole" }}");
}
```

```err
error[effect]: 'Word::eq' implements 'Eq::eq', which is #[pure], but it does io: 'println("comparing")' at main.vl: line 7, column 9 calls 'std::fmt::println'
 --> main.vl: line 6, column 5
  = help: return the data and let the caller print it, or remove #[pure] (the trait's)
  = try: volec query effects Word::eq --why io
```

Why insist? Because a `HashMap` or a sort decides how often it calls
`eq`, `cmp` and `hash`, and in what order; that changes when their
insides change. An `eq` that printed, or a `hash` that counted its
calls in a global, would make a program's behaviour depend on the
container's internals. Pure methods make that impossible. The help's
"remove #[pure] (the trait's)" applies to your own traits; for std's,
the way out is the first one.

> **If you know Haskell or Koka:** these effects are inferred and
> checked as upper bounds. There are no effect handlers, and no effect
> polymorphism beyond a closure's bound.

## Why bother

Effects cost you nothing to have: the compiler infers them whether or
not you look. Here is what they buy you when you do.

**Reading code.** A signature plus an effect set is most of what you
need to call a function safely. `mean: none` says you can call it
anywhere, as often as you like, in any order, and nothing outside it
will notice.

**Reviewing changes.** Run `volec query effects crate` before and after
a change, and compare. A function that suddenly gains `io` or
`alloc(Gpa)` is worth a second look, and a promise turns that look into
an error you can't miss. This matters just as much when the change was
written by an AI assistant: it can't quietly make your parser print,
and it can ask the compiler what a function does instead of guessing.

**Keeping a hot loop lean.** A team that wants no allocation in its
inner loop writes `#[no_alloc]` once, on the function that runs it.
From then on, every change to anything that loop calls is checked.

**Speed.** The optimizer uses the inferred effects too, whether or not
you write a promise. A call to a function with no effects, given the
same arguments, gives the same result, so the optimizer can compute it
once instead of on every trip around a loop, or drop it when the result
isn't used.

## Summary

- An effect is what a call may do beyond its result and its `inout`
  arguments: `alloc(A)`, `io`, `global`, `panic`, `diverge`, `unsafe`,
  and the thread effects `sync`, `thread` and `tls`.
- The compiler infers every function's effects. `volec query effects`
  prints them, `--why` shows the chain of calls behind one, and `--has`
  finds the functions that have one.
- `#[pure]`, `#[no_alloc]`, `#[no_io]`, `#[no_panic]` and
  `#[effects(...)]` declare an upper bound, checked on every build,
  through every call.
- A closure's bound can limit what it does (`+ effects(panic)`), and a
  trait method's promise binds every impl; std's `Eq`, `Ord` and `Hash`
  are pure.

Effects say what a function may *do*. The next chapter is about what it
needs and what it promises about its *values*: contracts, and the tests
that check them.

## Try it yourself

- Add `#[no_panic]` to `histogram`. Read the error, then make it go
  away without removing the promise. (Hint: `buckets.get(i)` and
  `set`, or a counted loop, or think about what `bucket` returns.)
- Write a `fn median(xs: [f64], gpa: Gpa) -> f64` that sorts a copy.
  What are its effects? Try `#[effects(alloc(Gpa), panic)]` on it.
- Run `volec query effects crate --has io` on chapter 11's word
  counter. Which functions print, and which only compute?
