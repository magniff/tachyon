# 15. Unsafe code and C

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

Step outside the checked language when you must, and talk to C. By the
end the reader can:

- list what `unsafe` allows and explain why each item can't be checked;
- use raw pointers (`*T`), `unsafe { }` blocks and `unsafe fn`, and write
  the contract of an unsafe function in its comment;
- call C: declare functions in `extern "C"`, or import a header with
  `import "math.h" as m;`; use `c"..."` strings; link a library;
- lay out structs for C with `#[repr(C)]`, and pass vole callbacks
  (`extern "C" fn`) to C (qsort);
- wrap unsafe code in a safe API, and test it with `--check-unsafe` and
  `--check-alloc`;
- let C call vole (`--emit-header`).

## Running example

Two threads of examples: (1) calling libm (`sqrt`, `erf`) and libc
(`getenv`, `qsort` with a vole comparator over `#[repr(C)]` structs);
(2) a tiny growable buffer of our own over `malloc`/`free`, wrapped in a
safe type with `impl Drop`, then a planted bug found by `--check-unsafe`.
examples/c-qsort, c-math, c-libc-tour and c-mixed-build cover all of it.

## Sections

1. **What safe code guarantees.** No undefined behaviour: recap
   (wrapping arithmetic, checked indexing, checked views). What it costs
   to break that promise, and why some programs must (C libraries,
   hardware, custom data structures).
2. **The unsafe operations.** Calling C or an `unsafe fn`; dereferencing
   or indexing a raw pointer; casting an integer to a pointer; reading a
   union field. Everything else stays checked inside `unsafe`.
3. **Raw pointers.** `*T`, `0 as *T`, `p.is_null()`, `&x` passed where a
   `*T` is wanted, `p[i]` (unchecked). `NonNull<T>` and
   `Option<NonNull<T>>` in one section.
4. **unsafe fn and its contract.** Write what the caller must promise in
   the comment; the caller's `unsafe { }` is where that promise is made.
5. **Calling C.** `extern "C" { fn ... }`; `import "stdio.h" as c;`
   (the header read by the system's C compiler); C strings; variadics
   (`printf`); linking (`-lm`, `#[link(lib = "m")]`, extra `.c` files on
   the command line).
6. **Layout.** `#[repr(C)]`, `packed`, `align(N)`, `#[repr(u8)]` enums;
   vole's own layout is unspecified.
7. **Callbacks and C calling vole.** `extern "C" fn` for qsort;
   `--emit-header` and a C file calling a vole function.
8. **Safe wrappers.** A type that owns raw memory implements `Drop`
   (which also makes it move-only). The rules unsafe code must keep for
   the safe code around it (from `guide unsafe`), in plain words.
9. **Checking unsafe code.** `--check-unsafe -O1`, `--check-alloc`;
   `volec fix --only unsafe` adds the blocks.

## Errors to show

- `calling a C function is unsafe` (real code `unsafe`), and its fix.
- Dereferencing a raw pointer outside unsafe.
- A `--check-unsafe` report of an out-of-bounds write (console, `...`
  for anything machine-specific such as addresses).
- `--check-alloc` reporting a use after free.

## Asides

- If you know Rust: the same model; no pointer arithmetic methods
  (`p[i]` instead of `p.add(i)`); `import "h.h" as c` replaces bindgen.
- If you know C: vole's safe code can't have UB; the unsafe parts are
  exactly the C-like parts.

## Sources

`volec guide unsafe`, `guide c-interop`, `guide types#accesses-and-pointers`,
examples/c-*.
