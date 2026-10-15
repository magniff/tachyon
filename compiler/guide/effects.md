# Effects (0.16)

Every function has an inferred effect set: what calling it may do. It
is inferred from the body and everything the body calls, closures and
generic instances included, and never depends on `-O`:

| effect | comes from |
|---|---|
| `alloc(Gpa)`, `alloc(Arena)`, `alloc(extern)` | allocating from that allocator type (`extern`: C's malloc) |
| `io` | a C function that reads or writes: `write`, `read`, stdio |
| `global` | reading or writing a `static mut`, taking its address |
| `panic` | a checked index or slice, `unwrap`, `as E`, std's panic |
| `diverge` | `while`, `loop`, recursion: it may not return (a counted `for` returns) |
| `unsafe` | unsafe operations in its own body (not its callers') |

A set is written in that order, `none` for the empty one. Allocation is
explicit (`guide allocators`), so `alloc(Gpa)` without `global` means
"from a Gpa it was given". Running out of memory is `alloc`, not `panic`.

## Asking

```sh
tachyonc query effects total            # crate::total  alloc(Gpa) panic
tachyonc query effects crate::parser    # every function of a module
tachyonc query effects total --why alloc     # the chain of calls down to where it allocates
tachyonc query effects crate --has io        # the functions that do io
tachyonc --print-effects main.tach           # every function's set, then the build
```

`query def`, `show` and `context` print a function's set on its first
line (`effects: alloc(Gpa) panic`); a generic function's sets are its
instances' (`query effects` lists each).

## Declaring

A declaration is an upper bound the compiler checks against the
inferred set; callers still see the inferred one, which may be smaller.

```tach
#[pure]                                   // no alloc, io or global
fn mid(a: i64, b: i64) -> i64 { a + (b - a) / 2 }

#[no_alloc]
fn sum(s: [i64]) -> i64 { s.iter().sum() }

#[effects(alloc(Gpa), panic, diverge)]    // at most these
fn grow(v: *Vec<i64>) { v.push(1); }

fn apply<F: Fn(i64) -> i64 + effects(panic)>(f: F, x: i64) -> i64 { f(x) }

fn main() -> i32 {
    let a = [1, 2];
    println(apply(|x| mid(x, 10), 2) + sum(a[..]));
    0
}
```
```out
9
```

- `#[pure]`: no `alloc`, `io`, `global` (it may panic, loop and write
  through its pointer parameters); `#[no_alloc]`, `#[no_io]`,
  `#[no_panic]` forbid one; `#[effects(...)]` lists what is allowed,
  `#[effects()]` nothing. Several attributes intersect.
- On a trait's function (`#[pure] fn hash(self: *Self) -> u64;`) the
  declaration binds every impl; std's `Eq`, `Ord` and `Hash` are pure.
- On a C function in an `extern` block it is trusted, as its signature
  is. Undeclared, std's table applies (libm and `mem*`: none, `malloc`:
  `alloc(extern)`, stdio: `io`), else everything.
- A bound `F: Fn(..) -> R + effects(panic)` is checked where `F` is
  given: the error is at the call, naming the closure's effect.
- A call through a `fn` value may call every function of that type
  whose address the program takes.

A broken declaration is one error with where the effect comes from:

```text
sum.tach:3:1: error[effect] 'total' is #[no_alloc], but it allocates from Gpa: 'v.push(x)' at sum.tach:7:9 grows a Vec<i64>
help: allocate in the caller and pass '*Vec<i64>' with room, or remove #[no_alloc]
try: tachyonc query effects total --why alloc
```
