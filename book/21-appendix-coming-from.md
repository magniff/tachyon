# Appendix C: coming from another language

If you already know a language well, the quickest way into vole is a
list of differences: what carries over, what looks the same and means
something else, and the first errors you'll meet. This appendix has one
section per background. Each row points to the chapter that explains
it, and each section ends with a small program.

Read the section for the language you know best; the others are short.

## From Rust

Vole looks like Rust on purpose: the same `fn`, `struct`, `enum`,
`match`, `impl`, traits and generics, `Option` and `Result` with `?`,
modules and `use`, `unsafe` and `extern "C"`. That's the good news. The
bad news is that a few things that look the same mean something else,
and Rust habits are the most common source of errors for a Rust
programmer. The compiler knows this, and most of them get an error
called `conv.rust` with the vole spelling on its `try:` line.

| Rust | vole | chapter |
|---|---|---|
| `x: &T`, `f(&x)` | `x: T`, `f(x)`: a parameter is read-only by default (*let*) | 4 |
| `x: &mut T`, `f(&mut x)` | `x: inout T`, `f(&x)`: `&` marks the argument that may change | 4 |
| `x: T`, taking ownership | `x: sink T`, `f(x)` | 4 |
| `&self`, `&mut self`, `self` | `self`, `inout self`, `sink self` | 4, 5 |
| `let mut x` | `var x` | 3 |
| `*r += 1` through a `&mut` | `r += 1`: an `inout` is used as the value; `*` is only for raw pointers | 4, 15 |
| lifetimes, `'a` | none: the compiler infers what each function's result views | 4 |
| `Box<T>`, `Rc<T>`, `Arc<T>` | none: values, a `Vec` and indices, or raw memory in `unsafe` | 8 |
| `Vec::new()`, `String::new()`, `format!` | `Vec::new_in(gpa)`, `String::new_in(gpa)`, `to_string_in(f"..", gpa)`: allocation is explicit | 8 |
| `println!`, `vec!`, `assert!`, macros | `println(f"{x}")`, `assert(c)`, `assert_eq(a, b)`; there are no macros | 1, 13 |
| `dyn Trait`, `impl Trait` arguments, `where` | generics: `fn f<T: Trait>(x: T)` | 9 |
| overflow panics in debug builds | integers always wrap; `x / 0` is 0 | 3 |
| `char`, `'a'` | no `char` yet: `'a'` is a `u8`; a code point is a `u32` | 7 |
| `a.cmp(&b)` returns `Ordering` | `a.cmp(b)` returns an `i64`: negative, zero or positive | 9 |
| `'outer: loop { break 'outer; }` | `outer: loop { break :outer; }` | 3 |
| `m.entry(k).or_insert(0)` | `m.get_or_insert(k, 0)[0] += 1` | 7 |
| `iter_mut()` | an index loop: `for i in 0..v.len() { v[i] += 1; }` | 7 |
| Cargo, crates | none yet: a program is its files, and C libraries through headers | 11 |
| bindgen | `import "header.h" as c;` | 15 |
| `#[test]`, proptest, cargo-fuzz | `#[test]`, `#[property]`, `#[fuzz]`, run by `volec test` | 13 |

The biggest difference is the first three rows. In Rust, `&x` makes a
reference, a value you can store and return, and the borrow checker
follows it with lifetimes. Vole has no references. A parameter says
what the function does with its argument: reads it (the default),
changes it (`inout`), or takes it (`sink`). That's all a caller needs to
know, so there's nothing to annotate and no lifetime to name. Views
(`str`, `[T]`) exist, and the compiler checks them, but you never write
their lifetimes.

Here's a small Rust-shaped program, as a Rust programmer would type it
on day one. Save it as `bump.vl`:

```vole bump.vl skip
fn bump(n: &mut i64) {
    *n += 1;
}

fn main() {
    let mut x = 1;
    bump(&mut x);
    println(f"{x}");
}
```

Every Rust spelling in it is an error, and every error has an exact fix.
`volec fix --only conventions` makes them all at once:

```console
$ printf '%s\n' 'fn bump(n: &mut i64) {' '    *n += 1;' '}' '' 'fn main() {' '    let mut x = 1;' '    bump(&mut x);' '    println(f"{x}");' '}' > bump.vl
$ volec fix --only conventions bump.vl
fixed 1 parameter to inout, 1 '&mut e' to '&e', 1 '*r' of an access, 1 'let mut' / 'mut x' to var	bump.vl	+4 -4 lines
$ cat bump.vl
fn bump(n: inout i64) {
    n += 1;
}

fn main() {
    var x = 1;
    bump(&x);
    println(f"{x}");
}
$ volec bump.vl -o bump
ok: built bump
$ ./bump
2
```

