# Memory

Vole's values have one owner each (0.17; spelled `let` / `inout` /
`sink` since 0.20): an owned value moves and is dropped at the end of
its scope, a function says by its parameters' conventions what it does
with each argument, and the views a slice holds are checked. Nothing
stores a reference, so there are no lifetimes to write. There is no
garbage collector and no reference counting; memory comes from an
allocator (`guide allocators`).

## Three kinds of types

The kind is computed from the type; nothing is declared:

| kind | what | `let w = v;`, a sink argument, `return` |
|---|---|---|
| plain | numbers, bool, raw `*T`, structs, tuples and arrays of plain types | a bit copy, as in C |
| owned | `Vec`, `Buf`, `HashMap`, `Arena`, a type with `Drop`, a struct holding one | a move: the old name is dead until assigned again; `.clone()` copies |
| view | a slice `[T]`, a struct holding one (`Scanner`) or an access field (`q: inout Query`), a closure capturing by access | a copy (one holding an `inout`: a move) that cannot outlive what it views |

`volec query own FILE:LINE:COL` shows each local's kind there, and
whether it is moved or what it views.

## Conventions: let, inout, sink

A parameter's convention says what the function does with the argument:

| convention | written | the callee | the caller writes |
|---|---|---|---|
| let (the default) | `v: Vec<i64>` | reads it; cannot change or keep it | `total(v)`: lent for the call, or a temporary |
| inout | `v: inout Vec<i64>` | may change it; the change reaches the caller | `fill(&v)`: `&` marks it |
| sink | `v: sink Vec<i64>` | owns it (may change it, keeps or drops it) | `keep(v)`: v moves (a plain value is copied) |

```tach
fn total(v: Vec<i64>) -> i64 {           // let: reads, no copy
    var s = 0;
    for x in v { s += x; }
    s
}

fn fill(v: inout Vec<i64>, n: i64) {     // inout: changes the caller's Vec
    for i in 0..n { v.push(i * i); }
}

fn keep(all: inout Vec<Vec<i64>>, v: sink Vec<i64>) {   // sink: takes it
    all.push(v);
}

fn make(n: i64, gpa: Gpa) -> Vec<i64> {  // the caller owns the result
    var v: Vec<i64> = Vec::new_in(gpa);
    fill(&v, n);
    v                                    // moved out: not dropped here
}

fn main(gpa: Gpa) {
    let v = make(4, gpa);
    let w = v.clone();                   // a copy; `let w = v;` moves v
    println(f"{total(v)} {total(w)} {w.len()}");
    var all: Vec<Vec<i64>> = Vec::new_in(gpa);
    keep(&all, w);                       // w is dead from here
    println(all.len());
}                                        // all (and w in it), then v, dropped (freed)
```
```out
14 14 4
1
```

- There are no references to take or store: where other languages
  borrow (a shared reference `&T`, a mutable reference `&mut T`), a let
  parameter borrows the value read-only for the call and an inout one
  borrows it exclusively, with `&x` at the call.
- For a plain type (`i64`, a struct of numbers) `let` and `sink` are
  both a copy; only `inout` changes the caller's value. For an owned one
  `let` lends it and `sink` moves it.
- Receivers: `fn len(self)`, `fn push(inout self, x: sink T)`, `fn
  finish(sink self)`. A method call lends its receiver without `&`:
  `v.push(1)` changes `v`, so `v` must be `var` (or an inout parameter).
- A let parameter is read-only: changing it is an error that names the
  fix (take it `inout`). Defaults: `b: i64 = 2` on let and sink
  parameters, not on inout ones.
- Mutable locals are `var x = e;`; `let` ones cannot change. A `sink`
  parameter is the callee's own, so it is mutable.

## Moves and drops

- `let w = v;`, a sink argument, `return v`, a struct literal's field
  and a `sink ||` closure move `v`; using `v` after that is `own.moved`,
  which names where it moved (`'keep(sink v)'`); its `try:` passes
  `v.clone()`, or lend it to a let parameter instead.
