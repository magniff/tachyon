# 23-fix-checker: integer ranges that cover the whole type are "non-exhaustive"

**The change.** `starter.patch` plants an off-by-one in the exhaustiveness
checker (`compiler/src/front/patterns/usefulness.vl`, Maranget's
usefulness algorithm). Integer columns are split into segments at the
arms' range boundaries (`int_segments`, start keys in `CUTS`).
`segment_end(i)` should return the inclusive end of segment `i`
(`CUTS[i + 1] - 1`). The starter returns the next segment's start
(`CUTS[i + 1]`). `ctor_count` uses it to decide whether the arms'
constructors cover the column's type (`complete`). With the bug, no
segment but the last is ever contained in an arm's range, so an integer
column is never complete:

- `find_missing` takes the default-matrix path. A match whose integer
  ranges cover the whole type, and that has no wildcard, is rejected with
  `non-exhaustive match: '_' is not covered` (or `'(false, _)'`,
  `'Option<u8>::Some(_)'` when the integer is nested).
- `useful` treats a wildcard arm after full coverage as reachable, so
  the "unreachable match arm" error is lost there.

It never makes a non-exhaustive match pass, so it cannot miscompile.
The starter also adds the failing regression test
`tests/run/eval_regress_ranges.vl` (a UTF-8 lead-byte classifier).

**Why it is realistic.** It is the exclusive/inclusive confusion a
cleanup introduces. Elsewhere `useful` and `find_missing` compute segment
ends inline (`MAT.data[cuts + c + 1] - 1`), and someone "simplifying" the
helper drops the `- 1`. The compiler still builds itself, since its own
integer matches all have a `_` arm. The full suite passes on the starter
except for the new test (772 cases, 0 failures before the test was
added): the suite has no exhaustive integer match without a wildcard.
Grepping the error message leads to `check_arms`, which is not where the
bug is. The agent has to follow `find_missing` → `ctor_count` →
`segment_end`, and learn what segments and `complete` mean, to find it.

**The grading** (`ctasks.grade`; about 1 minute on an M-series Mac):

1. `hidden/tests/run/` is copied in. The cases:
   - `eval_regress_ranges.vl`: the visible test, so editing or deleting
     it does not help.
   - `eval_regress_ranges_signed.vl`: exhaustive `i8`, `u16` (a `const`
     arm included), `i64` (from MIN to MAX in five arms) and `u64` (the
     top-bit keys) matches.
   - `eval_regress_ranges_nested.vl`: ranges inside a tuple
     `(bool, u8)`, `Option<u8>`, and enum variants with or-patterns.
   - `eval_regress_ranges_unreachable.vl`: a `_` after full `u8`
     coverage must still be "unreachable match arm". This fails on the
     starter and on a fix that only changes `find_missing`.
   - `eval_regress_ranges_missing.vl`: an `i8` match missing `-1`
     must still be rejected with `'-1' is not covered`. This guards
     against a fix that makes integer columns look complete wrongly, or
     that drops the error.
2. The fixpoint build. A build failure fails everything.
3. The suite filters `eval_regress` (the 5 cases above), `match` (the
   `err_match_*` cases: non-exhaustive enum, int, nested, guards,
   unreachable, float patterns, or-bindings, variant arity) and `pattern`
   (`match_patterns`, `let_patterns`).

The starter fails `eval_regress` (4 of the 5 cases). A fix that only
special-cases the visible program, for example by dropping the error
when the witness is `_`, still fails `_nested` (its witnesses are
`(false, _)` and `Some(_)`) and `_unreachable`.

**The reference solution** (`solution.patch`) restores the `- 1` in
`segment_end`. Shortcuts were checked by hand and fail:

- Dropping the error when the witness is `_` fails `_nested` and
  `_unreachable`.
- Treating integer columns as complete in `find_missing` only fails
  `_unreachable`, `_missing` and `err_match_nonexhaustive_int`.
- Forcing `complete` for integers in `ctor_count` makes the compiler
  crash (exit 139) on non-exhaustive integer matches. That fails
  `_missing` and `err_match_nonexhaustive_int`.

**At v0.16.0, if a patch does not apply** (0.16 moves the compiler's
source to `?`, derive and interpolation, so `usefulness.vl` may be
reformatted): make the starter again in a scratch tree of v0.16.0. Find
`segment_end` (`volec query show segment_end`), replace its
`CUTS.data[i + 1] - 1` with `CUTS.data[i + 1]` (`volec edit patch`),
add `hidden/tests/run/eval_regress_ranges.vl` as
`tests/run/eval_regress_ranges.vl`, commit, and use `git diff HEAD~1
HEAD` as `starter.patch`. `solution.patch` is the reverse of the
one-line change. Check that the starter still builds itself and passes
`tests/run.sh match`. If `segment_end` is gone (merged into its callers),
plant the same `- 1` removal in the end computation that decides
`complete`.
