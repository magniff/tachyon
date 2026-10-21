# Releases and the bootstrap chain

The tachyon compiler is written in tachyon. To build it on a machine that
has no tachyon compiler yet, the chain of releases is replayed from its
root, the seed:

```
seed (Rust)  ──builds──▶  0.1.0  ──builds──▶  next release  ──▶ ... ──▶  HEAD
```

- **The seed** is the original Rust implementation (`seed/`, Cranelift
  backend), tagged `seed`. It is frozen: its toolchain is pinned
  (`seed/rust-toolchain.toml`, `seed/Cargo.lock`), and it only ever has to
  build release 0.1.0. New language features never go into it.
- **Every release** is a git tag (`v0.1.0`, `v0.2.0`, ...) whose tree is
  self-contained: the compiler for that release in tachyon (`compiler/`),
  its examples (`examples/`), its test suite (`tests/`), the documentation
  of its language (`docs/`), and the chain tooling (`bootstrap/`). The tree
  of `v0.1.0` also holds the seed, so that one tag has everything.
- **Each release is built by the previous one**, and checked: it must reach
  the fixpoint (compiled by itself, it emits exactly what its first build
  emits) and pass its own test suite.

`bootstrap/releases.toml` lists the seed's tag and the releases in order,
with the tag, where the compiler's source is, what builds it, how its
binary is invoked, where its test runner is and which hosts it supports.
`bootstrap/bootstrap.sh` replays the chain.

## Versions

| release | tag | built by | hosts | introduced |
|---|---|---|---|---|
| seed | `seed` | Rust 1.98.0 | aarch64-macos, x86_64-macos, x86_64-linux | the language, and its Rust implementation with a Cranelift backend |
| 0.1.0 | `v0.1.0` | seed | aarch64-macos, x86_64-linux, x86_64-macos | the compiler in tachyon: the seed's whole language, compiled to AArch64 (Apple's arm64 ABI) and x86-64 (System V, ELF and Mach-O) assembly; a test suite run without cargo |
| 0.2.0 | `v0.2.0` | 0.1.0 | aarch64-macos, x86_64-linux, x86_64-macos | the optimizer: SSA IR, SCCP, instruction combining, GVN, LICM, inlining, linear-scan register allocation; `-O0`/`-O1`/`-O2` (default `-O2`); random differential testing; `bench/` |
| 0.3.0 | `v0.3.0` | 0.2.0 | aarch64-macos, x86_64-linux, x86_64-macos | aggregates and memory: enums with fields and `match`, methods, slices, C interop (`extern "C"`, `#[repr(C)]`, unions, C's convention for aggregates); SROA, memory forwarding across blocks, dead stores, switches and jump tables; ABI conformance fuzzing |
| 0.4.0 | `v0.4.0` | 0.3.0 | aarch64-macos, x86_64-linux, x86_64-macos | loops and C headers: the compiler written in the 0.3 language; `import "x.h"` (a C preprocessor and declaration reader) and `--emit-header`; `use`, checked `as` to enums, enum ordering, `size_of`/`align_of`, `for x in s`; loop canonicalization, induction variables, rotation, unrolling, unswitching, strength reduction, value ranges and bounds-check elimination, aggressive DCE, tail recursion elimination |
| 0.5.0 | `v0.5.0` | 0.4.0 | aarch64-macos, x86_64-linux, x86_64-macos | generics, modules and the back end: generics by monomorphization, modules (`mod`, `pub`, `use`), several errors per compilation, a small `std`; register allocation by linear scan with interval splitting, a calling convention of tachyon's own, frames aligned above 16, instruction selection by rules, block layout, selects, leaf frames, sibling calls |
| 0.6.0 | `v0.6.0` | 0.5.0 | aarch64-macos, x86_64-linux, x86_64-macos | interprocedural: the compiler written as a module tree; string literals as slices, `if let`, `defer`, structural `==`, a prelude, inline modules, generic type aliases; a cost-model inliner, attribute inference, interprocedural constants, devirtualization, scalar promotion, heap to stack, global DCE; shrink-wrapping; `--time-passes`, `--stats` |
| 0.7.0 | `v0.7.0` | 0.6.0 | aarch64-macos, x86_64-linux, x86_64-macos | object files: an assembler in the compiler writes Mach-O and ELF objects, `cc` only links (the compiler builds itself 4.4× faster at `-O2`, 15.7× at `-O0`); fixed-array indexing is checked; the undefined behaviour left is documented |
| 0.8.0 | `v0.8.0` | 0.7.0 | aarch64-macos, x86_64-linux, x86_64-macos | no wildcard imports: `use x::*` and `import "h.h";` without `as` are removed, every name a file uses is declared, imported by name or written with its path; `tachyonc --fix-imports` rewrites older code |
| 0.9.0 | `v0.9.0` | 0.8.0 | aarch64-macos, x86_64-linux, x86_64-macos | `unsafe`, traits and an e-graph: `unsafe` blocks and functions (safe code has no undefined behaviour; a warning in 0.9, an error from 0.10), `--fix-unsafe`; traits, bounds, operator traits, std `HashMap` and `sort`; array constants, line continuations; GVN on an acyclic e-graph with rewrite rules checked by `--check-rules` |
| 0.10.0 | `v0.10.0` | 0.9.0 | aarch64-macos, x86_64-linux, x86_64-macos | vectors and profiles: an unsafe operation outside `unsafe` is an error; vector types (`v4f32`, `v2f64`, ...) on NEON and SSE2; a loop vectorizer; profile-guided optimization; `--check-unsafe`; every error of a compilation reported |
| 0.11.0 | `v0.11.0` | 0.10.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | feature-complete, and tools for agents: DWARF line tables (`-g`); aarch64-linux as a target and a host; a broader `bench/`, a cost model for the loop vectorizer, unrolling with run-time trip counts, an SLP vectorizer, division by constants, value ranges through phis; `tachyonc query`, `check`, `fix`, `lint`, `same-output`, `edit` by name and semantic refactorings (`refactor rename`, `move`, `signature`, `field`, `variant`, `split`, `rewrite`, scripts, `undo`) |
| 0.12.0 | `v0.12.0` | 0.11.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | the compiler's source reorganized through its own tools: folders by phase, no file over 1,000 lines, no re-exports, tidy imports, output identical to 0.11's; `edit patch`, `edit insert --in`, `query text`, a module's `use` lines and header as targets, `fix --only reexports` and `tidy-imports`, `split --reexport`; the release gate in one command (`bootstrap/gate.sh`) |
| 0.13.0 | `v0.13.0` | 0.12.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | the tools, improved from 0.12's record: `edit patch` inside a line, `--pairs`, `edit wrap`, `edit new-file`, `signature --default`, `fix --in` over a subtree; section banners, `query grep`, `query type`, kinds of references; an on-disk cache (a query or `check` of an unchanged program in about 6 to 8 ms); `split` part names, layout kept by `move` and `split`, `refactor extract-function` and `inline`; `tachyonc fmt` (the tree formatted), `explain` and `guide` |
| 0.14.0 | `v0.14.0` | 0.13.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | closures and iterators: closures (captures by value or by reference, `move`, `Fn`/`FnMut` bounds, a non-capturing closure is a `fn`, an escape check); associated types; an `Iterator` trait, `for` over anything iterable, ranges as values, std's sources, adapters and consumers, chains compiled to the hand-written loop; std reads stdin (`read_line`, `read_stdin`, `Scanner`), text helpers, values changed in place, an introsort; did-you-mean across the program and std, helps for Rust habits; the tools on a user's program; the agent eval (`tests/agent-eval/`) and its 0.13 baseline |
| 0.15.0 | `v0.15.0` | 0.14.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | errors, conversions, less boilerplate: `?` on `Option` and `Result`, generic traits, `From`/`Into`, `main` returning `Result`, std's I/O on `Result` with typed errors (`fix --only std015` moves 0.14 code); lossless integer widening and joins, `i64::MAX`; f-strings over `Display` and `Debug`, generic `print`/`format`; `#[derive(Eq, Ord, Hash, Debug, Clone)]`; named and default arguments, field shorthand; `==` on `Vec`, `Buf`, `HashMap` by contents; std loaded by sections; if-conversion, vector masks and min/max reductions, split accumulators, `ldp`/`stp` (iterloop from 2.1 to about 1.05 times C); the tools for agents (`query context`, budgets, std from any program, `try`, `batch`, `edit apply`, merge conflicts, `--json`, the check hook); back end, gen0 and base on closures and iterators; algorithm and tool examples; six harder eval tasks |
| 0.16.0 | `v0.16.0` | 0.15.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | effects and explicit allocation: inferred effect sets (`alloc(A)`, `io`, `global`, `panic`, `diverge`, `unsafe`) shown by `query effects` (`--why`, `--has`), `#[pure]`/`#[no_alloc]`/`#[no_io]`/`#[no_panic]`/`#[effects(..)]` and `effects(..)` bounds checked transitively (std's `Eq`/`Ord`/`Hash` pure), `--verify-effects`; allocation explicit (`fn main(gpa: Gpa)`, `Vec::new_in(gpa)`, `fix --only alloc016` moves 0.15 code), the `Allocator` trait, `Gpa`, arenas, `arena_scope`, `FixedBuf`, a `Fmt` that never allocates; `#[sealed]` std types, `#[scoped]` arenas; `--check-alloc` (use after free, double free, leaks, arena resets and scopes); pure calls numbered and hoisted, arena allocation without a call; link inputs on the command line (`x.c`, `-l`, `-L`); examples in folders with READMEs, C interop and language tours; the compiler's source on 0.15's features; compiler tasks in the agent eval |
| 0.17.0 | `v0.17.0` | 0.16.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | memory safety by mutable value semantics: owned values (`Vec`, `Buf`, `HashMap`, `Drop` types, what holds one) move and are dropped at the end of their scope (`Drop`, generated drop glue, drop flags, `.clone()` explicit); references `&T`/`&mut T` and slices split into read-only `[T]` and exclusive `&mut [T]`, second-class: views checked so none outlives or is invalidated under what it views, with inferred view summaries (`views(..)`, `stores(..)`, `#[views]` pins), two-phase receivers and reborrows, no lifetime annotations; `--values=error` the default (`warn`, `report`, `off` for 0.17 only); noalias and read-only facts from reference parameters, NRVO, moves elided in loops; std on values (`Drop` for the containers, `&Self`/`&mut Self` receivers, sorts on `&mut [T]`, `Eq`/`Ord`/`Hash` on `&Self`); `fix --values` and the corpus migrated; `query own`, `query views`, `explain own.*`, tests/own-try; familiar forms (`&mut x`, `v[i]` on Vec and Buf, indexing through a pointer by its type, `p.0`, `len()`, `panic`/`unreachable`, a larger prelude, module paths in code resolved as `use` lines, struct-like enum variants); `fix --suggested`, the `&f` diagnostic; `--trace`, `probe`, `reduce`, `tachyonc test`, `guide debug`; compile speed (per-function IR and pipeline, -O1 leaf inlining, f-strings written in place: the compiler compiles itself 14% faster at -O0, 37% at -O2, in a third less memory) |
| 0.18.0 | `v0.18.0` | 0.17.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | contracts and verification in the language: `requires`/`ensures` (`result`, `old(..)`, `else` messages, `debug` clauses), checked at run time, a requires at the call so the caller is blamed, pure conditions (`contract.effect`); std's own clauses (`unwrap`, `Vec::get`, ...); `assert`, `assert_eq`, `assert_ne`, `debug_assert`; every run-time check one line `FILE:LINE:COL: message` with the condition and its values; `query checks` (the checks the optimizer proved away and those left), `--no-positions`; `#[test]`, `#[cfg(test)]` modules, `assert_snapshot`, `#[property]` with inputs generated from the types and shrunk, contracts tested as properties, `#[fuzz]` with block coverage (`--coverage`, `tachyonc fuzz`), leaks failing a test; `tachyonc test` builds at -O0 and -O2 and compares them; `reduce` over programs (`--differs`, `--fails`, `--test`); `type X = distinct T`, `std::NonNull<T>` with the null niche (`Option<NonNull<T>>` is a pointer, FFI-safe, `_Nonnull` imported) and a checked `as NonNull<T>`; std's `Display`, `Debug`, `Iterator`, `Clone` on references, `fix --values` over traits; the agent eval's `+debrief` |
| 0.18.1 | `v0.18.1` | 0.18.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | two use-after-free holes in safe code closed (a changed copy of a borrowed owned value; a reference into a Vec across a push); functions compiled in parallel (`-j N`, the same bytes at any N; the -O2 self-compile 2.13 s to 0.72 s at -j8) and incremental rebuilds from a code cache (a one-function edit 0.53 s, byte-identical to clean); V4: every `*T` raw, borrowing only `&`/`&mut`, the compiler and std on references; contracts in generated code (range fixes, `x % n` ranges, entry facts: the contracts bench 25% fewer instructions than without clauses); BinaryHeap/MinHeap, binding modes on references, `&f()` temporaries, let-else and the 0.18 eval's polish; a valgrind row and threads/incremental steps in the gate, a lock on the bootstrap cache |
| 0.19.0 | `v0.19.0` | 0.18.1 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | CPU intrinsics and target features: `std::arch` with over 1,775 AArch64 intrinsics (NEON, crc, sha2, sha512, sha3, aes, pmull, dotprod, float), each checked lane by lane against a scalar reference, and 484 x86-64 intrinsics (SSE to AVX2, FMA, BMI, AES-NI, SHA, PCLMULQDQ) encoded as cc does but not run; unsigned, 64-bit and 256-bit vector types; target features inferred like effects, `has`/`detect` guards, foreign architectures constant false, `-C target-cpu`/`target-feature`; run-time detection and `#[multiversion]`; intrinsics pure to the optimizer, never hoisted above their guard, vectors in vector registers; `query arch`, `guide arch`, examples/arch, the fuzzer's arch mode, `tachyonc assemble` |
| 0.19.1 | `v0.19.1` | 0.19.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | two soundness fixes: the store intrinsics' destination is `&mut [T]` (a store through a read-only view, or while a view of the buffer is used, is an error), and 0.17's transitional rule accepting a read-only `[T]` where `&mut [T]` is wanted is gone (`fix --values` migrates); examples/arch/sha256sum, coreutils-compatible on the SHA-256 instructions, faster than macOS's sha256sum and OpenSSL, about 5 times coreutils' on Linux |

Add a row here, and an entry to `bootstrap/releases.toml`, for every release.

### What's new in 0.19.1

- **Two soundness fixes** (code 0.19.0 accepted could write through a
  shared view):
  - the store intrinsics (`vst1q_*`, `vst1_*`, `vst2q_*`,
    `_mm_storeu_*`, `_mm256_storeu_*`) took their destination as a
    read-only `[T]`; it is `&mut [T]` now: a `[T]` there is
    own.readonly with its fix (`&mut a[..]`, `v.as_mut_slice()`), and a
    store into a buffer while a view of it is used is own.conflict;
  - 0.17's transitional rule that accepted a read-only `[T]` where
    `&mut [T]` is wanted (`sort(v.as_slice())`) is removed: such an
    argument is own.readonly, with the fix (`v.sort()`,
    `v.as_mut_slice()`, `&mut a[..]`, or `refactor signature F --type s
    '&mut [T]'`); `fix --values` ends with these fixes, and 51 call sites
    of the corpus moved.
- **examples/arch/sha256sum**: coreutils' `sha256sum` (output, `-c`,
  `--tag`, escapes, messages, exit codes) on the ARMv8 SHA-256
  instructions behind `detect("sha2")`, with a portable fallback. On an
  M5: 1 GiB in 0.352 s (3.05 GB/s) against macOS's sha256sum 0.428 s and
  OpenSSL 4.0.3's 0.399 s; 10,000 small files 0.119 s against 0.227 s.
  In the linux/arm64 container: 0.381 s against coreutils' 1.799 s and
  OpenSSL 3.0's 0.407 s. Built with v0.19.0's features.
- **Breaking**: a read-only `[T]` passed where `&mut [T]` is wanted, and
  a store intrinsic given one, are errors (`fix --values`, or the
  `try:` lines).

### What's new in 0.19

The design, its decisions (D1-D20) and each task's notes ("as built")
are in docs/design/arch.md; the language in docs/grammar.md, "Additions
of 0.19"; `tachyonc guide arch`; examples/arch.

- **`std::arch`**: CPU intrinsics under their vendor names, read from
  tables (`compiler/arch/*.def`: signature, features, instruction,
  encoding, folds, semantics, doc), declared on use (std's text does not
  grow). **AArch64: 1,775+ intrinsics**, NEON integer and float, crc,
  sha2, sha512, sha3, aes, pmull, dotprod; each is checked lane by lane
  against a scalar reference generated from its semantics, with constant
  and run-time inputs at every level (`arch-gen`), crypto by known
  answers, and objcheck agrees with cc on aarch64-macos and
  aarch64-linux. **x86-64: 484 intrinsics** (SSE to SSE4.2, AVX, AVX2,
  FMA, POPCNT, LZCNT, BMI1/2, AES-NI, SHA, PCLMULQDQ), encoded byte for
  byte as cc does (`tachyonc assemble`, tests/arch/enc.sh: 7,777
  instructions) and compiled for x86_64-linux and x86_64-macos, but
  **never executed**: x86 testing is off by the user's instruction, and
  docs/design/arch.md ("T5 as built") lists what runs once it returns.
  Memory forms take slices and are checked (`vld1q_u8(s, i)`), the raw
  pointer forms are in `raw::` and `unsafe`.
- **Vector types**: unsigned, 64-bit and 256-bit portable vectors (30 in
  all) with 0.10's operations and `T::from_bits`; NEON's types are their
  aliases, x86's `__m*` opaque; 256-bit vectors run on AArch64 as pairs.
- **Target features, inferred like effects**: a function needs the
  features of the intrinsics it calls, over the call graph;
  `#[target_feature(enable = ..)]` pins one; a call is legal where the
  callee's needs are known (the build's features, a declaration, or a
  flow-sensitive `has("x")`/`detect("x")` guard: the then-branch, `&&`,
  after `if !G { diverge }`, `assert(G)`); another architecture's
  features are constant false (its branches checked, never generated),
  which replaces `cfg`. `-C target-cpu=NAME|native`, `-C
  target-feature=+x,-y`; baselines apple-m1 on macOS (crc, aes, sha2,
  sha3, dotprod always there), Armv8.0 on Linux. `arch.*` diagnostics
  with `try:` lines.
