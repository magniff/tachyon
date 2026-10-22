# 16. Performance

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

Make programs fast, and know what the compiler did. By the end the
reader can:

- choose an optimization level, knowing every level gives the same
  results;
- time code with `std::time` and compare two versions fairly;
- write code the optimizer handles well: slices, iterators, contracts
  that remove bounds checks, allocation out of hot loops;
- look at what the optimizer produced (`--emit-ir`, `-S`, `query checks`);
- use SIMD vector types and CPU intrinsics (`std::arch`), guarded by
  feature detection, with `#[multiversion]` for a portable binary.

## Running example

A byte-search or checksum routine, taken from portable code to fast
code in measured steps: the naive loop, an iterator chain (same speed),
a version with a `requires` that drops the bounds checks (`query checks`
before and after), SIMD with `v16u8`, and the NEON/CRC intrinsics with
`detect` and a fallback. examples/arch (bytesearch, crc32, sha256sum)
and examples/algorithms have measured versions.

Timing output is never deterministic: show timings in `text` blocks
marked as one machine's numbers, and check only the program's result
in `out` blocks.

## Sections

1. **Optimization levels.** `-O0` (fast compiles), `-O1`, `-O2` (the
   default). Safe code means the same thing at every level: no undefined
   behaviour for the optimizer to exploit, so turning it up never
   changes a result. `volec test` checks this by running both.
2. **Measuring.** `std::time` (check the API) for a timer; warm-up,
   repetitions, printing the result so the work isn't removed.
3. **What's cheap.** Plain values in registers; views instead of copies;
   iterator chains compile to loops; generics are specialized; drops are
   static. What isn't: allocating in a loop (reuse a Vec, use an arena),
   a bounds check the compiler can't remove.
4. **Bounds checks and contracts.** `requires lo <= hi && hi <= s.len()`
   at the top of a function removes the checks inside; `volec query
   checks FN` shows which checks remain. Nothing is assumed without a
   check that ran.
5. **Looking at the output.** `--emit-ir` (the optimized IR, one function),
   `-S` for assembly; read just enough to spot a loop and a call.
6. **SIMD vectors.** `v16u8`, `v4f32`, lane-wise operators, `load`,
   `store`, `splat`, masks and `select`.
7. **std::arch.** Vendor intrinsics by their usual names (`vaddq_u8`,
   `__crc32cd`), `volec query arch WORDS` to find one, `detect("crc")`
   and `has`, `#[target_feature]`, `#[multiversion]`. The `arch.*`
   errors keep a missing feature from becoming an illegal instruction.
8. **Compile speed.** The cache for -O1/-O2 rebuilds, `-j N`, `-O0` for
   the edit-compile loop.

## Errors to show

- `arch.feature`: calling an intrinsic without its feature enabled or
  checked (real message).
- `query checks` output before and after a `requires` (console).

## Asides

- If you know C: no `-ffast-math`, no UB-based optimizations; contracts
  are the way to tell the compiler a fact, and they're checked.
- If you know Rust: the same "zero-cost abstractions" idea; `std::arch`
  names match.

## Sources

`volec guide arch`, `guide types#simd-vectors`, `guide contracts#contracts-and-the-optimizer`,
`guide tools#other-compiler-options`, docs/optimizer.md, examples/arch,
examples/algorithms, bench/.
