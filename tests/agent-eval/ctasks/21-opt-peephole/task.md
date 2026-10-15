# Combine shifts of shifts

At -O2 the optimizer leaves a shift of a shift by constants as two
instructions. `tachyonc --emit-ir -O2` on

    fn f(x: u32) -> u32 { (x << 3) << 4 }

shows a `shl` by 3 and a `shl` by 4; it should be one `shl` by 7. Add
this rule to the optimizer's instruction combining (compiler/src/middle/,
see docs/optimizer.md):

- `(x << c1) << c2` and `(x >> c1) >> c2`, with `c1`, `c2` constants and
  both shifts of one direction and the same type, become one shift of `x`
  (or a constant) — for every integer type, i8 to u64, signed and
  unsigned.
- The result must be exactly what the program computes at -O0 for every
  input. The language's shift semantics are in docs/grammar.md
  ("Defined"): an amount is taken modulo 64 for 64-bit operands and
  modulo 32 for narrower ones (which are shifted as 32-bit values and
  then truncated); a negative amount is a large one; `>>` is arithmetic
  on signed types and logical on unsigned ones. Mind what happens when
  the two amounts together reach the type's width.
- A shift whose amount is not a constant, or a pair of different
  directions or types (`(x << 4) >> 4`, a shift of a cast), may stay as
  it is but must still compute the right result.

Acceptance:

- the compiler builds (`bootstrap/eval-build.sh`, the fixpoint);
- add a test `tests/run/<name>.tach` of your own whose `// CHECK:` /
  `// CHECK-NOT:` lines show the rule firing in the -O2 IR and whose
  `// EXPECT:` lines show the right results (the directives are
  described at the top of tests/run.sh; tests/run/opt_egraph.tach is an
  example);
- `tests/run.sh opt_`, `tests/run.sh arith_` and
  `tests/run.sh algorithms` pass, and your test passes. Hidden tests of
  the same kind (CHECKs on the IR of such shifts at several widths and
  signednesses, and their results for edge-case inputs) are run too.
