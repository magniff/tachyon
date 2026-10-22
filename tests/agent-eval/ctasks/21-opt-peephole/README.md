# 21-opt-peephole: combine shifts of shifts

**The change.** At -O2, `(x << c1) << c2` and `(x >> c1) >> c2` (constant
amounts, one direction, one type) stay two instructions: neither
instruction combining (`middle/fold/mod.vl`, `combine`) nor the e-graph
rules (`middle/egraph.vl`) merge them. The agent adds the rule. It is a
real peephole every optimizer has (LLVM's InstCombine does it), small (the
reference is 18 lines in `combine`), and easy to get subtly wrong:
vole's shift amounts are taken modulo 64 (64-bit) or 32 (narrower
types, shifted as 32-bit values and truncated), a negative amount is a
large one, and when the amounts together reach the width the answer is 0
for `<<` and logical `>>` but a shift by width - 1 for arithmetic `>>`.
Adding the raw constants, or reducing the sum modulo the width, or treating
signed and unsigned `>>` alike, each gives wrong results.

**Grading** (`ctasks.grade`):

1. `hidden/tests/run/eval_peephole_shifts.vl` is copied over the tree;
   the compiler is built with the fixpoint (it compiles itself with the
   rule).
2. `suite`: `eval_peephole` (the hidden test: 16 `#[inline(never)]`
   functions over u8/i8/i16/u16/u32/i32/u64/i64; CHECK/CHECK-NOT on the
   -O2 IR that each pair became one shift by the expected amount (5, 13,
   6, 16, 5, 31, 63, 63) or no shift (0 results); EXPECT lines from -O0
   for negative, maximal and wrapping inputs, plus pairs that must not be
   merged: `(x << 4) >> 4`, a shift of a cast, a variable amount),
   `opt_` (52 optimizer tests), `arith_` (14), `algorithms` (10).
3. `grade.sh`: the agent's own test: some new `tests/run/*.vl` (not
   in the starter, not `eval_peephole_*`) with `// CHECK` lines, which
   passes under `tests/run.sh`.

Checked by hand: six wrong variants of the reference (raw constant sum,
sum without the width check, raw sum with the check, logical `>>` clamped
like arithmetic, arithmetic `>>` folded to 0, signedness swapped) all
build with the fixpoint and all fail the hidden test.

**Reference** (`solution.patch`, no starter): in `combine`, after the
zero-amount identities, when `a` is the same shift of the same type by a
constant, sum both amounts through `shift_amount`; at or past
`int_bits(ty)` make the constant 0 (left, unsigned) or clamp to
`bits - 1` (signed right); otherwise shift `a`'s operand by the sum. Plus
`tests/run/opt_shift_chains.vl` and a phrase in docs/optimizer.md.

**Time.** Grading takes about 1.5 min (build ~10 s, the suite ~50 s,
grade.sh ~5 s) on an M-series Mac.

**If the patches do not apply at v0.16.0.** 0.16 moves the compiler
source to `?`, derive and interpolation, so `combine` in
`compiler/src/middle/fold/mod.vl` may read differently. Re-make the
reference: in a tree of v0.16.0, add the same rule at the same place in
`combine` (after `if (op == Shl || op == Shr) && shift_amount(c, ty) == 0`),
copy `tests/run/opt_shift_chains.vl` from this patch, and
`git diff > solution.patch`. Check that the rule is still missing at
v0.16.0 (`volec --emit-ir -O2` on `(x << 3) << 4` shows two `shl`) and
that the hidden test still fails there. The hidden test's CHECKs on the
results that fold to 0 rely on those functions keeping a `y * 5` term (so
IPO does not delete them); if a v0.16.0 pass changes that, adjust the
CHECKs to the IR at the reference.
