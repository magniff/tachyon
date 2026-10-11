# The optimizer

How the tachyon compiler optimizes, since release 0.2: the IR, its
invariants, the passes and the pipeline at each level, the back end, and
how all of it is tested. This is the living design document of the middle
and back end; later releases extend it (see [roadmap.md](roadmap.md)).

The code: `compiler/src/44_ir.tach` (IR), `45_lower.tach` (AST to SSA),
`46_opt.tach` (CFG cleanups, dominators, dead code, the pipeline),
`47_fold.tach` (folding, SCCP, instruction combining), `48_gvn.tach`
(value numbering, alias analysis, memory forwarding, dead stores),
`48_sroa.tach` (scalar replacement, constant tables), `49_licm.tach`,
`49_inline.tach`, `50_regalloc.tach` (linear scan), `51_emit.tach`
(emission), `52_mc_arm64.tach` and `53_mc_x86_64.tach` (instructions).

## Optimization levels

| flag | pipeline |
|---|---|
| `-O0` | the 0.1 code generator (`40_gen.tach`), unchanged: stack-machine code straight from the AST |
| `-O1` | lowering to SSA; per function, twice: SCCP, instruction combining, (the first time) scalar replacement of aggregates and constant tables, CFG simplification, GVN with memory forwarding and dead stores, dead code elimination, CFG simplification; linear-scan register allocation |
| `-O2` (default) | `-O1`, then inlining bottom-up over the call graph and loop-invariant code motion, each followed by the `-O1` pipeline again; functions left without callers are not emitted |

`-O0` stays as an independent oracle: it shares only the front end with
the other levels, so a miscompile in the middle or back end shows up as a
difference (see "Testing"). `-O2` is the default because compile time stays
small: the compiler (about 14,000 lines) compiles itself in 13 ms at `-O0`
and 90 ms at `-O2` on Apple silicon.

Debugging flags: `--emit-ir` writes the optimized IR instead of assembly,
`--verify-ir` checks the IR after every pass, `--print-after-all` prints
every function after every pass (on stderr).

## The IR

A function is a control flow graph of basic blocks. Instructions compute
typed scalar values in SSA form; memory is explicit.

- **Values** are instruction ids (`INSTS`). Types are the checker's scalar
  types (`i8` ... `u64`, `f32`, `f64`, `bool`); pointers, function values
  and the addresses of compound values (structs, tuples, arrays) are `u64`.
- **Integers are canonical**: kept sign- or zero-extended to 64 bits, as in
  the 0.1 code generator. Every integer operation is a 64-bit operation
  followed by a normalization to its result type, so values of different
  widths can be mixed freely in address arithmetic.
- **Compound values live in memory**: frame slots (`SLOTS`, addressed by
  `slot`), statics (`gaddr`) or memory reached through pointers. A compound
  expression's value is its address; `copy` moves bytes (calls `memcpy`
  above 128 bytes).
- **Instructions**: `const`, `param`, `slot`, `gaddr` (a static), `saddr` (a
  string literal), `faddr` (a function), `phi`, the arithmetic and bitwise
  operators, `neg`, `not`, `bnot`, `cmp` (the operand type is recorded for
  signedness and floats), `conv` (from and to type), `load` and `store`
  (address plus constant offset), `copy`, and the calls `call` (direct),
  `calli` (through a value) and `callc` (a C library function: `fmod`,
  `memcpy`). Calls keep the type of each argument as the callee sees it,
  for the C calling convention.
- **Terminators**: `jump`, `branch` on a bool, `ret` with an optional value
  (for an aggregate returned in registers, its address), `unreachable`, and
  `switch` on an integer: case values with their blocks and a default;
  its distinct successors are listed once, and each has the switch block
  once among its predecessors.
- **Calls follow C's convention** for every function: an aggregate
  argument passed in registers is split by the lowering into its scalar
  pieces (one `load` each, so the optimizer sees through the round trip),
  and a parameter's pieces are separate `param`s (`imm2` = piece + 1)
  stored into a slot; larger aggregates go by reference or as a copy on
  the stack (`41_abi.tach`).
- **Replacement** is lazy: `ir_replace(v, w)` records that `v` now stands
  for `w` (and unlinks `v`); `ir_val` follows such records, and passes
  resolve operands before they look at them.

Invariants (checked by `--verify-ir` after every pass):

- every block ends in a terminator; successor and predecessor lists agree;
- phis come first in their block and have one operand per predecessor, in
  the order of the predecessor list;
- every operand is a live instruction of the same function, defined before
  its use in the same block or in a block that dominates the use (for a
  phi operand: dominates the end of the corresponding predecessor);
- operands are resolved (no replaced instruction is referenced).

