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
3. [Values, types, functions and control flow](03-basics.md) *(outline)*
4. [Value semantics: let, inout, sink](04-value-semantics.md) *(outline)*
5. [Structs, enums and pattern matching](05-structs-enums-match.md) *(outline)*
6. [Errors: Option, Result and panics](06-errors.md) *(outline)*
7. [Collections and text](07-collections-and-text.md)
8. [Allocation: where memory comes from](08-allocation.md)
9. [Traits and generics](09-traits-generics.md)
10. [Closures and iterators](10-closures-iterators.md)
11. [Modules and programs](11-modules-and-programs.md) *(outline)*
12. [Effects: what a function may do](12-effects.md) *(outline)*
13. [Contracts and testing](13-contracts-testing.md) *(outline)*
14. [Threads](14-threads.md) *(outline)*
15. [Unsafe code and C](15-unsafe-and-c.md) *(outline)*
16. [Performance](16-performance.md) *(outline)*
17. [The tools, and working with an agent](17-tools.md) *(outline)*
18. [Project: a command-line tool](18-project-cli-tool.md) *(outline)*

Appendices:

- A. [Keywords, operators and attributes](19-appendix-keywords-operators.md) *(outline)*
- B. [Reading diagnostics](20-appendix-diagnostics.md) *(outline)*
- C. [Coming from another language](21-appendix-coming-from.md) *(outline)*

Chapters 1 and 2 are written; the others are detailed outlines, being
filled in.

## How to read it

In order, the first time. Chapters 1 to 7 are the core of the language;
chapter 4, on value semantics, is the one that makes vole different from
what you know, so take it slowly. Chapters 8 to 18 can be read in most
orders once you have the core.

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
