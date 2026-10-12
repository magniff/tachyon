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
- `bench/` results are recorded in this file.

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
- 0.5: `#[repr(C, align(N))]` above 16 (needs realigned stack frames);
  [x] `import` into a module's namespace (`import "h.h" as c;`, and an
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
- [x] several errors per compilation (pulled forward from 1.0): the parser
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
- moved to stage B: realigned frames for `#[repr(C, align(N))]` above 16;
  a tachyon calling convention of its own (more argument registers,
  aggregates up to four registers passed and returned in registers: it
  needs the lowering of calls to classify aggregates by convention)

Stage B:

- instruction selection by tree-pattern rules (a rule table per target),
  scaled-index addressing
- list scheduling, post-RA peepholes
- shrink-wrapping
- block layout by fall-through and loop structure
- unrolling with run-time trip counts

## 0.6: interprocedural

The compiler's source starts using generics, modules and the standard
library (and reports several errors at once while it is written).

- call graph, bottom-up SCC-ordered inlining with a cost model and an
  inline → simplify iteration
- IPSCCP, function attribute inference (pure, readonly, nocapture,
  noreturn), dead argument elimination, global DCE
- function specialization on constant arguments
- escape analysis: heap-to-stack for non-escaping `malloc`
- language: `defer`, `#[inline]` / `#[cold]` attributes

## 0.7: equality saturation

- replace ad-hoc rewriting with an e-graph (acyclic, à la Cranelift's
  ægraph) and a rewrite-rule DSL compiled into matchers
- rewrite rules checked by randomized differential testing before they
  are accepted
- partial redundancy elimination (GVN-PRE)

## 0.8: vectorization

- SLP vectorizer
- loop vectorizer for counted loops with simple dependences
- NEON and SSE2/AVX2 lowering; language-level vector types (`v4f32`, ...)

## 0.9: profile-guided

- instrumentation profiles (`--profile-generate` / `--profile-use`)
- branch weights driving inlining, block layout and hot/cold splitting
- PGO-aware register allocation and unrolling

## 1.0: stable

- language specification frozen; multi-error diagnostics; DWARF line
  tables
- aarch64-linux host
- within 10% of clang -O2 on `bench/`

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