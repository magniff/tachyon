# 5. Structs, enums and pattern matching

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

Model data with types of your own. By the end the reader can:

- define structs, build them (including the field shorthand), read and
  change fields, compare them with `==`;
- add methods and associated functions with `impl`;
- define enums whose variants carry data, by position or by name;
- use `match` with every kind of pattern vole has, and `if let`,
  `while let`, `let ... else`;
- explain why `match` must be exhaustive, and use that to their
  advantage when adding a variant.

## Running example

A tiny text adventure's command parser and state:
`enum Direction { North, South, East, West }`, `enum Command {
Go(Direction), Take { item: str }, Look, Quit }`, `struct Player { room:
i64, moves: i64 }` with methods `apply(inout self, c: Command)`. Input
comes from an `in` block so the game is testable.

## Sections

1. **Structs.** Declaration, literal, field access, `p.x = 3` on a
   `var`. Shorthand `Point { x, y }`. Structs are compared field by field
   with `==`. A struct of plain fields is plain (copied); one with a
   `Vec` is owned (moves): tie back to chapter 4.
2. **Methods.** `impl Player { fn new() -> Player; fn describe(self);
   fn step(inout self); }`. `Self`. Associated functions called
   `Type::f()`. Several `impl` blocks are fine.
3. **Enums.** Fieldless variants; variants with positional data
   `Go(Direction)`; with named fields `Take { item: str }`. `use
   Command::{Go, Look};` to drop the prefix.
4. **match.** Arms, `_`, binding names, nested patterns, `|`, ranges
   `1..=9`, guards `n if n % 5 == 0`. `match` is an expression. Strings
   are not patterns: `if s == "north"` instead (say why briefly, and that
   it may change).
5. **Exhaustiveness.** Leave an arm out: show the error with the
   missing variant named and its `try:` that writes the arm. Then add a
   variant (`Drop { item: str }`) and watch the compiler list every
   `match` to update. Mention `volec refactor variant` adds arms
   everywhere (chapter 17).
6. **if let, while let, let else.** For one interesting case.
7. **Enums as numbers.** `#[repr(u8)] enum Level { Low = 1, ... }`, `as`
   both ways, the checked conversion back (exit 101 on a bad number).
8. **Option, briefly.** `Option<T>` is just an enum: `Some(x)`/`None`;
   matching it. Chapter 6 continues.
9. **Printing your types.** `#[derive(Debug)]` and `{p:?}` (formatting
   is chapter 7 and traits chapter 9; here only the derive).

## Errors to show

- `non-exhaustive match: 'Command::Quit' is not covered` (check the real
  wording), with its `try:`.
- A missing field in a struct literal.
- Calling an `inout self` method on a temporary or a let binding, if the
  compiler refuses it by then (see chapter 4's note).
- A bad `as` to an enum at run time (`out exit=101`).

## Asides

- If you know Rust: the same, minus `x @ pat`, slice patterns and
  string patterns; variant fields are read through patterns only.
- If you know C or Go: enums carry data (tagged unions); `match` checks
  every case.

## Sources

`volec guide language#structs-enums-match-methods`, `guide syntax`
(patterns), `guide types#enums-as-integers`, `guide formatting#derive`.
