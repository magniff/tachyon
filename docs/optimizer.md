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
| `-O2` (default) | `-O1`, then per function in call-graph order (callees first): tail recursion elimination, inlining, the loop optimizer (0.4: rotation, induction variables and unrolling, value ranges, strength reduction and unswitching, aggressive DCE) and loop-invariant code motion, each followed by the `-O1` pipeline again; functions left without callers are not emitted |

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
  for the calling convention. An aggregate result in registers (0.5) is
  `piece k` instructions after its call (defined by the call, in the
  result registers), stored into the result's slot.
- **Terminators**: `jump`, `branch` on a bool, `ret` with an optional value
  (for an aggregate returned in registers, a `pack` of its pieces, loaded
  from the value), `unreachable`, and
  `switch` on an integer: case values with their blocks and a default;
  its distinct successors are listed once, and each has the switch block
  once among its predecessors.
- **Calls follow the callee's convention** (C's, or tachyon's: see
  "Calling conventions"): an aggregate argument passed in registers is
  split by the lowering into its scalar pieces (one `load` each, so the
  optimizer sees through the round trip), and a parameter's pieces are
  separate `param`s (`imm2` = piece + 1) stored into a slot; larger
  aggregates go by reference or as a copy on the stack (`41_abi.tach`).
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

**Layout and liveness** (`50_regalloc.tach`). Critical edges (from a block
with several successors to one with several predecessors) are split, so
that every edge has a place for its moves. Blocks are laid out in reverse
post-order; back edges (to a block not later in the order: the graph is
reducible) give each block its loop depth. Positions go 4 apart: block k
starts at BSTART[k], where its phis and parameters are defined; the
instruction at p reads its operands at p, clobbers registers at p + 1 and
writes its result at p + 2; p - 1 is the gap before it, where moves go;
the terminator reads at BEND[k]. Liveness is the usual backward data flow
on bit sets.

**Intervals.** A value's lifetime is a list of ranges with holes, and its
uses with what each needs: a register (operands of most instructions), or
anywhere (call arguments, phi operands, returned values: the emitter moves
them into place). Operands taken as immediates and frame addresses used by
loads and stores are not uses. Constants and addresses (`const`, `slot`,
`gaddr`, `saddr`, `faddr`) get an interval only when some use needs them
in a register; on the stack they are rematerialized, so they cost no
store and no slot. Registers clobbered by calls (all caller-saved ones),
and on x86-64 rax and rdx around a division and rcx around a shift by a
register, are fixed intervals.

**Linear scan with interval splitting** (C. Wimmer and H. Mössenböck,
*Optimized Interval Splitting in a Linear Scan Register Allocator*, VEE
2005; C. Wimmer and M. Franz, *Linear Scan Register Allocation on SSA
Form*, CGO 2010). Intervals are taken by start; the active and inactive
(in a hole) ones hold registers. An interval gets a register free for its
whole lifetime when there is one, its hint first: the register of the
phi it flows into (or for a phi, of the phi it flows into, else of an
operand), following a partner not yet allocated to its own partner; else
the argument or result register it goes to. Else the register free
longest, for a first part, and the rest is split off. When none is free,
the register whose holders' next use is farthest is taken from them (they
go to the stack until just before that use), unless the interval's own
first use is farther still: then it goes to the stack until then.
Distances count uses in loops as nearer (by 4 per level of depth) and
constants as cheap to bring back. Splits that bring a value back into a
register move to the start of the outermost block between the last and
the next use when it is less deep in loops, so reloads leave loops.

**Spilling.** A value that goes to the stack anywhere is stored once,
right after its definition (the phi moves write a phi there directly when
it starts on the stack), so a split to the stack costs nothing and one
back costs a load. Spill slots are shared by values whose lifetimes, from
definition to last use, do not overlap.

**Resolution.** A split inside a block where the value lives on is a move
in the gap at the split. On each edge, the values live into the successor
and its phis go from where they are at the end of the predecessor to where
they are at the start of the successor: one parallel move, at the end of
the predecessor when it has one successor, else at the start of the
successor (which then has one predecessor). Moves to the stack are no
moves (the value is there since its definition).