- **Run-time detection**: `detect("sha2")` reads one cached word (sysctl
  on macOS, getauxval on Linux, cpuid and xgetbv on x86-64), filled
  before main or on first use in a library; `#[multiversion("sha3",
  "dotprod")]` makes a version per feature set behind a chain of detects;
  `TACHYON_ARCH_DISABLE` clears bits, and the suite runs every program
  that detects a second time with every feature off.
- **The optimizer**: intrinsics with an exact generic equivalent become
  the generic vector op; the others are pure `Intr` ops, numbered by GVN,
  moved by LICM (never above their guard), folded on constants; vectors
  are passed in vector registers in tachyon's convention (a call of a
  SIMD helper from 12 instructions to 2; a loop over one 2.12 G to 0.94
  G instructions).
- **Two undefined-behaviour bugs found and fixed before the release**:
  LICM hoisted a `crc32` guarded by `detect` above the detect (it would
  run on a CPU without crc), and could do the same with a 256-bit load;
  the guard rule now covers every instruction that needs a feature.
- **Tools**: `query arch WORDS [--feature F] [--equiv NAME]` searches the
  tables; `query def/show` of an intrinsic give its features,
  instruction, semantics and equivalent, and functions show `features:`;
  `query features --why`; `guide arch` with task recipes; 13 `explain`
  entries; the fuzzer's arch mode (`-A`); `tachyonc assemble`.
- **examples/arch**: bytesearch (NEON, as fast as libc's memchr: 0.12 s
  against a scalar 1.87 s) and crc32 (the crc instructions, as fast as
  clang's: 0.09 s against 2.21 s), with walkthroughs. Next, built with
  v0.19.0: examples/sha256sum on the sha2 instructions, against the
  system's sha256sum, openssl and coreutils.
- **Caught by the release gate, fixed before the tag**: on
  aarch64-linux at -O2, a program whose `main` takes a Gpa and reads
  argv crashed (examples/arch/crc32): main's feature word was filled
  before its parameters were taken, so the init (getauxval, inlined)
  overwrote argc and argv; it now goes after them
  (tests/run/arch_detect_main_args).
- **Tested on aarch64 only**, as 0.15 to 0.18.1 (`gate.sh --with-x86`).

### What's new in 0.18.1

The compiler on threads, incremental rebuilds, V4 and the 0.18 eval's
polish; docs/optimizer.md, "0.18.1: threads", "0.18.1: incremental
rebuilds", "Contracts and generated code: the evidence";
docs/design/contracts-verification.md §4.3, §4.4 and T7/T8's notes.

- **Two use-after-free holes in safe code, closed** (both accepted by
  0.18.0):
  - changing a bitwise copy of an owned value the original still points
    to: `match *e { E::B(v) => v.push(..) }`, `let w = v.get(i);
    w.push(..)`, `for w in vv { w.push(..) }`, or assigning such a
    binding, freed or grew the buffer behind the original's back. It is
    own.readonly now, with the fix (match the reference, or change the
    element in place);
  - `let r = &v[i]; v.push(..); *r` was not seen (the loan of
    `&v.as_slice()[i]` held no view): the loan views v, so the push is
    own.conflict.
- **Functions compiled in parallel**: `-j N` (default: the processors
  online, at most 8, fewer for a small program); the middle and back
  end's per-function state is a `FnCtx` per thread, the tasks (scalar
  pipeline, components bottom-up, emission) on a pool, the join in
  order, so the output is the same bytes for every N (tests/threads.sh,
  a gate step: every program at -j1/-j3/-j8). The -O2 self-compile from
  2.13 s (v0.18.0) to 0.72 s at -j8, -O1 0.87 to 0.37 s, -O0 0.35 to
  0.30 s (its assembler on a thread of its own).
- **Incremental rebuilds**: a task whose inputs (its functions' IR by a
  128-bit hash, what the program knows of them, the types, the compiler
  and the options) are those of an earlier build takes that build's
  output from the code cache (`target/`, `--cache=on|off`); rebuilding
  the compiler after a one-function edit takes 0.53 s at -O2 -j8 (0.47
  s with nothing changed), byte-identical to a clean build
  (tests/incremental.sh, a gate step: 148 series of edits). Off below
  8000 IR instructions and in the suite.
- **V4: every `*T` is raw.** The legacy rule (a non-`mut` `*T`
  parameter of a safe function borrowed as `&mut T`) is gone: borrowing
  is `&` and `&mut` only, and dereferencing a `*T` needs `unsafe`.
  compiler/src (358 `&mut` and 222 `&` parameters, 882 call sites, by
  `fix --values`; same-output on 8940 compilations) and std (about 90
  receivers; `read_line(&mut buf)`) moved; 0.18.0 code gets an error
  whose `try:` is `fix --values`, which keeps a pointer that is really
  raw (moved, compared, stored) raw. Not yet: the Allocator trait's
  `self: *Self` (0.19).
- **Contracts in generated code, measured** (bench/contracts against
  bench/contracts_plain, instructions): as 0.18.0 shipped them, clauses
  cost 8% more than none; with two range fixes (a length read as `len
  - 0`; one step of transitivity: `i < n` and `n <= v.len()` give `i <
  v.len()`), `x % n` ranges, and entry facts (a callee no caller inlines
  assumes its checked requires; indirect calls, C-callable and
  address-taken functions assume nothing) they save 25%: prefix -83%
  (vectorizes), dot -59%, bucket +15%, window +24% (its clause's form,
  `i + 4 <= len`, is not chained to `i + 1 < len` yet: one more check
  per call). The survey: 1670 checks left over bench and the examples,
  1564 now.
- **The 0.18 eval's polish** (docs/eval/0.18-polish-results.md: Haiku
  1.85 to 1.74 times Rust's cost, Sonnet 1.51 to 1.43, within noise
  overall; the heap task Haiku 2.52 to 1.53, Sonnet 2.11 to 1.26; Opus
  1.18, Fable 1.06): std's `BinaryHeap` and `MinHeap` in the prelude,
  `Vec::sort_by_key`, `retain`, `contains`, `first`, `(a..b).rev()`;
  Rust's default binding modes on references (`match e { E::A(n) => *n
  }` on `e: &E`); `&f(x)` and `&recv.method()` take temporaries;
  `let-else`; indexing through a reference; `ok: ...` when a check or
  build has no error; `guide std` a first page of the most used items;
  the check hook applies errors' exact fixes; `--emit-ir` to stdout;
  guide-mini answers what agents guessed; one `len()` in the corpus and
  the guide.
- **The gate**: a valgrind memcheck row in the aarch64-linux container
  (the compiler on the suite's programs); `threads` and `incremental`;
  bootstrap.sh's shared release cache under a lock.
- **Tested on aarch64 only**, as 0.15 to 0.18 (`gate.sh --with-x86`).
- **Breaking**: `*T` parameters are raw (V4): code that passed `&x` to
  a non-`mut` `*T` parameter and read through it without `unsafe` gets
  an error naming `fix --values`; std's receivers and `read_line` take
  references.

### What's new in 0.18

The design, its decisions, each task's notes and the integration with
0.17 ("as built") are in docs/design/contracts-verification.md; the
syntax in docs/grammar.md, "Additions of 0.18"; `tachyonc guide
contracts`, `guide testing`, `guide types#distinct-types`.

- **Contracts**: `requires` and `ensures` clauses between a function's
  signature and its body (functions, impl functions), `result` and
  `old(e)` in an ensures, `else "message"` or `else f"..."`, `debug`
  clauses checked only in test builds (and with `--debug-contracts`).
  The words are contextual: no program breaks. Always checked, exit 101:
  - a **requires is checked at the call**, after the arguments are
    evaluated, so the failure blames the caller's line, and names the
    clause: `main.tach:18:16: requires failed: 's.len() > 0' of 'median'
    (main.tach:2:5): s.len() = 0`;
  - an **ensures is checked in the callee** at each return (the body is
    moved to a companion function and its result checked):
    `main.tach:8:5: ensures failed: 'result <= hi' of 'clamp': result =
    6, hi = 5`;
  - a failing `&&` chain reports the conjunct that failed and the
    integer operands of its comparisons and calls;
  - conditions are pure by 0.16's effects (`contract.effect` with the
    call and a `query effects --why`); owned parameters are read in
    place, never moved; `old(..)` of a by-value owned parameter or of a
    view is `contract.old` (`old(v.len())`, `old(v.clone())`).
  - std states its preconditions as clauses (`Option::unwrap`,
    `Result::unwrap`, `Vec::get`, `set`, `swap`, `insert`, `remove`),
    with their old messages, now at the caller's line.
- **Assertions**: `assert`, `assert_eq`, `assert_ne`, `debug_assert` in
  the prelude (the bang spellings `assert!` and so on are accepted),
  each failure with its condition's text and values.
- **One failure line for every run-time check** (an index, a slice, `as
  E`, a vector lane, a contract, an assertion, `NonNull`): `FILE:LINE:COL:
  message`, from a site table the checks pass to the runtime; the `note:
  build with --trace` line is gone. Every path the compiler writes into
  what it makes (these positions, `--trace`, `--check-alloc`,
  `--check-unsafe`, `tachyonc test`'s labels, `-g`'s compile unit, whose
  `DW_AT_comp_dir` is now the root's directory) is relative to the root
  file's directory (`-g`'s `.file` names are that directory joined with
  it, so any assembler resolves them), so the output is the same whatever the current
  directory and however the root's path is spelled
  (tests/refactor/paths018). `--no-positions` makes every site 0,
  so code that only moved compiles to the same assembly.
- **The optimizer proves, never assumes**: a contract check is a check
  like a bounds check, removed only where the range analysis decides it;
  `tachyonc query checks FN|MODULE` (and `--print-checks`) lists each
  check left after the optimizer and those it removed.
- **Tests in the language**: `#[test]` functions (taking nothing or
  `gpa: Gpa`, returning `()` or a Result), `#[cfg(test)]` modules that
  see their parent's items without an import (`use super::*;` stays an
  error: no wildcard imports), `assert_snapshot(x)` against
  `tests/snapshots/`; test builds use `--trace` and `--check-alloc`, and a
  test that leaks fails.
