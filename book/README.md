# The Vole Book

A book for people learning vole, a compiled systems language of values.
It starts at "hello, world" and ends with threads, C, performance and a
complete command-line tool, one idea at a time, with an example for
every idea.

> **Vole is pre-1.0 and still being designed.** Its syntax, its
> standard library and some of its rules will change, and parts of this
> book will change with them. Every example in the book is compiled and
> run by its test suite against the current compiler, so what you read
> here works with the compiler it was written for. When a release
> changes something, the compiler's error messages tell you what to
> write instead.

## Who it's for

You can program in some language (Python, JavaScript, Go, Java, C,
anything) and want to learn vole. You don't need to know Rust. Vole
looks like Rust on purpose, and where it looks the same but means
something different, an "If you know Rust" note says so.

This book is a tutorial: it teaches by example and explains why things
are the way they are. It is not a specification. For precise rules, see
[docs/grammar.md](../docs/grammar.md); for a compact reference, run
`volec guide`.

## Contents

1. [Getting started](01-getting-started.md): installing, hello world,
   `volec`, errors, `volec try`, an editor
2. [A guessing game](02-guessing-game.md): a first real program, using
   a little of everything
3. [Values, types, functions and control flow](03-basics.md): `let` and
   `var`, numbers and their defined behaviour, tuples and arrays,
   functions, blocks as expressions, loops
4. [Value semantics: let, inout, sink](04-value-semantics.md): owners,
   copies and moves, drops, the three conventions, views, and why there
   are no lifetimes
5. [Structs, enums and pattern matching](05-structs-enums-match.md):
   your own types, methods, `match`, `Option`, `if let` and `let else`
6. [Errors: Option, Result and panics](06-errors.md): error types, the
   `?` operator, `main` returning a `Result`, panics, a first `requires`
7. [Collections and text](07-collections-and-text.md): `Vec`, slices,
   `HashMap` and friends, `str` and `String`, bytes, f-strings, and a
   word counter
8. [Allocation: where memory comes from](08-allocation.md): explicit
   allocators, arenas, `FixedBuf`, `--check-alloc`
9. [Traits and generics](09-traits-generics.md): generic functions and
   types, traits and bounds, std's traits, deriving, enums instead of
   trait objects
10. [Closures and iterators](10-closures-iterators.md): what a closure
    captures, `Fn` and `FnMut`, adapters and consumers, your own
    iterator
11. [Modules and programs](11-modules-and-programs.md): the word counter
    in three files, `mod`, `pub` and `use`, files, arguments, the
    environment, other programs
12. [Effects: what a function may do](12-effects.md): inferred effects,
    `--why`, promises like `#[pure]` and `#[no_alloc]`
13. [Contracts and testing](13-contracts-testing.md): `requires` and
    `ensures`, tests, properties, program tests, fuzzing
14. [Threads](14-threads.md): `spawn` and `join`, scoped threads,
    `Mutex`, atomics, channels, and what the compiler checks
15. [Unsafe code and C](15-unsafe-and-c.md): what `unsafe` allows, raw
    pointers, calling C and being called, C layout, a safe wrapper
16. [Performance](16-performance.md): optimization levels, measuring,
    bounds checks and contracts, assembly, SIMD, `std::arch`
17. [The tools, and working with an agent](17-tools.md): queries,
    checked edits, refactorings, `fix`, `fmt`, the editor, agents
18. [Project: a command-line tool](18-project-cli-tool.md): `tally`, the
    word counter grown into a tool with `std::cli`, an arena, an error
    type and tests

Appendices:

- A. [Keywords, operators and attributes](19-appendix-keywords-operators.md)
- B. [Reading diagnostics](20-appendix-diagnostics.md)
- C. [Coming from another language](21-appendix-coming-from.md): Rust,
  C and C++, Go, Python, JavaScript and Java

## How to read it

In order, the first time. Chapters 1 to 7 are the core of the language;
chapter 4, on value semantics, is the one that makes vole different from
what you know, so take it slowly. Chapters 8 to 16 can be read in most
orders once you have the core (each says when it leans on another).
Chapters 11, 17 and 18 grow chapter 7's word counter, so read them in
that order.

Type the examples in and run them. Change them and see what the
compiler says: its messages are part of the teaching, and the book
shows many of them on purpose.

## The examples are tested

Every `vole` code block in this book is compiled, every program shown
with its output is run and its output compared, every error shown is
the compiler's real message, and every shell session is replayed:

```sh
tests/book/run.sh                 # the whole book
tests/book/run.sh -f book/02-guessing-game.md
tests/run.sh book                 # as part of the compiler's test suite
```

## Writing for the book

Read [STYLE.md](STYLE.md) first: the voice, the conventions, and the
annotations that tell the test harness what each code block is.