**Checking** (`--verify-regalloc`). The checker simulates the allocation
over the control flow graph: the contents of every register and spill
slot, through the moves (planned by the same functions the emitter uses),
definitions, stores and clobbers, meeting at joins (a location whose
predecessors disagree holds nothing), until nothing changes; every use
must find its value where the allocation says it is. `--print-regalloc`
shows the blocks' positions and every value's intervals and locations.

| | AArch64 | x86-64 |
|---|---|---|
| allocated, caller-saved | x0-x15, d0-d7, d16-d29 | rax, rcx, rdx, rsi, rdi, r8, r9, xmm0-xmm13 |
| allocated, callee-saved | x19-x28, d8-d15 | rbx, r12-r15 |
| temporaries inside an instruction | x16, x17, d30, d31 | r10, r11, xmm14, xmm15 |
| parallel moves | x16 (temporary, indirect callee), x17 (cycles), d30, d31 | r11 (temporary, indirect callee), r10 (cycles), xmm14, xmm15 |

**Switches** become a jump table when they have at least 4 cases filling at
least a third of their range (up to 4096 entries): 32-bit offsets from the
table, so the code is position independent on ELF too; otherwise a binary
search of compares and branches.

**Emission** (`51_emit.tach`). The frame is addressed from sp, which does
not move in the body: outgoing stack arguments, spill slots, saved
callee-saved registers, then the frame slots. Locations depend on the
position: an instruction reads its operands where the allocation has them
at its position and writes its result where it has it two later. Before
each instruction come the moves of its gap; at the start and end of each
block, those of its edges (phi moves among them); calls put their
arguments in place with the same parallel-move resolver (stack arguments
first, then registers, cycles broken through a temporary). The function's
entry moves the parameters from where the caller put them; narrow
integers from C callers are normalized. A leaf function (no call, nothing
on the stack, no parameter on the stack) has no frame at all. At -O2, a
call whose result is returned at once, to a callee taking no stack
argument, is a sibling call: the frame goes, then a jump (not in
functions using frame slots, whose addresses the callee could hold).
Immediate forms are used where the target has them (add/sub, shifts,
logical immediates on AArch64, 32-bit immediates on x86-64, compare with
an immediate, `cbz` and `cbnz`); division by a constant other than 0 and
-1 skips the checks on x86-64.

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

## 0.4: the loop optimizer

0.4 adds a loop optimizer to `-O2`, run per function after inlining and
before LICM (`optimize_loops` in `46_opt.tach`; light cleanups between
its passes, the `-O1` pipeline once after them). Tail recursion
elimination runs before inlining (`49_tre.tach`). The passes, in
pipeline order:

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
5. **Unrolling**: full unrolling of loops with a small constant trip count
   (up to 16 trips and 160 instructions); partial unrolling (by 4 or 2) of
   innermost loops with a constant trip count (found up to 4096) that the
   factor divides, up to 96 instructions. All copies are made from the
   untouched loop, then chained.
6. **Loop strength reduction** (`49_lsr.tach`): an address affine in an
   induction variable (`k + c1*b1 + c2*b2 + (s + m*v)*i`, all 64-bit,
   `b1`, `b2`, `v` invariant) that costs a multiplication or a shift
   becomes a pointer induction variable; addresses a constant apart share
   one pointer, the difference folded into the access's offset. Up to 4
   pointers per loop. matmul's inner loop is two loads, a multiply and an
   add per element.
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
11. **Tail recursion elimination** (`49_tre.tach`): `return f(args)`,
    `return f(args) op y` and `return y op f(args)` (op one of `+ * & | ^`
    on integers, nothing with an effect after the call) become a loop with
    a phi per parameter and one for the accumulator; returns through a phi
    block are first moved into its predecessors. Functions with frame
    slots or aggregate parameters are left alone.

Instruction combining now reassociates `(x + c1) + c2` at every integer
type (both sums of one type wrap alike), which unrolled induction
variables need.

