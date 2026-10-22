# 8. Allocation: where memory comes from

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

Explicit allocation, explained from the reader's side: what it costs
them (a parameter here and there) and what it buys. By the end the
reader can:

- explain why vole has no global allocator, and read a signature to
  tell whether a function allocates;
- pass `gpa: Gpa` down from `main`, and know that containers remember
  their allocator (`push` needs none);
- use an arena (`arena_scope`) for many short-lived allocations, and
  know what the compiler stops from leaving it;
- allocate with no heap at all, from a fixed buffer;
- write code generic over the allocator (`A: Allocator`);
- find memory bugs in unsafe code with `--check-alloc`.

## Running example

A request handler that parses lines of a small log (or HTTP-like
requests) into tokens: first with `gpa` everywhere, then with an arena
per request (`arena_scope(gpa, |a| ...)`), then the token buffer on a
`FixedBuf` over a stack array. examples/allocators has five ready
programs to draw on: gpa-from-main, arena-parser, scoped-arena,
fixed-buffer, check-alloc.

## Sections

1. **Why explicit.** Three promises a signature makes when allocation is
   a parameter: you can see which functions allocate, you can choose
   the allocator for a part of the program, and code that must not
   allocate (a signal handler, an inner loop) can say so and be checked
   (chapter 12). The cost: one more parameter. Show a function that
   allocates next to one that doesn't, and their signatures.
2. **Gpa from main.** `fn main(gpa: Gpa)`; `Gpa` is zero-sized and
   copied freely; only `main` gets one. The `_in` functions take the
   allocator last. Containers keep theirs: `v.push(x)`, `v.clone()` and
   the drop use it.
3. **Drops free memory.** Recap of chapter 4: at the end of the scope,
   owned values are dropped; with an allocator that means freed. No
   `free` to forget, no double free.
4. **Arenas.** Bump allocation, freed all at once. `arena_scope(gpa, |a|
   { var v: Vec<i64, ScopedArena> = Vec::new_in(a); ... })`. Only plain
   results leave the closure; a Vec on the arena can't escape it (show
   the error). When arenas pay off: per request, per frame, per file.
   `Arena::new_in(gpa)` for a longer-lived one (briefly).
5. **No heap: FixedBuf.** Allocating from memory you provide; what
   happens when it runs out (check the real behaviour and show it).
6. **Generic over the allocator.** `Vec<T, A: Allocator = Gpa>`;
   `fn fill<A: Allocator>(v: inout Vec<i64, A>, n: i64)`; functions that
   only read take a slice and don't care.
7. **Checking memory.** `volec --check-alloc`: use after free, double
   free and leaks reported where they happen. Safe code can't make
   these mistakes; show it catching one in an `unsafe` block, and a
   leak (`std::forget`). Tests run with it on (chapter 13).

## Errors to show

- `allocation is explicit: pass an allocator (try: Vec::new_in(gpa))`
  (Vec, String, `format!`-style habits).
- A function that allocates without an allocator parameter: the
  `undefined variable 'gpa'` you get and the fix (add `gpa: Gpa`).
- The arena-escape error (a Vec on a ScopedArena returned from the
  closure): check its real code and wording.
- `--check-alloc` output for a leak, pasted from a console session.

## Asides

- If you know Rust: like the unstable allocator API made mandatory;
  no `Box`, `Rc` or `Arc`: a `Vec`, an index, or an arena.
- If you know Zig: very close to Zig's explicit allocators.
- If you know C: no `malloc`/`free` in safe code; drops free.

## Sources

`volec guide allocators`, `guide memory#moves-and-drops`,
docs/design/effects-allocation.md (the why), examples/allocators.
