# Roadmap

Where tachyon is going, release by release. Each release is built by the
previous one (see [releases.md](releases.md)): a language feature introduced in
release N may be *used in the compiler's own source* only from N+1.

Every release ships only when all of these hold, on aarch64-macos and
x86_64-linux:

- the tagged chain from a fresh clone builds it, and it reaches a fixpoint
  at its default opt level;
- its golden suite passes, with identical output at every opt level;
- the random-program differential tester (`-O0` vs every level, the seed as
  a third oracle) finds no mismatch;
- output is deterministic and host-independent;
- `bench/` results are recorded in this file;
- compile times are recorded in this file (the compiler building itself
  at `-O0` and `-O2`, and end to end to an executable), and any regression
  against the previous release is explained or fixed;
- the generated code does not get slower: every `bench/` program against
  the previous release and against `cc -O2` (and their geometric mean),
  on an idle machine; a slowdown beyond noise blocks the release unless it
  is understood and accepted in the notes. Language features ship only
  when their idiomatic use compiles to code as fast as the hand-written
  equivalent;
- the agents' tool use is traced (`tools/agent-tool-usage.py`, the hook's
  log): what share of reading, searching and editing went through
  `tachyonc` rather than the shell, and why the rest did not; the gaps
  feed the next release's tools.

The gate is one command (from 0.11; [releases.md](releases.md), "The
gate"): `bootstrap/gate.sh --release` builds the chain (every release's
fixpoint, the last release's suite, the working tree), then runs at once
the suite at every level, the random programs in every mode (the seed in
one), the C interop fuzzer in its three modes, objcheck, the header
layouts and the debugger check, next to the two Linux containers
(x86_64-linux from its own chain, aarch64-linux cross-built), and prints
one table. The benchmarks run alone afterwards, on an idle machine
(`gate.sh --only bench`). Between releases `tests/fuzz/forever.sh`
fuzzes every mode at low priority, so the gate's fuzz counts stay
modest; `bootstrap.sh --history full` (every release's suite) is an
occasional complete replay, not part of every gate.

Principle: **no undefined behaviour.** Every operation safe code can
write has defined behaviour (integer overflow wraps, division by zero,
shifts and conversions are defined, indexing is checked); what cannot be
checked (raw pointers, freeing memory, calls into C) is to be confined to
`unsafe` blocks (0.9). For agents above all, a program that compiles
should not be able to fail in ways no one can see in its text.

Priorities: correctness (the gate above) first, then, never traded away,
**the speed of the generated code** (what users get) and **compilation
speed** (how fast anyone iterates), both measured every release; exact C
interop where it is asked for; and tools that let agents do their work
through the compiler.
Compilation speed is weighed in every design: an optimization has to pay
for its compile time.

The reference points: **Cranelift** does SSA, e-graph-based rewriting
(GVN, constant folding, algebraic simplification, LICM, redundant load
elimination) and regalloc2, but no inlining, no loop transformations, no
vectorization and no interprocedural analysis. **LLVM -O2** does all of
those. Tachyon should pass Cranelift around 0.5 and work toward LLVM from
there.

## 0.2: a middle end

The foundation every later release builds on. Design and status in
[optimizer.md](optimizer.md).

- [x] SSA IR (CFG of typed virtual registers, Braun et al. construction),
  printer (`--emit-ir`), verifier after every pass
  (`--verify-ir`), `--print-after-all`
- [x] mem2reg (as part of SSA construction), SCCP (with tachyon's folding
  semantics), copy propagation (by replacement), dead code elimination
  (mark and sweep), CFG simplification. *Aggressive* DCE over control
  dependence (removing dead loops and branches) moves to 0.4, with dead
  loop deletion.
- [x] dominator tree (Cooper–Harvey–Kennedy), dominator-scoped GVN/CSE;
  in-block load and store forwarding with a slot/static alias analysis
- [x] natural loops, LICM of pure non-trapping operations (and of loads
  from slots and statics the loop does not write)
- [x] peepholes: algebraic identities, power-of-two strength reduction
  (including signed division), compare-and-branch fusion, multiplication
  by 3, 5 and 9 as one instruction
- [x] inlining of small and single-call-site functions, bottom-up over
  Tarjan's components; uncalled functions are not emitted
- [x] linear-scan register allocation on both targets, with phi hints and
  rematerialized constants and addresses; immediates (add/sub, shifts,
  AArch64 logical immediates, compares, `cbz`/`cbnz`) and base-plus-offset
  addressing (frame slots from sp). Scaled-index addressing modes move to
  0.5 with rule-based instruction selection.
- [x] `-O0` / `-O1` / `-O2`, default `-O2`; `-O0` is the 0.1 code generator,
  kept as the differential-testing oracle
- [x] testing: the suite at every level, IR checks (`// CHECK:`),
  random-program differential testing with the seed as a third oracle,
  `bench/`

## 0.3: aggregates and memory

Language:
- [x] `enum` with payloads and exhaustive `match` (literal, range, constant,
  binding, tuple, variant and or-patterns, guards; usefulness-based
  exhaustiveness and reachability with witnesses)
- [x] methods (`impl` blocks, static dispatch, `x.m()` with automatic `&`
  and `*`, `T::f()`, `Self`), fields through pointers
- [x] slices `[T]` (pointer plus length) with bounds checks
- [x] assignment evaluates its right-hand side first
- [x] C interop, Rust's model (see the track below)

Optimizations:
- [x] SROA: structs, tuples, enums, slices and small arrays split into
  scalars (also the values of `if`/`match`/`loop`)
- [x] alias analysis: objects reached through constant and variable
  offsets, distinct objects, private slots, constant data; no type-based
  rule (documented)
- [x] store-to-load forwarding along the dominator tree, dead store
  elimination, copies read through and removed (memcpy too), constant local
  tables as read-only data
- [x] `match` lowering: switches, jump tables, binary searches
- [x] C ABI aggregate classification on both targets (fixes `div_t`)
- moved to 0.4: comparison chains to switches; decision trees for matches
  with guards or refutable nested patterns (they test arms in order)

## C interop track

C compatibility is opt-in, as in Rust: the layout of tachyon's own types
and the convention of its own functions are unspecified; where C is asked
for, it is exact.

- **0.3**: `extern "C" { fn ...; static ...; }` imports, `extern "C" fn`
  definitions with unmangled symbols, `extern "C" fn` pointer types
  (distinct from `fn`), `extern "C" static` exports, varargs only in
  imports; `#[repr(C)]` structs, unions and enums (RFC 2195's layout for
  enums with fields), `#[repr(u8)]` and other integer tags,
  `#[repr(C, packed)]`, `#[repr(C, align(N))]` (N up to 16); the FFI-safety
  check; C's convention for every aggregate, every integer width, variadic
  calls; the 0.2 `extern fn` form accepted, deprecated. Gate: the ABI
  conformance fuzzer (`tests/abi/run.sh`), at least 1000 signatures clean
  per target.
- [x] **0.4**: `import "stdio.h";` reads C headers as the target's C
  compiler does (its predefined macros and include path come from
  `cc -dM -E -v`): a C preprocessor (`#include_next`, `#pragma once`,
  `#pragma pack`, GNU variadic macros, `__has_include`) and a declaration
  reader in tachyon, written out as tachyon source (`--emit-imports`
  shows it): `#[repr(C)]` records with C's layout (bit-fields, `packed`,
  `aligned` and `#pragma pack` as explicit padding or `packed(N)`),
  typedefs and enums as aliases, enumerators and constant macros as
  constants, macro aliases of variables and functions, an `extern "C"`
  block with `#[link_name]` for asm-label renames; what tachyon cannot
  express (long double on x86-64, `_Complex`, `__int128`, vectors,
  thread-local variables, static and inline functions) is left out and
  named, with the reason, when used. `--emit-header` writes the C header
  of a program (`extern "C"` functions and statics, `#[repr(C)]` and
  integer-repr types, with `_Static_assert`s of every layout). The
  compiler's own source moved to `extern "C"` blocks; the deprecated
  form is gone. Gates: `tests/cimport/layout.sh` (sizes, alignments
  and offsets of every record of 55 to 65 system headers agree with C),
  `tests/abi/run.sh -i` (signatures through `import`) and `-H` (C
  through the emitted header), 1000 signatures per target each.
- 0.5: [x] `#[repr(C, align(N))]` above 16, up to 4096 (realigned stack
  frames); [x] `import` into a module's namespace (`import "h.h" as c;`, and an
  `import` in any module); function-like macros that are expressions (as
  inline functions) and `errno` (a macro around a function call: use
  `*__error()` on macOS, `*__errno_location()` with glibc) move to 0.6.

## 0.4: loops

The compiler's own source starts using enums, `match`, methods and slices.

Language (front end):

- [x] `import "header.h";` and `--emit-header` (see the C interop track)
- [x] `use E::*;` and `use E::{A, B};`: an enum's variants by their own
  names, in expressions, calls and patterns
- [x] `const` of fieldless enum types; C strings (`c"..."`) as `const`
  and `static` initializers
- [x] `n as E` for fieldless enums, checked (an invalid value exits with
  101: "invalid value V for enum E"); `<`, `<=`, `>`, `>=` on fieldless
  enums (declaration order); variant ranges `E::A..=E::C` in patterns
- [x] `size_of(T)` and `align_of(T)`, integer constants
- [x] `for x in s` over slices and arrays
- [x] a slice's `len` is `i64` (was `u64`)
- [x] raw identifiers (`r#type`), `#[link_name = "..."]` in extern
  blocks, `#[repr(C, packed(N))]`, statics shared with C may be arrays