**Construction** (`45_lower.tach`) follows Braun et al., *Simple and
Efficient Construction of Static Single Assignment Form* (CC 2013),
directly from the checked AST. Scalar locals whose address is never taken
are SSA variables; the others get frame slots. The values of `if`, `&&`,
`||`, `loop` with `break` values, and loop counters are synthetic SSA
variables. Blocks are sealed as soon as all their predecessors are known,
which structured control flow makes obvious. Semantics follow `-O0`
exactly: evaluation order, the calling convention (compound arguments are
passed as a pointer to a private copy, compound results through a result
pointer) and every arithmetic rule.

## Passes

| pass | algorithm | file |
|---|---|---|
| cleanup | unreachable-block removal; trivial-phi removal (a phi whose operands are one value is that value), to a fixpoint | `46_opt` |
| SCCP | Wegman & Zadeck, *Constant Propagation with Conditional Branches* (TOPLAS 1991): a lattice per value, executable edges, two work lists; constant values and decided branches are rewritten | `47_fold` |
| folding | what the machine computes: wrapping arithmetic at every width, `x / 0 == 0`, `x % 0 == x`, `MIN / -1 == MIN`, shift amounts modulo 32 (types up to 32 bits) or 64, IEEE comparisons, the saturating float-to-integer conversions of `-O0` (including its quirks: up to 32-bit signed targets saturate at 32 bits and wrap) | `47_fold` |
| instruction combining | constants on the right; identities (`x + 0`, `x * 1`, `x & 0`, `x - x`, `x ^ x`, `x & x`, double negation, `b != false`); `x * 2^k` to a shift; unsigned division and remainder by `2^k` to a shift and a mask; signed division by `2^k` with the rounding fix-up (`(x + ((x >> 63) >>> (64 - k))) >> k`) and remainder from it; reassociation of constant address offsets and their folding into loads and stores; comparisons with the constant on the left mirrored; a branch on `!x` swapped | `47_fold` |
| CFG simplification | branches on constants and branches with one target become jumps; a block merges into its only predecessor when that predecessor jumps to it; jumps through empty blocks are threaded (when the target has no phis) | `46_opt` |
| dominators | Cooper, Harvey & Kennedy, *A Simple, Fast Dominance Algorithm*, over a reverse post-order | `46_opt` |
| GVN | a walk of the dominator tree with a scoped hash table (undo log, so scopes are popped in constant time per entry) over the pure instructions; commutative operands in a canonical order | `48_gvn` |
| alias analysis | an address is a base plus a constant offset; it points into a memory object (a frame slot, a static, constant data) through additions of constant or variable offsets, or into unknown memory; distinct objects never overlap; constant data is never written; a slot whose address only serves loads, stores, copies (memcpy calls included) and address arithmetic is private: no pointer from elsewhere and no call reaches it; within one object, byte ranges are compared when both offsets are known. No type-based rule: tachyon allows casts between any pointers | `48_gvn` |
| dead code elimination | mark from instructions with side effects and the terminators, sweep the rest | `46_opt` |
| LICM | natural loops from back edges (`h` dominates `t`); a preheader for each loop (the entering edge is split when needed); pure instructions whose operands are defined outside the loop move to the preheader, innermost loops first, and so do loads from frame slots and statics that nothing in the loop may write. Nothing moved can trap (division never traps in tachyon) | `49_licm` |
| SROA | a frame slot of a struct, tuple, enum, slice, small array or scalar whose address serves only loads, stores and copies at constant offsets becomes one SSA variable per scalar leaf of its type, by Braun et al.'s construction over the existing CFG (blocks in reverse post-order, sealed once their predecessors are filled); copies move leaf by leaf, to or from memory when the other side stays there. The values of `if`, `match` and `loop` of up to 128 bytes are built in one slot each exit copies into, so they are replaced too | `48_sroa` |
| constant tables | a private slot written only by stores of constants at known offsets, in one block that comes before every read, becomes read-only data; loads from read-only data (and string literals) at known offsets become constants | `48_sroa`, `48_gvn` |
| memory forwarding | along the dominator tree: what a block knows about memory (location to value) goes to a block it dominates when that one's only predecessor is it, or after the writes of every block on the paths between them are applied; loads of known locations are their values; storing what a location holds is dropped; a load from the destination of a copy that still holds reads its source (and the copy may then die) | `48_gvn` |
| dead stores | within a block, a store (or a copy) overwritten before anything may read it; a store or copy into a private slot that nothing reads | `48_gvn` |
| switches | a `match` on an integer, a fieldless enum or an enum's tag whose arms are literals, ranges, alternatives of them, or variants whose fields only bind (and no guards), is a `switch`; SCCP decides switches on constants and prunes them to their reachable successor | `45_lower`, `47_fold`, `46_opt` |
| inlining | strongly connected components of the call graph (Tarjan), callees first, so a callee is already optimized and recursion is never inlined; a callee is inlined when it has at most 30 instructions, or when this is its only call site and it has at most 400 (and is neither `main` nor address-taken); callers grow to at most 3,000 instructions. The callee's blocks are copied, parameters become the arguments, frame slots are copied, returns jump to a continuation block with a phi for the result | `49_inline` |

