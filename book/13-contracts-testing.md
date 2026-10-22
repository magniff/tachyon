# 13. Contracts and testing

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

State what code promises, and check it. By the end the reader can:

- write `requires` and `ensures` clauses (with `result`, `old(..)` and
  an `else` message), and read their failure lines;
- know that contracts are checked in every build, and that the
  optimizer uses them (a `requires i < v.len()` removes the bounds check
  on `v[i]`);
- use `debug requires` for checks too costly for every build;
- write `#[test]` functions, `#[property]` tests with generated inputs,
  and `#[fuzz]` targets;
- run them with `volec test` and `volec fuzz`, read a failure, and
  replay it with its seed;
- test a whole program with `tests/NAME.in` and `tests/NAME.out`.

## Running example

A small sorted-set or ring-buffer type (`struct Ring { items: Vec<i64>,
start: i64 }`) with `push`, `pop` and `get(i)`, given contracts, then
tests: a few `#[test]`s, a `#[property]` ("pop after push gives the
value back"), a `#[fuzz]` target for a tiny parser of ring commands.
A deliberately planted off-by-one is found by the property and shrunk to
a small input.

## Sections

1. **requires.** Checked at each call, after the arguments; a failure
   names the *caller's* line, the one to fix. `else "message"` or an
   f-string. Show the failure line and exit 101.
2. **ensures.** Checked at every return; `result`, `old(e)`. What a
   condition may do (read, call pure functions; no I/O or allocation:
   `contract.effect`).
3. **Contracts and speed.** A check the compiler proved needn't run
   again: after `requires`, the bounds check is gone. `volec query
   checks FN` lists what's left (console). Integers wrap, so `i + 1 <
   len` doesn't prove what it looks like: one short example.
4. **debug requires/ensures.** For expensive checks (`is_sorted(v)`);
   run by `volec test` and `--debug-contracts`.
5. **#[test].** Next to the code; takes nothing or `gpa: Gpa`; returns
   `()` or a `Result`. `assert`, `assert_eq`. Tests run with
   `--check-alloc`, so a leak fails the test. `#[cfg(test)] mod tests;`.
6. **volec test.** Builds at -O0 and -O2 and compares them; the summary
   line, a failure with its trace; `volec test FILTER`. A function with
   an `ensures` is tested as a property automatically.
7. **#[property].** Parameters generated from their types; 100 cases;
   shrinking; the `try:` line with `--seed` to replay. `impl
   std::Arbitrary` for a type of your own.
8. **#[fuzz] and volec fuzz.** Coverage-guided mutation; a crash is
   shrunk, saved, and replayed by every later `volec test`.
9. **Program tests.** `tests/NAME.in` + `tests/NAME.out` next to
   `main.vl`, run by `volec test`; `--accept`.
10. **Snapshots.** `assert_snapshot(x)` in one paragraph.

## Errors to show

- A `requires` failure line naming the caller (`out exit=101`).
- An `ensures` failure line naming the function.
- `contract.effect` (a condition that allocates or prints).
- `test.signature` (a test that takes a parameter it can't have).
- A `volec test` session with one failing `#[test]` and one failing
  property, pasted from a console block (use `...` for timing lines if
  any).

## Asides

- If you know Rust: `#[test]` as you know it, proptest and cargo-fuzz
  built in; contracts are checked in release builds too.
- If you know Eiffel, Ada/SPARK or Dafny: contracts are run-time
  checks here, not proofs, but the optimizer uses what they establish.

## Sources

`volec guide contracts`, `guide testing`, `guide debug`,
docs/design/contracts-verification.md.
