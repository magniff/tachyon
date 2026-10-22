# 6. Errors: Option, Result and panics

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

Handle failure deliberately. By the end the reader can:

- choose between `Option` (something may be absent) and `Result`
  (something may fail) and design an error enum;
- use `match`, `unwrap_or`, `map`, `and_then`, `ok_or`, `map_err`;
- propagate errors with `?`, converting them with `impl From`;
- write `fn main() -> Result<(), E>`;
- tell a panic (a bug, or a broken promise) from an error (expected);
- read the one-line run-time failure and its exit status 101;
- use `assert`, `assert_eq` and a first `requires` as documentation that
  is checked.

## Running example

A settings file parser: lines like `port = 8080` and `name = vole`.
`fn parse_line(s: str) -> Result<Setting, ConfigError>`, an enum
`ConfigError { MissingEquals(i64), BadNumber(ParseIntError), Unknown(str)
}`, a `load(text: str) -> Result<Config, ConfigError>` built with `?`,
and a `main` that reports the error (first by matching, then by
returning `Result`). Input from `in` blocks: one good file, one bad.

## Sections

1. **Absence: Option.** `Some`/`None`, `HashMap::get`, `str::find`;
   `match`, `if let`, `unwrap_or`, `?` on Option.
2. **Failure: Result.** `Ok`/`Err`; std's errors (`ParseIntError`,
   `io::Error`); making your own error enum. Option means absent, Result
   means failed: std follows this everywhere.
3. **The ? operator.** What it does, step by step; only in a function
   returning a compatible `Option` or `Result`; `defer` and drops still
   run.
4. **Converting errors.** `impl From<ParseIntError> for ConfigError`, so
   `?` converts. `map_err` when there is no impl. `ok_or` to turn an
   Option into a Result.
5. **main returning Result.** `#[derive(Debug)]` on the error; the
   program prints `Error: ...` and exits with 1. Show it with `out
   exit=1`.
6. **Panics.** `unwrap` on `Err`, an index out of bounds, `panic("..")`,
   `unreachable()`. The failure line `FILE:LINE:COL: message` and exit
   101. Why a panic is not undefined behaviour. When to panic (a bug,
   a broken invariant) and when to return an error (bad input). `--trace`
   prints the calls that led there (show it).
7. **Checks as documentation.** `assert(cond, "msg")`, `assert_eq(a,
   b)`; a first `requires` clause on a function (`requires port > 0
   else "port must be positive"`), with its failure line naming the
   caller's line. Point to chapter 13 for contracts in full.

## Errors to show

- `?` in a function returning `()` (check the message).
- `?` on a `Result<_, ParseIntError>` in a function returning
  `Result<_, ConfigError>` without a `From` impl.
- Run-time: `called unwrap on Err`, a `requires` failure line, `assert`
  failure with its values (`main.vl:4:5: k is small: k = 3`).

## Asides

- If you know Rust: the same `?`, `From`, `main -> Result`; `panic(..)`
  is a function; `assert!` also works but `assert(..)` is the vole
  spelling; integers never panic on overflow.
- If you know Go: `?` is `if err != nil { return err }`, typed.
- If you know Python or Java: there are no exceptions; failures are
  values, and `?` makes passing them on short.

## Sources

`volec guide conversions` (?, From, main -> Result, std's errors),
`guide contracts#assertions`, `guide errors#at-run-time`,
examples/errors-and-results.
