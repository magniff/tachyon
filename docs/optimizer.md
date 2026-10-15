# The optimizer

How the tachyon compiler optimizes, since release 0.2: the IR, its
invariants, the passes and the pipeline at each level, the back end, and
how all of it is tested. This is the living design document of the middle
and back end; later releases extend it (see [roadmap.md](roadmap.md)).

The code (0.12: in folders, see compiler/README.md): the middle end in
`compiler/src/middle/`: `ir.tach` (IR), `lower.tach` (AST to SSA),
`opt.tach` (CFG cleanups, dominators, dead code, the pipeline),
`fold.tach` (folding, SCCP, instruction combining), `gvn.tach`
(value numbering, alias analysis, memory forwarding, dead stores),
`sroa.tach` (scalar replacement, constant tables), `licm.tach`,
`inline.tach` and the other passes; the back end in
`compiler/src/back/`: `isel.tach`, `regalloc.tach` (linear scan),
`emit.tach` (emission), `mc_arm64.tach` and `mc_x86_64.tach`
(instructions); `-O0`'s generator in `compiler/src/gen0/`.

## Optimization levels

| flag | pipeline |
|---|---|
| `-O0` | the 0.1 code generator (`gen.tach`), unchanged: stack-machine code straight from the AST |
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
  aggregates go by reference or as a copy on the stack (`abi.tach`).
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

**Construction** (`lower.tach`) follows Braun et al., *Simple and
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
| cleanup | unreachable-block removal; trivial-phi removal (a phi whose operands are one value is that value), to a fixpoint | `opt.tach` |
| SCCP | Wegman & Zadeck, *Constant Propagation with Conditional Branches* (TOPLAS 1991): a lattice per value, executable edges, two work lists; constant values and decided branches are rewritten | `fold.tach` |
| folding | what the machine computes: wrapping arithmetic at every width, `x / 0 == 0`, `x % 0 == x`, `MIN / -1 == MIN`, shift amounts modulo 32 (types up to 32 bits) or 64, IEEE comparisons, the saturating float-to-integer conversions of `-O0` (including its quirks: up to 32-bit signed targets saturate at 32 bits and wrap) | `fold.tach` |
| instruction combining | constants on the right; identities (`x + 0`, `x * 1`, `x & 0`, `x - x`, `x ^ x`, `x & x`, double negation, `b != false`); `x * 2^k` to a shift; unsigned division and remainder by `2^k` to a shift and a mask; signed division by `2^k` with the rounding fix-up (`(x + ((x >> 63) >>> (64 - k))) >> k`) and remainder from it; reassociation of constant address offsets and their folding into loads and stores; comparisons with the constant on the left mirrored; a branch on `!x` swapped | `fold.tach` |
| CFG simplification | branches on constants and branches with one target become jumps; a block merges into its only predecessor when that predecessor jumps to it; jumps through empty blocks are threaded (when the target has no phis) | `opt.tach` |
| dominators | Cooper, Harvey & Kennedy, *A Simple, Fast Dominance Algorithm*, over a reverse post-order | `opt.tach` |
| GVN | a walk of the dominator tree with a scoped hash table (undo log, so scopes are popped in constant time per entry) over the pure instructions; commutative operands in a canonical order | `gvn.tach` |
| alias analysis | an address is a base plus a constant offset; it points into a memory object (a frame slot, a static, constant data) through additions of constant or variable offsets, or into unknown memory; distinct objects never overlap; constant data is never written; a slot whose address only serves loads, stores, copies (memcpy calls included) and address arithmetic is private: no pointer from elsewhere and no call reaches it; within one object, byte ranges are compared when both offsets are known. No type-based rule: tachyon allows casts between any pointers | `gvn.tach` |
| dead code elimination | mark from instructions with side effects and the terminators, sweep the rest | `opt.tach` |
| LICM | natural loops from back edges (`h` dominates `t`); a preheader for each loop (the entering edge is split when needed); pure instructions whose operands are defined outside the loop move to the preheader, innermost loops first, and so do loads from frame slots and statics that nothing in the loop may write. Nothing moved can trap (division never traps in tachyon) | `licm.tach` |
| SROA | a frame slot of a struct, tuple, enum, slice, small array or scalar whose address serves only loads, stores and copies at constant offsets becomes one SSA variable per scalar leaf of its type, by Braun et al.'s construction over the existing CFG (blocks in reverse post-order, sealed once their predecessors are filled); copies move leaf by leaf, to or from memory when the other side stays there. The values of `if`, `match` and `loop` of up to 128 bytes are built in one slot each exit copies into, so they are replaced too | `sroa.tach` |
| constant tables | a private slot written only by stores of constants at known offsets, in one block that comes before every read, becomes read-only data; loads from read-only data (and string literals) at known offsets become constants | `sroa.tach`, `gvn.tach` |
| memory forwarding | along the dominator tree: what a block knows about memory (location to value) goes to a block it dominates when that one's only predecessor is it, or after the writes of every block on the paths between them are applied; loads of known locations are their values; storing what a location holds is dropped; a load from the destination of a copy that still holds reads its source (and the copy may then die) | `gvn.tach` |
| dead stores | within a block, a store (or a copy) overwritten before anything may read it; a store or copy into a private slot that nothing reads | `gvn.tach` |
| switches | a `match` on an integer, a fieldless enum or an enum's tag whose arms are literals, ranges, alternatives of them, or variants whose fields only bind (and no guards), is a `switch`; SCCP decides switches on constants and prunes them to their reachable successor | `lower.tach`, `fold.tach`, `opt.tach` |
| inlining | strongly connected components of the call graph (Tarjan), callees first, so a callee is already optimized and recursion is never inlined; a callee is inlined when it has at most 30 instructions, or when this is its only call site and it has at most 400 (and is neither `main` nor address-taken); callers grow to at most 3,000 instructions. The callee's blocks are copied, parameters become the arguments, frame slots are copied, returns jump to a continuation block with a phi for the result | `inline.tach` |
| copy elision (0.14) | a whole slot copied once (outside loops) into another slot or a field of one, the source used only before, the destination's part only after, neither escaping: the source is that part, the copy goes | `copies.tach` |
| threading on tags (0.14) | a switch on a phi, or a branch comparing one with a constant, whose operands are constants or phis: the block (or a chain of single-predecessor blocks from the phi's) is copied for each predecessor giving a constant, going to its outcome; uses repaired by the SSA updater | `tags.tach` |
| if-conversion (0.15) | in innermost loops, a branch whose ways meet again after at most 4 pure instructions: the instructions move up, the meeting block's phis become selects (`sel`) | `ifconv.tach` |
| exit merging (0.14) | several exits at a loop's top testing induction variables against invariants: one counter tested against the smallest trip count; header phis with one start and step merged | `exits.tach` |

The pipeline (`optimize_program` in `opt.tach`) runs the cleanup on
every function, then the `-O1` pipeline twice per function, then at `-O2`
inlining and LICM in call-graph order, each followed by the `-O1`
pipeline, and finally drops functions nobody calls (other than `main` and
those whose address is taken).

## The back end

**Layout and liveness** (`regalloc.tach`). Critical edges (from a block
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

**Emission** (`emit.tach`). The frame is addressed from sp, which does
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
before LICM (`optimize_loops` in `opt.tach`; light cleanups between
its passes, the `-O1` pipeline once after them). Tail recursion
elimination runs before inlining (`tre.tach`). The passes, in
pipeline order:

1. **Loop analysis and canonical form** (`loops.tach`): the loop forest
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
3. **Induction variables and trip counts** (`scev.tach`): add
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
6. **Loop strength reduction** (`lsr.tach`): an address affine in an
   induction variable (`k + c1*b1 + c2*b2 + (s + m*v)*i`, all 64-bit,
   `b1`, `b2`, `v` invariant) that costs a multiplication or a shift
   becomes a pointer induction variable; addresses a constant apart share
   one pointer, the difference folded into the access's offset. Up to 4
   pointers per loop. matmul's inner loop is two loads, a multiply and an
   add per element.
7. **Unswitching**: a branch on a loop-invariant condition inside a small
   loop: the loop is cloned, one copy per outcome, the test hoisted.
8. **Value ranges and bounds checks** (`range.tach`): the range of an
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
10. **Aggressive dead code elimination** (`adce.tach`): over control
    dependence (post-dominators), branches that decide nothing live are
    removed; branches of loops are kept (a loop may not terminate: only
    the loop deletion above removes loops, when they are finite).
11. **Tail recursion elimination** (`tre.tach`): `return f(args)`,
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
lives in `lower.tach` and `abi.tach`, shared with C's), and the
realigned frames (from 3), which touch the -O0 generator too. Both are done
(stage B1, below).

## Calling conventions

Plain `fn`s compiled at -O1 and -O2 call each other with tachyon's own
convention; C's is kept by everything C can reach or call: functions
imported from C or defined `extern "C"`, `main` (called by C), variadic
functions, calls through `extern "C" fn` pointers, the run-time helpers,
and every function at -O0, the oracle (`fn_uses_c`, `fn_type_uses_c` in
`abi.tach`).

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

**Instruction selection** (`isel.tach`) runs between the optimizer and
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

**Block layout** (`layout.tach`). The emission order is apart from the
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

## 0.6: the back end, polished

**Shrink-wrapping** (`emit.tach`). The frame (the saved frame pointer
and return address, the reserved area, the saved callee-saved registers)
is set up at the start of one block, SAVE: the nearest common dominator
of the blocks that need it, moved up the dominator tree out of loops. A
block needs the frame when it calls (other than a call ending a block
that does not return), refers to a frame slot, or has a value in a
callee-saved register or on the stack (`mark_frame_blocks` reads the
allocation's intervals; the predecessors of a block that starts with
such a value need it too, their edge moves write it). The blocks SAVE
dominates run with the frame; a jump out of them tears it down after the
edge's moves (with critical edges split only a block ending in a jump
leaves the region, and it is never skipped as a trivial jump); the
blocks outside run without one and return with a bare `ret`. No path
re-enters the region but through SAVE, which is in no loop: the frame is
set up and torn down at most once per call. A block outside that ends in
a call that does not return (a panic) links a frame of its own first
(x86-64 needs the stack aligned at a call). Functions calling setjmp and
the like, realigning their frame, or taking parameters on the stack keep
the frame at their entry.

The allocator makes room for it. A value of the entry block (a
parameter, mostly) that would take a callee-saved register for its whole
lifetime keeps a caller-saved one, its hint first, until just before
that register is needed elsewhere (a call, usually): at a block that is
in no loop and dominates the rest of the value's blocks (layout order is
not execution order: a loop run before the split point may be laid out
after it), and no block where the value lives before it can be reached
from it. The move into the callee-saved register costs what the entry
move did, on the paths that need the frame only. And out of loops, a
value that lives across no call does not follow its hint into a
callee-saved register (the move the hint saves runs once, the frame it
may force on a fast path every time).

