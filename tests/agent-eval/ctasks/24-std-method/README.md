# 24-std-method: `std::strip_prefix` and `std::strip_suffix`

**The change.** A small std addition: two free functions next to `trim`
in std's "Text" section (`compiler/std/io.vl`),
`strip_prefix(s: [u8], prefix: [u8]) -> Option<[u8]>` and
`strip_suffix(s: [u8], suffix: [u8]) -> Option<[u8]>` (a view of `s`
without the prefix/suffix, `None` when it is not there), with a test case
and an entry in the guide's std topic.

**Why it is realistic.** std's text helpers cover trimming, splitting and
parsing but not this; it is the usual first std contribution. The work is
small but touches the whole std pipeline an engineer has to discover:
std's source is embedded in the compiler (`compiler/std/embed.sh` makes
`compiler/src/front/stdsrc.vl`, and its section index, which `tests/run.sh`
checks for staleness), the guide too (`compiler/guide/embed.sh` makes
`compiler/src/guide/text/`), and the compiler must be rebuilt before a test
sees either. Slice-of-bytes helpers were chosen because 0.16's effects and
allocators change std's containers (Vec, HashMap), not borrowed-text
functions.

**The grading** (`ctasks.grade`, about 3 to 4 minutes on an M-series Mac,
most of it the guide filter):

1. the hidden cases are copied in: `hidden/tests/run/eval_std_strip_prefix.vl`
   (matches, empty prefix/suffix, the whole text, a longer one, mismatch
   at the last/first byte, repeats like `"aaa"`/`"aa"`, empty texts, by
   path and by import, chained) and `eval_std_strip_view.vl` (the result
   is a view: a later `Vec::set` shows through it; bytes 254/255; a Buf's
   text; the whole text gives an empty slice);
2. the fixpoint build (a build failure fails everything);
3. suite filters `eval_std_strip` (the hidden cases, a few seconds),
   `std` (17 std cases plus the agent's own if named `std_*`; `tests/run.sh`
   also fails when `stdsrc.vl` is stale) and `guide` (every guide example
   compiled and run, the embedded guide fresh; about 2 to 3 minutes,
   mostly idle: its per-example watchdogs);
4. `grade.sh`: `compiler/guide/std.md` names both functions outside the
   generated `@STD-API@` listing (that listing names them by itself, so
   `volec guide std | grep` alone would prove nothing), a ```` ```tach ````
   block of it calls one of them, `volec guide std` prints both, and a
   case in `tests/run/` other than `eval_std_strip_*` uses each function
   and passes (`tests/run.sh NAME`).

The starter (the base, unchanged) fails at step 3 (the hidden cases do not
compile) and at step 4.

**The reference solution** (`solution.patch`): the two functions after
`trim` in `compiler/std/io.vl` (a length check, a byte loop, a subslice),
`compiler/std/embed.sh` rerun, a paragraph and an example in
`compiler/guide/std.md` (its "Input" section), `compiler/guide/embed.sh`
rerun, and `tests/run/std_text_strip.vl`.

**At v0.16.0, if a patch does not apply** (0.16 moves the compiler's source
to `?`, derive and interpolation, and may reshape std): there is no
starter. Remake `solution.patch` in a scratch tree of v0.16.0 by hand:
add the two functions to std's text section (wherever `trim` lives then),
run `compiler/std/embed.sh` (it regenerates `compiler/src/front/stdsrc.vl`
and its section index; the patch must include that file), add the
paragraph and example to `compiler/guide/std.md`, run
`compiler/guide/embed.sh` (it regenerates `compiler/src/guide/text/t_std.vl`;
include it), add `tests/run/std_text_strip.vl`, then
`git diff HEAD -- compiler tests/run/std_text_strip.vl > solution.patch`.
Never hand-edit the generated files: the build and `tests/run.sh` check
them against their sources. If 0.16 adds a `strip_prefix` of its own (or
makes std text a `str` type), the task must change its names. Check the
hidden cases still compile (std's import syntax, `Option` matching, `f""`
are 0.15 features) and `tests/agent-eval/run.py check-tasks --set compiler
24-std-method`.
