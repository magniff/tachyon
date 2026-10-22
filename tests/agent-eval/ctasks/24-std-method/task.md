# Add `strip_prefix` and `strip_suffix` to std

std has text helpers for `[u8]` (`trim`, `split`, `split_whitespace`,
`parse_int`; see `target/volec guide std`) but nothing to take a known
prefix or suffix off a text, so programs write the loop themselves. Add
two public functions to std, next to `trim`:

```
pub fn strip_prefix(s: [u8], prefix: [u8]) -> Option<[u8]>
pub fn strip_suffix(s: [u8], suffix: [u8]) -> Option<[u8]>
```

- `strip_prefix(s, prefix)`: when the first `prefix.len` bytes of `s`
  are `prefix`, `Some` of the rest of `s` (the bytes after them);
  otherwise `None`. `strip_suffix(s, suffix)`: the same at the end:
  `Some` of `s` without its last `suffix.len` bytes when they are
  `suffix`, otherwise `None`.
- The result is a view of `s` (a subslice, like `trim`'s), not a copy:
  nothing is allocated and nothing needs freeing.
- Edge cases: an empty prefix/suffix gives `Some(s)`; `s` equal to the
  prefix/suffix gives `Some("")` (an empty slice); a prefix/suffix longer
  than `s` gives `None` (never an out-of-bounds panic); an empty `s` with
  an empty prefix is `Some("")`. Bytes are compared exactly (no case
  folding, any byte value 0..255).
- They are free functions of the module `std`, usable as
  `std::strip_prefix(...)` and by import, `use std::{strip_prefix,
  strip_suffix};`, from any program, at every optimization level.

std's source is `compiler/std/`, and it is built into the compiler (read
the header of `compiler/std/embed.sh` and `compiler/src/front/README.md`
for how, and what to run after changing it). The guide is
`compiler/guide/*.md`, likewise built in (`compiler/src/guide/README.md`).

Acceptance:

1. The two functions, exactly as above, in std.
2. A test case of your own in `tests/run/` (see the directives at the top
   of `tests/run.sh`; name it e.g. `std_...vl`, not `eval_...`, a
   prefix reserved for the grader's own cases) that calls both functions,
   covers the edge cases above, and passes.
3. An entry in the guide's `std` topic (`compiler/guide/std.md`, the
   hand-written part, not only the API listing that is generated from
   std's source): a sentence or two on what they do and a ```` ```tach ````
   example calling them, with its ```` ```out ```` block, so that
   `target/volec guide std` shows it.
4. After rebuilding the compiler, these pass: `tests/run.sh std` and
   `tests/run.sh guide` (it compiles and runs every guide example; it
   takes a couple of minutes).