**Coalescing hints.** A value flowing into a phi takes the phi's
register as its hint over the operand it is computed from: the phi's
saves a move on the edge (a loop's back edge, often), the operand's
nothing on AArch64 (three-operand instructions), and nothing on x86-64
either when the operation commutes or has one operand. A loop header's
phi takes its own hint from its back-edge value, not its initial one;
and when that value is not allocated yet and lives across a call, the
phi takes a callee-saved register, which the value can then share (the
phi itself may live across no call: a caller-saved register would cost a
move on every iteration). On x86-64 a select takes the register of an
operand used only by it, so the cmov needs no movq first.

**Instruction selection.** A comparison whose result is a value (not
fused into a branch) compares with an immediate when the constant fits,
on AArch64 with `cmn` for a small negative one, instead of holding the
constant in a register (often a callee-saved one, across a loop with
calls). A jump table over cases that start at 0 is indexed by the value
itself.

**`--stats`** prints totals of the machine code emitted on stderr
(`--stats=functions` also a line per function): instructions, register
moves, spill stores and reloads, moves on loop back edges, frame bytes,
functions with a frame, saved callee-saved registers. The compiler's own
source at the start of the work (0.6 phase 1), compiled by the compiler
before and after:

| | AArch64 before | after | x86-64 before | after |
|---|---|---|---|---|
| instructions | 203,020 | 197,385 (-2.8%) | 214,367 | 207,901 (-3.0%) |
| register moves | 25,845 | 25,270 (-2.2%) | 27,393 | 27,446 (+0.2%) |
| spill stores | 1,538 | 1,367 (-11%) | 4,205 | 3,952 (-6.0%) |
| reloads | 4,607 | 4,159 (-9.7%) | 10,708 | 10,145 (-5.3%) |
| moves on back edges | 2,984 | 2,653 (-11%) | 3,604 | 3,515 (-2.5%) |
| functions setting up a frame later than their entry | 0 | 81 of 655 | | |

(x86-64 counts the movq before a cmov as an instruction, not a register
move.) At run time: fib, whose base case no longer touches the stack, is
21% faster; the other benchmarks and the compiler itself are within
noise. Compile time: the compiler compiling the same source at -O2 is
within noise of before (+0.5%, best of 31 runs interleaved); -O0 does
not run any of it. The entry split checks only dominance (a block in no
loop reaches only later blocks of the layout), without searching the
graph, which cost 2.6%.

Found while reading the hot loops of `bench/`: interp's dispatch copied
its opcode before indexing its jump table (fixed above); interp keeps its
VM stack pointer in memory across iterations (scalar promotion: the
middle end); stencil keeps bounds checks whose proof needs the caller's
slice lengths (interprocedural, 0.6 2a); fib-like loops rotating two
values (`a, b = b, a + b`) need a three-move cycle on the back edge
(unrolling by two would rename them: 0.8 with run-time unrolling).

## 0.6: interprocedural optimization

The -O2 pipeline gains a whole-program layer (`ipo.tach`, `inline.tach`)
around the per-function passes. In order:

1. **Per function, -O1 pipeline** (as before): every function simplified
   on its own.
2. **Interprocedural constant propagation** (IPCP), over the call graph:
   a parameter (or one piece of an aggregate passed in pieces) that every
   direct call site passes the same constant is that constant in the
   callee; a function whose every `ret` returns the same constant has its
   call results replaced by it (the call stays, for its effects, until
   attributes show it has none). Only internal functions: not `main`,
   not `extern "C"` definitions, not address-taken (a function pointer
   may reach them from anywhere). Signatures do not change (dead argument
   *removal* would change the tachyon convention's register assignment
   per function; the arguments are simply no longer read, and the
   caller's computation of them dies when nothing else uses it).
3. **Bottom-up over the call graph's strongly connected components**
   (Tarjan; callees first), per function: tail recursion elimination,
   **inlining**, the loop passes, LICM and **scalar promotion**, each
   followed by the scalar pipeline; then the function's **attributes** are
   inferred (callees are done, so their attributes are known; a component
   of several functions is iterated optimistically to a fixed point).
4. **Global dead code elimination**: functions and generic instances no
   one reaches from `main`, the `extern "C"` definitions and the
   address-taken functions are not emitted. A function whose address the
   program takes stays, even when every call through the address was
   made direct and inlined (a function used as a value is part of what
   the program is; the IR and assembly tests rely on it).
   Before all of this (0.14, at -O1 and -O2), the functions of std that
   no function of the program reaches, through calls and addresses, are
   dropped (`drop_unreachable_std`): they are neither cleaned up nor
   optimized. std grew with 0.14 and every one of its non-generic
   functions is lowered; optimizing them was most of the time of
   compiling a small program (a 7-line program: 7 ms of CPU, now 3 ms;
   0.13: 2 ms). The program's own unused functions stay roots, as before.
   At -O2 the remaining std functions have fewer callers, which can change
   what is inlined (a `print_int` called once is inlined) and which
   arguments are constants; -O0 does not go through here.

**The inliner's cost model.** The cost of inlining callee g at a call
site is g's size (instructions that become code, after g was itself
optimized: bottom-up order), minus a bonus for each constant argument
whose parameter decides a branch, switch or division in g (10 each: the
copy will fold), minus the call's own cost (the argument moves, the
call, the result). The threshold is 30, doubled inside a loop and again
in a loop nest, 0 in a cold block (one that leads only to a panic or a
call of a `#[cold]` function). A function with a single call site that
is not address-taken or global is inlined up to 400 (it is then not
emitted). Never inlined: calls within one component (recursion), a
function that calls `setjmp` or the like (or into one), and calls past
the caller's size budget (3000) or the program's growth budget (the sum
of all sizes may grow by half, plus 2000). `#[inline]` inlines whenever
possible (no budget), `#[inline(never)]` never, `#[cold]` never and makes
its call sites cold (the inliner reads them through the front end's
`fn_attr_inline` and `fn_attr_cold`). Inlining iterates: after the inlined copies are
simplified (constants propagated into them), their own calls are
considered again, up to three rounds. Before each round, indirect calls
of a constant function address become direct calls (devirtualization),
so they can be inlined too.