(The first line writes the file, so that the book's tests can run this
session.) `volec guide rust` is the full mapping, a page of tables like
the one above.

## From C and C++

Vole is a systems language, compiled to machine code, with no garbage
collector and no runtime to speak of, so a C programmer will find the
performance model familiar. What changes is the safety: the language
is designed so that ordinary code can't have undefined behaviour.

| C or C++ | vole | chapter |
|---|---|---|
| undefined behaviour: signed overflow, a bad index, an uninitialized variable | none in safe code: integers wrap, every index is checked, every variable is set | 3, 15 |
| `malloc` and `free`, `new` and `delete` | allocators passed as parameters; values are freed when they go out of scope | 8 |
| destructors (C++) | `impl Drop`, run at the end of the scope | 4, 15 |
| a pointer and a length, passed separately | a slice, `[T]`, which carries its length | 7 |
| `char *` strings | `str`, UTF-8 with a length; `c"..."` for C | 7, 15 |
| `int`, `long`, `size_t` | `i32`, `i64`, `u64`; lengths and indices are `i64` | 3 |
| `#include` and the preprocessor | `mod` and `use`; no macros | 11 |
| exceptions (C++), error codes | `Result` and `?` | 6 |
| templates (C++) | generics, compiled once per type as templates are; bounds are checked at each call | 9 |
| calling C | direct: `import "stdio.h" as c;`, or `extern "C"` | 15 |
| struct layout | unspecified, unless `#[repr(C)]` | 15 |
| `-ffast-math`, optimizations based on UB | none; contracts tell the optimizer facts, and they're checked | 16 |
| `assert`, `NDEBUG` | `assert`, and `requires`/`ensures` contracts, checked in every build | 13 |

Two of these surprise C programmers most. First, indexing is checked:
`v[i]` past the end stops the program with a message and exit status
101, rather than reading some other memory. The compiler removes the
check wherever it can prove `i` is in range, as it can in a simple
counted loop, and `volec query checks` shows the ones left (chapter
16). Second, division by zero isn't a crash: `x / 0` is 0 and
`x % 0` is `x`. Both are defined, so the optimizer has nothing to
assume.

The C-like parts of vole are still there: raw pointers, `malloc`,
unions, calling any C function. They're allowed inside `unsafe`, which
marks the few lines where C's rules apply (chapter 15).

```vole c.vl
// The sum of a slice: the slice knows its length.
fn sum(xs: [i32]) -> i32 {
    var total: i32 = 0;
    for x in xs {
        total += x; // wraps on overflow: defined, unlike C's int
    }
    total
}

fn main(gpa: Gpa) {
    var v: Vec<i32> = Vec::new_in(gpa); // freed when main ends: no free()
    v.push(2147483647);
    v.push(1);
    println(f"{sum(v.as_slice())} {v.len()}");
    let zero = v.len() - 2;
    println(f"{7 / zero} {7 % zero}");
    println(f"{v[2]}");
}
```

```out exit=101
-2147483648 2
0 7
c.vl:17:16: index out of bounds: index 2, length 2
```

> **If you know C++:** there are no constructors, no inheritance, no
> overloading and no implicit conversions that lose information.
> Methods live in `impl` blocks, interfaces are traits, and a struct is
> built with all its fields named: `Point { x: 1, y: 2 }`.

## From Go

Go and vole share a taste for simple, explicit code and a compiler that
cares about its own speed (chapter 16), but they make the opposite
choice about memory.

| Go | vole | chapter |
|---|---|---|
| a garbage collector | no collector: values are freed at the end of their scope; allocators are explicit parameters | 8 |
| `if err != nil { return err }` | `Result<T, E>` and `?` | 6 |
| `panic`, `recover` | `panic`, with no recover: a panic ends the program, with exit status 101 | 6 |
| goroutines and channels | OS threads (`std::thread`) and channels (`std::sync::mpsc`) | 14 |
| data races found by `-race`, at run time | data races rejected by the compiler | 14 |
| interfaces, satisfied implicitly | traits, implemented explicitly, resolved at compile time; enums for "one of several types" | 5, 9 |
| generics | generics, specialized for each type (no boxing) | 9 |
| slices that share an array | `[T]` views, which can't outlive or see changes to what they view | 4 |
| `defer` | `defer` (`volec guide syntax`), and `Drop` for values that clean up after themselves | 4, 15 |
| `go fmt`, `go vet` | `volec fmt`, and the compiler's own checks | 17 |
| modules and packages | modules (`mod`, `use`, `pub`); no packages yet | 11 |
| zero values | every variable is set when it's declared | 3 |