- At the end of a scope its owned locals are dropped, last declared
  first, on every exit (`return`, `break`, `?`), not on `exit` or a
  panic. A moved value is not dropped where it was.
- `impl Drop for T { fn drop(inout self) { ... } }` runs code at the
  drop; a type without one drops its fields. `drop(x)` drops early,
  `std::forget(x)` never (a leak, safe). A type with a Drop of its own
  holds no view, also through a type argument (`G<[i64]>` of `impl<T>
  Drop for G<T>`): `own.drop_view`, since its drop could read what the
  view points to after that is gone. std's containers of views are fine.
- `let x = v[i];` of an owned element borrows it (a let access, read
  only); `var x = v[i];` would move it out of the Vec and is
  `own.move_out`, as is `var k = self.keys;` in an `inout self` method:
  take it with `self.keys.take()`, which leaves an empty one
  (`std::take(&x)` for a `Default` value), `std::replace`, or
  `.clone()`.
- `v.free()` still works: it frees now and leaves `v` empty (its drop
  then frees nothing). `defer v.free()`, the idiom before 0.17, is
  legal and no longer needed.

## Accesses

An access is what a let or inout parameter holds: not a pointer to
manage, but the caller's value itself, used as that value.

- Read it, write it, call its methods: `n + 1`, `out = acc`, `out +=
  1`, `v.push(x)`, `p.x`. There is no `*r`; `*` is only for raw `*T`
  pointers.
- `inout r = &st;` names an inout access in a local; pass it on as
  `&r`, any number of times: `bump(&r); bump(&r);`. A let argument needs
  no local: pass `st` itself.
- A struct may hold one as a field: `struct Parser { toks: [Tok], q:
  inout Query }`, built as `Parser { toks: t, q: &q }`; such a struct is
  a view (`guide views`).
- `match e { E::A(n) => n + 1, .. }` on a let `e` binds into it;
  `match &x { .. }` binds inout accesses that change `x`'s parts.
- Exclusivity: while an inout access of `x` (or a view of it) is in use,
  `x` is not read or changed another way. `f(&a, a)` and `f(&a, &a)` are
  errors (`own.conflict`); `v.push(v.len())` is fine (the receiver is
  taken after the arguments).
- `*T` is a raw pointer (0.18.1): dereferencing it needs `unsafe`;
  `&x` passed where a `*T` is wanted gives the address, with an
  exclusive loan for the call (`guide unsafe`).

## Views

A slice does not own memory: `v.as_slice()` views `v`'s elements, a
`Scanner` views its text. The checker keeps every view inside what it
views: a view used after its owner grew or was dropped (`own.conflict`),
returned out of the function that owns its memory (`own.escape`), or a
`for` loop over a Vec that pushes to it, is an error, not undefined
behaviour. Take the view again after the change, or keep an index:

```tach
var v: Vec<i64> = Vec::new_in(gpa);
v.push(1);
let s = v.as_slice();
print(f"{s[0]} ");                        // used before the pushes
for i in 0..100 { v.push(i); }            // may move the elements
let s2 = v.as_slice();                    // a fresh view
println(f"{s2.len()}");
```
```out
1 101
```

`volec guide views` has the rules, the diagnostics and the patterns
(parsers and lexers that keep views of their input are fine).

`volec --check-alloc` (0.16) also checks at run time: every Gpa block
on pages of its own, so a use after free (through `unsafe` code) faults
and is reported with where the block was allocated and freed; bad frees
and leaks are reported too (`gpa.live_blocks()`, `gpa.check_leaks()` for
tests).

## Raw memory

`malloc` and `free` from C, raw `*T` pointers, in `unsafe` (`volec
guide unsafe`). `volec --check-unsafe -O1` checks heap accesses
through raw pointers at run time. Memory nobody wrote (from `malloc`)
has an unspecified value: write it before reading it.
