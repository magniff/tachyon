# 4. Value semantics: let, inout, sink

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

The chapter that makes vole vole. It must be the most patient one in
the book: motivation first, one idea per section, a picture in words
before every rule. By the end the reader can:

- explain what it means that every value has one owner, and when a
  value is copied, moved or dropped;
- choose a parameter's convention: `let` (the default: read it),
  `inout` (change it; the caller writes `&x`), `sink` (take it);
- write methods with `self`, `inout self` and `sink self`;
- read and fix `own.moved` and `own.conflict`;
- use a view (a slice, a `str`) without fear, and explain why there
  are no references or lifetimes to write;
- know when to reach for `.clone()`, and when not to.

## Running example

A playlist: `struct Song { title: str, seconds: i64 }` in a
`Vec<Song>`. Functions grow with the chapter: `total_seconds(list)`
(let), `add(&list, song)` (inout), `archive(&shelf, list)` (sink),
`longest(list) -> Song`, `first_title(list) -> str` (a view). Keep it
small enough that every listing is a complete program with `out`.

## Sections

1. **The problem.** Two functions share data; who may change it, and
   when is it freed? Contrast briefly: garbage collection (Python, Go,
   Java), manual `free` (C), the borrow checker (Rust). Vole's answer:
   *mutable value semantics*. Values behave like numbers do: assigning
   or passing one never creates a hidden second name for the same
   thing. The compiler checks the rest.
2. **Plain and owned values.** Numbers and structs of numbers are
   *plain*: `let b = a;` copies. A `Vec`, a `String`, a `HashMap`, or a
   struct holding one is *owned*: `let w = v;` *moves* it, and `v` is
   dead afterwards. Show `own.moved` and its `try:` (`.clone()`).
3. **Drops.** At the end of its scope an owned value is dropped (its
   memory freed), last declared first, on every way out of the scope. No
   `free` calls. A moved value isn't dropped where it was. `drop(x)`
   drops early. A `struct` with `impl Drop` runs code at the drop (show
   one printing a message, so the order is visible in `out`).
4. **let: reading.** The default convention. The function reads the
   argument in place; for an owned value no copy is made; the caller
   keeps it. Changing a let parameter is an error that names the fix.
5. **inout: changing.** `fn add(list: inout Vec<Song>, s: Song)`, called
   `add(&list, s)`. The `&` at the call site is the point: reading a
   call tells you what it may change. Inside the function the parameter
   is used as the value itself: `list.push(s)`, `n += 1` (no `*`).
   Exclusivity: `f(&a, &a)` is `own.conflict`. `inout r = &x;` names an
   access in a local. Errors: `conv.marker` (missing `&`) and
   `conv.marker_extra` (an `&` on a let argument).
6. **sink: taking.** `fn archive(shelf: inout Vec<Vec<Song>>, list: sink
   Vec<Song>)`. The caller's value moves in; the function owns it,
   may change it, keeps it or drops it. A plain value is simply copied.
   A sink parameter is mutable inside the function.
7. **Methods and receivers.** `fn len(self)`, `fn push(inout self, x:
   sink T)`, `fn finish(sink self)`. A method call lends the receiver
   without `&`: `list.push(s)`.
8. **Returning values.** Returning an owned value moves it to the
   caller; nothing is copied. This is the normal way to make a value in
   a function and hand it out.
9. **Views.** A slice `[T]` or a `str` points into memory something else
   owns. A function may return a view of its parameter (`first_title`).
   The compiler keeps every view inside what it views: using a view after
   its owner changed is `own.conflict`; returning a view of a local is
   `own.escape`. Show both, with the fix each `try:` suggests. Why no
   lifetimes: views can't be stored anywhere the compiler can't follow,
   so it works out each function's summary itself (`volec query views
   NAME` shows it).
10. **When to clone.** Rarely: when you really want two independent
    values. Usually the fix for `own.moved` is a let parameter instead.

## Errors to show

`own.moved`, `own.conflict` (two cases: `f(&a, &a)`, and a view used
after a `push`), `own.escape`, `conv.marker`, `conv.marker_extra`,
assigning to a let parameter, and `conv.rust` for `&mut x` or `let mut`
(in a Rust aside). Paste the human form; point at each `try:` line.

Known gap to check before writing: in 0.25, `let n = 1; bump(&n);` and
calling an `inout self` method on a `let` binding are accepted, although
the guide says such a binding must be `var`. Teach `var` for anything
that changes, and don't show an error for this case unless the compiler
gives one by then.

## Asides

- If you know Rust: `x: T` is like `&T`, `inout T` like `&mut T`, `sink
  T` like `T`; `self`/`inout self`/`sink self`; `&x` marks only
  `inout`; no `*r`; no lifetimes; `move ||` is `sink ||`. `volec fix
  --only conventions` rewrites Rust spellings.
- If you know Swift: `inout` with `&` at the call is the same idea;
  Hylo is where the words come from.

## Sources

`volec guide memory`, `guide views`, `guide rust#parameters-ownership-memory`,
docs/design/conventions.md (the why), docs/design/value-semantics.md.
