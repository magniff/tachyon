# 12. Effects: what a function may do

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

Read and use the effects the compiler infers. By the end the reader
can:

- name the effects (`alloc(A)`, `io`, `global`, `panic`, `diverge`,
  `unsafe`, and the thread ones `sync`, `thread`, `tls`) and what causes
  each;
- ask the compiler for a function's effects and for *why* it has one;
- declare a bound (`#[pure]`, `#[no_alloc]`, `#[no_io]`, `#[no_panic]`,
  `#[effects(...)]`) and read the error when the body breaks it;
- put an effect bound on a closure parameter;
- explain what this is good for: reading code, reviewing changes, and
  the optimizer.

## Running example

A checksum or statistics core (`fn mean(xs: [f64]) -> f64`, `fn
histogram(xs: [f64], buckets: inout [i64])`) that must stay pure, used
by an I/O shell (`main` reads numbers, prints the result). The core is
marked `#[pure]`/`#[no_alloc]`; a later "small change" that adds a debug
`println` or a `Vec` inside it is caught. examples/effects has four
ready programs.

## Sections

1. **What an effect is.** Beyond its parameters (which the conventions
   cover: `inout` for what it changes, `sink` for what it takes), what
   can calling a function do? Allocate, do I/O, touch global state,
   panic, never return. The compiler infers this for every function, from
   its body and everything it calls.
2. **Asking.** `volec query effects NAME` (console sessions), `--why io`
   for the chain of calls, `--has alloc(Gpa)` across a module; the
   editor's hover shows the same (chapter 1's extension).
3. **Declaring.** `#[pure]` (no alloc, io or global; it may still panic
   and change its `inout` parameters), `#[no_alloc]` and friends,
   `#[effects(alloc(Gpa), panic)]`. A declaration is an upper bound the
   compiler checks; callers still see the precise inferred set.
4. **When it breaks.** Show the error: `'total' is #[no_alloc], but it
   allocates from Gpa: 'v.push(x)' at ...`, its help and `try:`.
5. **Effects and closures.** `F: Fn(i64) -> i64 + effects(panic)`; the
   error lands at the call that passes a closure doing more.
6. **Effects on traits.** `#[pure]` on a trait method binds every impl;
   std's `Eq`, `Ord`, `Hash` are pure (so a hash map can trust them).
7. **Why bother.** A reviewer (or an AI assistant) can see that a change
   made a function start doing I/O; a team can keep allocation out of a
   hot loop; the optimizer can remove or reorder calls it knows are pure.
   Keep it concrete, one short example each.

## Errors to show

- `effect`: a `#[no_alloc]` function that allocates (real output).
- `effect`: a `#[pure]` function that prints.
- An effect bound on a closure broken at the call.
- `contract.effect` is chapter 13's; mention only.

## Asides

- If you know Rust: there is nothing like this in Rust; the closest is
  `const fn` (much narrower) or `#![no_std]` (per crate).
- If you know Haskell or Koka: effects here are inferred and checked as
  upper bounds; there are no effect handlers.

## Sources

`volec guide effects`, docs/design/effects-allocation.md,
examples/effects (pure-and-no-alloc, effect-bounds, trait-purity,
effects-for-agents).
