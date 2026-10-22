# Appendix A: keywords, operators and attributes

> **Status: outline.** This file is the plan for the appendix. Replace it
> with the appendix, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

A quick-reference page a reader keeps open while writing code. Tables,
each row with a one-line meaning and the chapter that teaches it. Not a
grammar: link docs/grammar.md for the precise rules.

## Contents

1. **Keywords.** `fn struct enum union impl trait type const static
   var let inout sink mod use pub crate self Self super import extern
   unsafe if else match loop while for in break continue return defer
   as true false requires ensures debug distinct` (check the list
   against docs/grammar.md's lexical section and the tokenizer before
   publishing); one line each, and which are only special in one
   place (`result` and `old` in contracts, `invariant` in a distinct
   type).
2. **Operators and precedence.** Arithmetic, bitwise (`~` for not,
   `<<` `>>`), comparison, logical (`!` on bool only), assignment forms
   (`+=` ...), `as`, `..` and `..=` (in `for` and slices), `?`, `&` at a
   call (marks inout), `*` (raw pointers only). The precedence table
   from `volec guide syntax#expressions-and-precedence`.
3. **Literals.** Integer forms and suffixes, floats, `'a'`, strings and
   their escapes, `c"..."`, `b"..."` (check), f-strings and specs.
4. **Attributes.** `#[derive(..)]`, `#[repr(..)]`, `#[test]`,
   `#[property]`, `#[fuzz]`, `#[cfg(test)]`, `#[pure]`, `#[no_alloc]`,
   `#[no_io]`, `#[no_panic]`, `#[effects(..)]`, `#[inline]`, `#[cold]`,
   `#[thread_local]`, `#[target_feature]`, `#[multiversion]`,
   `#[views]`, `#[link]`, `#[link_name]`, `#[sealed]` (std only).
5. **The prelude.** Every name available without `use`.

A test block at the end (one program using most operators, with its
`out`) keeps the precedence table honest.

## Sources

docs/grammar.md, `volec guide syntax`, `guide formatting`, `guide
modules` (the prelude).