- **Properties**: `#[property]` functions whose parameters are generated
  from their types (numbers, bool, text, Vec, Option, Result, tuples,
  Buf, the program's structs and enums through a made `Arbitrary`, or the
  program's own `impl Arbitrary` taking `&mut Gen`); 100 cases with
  growing sizes, each in its own process and leak-checked; a failure is
  shrunk and replayed with its inputs. A function with an `ensures` is
  tested as a property, its `requires` filtering the inputs.
- **Fuzzing**: `#[fuzz]` targets (a `[u8]` parameter is the input);
  `--coverage` counts the program's blocks; `tachyonc fuzz NAME` mutates
  inputs that reach new counts (AFL's buckets, splices, the program's
  string constants), shrinks a crash and saves it; `tachyonc test`
  replays the saved crashes.
- **`tachyonc test`** builds the program and its tests at -O2 and -O0,
  runs every case (`tests/NAME.in`/`.out`) and test in its own process,
  several at once, and compares the two levels: a difference is a `DIFF`
  line, the compiler's bug. Summary first, one line per failure with its
  trace, input and `try:`; `--accept`, `--cases`, `--seed`,
  `--no-contracts`, `--no-check-alloc`.
- **`tachyonc reduce` over programs**: `--differs` (-O0 and -O2
  disagree), `--fails 'TEXT'`, `--test NAME`; the program is cut by its
  layout (items, then statements) to a fixpoint, into `PROG.min.tach` (a
  planted miscompile in a generated 428-line program: 12 lines).
- **Distinct types**: `type X = distinct T` is a type of its own (Go's
  defined types): literals convert, `as` converts to and from T for free,
  T's operators and comparisons between two X, T's `Eq`, `Ord`, `Hash`,
  `Debug`, `Display` and `Clone` without an impl, none of T's methods
  (`impl X` adds its own); over plain types only (`distinct.kind`);
  mixing is `distinct.mix` with the conversion `fix --suggested` writes.
  The code generators never see one.
- **`std::NonNull<T>`**: `NonNull::new` (an Option), `as_ptr`,
  `p.is_null()` on any pointer; the null niche makes an enum of a
  fieldless variant and a NonNull one pointer, so `Option<NonNull<T>>` is
  8 bytes, C's nullable pointer and FFI-safe (layout, both back ends, the
  C ABI, `--emit-header`, the ABI fuzzer); C headers' `_Nonnull`
  pointers import as NonNull. `p as NonNull<T>` from a raw pointer is
  checked (`null pointer made NonNull`, exit 101), so safe code cannot
  make a null one.
- **std's traits on references**: `Display` and `Debug` take `self:
  &Self, f: &mut Fmt`, `Iterator::next` `self: &mut Self`, `Clone::clone`
  `self: &Self`; derive and the f-string lowering follow; an impl written
  the 0.16 way is still accepted by the legacy rule. `fix --values` now
  rewrites a program's own traits with every impl together, and respells
  impls of std's traits as their declarations; the examples, the eval's
  tasks, the tests and the guide are in the reference spelling (every
  test prints what it printed).
- **With 0.17's value semantics** (the integration's decisions, each
  tested): a requires check reads the call's arguments in place; an
  ensures may not read a by-value owned parameter (gone after the body)
  or keep a view in `old(..)`; distinct types are plain, so not over a
  reference or a type with `Drop`; `NonNull` is `distinct *T`, a value;
  generators take `&mut Gen`; property and fuzz cases are leak-checked;
  the test runtime and the fuzzer are lazy sections of std.
- **The agent eval**: `+debrief` (after the task, the same session is
  asked what confused it, which diagnostics helped or misled, what it
  would change, and three ratings; its cost apart), `run.py debrief`,
  `costx`, `binaudit`, and the 0.18 plan (216 runs).
- **V4 decided** (the user, 2026-10-16): once the compiler's source has
  moved to `&`/`&mut` (0.18.1), the legacy rule that a non-`mut` `*T`
  parameter is a borrow goes, and every `*T` is raw.
- **Caught by the release gate, fixed before the tag**: the check-site
  table wrote paths as given, so the compiler built on aarch64-linux
  differed from the cross-built one (paths relative to the root's
  directory, tests/refactor/paths018); GNU as refused the companions'
  `f?pre` symbols (`f$pre` and `f$body` now, tests/refactor/symbols018);
  nonnull_cimport needs clang (`// REQUIRES: clang`, a new directive);
  iterchain ran 5.8% more instructions than with 0.17.0, its dot loop
  unrolled twice instead of four times because a constant only a check's
  cold failure reads counted in the unroller's size (no longer,
  tests/run/opt_unroll_exit_consts); and realpath per source file had
  made compilations slow under a large directory.