The pipeline (`optimize_program` in `46_opt.tach`) runs the cleanup on
every function, then the `-O1` pipeline twice per function, then at `-O2`
inlining and LICM in call-graph order, each followed by the `-O1`
pipeline, and finally drops functions nobody calls (other than `main` and
those whose address is taken).

## The back end

**Layout and liveness** (`50_regalloc.tach`). Edges from a block with two
successors into a block with phis are split. Blocks are laid out in reverse
post-order; every instruction gets a position. Liveness is the usual
backward data flow on bit sets; a value's live interval is the hull of
every position where it is live (one range per value; holes are ignored).

**Linear scan** (Poletto & Sarkar, *Linear Scan Register Allocation*,
TOPLAS 1999). Intervals are allocated in order of their start. A value live
across a call gets a callee-saved register; others prefer caller-saved
ones. When no register is free, the interval that ends last is spilled
(the current one, or an active one whose register it then takes). A value
that feeds a phi (and a phi itself) first tries the register of its phi
partner, transitively through chains of phis, which removes most phi
moves. Constants and addresses (`const`, `slot`, `gaddr`, `saddr`,
`faddr`) are never allocated: they are rematerialized at each use. A
compare used only by the branch right after it is fused into that branch.

| | AArch64 | x86-64 |
|---|---|---|
| allocated, caller-saved | x9-x15, d16-d29 | rsi, rdi, r8, r9, xmm2-xmm13 |
| allocated, callee-saved | x19-x28, d8-d15 | rbx, r12-r15 |
| operand scratch | x0-x2, d0-d1 | r10, r11, xmm0-xmm1 |
| result scratch | x3, d2 | rax, xmm0 |
| temporaries inside an instruction | x4-x7, x16, x17, d3-d7 | rax, rcx, rdx, xmm14, xmm15 |
| parallel moves | x16 (temporary), x17 (cycles), d30, d31 | r11 (temporary), r10 (cycles), xmm14, xmm15 |

**Switches** become a jump table when they have at least 4 cases filling at
least a third of their range (up to 4096 entries): 32-bit offsets from the
table, so the code is position independent on ELF too; otherwise a binary
search of compares and branches.

**Emission** (`51_emit.tach`). The frame is addressed from sp, which does
not move in the body: outgoing stack arguments, spill slots, saved
callee-saved registers, then the frame slots. Phis become parallel moves at
the end of each predecessor; calls put their arguments in place with the
same resolver (stack arguments first, then registers, cycles broken through
a scratch register). The function's entry moves the parameters from where
the caller put them; narrow integers from C callers are normalized. Frame
slots are addressed from sp directly by loads and stores. Immediate forms
are used where the target has them (add/sub, shifts, logical immediates on
AArch64, 32-bit immediates on x86-64, compare with an immediate, `cbz` and
`cbnz`); division by a constant other than 0 and -1 skips the checks on
x86-64.

## Testing

- **Differential testing.** The golden suite (`tests/run.sh`) passes at
  `-O0`, `-O1` and `-O2` (`-O LEVEL`) on every target: aarch64-macos,
  x86_64-macos (Rosetta) and x86_64-linux (`bootstrap/linux-check.sh
  --all-levels`).
- **Random programs.** `tests/fuzz/gen.awk` writes random programs over
  every integer width with arithmetic, shifts, comparisons, casts, branches,
  bounded loops, arrays, pointers and calls, and (since 0.3, off in seed
  mode) structs passed by value, enums, `match` on integers and enums with
  ranges, alternatives and guards, methods and slices; `tests/fuzz/run.sh` compiles
  each at every level (with `--verify-ir`) and compares the output. With
  `-s SEED` the seed is a third oracle (divisors are then made non-zero,
  since the seed traps on division by zero).
- **C interoperability.** `tests/abi/gen.awk` writes a C file and a
  tachyon file that call each other with random signatures (scalars of
  every width, `#[repr(C)]` structs, unions and enums, packed and aligned
  ones, more arguments than registers, every kind of result, variadic
  calls); every value is checked on the other side. `tests/abi/run.sh` runs
  them at every level.
- **IR tests.** Test cases with `// CHECK: text` and `// CHECK-NOT: text`
  are matched against `--emit-ir` (FileCheck's rules: CHECKs in order,
  CHECK-NOTs between them; `// CHECK-OPT: n` picks the level). The
  `tests/run/opt_*.tach` cases cover each pass, and their folding edge
  cases (overflow, division by zero, NaN, shifts, conversions) are checked
  against `-O0` at run time too.
