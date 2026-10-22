# 3. Values, types, functions and control flow

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

The building blocks every program uses, at a steady pace. By the end
the reader can:

- declare variables with `let` and `var`, and shadow a name;
- pick a numeric type, write literals with suffixes, convert with `as`,
  and say what happens on overflow and division by zero;
- use `bool`, tuples, arrays and the unit type `()`;
- write functions with parameters, a result type, default and named
  arguments;
- use blocks as expressions, `if` as an expression, `while`, `for` over
  ranges, `loop` with a value, labelled `break`;
- write comments, and constants (`const`).

Not here: strings beyond literals (chapter 7), `Vec` (chapter 7),
parameter conventions beyond the default (chapter 4).

## Running example

A small unit converter that grows through the chapter:
`celsius_to_fahrenheit`, a table printed with a `for` loop, then a
"how many years until my savings double" loop with `while`, then a
prime counter that uses a labelled `break`. Each step a complete
program with `out`.

## Sections

1. **Variables.** `let` (cannot change), `var` (can). Shadowing: `let x
   = x + 1;` makes a new variable. Every variable is initialized when
   declared; there is no "declare now, assign later".
2. **Numbers.** `i64` is the default integer; `i8`..`i64`, `u8`..`u64`,
   `isize`, `usize`; `f64` default float, `f32`. Literals: `1_000`,
   `0xff`, `0b1010`, `3u32`, `2.5f32`. `as` converts; widening (`i32`
   into an `i64` place) is implicit, narrowing is not.
   - Defined behaviour: integers wrap, `x / 0 == 0`, `x % 0 == x`,
     float to int saturates. Show one `out` block with these (types
     guide has a ready one). Explain *why*: no undefined behaviour,
     the same answer at every optimization level.
   - Lengths and indexes are `i64`, not an unsigned type.
   - No methods on numbers (`x.abs()` does not exist): write it.
   - `i64::MAX`, `u8::MIN`.
3. **Other simple types.** `bool` and `!` (only on bool; `~x` is bitwise
   not), `'a'` is a `u8` (vole has no `char` type yet: say it plainly,
   "pre-1.0"), tuples `(1, "two")` and `t.0`, arrays `[0; 8]` and
   `[1, 2, 3]` with checked indexing, `()`.
4. **Functions.** `fn name(a: i64, b: i64) -> i64`; the last expression
   is the result; `return` early. Default arguments `b: i64 = 2` and
   named arguments `f(1, b: 3)`. Functions are declared at the top
   level only (no nested functions); order doesn't matter.
5. **Expressions and blocks.** A block's value is its last expression
   (no `;`). `if` is an expression (`let kind = if n < 0 { .. } else {
   .. };`). The classic mistake: a stray `;` turns the value into `()`.
6. **Loops.** `while`; `for i in 0..10` and `0..=9` (ranges); `(0..n).rev()`;
   `loop` with `break value`; labels `outer: for ...` and `break :outer`
   (note the spelling differs from Rust's `'outer`).
7. **Comments and constants.** `//`, `/* */` (nest), `const N: i64 =
   10;`. Mention `static var` exists and is rarely what you want (chapter
   14 explains why threads forbid it).

## Errors to show

- `cannot assign to immutable variable` (let then `+=`), with its
  `help: make it mutable: var x`.
- A type mismatch: `let x: i32 = 5; let y: i64 = 7; let z: i32 = x + y;`
  (the narrowing error and its `as` fix); show the real message.
- A literal that doesn't fit: `let b: u8 = 300;`.
- The stray-semicolon mistake: a function ending in `x + 1;` whose
  result type is `i64`.
- An index out of bounds at run time: `out exit=101` with
  `main.vl:L:C: index out of bounds: index 4, length 4`.

## Asides

- If you know Rust: `var` is `let mut`; labels are `name:` and `break
  :name`; overflow never panics; `x / 0` is 0; `usize` is not used for
  lengths.
- If you know C: no undefined behaviour on overflow or shifts; no
  implicit narrowing; arrays are values (copied by `=`).

## Sources

`volec guide language` (values, functions), `guide types` (numbers and
their defined behaviour, arrays), `guide syntax` (precedence, control
flow), `guide conversions#widening`, docs/grammar.md.
