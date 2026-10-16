# Memory

Tachyon has Rust's value semantics without lifetimes (0.17): a value has
one owner, an owned value moves and is dropped at the end of its scope,
references `&T` and `&mut T` are checked, and so are the views a slice
holds. There is no garbage collector and no reference counting; memory
comes from an allocator (`guide allocators`).

## Three kinds of types

The kind is computed from the type; nothing is declared:

| kind | what | `=`, a by-value argument, `return` |
|---|---|---|
| plain | numbers, bool, raw `*T`, structs, tuples and arrays of plain types | a bit copy, as in C |
| owned | `Vec`, `Buf`, `HashMap`, `Arena`, a type with `Drop`, a struct holding one | a move: the old name is dead until assigned again; `.clone()` copies |
| view | a slice `[T]`, a reference `&T`/`&mut T`, a struct holding one (`Scanner`), a closure capturing by reference | a copy (`&mut`: a move) that cannot outlive what it views |

`tachyonc query own FILE:LINE:COL` shows each local's kind there, and
whether it is moved or what it views.

## Moves and drops

```tach
fn total(v: &Vec<i64>) -> i64 {           // reads: a shared reference
    let mut s = 0;
    for x in v { s += x; }
    s
}

fn fill(v: &mut Vec<i64>, n: i64) {       // writes: an exclusive one
    for i in 0..n { v.push(i * i); }
}

fn make(n: i64, gpa: Gpa) -> Vec<i64> {   // the caller owns the result
    let mut v: Vec<i64> = Vec::new_in(gpa);
    fill(&mut v, n);
    v                                     // moved out: not dropped here
}

fn main(gpa: Gpa) {
    let v = make(4, gpa);
    let w = v.clone();                    // a copy; `let w = v;` moves v
    println(f"{total(&v)} {total(&w)} {w.len()}");
}                                         // w, then v, dropped (freed)
```
```out
14 14 4
```

- `let w = v;`, `f(v)` for a parameter `v: Vec<T>`, `return v`, a struct
  literal's field and a `move` closure move `v`; using `v` after that is
  `own.moved` (its `try:` makes the parameter `&Vec<T>`, or passes
  `v.clone()`).
- At the end of a scope its owned locals are dropped, last declared
  first, on every exit (`return`, `break`, `?`), not on `exit` or a
  panic. A moved value is not dropped where it was.
- `impl Drop for T { fn drop(self: &mut T) { ... } }` runs code at the
  drop; a type without one drops its fields. `drop(x)` drops early,
  `std::forget(x)` never (a leak, safe).
- Moving out of a borrowed place (`let k = self.keys;` in a `&mut self`
  method) is `own.move_out`: take it with `std::take(&mut self.keys)`,
  which leaves an empty one, or `std::replace`.
- `v.free()` still works: it consumes `v`. `defer v.free()`, the idiom
  before 0.17, is legal and no longer needed; `tachyonc fix --values`
  rewrites old code.

## References

- `&x` takes a shared reference: the callee reads. `&mut x` takes an
  exclusive one: the callee may change `x`. The parameter says which
  (`p: &T`, `p: &mut T`), and so does the call.
- `self: &T` and `self: &mut T` receivers are referenced by the call:
  `v.push(1)`, `p.get()`.
- Fields and methods reach through a reference (`p.x`, `p.len()`);
  the value itself is `*p` (`*out = acc`).
- `let r = &mut x;` keeps a reference in a local; passing `r` to several
  calls reborrows it each time. A struct may hold one
  (`struct Parser { q: &mut Query }`).
- Aliasing XOR mutation: while a `&mut x` (or a view of `x`) is in use,
  `x` is not read or changed another way. `f(&mut a, &a)` is an error;
  `v.push(v.len())` is fine (the receiver is taken after the arguments).
- A `*T` parameter (without `mut`) is still accepted as `&mut T` in
  0.17; `tachyonc fix --values` rewrites it to `&mut T` or `&T`.

## Views

A slice does not own memory: `v.as_slice()` views `v`'s elements, a
`Scanner` views its text. The checker keeps every view inside what it
views: a view used after its owner grew or was dropped (`own.conflict`),
returned out of the function that owns its memory (`own.escape`), or a
`for` loop over a Vec that pushes to it, is an error, not undefined
behaviour. Take the view again after the change, or keep an index:

```tach
let mut v: Vec<i64> = Vec::new_in(gpa);
v.push(1);
let s = v.as_slice();
print(f"{s[0]} ");                        // used before the pushes
for i in 0..100 { v.push(i); }            // may move the elements
let s2 = v.as_slice();                    // a fresh view
println(f"{s2.len}");
```
```out
1 101
```

`tachyonc guide views` has the rules, the diagnostics and the patterns
(parsers and lexers that keep views of their input are fine).

`tachyonc --check-alloc` (0.16) also checks at run time: every Gpa block
on pages of its own, so a use after free (through `unsafe` code) faults
and is reported with where the block was allocated and freed; bad frees
and leaks are reported too (`gpa.live_blocks()`, `gpa.check_leaks()` for
tests).

## Raw memory

`malloc` and `free` from C, raw `*T` pointers, in `unsafe` (`tachyonc
guide unsafe`). `tachyonc --check-unsafe -O1` checks heap accesses
through raw pointers at run time. Memory nobody wrote (from `malloc`)
has an unspecified value: write it before reading it.