Optimizations, the loop optimizer (design and status in
[optimizer.md](optimizer.md)):

- [x] loop canonicalization: preheaders, single latch, dedicated exits,
  LCSSA; an SSA updater and region cloning for the transformations
- [x] induction variables (add recurrences, also through chains of
  constant additions) and their exit values; constant trip counts by
  evaluating the exit test with the folding rules (wrapping exact)
- [x] loop strength reduction: addresses affine in an induction variable
  (constant or run-time strides) become pointer induction variables
- [x] loop rotation; full unrolling of small constant trip counts; partial
  unrolling by 2 or 4 when the factor divides a constant trip count.
  Unrolling with a run-time trip count (a remainder loop) moves to 0.5
- [x] loop unswitching on invariant conditions
- [x] value ranges from types, operations, dominating branch conditions,
  switch cases and counted loops; bounds checks they prove are removed,
  comparisons they decide are folded, edges whose test they decide are
  threaded (a `match` with guards becomes a decision tree)
- [x] trip-count-based dead loop deletion; aggressive dead code
  elimination over control dependence
- [x] deferred from 0.3: chains of equality tests become switches;
  decision trees for matches with guards (by threading)
- [x] tail recursion elimination with accumulators (`fib`: half the calls)
- not done: narrowing of induction variables (moves to 0.5, with
  instruction selection); bounds checks whose proof needs the slice's
  length from the caller (0.6, interprocedural)

## 0.5: backend quality (passing Cranelift)

Language (front end; see grammar.md, "Additions of 0.5"):

- [x] generics by monomorphization, checked at instantiation:
  `fn f<T>`, `struct Vec<T>`, `enum Option<T>`, `impl<T> Vec<T>` and
  methods with type parameters of their own; type arguments written
  (`Vec<i64>`, `max::<i64>`, `Vec::<u8>::new()`) or inferred from the
  arguments and the expected type; deterministic instance symbols;
  errors name the instantiation chain; a depth limit for instantiations
  that grow forever. Bounded generics (traits) are left for later.
- [x] modules: a file is a module (`mod m;`), `pub`, paths with `crate`,
  `self` and `super`, `use a::b::{c, d as e}`, `use a::b::*`, `pub use`;
  `import "h.h" as c;` names the C declarations' module
- [x] several errors per compilation (pulled forward from 0.10): the parser
  and the checker recover at statements, items and functions; errors that
  follow from an earlier one are not reported
- [x] a small standard library built into the compiler (`std::Option`,
  `Result`, `Vec`, `Buf`, printing); a generic hash map waits for traits
- [x] `size_of` and `align_of` are always the builtins (the compiler's own
  functions were renamed)
- not done: const generic array lengths (`[T; N]` with `N` a parameter),
  generic type aliases, inline modules, `errno` (a macro around a call)

Back end:

The back end, in two stages (design and status in
[optimizer.md](optimizer.md)). Stage A:

- [x] register allocation by linear scan on SSA form with lifetime holes
  and interval splitting (Wimmer & Mössenböck 2005, Wimmer & Franz 2010):
  splits at block boundaries out of loops, eviction by next use weighted
  by loop depth, phi and argument hints (coalescing), constants and
  addresses kept in registers and rematerialized instead of spilled, one
  store per spilled value, shared spill slots; every register but the
  parallel moves' temporaries allocated (AArch64 x0-x15, x19-x28, d0-d29;
  x86-64 rax-r9, rbx, r12-r15, xmm0-xmm13); `--verify-regalloc`, a checker
  simulating the allocation, and `--print-regalloc`
- [x] frame elision for leaf functions; sibling calls (tail calls to
  callees taking no stack arguments, at -O2)
- [x] (stage B1) a tachyon calling convention of its own for plain
  functions at -O1/-O2: 16 integer and 16 float argument registers on
  AArch64 (7 and 14 on x86-64), aggregates of up to four pieces passed and
  returned in registers by their leaves (or 8-byte chunks), results as IR
  values (`piece`, `pack`) that scalar replacement takes apart; C's
  convention kept by everything C reaches
- [x] (stage B1) realigned frames for `#[repr(C, align(N))]` above 16, up
  to 4096, at every level; C records aligned above 16 import as ordinary
  types; aggregates copied onto the stack aligned as clang and GCC do

Stage B:

- [x] instruction selection by rules (`isel.tach`): a per-target rule
  table tiling each block's SSA DAG by maximal munch into machine
  operations the allocator sees like any instruction: scaled-index
  addressing (AArch64 `[x, x, lsl #s]`, x86-64 `d(b, i, s)`, frame slots
  from `%rsp`), x86-64's three-operand `lea`, AArch64's `madd`/`msub`,
  shifted operands, `ubfx`, `tst`/`tbz`/`tbnz`; selects from small
  diamonds and triangles (`csel`, `csinc`, `fcsel`, `cmov`; one
  comparison shared by neighbouring selects); the C library's `sqrt` on
  macOS and `fabs`/`floor`/`ceil`/`trunc`/`round` on AArch64 as
  instructions; branches on phis threaded into their predecessors, a
  branch on its predecessor's condition decided
- [x] block layout (`layout.tach`): chains by fall-through from static
  edge weights (loop depth, back edges, cold panic paths last), and tail
  duplication of small blocks at emission (threaded dispatch in
  interpreters, loop rotation by layout), small epilogues inlined
- [x] post-allocation peepholes: `stp`/`ldp` for callee-saved registers,
  a move straight back dropped, a reload of what was just stored a move,
  the argument or result register tried when a hint's register is taken
- [x] scheduling, two rules before allocation: a branch's comparison
  last in its block (fused), constants out of loops (made once)
- moved: unrolling with run-time trip counts to 0.8 (the remainder loop
  is the loop vectorizer's too), a general list scheduler to 0.9 (with
  profiles), shrink-wrapping to 0.6

## 0.6: interprocedural

The compiler's source starts using generics, modules and the standard
library (and reports several errors at once while it is written).

Optimizations, interprocedural (design and status in
[optimizer.md](optimizer.md)):

- [x] call graph, bottom-up SCC-ordered inlining with a cost model
  (callee size, constant arguments that decide something, loop depth,
  cold blocks, single call site, growth budgets, `#[inline]` /
  `#[inline(never)]` / `#[cold]` hints) and an inline → simplify
  iteration (three rounds)
- [x] interprocedural constant propagation: constant arguments (also
  function addresses) into internal functions, constant results out;
  indirect calls of a constant address made direct (devirtualization).
  Dead arguments are no longer computed but stay in the signature (no
  per-function convention changes)
- [x] function attribute inference over the call graph's components:
  readnone, readonly, noreturn, willreturn, nopanic, nocapture
  (`--print-attrs`); calls that write nothing are no barrier to load
  forwarding and LICM, unused pure calls are removed
- [x] global DCE (a function whose address is taken stays)
- [x] escape analysis: small non-escaping `malloc` / `calloc` become
  frame slots
- [x] scalar promotion of memory in loops; value ranges of sums,
  products and shifts of two ranged values (stencil's bounds checks go,
  with the constant lengths from its caller)
- not done: function specialization by cloning (a copy per distinct
  constant argument; needs new functions in the front end's tables),
  value numbering of pure calls (with the e-graph, 0.7), promoting
  `vm.sp` in `bench/interp` (fixed arrays are not bounds-checked, so
  nothing proves `vm.stack[vm.sp]` apart from it)

Back end:

- [x] shrink-wrapping (from 0.5): the frame and the callee-saved
  registers only on the paths that need them; jumps out of the frame's
  region tear it down; panics outside it link a frame of their own; the
  allocator keeps entry values in caller-saved registers until the first
  call where it can
- [x] back end: phi and loop-phi coalescing hints, x86-64 cmov operand
  hints, comparisons with immediates (cmn on AArch64), jump tables
  indexed by the value; `--stats` to measure the machine code
- language (front end; see grammar.md, "Additions of 0.6"):
  - [x] `defer`, on every way out of a block
  - [x] `#[inline]`, `#[inline(never)]`, `#[cold]` (read by the optimizer
    through `fn_attr_inline`/`fn_attr_cold`); attributes before `pub`
  - [x] `if let`, `while let`
  - [x] string literals are `[u8]` (breaking)
  - [x] structural `==`/`!=` on structs, tuples, arrays, enums with fields
  - [x] a prelude (Option, Some, None, Result, Ok, Err, Vec, print,
    println); variants of generic enums by their own names
  - [x] ambiguous `*` imports are an error where used (breaking: 0.5 took
    the first)
  - [x] inline modules, generic type aliases
  - moved to 0.7: const generic lengths; `errno` (C macros that expand to
    expressions)

## 0.7: object files

Object files written directly (Mach-O for macOS, ELF
for Linux, both targets): an instruction encoder and the relocations, symbol
tables and sections each format needs, so `cc` only links. `--emit-asm`
stays, and the object files are checked against `cc`'s assembly of the
same text, section by section. The system assembler took 2.4 s of the
compiler's 3 s self-build in 0.6.

Also: fixed-array indexing bounds-checked like slices (no undefined
behaviour; breaking), and an audit of the undefined behaviour left (in
grammar.md); interp's 2% slowdown from 0.6.

## 0.8: no wildcard imports

Every name a file uses is declared in it, imported by name, or written
with its path: what a name means is visible where it is used, which
matters to agents above all.

- `use a::b::*` and `use E::*` are removed; `use a::b::{c, d}` and paths
  stay. The prelude (a fixed, documented list) is not a wildcard.
- `import "h.h";` (every declaration of a header in scope) is removed;
  `import "h.h" as c;` and `c::printf(...)` stay.
- `tachyonc --fix-imports FILE...` rewrites both forms into what replaces
  them, listing the names the code actually uses; the errors for the
  removed forms suggest the same.
- the compiler's own source moves to explicit imports first (while 0.7.0
  builds it).