- **Tested on aarch64 only**, as 0.15 to 0.17 (`gate.sh --with-x86`).
- **Breaking**:
  - std's `Display`, `Debug`, `Iterator` and `Clone` are declared with
    references; 0.16-style impls (`self: *T, f: *Fmt`) still compile
    (`fix --values` respells them);
  - `unwrap` and `Vec::get`/`set`/`swap`/`insert`/`remove` failures are
    reported at the caller's line, and every run-time failure is one line
    with a position (programs that compare stderr see the new line);
  - a failure's position, and `--trace`'s, `--check-alloc`'s and
    `-g`'s file names, are relative to the root file's directory, not
    to the directory the compiler ran in;
  - the prelude gains `assert`, `assert_eq`, `assert_ne`,
    `debug_assert`, `assert_snapshot` (a program's own names hide them);
    `test`, `property`, `fuzz` and `cfg(test)` are attributes.

### What's new in 0.17

The design, its decisions, the prototype's measurements and each task's
notes ("as built") are in docs/design/value-semantics.md; the language
in docs/grammar.md, "Additions of 0.17: familiar forms" (references,
moves and drops, std on values, the familiar forms); `tachyonc guide
memory`, `guide views`, `guide debug`; the optimizer's side in
docs/optimizer.md, "0.17: value semantics in the optimizer", "0.17:
compile time" and "0.17: cheaper f-strings"; the eval iterations in
docs/eval/0.17-iterations.md.

- **Moves and drops**: a value of an owned type (a `Vec`, `Buf`,
  `HashMap`, a type with `Drop`, a struct, tuple, enum or array holding
  one) moves on `=`, a by-value argument, `return`, a struct literal's
  field and a `move` capture; the source is dead until it is assigned
  again. Values are dropped at the end of their scope, in reverse order,
  on every exit (`return`, `break`, `continue`, `?`), as implicit defers
  the checker places: `Drop` (`fn drop(self: &mut Self)`, in the
  prelude) first, then generated drop glue (field by field, a `match`
  for enums, a loop for arrays, a `move` closure's captures); a local
  moved on some paths only carries a drop flag; assigning an owned place
  drops its old value; a discarded owned temporary drops at the end of
  its statement. `drop(x)`, `forget(x)` (leaks are safe), `needs_drop::<T>()`,
  `std::take`, `std::replace`, `T: Copy` for plain types; there is no
  `Copy` derive: what owns nothing copies, and is `Clone` without an
  impl. A view type cannot implement `Drop` (`own.drop_view`). Errors:
  `own.moved` (a use after a move), `own.move_out` (out of an index, a
  reference, a static or a borrowed binding, including a copy of an
  owned element out of `get`/`last`/`unwrap`: `try:` `x.take()`,
  `.clone()`), `own.partial`.
- **References and views**: `&T` and `&mut T` (`&x`, `&mut x`, both
  tracked; `let r = &x; r.f` is safe), `&mut [T]` the exclusive slice
  and `[T]` the read-only one. They are second-class: no lifetimes are
  written, and the checker (`front/own`, on the typed AST, after effects)
  keeps every view inside what it views: nothing writes, moves or drops a
  place while a view or loan of it is used later (`own.conflict`: a push
  while a slice of the Vec is live, a `for` over `v` pushing to `v`,
  `f(&mut a, &a)`); no view outlives its owner (`own.escape`); writes
  through `&T` and `[T]` are `own.readonly`; statics hold only views of
  constant data and are invalidated by `global` calls (`own.static`).
  Origins have two levels (what a value views, and what the views it
  holds view), so a `Vec<[u8]>` of tokens is not a view of itself;
  `&mut self` receivers are two-phase (`v.push(v.len())`); a `&mut` local
  passed on is an implicit reborrow; liveness is implicit (a view not
  used again is no conflict); disjoint fields do not overlap. `==` and
  `<` on two references compare the values (raw `*T` compare addresses).
  A non-`mut` `*T` parameter of a safe function is checked as `&mut T`
  through 0.17 (the legacy rule the compiler's own source relies on),
  and a `[T]` is accepted where `&mut [T]` is wanted, taking the
  exclusive loan.
- **Inferred view summaries**: each function has one, as it has effects:
  which parameters its result points into (`views(s)`, `views(self)`,
  `views(*self)`: carries the views `self` holds) and what its `&mut`
  parameters may come to hold (`stores(word)`), computed callees first
  over the effects' components (a recursive component to a fixed point),
  generic results parametric in their type arguments, filtered by type,
  indirect calls the join of the functions of their type whose address is
  taken. `#[views(..)]` and `#[stores(..)]` pin one (`own.views` when the
  body exceeds it). They are why a parser that keeps views of its input
  checks clean: the first design's one region per signature rejected 3.4%
  of the eval's functions; summaries reject none of them.
- **`--values`**: `error` is the default (moves, drops, views and
  exclusivity are errors, and the optimizer uses them); `warn` and
  `report` keep 0.16's semantics (no drops) and warn or list; `off` turns
  the pass off. The opt-outs are for 0.17 only.
- **The optimizer** (docs/optimizer.md): under `--values=error` a `&mut
  T`/`&mut [T]` parameter shares no memory with another reference
  parameter or a static, a `&T`/`[T]` one nothing written through it is
  read-only, and a reference parameter passed to no call is not written
  by calls; gvn, licm, slp and the vectorizer use it (`--no-noalias`,
  `--vec-stats`): the vectorizer's run-time overlap tests go (stencil 4
  to 0, matmul 2 to 0, 18% and 21% fewer lines), and a kernel of 8
  streams past the 16-pair limit vectorizes, 2.06 times faster. NRVO
  builds a returned local in the caller's result; a move in a loop is a
  copy elided. Drop glue and std's `drop` impls are `#[inline]`, so the
  drops cost what the hand-written frees did.
- **std on values**: `Vec`, `Buf` and `HashMap` implement `Drop`
  (elements dropped when they need it); `free(self)` consumes (`defer
  v.free()` stays legal and is no longer needed); `v.take()` empties and
  keeps the allocator; read-only methods take `&Self`, changing ones
  `&mut Self`; `as_mut_slice`, `s.swap(i, j)`, `v.sort()`, `s.sort()`,
  `iter_ref`; `sort`, `sort_by` and the stable sorts take `&mut [T]` and
  move elements as bits (owned elements sort; sort's code 2386 to 1887
  lines); `Vec::filled_in` clones; `HashMap::get_mut` and
  `get_or_insert` give `&mut [V]`; `Eq`, `Ord` and `Hash` take `&Self`
  (derive follows; a 0.16 impl's `*Self` is taken as `&Self`); Scanner,
  the iterators, split, trim and Fmt are views with pinned summaries.
- **`tachyonc fix --values`**: a `*T` parameter becomes `&mut T` when
  the function writes through it (transitively, to a fixed point over
  the program) else `&T`, and its calls' `&x` `&mut x`; a written slice
  parameter `&mut [T]` (`v.as_mut_slice()`, `&mut a[..]` at the calls);
  an owned parameter only read `&T` with `&v` at the calls; `defer
  x.free()` deleted. It moved 108 of the 380 tests/run programs, 30 of
  the 39 agent-eval programs, 35 of the 43 examples and 11 of the 20
  bench programs; the rest by hand (written slice locals, handle copies,
  bigint's operators, ledger's two `get_mut`). Every tests/run and
  example case prints what it printed, every bench program gives the
  same output, check-tasks grades every solution as before, and
  `--check-alloc` reports fewer leaks (drops free what programs leaked).
- **For agents**: every `own.*` diagnostic is one line with both
  positions, a `help:` with the replacement text and `try:` lines that
  run as they are (`edit patch`, `refactor signature --type v '&Vec<T>'`,
  `query own`); tests/own-try runs each `try:` of 15 situations (§2.9's
  six, the rarer conflicts, the agents' patterns that must not be
  rejected) and checks the program after it. `tachyonc query own
  FILE:LINE:COL` (each local's kind, where it moved, the views it holds,
  what invalidated them), `query views NAME|TYPE|MODULE [--why]`,
  `views:` in `def`, `show` and `context`, `--print-views`, `explain
  own.*` (every code with its fix), `refactor signature --type` and
  `refactor field --type` to references, `fmt` on `&&T`.
- **Familiar forms** (the night of 10-15's agent-efficiency work,
  measured in docs/eval/0.17-iterations.md; grammar.md "Additions of
  0.17: familiar forms"): `&mut x`; a larger prelude (`Buf`, `HashMap`,
  `read_line`, `Scanner`, `trim`, `sort`, `sort_by`, the stable sorts,
  `parse_int`, `Fmt`, `panic`, `unreachable`, ...; std loaded only where
  one is used); `panic(msg)` and `unreachable()`, safe, exit 101; `v[i]`,
  `v[i] = x`, `v[a..b]` on Vec and Buf, checked; `p[i]` on any pointer
  to a Vec, Buf or slice indexes the pointee, decided by the type as
  written (safe through a borrow, `unsafe` through a raw pointer, whose
  error names `(*p)[i]`; `p[0]` on a `*i64` names `*p`); `p.0` through a
  pointer; `s.len()` on slices and `a.len()` on arrays, `v.len` read as
  `v.len()`; module paths in code (`lexer::next(..)`, `lexer::Tok { ..
  }`, patterns) resolved as `use` lines are, beside the module then at
  the root, `ambiguous module` with both `crate::` paths when they
  differ; struct-like enum variants (`E::V { a, b }`, in patterns too);
  `b.push_str(f"..")`; constant range bounds in patterns; Rust labels get
  their tachyon spelling as `try:`.
- **Diagnostics with their fix**: name and API errors carry exact `try:`
  lines (imports, std's function forms, Rust's types, missing match arms
  to paste, argument lists, conversions); `tachyonc fix --suggested`
  applies every error's recorded fix as one checked, undoable edit
  (`--at FILE:LINE`, `--dry-run`); `let f = &factorial;` is "a
  function's name is already a pointer to it" with `try: factorial`
  (issue #1), `(*g)(4)` on a fn value `try: g`.
- **Debugging tools**: `--trace` (a shadow stack: a failed check, a
  panic, SIGSEGV, SIGALRM, SIGINT print the frames with the statement
  each runs; about 25% slower when on, nothing when off); `tachyonc probe
  FILE:LINE EXPR...` (values at a line as the program runs, from copies
  of the files); `tachyonc reduce FILE --until CMD` (line-based delta
  debugging); `tachyonc test` (a program's `tests/NAME.in`/`.out` cases,
  a compact summary within a token budget; in the tachyon tree, failures
  marked new or failing too); `guide debug` (a five-step recipe).
- **The tools for agents**: a 2k-token core guide, example-first, and a
  tiered AGENTS.md; `guide how` recipes, `query similar`, `query
  examples`; std edited by name (`edit patch std::trim`) with std
  re-embedded; the hooks rewrite a read of `.tach` source into its query
  instead of blocking it, a Stop hook checks every program a session
  touched, the check hook reports new errors as a delta and runs `tachyonc
  test`; edit, refactor and rewrite fixes from the shortfalls agents
  recorded in 0.15 and 0.16.
- **Compile speed** (docs/optimizer.md, "0.17: compile time"): a profile
  of the self-compile and its hot spots fixed (the returns-twice scan
  from 32% of -O2 to 1.7%, block layout, dominators, call pieces, fixed
  intervals, the assembler's parsing); the IR's ids local to each
  function and a per-function pipeline (each function lowered,
  optimized, emitted and freed before the next: the prerequisite for
  per-function arenas and threads in 0.18); -O1 inlines small leaf
  functions; an f-string passed straight to `print`, `println`,
  `format_in` or `push_fmt` is written in place, without a closure, an
  `Interp` instance or a generic instance. Measured in "Benchmarks",
  0.17 (docs/roadmap.md).
- **The own pass's cost**: 6.3% of the type checker on the compiler's
  source, after the checker records what the pass's fast path needs (the
  checker itself 2% slower for it): about 8.5% over 0.16's checker in
  all, against the 8% budget. Accepted for 0.17.0; recovering it is a
  0.17.1 item.
- **The agent eval**: ten small iterations after the 0.17 validation
  round (docs/eval/0.17-iterations.md): a ~600-token guide with a
  read-the-code-first line, the familiar forms (Sonnet's name errors
  0.57 to 0.14 a run), the query-first hook's rewrites (blocks 21 to 8
  per 16 runs), indexing through `*Vec` (Sonnet on task 03 from 3.6-4.7
  to 2.1 times Rust's cost); refuted: a worked program in the prompt.
  Against Rust, Sonnet is at 1.4 to 1.9 times the cost on these tasks,
  Haiku at 1.7 to 2.3.
- **Caught by the release gate, fixed before the tag**: the SLP
  vectorizer's tables by instruction were sized once at the pass's
  start; with ids local to each function, a small function whose packing
  added more than half again its instructions wrote past them (glibc
  stopped the compiler on aarch64-linux; tests/run/opt_slp_grow, reduced
  from opt_slp with `tachyonc reduce`); the own pass read before its
  place masks when a dropped local had no place (a function past 64
  places: a "Bus error" once on macOS, an invalid read under valgrind;
  tests/run/own_many_places); objcheck now builds each program with its
  test case's `// FLAGS:` and leaves out XFAIL cases, read by the suite's
  own reader (tests/directives.awk). The compiler is clean under
  valgrind on aarch64-linux on the `opt_*`, `own_*` and `fmt_*` tests,
  the bench programs and its own -O2 self-compile.
- **Tested on aarch64 only**, as 0.15 and 0.16 (`gate.sh --with-x86`).
- **Breaking** (`tachyonc fix --values` moves 0.16 code; what it cannot
  is an error with the place and `try:` lines):
  - owned values move: a use after `let w = v`, after passing `v` by
    value, is `own.moved` (`&v`, `.clone()`); a copy of an owned element
    out of a Vec, a reference or an accessor is `own.move_out`
    (`take()`, `clone()`);
  - views are checked: a slice or reference used after its owner was
    written, moved or dropped, returned out of the function owning its
    memory, or two loans of one place in a call, are errors; `--values=warn`
    is the one-release opt-out;
  - `&x` is a tracked reference, not a raw `*T` (`let p: *T = &x;` for a
    raw one); `&x` where `&mut T` is wanted is an error naming `&mut x`;
  - slices are read-only: writing through a `[T]` parameter is
    `own.readonly` (`&mut [T]`, `v.as_mut_slice()`);
  - std: `free` consumes; sorts take `&mut [T]`; `Eq`/`Ord`/`Hash` take
    `&Self`; `HashMap::get_mut` gives `Option<&mut [V]>`;
  - `p[i]` on a raw `*Vec<T>`, `*Buf` or `*[T]` indexes the pointee (it
    was pointer arithmetic), in `unsafe`;
  - the prelude gains the names above (a program's own `trim`, `sort` or
    `panic` still hides std's); `views`, `stores` are attributes.

### What's new in 0.16

The design, its work split and each part's notes are in
docs/design/effects-allocation.md; the language in docs/grammar.md,
"Additions of 0.16"; `tachyonc guide effects` and `guide allocators`;
the optimizer's side in docs/optimizer.md, "0.16".

- **Effects**: every function has an inferred set of effects: `alloc(A)`
  (which allocators it allocates from: `alloc(Gpa)`, `alloc(Arena)`,
  `alloc(extern)` for C's malloc), `io`, `global` (reads or writes a
  static), `panic`, `diverge` (may not return: a `while` or `loop`, or
  recursion; a counted `for` returns), `unsafe`. Generic functions per
  instance; calls through `fn` values and closures by the functions of
  that type whose address is taken; C functions by a table of libc
  (libm and `mem*` none, malloc `alloc(extern)`, stdio `io`, exit `io
  diverge`) or their declarations. An allocator's own methods are its
  business: a call of `a.alloc(..)` is `alloc(Arena)`, not the Gpa the
  arena refills from; `arena_scope(gpa, f)` and `a.scope(f)` are the
  closure's effects minus its scoped arena, plus the parent's. `tachyonc
  query effects NAME` (`--has EFFECT`, `--why EFFECT`: the chain of calls
  down to the source, one line a step; a module), and `query def`, `show`
  and `context` print `effects: ...`.
- **Declarations, checked**: `#[pure]` (no `alloc`, `io`, `global`),
  `#[no_alloc]`, `#[no_io]`, `#[no_panic]`, `#[effects(alloc(Gpa),
  panic)]` (an upper bound), on functions, trait functions (binding every
  impl, derived ones too) and C declarations (trusted); bounds `F: Fn(i64)
  -> i64 + effects(panic)` checked where `F` is given. std's `Eq::eq`,
  `Ord::cmp` and `Hash::hash` are `#[pure]`. A broken declaration is one
  error naming where the effect comes from (`'f' is #[no_alloc], but it
  allocates from Gpa: 'v.push(x)' at a.tach:7:9 grows a Vec<i64>`) and the
  `query effects --why` command. `--verify-effects` checks the IR's
  calls of C and stores to statics against the inferred sets.
- **Allocation is explicit**, as in Zig: nothing allocates without an
  allocator. `fn main(gpa: Gpa)` (the last parameter after `argc, argv`)
  is where a program's general-purpose allocator comes from; it is passed
  down as a parameter (`Vec::new_in(gpa)`, `with_capacity_in`,
  `filled_in`, `Buf::new_in`, `HashMap::new_in`, `collect_in`,
  `format_in`, `read_stdin_in`, `split_in`, `split_whitespace_in`,
  `sort_stable_in`); a container carries its allocator (`push` grows
  with it; `v.allocator()`). The `Allocator` trait (`try_alloc`,
  `try_resize`, `free`; `alloc`/`resize` stop on out of memory); `Gpa`;
  `Arena::new_in(gpa)` (bump allocation in chunks, the last block grows
  in place, blocks over 32 KB of their own; `used`, unsafe `reset` and
  `free_all`), `arena_scope(gpa, |a| ..)` and `a.scope(|s| ..)` (all of
  the scope's memory given back at its end), `FixedBuf::new(mem[..])`;
  `try_push`, `try_reserve`, `AllocError`. A `Fmt` never allocates
  (print's path reaches no allocator), so `println` works in
  `#[no_alloc]` code.
- **`#[sealed]` and `#[scoped]`**: std's `Vec`, `Buf`, `HashMap`, `Gpa`,
  `Arena`, `ScopedArena`, `FixedBuf` and `Fmt` are sealed: their fields
  are private to std and only std makes them (`v.len()`, not `v.len`);
  `ScopedArena` is scoped: no value holding it leaves its scope (returned,
  captured by another scope, put in a static). A static holds a
  container through a constant constructor (`static mut V: Vec<i64,
  Arena> = Vec::new_in(Arena::none());`, set up in main).
- **`--check-alloc`**: the program is built with a checking `Gpa` (any
  `-O`): every block on pages of its own, never reused, so a use after
  free, a double free, a free of a wrong pointer, size or allocator stop
  the program with where the block was allocated and freed; leaks are
  listed at exit (`gpa.live_blocks()`, `gpa.check_leaks()` in a test).
  Arenas and `FixedBuf` are checked the same way (a view used after
  `reset`, after its scope ended, after its Vec grew). With
  `--check-unsafe` too, raw-pointer accesses into Gpa's blocks are
  checked exactly.
- **The optimizer uses the effects** (docs/optimizer.md, "0.16"): calls
  of functions that read nothing are value-numbered by callee and
  arguments and hoisted out of loops (`willreturn` from counted loops,
  `nopanic`), read-only calls merged within a block; an arena's bump
  allocation inlines without a call (bench/arena_trees, binarytrees on
  std's arenas: 33 ms against C's arena 41, binarytrees on malloc 154);
  the algorithm examples' gaps: derived `Ord` in registers, `u32`
  without redundant extensions, `count_ones`/`leading_zeros`/
  `trailing_zeros` (std, AArch64's `cnt`), a widening multiply-accumulate
  vectorized (Benchmarks, 0.16).
- **Formatting without allocation and faster**: an f-string's integer
  hole with a spec is formatted in one pass, `Buf::push_int` writes in
  place (bench/fmtloop about 0.8 of 0.15's).
- **Link inputs on the command line**: `tachyonc main.tach helper.c
  lib.o -l m -L dir -o prog` compiles C files with cc and links objects
  and libraries; `-lm` is added on Linux when libm is used; `// LINK:` in
  tests. `-S` writes the symbols of generics instantiated at C types.
- **The tools**: `fix --only alloc016` moves a 0.15 program to explicit
  allocation (the calls of 0.15's allocating forms become their `_in`
  forms, `gpa: Gpa` threaded from main through every caller, before any
  parameter with a default; the reads of sealed fields become their
  methods; what cannot take a parameter, an impl of std's trait, a
  function used as a value, a default, a write of a sealed field, is an
  error naming the place); `query effects`; `rewrite` with `--subst`,
  `--list` and name holes, `query callees` (`--transitive`, `--writes`),
  refs of locals, `edit patch --nth/--all`; fmt and the refactorings know
  0.16's syntax and keep effect attributes; `same-output` finds the old
  compiler on PATH; arrays have their slice's methods (`a.iter()`).
- **Examples** (examples/README.md): one folder each, with a README
  (what it shows, how to build and run it, its output, a walk through the
  code, the guide topics): the old examples on 0.15 and 0.16 idioms, C
  interop (qsort with tachyon callbacks, a libc tour, libm, a C file
  linked in and C calling tachyon), language tours (closures and
  iterators, errors and results, traits and generics, formatting); the
  algorithm examples and the tool sessions on explicit allocation;
  examples/allocators (Gpa from main, an arena parser, scoped arenas, a
  fixed buffer, five memory bugs `--check-alloc` stops) and
  examples/effects (`#[pure]` and `#[no_alloc]`, effect bounds, trait
  purity, `query effects` for agents), each README a tested session;
  every example's test also runs under `--check-alloc` in the gate.
- **Fixed**: at -O1 a nested pattern naming an enum's only variant
  (inside `Ok(..)`) branched to a block that did not exist ("cannot
  assemble"); examples/errors-and-results printed an error holding a
  view of input it had freed.
- **The compiler's source** on 0.15's features (f-strings for its
  messages and text, widening, `any`/`all`, field shorthand, named
  arguments) in the back end, base, gen0 and part of the front end (the
  lexer, C import, derive, conversions, associated types, patterns,
  modules); the checker finds types and instances by hash (it scanned);
  six modules over 1000 lines split with `refactor split`; same-output
  identical throughout. The rest of the front end and the tools move in
  0.17.
- **The agent eval**: compiler tasks (an optimization, a cross-module
  rename, a checker fix, a std method) run with and without the tools
  (`--set`, `--reps`, `plans/0.16.md`).
- **Tested on aarch64 only**, as 0.15 (x86_64 off by default,
  `gate.sh --with-x86`).
- **Breaking** (`tachyonc fix --only alloc016` moves 0.15 code; what it
  cannot is an error with the place and what to write):
  - allocation is explicit: `Vec::new()`, `Buf::new()`,
    `HashMap::new()`, `with_capacity`, `filled`, `collect()`,
    `format(x)`, `read_stdin()`, `split`, `split_whitespace`,
    `sort_stable` are errors naming their `_in` form; `main` takes
    `gpa: Gpa` to allocate; a parameter's default cannot allocate;
  - std's containers are sealed: `v.len`, `v.cap`, `v.ptr`, `b.bytes` and
    `Vec { .. }` literals outside std are errors (the methods: `len()`,
    `capacity()`, `as_slice()`); with_capacity reserves exactly what it is
    asked (at least 4), no longer the next power of two;
  - the I/O API: `read_line(&buf)` takes a `Buf` of any allocator;
    `read_stdin_in(gpa)`, `split_in`, `split_whitespace_in`, `format_in`;
    `Fmt::to_buf` is gone (`buf.push_fmt(x)` with a `Display`);
    `Fmt::spec` returns a `FmtSpec`;
  - `Eq`, `Ord` and `Hash` impls must be pure (no statics, I/O or
    allocation: keep a comparator's state behind a pointer);
  - the prelude gains `Allocator`, `Gpa`, `Arena`, `ScopedArena`,
    `arena_scope`, `format_in`; `pure`, `effects`, `no_alloc`, `no_io`,
    `no_panic`, `sealed`, `scoped` are attributes.

### What's new in 0.15

The design, its work split and each part's notes are in
docs/design/errors-formatting.md; the language in docs/grammar.md,
"Additions of 0.15"; `tachyonc guide conversions` and `guide formatting`.

- **Errors and `?`**: `e?` on an `Option` gives the value or returns
  `None`; on a `Result` the value or `Err(e)`, the error widened or
  converted by the function's error type's `impl From`. Inside a closure
  it returns from the closure; defers run. `fn main() -> Result<(), E>`
  prints `Error: {e:?}` on stderr and exits with 1. Errors name what to
  write (`-> Result<i64, E>`, `e.ok_or(..)?`, the `impl From` to add).
- **Generic traits, `From` and `Into`**: traits take type parameters
  (`trait From<T>`), impls name concrete types or their own parameters,
  bounds pass arguments (`T: From<U>`); a call picks the impl by its
  argument types. `From` holds without an impl for the identity and for
  widening (`i64::from(x_i32)`); `x.into()` is `U::from(x)` with `U` the
  expected type. std's `Option`/`Result` helpers: `ok_or`, `map`,
  `and_then`, `map_err`, `unwrap_or_else`, `err`.
- **std's I/O on `Result`**: `read_line(&buf) -> Result<bool, IoError>`,
  `read_stdin() -> Result<Buf, IoError>`, `parse_int -> Result<i64,
  ParseIntError>`, `Scanner::next_int -> Result<i64, ScanError>`; the
  error enums have `Display` and `Debug`. Option means absence, Result
  failure. `tachyonc fix --only std015` moves 0.14 code (exact but for
  `read_stdin` on a read error).
- **Widening**: a narrower integer converts implicitly to a wider one of
  the same signedness, and unsigned to a wider signed one, wherever a
  value meets an expected type (lets, assignments, arguments, returns,
  fields, elements) and where two types meet (operands, `if`/`match`
  branches, two arguments of one type parameter: `max(a_i32, b_i64)` is
  `max::<i64>`); never inside other types, never narrowing, never
  between integers and floats. An expected type flows into arithmetic
  (`let t: i64 = a_i32 * b_i32` multiplies in `i64`). `i64::MAX`,
  `u8::MIN`, ... are constants of the integer types (std's `I64_MAX`
  ... are the same).
- **Formatting**: f-strings, `f"p = {p:?}, x = {x:>4}, {n:08x}"`
  (width, alignment, zero padding, precision, hex, binary, a byte;
  `{{`), evaluated where written, holes once and left to right; a value
  of type `Interp` that any `T: Display` takes. `Display` and `Debug`
  (`fn fmt(self: *T, f: *Fmt)`, `fn fmt_debug`), implemented for the
  numbers, `bool`, `[u8]` (Debug quoted and escaped as Rust's), `Buf`,
  and Debug for `Option`, `Result`, `Vec`, `HashMap`; floats print the
  shortest decimal that reads back. `print`, `println`, `eprint`,
  `eprintln`, `format` and `Buf::push_fmt` take any `Display`; output
  goes through one static 4 KB buffer, one `write` per print, no heap:
  `bench/fmtloop` (10^6 formatted lines) matches the same text built by
  hand (`bench/fmtints`). `println!` and Rust's `fmt(&self, f: &mut
  Formatter)` get the tachyon form in their help; a plain literal with
  `{name}` of a local passed to print gets a warning.
- **derive**: `#[derive(Eq, Ord, Hash, Debug, Clone)]` on structs and
  enums (generic ones too, each parameter bound by the trait): Ord
  lexicographic in declaration order, Debug as Rust's (`P { x: 1, y: 2
  }`), Clone field by field (a Vec deep). `Clone` in std; tuples of
  Eq/Ord/Hash/Clone types are those too (`sort` sorts tuples,
  `HashMap<(i64, [u8]), V>`); `sort_stable` and `sort_stable_by`.
- **Less boilerplate**: named arguments after the positional ones, in
  the parameters' order (`area(w, h: 2)`); defaults on trailing
  parameters of functions and inherent methods (`fn f(x: i64, step: i64
  = 1)`), evaluated per call in the callee's module; field shorthand `S
  { x, y }`.
- **`==` on `Vec`, `Buf` and `HashMap` compares contents** (Vecs element
  by element, maps by entries in any order); `==` on a `Vec<T>` needs
  `==` on `T`.
- **Compile time**: std is loaded by sections: an index made with std's
  source (compiler/std/index.awk) lets the loader lex only the sections a
  program reaches (Vec and printing always; HashMap, iterators, text,
  conversions, Clone when named or needed). A small std program compiles
  faster than with 0.14.0 although std grew from 46 to 90 KB (`Benchmarks`,
  0.15).
- **The tools for agents** (docs/tool-gaps-014.md, from the 0.14 eval
  and development record; docs/query.md, docs/refactor.md): `query
  context NAME` (the item, what it calls and uses, its callers, fitted to
  a budget); `--budget N` on every query, long answers cut with the
  command that gets the rest; std from any program (`query items std`,
  `show std::read_line` with the `use` line, `text std:A-B`, `grep --in
  std`, a name std defines asked again with std); every spelling a tool
  prints accepted back as a name; `tachyonc try 'STATEMENTS'` (a snippet
  compiled and run with std, its value and type printed); `guide --find
  WORDS`, `explain WORDS`; `tachyonc batch` (several commands in one
  call); `edit apply` (blocks per item, or `query show`'s output edited)
  and `edit patch` over several targets; `edit.breaks` saying what broke
  and the refactoring that would carry the change; `query conflicts` and
  `edit resolve` for merge conflicts in `.tach` files; `--json` on every
  command; builds off a terminal print the one-line errors; the check
  hook (tools/agent-hooks/check-after-edit.py: errors after every edit
  of a .tach file); tachyonc recognised through copies and variables,
  `target/tools/tachyonc`. fmt, query and the refactorings know 0.15's
  syntax (`signature --add 'x: T = V'` declares a default; `--fill-calls`
  is 0.14's behaviour).
- **Loops as cc compiles them** (docs/optimizer.md, "0.15"): a select in
  the middle end and if-conversion of small branches in innermost loops
  (`if x > r { c += 1 }` is a sum); masks and minimum/maximum reductions
  in the vectorizer; one accumulator per copy in the run-time unroller
  for associative integer reductions; the vectorizer's cost model weighs
  a 64-bit multiplication lane by lane against the unrolled scalar loop;
  `ldp`/`stp` pairs on AArch64. bench/iterloop (six kernels by hand) went
  from about 2.1 times cc -O2's time to about 1.0 to 1.1 (Benchmarks,
  0.15).
- **Examples**: examples/algorithms, ten algorithms (Dijkstra, Kruskal,
  topological sort, string search, Huffman, an LRU cache, big integers,
  quickselect, sudoku, n-queens) in idiomatic 0.15, each with a README,
  a C reference and a test; examples/tools, eight sessions with the
  tools (exploring unknown code, fixing errors, merge conflicts, proving
  a change unchanged, renames and moves, rewrites, signatures and
  variants, splitting a module), each README a transcript that
  tests/walkthrough/run.sh replays.
- **The compiler's source**: the back end, gen0 and base iterate with
  `IntVec::items()`, `kids(n)` and std's `any`/`all`/`position`/`find`
  (through `rewrite`, which gained `$s...` holes over a block's
  statements); same-output identical, self-compile time unchanged. The
  front end and the tools move in 0.16.
- **The agent eval, harder**: tasks 13-18 (porting a C compressor, a
  pass over an interpreter's AST, a multi-module CSV query engine, a
  tight perf limit, three run-time bugs, an API refactor); `run.py
  --check-hook`, and the errors left at the end in each result.
- **Also**: `query refs` no longer counts a trait's `Self` as a use of
  each type implementing it; a negated suffixed literal under an
  expected type (`let d: i64 = -9223372036854775808i64`) is no longer
  out of range.
- **Tested on aarch64 only**: 0.15's release gate ran on aarch64-macos and
  aarch64-linux; x86_64 (the x86_64-linux container) is off by default
  from 0.15 (`bootstrap/gate.conf`, `gate.sh --with-x86`). Its one run on
  0.15's tree failed only the new walkthrough sessions (a path in their
  transcripts, fixed after).
- **Breaking**: `read_line`, `read_stdin`, `parse_int` and
  `Scanner::next_int` return `Result` (`fix --only std015`); `==` on
  `Vec`, `Buf`, `HashMap` compares contents, no longer the pointer; the
  prelude gains `Display`, `Debug`, `Clone`, `From`, `Into`, `format`,
  `eprint`, `eprintln` (a program's own names come first); `f(label:
  loop { .. })` is a named argument; integer types that mismatched before
  may now widen (a program valid in 0.14 keeps its types).

### What's new in 0.14

- **Closures** (docs/grammar.md, "Additions of 0.14"; `tachyonc guide
  closures`): `|x| x + k`, `move`, `|x| -> T { .. }`, patterns as
  parameters. Each closure has its own type; an immutable variable is
  captured by value (by reference above 32 bytes or when the closure
  takes its address), a `let mut` one by reference, everything by value
  with `move`. `Fn(A) -> R` and `FnMut(A) -> R` bounds, monomorphized,
  type the closure's parameters and bind what their result names; a
  closure that captures nothing coerces to a `fn`. A value holding a
  closure that borrows a variable cannot leave that variable's block.
- **Associated types**: `type Item;` in a trait, `type Item = T;` in its
  impls, projections `T::Item` and `Self::Item`, `F::Output` of fn types
  and closures, constraints `I: Iterator<Item = T>` (checked, and used
  for inference); a trait default copied into a non-generic impl is
  checked and compiled only when used; `impl<T> [T]` and `impl<T> Tr for
  [T]` for slices.
- **Iterators** (`tachyonc guide iterators`): the `Iterator` trait in
  the prelude; `for` over slices, arrays, `Vec`, ranges, iterators and
  types with an `iter()` method, or a pointer to one; `a..b` and `a..=b`
  as values; std's sources (`v.iter()`, ranges, `HashMap::iter`, `keys`,
  `values`), adapters (`map`, `filter`, `enumerate`, `zip`, `take`) and
  consumers on `fold` (`for_each`, `count`, `sum`, `min`, `max`,
  `collect` into a `Vec`), `sort_by` with an `FnMut` comparison.
- **Zero cost** (docs/optimizer.md, "0.14: zero-cost iterators"): an
  iterator chain, once inlined, is the hand-written loop, with no call,
  no frame slot and the same vector loop: copy elision, SROA to a
  fixpoint, threading on constant tags, the merging of counted exits,
  #[inline] functions optimized after inlining, closures called once
  always inlined. `bench/iterchain.tach` (six kernels with std's
  iterators and closures) against `bench/iterloop.tach` (the same
  loops by hand): `bench/run.sh` fails above a ratio of 1.05.
- **std** (`tachyonc guide std`): `read_line(&buf)`, `read_stdin()` and
  a `Scanner` read stdin without `unsafe`; `parse_int`, `trim`, `split`,
  `split_whitespace`, `is_space`, `is_digit`; `Vec::last`, `swap`,
  `insert`, `remove`, `truncate`, `extend_from_slice`;
  `HashMap::contains_key`, `get_mut`, `get_or_insert` (a one-element
  slice: `counts.get_or_insert(w, 0)[0] += 1`); `sort` is an introsort
  (4M random i64: 302 to 195 ms). std's functions that the program does
  not reach are dropped before the optimizer.
- **Diagnostics for newcomers**: did-you-mean for methods, fields,
  associated functions, variants and module items; an unknown name that
  std has gets its `use` line (and `tachyonc fix` writes it), one with
  no close match points to `tachyonc guide std`; helps for Rust habits
  (macros, `&str`, `&self`, `?`, `String`, `.chars()`, ...); a private
  item's help makes it `pub`; errors past a failed condition are
  reported in the same pass; `const S: [u8] = "..."`; an unsuffixed
  literal takes the type of the other branch or arm; `mod eval; use
  eval::eval;` as in Rust.
- **Tools on a user's program** (docs/refactor.md, docs/query.md):
  `undo` and `query diff` without git; `refactor rename` of a local or
  parameter (`FILE:LINE:COL`, `FN::local`), its captured uses included;
  comment mentions renamed only in backquotes; `refactor variant --add
  --arm-in SITE EXPR`; `edit patch FILE:LINE` between items; edits add
  the imports their new text needs; `refactor --script` heredocs; import
  paths in the file's style. query, refactor, rewrite and fmt know
  closures.
- **The agent eval** (`tests/agent-eval/`, docs/eval/): twelve tasks
  (write, fix, extend, refactor, perf) with hidden tests and Rust twins;
  `run.py` puts Claude Code or an Ollama model on each task in five
  conditions and reports. The 0.13 baseline (Claude Haiku and Sonnet,
  59 of 60 runs each; a partial Qwen3-Coder run) and what it changed are
  in docs/eval/0.13-findings.md.
- **No undefined behaviour, fixed**: slicing (and vector loads and
  stores) read the slice after its bounds, so a bound that grew the
  storage read freed memory; `Buf::push_str` of its own view read freed
  memory; the compiler indexed its tables through calls that can move
  them (a wrong struct or a crash on generic literals). The gate's new
  `stress-grow` step moves every table growth of the compiler and
  checks the self-compile and the suite.
- **Also**: `==` on slices without std and on types holding a part with
  an `impl Eq`; bounds of declared types (`HashMap<i64, i64>` as a
  field) checked once every impl is known; generic instances limited by
  the size of their type arguments (chains of hundreds of adapters);
  worktrees share the main checkout's release cache.
- **Breaking**: nothing (`move`, reserved before, is now a keyword; a
  program's own `Iterator` comes before the prelude's).

### What's new in 0.13

- **Edits** (docs/refactor.md): `edit patch` takes an OLD that starts
  or ends inside a line, in every form, and says where a multi-line OLD
  stops matching; `--pairs FILE` reads the pairs from a file (and `try:`
  lines with pairs of several lines suggest it); `edit wrap TARGET --in
  HEAD` puts a body or a range of lines in a block, re-indented; `edit
  new-file PATH` writes a file and its `mod` line in one checked edit;
  `refactor signature --type x T --default EXPR` rewrites each call's
  argument; `fix --in MODULE` covers the module's children for every fix.
- **Queries** (docs/query.md): `query items MODULE --comments` lists the
  section banners and the comments outside items, `query show
  MODULE::section TITLE` prints a section; `query grep` searches the
  program's text, each hit with its item and whether it is code, a
  comment or a string; `query type FILE:LINE[:COL]` gives an
  expression's checked type; `refs` and `callers` print each
  reference's kind (read, write, call, init, type, use, mod, pat), and
  `--kind` keeps some. The hook suggests `query grep` for text searches.
- **A cache** (docs/query.md, "Speed: the cache"): a command that reads
  a program in full leaves its front end under `target/tachyonc-cache`,
  and `query def`, `show`, `refs`, `callers`, `items`, `check` and the
  reading of `edit` take it from there while the program's files are
  unchanged: about 6 to 8 ms on the compiler's source instead of about
  60. `TACHYON_CACHE` names another directory, or `off`. The answers are
  the same: the tools' tests run every transcript with and without it.
- **Refactorings** (docs/refactor-modules.md, docs/refactor-shape.md):
  `split --plan` names each part from its banner, the type its items
  operate on or a common prefix (`--names` gives them); `move --after`
  and `--before ITEM`; the blank lines around moved items and their
  banners kept, so a move and the move back leave every file as it was
  (tests/refactor/roundtrip.sh); `refactor extract-function FN --lines
  A-B --to NEW` (parameters and result computed) and `refactor inline
  FN` (a small function's body at its calls).
- **`tachyonc fmt`** (docs/fmt.md): one layout for tachyon source, with
  no options; a formatted text must lex to the same tokens and comments
  or the file is left as it is. Every edit, fix and refactoring lays out
  the lines it writes the same way. The tree is formatted (only blanks
  changed: `same-output` against 0.12.0 is identical), and
  tests/fmt/run.sh keeps it so. **`tachyonc explain CODE`**: what a
  diagnostic code means, how to fix it, an example, for every code the
  tools print and the compiler's error and warning kinds.
- **`tachyonc guide`**: the language for a reader who knows Rust, built
  into the compiler (the core guide about 5k tokens, `guide TOPIC`,
  `--list`, `--all`; std's API made from std's own source); every
  example in it is compiled and run by `tests/run.sh guide`.
- **Breaking**: nothing in the language. `query refs` and `callers`
  print a kind column in each line.

### What's new in 0.12

- **The compiler's source, reorganized** (compiler/README.md): six
  folders by phase (`base`, `front`, `middle`, `back`, `gen0`, `tools`),
  each with a README; the 25 files over 1,000 lines split by concern
  into folders of their own (77 files before, 172 now, none over 1,000
  lines: `tachyonc lint --max-lines 1000`); every import names the module that
  defines what it imports (no re-exports), the `use` lines merged,
  sorted and wrapped. Done with the compiler's own tools, almost every
  edit through them (docs/agent-tool-usage.md, 0.12), and proven to
  change nothing: `same-output` identical over 4,668 compilations, the
  0.12.0 compiler emits what 0.11.0 does.
- **Tools** (docs/refactor.md, docs/refactor-modules.md, docs/query.md):
  `edit patch TARGET --old --new` and `edit insert --in` (edits inside an
  item, by its text, checked and undoable), `--show`, `query diff`,
  `query text FILE:A-B`, `query show FILE` and a module's regions;
  `MODULE::use` and `MODULE::header` as targets of `edit patch`,
  `replace`, `insert`, `delete`; `fix --only tidy-imports` and `fix
  --only reexports` (`// api:` keeps a re-export); `refactor split
  --reexport` and `--header`, parts headed by their banner, runs of items
  kept together, banners moving with most of their group; `move` and
  `split` leave tidy imports. The agent hook judges writes by the files
  written, logs which agent made each record, and with
  `tools/agent-feedback` finds the log without running git.
- **The gate in one command**: `bootstrap/gate.sh --release` runs the
  chain, the suite at every level, the fuzzers and the Linux containers
  at once and prints one table; `bootstrap.sh --history fast` checks the
  older releases' fixpoints without their suites;
  `tests/fuzz/forever.sh` fuzzes between releases.
- **Breaking**: nothing in the language or the command line.

### What's new in 0.11

- **Debug information**: `-g` writes DWARF line tables (and the compile
  unit's functions) in the assembly and in the objects the compiler
  writes, Mach-O and ELF; on macOS `dsymutil` runs after linking. lldb
  and gdb stop at source lines and show `file:line` in backtraces. The
  output without `-g` is unchanged.
- **aarch64-linux** as a target (`--target aarch64-linux`: AAPCS64, ELF,
  `import` of its headers) and a host, whose compiler is cross-built on
  another host and then rebuilds itself there to the same object (see
  "aarch64-linux: cross-built, then checked natively" below).
- **Faster code**: a cost model for the loop vectorizer (expected trips
  from constant bounds or the profile, and against unrolling a short
  loop whole), unrolling of loops with run-time trip counts, an SLP
  vectorizer (stores to the lanes of a vector packed with their values),
  division and remainder by constants as multiplications, value ranges
  through phis (more bounds checks removed), branches on `&&` threaded,
  equalities from branches. `bench/` has six more programs (binarytrees,
  fannkuch, json, mandelbrot, sort, wordcount), each with its C version,
  and a geometric mean against `cc -O2`: tachyon -O2 is at 0.95 of it
  (docs/roadmap.md, "Benchmarks").
- **Tools for agents** (docs/query.md, docs/refactor.md and the pages it
  links): `tachyonc query` (`def`, `show`, `refs`, `callers`, `items`,
  `stats`, `deps`, `unused`, `impact`), `tachyonc check` (the front end
  only, one line per error), `fix` (missing and unused imports, `pub`,
  `unsafe` blocks), `lint --max-lines N`, `same-output OLD_TACHYONC`;
  `edit replace|insert|delete NAME` and `undo`; `refactor rename`, `move`,
  `new-module`, `move-module`, `split`, `signature`, `field`, `variant`,
  the typed `rewrite`, and `refactor --script`. Every edit is checked
  before it is written (nothing is written when it adds an error).
  `--diagnostics=short`: one line per error, with a stable code and a
  suggested fix. AGENTS.md and a hook for agents working on the compiler
  (`tools/agent-hooks/`).
- **Fixed**: `x as i64 < n` compares (a primitive type takes no type
  arguments); it failed with "expected '>'" when `n` was followed by `.`.
- **Breaking**: nothing in the language. On the command line, a first
  argument `query`, `edit`, `undo`, `check`, `fix`, `lint` or
  `same-output` is a command, not a file to compile.

### What's new in 0.10 (in progress)

- **Unsafe operations are errors.** An unsafe operation outside unsafe
  code is `error[unsafe]` (a warning in 0.9); `tachyonc --fix-unsafe`
  still adds the blocks. `--allow-unsafe` is gone (breaking): the
  compiler's own source is in unsafe code (whole function bodies in one
  block where a function has several unsafe operations), and the
  bootstrap builds 0.10 through the interface `tachyonc-0.10`, which does
  not pass it. Releases before 0.10 are built as before.
- **Vector types** `v2f64`, `v4f32`, `v2i64`, `v4i32`, `v8i16`, `v16i8`:
  lanewise arithmetic, masks, select, lanes, sums, checked loads and
  stores (grammar.md, "Additions of 0.10"); NEON and SSE2. Their names are
  reserved (breaking, for programs naming an item so).
- **Loop vectorizer** for counted loops over slices and arrays, guarded
  at run time; `--no-vectorize`; `tests/fuzz/run.sh -V`.
- **Profiles**: `--profile-generate FILE` and `--profile-use FILE` (block
  layout, inlining, unrolling).

### What's new in 0.10

- **`unsafe` is enforced** (breaking): an unsafe operation outside an
  `unsafe` block or `unsafe fn` is an error, not a warning. Safe code has
  no undefined behaviour. The compiler's own source moved to `unsafe`
  blocks (its output byte-identical before and after).
- **Vector types** `v2f64`, `v4f32`, `v2i64`, `v4i32`, `v8i16`, `v16i8`:
  lanewise arithmetic, masks and `select`, lanes, horizontal sums, and
  bounds-checked loads and stores; NEON on AArch64, SSE2 on x86-64. Not
  allowed in `extern "C"` signatures yet.
- **A loop vectorizer**: counted inner loops (maps, integer reductions)
  and the loop around one inner loop (matmul), behind run-time checks
  that prove the bounds and rule out overlap, the original loop kept as
  the remainder; `--no-vectorize`. Float reductions are not vectorized
  (that would reorder additions).
- **Profile-guided optimization**: `--profile-generate`, then
  `--profile-use FILE`; the counts steer block layout, inlining and
  unrolling.
- **`--check-unsafe`**: a checking mode for `unsafe` code.
- **Every error of a compilation is reported**: declarations recover one
  by one, and a syntax error no longer stops the type checking of
  everything else.

### What's new in 0.9 (in progress)

- **Unsafe code.** `unsafe { ... }` blocks and `unsafe fn`: dereferencing,
  indexing and slicing raw pointers, integer-to-pointer casts, calls into
  C and to `unsafe fn`, and reading union fields are allowed only there,
  so safe code has no undefined behaviour. Pointer parameters (and
  `self: *T`) are *borrows*, dereferenced in safe code; passing a raw
  pointer to one is unsafe. In 0.9 an unsafe operation outside unsafe
  code is a warning (`warning[unsafe]`; `--deny-warnings` makes warnings
  errors), an error from 0.10; `tachyonc --fix-unsafe` adds the blocks.
  The compiler's own source is built with `--allow-unsafe` (interface
  `tachyonc-0.9`) until 0.10 migrates it. std's `panic`, `print_cstr` and
  `Buf::push_cstr` are `unsafe fn` (breaking). The tests, examples,
  benchmarks and fuzzers are unsafe-clean, and the test suite compiles
  every case with `--deny-warnings`.
- **Traits.** `trait` declarations (with default functions), `impl Trait
  for Type` for any type, generic impls with bounds, bounds `T: Hash +
  Eq` on functions, structs and enums, checked at instantiation, one impl
  per trait and type. Static dispatch only (no `dyn`). Operators on user
  types through std's `Add`, `Sub`, `Mul`, `Div`, `Neg`, `Eq` (before the
  structural `==`) and `Ord`. std gains `Hash`, impls for the primitives
  and byte strings, `HashMap<K: Hash + Eq, V>` and `sort`. Unbounded
  generics are unchanged.
- Smaller: array constants, string literals in static aggregates, line
  continuations in string literals, `if`/`else` inference of `Some`/
  `None`, and `$TACHYON_CC` naming a cross C compiler for `import`.
- **E-graph.** GVN's table is an acyclic e-graph with a table of rewrite
  rules (a small pattern language) and cost-based extraction;
  `tachyonc --check-rules` checks every rule on random values at every
  integer width (tests/run.sh runs it).

### What's new in 0.9

- **`unsafe`.** Raw-pointer dereference, indexing and slicing, integer to
  pointer casts, calls to C functions and to `unsafe fn`, and reading a
  union's field need an `unsafe { ... }` block or an `unsafe fn`: safe code
  has no undefined behaviour (see [grammar.md](grammar.md), which also
  states the gaps left: slices outliving their storage). A pointer
  parameter that is not `mut` is a borrow, and dereferencing it is safe.
  In 0.9 an unsafe operation outside `unsafe` is a warning
  (`--deny-warnings` makes it an error, as every test does); from 0.10 it
  is an error. `tachyonc --fix-unsafe` adds the blocks. Breaking: std's
  `panic`, `print_cstr` and `Buf::push_cstr` are `unsafe fn`.
- **Traits**: `trait`, default functions, `impl Trait for T`, generic
  impls with bounds, bounds on functions and types (checked at
  instantiation), one impl per trait and type; operator traits `Add`,
  `Sub`, `Mul`, `Div`, `Neg`, `Eq`, `Ord`. std: `Hash`, `Eq`/`Ord`/`Hash`
  for the integers, `bool` and `[u8]`, `std::HashMap`, `std::sort`. No
  trait objects yet. Unbounded generics mean what they did.
- Array constants, string literals in static aggregates, `\` line
  continuations in strings, `Some`/`None` inferred across `if`/`else`;
  `$TACHYON_CC` names a cross C compiler for `import`.
- **An e-graph**: GVN works on an acyclic e-graph (as Cranelift's aegraph)
  with 31 rewrite rules in a small pattern language, the cheapest member
  of each class extracted; `tachyonc --check-rules` tests every rule on
  random values at every integer width (run by the test suite). It costs
  about 5% of `-O2` compile time.

### What's new in 0.8

- **No wildcard imports** (breaking). `use a::b::*;`, `use E::*;` and
  `import "h.h";` without `as` are errors: every name a file uses is
  declared in it, imported by name (`use a::b::{c, d}`), or written with
  its path; C headers are imported as `import "stdio.h" as c;` and used
  as `c::printf`. What a name means is visible where it is used. The
  prelude, a fixed list, stays.
- **`tachyonc --fix-imports FILE...`** rewrites code written for 0.7 and
  earlier: each wildcard becomes the list of names the file uses through
  it, each header import gets `as c` and its uses `c::`. The errors for
  the removed forms suggest the same rewrite.
- The compiler's own source, the tests and the fuzzers use explicit
  imports (380 wildcards replaced; the compiler built before and after
  is byte-identical).

### What's new in 0.7

- **Object files.** The compiler assembles its own output: Mach-O for
  macOS (arm64, x86-64) and ELF for Linux; `cc` only links. `-c` writes an
  object, `-S` (or `--emit-asm`) assembly, any other output an executable.
  The objects are checked against `cc -c` of the same assembly over the
  whole corpus (`tests/objcheck.sh`), and are identical whatever the host.
  The compiler builds itself to an executable in 0.6 s at `-O2` (2.7 s
  with 0.6.0) and 0.12 s at `-O0` (1.9 s).
- **Indexing a fixed array is checked** (breaking): `a[i]` on `[T; N]`
  panics like slice indexing (exit 101) when out of bounds; the optimizer
  removes the checks it proves unneeded.
- **No undefined behaviour** is now a principle of the language;
  [grammar.md](grammar.md) lists what is defined and the little that is
  not yet (raw pointers, C calls), which 0.8 puts behind `unsafe`.
- The bootstrap uses objects from 0.7 on (interface `tachyonc-0.7`; the
  fixpoint compares objects).

### What's new in 0.6

The compiler's own source is a module tree in the 0.5 language (generics
for its arrays, `Option` for lookups, enum variants by name), checked to
emit byte-identical output to 0.5.0. Releases from 0.6 on name their root
file in `bootstrap/releases.toml`.

The language (see [grammar.md](grammar.md), "Additions of 0.6"); two
changes are breaking:

- **String literals are `[u8]` slices** (they were `(*u8, u64)` tuples):
  `.ptr` and `.len`, and `println("hello")` works. `c"..."` is still a
  `*u8`.
- **Two `*` imports bringing different things under one name** make it an
  error where the name is used (0.5 took the first).
- `if let` and `while let`; `defer` (run when the block is left, last
  first, on every way out but a panic); `==` and `!=` on structs, tuples,
  arrays and enums with fields, field by field; a prelude (`Option`,
  `Some`, `None`, `Result`, `Ok`, `Err`, `Vec`, `print`, `println`
  without `use`, shadowed by anything the program declares or imports);
  `#[inline]`, `#[inline(never)]`, `#[cold]`; inline modules
  `mod m { ... }`; generic type aliases; attributes before `pub`.

The optimizer (see [optimizer.md](optimizer.md)): a whole-program layer
at `-O2`: interprocedural constants (arguments into internal functions,
results out) and devirtualization, inlining bottom-up over the call graph
with a cost model and budgets, function attribute inference (readnone,
readonly, noreturn, willreturn, nopanic, nocapture; `--print-attrs`) used
by GVN, LICM and dead code elimination, scalar promotion of memory in
loops, small non-escaping heap allocations moved to the stack, global
dead code elimination, value ranges of sums and products. The back end:
shrink-wrapping (the frame only on the paths that need it), coalescing
hints for phis, comparisons with immediates. `--time-passes` and
`--stats` measure the compiler and its output; compile times are part of
every release from now on (see [roadmap.md](roadmap.md)).

### What's new in 0.5

The language (see [grammar.md](grammar.md), "Additions of 0.5"):

- **Generics** by monomorphization, checked at instantiation: generic
  functions, structs, enums and `impl` blocks, methods with type
  parameters of their own; type arguments written (`Vec<i64>`,
  `max::<i64>(..)`, `Vec::<u8>::new()`) or inferred from the arguments
  and the expected type. An error inside an instance names the
  instantiation chain. Bounds (traits) are left for later; adding them
  will not change what today's programs mean.
- **Modules**: a file is a module (`mod m;` loads `m.tach` or
  `m/mod.tach`); items are private unless `pub`; paths with `crate`,
  `self`, `super`; `use a::b::{c, d as e}`, `use a::b::*`, `pub use`;
  `import "h.h" as c;` puts a header's declarations under `c::`. Several
  files on the command line still make one root module.
- **Several errors per compilation**: the parser and the checker recover,
  and errors that follow from an earlier one are not reported.
- **A small standard library**, built into the compiler: `std::Option`,
  `Result`, `Vec`, `Buf`, printing.
- `size_of` and `align_of` are always the builtins; `#[repr(C,
  align(N))]` up to 4096, and C records aligned above 16 import normally.
- The layout and calling convention of plain functions and default
  types stay unspecified: at `-O1`/`-O2` plain functions now use a
  convention of tachyon's own; everything C can reach keeps C's.

The back end (see [optimizer.md](optimizer.md)): register allocation by
linear scan on SSA with lifetime holes and interval splitting, coalescing
hints and rematerialization, checked by `--verify-regalloc`; a calling
convention of its own (16 integer and 16 float argument registers on
AArch64, aggregates in registers); realigned frames; instruction selection
by per-target rule tables (scaled-index addressing, `lea`, `madd`, shifted
operands, `ubfx`, `tbz`, `csel`/`csinc`/`cmov` selects, libm calls as
instructions where exact); block layout by fall-through with cold paths
last and tail duplication; `stp`/`ldp` and other post-allocation
peepholes; leaf functions without frames; sibling calls; `setjmp` and
other calls that return twice handled soundly. Tests: `ASM(T):`
directives, `ERROR-COUNT:`, several `ERROR:` lines; random programs in
generics, register-pressure and calls modes; `--emit-mir`.

### What's new in 0.4

The compiler's own source is written in the 0.3 language (enums and
`match` for every kind of node, token, type and instruction; methods;
slices; `extern "C"` blocks), checked to emit byte-identical output to
0.3.0 by `tests/compare.sh`, which compares two compilers over the suite,
examples, benchmarks, random programs and the compiler itself.

The language (see [grammar.md](grammar.md)); two changes are breaking:

- **A slice's `len` is `i64`** (it was `u64`); indexing accepts any
  integer type.
- **The 0.2 form `extern fn f();` is removed**; use `extern "C" { ... }`.
- **`import "stdio.h";`** reads C headers: a C preprocessor and a C
  declaration reader, with the target's own predefined macros and include
  path (from `cc`, or `$TACHYON_CC`), so a header means what it means to
  C. Structs and unions (bit-fields, `packed`, `aligned`, `#pragma pack`)
  become `#[repr(C)]` types, typedefs and enums aliases, enumerators and
  constant macros typed constants, asm-label renames `#[link_name]`;
  what tachyon cannot express (`long double` on x86-64, `_Complex`,
  `__int128`, inline functions...) is left out, with an error naming the
  reason when it is used. `-I` adds directories; `--emit-imports` shows
  the result.
- **`--emit-header`** writes a C header for a program's `extern "C"`
  functions and statics and the types they need, each checked with a
  `_Static_assert` of its size and alignment.
- `use E::*;` and `use E::{A, B};`; `const` of enum types and of `c"..."`;
  `n as E`, checked (an invalid value exits with 101); `<`, `<=`, `>`,
  `>=` on fieldless enums and variant ranges in patterns; `size_of(T)` and
  `align_of(T)`; `for x in s` over slices and arrays; raw identifiers
  (`r#type`); `#[link_name]`; `#[repr(C, packed(N))]`. `import` and `use`
  are keywords.

The loop optimizer (see [optimizer.md](optimizer.md)): loop canonical form
and LCSSA, rotation, induction variables and exact trip counts, full and
partial unrolling, unswitching, strength reduction of addresses, value
ranges (bounds checks they prove are removed, guarded `match` arms become
decision trees, chains of tests become switches), dead loop deletion,
aggressive dead code elimination, tail recursion elimination with
accumulators. Tests: a loop mode for the random program generator
(`tests/fuzz/run.sh -l`), the ABI fuzzer through `import` (`-i`) and
through `--emit-header` (`-H`), a layout check of imported C records
against `cc` (`tests/cimport/layout.sh`), a stencil benchmark.

### What's new in 0.3

The language grew (see [grammar.md](grammar.md)); one change is breaking:

- **Assignment evaluates its right-hand side first**, then the place (a
  compound assignment then reads the old value), as Rust does; before, the
  place's address came first. `a[i].x = f()` is now safe when `f` moves
  `a`.
- **Enums**, fieldless (with discriminants, castable to integers, compared
  with `==`) or with tuple variants; **`match`** with literal, range,
  constant, binding, wildcard, tuple, variant and or-patterns and guards,
  checked for exhaustiveness (a missing case is named) and unreachable
  arms; `let` and `for` patterns must be irrefutable.
- **Methods** in `impl` blocks (`self: T` or `self: *T`, with `&` and `*`
  added at the call), associated functions (`T::f()`), `Self`; a field
  through a pointer to a struct (`p.f`).
- **Slices** `[T]`: `a[lo..hi]` (and `..`, `lo..`, `..hi`, `..=`) of arrays
  and slices, checked, and of raw pointers, unchecked; `s.len`, `s.ptr`;
  checked indexing. A failed check prints `index out of bounds: index I,
  length N` (or the range) on stderr and exits with 101.
- **C interop** is explicit, as in Rust: `extern "C" { fn ...; static ...; }`
  imports, `extern "C" fn` definitions (unmangled, callable from C) and
  pointer types, `extern "C" static` exports, `#[repr(C)]` structs, enums
  (an `int` tag, then a union of structs) and unions, `#[repr(C, packed)]`,
  `#[repr(C, align(N))]`, `#[repr(u8)]` and friends for enum tags.
  Everything in an `extern "C"` signature must be FFI-safe, which the
  compiler checks. Aggregates follow C's calling convention exactly
  (AArch64 HFAs and x-register pairs, System V eightbytes, MEMORY,
  packed and aligned types, variadic calls). The 0.2 form `extern fn f();`
  is still accepted (deprecated, meaning `extern "C"`); the compiler's own
  source uses it until 0.4.
- **Default layouts and conventions are unspecified**: a plain struct's
  fields are now ordered to save padding; only `#[repr(C)]` types have C's
  layout.
- Reserved words `enum`, `match`, `impl`, `union` are keywords; `self` and
  `Self` are no longer reserved.

The optimizer (see [optimizer.md](optimizer.md)): scalar replacement of
aggregates, an alias analysis that follows addresses to their objects
through variable offsets, load and store forwarding along the dominator
tree, copies read through and removed, dead store elimination, constant
local tables moved to read-only data, a `switch` terminator with jump
tables and binary searches. Tests: `tests/run.sh` and the fuzzers run in
parallel (`-j`); `// STDERR:` and `// CSOURCE:` directives; the random
program generator covers the new language; `tests/abi/run.sh` checks C
interop with random signatures in both directions.

### What's new in 0.2

The language is unchanged (every 0.1 program compiles and means the same).
The compiler gained a middle end and a register-allocating back end,
described in [optimizer.md](optimizer.md):

- `-O0` is the 0.1 code generator; `-O1` lowers to an SSA IR and runs SCCP,
  instruction combining, CFG simplification, GVN with load and store
  forwarding, and dead code elimination, then allocates registers by linear
  scan; `-O2`, the default, adds inlining and loop-invariant code motion.
- `--emit-ir`, `--verify-ir` and `--print-after-all` show and check the IR.
- One fix that is visible: `main` without a result type now exits with 0
  (it exited with whatever was left in the result register).
- Tests: `tests/run.sh -O LEVEL`, IR checks (`// CHECK:`, `// CHECK-NOT:`,
  `// CHECK-OPT:`), random differential testing (`tests/fuzz/run.sh`).
- `bench/run.sh` times programs at every level against the previous
  release, the seed and C (`cc -O2`); results are in
  [roadmap.md](roadmap.md#benchmarks).

## Hosts

A host is where the chain runs; every release builds for the host it runs
on. `bootstrap/bootstrap.sh` detects it with `uname` and fails early, with a
message, on a host that some release in the chain does not support.

| host | machines | needs |
|---|---|---|
| `aarch64-macos` | Macs with Apple silicon | git, Rust (rustup), the Xcode command line tools (`cc` is clang) |
| `x86_64-macos` | Intel Macs | the same |
| `x86_64-linux` | x86-64 Linux with glibc | git, Rust (rustup), a C compiler with the libc headers (`gcc` and `libc6-dev` on Debian/Ubuntu, or clang) |
| `aarch64-linux` (from 0.11) | AArch64 Linux with glibc | a C compiler with the libc headers; the chain itself runs on one of the hosts above (see below) |

Every host also needs the POSIX utilities that any Unix has (`sh`, `awk`,
`sed`, `tar`, `cmp`, `mktemp`); the scripts use nothing beyond POSIX, and
no tool of another host (no clang on Linux, no macOS-only command).
`bootstrap.sh` lists every missing tool at once. `CC` selects another C
compiler.

Rust: install rustup (https://rustup.rs). The seed's directory pins Rust
1.98.0 in `seed/rust-toolchain.toml`, and rustup installs it on first use;
if your rustup does not install toolchains automatically, run
`rustup toolchain install` once inside `seed/`.

On Apple silicon, `bootstrap.sh --host x86_64-macos` builds and checks the
chain for Intel Macs, running the x86-64 binaries under Rosetta 2.

### aarch64-linux: cross-built, then checked natively

0.11 adds the target and host `aarch64-linux` (the standard AAPCS64, ELF,
position independent). The chain cannot start there: the seed (Rust with
Cranelift, pinned) has no aarch64-linux backend, and neither has any
release before 0.11, so no step before HEAD runs on it. Rather than a new
seed, the compiler for it is cross-built, which is sound because a
compiler's output does not depend on the host it runs on (the fixpoint
check proves it for every host it runs on):

1. On a host where the chain runs (aarch64-macos, x86_64-macos or
   x86_64-linux), `bootstrap.sh --host aarch64-linux` runs the chain as
   usual (HEAD built by the last release, its fixpoint and its test suite
   on that host), then has HEAD's compiler compile its own source for
   aarch64-linux: `target/aarch64-linux/tachyonc.o`, the object of the
   compiler that runs there (`cc -o tachyonc tachyonc.o -lm` links it
   there). On aarch64-linux itself, `bootstrap.sh` stops with this advice.
2. On aarch64-linux, the cross-built compiler builds itself. The object it
   writes must be the cross-built one, byte for byte (the host made no
   difference), and the compiler so built must write it again (the
   fixpoint); then the test suite runs there, with the random programs,
   the C interoperability checks and the object check.

`bootstrap/aarch64-linux-check.sh` does both: step 1 where it runs, step 2
in a linux/arm64 Debian container (`bootstrap/ci/linux-aarch64.Dockerfile`;
native on Apple silicon, e.g. with colima):

```
$ bootstrap/aarch64-linux-check.sh --worktree --dev --all-levels --fuzz=100 --abi=40 --objcheck --debugger
```

With `--compiler C` it skips step 1's chain: C (built and tested here
from the same tree, as `bootstrap/gate.sh` does) cross-compiles the
tree's compiler.

In `releases.toml`, `aarch64-linux` is a host of HEAD (and so of 0.11 and
every later release), and of no release before; the releases before 0.11
and their checks are unchanged.

## Semantic versioning

The version is about the **language** the compiler accepts. While the major
version is 0, the language is not stable:

- **0.x minor** (0.1.0 → 0.2.0): new features, and possibly breaking
  changes (something that compiled is rejected, or means something else).
  The release notes in the table above say which.
- **0.x patch** (0.1.0 → 0.1.1): fixes only; every program that compiled
  still compiles and means the same.

From 1.0.0 on, the usual rules apply: patch for fixes, minor for compatible
additions, major for breaking changes.

Whatever the version, a breaking change goes through two releases because
of the release rule below: the release that makes the change is still
written in the old language, and only the next one may use the new one.

## The release rule

**The compiler source of a release may only use language features that the
previous release's binary supports.** The binary of release N-1 is what
builds release N on a new machine; if N's source used a feature N-1 does not
have, the chain breaks.

A new feature is therefore adopted in two releases:

1. Implement the feature in the compiler, keeping the compiler's own source
   in the old language. Add tests for it to the suite. Cut a release.
2. Only after that release exists may the compiler's source use the feature
   (in the next release).

`compiler/README.md` lists the language subset the current source uses.

## Cutting a release

Say the last release is 0.2.0 and you have implemented a feature on main.

1. Check the source rule: the compiler in `compiler/src` must still build
   with the previous release:
   ```
   $ bootstrap/bootstrap.sh            # builds the seed, 0.1.0 and 0.2.0, then HEAD with 0.2.0
   ```
2. Add the tests for the new behaviour to `tests/` (`tests/run/*.tach` with
   `// EXPECT:` ... directives; see `tests/run.sh`), and examples if useful.
   Update `docs/grammar.md` for language changes.
3. Bump the version string in `compiler/src/main.tach` (`version()`).
4. Add the release to `bootstrap/releases.toml`:
   ```toml
   [[release]]
   version = "0.3.0"
   tag = "v0.3.0"
   compiler = "compiler/src"
   root = "main.tach"          # from 0.6: the root of the compiler's module tree
   built_by = "0.2.0"
   cli = "tachyonc-0.1"
   tests = "tests/run.sh"
   hosts = ["aarch64-macos", "x86_64-linux", "x86_64-macos"]
   summary = "What 0.3.0 introduced."
   ```
   and a row to the table above.
5. Run the gate (below, and [roadmap.md](roadmap.md)): the chain with the
   new entry, in working-tree mode (the tag does not exist yet, so the new
   release is the working tree), and every check, on every host it lists:
   ```
   $ bootstrap/gate.sh --release        # everything, at once (docker running)
   $ bootstrap/gate.sh --only bench     # then alone, on an idle machine: the benchmarks
   ```
   Then commit, and tag the commit: `git tag v0.3.0`. From now on,
   `bootstrap/bootstrap.sh` builds the seed, 0.1.0, 0.2.0, then 0.3.0 from
   its tag, then HEAD.
6. Now (and not before) the compiler's source may use the new feature.

### The gate

`bootstrap/gate.sh` runs the whole gate in one command, as parallel as
the machine allows, and ends with one table (each step, its result and
time, a line about it) and the failures' details; it exits 1 when a step
failed. Its logs are in `target/gate/<date>/` (`target/gate/last`), one
file per step.

```
$ bootstrap/gate.sh --quick            # before committing a big change: chain, suite at -O2, a short fuzz
$ bootstrap/gate.sh                    # every step, modest fuzz counts
$ bootstrap/gate.sh --release          # every step, the release's fuzz counts
$ bootstrap/gate.sh --no-linux         # without the containers
$ bootstrap/gate.sh --with-x86         # with x86_64 (off by default since 0.15)
$ bootstrap/gate.sh --only 'fuzz-*,objcheck'   # some steps (--list shows them)
$ bootstrap/gate.sh --release --bench  # the gate, then the benchmarks alone
$ bootstrap/gate.sh --only bench       # only the benchmarks
```

The steps: `chain` (`bootstrap.sh --dev --no-head-tests`: the releases,
then the working tree, built and checked for its fixpoint); then, at
once, `suite-O0`, `suite-O1`, `suite-O2`; `fuzz-plain`, `fuzz-loops`,
`fuzz-generics`, `fuzz-pressure`, `fuzz-calls`, `fuzz-lang06`,
`fuzz-vector`, `fuzz-div`, `fuzz-range`, `fuzz-arch` (0.19: the
intrinsics, `tests/fuzz/run.sh -A`) and `fuzz-seed` (the seed as a
third oracle); `abi-plain`, `abi-import`, `abi-header`; `objcheck`;
`layout` (`tests/cimport/layout.sh` on the system headers); `debug`
(`tests/debug.sh`); `stress-grow` (0.14, not in `--quick`: the compiler
run with `TACHYON_STRESS_GROW=1`, under which every growth of its tables,
`base::grow`, `buf_reserve` and the symbol tables, moves them, by half
their size from a capacity of 1, and fills the old block with 0xAA bytes
and keeps it; a read through a table pointer taken before a growth then
finds garbage instead of, by luck, the old data. Its self-compile must
give the same object as without, and the suite pass at -O0 and -O2. The
mode is for finding such reads, as `TYPES[template_instance(..)].a` was
before 0.14 read TYPES before the call that grew it; it costs little
time and about twice the memory); `examples-checkalloc` (0.16, not in
`--quick`: every example's test, tests/examples/*.test, with the program
built by `--check-alloc`, whose Gpa puts every block on pages of its own
and never reuses them, so a use after free, a double free or a wrong free
in an example stops it with where the block was allocated and freed;
added after examples/errors-and-results printed an error holding a view
of memory it had freed; through `TACHYON_TEST_FLAGS=--check-alloc`, which
a case whose output differs by design with the flag declines with `//
NO-EXTRA-FLAGS: why`); `valgrind` (0.18.1, `--release` only, in the
`linux-aarch64` container, where valgrind is: `tests/valgrind.sh`, the
compiler under memcheck, its -O2 self-compile at `-j4` and the
compilations of the `opt_*`, `own_*` and `contract_*` cases and a few
examples at -O0 and -O2; any invalid read or write or use of an
uninitialised value fails it, leaks do not, as the compiler leaves its
memory to the exit; added after two memory bugs of 0.17, an SLP table
overflow and a read of the own pass's place -1, passed every macOS check
and only valgrind showed them; about 2 minutes, beside the container's other steps; on its own:
`bootstrap/aarch64-linux-check.sh --worktree --dev --compiler
target/tachyonc --only valgrind`); `compile-cost` (0.21.1, in `--quick`
too, a few seconds: `tests/compile_cost.sh`, the instructions retired,
from `/usr/bin/time -l`, the fewest of three runs, of building a hello
world and tests/cost/std_heavy.tach and of `check` of a copy of
compiler/src, with this compiler and with the newest release built here
that is not this commit; it fails when a build costs more than 1.5 times
the release's or `check` more than 1.15 times, and prints the three
numbers with their ratios; added after 0.20's std made a hello world 5.5
times dearer unnoticed: std's index made 660 KB of std core;
`compiler/std/embed.sh --core` lists the core sections, each with the
section and the name that pull it in, and `tests/std/core_sections.sh`,
run by the suite, bounds their bytes); and the two containers: `linux-x86_64`
(`bootstrap/linux-check.sh`, which builds its own chain and so starts at
once) and `linux-aarch64` (`bootstrap/aarch64-linux-check.sh --compiler`:
the chain's compiler cross-compiles the tree). Inside each container the
same steps run at once (`gate.sh --inside`), and their rows appear in the
table under the container's. `bench` runs alone, at the end: benchmarks
need an idle machine.

(0.15) x86_64 is off by default: `bootstrap/gate.conf` sets `X86=0`, so
the `linux-x86_64` step (the emulated container: about half of the
release gate's machine time) is not run; `--with-x86` (or
`TACHYON_GATE_X86=1`) runs it, `--no-x86` leaves it out whatever the
default. Since then programs are not run on x86_64 by the gate (the
x86_64-macos suite never was: Rosetta); the x86_64 back end is still
compiled and same-output still compares its assembly.

It stays parallel without overloading the machine: the test runners
(`tests/run.sh`, `tests/fuzz/run.sh`, `tests/abi/run.sh`,
`tests/objcheck.sh`) take their slots from one pool, a FIFO named by
`$TACHYON_JOBSERVER` that the gate fills with `-j` lines (by default one
per CPU). Twenty steps share the CPUs, none waits for another's tail, and
no program runs late enough to hit its timeout.

**macOS checks every new program.** The first launch of an executable
that was just linked waits for syspolicyd and XProtect to check it:
0.2–0.4 s, against milliseconds for the compilation and the link of a
test (measured on 0.11, one test at a time: compile 5 ms, link 40 ms,
first launch 240 ms, a second launch 2 ms). Every test, random program
and ABI program is a new executable, so on macOS this wait is most of the
suite's time, and the checks are taken about one at a time, whatever the
number of CPUs: the gate's release run on macOS (8,300 programs at the
0.11 counts) took 33 minutes with the CPUs mostly idle, while the same
suite runs in 15 s in the aarch64-linux container. More slots do not help
(`--quick` took 3:53 with two slots per CPU, 2:27 with one). So on macOS
the gate runs a modest number of random programs, and the volume runs
in the aarch64-linux container, the same code generator. Ad-hoc signing
does not change it (the linker signs already). It does not apply to
programs a *developer tool* starts: add the terminal that runs the gate
to System Settings → Privacy & Security → Developer Tools (`spctl
developer-mode enable-terminal` makes Terminal appear in that list).
`gate.sh` times one launch when it starts and says when it is slow.

The containers get `--cpus N` each (default 8; at most what docker has:
with colima, `colima start --cpu 10 --memory 12`); x86_64-linux runs
emulated (Rosetta, in colima's VM), aarch64-linux natively, both at once.
Emulated, gcc and ld now and then crash (a segmentation fault in
collect2, two in one release run): the runners run `cc` once more when
it crashed (a signal, or gcc's "internal compiler error"), and say so in
the case's output; a crash of `cc` is not tachyon's.
An image is built again only when its recipe (the Dockerfile and the
files it copies) changes (`--rebuild-image` forces it, for a newer base
image). The x86_64-linux chain keeps its built releases in a docker
volume (`tachyon-bootstrap-x86_64-linux`), by tag and commit as
`bootstrap.sh` caches them, so a rerun builds only the working tree;
`gate.sh --fresh` (`linux-check.sh --fresh`) starts from nothing, as a
new machine does.

The history: `bootstrap.sh` checks every release's fixpoint but, by
default (`--history fast`), runs only the last release's test suite (the
release that builds HEAD); a suite that passed before for the same tag
and commit (in the cache) is not run again in either mode.
`--history full` runs every release's suite: an occasional complete
replay (with `--clean`, from nothing; `gate.sh --history full --fresh`
does it on this host and in the x86_64-linux container).

Between releases, `tests/fuzz/forever.sh` fuzzes in every mode, batch
after batch on new seeds, at the lowest priority (nice 19), so the gate's
fuzz counts can stay modest. It logs to `target/fuzz-forever/log`, keeps
failing programs in `target/fuzz-forever/failures/MODE/`, goes on from
where it stopped, and stops after the current batch once
`target/fuzz-forever/stop` exists:

```
$ tests/fuzz/forever.sh &      # --follow: test each new target/tachyonc
$ touch target/fuzz-forever/stop
```

If a release changes how its binary is invoked or what it emits (another
command line), give it a new `cli` value and teach `compile_with` in
`bootstrap/bootstrap.sh` about it; the script keeps every interface that a
release in the chain uses. How a release's *source* is laid out is the
`root` key's business: from 0.6 the compiler is a module tree whose root
file (`compiler/src/main.tach`) is the only file on the command line; a
release without `root` (0.1.0 to 0.5.0) is compiled from all the `.tach`
files of its `compiler` directory, as one module. The builder's `cli` says
how to invoke the builder; the release's `root` says what to give it.

From 0.16 the gate gives each test program a minute (`TACHYON_TEST_TIMEOUT`,
60; tests/run.sh's own default stays 20 s): its steps run side by side
with the Linux container, and the heavier examples at -O0 took longer
than 20 s on a loaded machine (the examples-checkalloc step: 2 minutes).

## Adding a host

A new host (say `aarch64-linux`) needs:

1. A backend for it in the compiler: an instruction set file next to
   `compiler/src/gen0/arm64.tach` and `x86_64.tach`, and the back end's
   `compiler/src/back/mc_arm64.tach` and `mc_x86_64.tach` (or a new
   object format and ABI in an existing one), a target name in
   `compiler/src/gen0/target.tach`, and its detection in `host_target()` in
   `main.tach`. The release that adds it is built on an existing host,
   and is checked on the new one by cross-compiling: its assembly for the
   new target must be the same wherever it is produced, and the suite must
   pass there (`tests/run.sh -t <target>`).
2. The host in `bootstrap/bootstrap.sh` and `tests/run.sh` (the `uname`
   mapping and how `cc` links for it).
3. The host in `hosts` of that release and of HEAD in `releases.toml`.

The chain on the new host starts at the seed, so the seed must run there
too, or every release before the one adding the host must already support
it. When neither holds, a new seed release (a frozen tag that runs there)
starts the chain; that is a decision to document here.

## Building and testing

With a compiler binary at hand (`target/tachyonc`, as `bootstrap.sh` leaves
it), on aarch64-macos:

```
$ target/tachyonc compiler/src/main.tach -o tachyonc.s   # the compiler (its root file), by itself
$ cc -arch arm64 -o tachyonc tachyonc.s -lm
$ tests/run.sh -c ./tachyonc                            # the test suite, for the host
$ tests/run.sh -c ./tachyonc prog_                      # only cases named *prog_*
$ tests/run.sh -c ./tachyonc -t x86_64-macos            # x86-64, under Rosetta
$ tests/run.sh -c ./tachyonc -O 0                       # at another optimization level
$ tests/fuzz/run.sh -c ./tachyonc -n 500                # random programs, -O0 vs -O1 vs -O2
$ tests/abi/run.sh -c ./tachyonc -n 150                 # C interop: random signatures, both ways
$ tests/objcheck.sh -c ./tachyonc                       # objects (and -g line tables) against cc -c
$ tests/debug.sh -c ./tachyonc                          # -g under lldb or gdb (0.11)
$ bench/run.sh -c ./tachyonc                            # benchmarks
```

and on x86_64-linux:

```
$ target/tachyonc compiler/src/main.tach -o tachyonc.s
$ cc -o tachyonc tachyonc.s -lm
$ tests/run.sh -c ./tachyonc
```

`tachyonc --target T` picks the target (`aarch64-macos`, `aarch64-linux`, `x86_64-linux`,
`x86_64-macos`); the default is the host. The assembly for a target is the
same on every host, so a compiler can cross-compile itself.

`tests/run.sh` is a POSIX shell script: it needs the compiler and `cc`, not
cargo. Its directives (`// EXPECT:`, `// EXIT:`, `// ARGS:`, `// STDIN:`,
`// ERROR:`, `// XFAIL:`, `// XFAIL(<target>):`, `// CHECK:`,
`// CHECK-NOT:`, `// CHECK-OPT:`, `// STDERR:`, `// CSOURCE:`) are described
at its top. A release's suite must pass at every optimization level. The
runners take `-j N` (default: the number of CPUs); their reports do not
depend on it.

The seed keeps its own tests, run with cargo:

```
$ cd seed && cargo test
```

## The whole chain on a new machine

On macOS (Apple silicon or Intel):

```
$ xcode-select --install                                  # git and clang
$ curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
$ git clone <repository> tachyon && cd tachyon && git fetch --tags
$ bootstrap/bootstrap.sh
```

On x86-64 Linux (Debian/Ubuntu shown):

```
$ sudo apt-get install git gcc libc6-dev curl ca-certificates
$ curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
$ git clone <repository> tachyon && cd tachyon && git fetch --tags
$ bootstrap/bootstrap.sh
```

This builds the seed from the `seed` tag with cargo, builds 0.1.0 (from
`v0.1.0`) with the seed, checks 0.1.0's fixpoint, does the same for every
later release (0.2.0 is built by 0.1.0), runs the last release's test
suite, and finally builds, checks and tests HEAD (`--history full` runs
every release's test suite as well). It prints a
summary and leaves the HEAD compiler in `target/tachyonc`.

To check the Linux chain from any machine with docker:

```
$ bootstrap/linux-check.sh                   # HEAD and the tags, from a fresh clone
$ bootstrap/linux-check.sh --seed-tests      # also the seed's cargo tests on Linux
$ bootstrap/linux-check.sh --all-levels --fuzz=200   # also -O0/-O1/-O2 and random programs (each mode)
$ bootstrap/linux-check.sh --abi=150 --bench          # also C interop fuzzing and the benchmarks
$ bootstrap/linux-check.sh --fresh --history full     # without the cache volume, every release tested
```

It builds a minimal Debian image (`bootstrap/ci/linux-x86_64.Dockerfile`:
only git, gcc, libc6-dev, curl, ca-certificates and rustup; again only
when that recipe changes), clones the repository inside it, runs
`bootstrap.sh` (its cache in a docker volume, see "The gate"), checks the
md5 example against `md5sum`, then runs the checks asked for at once
(`bootstrap/gate.sh --inside`).

Built steps are cached in `target/bootstrap/<host>/`; a rerun only rebuilds
HEAD. (0.18.1) Runs from several worktrees share the main checkout's
cache safely: a release's entry is written under a lock (`<entry>.lock`,
a directory made by `mkdir`, with its holder's pid), built in
`<entry>.building` and renamed into place once its fixpoint (and suite)
passed, so no run sees a half-built entry or deletes another's tree (two
gates built 0.17.0 into it at once, and one removed the other's tree
mid-suite). A second run waits for the lock, then finds the entry built;
a lock whose holder is gone, or older than
`TACHYON_BOOTSTRAP_LOCK_STALE` minutes (120), is taken over. Options of `bootstrap.sh`:

```
--until 0.1.0      stop after a release: a from-scratch build of any release
--worktree         build the working tree instead of HEAD in the last step
--dev              before the tags exist: missing release tags are skipped, and
                   the seed comes from the working tree without a `seed` tag
--host HOST        build for HOST instead of the detected host
--seed-bin PATH    use an existing seed binary
--clean            empty the cache first
--out PATH         also copy the final compiler to PATH
--history MODE     fast (the default): every release's fixpoint, the last
                   one's suite; full: every release's suite too
--no-head-tests    build HEAD and check its fixpoint, not its suite
```