**Function attributes** (`--print-attrs` prints them), inferred per
function from its instructions and its callees' attributes:

| attribute | meaning |
|---|---|
| `readnone` | reads and writes no memory but its own private frame slots |
| `readonly` | writes no memory but its private slots |
| `noreturn` | never returns (every path ends in a panic or a noreturn call) |
| `willreturn` | always returns: no loop, no recursion, only willreturn callees |
| `nopanic` | cannot panic or exit: no bounds check, no `as E` check, only nopanic callees |
| `nocapture(i)` | pointer parameter i is only dereferenced, compared or passed to nocapture parameters: it is not stored, returned or converted |

A C function (`extern "C"` import), an indirect call and a function that
calls one are unknown: none of these. The run-time panic is noreturn and
writes nothing a later instruction could see. Uses: a call of a
`readonly` function is not a memory barrier for load forwarding and
LICM (it writes nothing), and a `readnone` one does not end the dead
stores' search either (it reads nothing); a call of a `readnone`,
`willreturn`, `nopanic` function whose result is unused is removed (dead
code elimination, aggressive dead code elimination, dead loop deletion).
Value numbering of such calls (two with equal arguments are one) is left
for the e-graph of 0.7. In the compiler itself, of 1574 functions, 96 are
inferred readnone, 233 more readonly, 293 willreturn, and 111 have
nocapture parameters.