The trade is this: Go makes memory easy by collecting it for you, at the
cost of a collector running alongside your program. Vole makes you pass
an allocator to code that allocates, which is more typing, and in return
memory is freed at predictable points, you can see in a signature
whether a function allocates, and a part of a program can use an arena
instead (chapter 8).

Here is Go's most common pattern, returning an error up the call
chain, with a few threads sending results down a channel:

```vole go.vl
use std::thread;
use std::sync::mpsc;

// Like Go's strconv.Atoi: the number, or an error to return.
fn parse(s: str) -> Result<i64, str> {
    match s.parse::<i64>() {
        Ok(n) => Ok(n),
        Err(_) => Err("not a number"),
    }
}

fn sum_of_squares(words: [str], gpa: Gpa) -> Result<i64, str> {
    var nums: Vec<i64> = Vec::new_in(gpa);
    for w in words {
        nums.push(parse(w)?); // Go: if err != nil { return 0, err }
    }
    let total = thread::scope(|s| {
        let (tx, rx) = mpsc::channel_in::<i64>(gpa);
        for n in nums.as_slice() {
            let tx = tx.clone();
            s.spawn(sink || {
                tx.send(n * n).unwrap();
                0
            });
        }
        drop(tx);
        var sum = 0;
        for x in rx.iter() {
            sum += x;
        }
        sum
    });
    Ok(total)
}

fn main(gpa: Gpa) {
    let good: [str; 3] = ["1", "2", "3"];
    let bad: [str; 2] = ["1", "two"];
    println(f"{sum_of_squares(good, gpa):?}");
    println(f"{sum_of_squares(bad, gpa):?}");
}
```

```out
Ok(14)
Err("not a number")
```

`thread::scope` waits for every thread started in it before it returns,
like a `sync.WaitGroup` built into the call. Each thread gets its own
`Sender`, and `drop(tx)` drops the original, so that `rx.iter()` ends
when the last thread is done.

## From Python, JavaScript or Java

Coming from a dynamic or garbage-collected language, three things will
feel different at first: types are checked before the program runs,
values are copied or moved rather than shared, and memory is managed
without a collector.

| Python, JavaScript, Java | vole | chapter |
|---|---|---|
| types checked at run time (Python, JavaScript) | types checked by the compiler; most are inferred, so you write few | 3 |
| `b = a` shares one list | `var b = a;` moves a `Vec` into `b`; `a.clone()` copies it | 4 |
| a function can change any object you pass it | only an `inout` parameter can, and the call says so: `f(&x)` | 4 |
| exceptions, `try`/`except` | `Result` and `?`; a `panic` for bugs | 6 |
| `None`, `null`, `undefined` | `Option<T>`: `Some(x)` or `None`, and the compiler makes you handle both | 6 |
| a garbage collector | values are freed when they go out of scope | 8 |
| classes and inheritance | structs with methods, traits for shared behaviour, enums for alternatives | 5, 9 |
| list comprehensions, `map`/`filter` | iterator chains: `v.iter().filter(..).map(..)` | 10 |
| `import` runs the module's code | `use` only names things; modules are compiled together | 11 |
| run by an interpreter or a VM | compiled to a native executable | 1 |

The second row is the one to watch. In Python, after `b = a`, both
names refer to the same list, and a change through one shows through
the other. In vole, a `Vec` has one owner. `var b = a;` moves it, and
using `a` afterwards is an error:

```vole
fn main(gpa: Gpa) {
    var a: Vec<i64> = Vec::new_in(gpa);
    a.push(1);
    var b = a;
    b.push(2);
    println(f"{a.len()} {b.len()}");
}
```

```err
error[own.moved]: 'a' is used here after it moved at 4:13
 --> main.vl: line 6, column 16
  = help: use it before the move, pass a copy where it moves ('.clone()'), or let the callee read it: a let parameter ('x: T'), not 'sink'
  = try: volec edit patch main.vl:4 --old 'var b = a;' --new 'var b = a.clone();'
```

Following the `try:` line, `var b = a.clone();` makes `b` a copy, and
the two lists are independent:

```vole
fn main(gpa: Gpa) {
    var a: Vec<i64> = Vec::new_in(gpa);
    a.push(1);
    var b = a.clone();
    b.push(2);
    println(f"{a.len()} {b.len()}");
}
```

```out
1 2
```

Nothing is shared by accident, so a function that reads a value can't
change it behind your back, and two threads can't race on it. When you
do want a function to change a value, `inout` and `&` say so in both the
signature and the call. Chapter 4 explains the whole idea; it's the one
chapter worth reading slowly.