Costs: the compiler (22,800 lines) compiles itself at `-O2` in about 1.75
times the CPU time of 0.3.0 (300 ms against 170 ms on Apple silicon);
`-O1` is unchanged. Per-block arrays are kept from call to call (one per
call would cost the whole program's size each time), and loops are
rotated in one sweep, innermost first.

Bugs found on the way (all by the checks below, before they shipped): an
exit value taken from the wrong phi (the first match kept a stale flag),
unrolled copies cloned from an already rewired loop, header phis of the
inner loop rotated after the outer one's updater added to them, and the
header phis' own operands skipped when rewriting a rotated header's
uses.

Tested by IR `CHECK` tests (`tests/run/opt_loops.tach`,
`opt_ranges.tach`, `opt_loop_transforms.tach`), the suite at every level,
the fixpoint (the compiler itself is the largest loop test) and the loop
mode of the random program generator (`tests/fuzz/run.sh -l`: counted
loops with bounds from expressions, while loops of every integer type up,
down and to an exact end, `break` and `continue`, slices indexed one past
the end now and then, chains of equality tests; the exit status is
compared too).

## 0.5: the back end, stage A

The plan, in order of priority:

1. A register allocator with live-range splitting and coalescing, in place
   of 0.2's single-hull linear scan: linear scan on SSA form with lifetime
   holes and interval splitting (above). The alternative, a backtracking
   allocator over live-range bundles as in regalloc2, finds better
   assignments under pressure, but linear scan with splitting gets most of
   it for a fraction of the code and compile time, and keeps allocation
   one pass. Acceptance: collatz's loop-carried value in one register (no
   move in its loop), sieve's bound kept in a register instead of
   rebuilt every iteration.
2. A tachyon calling convention for plain `fn`s (more argument registers,
   aggregates of up to four registers passed and returned in registers),
   `extern "C"` staying exactly C. Safe per optimization level: a program
   is compiled at one level, -O0 (the oracle) keeps C's convention, and
   plain `fn` pointers only ever reach plain functions of the same
   program.
3. Frames: leaf functions without a frame; realigned frames for
   `#[repr(C, align(N))]` above 16 at every level; sibling calls.

Done: 1, and from 3 leaf frames and sibling calls. Stage A frees every
register the old emitter kept as operand and result scratch (operands
needing a register always get one), which gives AArch64 9 more integer
and 8 more float registers and x86-64 3 more integer and 2 more float
ones; the machine layer of x86-64 now uses only r10 and r11 inside
instructions (rax and rdx stay fixed for division, rcx for shifts).