**Scalar promotion** (LLVM's "promote memory to register" in LICM): a
memory location accessed in a loop only by loads and stores of one type
at one loop-invariant address, in a frame slot or a static, where no
other access in the loop may overlap it, lives in a register for the
loop: it is loaded in the preheader, its loads and stores become SSA
values (the SSA updater places the phis), and when the loop stores to it,
it is stored back in each exit. Accesses to the same object at variable
offsets are disjoint when the value ranges at their blocks (bounds
checks, loop counters, masks) keep them apart. Calls in the loop must
not reach the location (a private slot, or a readnone callee). The pass
runs after LICM, and an address constant (a slot's or a static's
address) defined in the loop is made again outside it. Not promoted:
`bench/interp`'s `vm.sp`. Indexing a fixed array is not checked in
tachyon, so nothing bounds `vm.stack[vm.sp]` away from `vm.sp`; with
checked array indexing (or out-of-bounds array indexing declared
undefined) the ranges would.

**Value ranges, extended:** the range of a sum, difference, product or
left shift of two ranged values (interval arithmetic, given up on
overflow), with the facts of the block applied to every operand, not
only to the value compared. With IPCP this removes the bounds checks of a
function whose slice lengths come from its callers as constants
(`stencil`'s `sweep`).

**Escape analysis (heap to stack):** a `malloc` (up to 1024 bytes) or
`calloc` (up to 256) of a constant size whose result is only
dereferenced, compared, copied to or from, and passed itself to `free`
becomes a frame slot (zeroed for `calloc`), and the `free`s go; SROA can
then take it apart. A pointer that is stored, returned, merged by a phi
or passed to any other call keeps its allocation on the heap. One slot
serves an allocation in a loop: the pointer of one iteration cannot reach
the next (it would need a phi).

**Compile time.** `--time-passes` prints the CPU time of each phase.
Compiling the compiler itself to assembly at -O2 (Apple M-series, best
of 7, user + system): 0.5.0 takes 0.63 s, 0.6 (built by itself) 0.50 s;
at -O0, 0.06 s and 0.03 s. Of 0.6's -O2 time, the interprocedural layer
is about 22 ms (constants 5, heap to stack 3, promotion 7, attributes
7): promotion first checks cheaply for a loop that stores to a slot or a
static (most functions have none), the capture analysis marks derived
addresses in place of rescanning per address, and a component whose
functions do not call each other is inferred in one round. The largest
phases are the loop passes (about 130 ms), register allocation with
emission (about 110 ms) and inlining with the simplification after it
(about 80 ms).

**Function pointers as constants:** interprocedural constant propagation
carries function addresses too: a function pointer parameter every
caller passes the same function becomes that function's address, and its
indirect calls become direct (and inlinable). Specialization proper, a
copy of the callee per distinct function pointer argument, needs a new
function in the front end's tables per copy and is left for later.

## Not yet

Planned in [roadmap.md](roadmap.md), or left over: induction variable
narrowing (from 0.5); interprocedural analyses and a
cost-model-driven inliner (0.6); an e-graph-based rewriter (0.7);
vectorization and unrolling with run-time trip counts (0.8);
profile-guided scheduling (0.9).

## 0.7: object files

**0.7 status**
- done: the assembler (`objfile.tach`, `enc_arm64.tach`, `enc_x86.tach`),
  Mach-O and ELF writers; `-c` (or `-o x.o`) writes an object, `-S`,
  `--emit-asm` (or `-o x.s`) assembly, any other output an executable
  (cc links); tests/run.sh, the fuzzers, the benchmarks and the bootstrap
  (interface `tachyonc-0.7`: its fixpoint compares objects) use objects;
  tests/objcheck.sh: on all three targets every compilation of the corpus
  (374) links to the same program as `cc -c` of its assembly; objects are
  identical whatever the host; compile times in roadmap.md
- gate passed (on objects): the suite at every level on both macOS
  targets and in the Linux container, the fixpoint, objcheck 374/374 on
  all three targets, the fuzzer in every mode (about 1,300 programs on
  macOS), the ABI fuzzer in all three modes, host independence
- done (scope added by the user: no undefined behaviour): fixed-array
  indexing `a[i]` is checked like slice indexing, at every level (gen.tach
  for -O0, lowering for -O1/-O2); SCCP and the value ranges remove what
  they prove: matmul, nbody, stencil, sieve keep none, md5 keeps 2 (speed
  unchanged), interp keeps 15 (46 -> 49 ms). With the checks scalar
  promotion can keep a stack machine's `sp` in a register (shown on small
  programs), but not yet in bench/interp: its `match`-dispatched loop is
  not promoted (to look at in 0.8)
- done: an "Undefined behaviour" section in grammar.md: what is defined
  (each case checked at -O0 and -O2 on both instruction sets, at run time
  and folded), what is still undefined (raw pointers and C), and the plan
  (`unsafe` in 0.8)

The compiler writes object files itself. The assembly text it has always
written stays the single source: `objfile.tach` assembles exactly that
text (one statement per line, the subset of the syntax the code
generator uses), so `--emit-asm` and the object cannot disagree, and
`cc -c` of the same text is an oracle for every object.

**How it works.** `objfile.tach` reads the text line by line into
fragments: runs of bytes, each with an optional tail whose size depends
on where it lands: an alignment (zeros in data, NOPs in code, LLVM's
NOPs on x86-64), or an x86-64 jump to a label, short or long. Labels
remember their fragment and offset; references become fixups. Layout
places the fragments section by section and relaxes the jumps as both
system assemblers do: every jump short first, a short one that does not
reach becomes long, until none changes. A jump may be short only when the
assembler resolves it: a label of the same section that is not global
(GNU as), and on Mach-O of the same atom as the jump (LLVM: an atom runs
from one non-temporary symbol to the next, so the linker may move atoms
apart). Fixups then become values, or relocations: AArch64 BRANCH26,
PAGE21/PAGEOFF12, GOT_LOAD_PAGE21/PAGEOFF12, UNSIGNED; x86-64 Mach-O
BRANCH, SIGNED, GOT_LOAD, UNSIGNED; ELF PLT32, PC32,
(REX_)GOTPCRELX, 64 (a temporary label on ELF is its section's symbol
plus an addend). The Mach-O writer adds, on AArch64, LLVM's section-start
symbols (`ltmp0`...): the linker keeps a section, even an empty one, by
its symbols.

The encoders take the instruction forms the code generator writes and
choose where the syntax leaves a choice as the system assemblers do:
`ldr` with a negative or unaligned offset is `ldur`; `mov` of an
immediate is `movz`, `movn` or `orr` with a bitmask; `add`/`sub` with sp
take the extended-register form; x86-64 picks the shortest immediate, the
accumulator forms of `op $imm32, %rax`, the MR form for register moves,
`D1` for shifts by one.

**Checked** by tests/objcheck.sh on every target: each program of the
corpus at -O0 and -O2 is compiled to an object and to assembly, `cc -c`
assembles the assembly, both are linked, and the two executables must
have the same disassembly (padding NOPs aside) and the same data. The
fixpoint compares the compiler's own objects; the objects of the x86-64
build of the compiler (under Rosetta) are identical to the arm64 one's.

## 0.9: the e-graph

GVN (`gvn.tach`) hash-conses the pure instructions along the dominator
tree; 0.9 makes its table an acyclic e-graph, in the manner of
Cranelift's aegraph (`egraph.tach`). Every value has an e-class (the
values known equal to it). Classes are directional, as in Cranelift: when
a rule shows instruction v equal to w (which dominates it), w and its
members join v's class but not the other way round, since w's other
users need not be dominated by v (joining both ways, with union-find,
was the first version's bug, found by the fuzzer). An
instruction new to the table is matched against the rewrite rules, each
pattern's operands against every member of the operands' classes (so a
rewrite made earlier, `x - 3` also being `x + -3`, enables later ones);
a match builds its right-hand side from existing classes, through the
table (equal nodes are shared; new ones go just before the instruction,
so they dominate its uses), and joins it to the instruction's class.
Nothing refers to a node made later, so the graph is acyclic and is never
rebuilt or saturated to a fixpoint. Extraction then picks the class's
cheapest member (constants 0, multiplication 3, division 20, the rest 1,
plus the operands' best costs; the instruction itself on a tie) to stand
for the instruction; members not picked are dead code for the DCE that
follows.

The rules are a table of patterns in a small language, parsed once into
matchers:

```
(add (add x c1) c2) => (add x (+ c1 c2))
(sub x c1) => (add x (negc c1))
(sub (add x y) y) => x
(mul x c1) if (pow2 c1) => (shl x (log2 c1))
(eq (xor x c1) c2) => (eq x (^ c1 c2))
(add (bnot x) 1) => (neg x)
...
```

31 rules: reassociation of constants (add, mul, and, or, xor),
cancellation (`(x + y) - y`, `x - (x - y)`, `(x ^ y) ^ y`), absorption,
`x * c + x`, comparisons with constants through additions and xors,
`x - y == 0`, negations and complements. Commutative operations match
either way round. **Checked**: `tachyonc --check-rules` (run by
tests/run.sh) evaluates both sides of every rule on random values (edge
values included: 0, -1, 1, powers of two and their neighbours) at every
integer width, with the optimizer's folding (which is the language's
arithmetic: wrapping, shifts modulo the width), 2,000 times per rule and
type; a rule that differs once fails. `--no-egraph` turns the rules off,
to compare. The e-graph costs about 3% of the compiler's self-compile at
`-O2`.

## 0.10: vectors

**Vector values.** The vector types of the language (`v2f64`, `v4f32`,
`v2i64`, `v4i32`, `v8i16`, `v16i8`; grammar.md) are compound in the
front end: an expression's value is the address of its 16 bytes, as for
a struct. Lowering loads a vector operand once (when it is evaluated),
computes with the vector instructions (`vbin.op`, `vcmp.cond`, `vsplat`,
`vext`, `vins`, `vsum`, `vneg`, `vsel`) and stores the result into a new
slot; scalar replacement keeps a vector slot's leaf whole, so the slots
become SSA values. `-O0` computes lane by lane, through frame slots: it
shares nothing with the vector instructions, and stays the oracle. Calls
pass vectors as structs of their lanes (tachyon's convention); C's
conventions for vectors are not supported (vectors are not FFI-safe).

The vector instructions are pure, GVN numbers them and LICM moves them;
nothing folds them, and the e-graph's rules (integer patterns) never
match them. In the back end a vector lives in a float register as its
128 bits: q/v registers on AArch64 (never d8-d15, whose upper halves a
call does not keep: a vector interval's register class leaves them out),
xmm on x86-64, both caller-saved; spills take two adjacent 8-byte slots,
the spill area then 16-aligned. Each instruction is one NEON instruction
on AArch64, except a 64-bit multiplication (lane by lane in x16 and
x17). SSE2 has no 8-, 32- or 64-bit multiplication, no 64-bit
comparison, and moves lanes to and from the integer registers poorly:
those go lane by lane through the red zone below `%rsp` (System V
leaves 128 bytes there for the function; nothing else in the generated
code uses it). Both encoders (`enc_arm64.tach`, `enc_x86.tach`) learned
the instructions; `tests/objcheck.sh` checks them against `cc -c`. AVX2
is not used: Rosetta, where x86-64 is tested on Apple silicon, has none.

**The loop vectorizer** (`vectorize.tach`, after the value ranges and
before strength reduction). A candidate is an innermost counted loop
(an induction variable `i` from `start`, step 1, to `n`, the latch's test
`i + 1 < n` or `!=`) whose blocks form a chain from the header to the
latch, each branching out only to checks that fail (blocks ending in
`unreachable`). Every instruction is classified:

- *uniform*: computed from `i` and loop invariants by pure operations
  (addresses, indices), with its coefficient of `i` when it is affine
  (`coef`); copied into the vector loop, where `i` is the first lane's;
- *vector*: a load or store whose address has coefficient size(T)
  (unit stride), arithmetic on such values (`+ - *`, `/` on floats,
  `& | ^`, negation), and reductions: a header phi `r` whose next value is
  `r op x` (op one of `+ - * & | ^`, integers only: a float sum would be
  reassociated, which changes its rounding); the other operand of a
  vector operation is a vector or the same in every iteration (a splat);
- *skipped*: the latch's test and the checks (`idx <u len` with idx
  uniform of coefficient 1, len invariant).

All vector values have one element type T (an unsigned type uses the
signed vector of its width; reductions convert back), so VF = 16 /
size(T) lanes. Loops with calls, other phis, other control flow,
non-unit or unknown strides, comparisons that are values, or a load from
an invariant address in a loop that stores, are left alone.

The transformation keeps the original loop as the remainder and the
fallback, and puts before it:

```
C:  trips = n - start
    ok = trips >= U*VF
         && for each check: lo = idx(start) >= 0 && hi = idx(n-1) >= lo && hi < len
         && for each store S and access A at another address:
            [S(start), S(n-1)+size) and [A(start), A(n-1)+size) disjoint
    branch ok, VP, SP
VP: splats of invariants, the reductions' first vectors (the scalar start
    in lane 0, the identity in the others; zeros for the further copies),
    vend = start + (trips & -(U*VF))
VH: U copies of the body (U = 2 for bodies of up to 40 instructions,
    each copy with its own accumulators); i += U*VF; branch i != vend
VX: accumulators combined, summed across lanes; branch vend == n, E, SP
SP: i and the reductions from C or from VX; the scalar loop
```

`hi >= lo` catches an index that would wrap (the trip count is below
2^63). The overlap tests go by groups of accesses whose addresses differ
by a constant (one range each; a storing group whose accesses are at
different offsets is a dependence, and the loop is left alone), so
`v[0] ... v[6]` cost one test. A load at an address the same in every
iteration is a scalar, its range part of the tests. So the vector loop runs exactly when the scalar loop would run
every iteration without a failing check and without a store reaching
memory another access (at a different address) reads or writes; else the
scalar loop runs from where the vector loop stopped, or from the start,
and stops where it would, at the same iteration. Exit values: the
reductions' results, and uniform values at the last iteration (computed
after the vector loop). The scalar loop's header is marked (`novec`,
kept by inlining and cloning) so that it is not vectorized again;
partial unrolling leaves the loops the vectorizer takes to it.

