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
- `enum` with payloads and exhaustive `match`
- methods (`impl` blocks, static dispatch, `x.f()` sugar for `f(x)`)
- slices `[T]` (pointer plus length) with bounds checks

Optimizations:
- SROA: tuples, structs and small arrays split into scalars
- basic alias analysis: distinct stack slots and globals, field and
  constant-offset disambiguation, escape-free locals
- store-to-load forwarding, dead store elimination, memcpy elimination
- `match` lowering: jump tables, binary decision trees
- C ABI aggregate classification on both targets (small structs in
  registers; fixes the `div_t` xfail)

## 0.4: loops

The compiler's own source starts using enums, `match`, methods and slices.

- loop canonicalization: preheaders, single latch, dedicated exits, LCSSA
- scalar evolution (add recurrences) and induction variable simplification
- loop strength reduction
- loop rotation, full unrolling of small constant trip counts, partial
  unrolling
- loop unswitching
- value range analysis; bounds-check elimination from induction ranges
- trip-count-based dead loop deletion

## 0.5: backend quality (passing Cranelift)

Language: generics by monomorphization (`fn f<T>`, `struct Vec<T>`),
modules and imports.

- register allocation with live-range splitting and coalescing (SSA-based
  linear scan with interval splitting, or iterated register coalescing);
  rematerialization of constants
- instruction selection by tree-pattern rules (a rule table per target)
- list scheduling, post-RA peepholes
- tail calls, frame elision for leaf functions, shrink-wrapping
- block layout by fall-through and loop structure

## 0.6: interprocedural

The compiler's source starts using generics and modules.

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
