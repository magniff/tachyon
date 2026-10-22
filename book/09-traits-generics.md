# 9. Traits and generics

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

Write code once for many types. By the end the reader can:

- write generic functions and types with type parameters, and call
  them with inferred types or the turbofish;
- define a trait with required and default methods, implement it for
  their own types and for std's (`i64`, `[T]`);
- bound type parameters (`T: Ord + Hash`);
- make operators work on their types (`Add`, `Ord`, `Eq`), print them
  (`Display`, `Debug`), and use `#[derive(Eq, Ord, Hash, Debug,
  Clone)]`;
- convert between types with `From`/`Into`;
- model "one of several kinds" with an enum, since vole has no `dyn`.

## Running example

A small geometry library: `struct Vec2 { x: f64, y: f64 }` with `Add`
and `Display`; shapes `Circle`, `Rect` implementing `trait Shape { fn
area(self) -> f64; fn name(self) -> str { "shape" } }`; a generic
`largest<T: Ord>(items: [T]) -> T`; `total_area<T: Shape>(items: [T])`;
and an `enum AnyShape { Circle(Circle), Rect(Rect) }` that implements
`Shape` by matching, for a list of mixed shapes. examples/traits-generics
is a larger version.

## Sections

1. **Generic functions.** `fn largest<T: Ord>(s: [T]) -> T`. A generic
   function is a template: each type it's used with gets its own copy,
   compiled as if written by hand (so there's no run-time cost). The
   turbofish `largest::<u8>(...)`.
2. **Generic types.** `struct Stack<T> { items: Vec<T> }`, `impl<T>
   Stack<T>`, `impl Stack<i64>` for one instance. Type aliases.
3. **Traits.** Declaring, implementing, default methods, calling
   `x.area()` or `Shape::area(x)`. One impl per trait and type.
4. **Bounds.** `T: Shape`, `T: A + B`; the error when a type lacks the
   trait (show it). Without a bound, a generic body is checked for each
   type it's used with (mention: errors then say "in instantiation of").
5. **std's traits.** Operators through `Add`, `Sub`, `Mul`, `Div`, `Neg`,
   `Eq`, `Ord` (`cmp` returns negative, zero or positive: an `i64`, not
   an `Ordering` enum); `Hash` for map keys; `Display` with `fmt(self, f:
   inout Fmt)`; `Debug`; `Clone`; `Default`; `#[derive(...)]` and what it
   writes. `From`/`Into`.
6. **No trait objects: enums instead.** vole dispatches statically only.
   For a mixed list, an enum of the cases implementing the trait by
   `match`. Why: no hidden indirection, exhaustive matching. Say plainly
   this is a current design choice of a young language.
7. **Associated types.** `type Item;` in a trait, as `Iterator` uses it;
   a short look, chapter 10 uses it.

## Errors to show

- A call with a type that doesn't implement the bound (the error
  names the bound).
- A missing trait method in an impl.
- `#[derive(Debg)]` (a typo: the did-you-mean and `fix --suggested`).
- Two impls of one trait for one type.
- `conv.rust`-style or "no `dyn`" message when writing `dyn Shape`
  (check what the compiler says).

## Asides

- If you know Rust: no `dyn`, no `where`, no supertraits, no blanket
  impls; `cmp` returns an `i64`; derives are Eq, Ord, Hash, Debug, Clone.
- If you know Go: traits are like interfaces, but satisfied by an
  explicit `impl`, and resolved at compile time.
- If you know Java or C#: generics are templates, not erased.

## Sources

`volec guide generics`, `guide traits`, `guide formatting#display-and-debug`,
`guide formatting#derive`, `guide conversions#from-and-into`,
examples/traits-generics.