**Outer loops.** A loop over j whose body is straight-line code around
one inner loop over k (from a constant to a constant, by any step:
unrolling may have made it 4) is vectorized over j: the copy of the
whole nest (`clone_region`) runs VF values of j at once, the inner
loop's phis that are not k become vectors (each lane accumulates exactly
the scalar loop's sequence for its j: a float sum is fine here, nothing
is reassociated), loads whose address has no j stay scalars (a splat
where a vector needs them), and loads and stores at unit stride in j
become vector accesses. The overlap test takes each group's range over
both j and k: addresses affine in each (no j·k product), with the
corners evaluated before the loop (both values of k when its coefficient
is not a constant, `b[k * n + j]`). This is matmul's
`for j { sum = 0.0; for k { sum += a[i][k] * b[k][j] } c[i][j] = sum }`.
Scalar evolution's entry test (`entry_implies`) now also finds the guard
in a block dominating the preheader (an inner loop's guard that the outer
loop's made redundant was not found before).

Tested by `tests/run/opt_vectorize.tach` (IR and assembly checks, every
level, overlapping slices, a check failing part way),
`opt_vectorize_outer.tach` (matrix-vector and matrix products, f64 and
f32, an output overlapping the input),
`tests/run/vector_*.tach`, and `tests/fuzz/run.sh -V`: random
reductions, maps, stencils and explicit vector code over slices of
random lengths and starts, overlapping slices of one array, slices too
short for the loop, nested loops over raw pointers (an output overlapping
the input now and then). `--no-vectorize` turns the vectorizer off.

## 0.10: profiles

`tachyonc --profile-generate FILE` (at `-O1` or `-O2`) instruments the
program: after lowering, every IR block starts by incrementing its
counter (a 64-bit load, add and store), and `main` starts with a call to
the runtime (`profile.tach` holds its source, added to the program as the
module `__profile`), which allocates the counters and registers, with
`atexit`, the function writing them to FILE when the program exits (also
through `exit`, a failed check included):

```
tachyon-profile 1
fn <symbol> <checksum> <blocks>
<count of block 0>
...
```

Functions are in the compiler's order, so the file is deterministic for a
deterministic program; a run overwrites it. `--profile-use FILE` reads it
at the same point, where the IR of a function is exactly what its source
gives (the same in both compilations): the counts go to the blocks
(`BLOCKS[b].count`, -1 where unknown) of each function whose symbol and
checksum (of its blocks' operations, terminators and successors, in
order) match. A function changed since keeps no counts, with
`warning[profile]: the profile of 'f' is stale ...`; a file that cannot
be read is a warning too. `-O0` ignores `--profile-use`.

The counts are hints. Passes that copy blocks keep them (inlining scales
a callee's counts by the call site's over the callee's entry; loop
cloning copies them); blocks made later are unknown. They decide:

- **block layout** (`layout.tach`): the counts are the blocks'
  frequencies (unknown ones estimated: an edge's block as the lesser of
  its ends, others from their predecessors' shares), a branch's
  successors share in proportion to their counts, and blocks that never
  ran go last with the cold ones;
- **inlining**: a call site that never ran is cold (inlined only if that
  costs no size), a hot one (a 32nd of the profile's largest count, 64 at
  least) takes callees up to 240 instructions (30, doubled per loop level,
  otherwise);
- **unrolling and vectorization**: a loop that never ran is neither
  unrolled nor vectorized; a hot one may grow twice as much (192
  instructions) when unrolled partially.

Not done: hot/cold function splitting, profile-guided register
allocation and scheduling. Tested by `tests/run/opt_profile.tach` (the
test runner's `PROFILE` directive compiles a case with
`--profile-generate`, runs it, then checks it compiled with the profile:
the rare way of a branch out of the fall-through, a hot call inlined)
and `opt_profile_stale.tach` (a checked-in profile, stale for one
function).

## 0.11: performance

**The vectorizer's cost model** (`vector_unroll` in `vectorize.tach`).
After the analysis, the loop is vectorized only when the vector version
is expected to be cheaper, in rough cycles of throughput: a scalar
iteration costs S (an instruction 1, a check 2, a float division 4), a
vector iteration of U copies of the body U·B + 3 (B: an instruction 1, a
multiplication done lane by lane 3·VF: SSE2 has only 16-bit lanes for
it, NEON no 64-bit ones), and the decision before the loop, the
reductions' first vectors and their combination G (6, 8 a check, 10 an
overlap test, 4 a sum, 2 + 2·VF another reduction). The expected number
of iterations T is exact when the bounds are constants or one value plus
two constants (an array's end: `[0; 20]` has 20), else the profile's
average (the header's count over the entries', from the preheader or the
nearest block above it with a count). With T the vector version costs
G + ⌊T / U·VF⌋·(U·B + 3) + (T mod U·VF)·S against T·S, for U = 2 (small
bodies, as in 0.10) and U = 1; the cheaper wins, or the scalar loop
stays. Without T, a vector iteration need only be cheaper than the scalar
iterations it replaces. Unrolling asks the same question
(`vectorizable_lanes`), so a loop the vectorizer turns down is unrolled
as before.

*Against full unrolling.* A loop of a few constant trips is unrolled
whole by `transform_loops` (scev.tach: at most 16 trips and 160
instructions), and there the scalar alternative is not the loop: each
copy keeps only its loads, stores and operations (the induction variable,
the latch's test and the addresses affine in it become constants and
offsets, what is invariant leaves, a check of a constant length on an
index of the induction variable and constants is decided), and SLP may
pack them. With `unrolled` = the trip count, `vector_unroll` weighs the
vector loop against T times that. The unroller asks so before unrolling;
and a loop whose checks kept the unroller from it (an exit other than the
latch's) until the ranges removed them is left by the vectorizer when
unrolling whole is cheaper (`full_unroll_trips`), with transform_loops run
again after the vectorizer (only then). bench/fannkuch's copy of a
10-element permutation had been a vector loop since the ranges through
phis proved its checks: a run-time overlap test of the two arrays (both
on the stack), five vector iterations, the scalar loop as fallback, the
loop not unrolled; it is now ten loads and stores, which SLP makes five
16-byte copies, as with `--no-vectorize`: about 5% faster, which takes
back the 3% it had lost (it was not the forwarding of 8-byte stores to
16-byte loads, as first thought: the unrolled copy has those too).
`tests/run/opt_vectorize_unrolled.tach`. The compiler's own code is
unchanged.

In 0.10, `[0; 20]` became a loop of two 16-byte stores an iteration,
which never ran (20 < 32); it is now one vector store and four scalar
ones. A loop the profile shows running two iterations an entry over
`i32`s (four lanes) stays scalar (`tests/run/opt_vectorize_cost.tach`).
bench/interp, which 0.10 measured 5% slower with the vectorizer, has no
loop the vectorizer takes: its IR is the same with `--no-vectorize`, and
the difference was noise.

**Unrolling with run-time trip counts** (`unroll_runtime_loops` in
`vectorize.tach`, after the vectorizer, in its frame). An innermost
counted loop (i from start, step 1, to n) whose trip count is not a
constant, whose only exits are the latch's and failing checks, and which
has no call, gets U copies of its body per iteration:

```
C:  trips = n - start; ok = trips >= U && no check fails over [start, n)
    branch ok, UP, SP
UP: uend = start + (trips & -U)
U0..U(U-1): the copies, chained (copy k's header phis are copy k-1's
    next values), without their checks; branch i' != uend, U0, UX
UX: branch uend == n, E, SP
SP: the header's phis from C or UX; the original loop (the remainder)
```

The checks are proved before the loop as the vectorizer's are, now for
indices of coefficient -1 as well (`s[n - 1 - i]`); a loop with any other
kind of check is left alone. The copies compute exactly what the
iterations do, in order, so recurrences of any kind, float ones included,
are fine. It pays where checks go, or where the loop's own instructions
are a good part of a small body: a loop is unrolled when it has checks or
at most 12 instructions, by 4 within 64 instructions (128 for a hot loop),
else by 2; with a profile, by less (or not) when the loop runs fewer than
2U iterations an entry. Two instcombine rules make the copies' addresses
offsets of one base: `y + (x + c)` is `(y + x) + c` for addresses (u64;
loads and stores take c as their offset, and GVN shares y + x), and
`(x + c) - x` is c. The headers of both loops are marked `novec`.
`--no-unroll-runtime` turns it off. Tested by
`tests/run/opt_unroll_runtime.tach` (a recurrence and a reversed copy,
every length from 0 to 10, a check failing part way).

Compile time: the self-compile at -O2 is within 0.5% (the candidates
are rejected before LCSSA is formed, and the vectorizer's loop forest is
reused when it changed nothing). fannkuch's flips and rotations run about
5% faster.

**The SLP vectorizer** (`slp.tach`, last of the -O2 pipeline, on each
function as it will be emitted: run earlier, vector stores would hide
their values from the loads of the functions they are inlined into). In
a block, the stores writing the VF lanes of one 16-byte vector (one base,
consecutive offsets, one scalar type) are a seed; their values are packed
bottom-up, lane by lane: one value in every lane is a splat; loads of
consecutive addresses in the block, a vector load; the same operation in
every lane (`+ - * & | ^`, negation, `/` on floats), that operation on
the vectors of its operands; anything else is gathered (a splat and
`vins`). A lane is exactly its scalar code: float lanes are the same IEEE
operations, nothing is reassociated. The vector code goes just before the
group's last store, which a vector store replaces; scalars left unused go
with dead code elimination.

That moves the group's loads and stores down to its last store, which the
memory between must allow (gvn.tach's `may_alias`): no call or other
side effect in between, no store in between that may write what a moved
load reads, no access in between to what a moved store writes, no moved
load reading a store of the group made before it. Cost: the vector
instructions (a gather VF, a multiplication done lane by lane 3·VF) must
be fewer than the scalar instructions that go: the stores, and each
lane's load or operation whose every use goes. A load or an operation
whose scalars all stay (used elsewhere) is gathered from them instead
when that is cheaper.

nbody's position update (`b.x += dt * b.vx; b.y += dt * b.vy`) is one
`v2f64` load of the velocities, a multiplication by the splat of dt, an
addition to the loaded positions, one store; its velocity updates pack
the same way, gathering dx and dy (which the distance also uses). Two
pointers the analysis cannot tell apart are left alone (`q.a = q.a +
r.a` ... may be one struct). Tested by `tests/run/opt_slp.tach`.
`--no-slp` turns it off.

**The gaps against clang -O2** on the new benchmarks, and what was done
about the cheap and general ones:

- *Branches on `&&`* (isel.tach). `a && b` leaves a block with a phi of
  a's value and b's and a branch on it; the predecessor that branched on
  a kept a materialized bool, tested twice (`cset`, `cbz`, and `cbz`
  again), as only predecessors ending in a jump were threaded. Now one
  that branched on the phi's value for it goes straight to the phi's
  false (or true) way. bench/sort's heapsort (`child + 1 < end &&
  s[child] < s[child + 1]`) is about 30% faster, a `csel` where clang
  has one.
- *Equalities from branches* (gvn.tach). Below the edge where `x == y`
  holds (the true way of `==`, the false way of `!=`, into a block with no
  other predecessor), uses of y take x in the blocks the edge dominates:
  a constant when one side is one, else the older value; `conv(a) ==
  conv(b)` of one width gives `a == b`. Integers only (0.0 == -0.0).
  After `if a.len != b.len { return false; }` an index below a.len is
  below b.len, so the range analysis drops the check of b[i] in std's
  slice equality, which bench/wordcount's map runs for every word (about
  8%); `tests/run/opt_equality.tach`.
- *Division by a constant* (isel.tach, before tiling). `x / d` and
  `x % d` for a constant d multiply by a magic number (Granlund and
  Montgomery; Hacker's Delight, chapter 10) with a new machine operation,
  `mulh` (the high half of the 128-bit product: `umulh`, `smulh` on
  AArch64, one-operand `mulq`, `imulq` into rdx on x86-64, which the
  allocator keeps free as for a division). Unsigned values up to 32 bits
  take one `mulh` by 2^64 / d rounded up (exact below 2^32, as d < 2^32);
  u64 a `mulh` and a shift, with the add fix-up when the magic number has
  65 bits; signed values up to 32 bits a 64-bit product by the 33-bit magic
  number and an arithmetic shift, i64 a `smulh` with its corrections; then
  one more when negative (`sub q, t, t, asr #63`). The remainder is
  `x - q * d` (`msub`), sharing q with a quotient of the same operands in
  the block. Tachyon's results are kept: division by 0 is left to the
  division instruction (x / 0 is 0, x % 0 is x), x / -1 is -x (MIN / -1
  wraps to MIN). Tested by `tests/run/opt_divide_constant.tach` (every
  kind of constant at every width, against divisions by the same numbers
  unknown to the compiler) and a fuzz mode, `tests/fuzz/run.sh -D`
  (`gendiv.awk`: random constants and dividends, the extremes and exact
  multiples, every level against -O0). bench/wordcount (`% 26`, `/ 26`:
  `umulh`, `lsr`, `msub`) is 3.5% faster, bench/json 3%; collatz divides
  by 2 only, which was a shift already.
- *Ranges through phis* (range.tach). A phi's range is the union of its
  operands' ranges, each at the end of its predecessor with the facts
  there and on the edge. The phis of a loop header are found together by
  induction: each is assumed in a range H, the operands coming back around
  the loop are ranged under the assumptions, and when each falls in its
  phi's H, every phi is in its H always (H holds the entry operands). H
  starts as the entry operands' range, then takes in what came back (a
  join), then is widened to what the facts on the edges back allow (an
  induction variable below its loop's bound, with any step, even one read
  from memory; a decreasing one above its floor), then to the type's
  range, which proves nothing but holds. Phis of other blocks are ranged
  likewise (their loop header's phis first); a range found under an
  assumption about an enclosing phi is kept only for that assumption.
  Facts comparing a value with another now bound it by the other's range
  (`child < end` with end below 1000000), arithmetic shifts and 64-bit
  conversions keep ranges, and an operation of one operand costs a
  quarter of the depth of one of two (light cleanup leaves chains like
  `0 + (n - 0) * 1`). A branch on the phi of `&&` or `||` (a block of the
  phi and the branch alone) is threaded from each predecessor that
  branched on the phi's operand for it, as isel.tach does, but before the
  ranges: in `child + 1 < end && s[child] < s[child + 1]`, the first test
  then holds wherever the whole is true.

  Phi ranges and facts between two values are taken while the branch of
  a check is decided (one way ends the program: a bounds check, an
  unwrap): everywhere, they cost 4% of the self-compile's instructions
  for little more. bench/sort's heapsort, inlined into main with its
  vector's length known, keeps none of its 12 checks (16 checks before, 4
  now, in the generic sift-down of the records); bench/sort is 5% faster.
  The threading costs the loop passes about 6% of their time, and pays it
  back: the compiler built with it builds itself in 2.6% fewer
  instructions. `tests/run/opt_range_phi.tach`: a step of 2, a step read
  from memory, a decreasing index, a sift-down; and an index that reaches
  past the end, whose check stays (and fails); a fuzz mode,
  `tests/fuzz/run.sh -R` (`genrange.awk`), of such loops (some going past
  an end).

What remains, measured:

- *Bounds checks* that need facts the ranges do not carry: in a generic
  sift-down, `end <= s.len` (so the first `s[root]`, with root the
  caller's start, keeps its check). C has no checks; this is the safety
  tachyon keeps.
- *FMA*: clang contracts `a * b + c` by default (nbody: 27 ms against 29
  with `-ffp-contract=off`); tachyon never does, as that changes results.
- *Floats compared for a branch* are `fcmp`, `cset`, `cbnz` on AArch64
  rather than `fcmp`, `b.cond` (`is_fused_compare` excludes floats).
  Fusing them (with the unordered-aware negated conditions `pl`, `hi`,
  `le`, `lt`) was tried and measured: no difference on mandelbrot or
  nbody, so it was left out.
- mandelbrot is within 6% and json, binarytrees and fannkuch are level
  with clang or ahead; the rest of wordcount's gap is its hashing and
  probing loops, which inlining everything (with a profile) does not
  change.

## 0.14: zero-cost iterators

The closures and iterators of 0.14 (docs/design/closures-iterators.md)
come to the optimizer as ordinary code: a closure is a struct of its
captures (a by-reference capture a pointer field) with a function taking
it by pointer (`FN_CLOSURE`); an adapter is a generic struct holding the
iterator below and a closure, taken by value (`self: Self`); a consumer is
a `fold`, which sources and adapters override with a counted loop, its
closure capturing the adapter's closure by reference and the outer one by
value; `for x in it` over anything but a range or a slice is `loop {
match it.next() { Some(x) => .., None => break } }`. Every std iterator
method is `#[inline]`. A chain is zero cost when, once inlined, this is
the loop written by hand: no call, no frame slot, the same vector loop.
What was missing, in pipeline order:

- **Loop passes of `#[inline]` functions wait** (`inlined_everywhere`,
  `loop_pipeline` in `opt.tach`). Bottom-up, a callee's loops were
  rotated, vectorized and unrolled before it was inlined: a source's
  `fold` loops from `self.pos`, unknown there, so its bounds check stayed
  and the vector loop got run-time checks and a checked scalar
  remainder, which the caller, where `pos` is 0, could not undo. A
  function that is `#[inline]`, not address-taken and not visible outside
  now skips the loop passes, LICM and scalar promotion; they run after
  inlining for those still called somewhere. Its size also stays out of
  the program's inlining budget (it leaves the program once inlined).
- **Copy elision** (`copies.tach`, before SROA). A frame slot copied
  whole into another slot or into a part of one at a constant offset (a
  field), by a copy outside loops, where the source is used only before
  the copy and that part of the destination only after it (or elsewhere
  in it before), neither slot's address escaping: the source becomes that
  part, the copy goes. Each adapter level copies the level below into its
  struct, by memcpy above 128 bytes, which SROA does not look through: a
  chain of 20 capturing maps was 20 memcpy calls.
- **SROA to a fixpoint** (`run_sroa`). A slot whose address was stored
  into a slot that is replaced (a variable captured by reference, held by
  the closure's environment) is not a candidate in that round; its address
  then reaches its uses directly, and SROA runs again (at most 4 rounds).
- **Threading on constant tags** (`tags.tach`, at the end of the first
  round of the scalar pipeline). A block whose switch decides on a phi
  (`match` on an enum's tag), or whose branch compares one with a
  constant, is copied for each predecessor giving that phi a constant,
  and the copy jumps to that constant's outcome. The phi may be in an
  earlier block when the blocks between have one predecessor each (a
  loop's header testing its exit before the match): the chain is copied
  (at most 4 blocks, 12 instructions). A predecessor holding only phis
  that feed the tag (what the arms of an `if` leave) is merged into the
  block first. The values the chain defines are then read where they are
  used through the SSA updater, as rotation does. Only phis whose operands
  are constants or phis are tags: an induction variable's loop is left to
  rotation, and bool phis (`&&`, `||`) to range::thread. Once `next` is
  inlined, each of its returns made the `Option`'s tag a constant: `match
  it.next()` becomes a plain loop; a fold whose accumulator is an `Option`
  (`max`) is peeled once and then keeps a plain maximum.
- **Counted loops out of several exits; equal induction variables**
  (`exits.tach`, before rotation). A loop whose header, and blocks after
  it that have no effects and one predecessor each, test several exits to
  one block (past the exit blocks canonical form makes), each an induction
  variable with a step of ±1 against an invariant (`!=` either way, `<`
  going up, `>` going down, signed or not), runs min(T₁, …) times, Tₖ
  computed in the preheader as unsigned numbers (n - start, or 0 when the
  loop is not entered, without branches). A new induction variable c from
  0 replaces the first test by c != T and the others by true; the exit's
  phis must take one value from every test. `for x in v.iter().take(n)`
  over `next` (n != 0, then pos < len) becomes a loop the vectorizer
  takes. Then header phis with the same start and step are one
  induction variable (the counter above and the slice position; next-based
  `enumerate` and `zip`).
- **The inliner's budgets** (`should_inline`, `inline_calls`). A callee
  whose cost is at most 2 (about its call's) is inlined whatever the
  caller's size, while the program's budget lasts: the chain of small
  closures, `as_slice`. A closure called once (`FN_CLOSURE`, single call
  site) is inlined whatever its size: it is moved, not copied, and its
  size before its environment is known (loads through it) says little of
  what it becomes (a closure calling closures: the fold of a chain).
  `#[inline]` functions and closures are charged to the budgets only for
  what they add once simplified (the recount after each round), not their
  size beforehand.
- **CFG**: a branch to two empty blocks that jump to one block, whose phis
  take one value from both, is a jump (what a threaded `cmp(a, b) < 0`
  leaves).
- **Front end**: the limit on type arguments is their size as a tree
  (4096 nodes, memoized), not their depth (12); nested instantiations may
  go 2000 deep (64). A chain nests a level per adapter.

The invariant closures rely on (design, section 2): a local whose address
is taken keeps its own frame slot for the whole function. Copy elision
merges slots only when neither address escapes (all uses are loads,
stores and copies the analysis sees), and nothing colours the stack.

The key kernel, `v.iter().map(|x| x * 3).sum()` hand-desugared
(`tests/run/opt_iter_map_sum.tach`): before, 111 lines of IR, the
callee's vector loop with its run-time check (`cmp.ge`, `cmp.lt` and
`and`s before it), a scalar remainder with a bounds check and a
`callc rt.panic`; after, the hand loop's 77 lines, instruction for
instruction:

```
b333 <- b332 b333:
    v1365: u64 = phi v1279, v1366
    v1325: i64 = phi v1280, v1351
    v1326: v2i64 = phi v1324, v1336
    v1327: v2i64 = phi v1323, v1347
    v1331: v2i64 = load v1365
    v1335: v2i64 = vbin.mul v1331, v1334
    v1336: v2i64 = vbin.add v1326, v1335
    v1344: v2i64 = load v1365 +16
    v1346: v2i64 = vbin.mul v1344, v1334
    v1347: v2i64 = vbin.add v1327, v1346
    v1351: i64 = add v1325, v1315
    v1352: bool = cmp.ne v1320, v1351 from i64
    v1366: u64 = add v1365, v1364
    branch v1352, b333, b334
```

Tests: `tests/run/opt_iter_map_sum.tach` (no call, no slot, the vector
loop), `opt_iter_next.tach` (`take` over `next` vectorized, `while let`
over `map`, `max` with an `Option` accumulator: no switch, no tag phi
left), `opt_iter_deep.tach` (60 capturing maps: one vector loop, no
memcpy), all three hand-desugared, and `opt_iter_real.tach`: the same
kernels (and filter, zip, enumerate, count) written with std's
iterators and closures as the front end makes them, with the same
checks. bench/iterchain.tach (six kernels as chains of std's iterators
and closures) against bench/iterloop.tach (the same by hand), with C
twins; bench/run.sh prints the ratio of their -O2 times, the fastest of
RUNS rounds each, run alternately, and fails above 1.05.

With the front end's own output (after the merge of the closures and
iterators), best of 5 per kernel on a busy machine, chain/hand in ms:
filter-map-sum 68/71, dot 106/112, enumerate 54/55, max+count 158/162,
take over `next` 26/26, collect+sort_by 19/16; the whole program
497/511 (0.97). The last kernel's gap is std's `sort_by` (one loop for
both heap phases) against the hand-written heapsort, not the chain: the
collect alone is even, and the inlined comparator compiles to the same
instructions; the two sorts differ in block layout only.

Compile time: the compiler compiles itself as fast as before (1.59 s
against 1.59 s, best of five); a chain of 200 capturing maps compiles in
0.8 s, one vector loop.

Not done: a loop with an early exit at the header and its counted exit
at the latch (a rotated `while i < n && i < m`) is not merged (the tests
must be at the top); next-based `filter` keeps a bounds check the hand
loop does not have (its position is a phi of two loops' phis); the
sort kernel's comparator, threaded, still leaves an unused comparison.

## 0.15: loops as cc compiles them

0.14's benchmarks found bench/iterloop (six loop kernels written by
hand) at about 2.2 times the time of its C twin under cc -O2, the
iterator chains the same. Comparing the assembly kernel by kernel
(`tachyonc -S`, `cc -O2 -S`), the causes were:

| kernel | cause | ratio to cc -O2, before / after |
|---|---|---|
| filter-map-sum (`if x & 1 == 0 { t += x * x + r }`) | a branch per element (mispredicted), the loop too big for the run-time unroller, one accumulator | 1.78 / 1.05 |
| dot product via zip | vectorized with the 64-bit multiplication done lane by lane (NEON has none): 13 instructions for two elements | 2.62 / 1.03 |
| enumerate-map-sum | unrolled, but one accumulator: each copy waits for the one before | 1.32 / 0.92 |
| map-max + count | the maximum and the count were serial chains of `csel` (2 and 1 cycles an element); cc vectorizes both | 3.74 / 1.07 |
| take | vector loop of 2 copies of 2 lanes, against cc's 4 of 2 | 1.71 / 1.00 |
| collect + sort | the heapsort's bounds checks (`2 * root + 1` may wrap: the checks stay, see below) | 1.23 / 1.15 |

(aarch64-macos, the fastest of 9 alternating runs per kernel.)

**A select in the middle end** (`SEL k, x, y`: k ? x : y, k a bool, x
and y integers). Instruction selection made selects of small diamonds
before (`form_selects`, `csel`); now the loop passes have one too, and
isel makes each a machine SELECT (on the comparison when k is one, an
integer one on x86-64; else on k != 0). It is pure: GVN numbers it
(which made GVN hash and compare the third operand, VSEL's too), LICM
hoists it (checking the third operand as well), the ranges take the
union of x's and y's. Instruction combining: a constant k picks, k ? x
: x is x, and **k ? t op x : t is t op (k ? x : 0)** for op one of `+ -
| ^` (t on the left of `-`): the select leaves the chain through t.

**If-conversion** (`ifconv.tach`, in the loop passes after the ranges,
before the vectorizer; `--no-ifconv`). In an innermost loop, a branch
on a condition that is not invariant (unswitching takes those) whose
ways meet again within the loop, a triangle or a diamond whose arms
hold at most 4 instructions together, pure, no division, no float
operation, and whose meeting block's phis that take two values are at
most 3 integers: the arms' instructions move up before the branch, each
such phi becomes a select. The combining rule above is applied at once,
so `if x > r { c += 1 }` is `c + (x > r ? 1 : 0)`, a sum.

**Masks and minimum/maximum reductions in the vectorizer.** A
comparison with a vector operand used only as the condition of selects
is a mask (`vcmp`; signed when ordered, as the vector comparisons are),
a select on it a `vsel`. A header phi r whose next value is `k ? z : r`
or `k ? r : z`, k an ordered signed comparison of r and z, is a minimum
or a maximum: every lane starts at the start value (the operation is
idempotent), the copies' accumulators are combined lane by lane with
the same comparison and select, then the lanes (`vext`) with scalar
ones. A select picks one of two integers: with ties both are equal, so
the order of the combination does not matter.

**Several accumulators in the run-time unroller**
(`split_reduction`). A header phi whose value is only combined, through
phis and selects, with values that do not depend on it, by one
associative and commutative operation (`+` and `-`, `*`, `^`, `&`, `|`
of integers: they wrap, so their order does not change the result), or
a minimum or maximum as above (of any integers, unsigned too), and
whose only value used after the loop is its next value, gets one
accumulator per copy: copy k's is a new phi of the first copy's header,
starting at the identity (a minimum's at the start), and the
accumulators are combined after the unrolled loop, in order. A loop
with such a reduction is unrolled up to 32 instructions (12 before,
when it has no checks). Floats stay on one accumulator (reassociating
their sums changes the rounding).

**The vectorizer's cost model.** A 64-bit multiplication done lane by
lane costs 4 per lane plus 1 (two lanes out, the product, one in), and
a loop with one is weighed against the scalar loop the run-time
unroller would make of it: its work only, without checks or the loop's
own instructions. `v.iter().map(|x| x * 3).sum()` and the dot product
run 2.5 times faster scalar, unrolled by 4 with 4 accumulators, than as
the 0.10 vector loop. Tiny bodies (at most 16 instructions) over lanes
of 4 bytes or more run 4 copies per vector iteration (2 before). On
x86-64, a 64-bit vector comparison costs as one done lane by lane.

**Pairs of loads and stores** (AArch64). Instruction selection's
scheduler puts loads (stores) of one base at offsets one access apart
side by side, the lower offset first: a load moves up past no store or
call, a store down past no memory access or call (`pair_accesses`).
Emission makes the two lines one `ldp` (`stp`) of x, d or q registers
(`pair_with_last`), unless the first load's result is the base or both
are one register; the encoder learned the q form.

Tests: `opt_ifconv` (selects, masks, every comparison order of minimum
and maximum, a division left as a branch, two selects, every length
from 0 to 20), `opt_unroll_reduction` (each kind of split reduction,
wrapping i32 arithmetic, an unsigned maximum combined by selects),
`opt_ldp`; the iterator tests expect the unrolled scalar loop for
`x * 3`.

Not done: the sort kernel's bounds checks. In a sift-down, `child = 2 *
root + 1` may wrap for all the ranges know (root below a length, a
length below 2^63), so `child < end` does not prove `child <u len`; C
has no checks, and its signed overflow is undefined. The remaining
filter-map-sum gap is cc's knowledge of the length (the kernels are
`static`: clang propagates the constant 1048576 into them).
