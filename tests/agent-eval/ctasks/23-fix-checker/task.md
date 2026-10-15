# Bug: a `match` whose integer ranges cover every value is "non-exhaustive"

A user reports:

> I wrote a UTF-8 lead-byte classifier with one arm per byte range:
>
> ```
> fn utf8_len(lead: u8) -> i64 {
>     match lead {
>         0..=127 => 1,
>         128..=191 => 0,
>         192..=223 => 2,
>         224..=239 => 3,
>         240..=255 => 4,
>     }
> }
> ```
>
> The arms cover 0 to 255, every `u8`, but `tachyonc` rejects it:
>
> ```
> error[type error] non-exhaustive match: '_' is not covered | help: add an arm for it, or a wildcard arm '_ =>'
> ```
>
> It names no missing value, because there is none. An `enum` or `bool`
> match without a wildcard is fine. If I add a `_ => 0` arm to get past
> the error, the compiler accepts it, but it does not report that arm as
> unreachable. It does report an unreachable arm in other matches.

`tests/run/eval_regress_ranges.tach` reproduces it (`tests/run.sh
eval_regress` fails now). The compiler's match checking is in
`compiler/src/front/patterns/`.

Fix the compiler so that:

- a `match` on an integer (any width, signed or unsigned, also inside a
  tuple or an enum variant's fields) whose arms cover every value of the
  type is accepted without a wildcard arm;
- the rest of exhaustiveness and reachability checking works as before:
  a match that really misses a value is still rejected and names a
  missing value, and an arm that the arms above it already cover (a `_`
  after full coverage too) is still an "unreachable match arm" error.

Fix the compiler, not the test: the grader uses its own copy of
`tests/run/eval_regress_ranges.tach` and other programs of this kind. A
fix that only makes this one program compile does not pass. You may add
test cases of your own in `tests/run/`, named anything except `eval_*`.

Acceptance, after rebuilding with `bootstrap/eval-build.sh` (the build
must reach its fixpoint), all of these must pass:

    tests/run.sh eval_regress
    tests/run.sh match
    tests/run.sh pattern