Moved to stage B: the calling convention (2), which needs the lowering of
calls and parameters to classify aggregates by convention (classification
lives in `45_lower.tach` and `41_abi.tach`, shared with C's), and the
realigned frames (from 3), which touch the -O0 generator too. Both are done
(stage B1, below).

## Calling conventions

Plain `fn`s compiled at -O1 and -O2 call each other with tachyon's own
convention; C's is kept by everything C can reach or call: functions
imported from C or defined `extern "C"`, `main` (called by C), variadic
functions, calls through `extern "C" fn` pointers, the run-time helpers,
and every function at -O0, the oracle (`fn_uses_c`, `fn_type_uses_c` in
`41_abi.tach`).

The two never meet. A program is compiled at one level, and a plain `fn`
value only ever holds a plain function of the same program: `fn` and
`extern "C" fn` do not convert into each other, also not through statics or
generic instances (they are type-checked the same way). `main` is the one
plain function following C's convention whose value can be taken; for a
`main` taking scalars that fit in C's argument registers and returning a
scalar, as C's `main` does, the two conventions agree, because tachyon's
puts the first scalars where C's does.

**Arguments.** Every argument is a list of scalars, assigned one by one to
the next free register of its class, else to the next 8-byte slot of the
stack area:

| | AArch64 | x86-64 |
|---|---|---|
| int registers | x0-x15 | rdi, rsi, rdx, rcx, r8, r9, rax |
| float registers | d0-d7, d16-d23 | xmm0-xmm13 |
| result registers | x0-x3, d0-d3 | rax, rdx, rcx, rsi, xmm0-xmm3 |
| result pointer | first int argument | first int argument |

(The temporaries the parallel moves and indirect calls use, x16/x17 and
r10/r11, are never arguments.) An aggregate of at most four scalar leaves
that do not overlap is its leaves (a struct of three `f64` is three float
registers, `{u8, i64, f32, bool}` four registers of their own types); one
with overlapping leaves (an enum with fields, a union) or more leaves, of
at most 32 bytes, is its 8-byte chunks, read as integers; a larger one is
a pointer to the caller's private copy. Since leaves are passed with their
own types, scalar replacement takes an aggregate parameter or argument
apart completely.

**Results.** An aggregate of up to four pieces comes back in the result
registers: as IR, the callee's `ret` takes a `pack` of the pieces, and the
caller gets `piece` instructions defined by the call; scalar replacement
then removes the slot on both sides. A larger one goes through a result
pointer, passed as the first argument (and, unlike C on x86-64, not
returned).

**Frames aligned above 16.** Types may be aligned up to 4096
(`#[repr(C, align(N))]`). At -O1/-O2 the frame is addressed from sp, so the
prologue rounds sp down to the largest alignment a slot or a stack argument
needs (the epilogue restores sp from the frame pointer; incoming stack
arguments are reached from the frame pointer). At -O0, whose slots are
reached from the frame pointer, such a slot gets room to be rounded up in
and its address is rounded at run time (also for the address of a field of
it: `slot - field`); a call copying such an aggregate onto the stack (x86-64)
first moves the pushed arguments down so that the stack area is aligned,
and sp comes back from a frame slot after the call. On x86-64 an aggregate
copied onto the stack starts at a multiple of its alignment, as clang and
GCC place it; on AArch64 an aggregate aligned above 16 is larger than 16
bytes and goes by reference anyway.

Testing: `tests/run/conv_tachyon.tach` (20 integer and 20 float arguments,
aggregates of every shape in both directions, fn pointers, recursion,
generic instances, registers running out), `align_over16` (locals, arrays,
nested and 4096-aligned values, statics, parameters and results, C by value
and by pointer in both directions), the random program generator's calls
mode (`tests/fuzz/run.sh -C`), and the ABI fuzzer's structs aligned to 16,
32 or 64 in all three modes.

Testing: `--verify-regalloc` over the suite, the fuzzers and the compiler
itself in every gate run; `tests/run.sh` checks `// ASM(T):` and
`// ASM-NOT(T):` directives against the assembly for target T
(`opt_regalloc_coalesce`, `opt_leaf_frame`, `opt_tail_call`);
`opt_regalloc_pressure` keeps more values live than there are registers;
the random program generator has a pressure mode (`tests/fuzz/run.sh -p`:
up to 10 parameters, 12 to 25 locals all live to the end).

## 0.5: the back end, stage B (instruction selection and layout)

The plan was, in order of priority: instruction selection by rules, block
layout, post-allocation peepholes, unrolling with run-time trip counts,
scheduling, shrink-wrapping. Done: the first three, and of scheduling the
two rules that paid off; the rest is below.

**Instruction selection** (`50_isel.tach`) runs between the optimizer and
register allocation, after `--emit-ir` (so the optimizer's IR checks are
unaffected; `--emit-mir` shows the IR after it). Per function:

1. *Branches on phis.* A block holding only a phi and a branch on it (what
   `&&`, `||` and a `bool` from an `if` leave) is threaded: each
   predecessor that jumps there branches itself on its own value for the
   phi (a comparison it made, which then fuses with the branch), or jumps
   where a constant leads. A branch on the condition its only
   predecessor branched on is decided by the edge.
2. *Selects.* A diamond or triangle whose arms hold at most two cheap pure
   instructions each (no division, no float conversion), and four in all
   with the selects, meeting in a block whose phis (at most two that
   differ) pick between the arms' values, becomes the arms' instructions,
   moved up (speculated: they cannot trap), and a `select` per phi. A
   select owns its comparison (two extra operands, as a phi's or a call's;
   the right one may be an immediate), so nothing can come between the
   comparison and its use of the flags: on x86-64 a rematerialized 0 is
   an `xorl`. AArch64: `csel`, `fcsel`, `csinc` for `c ? a : b + 1` (and
   `c ? a + 1 : b`, with the condition inverted, for integer comparisons
   and tests: the negation of a float comparison is not the opposite
   comparison), `xzr` for a 0; x86-64: `cmov` (integers only; the value
   replaced is hinted to the select's register). A select comparing what
   the select before it compared reuses its flags (on x86-64 only when
   nothing was emitted between them).
3. *Tiling* by maximal munch, each block's instructions from the last to
   the first so that a user is matched before what it uses. A rule
   matches a root and the definitions of some of its operands, each in the
   same block and used by the root alone, and rewrites the root in place
   into a machine operation whose operands are the leaves; use counts are
   kept as rules go, and what was covered dies (dead code elimination
   after). The machine operations are IR instructions like the others, so
   liveness, the allocator and its checker need no special case:

   | operation | meaning | made from |
   |---|---|---|
   | `loadx`, `storex` | access at `a + (b << s) + off` | load/store of `a + (b << s)` or `a + b`; AArch64: `s` the access size or 0, no offset; x86-64: `s` up to 3, any offset, a frame slot as the base (from `%rsp`) |
   | `lea` (x86-64) | `a + (b << s) + off`, 64-bit | `a + (b << s)`, `a + b`, `a ± k`, `x * {3,5,9} + k`, `(x + y) + k` |
   | `madd`, `msub` (AArch64) | `c ± a * b` | `c + a * b`, `c - a * b` (not by 3, 5 or 9: those are one shifted add already) |
   | `shop` (AArch64) | `a op (b sh k)`, op `+ - & \| ^`, sh `lsl lsr asr` | an operation and a shift by a constant |
   | `ubfx` (AArch64) | `(a >> k) & (2^n - 1)` | the same, the field within the type |
   | `test` | `(a & b) == 0` or `!= 0`, fused with a branch | a branch on `(x & m) == 0`; `tbz`/`tbnz` for one bit (in functions small enough for their 32 KB reach) |
   | `select` | above | selects on `(x & m) ==/!= 0` test |
   | `fmath` | `sqrt`, `fabs`, `floor`, `ceil`, `trunc`, `round` | calls of the C library's functions of those names and C signatures (and the `f32` ones): `sqrt` on macOS only (Darwin's libm never sets errno, glibc's does), the others on AArch64 (x86-64 has them from SSE4.1 only) |

   Integer arithmetic wraps and every machine operation normalizes its
   result to its type once, so fusing integer operations is exact; floats
   are never fused (no `fmadd`: one rounding per operation).
4. *Scheduling*, two rules: a branch's comparison (used by the branch
   alone) moves to the end of its block, where it fuses with the branch
   (loop strength reduction leaves increments after it); constants defined
   in loops move to the entry block (at most 16 per function), so that one
   needed in a register (a store's value, a float) is made once; the
   allocator rematerializes it, before the loop, when it runs short.

**Block layout** (`51_layout.tach`). The emission order is apart from the
allocation order (any order is correct: every move belongs to a block or
an edge, and a block's code depends on its positions only). Chains by
fall-through (Pettis and Hansen, PLDI 1990, with static estimates): a
block's frequency is 8^(loop depth); a branch sends 63/64 away from a cold
successor (one that only leads to a panic or `unreachable`), 7/8 along a
back edge or within its loop, else half each way; the heaviest edges join
the chain ending at their source to the one starting at their target. The
entry's chain first, then the others by allocation order, cold ones last.

**Tail duplication** at emission: a jump to a block of at most three
instructions without a call, ending in a jump, a branch or a return,
emits a copy of the block instead, up to two deep (the copy falls through
to what follows the block it ends). In an interpreter, each handler then
ends in its own dispatch test (threaded dispatch); a loop entered by a
jump to its test gets the test at its end (rotation by layout). A return
from a block that is not the last emits the epilogue when it restores at
most four registers, and the shared epilogue is emitted only when
something jumps or falls to it.

**Post-allocation peepholes**: `stp`/`ldp` save and restore callee-saved
registers in pairs; a move back to where a value just came from is
dropped; a load of the stack slot just stored to is a move from the
register stored; an interval whose partner's register (its hint) is taken
tries the argument or result register it goes to before any other.

Also fixed on the way: two constants needed by one instruction (a
select's arms) took each other's register forever, a constant counting as
cheap to evict even when the very next instruction needs it; a constant
needed there is now as near as any other value.

Not done: unrolling with run-time trip counts (moved to 0.8, whose loop
vectorizer needs the same remainder loop), a general list scheduler (on
the out-of-order cores tachyon targets, the two rules above are what
mattered in `bench/`; moved to 0.9, where profiles tell which blocks are
worth it), shrink-wrapping (moved to 0.6, with interprocedural attribute
inference: its gain is in small functions with early returns that are
not inlined).

## Not yet

Planned in [roadmap.md](roadmap.md): induction variable narrowing, a
tachyon calling convention of its own, realigned frames (0.5, stage B);
interprocedural analyses, a cost-model-driven inliner and shrink-wrapping
(0.6); an e-graph-based rewriter (0.7); vectorization and unrolling with
run-time trip counts (0.8); profile-guided scheduling (0.9).