- **Fixpoint.** At the default level, the compiler compiles itself to
  byte-identical assembly, on every host, and the assembly for a target
  does not depend on the host.

## What 0.3 did

0.3 (aggregates and memory) added, besides the language of
[grammar.md](grammar.md) (enums and `match`, methods, slices, C
interop):

- the C calling convention for aggregates on both targets (and in the
  `-O0` generator), checked against C by `tests/abi/run.sh`: random
  signatures of scalars, `#[repr(C)]` structs (nested, with arrays, packed,
  aligned), unions and enums, called from tachyon to C and from C to
  tachyon (by name and through pointers), with results of every kind and
  variadic calls;
- SROA, constant tables, the alias analysis above, memory forwarding along
  the dominator tree, copies read through, dead store elimination;
- the `switch` terminator, `match` lowered to it, jump tables and binary
  searches;
- bugs found on the way: a reassociation of `(x + c1) + c2` across
  different integer widths (an old one, exposed by SROA), and a nested
  `match` overwriting the switch state of the one it is in.

## 0.4: loops (the plan)

0.4 adds a loop optimizer to `-O2`, run per function after inlining and
before LICM, then again after it. The passes, in pipeline order:

1. **Loop analysis and canonical form** (`49_loop.tach`): the loop forest
   (natural loops by header, nesting, depth); every loop gets a preheader
   (one block entering the header, ending in a jump), a single latch (one
   back edge) and dedicated exits (exit blocks entered only from inside the
   loop). LCSSA: a value defined in a loop and used outside goes through a
   phi in the exit block. Two utilities serve the transformations: an SSA
   updater (the definitions of a value in several blocks; a use reads the
   one that reaches it, with phis inserted where they meet: Braun et al.'s
   construction over the finished CFG) and the cloning of a region of
   blocks.
2. **Loop rotation**: a `while` loop (exit test in the header) becomes a
   guarded `do`-`while` (the test duplicated in the preheader, the exit
   test at the latch): one branch per iteration instead of two, and the
   body known to run at least once.
3. **Induction variables and trip counts** (`49_scev.tach`): add
   recurrences `{start, +, step}` of header phis; for a loop whose only
   exit is at the latch, the trip count when it is a constant (by
   evaluating the exit test with the folding rules, so wrapping is exactly
   the machine's) and the exit values of induction variables for counted
   loops `i < n` / `i != n` (an expression computed in the preheader); a
   loop is finite when its exit test is such a counted test.
4. **Dead loop deletion**: a finite loop without side effects whose results
   are only its exit values is removed.
5. **Unrolling**: full unrolling of loops with a small constant trip count;
   partial unrolling (by 2 or 4) of loops with a constant trip count that
   the factor divides, under a size budget.
6. **Loop strength reduction**: an address `base + i * stride` (a shift or
   a multiplication of an induction variable) inside a loop becomes a
   pointer induction variable.
7. **Unswitching**: a branch on a loop-invariant condition inside a small
   loop: the loop is cloned, one copy per outcome, the test hoisted.
8. **Value ranges and bounds checks** (`49_range.tach`): the range of an
   integer value at a block, from its type, its operation (masks,
   remainders, conversions), induction variables, and the branch conditions
   that dominate the block; with it, bounds checks of slices whose index is
   proven in range are removed (the check `i < len` is implied by a
   dominating `i < n` with `n` the same length, and `i >= 0`), comparisons
   decided by ranges are folded, and a branch whose outcome is implied by a
   dominating condition on the edge into its block is threaded past.
   Jump threading on implied conditions turns the arm-by-arm tests of a
   `match` with guards into a decision tree.
9. **Comparison chains**: `x == c1` / `x == c2` / ... tests of one value in
   a chain of blocks become a `switch`.
10. **Aggressive dead code elimination** (`46_adce.tach`): over control
    dependence (post-dominators), branches that decide nothing live are
    removed; branches of loops are kept (a loop may not terminate: only
    the loop deletion above removes loops, when they are finite).

Tested by IR `CHECK` tests per pass, the suite at every level, the fixpoint
(the compiler itself is the largest loop test) and a loop mode of the random
program generator (nested counted loops with varied bounds, steps,
signedness and early exits, slices indexed in and out of bounds).

## Not yet

Planned in [roadmap.md](roadmap.md): chains of comparisons of one value
turned into switches, aggressive dead code elimination, loop
canonicalization, induction variables, unrolling, range analysis and
bounds-check elimination (0.4); live-range splitting and coalescing in the
register allocator, rule-based instruction selection, scheduling, a
tachyon calling convention of its own (0.5); interprocedural analyses and a
cost-model-driven inliner (0.6); an e-graph-based rewriter (0.7);
vectorization (0.8).
