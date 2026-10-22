# Appendix C: coming from another language

> **Status: outline.** This file is the plan for the appendix. Replace it
> with the appendix, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

A page per background, for the reader who wants the differences in one
place: what carries over, what looks the same and means something
else, and the first errors they will hit. Each row points to the
chapter that explains it. Short tables, with a small program at the end
of each section (checked).

## Contents

1. **From Rust.** The biggest section, since vole looks like Rust on
   purpose. Parameters (`&T`, `&mut T`, `T` against let, inout, sink),
   `let mut` against `var`, no lifetimes, no `Box`/`Rc`/`Arc`, explicit
   allocators, no macros (f-strings, `assert(..)`), no `dyn`/`where`,
   integer semantics, `cmp` returns an `i64`, `'a'` is a `u8`, labels.
   `volec fix --only conventions` and the `conv.rust` errors.
   `volec guide rust` is the full mapping.
2. **From C and C++.** No undefined behaviour in safe code; values are
   dropped automatically, no `free`; slices carry their length; `unsafe`
   is where C's rules apply; calling C is direct (`import "h.h" as c`).
3. **From Go.** Explicit allocators instead of a garbage collector;
   errors as `Result` with `?`; OS threads and channels; generics are
   templates; no interfaces at run time (traits, enums).
4. **From Python, JavaScript, Java.** Static types; values are copied or
   moved, never shared by accident; no exceptions; memory is freed when
   values go out of scope; compiling to a native binary.

## Sources

`volec guide rust`, README.md's "Why this is not Rust" table.
