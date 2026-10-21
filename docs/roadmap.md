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

Done (0.15.0). The design
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
Also in 0.15: the optimizer closed the gap to C on loops (if-conversion,
vector masks and minimum/maximum reductions, one accumulator per copy in
the run-time unroller, `ldp`/`stp`: bench/iterloop from about 2.1 to 1.04
times cc -O2); ten algorithm examples and eight tool sessions (tested
transcripts); 772 tests. From 0.15 the gate leaves x86_64 out
(`bootstrap/gate.conf`; `--with-x86`): the work is on the language and the
evals, and the emulated container was half the gate's machine time.

0.15.0 release gate (2026-10-15): `bootstrap/gate.sh --release` on
aarch64-macos, 85:47 wall, with the machine just rebooted and other
agents' work on it (load average 15 to 4): the chain (fixpoint, built by
0.14.0) and the suite at -O0/1/2 (772 tests); fuzz 60 in each of the ten
modes (the seed in one), ABI 100 in three modes, objcheck (1216 of
1216), header layouts, stress-grow; aarch64-linux (the cross-built
fixpoint, the suite at every level, fuzz 300 in nine modes, ABI 150 in
three, objcheck, layouts, gdb at -O0 and -O2). The lldb check failed in
that run at -O0 and -O2 alike: lldb waited about 80 minutes without
running the program; the line table it checks is the same as before the
optimizer's changes, and the step passed alone afterwards (`gate.sh
--only debug`); tests/debug.sh now bounds each lldb run. x86_64-linux
ran once and failed only the walkthrough sessions (the compiler's path
in their transcripts, fixed in f1cb343); it was not run again (x86_64
off from 0.15). Benchmarks and compile times in "Benchmarks", 0.15.

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

Done (0.16.0). The design (docs/design/effects-allocation.md, with the
user's decisions: allocation strictly explicit, no ambient allocator),
an interface commit with stubs, and six parallel tasks: effects
(inference over the call graph per instance, through `fn` values and C,
declarations and `effects(..)` bounds checked, why-chains,
`--verify-effects`); allocators (`Allocator`, `Gpa`, arenas with scoped
arenas, `FixedBuf`, `#[sealed]` and `#[scoped]`, a `Fmt` that never
allocates, std's loops counted so growing a Vec does not diverge);
`--check-alloc` (a checking Gpa: pages of their own, never reused; arenas
routed through it); the optimizer (pure calls value-numbered and hoisted
from the inferred effects, arena allocation without a call, the gaps the
algorithm examples showed); the tools (`fix --only alloc016`, which moved
the whole corpus, `query effects`, the guide's `effects` and `allocators`
topics); the compiler's source on 0.15's features. Decided at
integration: `a.scope(..)` is `alloc(Arena)`, the arena's own use of Gpa
its business; std's `Eq`/`Ord`/`Hash` `#[pure]`; `fix --only alloc016`
also rewrites the reads of sealed fields. Also in 0.16: link inputs on
the command line (`x.c`, `x.o`, `-l`, `-L`); the examples in folders with
READMEs, C interop and language tours; compiler tasks in the agent eval
(tools against plain). Moved: naming an allocator by value in effects
(`alloc(arena)` for a parameter: only types now) to 0.17, with values
that carry their allocator; memoizing pure calls across the program
(numbering and hoisting are done) to a later optimizer release; the
lru-cache gap (the probe loop around an out-of-line `HashMap::insert`,
which the capture analysis does not prove non-capturing) and a widening
multiply-accumulate on x86_64 to a later perf task; the effects and
allocators examples made the gate (examples/effects,
examples/allocators, nine tested sessions).

0.16.0 release gate (2026-10-15): `bootstrap/gate.sh --release` on
aarch64-macos, 5:52 wall (load average 15 to 30 from other agents'
work): the chain (fixpoint, built by 0.15.0), the suite at -O0/1/2
(938 tests); fuzz 60 in each of the ten modes (the seed in one), ABI 100
in three modes, objcheck (1512 of 1512), header layouts, lldb at -O0 and
-O2, stress-grow, and the new examples-checkalloc (every example's test
built with `--check-alloc`, 87 cases); aarch64-linux (the cross-built
fixpoint, the suite at every level, fuzz 300 in nine modes, ABI 150 in
three, objcheck, layouts, gdb). Two earlier runs failed only on time
(two algorithm examples at -O0 and one checked example past 20 s under
load 30): the gate now gives each test program a minute. x86_64 not
run (off from 0.15). Benchmarks and compile times in "Benchmarks", 0.16.

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
- compile speed, part 1 (a parallel track, back end only, independent of
  the value-semantics work): a profiling pass over `--time-passes` and
  hot front-end routines (interning, lookups by linear scan); the
  middle and back end restructured into a per-function pipeline with
  function-local IR ids (the prerequisite for both per-function arenas
  and parallel code generation, measured in the 0.16 arena prototype:
  the IR in flight drops from 185 MB to about 1.5 MB); cheaper f-strings: today each one becomes four functions (a closure,
  its environment, an `Interp` instance and a Display instance) that -O0
  and -O1 do not inline, which made the compiler's own -O0/-O1
  self-compile 3–4% slower when it adopted f-strings in 0.16; lower an
  f-string passed straight to print/format/push_fmt into direct `Fmt`
  calls, and let -O1 inline small leaf functions

