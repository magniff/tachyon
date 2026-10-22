# 10. Closures and iterators

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

Functions as values, and data processing in chains. By the end the
reader can:

- write closures, give them to generic functions with `Fn`/`FnMut`
  bounds, and keep them in a `let` or a struct field;
- say what a closure captures and how (copy, read, change, take), and
  use `sink ||` to make one own its captures;
- process sequences with `map`, `filter`, `enumerate`, `zip`, `take`,
  `fold`, `sum`, `count`, `min`, `max`, `any`, `all`, `find`,
  `position`, `collect_in`;
- write their own iterator;
- know that these chains cost nothing at run time.

## Running example

A log analyzer over stdin (lines like `200 GET /index.html 512`):
count status codes, sum bytes for successful requests, find the
slowest, collect the paths of errors into a Vec, sort them with
`sort_by`. Then a `Fibonacci` iterator of our own. examples/closures-iterators
is the long version.

## Sections

1. **Closures.** `|x| x + k`; parameter types from the context, or
   written `|x: i64|`; block bodies; `return` inside a closure returns
   from it.
2. **Captures.** The table: a plain `let` is copied, an owned `let` is
   read in place, a `var` is changed in place, anything in a `sink ||`
   closure is taken. While a closure that captures `x` may still be
   called, `x` isn't changed another way (`own.conflict`); show it and
   the fix.
3. **Fn, FnMut and fn.** `F: Fn(i64) -> i64` (doesn't change its
   captures), `F: FnMut(i64)` (may); plain function values `fn(i64) ->
   i64`, and a closure that captures nothing converts to one. No `FnOnce`,
   no boxed closures; closures can't be returned (yet).
4. **Iterators.** `v.iter()`, ranges as values `(0..n)`, `m.iter()`.
   Adapters are lazy; consumers run them. `for` works on any iterator.
   `collect_in(gpa)` makes a Vec (the allocator again).
5. **Writing an iterator.** `impl Iterator for Fibonacci { type Item =
   i64; fn next(inout self) -> Option<i64> }`; every adapter comes free.
6. **Zero cost.** The chain compiles to the loop you'd write by hand.
   Show it briefly with timing or with `--emit-ir` (light touch; chapter
   16 goes deeper).
7. **What's not there yet.** No `iter_mut` (use indices), no `chain`,
   `flat_map`, `peekable`, `step_by`. Keep it to one short paragraph:
   the list will shrink.

## Errors to show

- `cannot infer the type of closure parameter 'x'` (a closure in a `let`
  with no annotation), fixed by `|x: i64|`.
- A capturing closure passed where `fn(i64) -> i64` is wanted.
- `own.conflict`: changing a variable a live closure captured.
- `conv.rust`: `move ||` with its `sink ||` fix.

## Asides

- If you know Rust: `sink ||` is `move ||`; `|x|` not `|&x|`; no
  `FnOnce`, no `impl Fn` results; `collect_in(gpa)` only to a Vec.
- If you know Python or JavaScript: closures capture by the rules above,
  decided per variable, never by reference to a variable that keeps
  changing behind your back.

## Sources

`volec guide closures`, `guide iterators`, examples/closures-iterators,
docs/design/closures-iterators.md.