## 0.9: unsafe, traits and equality saturation

**0.9 status** (work in progress on branch `release-0.9`):

- done: `unsafe` blocks and `unsafe fn`, borrows, `warning[unsafe]`,
  `--deny-warnings`, `--allow-unsafe` (bootstrap interface `tachyonc-0.9`),
  `--fix-unsafe`; std, tests, examples, bench and fuzzers migrated.
  Traits: declarations with defaults, impls for any type, generic impls
  with bounds, bounds on functions, structs and enums, coherence,
  operator traits (Add, Sub, Mul, Div, Neg, Eq, Ord), std's Hash, impls
  for the primitives and `[u8]`, `HashMap`, `sort`
  Small fixes: array constants, strings in static aggregates, line
  continuations in strings, `if c { Some(x) } else { None }` inference,
  `$TACHYON_CC` for importing C headers when cross-compiling
  E-graph: GVN's table is an acyclic e-graph (Cranelift's aegraph) with
  31 rewrite rules in a small pattern language, cost-based extraction,
  and `tachyonc --check-rules` (randomized differential checking of
  every rule at every integer width); `--no-egraph` to compare
- gate (on 249e3d1): bootstrap --dev fixpoint ok, 346 tests at -O0/1/2
  on aarch64-macos and x86_64-macos, fuzz 200 per mode, ABI 50 (plain,
  import, header), objcheck 404/404; x86_64-linux in a container: chain,
  tests at every level, fuzz 80, ABI 30 x3, objcheck, header layout;
  self-compile -O2 670 -> 703 ms (see Benchmarks, 0.9)
- in progress: -
- remaining (moved to 0.10): GVN-PRE; a checking mode for unsafe code
  (pointers carrying bounds); migrating the compiler's own source to
  unsafe blocks (then unsafe operations outside unsafe code are errors)

Language: `unsafe` blocks and functions: raw-pointer dereference,
indexing and arithmetic, freeing memory and calls into C only inside them,
so that safe code has no undefined behaviour at all; a checking mode for
`unsafe` code (pointers carrying bounds, freed memory detected). Traits
(bounded generics), which a generic hash map and
operator overloading need; adding bounds does not change what programs
written against 0.5's unbounded generics mean.

- replace ad-hoc rewriting with an e-graph (acyclic, à la Cranelift's
  ægraph) and a rewrite-rule DSL compiled into matchers
- rewrite rules checked by randomized differential testing before they
  are accepted
- partial redundancy elimination (GVN-PRE)

## 0.10: vectorization and profiles

**0.10 status** (work in progress on branch `release-0.10`):

- done: the compiler's own source migrated to unsafe code (whole
  function bodies in `unsafe { ... }` where a function has several
  unsafe operations, `tachyonc --fix-unsafe` for the rest; the compilers
  built before and after are byte-identical, and tests/compare.sh finds
  9281 of 9281 compilations identical); unsafe operations outside unsafe
  code are errors (`error[unsafe]`), `--allow-unsafe` is gone, and the
  bootstrap interface `tachyonc-0.10` builds HEAD