Done (0.17.0). The design (docs/design/value-semantics.md), a prototype
measured on 7,413 functions (branch c17-proto, §8), Revision 1 after it,
the user's decisions (U1–U4: Rust's spelling `&T`/`&mut T`, slices split
into read-only `[T]` and exclusive `&mut [T]`, errors in 0.17.0 with
`--values=warn` as a one-release opt-out; V1–V3: inferred view
summaries, an 8% budget for the pass, warnings for summary-only
conflicts had summaries slipped, which they did not), a Phase 0
contract, then seven tasks: moves and drops (T1: implicit defers, drop
glue, drop flags, `own.moved`/`move_out`/`partial`/`drop_view`); views
and exclusivity (T2: two-level origins, reborrows, two-phase receivers,
`own.conflict`/`escape`/`static`/`readonly`, the fast path over 4,450 of
6,586 functions); inferred view summaries (T3: over the effects'
components, parametric generics, the type filter, `#[views]`/`#[stores]`,
`query views`); std on values (T4); the optimizer (T5: noalias and
read-only facts from reference parameters, NRVO, moves elided in loops);
the tools (T6: `query own`, `explain own.*`, `fix --values`,
tests/own-try); the migration (T7: `fix --values` over tests, examples,
bench and the eval, `--values=error` the default). Also in 0.17, in
parallel: compile speed, part 1 (the profile, function-local IR ids, the
per-function pipeline, -O1 leaf inlining, f-strings written in place);
the night of 10-15's agent-efficiency work (the familiar forms, `fix
--suggested`, the debugging tools, the 2k core guide, the hooks;
docs/eval/0.17-iterations.md); the `&factorial` diagnostic (issue #1);
struct-like enum variants. Decided at integration: implicit drops only
under `--values=error`; the own pass's cost at about 8.5% of 0.16's
checker (the pass 6.3% of the checker, the checker 2% slower for the
record that makes it so) against the 8% budget, accepted for 0.17.0.
Not done: the compiler's source on effect annotations (0.16), with the
compiler's move to value semantics in 0.18.

The release gate (`gate.sh --release --no-x86` on aarch64-macos, 6:51
wall, every step passing; x86_64 not run, by instruction): the chain
(fixpoint, built by 0.16.0) and the suite at -O0/1/2 (1114 tests, 3
XFAIL); fuzz 60 in each of the ten modes, ABI 100 in three modes,
objcheck 1728 of 1728, header layouts, lldb at -O0 and -O2, stress-grow,
examples-checkalloc (87); aarch64-linux (the cross-built fixpoint, the
suite at every level, fuzz 300 in nine modes, ABI 150 in three, objcheck
1728, layouts, gdb). The first two runs failed, and each failure was
fixed before the tag: objcheck built the programs 0.17's migration marks
`// FLAGS: --values=off` without their flags (it now reads each case's
directives with the suite's reader, tests/directives.awk); on
aarch64-linux the compiler stopped in opt_slp at -O2 (glibc: "corrupted
size vs. prev_size"): the SLP vectorizer's tables by instruction were
sized once per pass, which function-local ids made too small for a
function whose packing adds more than half again its instructions
(tests/run/opt_slp_grow); and once a "Bus error" at -O1 on macOS
(fmt_direct), which valgrind showed as a read before the own pass's
place masks when a dropped local had no place, in a function past 64
places (tests/run/own_many_places). Valgrind on aarch64-linux then found
nothing on the `opt_*`, `own_*` and `fmt_*` tests, the bench programs or
the compiler's -O2 self-compile. Benchmarks and compile times in
"Benchmarks", 0.17.

Moved to 0.17.1:
- the own pass's cost back under the 8% budget (at least 0.5%: a cheaper
  per-function record, or std's instances skipped);
- projections: `-> &T`, `-> &mut T`, references as type arguments,
  `HashMap::get_mut -> Option<&mut V>`, `iter_mut`, `&T` binding types
  (a `for` over `next()`, a match through a reference); `&&mut T` parsed;
- written-static sets in effects and summaries naming statics
  (`views(TYPES)`), stores into statics through calls, `&S` passed to a
  `global` function;
- arena handles as references (`Vec<T, &Arena>`, safe `reset` and
  `free_all`, `Drop` for Arena, `fix --only alloc017`; U3), `FixedBuf`
  views, allocators named by value in effects (`alloc(a)`, 0.16's U2);
- the drops T1 left: owned temporaries other than `e;` (method
  receivers, `let _ = e`, f-string holes: leaks, safe), by-value closure
  parameters, an assignment through an index (leaks the old value, safe),
  the error for calling `x.drop()`;
- the checks T7 left: `extend_from_slice` on owned elements (clone under
  `T: Clone`), a `Vec<[u8]>` element from `iter()` viewing the Vec
  (XFAIL own_iter_elem_views), `v.as_slice()[0] = x` and `&mut s[..]` of
  a read-only `s` as own.readonly, a closure parameter's call as a legacy
  `self: *Self` store, a Vec made on an allocator copied out of `*p`;
  why-chains through locals and matches, the type filter on stores,
  `query own`'s state gaps, closures/escape.tach folded into the own pass;
- `fix --values`: written slice locals (`as_mut_slice()`, 45 of the eval
  solutions' 92 errors), `&mut *c` for a `&T` local, a slice passed to C;
- the optimizer: noalias scopes through inlining (per-instruction tags),
  a moved argument passed by the caller's slot without its copy;
- `*T` parameters deprecated (a warning) ahead of 0.18 making them raw,
  and per-target `stores`, if the evals ask for it;
- a small focused eval of 0.17's value rules: of the 0.16-era eval
  solutions as agents wrote them, 14 of 18 are rejected under the new
  default (written `[T]` in 9 tasks, handle moves, views of leaked Bufs,
  ledger's two `get_mut`, legacy `*T` conflicts);
- V4 (design §7), decided by the user on 2026-10-16: every `*T` becomes
  raw in 0.18.1 (see 0.18).

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
- compile speed, part 2: functions optimized and emitted in parallel on a
  small thread pool inside the compiler (an `unsafe` island over the
  platform's threads until 0.21 brings std concurrency); output
  byte-identical whatever the thread count, checked by the gate; goal:
  the self-compile at -O2 several times faster on a 10-core machine and
  peak memory down by most of today's ~700 MB; incremental rebuilds:
  unchanged functions reuse their optimized code from the cache that
  already serves the query tools
- the language specification waits for 0.23 (see "After 0.23: the
  specification")
- 0.18.1: once compiler/src has migrated to `&`/`&mut` (with the
  compiler-on-values work above), the legacy rule that a non-`mut` `*T`
  parameter is accepted as `&mut T` is removed (V4 in
  docs/design/value-semantics.md §7, decided by the user on 2026-10-16):
  from then on every `*T` is a raw pointer, as Rust's are (a dereference
  needs `unsafe`), `mut` or not, and borrowing is only `&` / `&mut`

Done (0.18.0). The design (docs/design/contracts-verification.md, with
the decisions taken for the user's review: contracts always checked, a
requires checked at the call and blaming the caller, facts only from
checks that ran, one failure line, Rust's `#[test]`, test modules
without `use super::*`, Go's defined types, `NonNull<T>` with a null
niche), a phase 0 that reads the syntax, and four tasks built in
parallel on 0.17 before its value semantics, then merged onto v0.17.0:
contracts and check positions (T1, T5: `requires`/`ensures`, the
assertions, std's clauses, the site table and one failure line, `query
checks`, `--no-positions`); tests and properties (T2: `#[test]`,
`#[cfg(test)]`, snapshots, `#[property]` with generated, shrunk inputs,
`tachyonc test` comparing -O0 and -O2); fuzzing and reduce (T3:
`--coverage`, `#[fuzz]`, `tachyonc fuzz`, `reduce --differs/--fails/
--test`); distinct types and `NonNull` (T4: the null niche, the checked
cast). Also in 0.18: std's `Display`, `Debug`, `Iterator` and `Clone`
on references and `fix --values` over traits, with the corpus moved;
the eval harness's `+debrief`. Decided at integration (each with a
test): a requires check reads the call's arguments in place; `old(..)`
of a by-value owned parameter or of a view is `contract.old`; distinct
types only over plain types (not a reference, not a `Drop` type);
generators take `&mut Gen`; property and fuzz cases are leak-checked;
the test runtime and the fuzzer are lazy std sections; the `note: build
with --trace` line is gone. V4 was decided by the user (below). Not
done in 0.18.0, and now 0.18.1's: the compiler's source on values and
arenas, functions compiled in parallel, incremental rebuilds.

The release gate (`gate.sh --release --no-x86` on aarch64-macos, 9:58
wall, every step passing; x86_64 not run, by instruction): the chain
(fixpoint, built by 0.17.0) and the suite at -O0/1/2 (1168 tests, 3
XFAIL); fuzz 60 in each of the ten modes, ABI 100 in three modes,
objcheck 1820 of 1820, header layouts, lldb at -O0 and -O2, stress-grow,
examples-checkalloc (87); aarch64-linux (the cross-built fixpoint, the
suite at every level, 1167 and nonnull_cimport skipped, fuzz 300 in
nine modes, ABI 150 in three, objcheck 1820, layouts, gdb). Its first
runs found, and the release fixed before the tag: the check-site table
wrote each file's path as given, so the compiler built in the
aarch64-linux container differed from the cross-built one (every path
the compiler writes into its output is now relative to the root's
directory, tests/refactor/paths018; -g's `.file` names the root's
directory joined with it); GNU as refused the contract companions'
`f?pre` symbols (now `f$pre`, tests/refactor/symbols018);
nonnull_cimport tested clang's `_Nonnull` where cc is gcc (`// REQUIRES:
clang`); and the benchmarks found iterchain 5.8% slower in instructions
than 0.17.0, from the b18-contracts merge: dot's loop was unrolled
twice, not four times, because a constant only its checks' cold failure
calls read counted in the unroller's size (no longer,
tests/run/opt_unroll_exit_consts). Measuring the compile times then
found out_path calling realpath for every file (twice 0.17.0's -O0
self-compile under a large directory): paths are now made relative by
their text. Benchmarks and compile times in "Benchmarks", 0.18.

Moved to 0.18.1:
- the compiler's source on value semantics and arenas (design §4.1,
  §4.2): the front end's tables as `Vec<T, Comp>`, the syntax tree's
  arena released after lowering, `FnCtx`/`Program` for middle, back and
  gen0, per-function IR arenas;
- compile speed, part 2: functions optimized and emitted in parallel
  (§4.3; in progress on branch p181-par), output byte-identical for every
  `-j`, checked by the gate; incremental rebuilds from the per-function
  cache (§4.4);
- V4: once compiler/src uses `&`/`&mut`, the legacy rule that a non-`mut`
  `*T` parameter is a borrow is removed (decided 2026-10-16), and every
  `*T` is raw;
- contracts: the checking entry for calls through `fn` values and trait
  objects (they skip a requires today), hence facts at the callee's
  entry and std's body checks removed behind its requires; facts from
  `ensures` on call results (`middle::ipo`); type invariants and
  `contract.sealed`; `contract.violated` at compile time,
  `contract.impl-requires` and clauses on trait methods; `macro.args`;
  values other than integers in failure lines; `query effects --why`
  naming a clause; `Vec::get`'s body check behind its requires when the
  length goes through `as_slice`;
- tests: `probe --test/--seed`, `--against CMD --gen CMD`, `test --fuzz
  S`, failing property inputs saved to a corpus, effects (no io, no
  global) required of contracts tested as properties, the bang spellings
  in try: lines and kept by `fmt`, a leak's site naming the property
  rather than the generated `<test>` source;
- reduce: expressions replaced by literals, calls inlined, several
  files, candidates checked in the process;
- distinct types: field access through a distinct struct, `!` on a
  distinct bool, a distinct type's `invariant`;
- the gate: the level comparison over tests/run as `tachyonc test` runs
  it, a fuzz mode whose programs carry clauses, the `-j` and incremental
  byte comparisons, `TACHYON_ARENA_SHUFFLE`, a valgrind row on
  aarch64-linux (0.17.0's gate found two heap bugs macOS hid), a lock on
  bootstrap.sh's shared release cache;
- compile time: std's text built by section as it is loaded (a small
  program compiles with about 10 M more instructions than with 0.17.0,
  "Benchmarks", 0.18);
- 0.17.1's list (above) stands.

Done (0.18.1). Code generation on threads (T7: `-j N`, the per-function
state in `FnCtx`, byte-identical output for every N, tests/threads.sh)
and incremental rebuilds (T8: the code cache, tests/incremental.sh); V4
(every `*T` raw; compiler/src and std on references); two use-after-free
holes in safe code closed (a changed copy of a borrowed owned value, a
reference into a Vec across a push); the contracts' evidence in
generated code with two range fixes, `x % n` ranges and entry facts;
the 0.18 eval's polish (BinaryHeap/MinHeap, binding modes on references,
`&f()` temporaries, let-else, `ok:` lines, the check hook applying
fixes, one `len()`); a valgrind row in the gate and a lock on the
bootstrap cache. The release gate's record is in "Benchmarks", 0.18.1.

The release gate (`gate.sh --release --no-x86` on aarch64-macos, 10:57
wall, every step passing; x86_64 not run, by instruction): the chain
(fixpoint, built by 0.18.0), the suite at -O0/1/2 (1532 tests, 3
XFAIL; 325 of them the agent hooks' tests, which need python3), fuzz 60
in each of the ten modes, ABI 100 in three modes, objcheck 1900 of 1900,
header layouts, lldb, threads (2278 compilations the same at -j1 and
-j8), incremental (160 edit series rebuilt as clean builds, 92% hits),
stress-grow, examples-checkalloc (87); aarch64-linux (the cross-built
fixpoint, the suite at every level, 1206, the hooks' tests left out:
no python3 in the container, nonnull_cimport skipped), fuzz 300 in nine
modes, ABI 150 in three, objcheck 1900, layouts, gdb, and the new
valgrind row: 227 compilations clean under memcheck).

Moved to 0.18.2 or 0.19:
- the compiler's source on arenas (design §4.1, §4.2: the front end's
  tables as `Vec<T, Comp>`, the syntax tree's arena released after
  lowering, per-function IR arenas);
- incrementality in the front end, and per-function assembly (the -O2
  -j8 rebuild's serial parts: front end 127 ms, lowering 51,
  interprocedural constants 49, dead functions 36);
- contracts: the checking entry for indirect calls (they skip a
  requires; their callees assume nothing), a `len >= 0` invariant and
  offsets (`i + 4 <= len` against `i + k < len`, window's +24%), a min
  as a loop bound, rotated loops, non-negative while-loop indices, `query
  checks crate`;
- the Allocator trait's `self: *Self` on references (0.18.0 builds
  compiler/src, so 0.19);
- `HashMap::get_or_insert -> &mut V` and the other reference results
  (0.17.1's projections);
- `check` 7% more instructions than 0.18.0's on the same source (its
  phases are 0.18.0's; the difference is in the command around them);
- the items of 0.18.1's list above not named here, and 0.17.1's.

## After 0.18: a standard library, and a real program on it

Planned with the user on 2026-10-14, to start once 0.18 has shipped. The
standard library is built with the language of 0.15–0.18 (allocators in
effects, mutable value semantics, contracts), measured against Rust's and
C's, and proven on a real program: a GPU-rendered terminal emulator,
shipped as an example (not a release goal of its own). Each release may
split into .x releases rather than be rushed.

## 0.19: CPU intrinsics and target features (`std::arch`)

Planned with the user on 2026-10-15: direct access to the CPU's
instructions, as Rust's `std::arch`/`core::arch`, without giving up the
no-UB rule. It comes before the standard library build-out, which uses it
(SIMD-probed hash tables, fast text search, checksums).

- `std::arch::aarch64` (NEON, then crc, aes, sha, dotprod; SVE later) and
  `std::arch::x86_64` (SSE2 to SSE4.2, AVX, AVX2, FMA, BMI1/2, POPCNT,
  LZCNT; AVX-512 later): typed intrinsics with the vendors' names
  (`vaddq_u8`, `_mm256_add_epi32`), on 0.10's vector types plus the
  vendor vector types, lowered to single instructions in both back ends
  and understood by the optimizer (no opaque calls)
- portable intrinsics in `std::arch` for every target: `count_ones`,
  `leading_zeros`, `trailing_zeros`, `rotate_left`, `bswap`,
  `prefetch`, `spin_loop`, `wide_mul` (128-bit product), with
  constant folding
- target features: `#[target_feature(enable = "avx2")]` on a function;
  `tachyonc -C target-cpu=native|NAME` and `-C target-feature=+x,-y`; a
  build's baseline features are known at compile time
  (`std::arch::has::<"neon">()` constant-folds)
- no UB: an instruction the CPU lacks must never run. A
  `#[target_feature]` function may be called safely only where the
  feature is known: inside another function with the feature, under the
  build's baseline, or in the branch of a run-time check
  (`if std::arch::detect("avx2") { fast(x) } else { slow(x) }`, checked
  flow-sensitively like a narrowing); elsewhere the call is an error with
  the exact `try:` (wrap in the detect branch). Run-time detection is
  cached (cpuid, `getauxval`/`sysctl`), and multiversioning
  (`#[target_feature]` variants selected once at start-up) is sugar on top
- intrinsics with memory operands (loads, stores, gathers) take slices
  or `&`/`&mut` places (0.17) and check bounds, so they are safe; raw
  pointer forms stay `unsafe`; effects: intrinsics are pure unless they
  touch memory
- tests: every intrinsic checked against a scalar reference on random
  inputs (the fuzzer gains intrinsics), run on aarch64-macos, x86_64
  (Rosetta) and both Linux containers; `tests/objcheck.sh` checks the
  encodings; examples/arch/ shows a SIMD byte search and a checksum
  against their portable versions with timings
- the tools: `query` shows an intrinsic's instruction and feature;
  `guide arch`; `explain` for the feature errors

Done (0.19.0). The design (docs/design/arch.md, decisions D1-D20 taken as
recommended), a phase 0 and eight tasks: vector types (T1), the feature
analysis (T2), detection and `#[multiversion]` (T3), the AArch64
intrinsics (T4: 1,743 in the table at its merge, more with T6's
leftovers), x86-64 (T5: 484, encoded and compile-tested, never run), the
optimizer and the vector convention (T6), the test generator and the
fuzzer's arch mode (T7), the tools, guide and examples (T8). Found and
fixed before the release: LICM hoisting a guarded intrinsic, and a
256-bit load, above its `detect` (undefined behaviour on a CPU without
the feature).

The release gate (`gate.sh --release --no-x86`, 13:03 wall, every step
passing; x86_64 not run, by instruction): the chain (built by 0.18.1),
the suite at -O0/1/2 (1584 tests, 3 XFAIL), fuzz in every mode,
ABI, objcheck 2232 of 2232 and the x86-64 intrinsics' objcheck 240 of
240 (compiled, not run), layouts, lldb, threads (2380), incremental
(160 series, 92% hits), stress-grow, examples-checkalloc (91);
aarch64-linux (fixpoint, the suite at every level, 1257, fuzz, ABI,
objcheck 2232, gdb, valgrind 237 clean). Its first run found
examples/arch/crc32 crashing on aarch64-linux at -O2: main's feature
word was filled before its parameters were taken, and the inlined
getauxval init overwrote argc and argv (fixed,
tests/run/arch_detect_main_args).

Moved to 0.19.x or later (docs/design/arch.md, "as built"):
- AArch64 breadth: `vqtbl2q`/`vqtbx2q`, the float forms whose
  references are not exact yet (`vsqrtq`, `vfmaq_f64`, `vmaxnmq`,
  `vrecpe` and the like), `vbslq_f32`/`f64`, unfused `vmlaq` on floats,
  the f64 64-bit forms, the x3/x4 tuple forms;
- x86-64: running it (when x86 testing returns), gathers and masked
  forms, the string compares, `_mulx_u64`, float-scalar intrinsics,
  `_mm_set_epi*`, alignment checks of the aligned forms;
- the optimizer: `ld1r` fusion, `VConst` literal pools, `Rot`/`BSwap`
  and the vectorizer's portable bit ops, float and x86 folds,
  `Op::IntrMem`; a library's `detect` made pure (hoisted);
- tools: `query arch --features`, examples/arch's utf8 and swissprobe,
  bench pairs, tests/arch-try;
- examples/sha256sum, written with v0.19.0 (as fast as the system's
  sha256sum, openssl and coreutils).

Done (0.19.1). Two soundness fixes (the store intrinsics' destination
`&mut [T]`; 0.17's transitional read-only-slice rule removed, with the
corpus migrated) and examples/arch/sha256sum, written with v0.19.0:
faster than the system's sha256sum and OpenSSL on the M5, about 5 times
coreutils' in the linux/arm64 container.

## 0.20: collections, text and I/O

- collections, each allocator-aware (0.16), with value semantics (0.17),
  iterators, `derive`d traits and contracts:
  - `Vec` (reworked);
  - `VecDeque`;
  - `HashMap` and `HashSet`: an open-addressing, SIMD-probed table (0.19's `std::arch`), with
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

Done (0.20.0). Parameter conventions (docs/design/conventions.md: Phase
0, T1 the semantics, T2 the tools, Phase M the migration and the flip),
std as a module tree with a benchmark harness against Rust and C
(bench/std), the collections (Swiss-table HashMap and HashSet, BTreeMap
and BTreeSet, ipnsort and driftsort, slice algorithms), text (String,
str, std::unicode, number formatting and parsing), I/O and the system
(io, fs, path, env, process, time, random, sys), owned temporaries
dropped at the statement's end, and `tachyonc lsp`
(docs/design/collections-text-io.md for std's parts).

The release gate (`gate.sh --release --no-x86`, 22:15 wall at load up
to 38, rerun of suite-O0 and stress-grow 10:47): the chain (built by
0.19.1), the suite at -O0/1/2 (1661 tests, 2 XFAIL), fuzz in every
mode, ABI, objcheck 2388 and the x86 intrinsics' 240, layouts, lldb,
threads (2530), incremental (160 series, 93% hits), stress-grow,
examples-checkalloc (95); aarch64-linux (fixpoint, the suite at every
level, 1334, fuzz, ABI, objcheck 2388, gdb, valgrind 245 clean). Its
first run found, fixed before the tag: std's SysPath::ptr and
DirEntry::file_name handing out a copied `let` receiver's storage
(wrong output at -O0: std_io, sys_files, sys_process); bench/matmul and
bench/wordcount (a migration to `inout f64` read as raw pointers; a
checksum on std's Hash, now foldhash); the LSP transcripts' version.
example_algorithms-lru-cache at -O0 timed out once under load 38 (4.8 s
alone) and passed on the rerun.

Moved to 0.20.1 or 0.21:
- `fn(T)` and `fn(let T)` one type; std's consuming bounds then
  `Fn(sink T)`;
- a closure's by-value parameter dropped (a leak since 0.19);
- a generic `let` parameter given an rvalue of a non-copyable type
  other than a closure literal;
- `fix --only conventions`: the `&` of an inout argument in an
  f-string hole, `Iterator::at`'s convention in impls;
- `query def` of std's statics' symbols (`tachyon.static.std.X`);
- the own pass over std's own functions (two -O0 wrong-output bugs of
  std slipped through without it before the tag);
- compile time: a small std program does about 270 M more instructions
  than with 0.19.1 (hello world 47 M to 317 M, a few ms), outside the
  timed phases: std's text, much larger as a module tree, built for every
  compilation; `check` of the compiler 13% more;
- the rest of collections-text-io.md not yet done (VecDeque, a
  small-vector and a bitset, property tests against models), and
  compiler/src on 0.20's spelling (0.21's first commit).

## 0.21: concurrency, atomics and synchronization

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

Done (0.21.0). Threads (std::thread's safe spawn and scope, std::sync's
atomics, Mutex, RawLock, Once, Condvar and channels, `#[thread_local]`,
the thread, sync and tls effects, Send and Sync from the types, atomics
on AArch64 as LSE or exclusive pairs and as barriers in the optimizer),
the compiler's source in 0.20's conventions, the 0.19 spelling removed,
`.vl` sources and `VOLE_*` variables accepted. Moved to 0.21.1: the
small-program compile regression of 0.20 (being investigated), the
0.20.1 list of docs/design/conventions.md, `Mutex::lock`'s guard made
safe (Drop on view types), x86-64 atomics run.

## 0.22: GPU support

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

Done (0.22.0). std::gpu on wgpu's model with the Metal backend over
std::objc (resources as values with destructors, the validation rules
as contracts, the per-frame functions allocation-free, tested headless
against CPU results and reference images), std::gpu::wgsl (WGSL to MSL
with reflection, an interpreter as the oracle, faster than naga on the
bench's corpus), std's section index fixed (a hello world 357 M to 96 M
instructions) with a compile-cost gate row, std own-checked. Moved to
0.22.1 or later: SPIR-V and the Vulkan backend, D3D12 and CUDA (one
backend per build until generic structs over associated types work),
the let-as-borrow rule, the closure by-value parameter leak, the own
pass's reading of `Buf<ScopedArena>`.

## 0.23: windows and input in std, and a terminal emulator

- a `window` library in std, in the manner of winit: an event loop,
  windows with a GPU surface (0.22), keyboard (with modifiers and text
  input), mouse, resize, high-DPI scale, a frame clock, clipboard; Cocoa
  on macOS, Wayland then X11 on Linux
- the terminal emulator, an example program (`examples/term`) that
  proves the standard library:
  - a pty and a child shell, its I/O on its own thread (0.21);
  - an xterm-compatible escape-sequence parser (a state machine in the
    manner of vte), a grid with scrollback, alternate screen, 256 and
    true colours, attributes, wide and combining characters (0.20's
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

Done (0.23.0). std::window on Cocoa (winit's objects with events
pulled, behind a gate), voltty in examples/voltty (a core checked
against alacritty_terminal by an oracle and a fuzzer, Core Text glyphs
in an atlas, one instanced draw per frame on std::gpu with its shader
compiled by std::gpu::wgsl, damage tracking, a shell on a pty), and the
rename tools for 0.24. Moved to 0.23.1 or later: Wayland and X11,
selection and copy, the scrollback view and configuration, the
measurements against Alacritty's input latency and memory, fonts through
FreeType and a rasterizer in the language (after 0.24).

## After 0.23: the specification

Decided with the user on 2026-10-16: once 0.23 has shipped, the whole
language is specified thoroughly, its syntax and all of its semantics
(types, values and moves, references and views, effects and
allocation, contracts, generics and traits, modules, unsafe and the C
boundary, concurrency and the memory model, what is and is not
undefined), as a document a reader can check the compiler against. It
is written with the user, and the compiler's behaviour is tested against
it.

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
- the written language specification (after 0.23, above)
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

### 0.15

aarch64-macos (Apple silicon, native; `bench/run.sh -p <0.14.0> -r 9`,
the fastest of 9 runs in ms, after the gate, load average about 5 from
other agents; "0.14.0" is the previous release at its default level; the
geometric means are over cc -O2's, programs with a C version only):

| program | 0.14.0 | 0.15 -O2 | cc -O2 |
|---|---|---|---|
| binarytrees | 174 | 160 | 156 |
| collatz | 311 | 312 | 306 |
| fannkuch | 119 | 122 | 143 |
| fib | 14 | 14 | 15 |
| interp | 42 | 43 | 41 |
| iterchain | 418 | 196 | 189 |
| iterloop | 419 | 194 | 187 |
| json | 109 | 112 | 95 |
| mandelbrot | 175 | 174 | 168 |
| matmul | 19 | 19 | 46 |
| nbody | 32 | 31 | 29 |
| sieve | 65 | 69 | 77 |
| sort | 60 | 60 | 56 |
| stencil | 8 | 8 | 8 |
| wordcount | 126 | 92 | 75 |
| md5 | 39 | 37 | - |
| fmtints | 28 | 30 | - |
| fmtloop | - | 27 | - |
| geomean vs cc -O2 (15 programs, iterchain included) | 1.091 | 0.966 | 1 |

(-O0 and -O1 in the same run: geomean 8.052 and 1.658.) iterchain over
iterloop, alternating, fastest of 18 rounds: 196 against 194 ms, a ratio
of **1.010** (the limit is 1.05); both are now within 4% of cc -O2's
(189 and 187 ms), from about 2.2 times in 0.14 (docs/optimizer.md,
"0.15"). fmtloop (10^6 lines formatted by f-strings into a Buf) over
fmtints (the same text with push_int and push_str by hand): 27 against
29 ms, **0.931** (the limit is 1.05).

The other differences are noise: an alternating rerun (fastest of 15,
load average about 5) gives wordcount 87 against 87 ms, json 110 against
111, binarytrees 159 against 165, sieve 66 against 74; sieve's
assembly is the same as 0.14.0's (the binaries differ in their UUID), so
its difference is the machine's. iterchain and iterloop are the
optimizer's 0.15 work; everything else compiles as before.

Compile time (aarch64-macos, wall time, best of 7, the two compilers
alternating on the same input: the 0.15 source, 114,000 lines in 249
files; load average about 4.5):

| | 0.14.0 | 0.15 |
|---|---|---|
| the compiler to an object, -O0 | 303 ms | 300 ms |
| the compiler to an object, -O2 | 2423 ms | 2399 ms |
| `tachyonc check compiler/src/main.tach`, no cache | 97 ms | 100 ms |
| `tachyonc query refs run_gvn`, no cache (`TACHYON_CACHE=off`) | 121 ms | 135 ms |
| `tachyonc check compiler/src/main.tach`, cache warm | 8.7 ms | 8.9 ms |
| `tachyonc query refs run_gvn`, cache warm | 10.1 ms | 9.5 ms |
| a 7-line std program to an object, -O0 | 3.2 ms | 2.9 ms |
| a 7-line std program to an object, -O2 | 5.0 ms | 5.0 ms |

The compiler compiles itself as fast as 0.14.0 does (its source grew 16%
since 0.14's measurement, 98,000 to 114,000 lines, so the absolute times
are higher than 0.14's table). `query refs` without the cache is about
12% slower (0.15's checker: widening, generic traits, named arguments),
not investigated further; with the cache, queries are about 9 to 10 ms
on this machine at this load. The tiny std program compiles as fast as
with 0.14.0 although std doubled (46 to 90 KB): std is loaded by
sections, and print compiles less code (Integration notes in
docs/design/errors-formatting.md).

### 0.16

aarch64-macos (Apple silicon, native; `bench/run.sh -p <0.15.0> -r 9`,
the fastest of 9 runs in ms, right after the release gate, load average
from 25 down to 2 while it ran, other agents' work on the machine; the
"0.15.0" column is 0.15's own table, since 0.15.0 cannot build the
programs migrated to explicit allocation; the geometric mean is over cc
-O2's, programs with a C version only):

| program | 0.15.0 | 0.16 -O2 | cc -O2 |
|---|---|---|---|
| arena_trees | - | 33 | 40 |
| binarytrees | 160 | 159 | 161 |
| collatz | 312 | 291 | 291 |
| fannkuch | 122 | 117 | 140 |
| fib | 14 | 14 | 14 |
| interp | 43 | 42 | 40 |
| iterchain | 196 | 193 | 183 |
| iterloop | 194 | 191 | 185 |
| json | 112 | 105 | 93 |
| mandelbrot | 174 | 162 | 156 |
| matmul | 19 | 18 | 43 |
| nbody | 31 | 31 | 28 |
| sieve | 69 | 59 | 70 |
| sort | 60 | 55 | 52 |
| stencil | 8 | 8 | 8 |
| wordcount | 92 | 85 | 69 |
| md5 | 37 | 20 | - |
| fmtints | 30 | 22 | - |
| fmtloop | 27 | 22 | - |
| purecall | - | 74 | - |
| purecall_hoisted | - | 74 | - |
| geomean vs cc -O2 (16 programs) | 0.966 (15) | 0.953 | 1 |

(-O0 and -O1 in the same run: geomean 7.750 and 1.598.) The pairs, run
alternately, fastest of 18 rounds: iterchain over iterloop 193 against
191 ms, **1.010**; fmtloop over fmtints 22 against 22, **1.000**;
purecall (calls of pure functions left in loops) over purecall_hoisted
(the same hoisted and merged by hand) 74 against 74, **1.000**, where
0.15.0 took 291 ms (the limit for each pair is 1.05). arena_trees
(binarytrees with its nodes in std's arenas through the Allocator trait)
33 ms against C's arena 40 and binarytrees on malloc 159: the bump path
inlines without a call. fmtloop and fmtints are faster than 0.15's
(27 and 30 ms): an integer hole with a spec is formatted in one pass and
`push_int` writes in place. md5 (u32 arithmetic throughout) went from
34 to 19 ms against 0.15.0's build of its own md5, measured alone (min
of 9): T4's u32 operations on the w registers, without the extension
after each.

The gaps examples/algorithms showed (docs/optimizer.md; measured by T4 on
the examples, ms, C's in parentheses): dijkstra with struct entries 78 to
65 (47), a derived `<` branch-free; nqueens on u32 masks 109 to 76 (69),
u32 arithmetic without extensions; bigint's schoolbook multiply 8.3 to 5.7
(4.7) and F(10^6) 45 to 36 (27), the widening multiply-accumulate
vectorized (`umlal`); `count_ones`, `leading_zeros`, `trailing_zeros` in
std, `cnt`/`clz` on AArch64. lru-cache stays at about 1.5 times C's
(the probe loop around an out-of-line `HashMap::insert`): later.

Compile time (aarch64-macos, wall time, best of 7, the two compilers
alternating on the same input: 0.16's source, 125,600 lines in 277
files; load average about 1.3):

| | 0.15.0 | 0.16 |
|---|---|---|
| the compiler to an object, -O0 | 299 ms | 298 ms |
| the compiler to an object, -O1 | 851 ms | 856 ms |
| the compiler to an object, -O2 | 2596 ms | 2502 ms |
| `tachyonc check compiler/src/main.tach`, no cache | 114 ms | 117 ms |
| `tachyonc query refs run_gvn`, no cache | 149 ms | 158 ms |
| a 7-line std program to an object, -O0 | 2.8 ms | 3.0 ms |
| a 7-line std program to an object, -O2 | 5.7 ms | 6.8 ms |

The compiler compiles itself as fast as 0.15.0 does at -O0 and -O1 and
4% faster at -O2 (T6's register allocator fix: `is_returns_twice_call`
compared names through strlen). The effects (inference and checks over
about 400,000 nodes, 3 to 4 ms) are in `check`, 2% more; queries without
the cache about 6% more. Accepted for 0.16, decided at integration: the
compiler's own source moved to f-strings (T6), and a compiler built from
it is 3 to 4% slower at -O0 and -O1 than one built from release-0.16
before that move (check +0.6%, -O2 9% faster with the regalloc fix):
each f-string is lowered to four functions that -O0 and -O1 do not
inline, which user programs pay too; the fix belongs to the f-string
lowering, in 0.17's compile-speed work, not to reverting the compiler's
f-strings. The small std program compiles 0.2 ms slower at -O0 and 1.1
ms at -O2: std's allocation layer (the Allocator trait, Gpa's methods
inlined, alloc.tach's sections) and, at -O2, the effects the optimizer
reads (at -O0 inference is skipped when nothing reads it).

### 0.17

aarch64-macos (Apple silicon, native; `gate.sh --only bench`, that is
`bench/run.sh -p <0.16.0> -r 5`, the fastest of 5 runs in ms, right
after the release gate, load average 2.7 at the start, falling from 26
over the last quarter hour; the "0.16.0" column is 0.16's own table,
since 0.16.0 cannot build most of the programs migrated to 0.17's values;
where it can, its build in the same run is in parentheses; the geometric
mean is over cc -O2's, programs with a C version only):

| program | 0.16.0 | 0.17 -O2 | cc -O2 |
|---|---|---|---|
| arena_trees | 33 | 32 | 39 |
| binarytrees | 159 (164) | 155 | 161 |
| collatz | 291 (291) | 291 | 291 |
| fannkuch | 117 (117) | 117 | 140 |
| fib | 14 (14) | 14 | 14 |
| interp | 42 | 42 | 41 |
| iterchain | 193 | 190 | 184 |
| iterloop | 191 | 191 | 184 |
| json | 105 | 105 | 94 |
| mandelbrot | 162 (165) | 164 | 157 |
| matmul | 18 | 18 | 44 |
| nbody | 31 | 32 | 28 |
| sieve | 59 (77) | 78 | 86 |
| sort | 55 | 57 | 53 |
| stencil | 8 | 8 | 8 |
| wordcount | 85 | 85 | 71 |
| md5 | 20 | 21 | - |
| fmtints | 22 | 22 | - |
| fmtloop | 22 (22) | 22 | - |
| purecall | 74 (74) | 74 | - |
| purecall_hoisted | 74 (74) | 75 | - |
| geomean vs cc -O2 (16 programs) | 0.953 | 0.953 | 1 |

(-O0 and -O1 in the same run: geomean 7.674 and 1.475; a first run at
load 16 to 35 gave 0.960.) The pairs, fastest of 10: iterchain over
iterloop 190 against 191 ms, **0.995**; fmtloop over fmtints 22 against
22, **1.000**; purecall over purecall_hoisted 74 against 74, **1.000**.
The generated code is where 0.16's was: drops are inlined glue that
replaces the hand-written frees (the migrated programs' code is the
same or within noise), and the noalias facts remove the vectorizer's
overlap tests from stencil (4 to 0) and matmul (2 to 0) without moving
their times, as the prototype predicted (docs/optimizer.md, "0.17: value
semantics in the optimizer": the facts pay in kernels with many streams,
2.06 times on 8 streams). sieve's 59 in 0.16's table against 78 now is
the machine: 0.16.0's own build took 77 in the same run, and C 86
against 70 then.

Compile time (aarch64-macos, wall time, best of 7, the two compilers
alternating on the same input: 0.17's source, 150,200 lines in 315
files; `TACHYON_CACHE=off`; load average 2.3 to 5.9):

| | 0.16.0 | 0.17 |
|---|---|---|
| the compiler to an object, -O0 | 370 ms | 318 ms (-14%) |
| the compiler to an object, -O1 | 1104 ms | 815 ms (-26%) |
| the compiler to an object, -O2 | 3134 ms | 1967 ms (-37%) |
| `tachyonc check compiler/src/main.tach` | 143 ms | 154 ms (+7.6%) |
| `tachyonc query refs run_gvn` | 188 ms | 202 ms (+7.6%) |
| a small std program to an object, -O0 | 3.3 ms | 3.5 ms |
| a small std program to an object, -O2 | 6.1 ms | 6.0 ms |

Instructions retired and peak memory of the same compilations
(`/usr/bin/time -l`): -O0 8.41 G and 356 MB against 6.80 G and 306 MB;
-O2 53.15 G and 874 MB against 32.70 G and 570 MB. The compile-speed
track (docs/optimizer.md, "0.17: compile time" and "0.17: cheaper
f-strings": the hot spots, function-local ids and the per-function
pipeline, -O1 leaf inlining, f-strings written in place) makes the
compiler compile itself 14% faster at -O0, 26% at -O1 and 37% at -O2,
with a third less memory at -O2. `check` and the queries without the
cache pay the own pass: 7.6% here, which with the record the checker
keeps for its fast path (the checker 2% slower, the pass 6.3% of it) is
about 8.5% over 0.16's checker against the 8% budget, accepted for
0.17.0 (getting at least 0.5% back is a 0.17.1 item). The small
program: `Vec::new_in(gpa)`, ten pushes, a sum, `print_int`,
`println("")`.

### 0.18

aarch64-macos (Apple silicon, native; `gate.sh --only bench`, the
fastest of 5 runs in ms, right after the release gate; other agents'
work kept the load average between 6 and 25, so the times move by
several percent from run to run; "0.17.0" is v0.17.0's build of the same
programs in the same run; the geometric mean is over cc -O2's):

| program | 0.17.0 | 0.18 -O2 | cc -O2 |
|---|---|---|---|
| arena_trees | 33 | 34 | 42 |
| binarytrees | 153 | 157 | 154 |
| collatz | 314 | 314 | 315 |
| fannkuch | 121 | 122 | 144 |
| fib | 14 | 14 | 14 |
| interp | 42 | 43 | 40 |
| iterchain | 191 | 194 | 188 |
| iterloop | 195 | 197 | 187 |
| json | 107 | 106 | 94 |
| mandelbrot | 171 | 171 | 166 |
| matmul | 20 | 18 | 45 |
| nbody | 31 | 32 | 29 |
| sieve | 82 | 85 | 101 |
| sort | 65 | 65 | 61 |
| stencil | 9 | 10 | 10 |
| wordcount | 175 | 124 | 92 |
| md5 | 24 | 22 | - |
| fmtints | 22 | 22 | - |
| fmtloop | 22 | 22 | - |
| purecall | 78 | 90 | - |
| purecall_hoisted | 88 | 87 | - |
| geomean vs cc -O2 (16 programs) | 0.969 | 0.958 | 1 |

(-O0 and -O1 in the same run: geomean 7.877 and 1.580.) The pairs,
fastest of 10: iterchain over iterloop **0.985**, fmtloop over fmtints
**1.000**, purecall over purecall_hoisted **1.012**. With the load this
high the times are not the measure; the instructions retired are (one
run each, which vary by about 0.3% from run to run):

| program | 0.17.0 | 0.18 |
|---|---|---|
| arena_trees | 693.6 M | 693.0 M |
| binarytrees | 5106.4 M | 5105.5 M |
| collatz | 3040.2 M | 3040.1 M |
| fannkuch | 1284.7 M | 1284.5 M |
| interp | 1500.3 M | 1500.2 M |
| iterchain | 4478.9 M | 4479.7 M |
| iterloop | 4510.7 M | 4510.3 M |
| json | 1516.8 M | 1516.6 M |
| mandelbrot | 2172.2 M | 2172.1 M |
| matmul | 251.7 M | 248.3 M |
| nbody | 622.2 M | 622.3 M |
| sieve | 467.6 M | 468.5 M |
| sort | 415.7 M | 414.8 M |
| stencil | 236.0 M | 236.0 M |
| wordcount | 1591.2 M | 1593.4 M |
| purecall | 1128.8 M | 1128.8 M |

The generated code is 0.17.0's: contract checks are checks the range
analysis removes like bounds checks, std's clauses replaced the checks
its bodies made, and the check sites' constants live on the cold paths.
Before the unroller's fix (tests/run/opt_unroll_exit_consts) iterchain
took 4741 M, its pair 1.031.

Compile time (aarch64-macos, best of 7 alternating, wall, load 13 to
16, so a few percent is noise; the instructions retired, `/usr/bin/time
-l`, are the measure; 0.18's source, 159,250 lines in 338 files, in a
copy outside the tree; no query cache):

| | 0.17.0 | 0.18 |
|---|---|---|
| the compiler to an object, -O0 | 376 ms / 7.33 G / 343 MB | 386 ms / 7.50 G / 352 MB |
| the compiler to an object, -O1 | 932 ms / 14.09 G / 439 MB | 943 ms / 14.29 G / 441 MB |
| the compiler to an object, -O2 | 2193 ms / 35.41 G / 580 MB | 2185 ms / 35.61 G / 581 MB |
| `tachyonc check compiler/src/main.tach` | 181 ms / 3.23 G | 183 ms / 3.28 G |
| `tachyonc query refs run_gvn` | 241 ms / 4.23 G | 251 ms / 4.45 G |
| a small std program to an object, -O0 | 3.9 ms / 47 M | 4.6 ms / 57 M |
| a small std program to an object, -O2 | 6.7 ms / 79 M | 7.3 ms / 91 M |

The compiler compiles itself with 2.3% more instructions at -O0, 1.4%
at -O1 and 0.6% at -O2: the contracts' expansion and checks, the tests'
and distinct types' front-end work, and the check-site table. `check`
does 1.5% more, a query without the cache 5.2% more. A small std
program pays most (about 10 M instructions, 0.6 ms; 13.5 M of either
column is the process's start): std is 23% larger (175 to 216 KB: its
clauses, the test runtime, the fuzzer, NonNull), and its text is built
for every compilation though the new sections are only lexed by the
builds that name them; the phase 0 syntax hooks, the contracts and the
tests each added a third of it (bisected on release-0.18's merges).
Building std's text by section, as it is loaded, is a 0.18.1 item.

### 0.18.1

aarch64-macos (`gate.sh --only bench`, the fastest of 5 runs in ms, at
load about 2; "0.18.0" is v0.18.0's build in the same run; the geometric
mean is over cc -O2's, programs with a C version only; 0.18.0 cannot
build heap, so its geomean leaves heap out):

| program | 0.18.0 | 0.18.1 -O2 | cc -O2 | instructions 0.18.0 / 0.18.1 |
|---|---|---|---|---|
| arena_trees | 32 | 32 | 39 | 693.1 / 693.1 M |
| binarytrees | 168 | 169 | 162 | 5102 / 5104 M |
| collatz | 290 | 291 | 291 | 3040 / 3040 M |
| contracts | 205 | 148 | - | 6717 / 4384 M (-34.7%) |
| contracts_plain | 199 | 194 | - | 6199 / 5871 M (-5.3%) |
| fannkuch | 117 | 118 | 140 | 1284.5 / 1284.5 M |
| heap | - | 203 | 198 | - / 1761 M |
| interp | 42 | 43 | 40 | 1500 / 1500 M |
| iterchain | 189 | 189 | 182 | 4478 / 4478 M |
| iterloop | 193 | 190 | 183 | 4509 / 4509 M |
| json | 104 | 105 | 93 | 1516 / 1516 M |
| mandelbrot | 163 | 162 | 156 | 2172 / 2172 M |
| matmul | 18 | 18 | 43 | 247.5 / 247.5 M |
| nbody | 31 | 31 | 28 | 622.2 / 622.3 M |
| sieve | 58 | 59 | 67 | 467.3 / 467.0 M |
| sort | 55 | 56 | 52 | 414.1 / 414.2 M |
| stencil | 8 | 8 | 8 | 236.1 / 235.9 M |
| wordcount | 83 | 84 | 68 | 1591 / 1591 M |
| geomean vs cc -O2 | 0.957 | 0.965 (heap included) | 1 | |

The pairs: iterchain over iterloop 0.995, fmtloop over fmtints 1.000,
purecall over purecall_hoisted 1.000. Every program's code is 0.18.0's
in instructions (within 0.1%) but the contracts pair, faster by the
range fixes and the entry facts (docs/optimizer.md, "Contracts and
generated code: the evidence"); heap (std's BinaryHeap) is 1.03 of C's.

Compile time (aarch64-macos, best of 5 alternating, wall, load 2 to 6;
0.18.1's source in a copy outside the tree; no cache; the default `-j`):

| | 0.18.0 | 0.18.1 |
|---|---|---|
| the compiler to an object, -O0 | 359 ms / 7.97 G | 308 ms / 7.92 G |
| the compiler to an object, -O1 | 873 ms | 392 ms |
| the compiler to an object, -O2 | 2150 ms / 37.17 G / 613 MB | 765 ms / 36.46 G / 684 MB |
| the same at -j1 | 37.16 G | 36.34 G / 651 MB |
| `tachyonc check compiler/src/main.tach` | 177 ms / 3.48 G | 189 ms / 3.73 G |
| `tachyonc query refs run_gvn` | 238 ms | 253 ms |
| a small std program to an object, -O0 | 3.9 ms / 57 M | 4.1 ms / 63 M |
| a small std program to an object, -O2 | 6.5 ms | 6.1 ms |

The compiler compiles itself 2.8 times faster at -O2 and 2.2 times at
-O1 (threads, docs/optimizer.md, "0.18.1: threads"), in fewer
instructions; the threads cost memory at -O2 (613 to 684 MB). `check`
and the queries do 7% more: their phases (parse, check, effects, own)
are within 2 ms of 0.18.0's, and the difference is in the command
around them, a 0.18.2 item. The small program at -O0 pays 6 M
instructions more (std's new sections).

### 0.19

aarch64-macos (`gate.sh --only bench`, fastest of 5, ms, load falling
from 13 to 3; "0.18.1" is v0.18.1's build in the same run):

| program | 0.18.1 | 0.19 -O2 | cc -O2 |
|---|---|---|---|
| arena_trees | 33 | 33 | 40 |
| binarytrees | 173 | 156 | 171 |
| collatz | 292 | 291 | 291 |
| contracts | 148 | 149 | - |
| fannkuch | 119 | 118 | 141 |
| heap | 207 | 206 | 200 |
| interp | 43 | 43 | 40 |
| iterchain | 189 | 190 | 183 |
| iterloop | 190 | 191 | 183 |
| json | 104 | 105 | 93 |
| mandelbrot | 164 | 163 | 158 |
| matmul | 18 | 18 | 43 |
| nbody | 31 | 31 | 28 |
| sieve | 58 | 57 | 66 |
| sort | 56 | 56 | 53 |
| stencil | 8 | 8 | 8 |
| wordcount | 84 | 84 | 69 |
| geomean vs cc -O2 | 0.958 | 0.951 | 1 |

The pairs 0.995, 1.000, 1.000. Instructions retired: every program
within 0.06% of v0.18.1's (bench uses no intrinsic; examples/arch has
the intrinsics' timings: bytesearch 0.12 s = libc memchr, crc32 0.09 s
= clang).

Compile time (best of 5 alternating, wall, load 2.5 to 3; instructions
retired; 0.19's source in a copy outside the tree; no cache):

| | 0.18.1 | 0.19 |
|---|---|---|
| the compiler to an object, -O0 | 347 ms / 8.84 G | 373 ms / 9.33 G |
| -O1 | 438 ms | 450 ms |
| -O2 (-j8; -j1 instructions) | 834 ms / 39.65 G | 855 ms / 40.21 G |
| `tachyonc check` | 209 ms / 4.11 G | 220 ms / 4.27 G |
| a small std program, -O0 / -O2 | 4.1 / 6.2 ms | 4.2 / 6.3 ms |

The -O0 self-compile does 5.5% more instructions: the feature analysis
over the call graph (check +4 ms) and the assembler's larger encoder
(data and output 141 to 157 ms, the AArch64 and x86-64 instruction
tables); -O2 1.4%, check 3.7%. A program without intrinsics pays only
the analysis.

### 0.19.1

The release gate (`gate.sh --release --no-x86`, 14:05 wall, every step
passing; the suite 1593 tests, aarch64-linux 1266 and valgrind 237
clean). Bench (fastest of 5, load falling from 16 to 2): geomean 0.951
of cc -O2, v0.19.0 0.954 in the same run; the pairs 0.995, 1.000,
1.000; instructions retired within 0.15% of v0.19.0's for every
program. Compile time in instructions, against v0.19.0 on 0.19.1's
source: the self-compile 9.35 G to 9.36 G at -O0, 40.26 G to 40.27 G at
-O2 (-j1), check 4.33 G both, a small program 65 M both.

### 0.20

aarch64-macos (`gate.sh --only bench`, fastest of 5, ms, load 8 falling
to 3: times move by several percent; 0.19.1 cannot build the programs in
0.20's spelling, so it is compared by instructions retired, its own
source against 0.20's, one run each):

| program | 0.20 -O2 | cc -O2 | instructions 0.19.1 / 0.20 |
|---|---|---|---|
| binarytrees | 163 | 177 | 5102 / 5106 M |
| collatz | 327 | 329 | 3041 / 3040 M |
| fannkuch | 122 | 144 | 1292 / 1292 M |
| heap | 212 | 207 | 1780 / 1762 M |
| iterchain | 190 | 184 | 4491 / 4491 M |
| json | 107 | 96 | 1523 / 1507 M |
| matmul | 19 | 46 | 249 / 248 M |
| sieve | 66 | 71 | 475 / 471 M |
| sort | 19 | 56 | 416 / 361 M (-13%, ipnsort) |
| wordcount | 79 | 72 | 1594 / 1721 M (+8%: foldhash and the Swiss table's probing; faster in time) |
| geomean vs cc -O2 | 0.889 | 1 | |

The pairs: iterchain/iterloop 0.974, fmtloop/fmtints 0.957,
purecall/purecall_hoisted 1.000.

bench/std (`bench/std/run.sh -r 3`, tachyon's time over the baseline's;
Rust with the same hash where marked): hash_u64 0.98 (rust:fold), 0.62
(Rust's default), 0.61 (C); hash_str 1.07, 0.81, 0.81; hash_churn 1.05,
0.69, 0.73; btree_u64 0.86 (Rust), 1.00 (C); sort_unstable 1.16 (Rust),
0.20 (qsort); sort_stable 1.17, 0.22 (mergesort); fmt_f64 0.80, 0.22
(`%.17g`); fmt_f64_prec 1.85; parse_f64 1.35, 1.16 (strtod); fmt_int
0.85, 0.55; parse_int 1.19, 1.06; chars 0.95; graphemes 0.28 (Rust's
unicode-segmentation-free scan); width 0.93 (Rust str), 0.17 (wcwidth);
term_feed 0.58, 0.46; str_ops 1.29, 1.16; read_lines 0.67 (allocating),
1.03 (reused String), 0.94 (getline); rng 1.00; spawn 1.00; UTF-8
validation about 15 GB/s on non-ASCII, 50-60 GB/s on ASCII. Above their
targets: str_ops, parse_int, parse_f64 (0.20.1 work).

Compile time (instructions retired, 0.20's source in a copy, no cache):
the self-compile 10.88 G to 11.55 G at -O0 (+6.2%), 43.24 G to 43.80 G
at -O2 -j1 (+1.3%); `check` 4.84 G to 5.49 G (+13.5%); a hello world 47 M
to 317 M (std's text, above).

### 0.21

The release gate (`gate.sh --release --no-x86`, 26:10 wall at load up
to 30; suite-O0 and stress-grow rerun, 13:06): every step passing, the
suite 1687 (2 XFAIL), aarch64-linux 1360, threads 2602, incremental 160
series, valgrind 247 clean. example_algorithms-lru-cache at -O0 timed
out once under load (as at 0.20.0) and passed on the rerun.

Bench (load 9 to 27: times are not the measure): geomean 0.845 of cc
-O2, v0.20.0's build 0.957 in the same run; instructions retired against
v0.20.0's build of the same programs: every program within 0.1% but
sieve (+0.9%). Compile time in instructions (0.21's source, no cache):
the self-compile 11.83 G to 11.89 G at -O0, 45.04 G to 45.51 G at -O2
-j1 (+1.0%), check 5.68 G to 5.70 G; a hello world 327 M to 336 M (0.20's
regression, under investigation for 0.21.1).

### 0.22

The release gate (`gate.sh --release --no-x86`, 35:02 wall at load up
to 66): every step passing but three, rerun with compile-cost (16:59):
objcheck gave examples/gpu's `-l objc` to `-c` (tests/objcheck.sh now
gives -l and -L to the links, and skips Metal programs off macOS, in the
container too); example_allocators-arena-parser was killed by its time
limit under --check-alloc at load 40 and passed on the rerun. The suite
1749 (6 XFAIL), aarch64-linux 1391, threads 2635, incremental 160
series, valgrind 249 clean. compile-cost against v0.21.0: a hello world
95.9 M instructions against 357.5 M (0.27x), tests/cost/std_heavy 0.96x,
check of the compiler 5.49 G against 5.42 G (1.01x).

Bench (load 20 to 50: times are not the measure): geomean 0.801 of cc
-O2, v0.21.0's build 0.789 in the same run; instructions retired against
v0.21.0's build of the same programs: every program within 0.5% but sort
(+1.0%) and wordcount (-1.0%), the outputs the same. The self-compile
(0.22's source, no cache): 11.11 G to 11.17 G at -O0 (+0.6%), 43.38 G to
43.47 G at -O2 -j1 (+0.2%), 814 MB to 811 MB.

### 0.23

The release gate (`gate.sh --release --no-x86`, 30:53 wall at load up
to 50): every step passing but three, rerun (21:22): stress-grow's
voltty_render_font_ascii_time (a timing case, 95 glyphs in 105 ms under
load) and examples-checkalloc's arena-parser (its time limit) passed on
the rerun; in the container objcheck linked voltty's app, which needs
Core Text (tests/objcheck.sh now keeps it to macOS), and tests/fmt's
`compiles` found std_gpu_wgsl_reflect's assembly different once (the
same on the rerun and, cross-compiled, here in four builds). The suite
1846 (6 XFAIL), aarch64-linux 1404, threads 2638, incremental 160
series, objcheck 2460, voltty-fuzz 337 scripts against the oracle,
valgrind 249 clean. compile-cost against v0.22.0: a hello world 94.0 M
instructions (1.00x), std_heavy 1.00x, check of the compiler 5.62 G
(1.00x).

Bench (load 5 to 25): geomean 0.849 of cc -O2, v0.22.0's build 0.904 in
the same run; instructions retired against v0.22.0's build of the same
programs: every program within 0.1%, the outputs the same. The
self-compile (0.23's source, no cache): 11.30 G to 11.36 G at -O0
(+0.5%), 44.56 G to 44.49 G at -O2 -j1 (-0.2%), 834 MB to 813 MB.
