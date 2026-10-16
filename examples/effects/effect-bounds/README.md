# Effect bounds: what a library lets your closure do

`table.tach` is a small library over rows of a name and a value. Its
operations take closures, and each closure parameter's bound says what
the closure may do, with `+ effects(...)` after the `Fn` type:

```tach
pub fn map_values<F: Fn(i64) -> i64 + effects(panic)>(rows: &mut [Row], f: F)
pub fn partition<F: Fn(*Row) -> bool + effects()>(rows: &mut [Row], keep: F) -> i64
pub fn sort_by_key<F: Fn(*Row) -> i64 + effects(panic)>(rows: &mut [Row], key: F)
pub fn each<F: FnMut(*Row)>(rows: [Row], f: F)
```

A library that calls your closure decides how often, and in which
order: a sort calls its key about 2 n log n times, in an order that is
its own business; a map may call `f` once per row today and once per
distinct value tomorrow. A closure that prints, counts in a static or
allocates would make those choices visible. The bound rules it out, and
the compiler checks it where the closure is given: the error is at your
call, naming what your closure does and the line that does it, not
somewhere inside the library.

| bound | the closure may |
|---|---|
| `effects()` | only compute: not even panic (`partition`: a filter that stopped the program halfway would leave the table half moved) |
| `effects(panic)` | compute, and panic (an index, an `unwrap`) |
| none | anything (`each` exists to let the caller print) |

Every command below is run by `tests/walkthrough/run.sh` in a copy of
this directory, and its output is checked against this file;
`tests/examples/effects-effect-bounds.test` runs the program.

## Run it

```console
$ tachyonc main.tach -o table && ./table
grace     90
alan      46
ada       41
brian     12
barbara   17
3 of 5 rows kept, sorted by value
```

`main.tach` gives each operation a closure within its bound: `|v| v +
bonus` (it captures `bonus`, and only reads it), `|r| r.value >= 20`,
`|r| -r.value`. The closure for `each` prints, and counts the rows it
printed in a local it captures (`shown += 1`): state of the caller's
own is not an effect, only statics are (`global`).

## Each instance's effects

A generic function's effects are its instances': one per closure.

```console
$ tachyonc query effects crate::table
map_values<closure(i64) -> i64 at main.tach:17:31>	none
partition<closure(*Row) -> bool at main.tach:18:38>	panic
sort_by_key<closure(*Row) -> i64 at main.tach:19:33>	none
each<closure(*Row) -> () at main.tach:21:20>	io global panic
```

`map_values` is `none` for this closure (its `rows[i]` is in a counted
loop over the rows: in range); `each`'s instance has the closure's
`io`.

## A closure that prints

```console
$ tachyonc edit patch main --old '|v| v + bonus' --new '|v| {
>         println(f"{v}");
>         v + bonus
>     }'
main.tach:17:5: error[effect] the closure for 'F' of 'table::map_values' does io ('println(f"{v}")' at main.tach:18:9 calls 'std::println'); 'F: Fn(i64) -> i64 + effects(panic)' allows panic only | help: do only what the bound allows in the closure, or allow 'io' in the bound  [edited: crate::main]
error edit.breaks: 1 new error; nothing written
try: tachyonc edit patch main --old '|v| v + bonus' --new '|v| {
        println(f"{v}");
        v + bonus
    }' --no-check
[exit 1]
```

The error is at the call of `map_values` in `main`, and says what the
closure does (`io`), where (the `println`), and what the bound allows.
The help offers both ways out: do less in the closure, or (if you own
the library) widen the bound.

## A closure that may panic, where nothing may

`r.name[0]` is a checked index: an empty name would stop the program.
`partition`'s bound is `effects()`:

```console
$ tachyonc edit patch main --old '|r| r.value >= 20' --new "|r| r.name[0] == 'a'"
main.tach:18:13: error[effect] the closure for 'F' of 'table::partition' may panic ('r.name[0]' at main.tach:18:42 is a checked index); 'F: Fn(*Row) -> bool + effects()' allows none only | help: do only what the bound allows in the closure, or allow 'panic' in the bound  [edited: crate::main]
error edit.breaks: 1 new error; nothing written
try: tachyonc edit patch main --old '|r| r.value >= 20' --new '|r| r.name[0] == 'a'' --no-check
[exit 1]
```

`get` returns an `Option` instead, which cannot fail:

```console
$ tachyonc edit patch main --old '|r| r.value >= 20' --new "|r| r.name.get(0) == Some('a')" --show
patched crate::main	main.tach	+1 -1 lines
// main.tach:18
18	    let n = partition(&mut rows[..], |r| r.name.get(0) == Some('a'));
$ tachyonc main.tach -o table && ./table
alan      46
ada       41
brian     12
grace     90
barbara   17
2 of 5 rows kept, sorted by value
```

## What the bound is not

- It is an upper bound on the closure, not on the library: `sort_by_key`
  may do whatever its own body does (here it calls std's `sort_by`).
- A function given as a value (`fn` type) is checked the same way: its
  effects are those of every function of that type whose address the
  program takes.
- Effects name kinds, not values: `effects(alloc(Arena))` would let the
  closure allocate from any arena, not only one the library chose.

## Read more

- `tachyonc guide effects`, section "Declaring" (bounds are the last
  form).
- `tachyonc guide closures`: `Fn` and `FnMut`, captures.
- [pure-and-no-alloc](../pure-and-no-alloc/): the same promises on
  functions.