- done: vector types (`v2f64` ... `v16i8`; grammar.md "Additions of
  0.10"): lanewise operators, masks, select, lanes, sums, checked loads
  and stores; -O0 lane by lane; IR vector instructions (vbin, vcmp,
  vsplat, vext, vins, vsum, vneg, vsel), scalar replacement keeps vectors
  whole; NEON and SSE2 (red zone for what SSE2 lacks) in both text
  emitters and both encoders; vectors in the float registers (never
  d8-d15, whose upper halves calls do not keep), 16-byte spill slots;
  not FFI-safe
- done: loop vectorizer (vectorize.tach): innermost counted loops with
  unit-stride loads and stores of one type and integer reductions, a
  vector loop guarded at run time (bounds checks proven for the whole
  loop, no overlap between stores and other accesses) and the original
  loop as the remainder and the fallback; `--no-vectorize`
- done: `tests/fuzz/run.sh -V` (genvec.awk): reductions, maps, stencils
  and explicit vector code over slices of random lengths and starts,
  overlapping slices, checks failing part way
- done: vector loops of small bodies run two vectors an iteration (own
  accumulators); invariant splats before the loop; optimizer.md "0.10"
- done: profile-guided optimization (profile.tach): `--profile-generate
  FILE` (block counters, written at exit by a small runtime added to the
  program), `--profile-use FILE` (counts per function, checked by a
  checksum of its IR: stale profiles ignored with a warning) for block
  layout, inlining (hot call sites), unrolling and vectorization (cold
  loops); the test runner's `PROFILE` directive
- done: outer-loop vectorization (a loop around one inner loop, over the
  outer index: matmul, whose inner loop is a float sum that may not be
  reassociated); loads at invariant addresses kept scalar under the
  overlap test; overlap tests by groups of accesses
- done: a checking mode for unsafe code (`--check-unsafe`,
  unsafecheck.tach): raw-pointer accesses checked against the heap blocks
  the program allocated (out of bounds, use after free, double free); the
  compiler compiled with it compiles itself to the same output
- done: every error in one compilation (grammar.md "Error recovery"):
  the checker runs after syntax errors (skipping the bodies that had
  them) and recovers per declaration and per field, parameter and result
  type (the error type, with the errors that follow from it suppressed);
  impls, bounds, imports, missing module files and C header errors
  recover too
- done: interp: `vm.sp` is promoted (the 0.6 note): interp is level with
  cc -O2 (40 against 39-40 ms)
- not done, measured: GVN-PRE. Of the compiler's 16,482 pure
  instructions in two-way merge blocks at -O2, 26 are partially
  redundant (an equal one on one way in), and none of bench/'s: a pass
  would not pay for its compile time (LICM already moves what loops
  repeat)
- in progress: -
- remaining (to 0.11): SLP vectorizer; scalar unrolling with run-time
  trip counts; AVX2 (behind a --target-cpu, untestable under Rosetta);
  hot/cold function splitting; PGO-aware register allocation and
  scheduling

Vectorization:
- SLP vectorizer
- loop vectorizer for counted loops with simple dependences
- unrolling with run-time trip counts (from 0.5), sharing the vectorizer's
  remainder loop
- NEON and SSE2/AVX2 lowering; language-level vector types (`v4f32`, ...)

Profile-guided:
- instrumentation profiles (`--profile-generate` / `--profile-use`)
- branch weights driving inlining, block layout and hot/cold splitting
- PGO-aware register allocation and unrolling
- list scheduling (from 0.5) where profiles say a block is hot

## 0.11: feature-complete

The last release of the build-out.

- DWARF line tables (debuggers and backtraces see source lines), in the
  assembly and in the objects the compiler writes
- aarch64-linux as a target and a host
- performance: a broader `bench/` (allocation-heavy, branchy, string and
  hash-map code, not only numeric kernels), measured against clang -O2;
  the SLP vectorizer, scalar unrolling with run-time trip counts and a
  cost model for the loop vectorizer (from 0.10)
- multi-error diagnostics: done (0.5, completed in 0.10)

0.11 A status (DWARF line tables, aarch64-linux):

- aarch64-linux target: done (AAPCS64 in abi.tach and both back ends, ELF
  objects with R_AARCH64_* relocations and mapping symbols, `import`);
  tests, fuzz, ABI (three modes) and objcheck pass in a linux/arm64
  container
- aarch64-linux host: done (cross-built by `bootstrap.sh --host
  aarch64-linux`, finished natively by `bootstrap/aarch64-linux-check.sh`)
- DWARF line tables (`-g`): done (`.file`/`.loc` from statement
  positions carried through the IR at every level; .debug_info with a
  compile unit and its subprograms; the line program written by the object
  writer for Mach-O and ELF; dsymutil after linking on macOS; CFI as compact
  unwind on Mach-O, for lldb at -O0); objcheck compares the decoded line
  tables with `cc -c`'s on every target, tests/debug.sh runs lldb and gdb
  (breakpoints in two files, a crash's backtrace with file:line at -O0 and
  -O2); the output without `-g` is unchanged
- gate: bootstrap --dev and the suite at -O0/1/2 on aarch64-macos;
  linux-check (x86_64-linux: chain, all levels, fuzz, ABI, objcheck);
  aarch64-linux-check (fixpoint, all levels, fuzz in every mode, ABI,
  objcheck, gdb); compile time without -g as 0.10's. Not run: the suite
  on x86_64-macos (Rosetta stopped running new programs on the test
  machine after lldb attached to one; needs a reboot), gdb on x86_64-linux
  (no ptrace under Rosetta for Linux)

0.11 B status (performance):
- broader bench/: done (binarytrees, fannkuch, json, mandelbrot, sort,
  wordcount, each with its C version; `bench/run.sh` prints the
  geometric mean of each column against cc -O2)
- cost model for the loop vectorizer: done (expected trips from constant
  bounds or the profile; optimizer.md, 0.11)
- scalar unrolling with run-time trip counts: done (in the vectorizer's
  frame, checks proved before the loop; optimizer.md, 0.11)
- SLP vectorizer: done (stores to the lanes of a vector, packed bottom-up;
  last in the pipeline; optimizer.md, 0.11)
- the gaps against clang on the new benchmarks: branches on `&&` threaded
  from the predecessor that branched (isel), equalities from branches
  (GVN); what remains in optimizer.md, 0.11

0.11.0 release gate (2026-10-14): bootstrap --dev (fixpoint, 412 tests)
and the suite at -O0/1/2 on aarch64-macos; fuzz 100 in each of the nine
modes, ABI 40 (plain, `-i`, `-H`), objcheck (904 of 904); linux-check
(x86_64-linux: the chain from the seed, all levels, fuzz 60 and 60 `-D`,
ABI 30 in three modes, header layouts, objcheck); aarch64-linux-check
(the cross-built fixpoint, all levels, fuzz 100 in the seven modes it
runs, ABI 40 in three modes, header layouts, objcheck, gdb); benchmarks
and compile times in "Benchmarks", 0.11; the agents' tool use in
agent-tool-usage.md, "0.11: with the compiler's tools". Not run: the
suite on x86_64-macos (Rosetta on the test machine, as for part A).

## 0.11 (continued): tools for agents

`tachyonc query` (def, show, refs, callers, items; fully qualified paths
in and out; see docs/query.md) and the agent harness's query-first test
(AGENTS.md, tools/agent-hooks/), then the refactoring toolkit, measured
by docs/agent-tool-usage.md:

- edit by name: `tachyonc edit replace|insert|delete NAME` (no reading a
  file to change one item)
- `tachyonc check` (front end only, short diagnostics), `tachyonc fix`
  (every machine-applicable fix), `tachyonc same-output OLD` (a pure
  refactor proven to change nothing)
- semantic refactors, atomic (checked after editing, nothing written on
  failure), one summary line each: `refactor rename`, `move`, `signature`,
  `field`, `variant`, `new-module`, `move-module`, `split`; typed
  structural `rewrite`; `refactor --script` batches; `--dry-run`, `--undo`
- planning queries: `query stats` (sizes), `query deps` (what references
  what inside a module), `query unused`, `query impact`
- `tachyonc lint --max-lines N`
- every diagnostic: one line with a stable code, then `try:` lines with
  the exact command; large outputs summarized

## 0.12: the compiler's source, reorganized with those tools

`compiler/src` split into folders by phase (front end, middle end, back
end, object writing, driver), no file over 1,000 lines (checked by the
test suite from then on), done with 0.11's own refactoring commands and
proven output-identical with `same-output`. Every place the tools fell
short is recorded (tools/agent-feedback, the hook's log).

Done (0.12.0). Phase 1 moved the modules into six folders by phase
(`base`, `front`, `middle`, `back`, `gen0`, `tools`) in one `refactor
--script`; phase 2, six agents in parallel worktrees, split the 25 files
over 1,000 lines by concern (77 files before, 172 after; `lint
--max-lines 1000` clean); the clean-up then added the tools the agents
had asked for (`fix --only reexports` and `tidy-imports`, `split
--reexport` and part headers, `MODULE::use` and `::header` as edit
targets, the hook's fixes) and used them: every import names the module
that defines what it imports (805 imports and paths rewritten, every
re-export removed), the `use` lines tidied, 16 unused items deleted, a
README per folder. `same-output` identical after every step, against
the reorganization's base and against 0.11.0 (4,668 compilations); the
fixpoint holds (built by 0.11.0, 418 tests). The tool use, phase by
phase, is in agent-tool-usage.md, "0.12: the reorganization through the
tools".

0.12.0 release gate (2026-10-14): `bootstrap/gate.sh --release`, 11:54
wall, every step passed: the chain (fixpoint, built by 0.11.0) and the
suite at -O0/1/2 (418 tests) on aarch64-macos; fuzz 60 in each of the
ten modes (the seed in one), ABI 100 in three modes, objcheck (904 of
904), header layouts, the lldb check; x86_64-linux (its own chain, the
suite at every level, fuzz 50 in ten modes, ABI 40 in three, objcheck,
layouts); aarch64-linux (the cross-built fixpoint, the suite, fuzz 300
in nine modes, ABI 150 in three, objcheck, layouts, gdb). Benchmarks and
compile times in "Benchmarks", 0.12. Not run: the suite on x86_64-macos
(Rosetta on the test machine).

## 0.13: the tools, improved from that record

What 0.12's refactoring showed the tools lacked, fixed and measured
again.

- `tachyonc guide` (`compiler/guide/`, `compiler/src/guide/`): the
  language for a reader who has never seen it, built into the compiler:
  the core guide by default (about 5k tokens: Rust habits and what
  tachyon has instead, the essentials, std's API generated from std's
  source, the first errors, the tools), `guide TOPIC` for the detail,
  `guide --list` with each topic's size. `tests/guide/run.sh` (category
  `guide`) compiles and runs every example, checks the std section
  against the compiler's item index and the core guide's budget.

Done (0.13.0). Six agents in parallel worktrees, one per area, then the
integration: edit precision (`edit patch` inside a line, `--pairs`,
`edit wrap`, `edit new-file`, `signature --default`, `fix --in` over a
subtree); query completeness (banners and sections, `query grep`, `query
type`, kinds of references); the tools' cache (a query or `check` of an
unchanged program in about 6 to 8 ms instead of about 60); refactor
(`split` part names, layout kept so a move and the move back change
nothing, `extract-function`, `inline`); `tachyonc fmt`, with the tree
formatted (same-output identical to 0.12.0), and `tachyonc explain`;
`tachyonc guide`. 83% of the edits to existing compiler source went
through the tools, every one of the feature agents' on files that existed
before they began (agent-tool-usage.md, "0.13: the tools, built with the
tools").

0.13.0 release gate (2026-10-14): `bootstrap/gate.sh --release`, 15:02
wall (other agents' work on the machine), every step passed: the chain
(fixpoint, built by 0.12.0) and the suite at -O0/1/2 (552 tests) on
aarch64-macos; fuzz 60 in each of the ten modes (the seed in one), ABI
100 in three modes, objcheck (904 of 904), header layouts, the lldb
check; x86_64-linux (its own chain, the suite at every level, fuzz 50 in
ten modes, ABI 40 in three, objcheck, layouts); aarch64-linux (the
cross-built fixpoint, the suite, fuzz 300 in nine modes, ABI 150 in
three, objcheck, layouts, gdb). Not run here: the benchmarks (`gate.sh
--only bench`, on an idle machine) and the suite on x86_64-macos
(Rosetta on the test machine).

## 0.14: an agent eval; closures and iterators

From here a feature new in release N enters the compiler's own source in N+1
(migrated with the refactoring tools; breaking changes come with a
`tachyonc fix` migration).

- the agent eval (`tests/agent-eval/`): about twelve fixed tasks (write a
  hash map, fix a parser bug, port a C program, add a compiler pass,
  refactor a module, a CLI tool, ...) with hidden acceptance tests, each
  given to a fresh agent with only `tachyonc guide` and the docs;
  measured: success rate, tokens, tool calls, compile-fix iterations.
  Baseline on 0.13; no release may regress it, and language changes must
  improve it. Each task has a Rust twin (same specification, same hidden
  tests) as the control: a language the models know against one they do
  not; tachyon runs in four conditions (compiler only, with the guide,
  with the tools and `try:` diagnostics, with both) to show what each
  contributes; models of several sizes, hosted (small, mid, large) and
  local (e.g. Qwen3-Coder through any OpenAI-compatible server, driven by a
  minimal agent loop in the runner with the same tools); run
  periodically, not every release (decided after the 0.13 baseline: see
  [docs/eval/0.13-findings.md](eval/0.13-findings.md), whose findings
  added std input reading, std-aware did-you-mean and the user-program
  tool fixes to 0.14)
- closures (`|x| x * 2`): capture by value, or by borrow when they do not
  escape; `Fn`/`FnMut` traits, monomorphized; a non-capturing closure is a
  `fn` pointer
- iterators: an `Iterator` trait, `for` over anything iterable, `map`,
  `filter`, `enumerate`, `zip`, `take`, `sum`, `min`, `max`, `collect`;
  slices, `Vec`, ranges and `HashMap` iterable
- zero cost: closures inlined and iterator chains fused into loops (a
  benchmark pair, iterator chain against hand loop, must time the same)
- query and refactor understand closures
- candidates from 0.13's record (agent-tool-usage.md, "0.13"): `edit
  insert` adding a new item's imports in the same edit; `split --items`
  moving a section's banner with it; `edit patch FILE:LINE` on a comment
  line outside items; merge conflicts in `.tach` files (a query of the
  regions, `edit resolve`)

Done (0.14.0). The agent eval first (twelve tasks with Rust twins,
`tests/agent-eval/run.py`, the 0.13 baseline with Claude Haiku and Sonnet
and six runs of Qwen3-Coder; local runs off until re-enabled), and what
its findings asked for: std's stdin reading, text helpers, in-place map
and vector updates and an introsort; did-you-mean across the program and
std, helps for Rust habits; the tools on a user's program (`undo` without
git, local renames, `variant --arm-in`, imports added by edits). Then the
design (docs/design/closures-iterators.md), an interface commit and five
parallel tasks: closures (`Fn`/`FnMut` bounds, captures by value or by
reference, `move`, an escape check, a non-capturing closure a `fn`);
associated types (needed by `Iterator`, with constraints and lazy
defaults); iterators (`for` over anything iterable, ranges as values,
`map`, `filter`, `enumerate`, `zip`, `take`, `fold`, `for_each`,
`count`, `sum`, `min`, `max`, `collect`, `sort_by`; slices, `Vec`,
ranges and `HashMap` iterable); zero cost (bench/iterchain.tach against
bench/iterloop.tach, held by `bench/run.sh` at a ratio of at most 1.05);
the tools, fmt and the guide on closures. Of 0.13's tool candidates,
`edit insert` adding imports, `split` moving a banner with its group and
`edit patch FILE:LINE` between items are done. Moved: merge conflicts in
`.tach` files (docs/tool-gaps-014.md, gap 8) to a later release;
`iter_mut` to 0.17's value semantics (indexing until then); `collect`
into anything but a `Vec`, and returning closures (`impl Fn`), to a
later release. Fixed on the way: three reads of freed memory (slicing
whose bounds grow the storage, `Buf::push_str` of its own view, the
compiler's tables indexed through calls that move them), and the gate's
`stress-grow` step that keeps them fixed. 85% of the edits to existing
compiler source went through the tools (agent-tool-usage.md, "0.14");
630 tests.

0.14.0 release gate (2026-10-15): `bootstrap/gate.sh --release`, 30:02
wall (other agents' work on the machine, load average 6 to 24), every
step passed: the chain (fixpoint, built by 0.13.0) and the suite at
-O0/1/2 (630 tests) on aarch64-macos; fuzz 60 in each of the ten modes
(the seed in one), ABI 100 in three modes, objcheck (1048 of 1048),
header layouts, the lldb check, and the new stress-grow step (the
self-compile the same, the suite at -O0 and -O2, with every table growth
moving); x86_64-linux (its own chain, the suite at every level, fuzz 50
in ten modes, ABI 40 in three, objcheck, layouts); aarch64-linux (the
cross-built fixpoint, the suite, fuzz 300 in nine modes, ABI 150 in
three, objcheck, layouts, gdb). Benchmarks and compile times in
"Benchmarks", 0.14. Not run: the suite on x86_64-macos (Rosetta on the
test machine).

## 0.15: errors, conversions, less boilerplate

- `?` on `Result` and `Option`; typed error enums as the std convention;
  std I/O returning `Result`
- lossless implicit widening (narrower to wider integer of the same
  signedness, unsigned to wider signed); everything else stays an
  explicit `as`; `From` / `Into`
- `#[derive(Eq, Ord, Hash, Debug, Clone)]`
- string interpolation, `"n = {n}, v = {v:?}"`, over `Display` / `Debug`
- field shorthand `S { x, y }`; named and default arguments
- the compiler's source moves to closures and iterators (0.14)
- the agent eval, harder (the 0.13 baseline hit the ceiling: Claude
  Haiku and Sonnet solved 59 of 60 runs each): larger multi-module tasks,
  porting a C program, a compiler-like pass over an AST, tighter perf
  limits, several runs per cell; the guide says when the tools pay off
  (renames, moves, signatures, errors across files) and when reading a
  small file is cheaper (tools-only cost more than the guide alone)

Done (0.15.0, the release gate still to run). The design
(docs/design/errors-formatting.md), an interface commit with stubs and
hooks, and six parallel tasks merged in the design's order: errors and
conversions (`?`, generic traits, `From`/`Into`, `main` returning
`Result`); widening and arguments (lossless widening and joins, named
and default arguments, shorthand checked, std's I/O on `Result` with
typed errors, `fix --only std015` for 0.14 code); formatting (f-strings,
`Display`/`Debug`, generic `print`/`format` through one static buffer,
`bench/fmtloop` at the cost of the hand-written text); derive (`Eq`,
`Ord`, `Hash`, `Debug`, `Clone`, `Clone` in std, tuples ordered and
hashed, `sort_stable`); the tools on all of it and the tools track from
docs/tool-gaps-014.md (`query context` and budgets, std from any
program, names in every printed spelling, `try`, `batch`, `edit apply`
and several targets, `edit.breaks` hints, merge conflicts through `query
conflicts` and `edit resolve` (0.14's moved gap 8), `--json`, the check
hook, `target/tools/tachyonc`); the compiler's back end, gen0 and base on
closures and iterators. Decided at integration: `i64::MAX` and the other
integer limits as builtin constants (no associated constants in general
yet); `==` on `Vec`, `Buf` and `HashMap` by contents. std doubled in size
(46 to 90 KB), so it is loaded by sections: a small program compiles
faster than with 0.14.0. The eval gained tasks 13-18 (harder: a C port,
an AST pass, a multi-module program, a tight perf limit, run-time bugs,
an API refactor) and the check hook; the guide says when the tools pay
off. Moved: the front end's and the tools' source onto closures and
iterators to 0.16 (with 0.15's own features, as planned); several runs
per eval cell, and a baseline on the harder tasks, to a later release;
associated constants in general, `Debug` for tuples and generic slices,
`collect` into anything but a `Vec`, and returning closures, to later
releases.

## 0.16: effects

- inferred effect sets per function: `alloc`, `io`, `panic`, `global`
  (reads or writes statics), `unsafe`, `diverge`; shown by `query
  effects`, in `query def` / `show`, in diagnostics
- declarable and checked transitively: `#[pure]`, `#[no_panic]`,
  `#[no_alloc]`, `#[no_io]`; effect bounds on trait methods; generics'
  effects inferred per instantiation
- writing a `static mut` needs the `global` effect (denied in pure code)
- allocation is explicit, as in Zig: an `Allocator` interface passed or
  stored (std containers carry theirs), no allocator in scope means no
  allocation; std provides a general-purpose allocator (with leak,
  double-free and use-after-free detection in debug builds), an arena
  (bump allocation, freed at once, a scoped form whose values cannot
  escape) and a fixed-buffer allocator; `alloc` names which allocator a
  function uses, so `#[no_alloc]` and "allocates only from its arena" are
  checked and shown by `query effects`
- the optimizer uses them: pure calls numbered, hoisted and memoized in
  the e-graph
- the compiler's source moves to `?`, `derive`, interpolation and widening
  (0.15)

## 0.17: memory safety by mutable value semantics

- values are values: assigning a type owning memory (`Vec`, `Buf`,
  `HashMap`, user types with `Drop`) moves it; destructors at the end of
  the scope replace manual `free` (and most `defer`); `.clone()` explicit
- references are second-class: `&x` / `inout x` parameters pass down the
  call chain but are never stored in a struct, returned, or captured by
  an escaping closure; slices become views under the same rule. This
  closes the dangling-borrow gap without lifetime annotations
- raw pointers stay the escape hatch, in `unsafe`, checked by
  `--check-unsafe`
- with the allocators of 0.16: an owned value carries its allocator,
  moves and destructors free through it; values in an arena skip
  per-value destruction, and second-class references keep arena data from
  outliving its scope. One design covers ownership and allocation
- `tachyonc fix --values` migrates the common patterns (manual `free` to
  destructors, stored slices to owned copies or indices) and gives exact
  diagnostics for the rest
- the largest design change of the plan: a design document and a
  prototype first, then the implementation; it may become 0.17 and 0.17.1
  rather than be rushed
- the compiler's source moves to effect annotations (0.16)

## 0.18: contracts and verification in the language

- `requires` / `ensures` / `invariant`: checked at run time (a violation
  exits with 101, like any check); the optimizer removes a check only
  where range analysis proves it, never by assuming it
- `test` blocks; `#[property]` tests with generators derived from the
  types; `#[fuzz]` entry points; snapshot tests; `tachyonc test` (with the
  `-O0` against `-O2` comparison built in) and `tachyonc reduce`
- `type X = distinct T`; non-null pointer types
- the compiler's source moves to mutable value semantics (0.17) and to
  arenas: the syntax tree and types in one per compilation, the IR in one
  per function, reset after it is emitted (compile time measured before
  and after)
- after 0.18 the type system has settled: the language specification is
  written (see "Toward 1.0")

## After 0.18: a standard library, and a real program on it

Planned with the user on 2026-10-14, to start once 0.18 has shipped. The
standard library is built with the language of 0.15–0.18 (allocators in
effects, mutable value semantics, contracts), measured against Rust's and
C's, and proven on a real program: a GPU-rendered terminal emulator,
shipped as an example (not a release goal of its own). Each release may
split into .x releases rather than be rushed.

## 0.19: collections, text and I/O

- collections, each allocator-aware (0.16), with value semantics (0.17),
  iterators, `derive`d traits and contracts:
  - `Vec` (reworked);
  - `VecDeque`;
  - `HashMap` and `HashSet`: an open-addressing, SIMD-probed table, with
    a seeded hash where inputs are untrusted;
  - `BTreeMap` and `BTreeSet`;
  - `BinaryHeap`;
  - a small-vector and a bitset;
  - stable and unstable sorts, binary search;
- text:
  - an owned UTF-8 `String` and `str` views;
  - chars, graphemes and display width (needed by the terminal);
  - formatting and parsing of numbers and floats (shortest round-trip);
  - interpolation (0.15) on top of it;
- I/O and the system:
  - files, buffered readers and writers, paths, directories, environment;
  - processes and pipes; time and clocks; random numbers;
  - `std::io` errors with `?` (0.15);
- benchmarks against Rust's std and C on the same operations (a bench/
  pair each); a property test per collection against a model (0.18)

## 0.20: concurrency, atomics and synchronization

- threads: `spawn`/`join`, scoped threads that may borrow the parent's
  values (second-class references, 0.17), thread-locals
- atomics on integers and pointers with C11 orderings (`Relaxed`,
  `Acquire`, `Release`, `AcqRel`, `SeqCst`), compare-exchange and fences,
  lowered to arm64's LDAR/STLR/LSE and x86's locked instructions
- synchronization: `Mutex` (owning its data), `RwLock`, `Condvar`,
  `Once`/lazy statics, `Barrier`, a semaphore; channels (unbounded and
  bounded MPSC, MPMC); a work-stealing thread pool and parallel iterators
- no data races in safe code, so no UB: what may cross threads is
  inferred like Rust's Send/Sync, from value semantics and effects
  (`thread` and `sync` effects, `query effects` shows them); shared
  mutable state only through atomics and locks
- testing built in: a schedule-exploring checker for small concurrent
  tests (in the manner of loom) and a race-detecting build mode; the
  fuzzer gains threads

## 0.21: GPU support

- a native `gpu` library: wgpu's model (instance, adapter, device, queue,
  buffers, textures, samplers, bind groups, render and compute pipelines,
  command encoders, surfaces), but designed for tachyon rather than
  ported: resources as values with destructors (0.17), allocation through
  allocators (0.16), effects for what touches the device, traits for the
  backend interface, contracts for the validation rules
- backends: Metal first (macOS is the main platform), Vulkan second
  (Linux); through C interop: `import "..." as` for Vulkan and the
  Objective-C runtime for Metal (`objc_msgSend` behind typed bindings)
- shaders: a WGSL subset compiled by a tachyon library to MSL and SPIR-V
  (a translator in the manner of naga; a compiler workload that dogfoods
  the language)
- tested headless: compute kernels against CPU results, render passes
  read back and compared with reference images

## 0.22: windows and input in std, and a terminal emulator

- a `window` library in std, in the manner of winit: an event loop,
  windows with a GPU surface (0.21), keyboard (with modifiers and text
  input), mouse, resize, high-DPI scale, a frame clock, clipboard; Cocoa
  on macOS, Wayland then X11 on Linux
- the terminal emulator, an example program (`examples/term`) that
  proves the standard library:
  - a pty and a child shell, its I/O on its own thread (0.20);
  - an xterm-compatible escape-sequence parser (a state machine in the
    manner of vte), a grid with scrollback, alternate screen, 256 and
    true colours, attributes, wide and combining characters (0.19's
    display width), resize and reflow;
  - rendering: fonts rasterized through the platform (Core Text,
    FreeType) into a glyph atlas, one instanced draw of the cells per
    frame, damage tracking so idle costs nothing;
  - input: keys with modifiers, mouse reporting, bracketed paste,
    selection and copy;
  - measured against Alacritty on the same machine (input latency, `cat`
    throughput, memory, frame time); the parser fuzzed with a reference
    terminal's state as the oracle
- what writing it reveals feeds the surface-language rework of "Toward
  1.0"

## Toward 1.0

1.0 is not a feature milestone: it ships when the language is thought
through and stable, after as many 0.11.x / 0.12+ iterations as that takes:

- the surface language reworked with experience of real programs:
  strings, error handling, iteration, conversions, traits and their
  ergonomics, naming; anything breaking settled before 1.0
- tools: a language server (editor support), a formatter, build and
  package workflow, documentation generation
- stability: long-running fuzzing, real programs in tachyon beyond the
  compiler, no known miscompiles
- making the language and its tools work for agents as well as people:
  ideas collected in [agents.md](agents.md)
- a written language specification, once the type system and the
  agent-facing design have settled
- 1.0 freezes compatibility, not features: from 1.0 on, additions are minor
  releases and breaking changes wait for 2.0

## Benchmarks

Runtimes per release are recorded here as each one ships. `bench/run.sh`
prints the fastest of several runs, in milliseconds; "previous" is the
previous release at its default level, "seed" the seed at `-O` (Cranelift).
From 0.4 on the benchmarks declare their C functions in `extern "C"` blocks,
which the seed does not know; `bench/run.sh` (and the fuzzer's seed mode)
hand the seed a copy rewritten into 0.2's `extern fn` declarations by
`tests/seed-compat.awk`, so the seed column stays for every program written
in the seed's language.

### 0.2

aarch64-macos (Apple silicon, native; `bench/run.sh -r 5`):

| program | 0.1.0 | 0.2 -O0 | 0.2 -O1 | 0.2 -O2 | seed -O | cc -O2 |
|---|---|---|---|---|---|---|
| collatz (`< 3·10⁶`) | 2563 | 2559 | 422 | 419 | 477 | 292 |
| fib (35, recursive) | 56 | 54 | 29 | 28 | 29 | 14 |
| matmul (300², f64, ×3) | 500 | 506 | 105 | 46 | 94 | 43 |
| sieve (`3·10⁷`) | 301 | 307 | 67 | 69 | 67 | 71 |
| md5 (8 MB) | 369 | 369 | 164 | 145 | 133 | — |

x86_64-linux (the minimal Debian container, x86-64 emulated by Rosetta on
Apple silicon: absolute numbers are distorted, cc's most of all; `-r 3`):

| program | 0.1.0 | 0.2 -O0 | 0.2 -O1 | 0.2 -O2 | seed -O | cc -O2 |
|---|---|---|---|---|---|---|
| collatz | 2326 | 2312 | 477 | 443 | 486 | 362 |
| fib | 89 | 89 | 51 | 51 | 51 | 17 |
| matmul | 583 | 580 | 254 | 54 | 190 | 27 |
| sieve | 360 | 359 | 125 | 162 | 171 | 146 |
| md5 | 468 | 468 | 189 | 147 | 154 | — |

Against 0.1.0, `-O2` is 2–11× faster; it is ahead of or level with the
seed's Cranelift output on four of five programs (md5 is 9% behind: its
`get_shift` builds a 64-byte table on every call, and nothing yet removes
the stores), and within 10% of clang on matmul and sieve. Compile time of
the compiler itself (14,000 lines) on the same machine: 0.1.0 32 ms, 0.2 at
`-O0` 13 ms, at `-O1` 35 ms, at `-O2` 90 ms.

### 0.3

aarch64-macos (Apple silicon, native, on an otherwise idle machine;
`bench/run.sh -r 7`; "0.2.0" is the
previous release, which cannot build the programs written in the 0.3
language, nor md5, whose example now uses `extern "C"`: its 0.2.0 time
is from the 0.2 table):

| program | 0.2.0 | 0.3 -O0 | 0.3 -O1 | 0.3 -O2 | seed -O | cc -O2 |
|---|---|---|---|---|---|---|
| collatz | 451 | 2549 | 423 | 420 | 479 | 297 |
| fib | 29 | 56 | 29 | 29 | 30 | 15 |
| interp (new: enums, `match`, methods, slices) | - | 444 | 95 | 54 | - | 41 |
| matmul | 46 | 507 | 106 | 46 | 94 | 44 |
| nbody (new: structs of floats) | - | 302 | 36 | 36 | - | 28 |
| sieve | 69 | 270 | 67 | 69 | 70 | 72 |
| md5 | (145) | 384 | 168 | 121 | - | - |

x86_64-linux (the minimal Debian container under Rosetta; `-r 3`):

| program | 0.2.0 | 0.3 -O0 | 0.3 -O1 | 0.3 -O2 | seed -O | cc -O2 |
|---|---|---|---|---|---|---|
| collatz | 465 | 2653 | 497 | 460 | 505 | 376 |
| fib | 52 | 91 | 52 | 51 | 51 | 17 |
| interp | - | 545 | 207 | 148 | - | 109 |
| matmul | 55 | 617 | 254 | 54 | 191 | 28 |
| nbody | - | 309 | 92 | 84 | - | 40 |
| sieve | 165 | 334 | 181 | 160 | 152 | 150 |
| md5 | (147) | 465 | 190 | 124 | - | - |

md5 is 17% faster than 0.2 (its shift table is read-only data now, its
loads folded); interp, a `match`-dispatched bytecode VM over a slice, is
within 35% of C, and nbody within 30%, with every struct and enum value in
registers. (sieve compiles to byte-identical code with 0.2.0 and 0.3; an
earlier measurement showing it 18% slower was taken on a busy machine.)

### 0.4

aarch64-macos (Apple silicon, native, idle machine; `bench/run.sh -r 7`;
"0.3.0" is the previous release at its default level):

| program | 0.3.0 | 0.4 -O0 | 0.4 -O1 | 0.4 -O2 | seed -O | cc -O2 |
|---|---|---|---|---|---|---|
| collatz | 420 | 2440 | 423 | 431 | 478 | 293 |
| fib | 28 | 55 | 28 | 18 | 29 | 14 |
| interp | 54 | 440 | 94 | 55 | - | 41 |
| matmul | 45 | 496 | 104 | 35 | 94 | 43 |
| nbody | 36 | 299 | 35 | 34 | - | 28 |
| sieve | 67 | 265 | 66 | 64 | 67 | 71 |
| stencil (new: 2D five-point, f64) | 31 | 241 | 32 | 26 | - | 8 |
| md5 | 119 | 381 | 164 | 73 | 132 | - |

md5 is 39% faster than 0.3, fib 36% (tail recursion elimination halves the
calls), matmul 22% (strength reduction of its addresses; it now beats
clang). collatz is 3% slower: rotation leaves a loop-carried value that the
linear-scan allocator cannot keep in one register, which costs a move and a
jump on one path; that is 0.5's register allocator. stencil is 3× behind
clang, which vectorizes it (0.8), and keeps bounds checks whose proof needs
the caller's lengths (0.6).
### 0.5

aarch64-macos (Apple silicon, native, idle machine; `bench/run.sh -r 7`;
"0.4.0" is the previous release at its default level):

| program | 0.4.0 | 0.5 -O0 | 0.5 -O1 | 0.5 -O2 | seed -O | cc -O2 |
|---|---|---|---|---|---|---|
| collatz | 432 | 2437 | 293 | 292 | 475 | 292 |
| fib | 18 | 55 | 31 | 17 | 29 | 14 |
| interp | 56 | 440 | 79 | 44 | - | 40 |
| matmul | 34 | 495 | 87 | 27 | 94 | 43 |
| nbody | 35 | 299 | 33 | 32 | - | 28 |
| sieve | 70 | 263 | 66 | 63 | 69 | 71 |
| stencil | 26 | 242 | 22 | 22 | - | 9 |
| md5 | 73 | 381 | 149 | 72 | 132 | - |

Geometric means: the seed's Cranelift code is 1.81× slower than 0.5 -O2
on the five programs it can build; 0.5 -O2 is 1.11× slower than clang -O2
on the seven with a C version, and 3% faster without stencil (which clang
vectorizes: 0.8). collatz now matches clang (a branch-free `tst`/`csinc`
loop), interp is within 10% (threaded dispatch by tail duplication).

A larger program: release 0.1.0's compiler (7,562 lines, branchy, many
small functions; its source made acceptable to 0.5 by turning `extern fn`
into blocks and renaming its `size_of`/`align_of`), built by the seed and
by 0.5, compiling its own source. All builds print identical output.

| | seed -O | 0.5 -O2 | 0.5 -O0 |
|---|---|---|---|
| 30 runs (best of 5, ms; ~38 ms of it is process start) | 230 | 175 | 461 |
| executable size (bytes) | 207,496 | 243,208 | 306,088 |
| build time, to an executable (ms) | 71 | 509 | 305 |
| of which the compiler itself (to `.s`, ms) | - | 83 | - |

0.5 -O2 code runs about 1.4× faster than the seed's here. The compilers
themselves are about as fast; the end-to-end build is slower because
tachyon emits textual assembly (about 1 MB here) that `cc` assembles.

### 0.6

aarch64-macos (Apple silicon, native, idle machine; `bench/run.sh -r 7`;
"0.5.0" is the previous release at its default level):

| program | 0.5.0 | 0.6 -O0 | 0.6 -O1 | 0.6 -O2 | seed -O | cc -O2 |
|---|---|---|---|---|---|---|
| collatz | 292 | 2516 | 293 | 292 | 478 | 293 |
| fib | 18 | 55 | 21 | 14 | 30 | 14 |
| interp | 42 | 443 | 79 | 44 | - | 40 |
| matmul | 28 | 503 | 76 | 27 | 93 | 43 |
| nbody | 33 | 301 | 33 | 33 | - | 28 |
| sieve | 61 | 266 | 64 | 64 | 69 | 72 |
| stencil | 22 | 243 | 22 | 13 | - | 9 |
| md5 | 73 | 383 | 151 | 74 | 134 | - |

Geometric means: the seed's Cranelift code is 1.88× slower than 0.6 -O2;
0.6 -O2 is level with clang -O2 over the seven programs with a C version
(1.006×; stencil, which clang vectorizes, is 1.44×), and 5% faster than
clang without stencil. fib now matches clang (shrink-wrapping: its base case touches no
stack); stencil's bounds checks are all proven away (constants from its
caller, ranges of sums and products). interp is 2% slower than with 0.5.0
(43 against 44 ms, repeatably): to look at in 0.7. sieve's 61 against 64
is within the run-to-run noise of this machine for that program.

Compile time (new in the gate from 0.6). The same input for both
compilers, the 0.6 phase-1 source of the compiler (35,800 lines), to
assembly, best of 11:

| | -O0 | -O2 |
|---|---|---|
| 0.5.0 | 63 ms | 583 ms |
| 0.6.0 | 38 ms | 466 ms |

The 0.6 compiler building itself (39,200 lines): 42 ms at -O0 and 510 ms
at -O2 to assembly; 2.6 s to an executable at -O2, of which the system
assembler takes about 2 s (0.7 writes object files itself). Per phase at
-O2 (`--time-passes`): the loop passes 27%, register allocation and
emission 22%, inlining and the simplification after it 16%, the scalar
pipeline 11%, the interprocedural layer 4.5%, the front end 8%.

### 0.7

Compile time, the compiler building itself (the 0.7 source, about 40,000
lines; aarch64-macos, idle machine, best of 7), to an executable:

| | -O0 | -O2 |
|---|---|---|
| 0.6.0: assembly, then `cc` assembles and links | 1867 ms | 2734 ms |
| 0.7: the object written by the compiler, `cc` links | 119 ms | 616 ms |
| of which the compiler (to the object) | 94 ms | 594 ms |

15.7× and 4.4× faster end to end: the system assembler took about 1.8
s to assemble the 5 MB of text; the compiler's own assembler, reading the
same text, about 45 ms. The test suite's wall time is unchanged (17.4 s,
mostly starting and linking 315 programs). Run time: the code is the same
as with 0.6 (the objects hold exactly the assembly 0.6 would write).

### 0.9

Compile time, the compiler building itself to an object (the 0.9 source,
about 44,000 lines; aarch64-macos, `--time-passes` total, best of 5; 0.9
with `--allow-unsafe`):

| | -O0 | -O2 |
|---|---|---|
| 0.8.0 | 87 ms | 670 ms |
| 0.9 | 86 ms | 703 ms |
| 0.9, `--no-egraph` | | 671 ms |

The unsafe checks and traits cost nothing measurable; the e-graph's
rewrite rules cost 4.7% at -O2 (within the 10% allowed).

### 0.10

aarch64-macos (Apple silicon, native; `bench/run.sh -r 5`; "0.9.0" is
the previous release at its default level):

| program | 0.9.0 | 0.10 -O0 | 0.10 -O1 | 0.10 -O2 | cc -O2 |
|---|---|---|---|---|---|
| collatz | 293 | 2443 | 292 | 291 | 292 |
| fib | 13 | 54 | 22 | 13 | 14 |
| interp | 42 | 444 | 77 | 44 | 40 |
| matmul | 26 | 495 | 74 | 18 | 43 |
| nbody | 33 | 296 | 32 | 32 | 28 |
| sieve | 63 | 254 | 59 | 69 | 71 |
| stencil | 16 | 242 | 21 | 10 | 10 |
| md5 | 35 | 164 | 38 | 35 | - |

The vectorizer makes matmul 2.4× faster than clang -O2 and brings stencil
level with it. sieve's 63 against 69 is this machine's noise for that
program (58 to 64 ms in repeated runs of either build). interp is about
5% slower with the vectorizer than without it (`--no-vectorize`): its
run-time guards on loops that gain nothing; a cost model for the
vectorizer is for 0.11.

Compile time, the compiler building itself to an object, best of 7:
-O0 109 ms with 0.9.0, 113 ms with 0.10; -O2 791 ms and 816 ms (+3%, the
vectorizer and profile support).

### 0.11

aarch64-macos (Apple silicon, native, idle machine; `bench/run.sh -p
<0.10.0> -r 9`, the fastest of 9 runs in ms; "0.10.0" is the previous
release at its default level; the last row is the geometric mean of each
column over cc -O2's, programs with a C version only):

| program | 0.10.0 | 0.11 -O2 | cc -O2 |
|---|---|---|---|
| binarytrees | 169 | 156 | 163 |
| collatz | 291 | 292 | 295 |
| fannkuch | 125 | 118 | 142 |
| fib | 14 | 14 | 14 |
| interp | 42 | 41 | 42 |
| json | 115 | 109 | 93 |
| mandelbrot | 170 | 171 | 166 |
| matmul | 20 | 19 | 44 |
| nbody | 33 | 32 | 29 |
| sieve | 67 | 70 | 79 |
| sort | 92 | 64 | 59 |
| stencil | 8 | 8 | 8 |
| wordcount | 96 | 89 | 71 |
| md5 | 37 | 37 | - |
| geomean vs cc -O2 | 1.004 | 0.953 | 1 |

(-O0 and -O1 in the same run: geomean 6.689 and 1.344.) No program is
slower than with 0.10.0 beyond noise. The three rows where 0.11 is not
ahead were measured again, alternating the two builds, best of 25:
sieve's object is byte for byte 0.10.0's (62.7 against 63.5 ms: noise),
collatz's runs 291.9 against 291.8 ms, mandelbrot 165.4 against 161.1
ms. sort is 30% faster (branches on `&&` threaded, ranges through phis),
wordcount 7% and json 5% (equalities from branches, division by
constants), fannkuch 6% (unrolling with run-time trip counts; its copy of
10 elements unrolled whole rather than vectorized, which had cost it 5%
since the ranges through phis: optimizer.md, 0.11); binarytrees' 8% is
mostly this machine's spread for it (155 to 176 ms with either build).
What remains against clang (bounds checks, FMA) is in optimizer.md, 0.11.

Compile time (aarch64-macos, idle machine, wall time, best of 7, the two
compilers alternating on the same input: the 0.11 source, 71,900 lines):

| | 0.10.0 | 0.11 |
|---|---|---|
| the compiler to an object, -O0 | 157 ms | 143 ms |
| the compiler to an object, -O2 | 1208 ms | 1206 ms |
| to an executable (`cc` links), -O0 | 184 ms | 171 ms |
| to an executable (`cc` links), -O2 | 1231 ms | 1232 ms |
| `tachyonc check compiler/src/main.tach` | | 44 ms |
| `tachyonc query refs vector_unroll` | | 49 ms |

The 0.11 compiler, built by itself, compiles the same input at -O2 as
fast as 0.10.0 (its new passes cost about what its better-optimized code
saves) and 9% faster at -O0. `check` (the front end only) and a query
answer in under 50 ms.

### 0.12

aarch64-macos (Apple silicon, native; `bench/run.sh -p <0.11.0> -r 9`,
the fastest of 9 runs in ms, run after the gate on a machine with other
work on it, load average about 5; "0.11.0" is the previous release at
its default level; the last row is the geometric mean over cc -O2's,
programs with a C version only):

| program | 0.11.0 | 0.12 -O2 | cc -O2 |
|---|---|---|---|
| binarytrees | 174 | 179 | 172 |
| collatz | 293 | 291 | 292 |
| fannkuch | 116 | 116 | 139 |
| fib | 14 | 14 | 14 |
| interp | 42 | 44 | 40 |
| json | 107 | 107 | 92 |
| mandelbrot | 162 | 162 | 156 |
| matmul | 18 | 18 | 43 |
| nbody | 31 | 31 | 28 |
| sieve | 62 | 63 | 71 |
| sort | 63 | 63 | 58 |
| stencil | 8 | 8 | 8 |
| wordcount | 84 | 84 | 70 |
| md5 | 35 | 36 | - |
| geomean vs cc -O2 | 0.957 | 0.963 | 1 |

(-O0 and -O1 in the same run: geomean 6.843 and 1.344.) The generated
code is 0.11.0's byte for byte: `tachyonc same-output` against the
0.11.0 compiler is identical over the whole corpus (4,668 compilations:
tests/run, examples, bench and compiler/src, four targets, -O0 to -O2),
so the differences above are this machine's spread (the gate's own
`--only bench` run, with the containers just stopped, had binarytrees
151 against 157 and mandelbrot 181 against 165, each way).

Compile time (aarch64-macos, wall time, best of 7, the two compilers
alternating on the same input: the 0.12 source, 77,400 lines in 172
files):

| | 0.11.0 | 0.12 |
|---|---|---|
| the compiler to an object, -O0 | 163 ms | 165 ms |
| the compiler to an object, -O2 | 1316 ms | 1315 ms |
| to an executable (`cc` links), -O0 | 194 ms | 195 ms |
| to an executable (`cc` links), -O2 | 1347 ms | 1350 ms |
| `tachyonc check compiler/src/main.tach` | 60 ms | 60 ms |
| `tachyonc query refs run_gvn` | 65 ms | 66 ms |

The same within noise, as expected of a reorganization that changes no
output (the 0.11 numbers above were on the 0.11 source, 71,900 lines; the
split into 172 files costs nothing measurable).

The gate (`bootstrap/gate.sh --release`, every step at once on
aarch64-macos and in the two Linux containers): 11:54 wall, every step
passed.

### 0.13

aarch64-macos (Apple silicon, native; `bench/run.sh -p <0.12.0> -r 9`,
the fastest of 9 runs in ms, run after the gate on a machine with other
agents' work on it, load average 5 to 7; "0.12.0" is the previous
release at its default level; the last row is the geometric mean over
cc -O2's, programs with a C version only):

| program | 0.12.0 | 0.13 -O2 | cc -O2 |
|---|---|---|---|
| binarytrees | 179 | 189 | 189 |
| collatz | 323 | 316 | 333 |
| fannkuch | 132 | 135 | 157 |
| fib | 16 | 15 | 19 |
| interp | 64 | 47 | 47 |
| json | 127 | 110 | 97 |
| mandelbrot | 175 | 173 | 168 |
| matmul | 19 | 19 | 46 |
| nbody | 32 | 32 | 29 |
| sieve | 64 | 66 | 70 |
| sort | 64 | 69 | 60 |
| stencil | 8 | 8 | 8 |
| wordcount | 86 | 85 | 72 |
| md5 | 36 | 36 | - |
| geomean vs cc -O2 | 0.966 | 0.939 | 1 |

(-O0 and -O1 in the same run: geomean 6.770 and 1.359.) The generated
code is 0.12.0's byte for byte: `tachyonc same-output` against the
0.12.0 compiler is identical over the whole corpus (4,668 compilations,
as for 0.12), so the differences above are this machine's spread under
load: interp's 64 against 47 ms and json's 127 against 110 are the same
code, and a first run a few minutes earlier, load average 9 to 11, had
binarytrees at 319 against 224 ms and a geomean of 0.983 against 0.987.

Compile time (aarch64-macos, wall time, best of 7, the two compilers
alternating on the same input: the 0.13 source, 90,000 lines in 209
files; the same loaded machine, load average 5 to 7, so every row is
slower than 0.12's on an emptier one):

| | 0.12.0 | 0.13 |
|---|---|---|
| the compiler to an object, -O0 | 205 ms | 204 ms |
| the compiler to an object, -O2 | 1613 ms | 1633 ms |
| to an executable (`cc` links), -O0 | 230 ms | 228 ms |
| to an executable (`cc` links), -O2 | 1713 ms | 1738 ms |
| `tachyonc check compiler/src/main.tach`, no cache | 74 ms | 73 ms |
| `tachyonc query refs run_gvn`, no cache (`TACHYON_CACHE=off`) | 80 ms | 86 ms |
| `tachyonc check compiler/src/main.tach`, cache warm | | 6.8 ms |
| `tachyonc query refs run_gvn`, cache warm | | 7.2 ms |

Compiling is the same within noise (the -O2 rows 1 to 1.5% apart, the
output identical). Without the cache, `query refs` is a few ms slower
than 0.12.0's (best of 15 again: 87 against 91 ms); with the cache warm,
`check` and `query refs` answer in about 7 ms, ten times faster than
reading the program.

### 0.14

aarch64-macos (Apple silicon, native; `bench/run.sh -p <0.13.0> -r 9`,
the fastest of 9 runs in ms, run after the gate on a machine with other
agents' work on it, load average falling from 10 to 4 during the run;
"0.13.0" is the previous release at its default level; the geometric
means are over cc -O2's, programs with a C version only):

| program | 0.13.0 | 0.14 -O2 | cc -O2 |
|---|---|---|---|
| binarytrees | 157 | 160 | 158 |
| collatz | 317 | 328 | 316 |
| fannkuch | 126 | 120 | 145 |
| fib | 14 | 14 | 14 |
| interp | 43 | 44 | 43 |
| iterchain | - | 420 | 199 |
| iterloop | 408 | 407 | 186 |
| json | 110 | 109 | 95 |
| mandelbrot | 173 | 175 | 167 |
| matmul | 19 | 19 | 46 |
| nbody | 32 | 32 | 29 |
| sieve | 67 | 66 | 73 |
| sort | 65 | 60 | 57 |
| stencil | 8 | 8 | 8 |
| wordcount | 87 | 92 | 75 |
| md5 | 38 | 39 | - |
| geomean vs cc -O2, the 14 programs both compile | 1.017 | 1.016 | 1 |
| geomean vs cc -O2, with iterchain (run.sh's) | | 1.067 | 1 |

(-O0 and -O1 in the same run: geomean 7.998 and 1.643, with iterchain.)
iterchain (0.14's iterators and closures; 0.13.0 cannot compile it) over
iterloop (the same six kernels as loops by hand), alternating, fastest
of 18 rounds: 420 against 407 ms, a ratio of **1.032** (the limit is
1.05). Both are about 2.2 times cc -O2's (186 to 199 ms): the hand loops
themselves, not the iterators, are what C does better there.

The generated code changed (the optimizer's passes for iterator chains,
std's introsort, std's unreachable functions dropped), so the
differences can be real. An alternating rerun of the programs that
moved (fastest of 15 each, load average 4) tells which: sort is faster,
65 against 60 ms both times, std's introsort (bench/sort.c follows it,
so cc's time moved too: 60 to 57); wordcount (95 against 93 ms),
collatz (314 against 315), fannkuch (120 against 118), binarytrees (157
against 160) and json (110 against 109) are the same within noise. The
geomean over the programs both compile is the same; the one run.sh
prints is higher because it counts iterchain, new, and at about 2.1
times C, like its hand-written twin.

Compile time (aarch64-macos, wall time, best of 7, the two compilers
alternating on the same input: the 0.14 source, 98,000 lines in 221
files; load average about 3.5; two runs, the first shown, the second
the same within a few percent each way but for a busier `check`):

| | 0.13.0 | 0.14 |
|---|---|---|
| the compiler to an object, -O0 | 226 ms | 231 ms |
| the compiler to an object, -O2 | 1901 ms | 1950 ms |
| `tachyonc check compiler/src/main.tach`, no cache | 79 ms | 81 ms |
| `tachyonc query refs run_gvn`, no cache (`TACHYON_CACHE=off`) | 93 ms | 103 ms |
| `tachyonc check compiler/src/main.tach`, cache warm | 6.7 ms | 6.9 ms |
| `tachyonc query refs run_gvn`, cache warm | 7.0 ms | 7.3 ms |
| a 7-line std program to an object, -O2 | 4.4 ms | 4.7 ms |

0.14 is 2 to 3% slower to compile the compiler, in both runs: at -O2,
`--time-passes` puts the difference in the scalar pipeline (176 against
190 ms) and the loop passes (598 against 611 ms), where the passes for
iterator chains run (copy elision, SROA to a fixpoint, threading on
constant tags, exit merging); the front end is the same (check 45 ms in
both). `query refs` without the cache is about 10% slower in both runs
(93 against 103, 105 against 118 ms), not investigated; with the cache
warm, every query is about 7 ms as in 0.13. The tiny std program
compiles in about the time 0.13.0 takes (std's unreachable functions
dropped before the optimizer).
