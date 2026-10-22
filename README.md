<p align="center"><picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/vole-logo-round-dark.png">
  <img src="docs/assets/vole-logo-round.png" alt="The vole logo" width="260">
</picture></p>

# Vole

Vole is a compiled systems language built for AI agents to write and
maintain. No model has seen it in training, so the compiler carries the
knowledge: it prints the language on demand, answers questions about a
program by name, makes edits that are checked before anything is
written, and reports each problem as one line with a `try:` command to
run. The compiler is written in vole and generates native AArch64 and
x86-64 code with its own optimizer and assembler.

**Who it is for:** agents writing systems code, and the people directing
them: command-line tools, parsers and compilers, servers, GPU compute, a
terminal emulator. It fits where a program should say in its text what
it allocates and changes, and where the toolchain is driven from a
shell. It does not fit yet where you need packages (there is no package
manager), Windows, a stable language or a track record.

## An example

```rust
// Quicksort, in place: `inout` lends the slice for writing, nothing is copied.
#[no_alloc] // checked: sorting allocates nothing
fn quicksort<T: Ord>(xs: inout [T]) {
    if xs.len() <= 1 { return; }
    let p = partition(&xs);
    quicksort(&xs[0..p]); // the two halves are disjoint places
    quicksort(&xs[p + 1..xs.len()]);
}

fn partition<T: Ord>(xs: inout [T]) -> i64
    ensures 0 <= result && result < xs.len()
{
    let last = xs.len() - 1;
    xs.swap(last / 2, last); // the middle element is the pivot
    var store = 0;
    for i in 0..last {
        if xs[i] < xs[last] {
            xs.swap(i, store);
            store += 1;
        }
    }
    xs.swap(store, last);
    store
}

fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa); // the allocator is explicit
    for x in [5, 3, 9, 1, 4, 8, 2, 7, 6] { v.push(x); }
    quicksort(&v); // & marks what the callee may change
    println(f"{v:?}"); // [1, 2, 3, 4, 5, 6, 7, 8, 9]
}
```

`volec query effects quicksort main.vl` answers `panic diverge`: an
index may fail its check, and the recursion may not end; no `alloc`, as
`#[no_alloc]` checks.

## Why this is not Rust

It looks like Rust on purpose, so a model's habits get it most of the
way, but it means different things:

| | Rust | vole |
|---|---|---|
| parameters | `&T`, `&mut T`, `T` | `let` (the default: read in place), `inout` (the call writes `&x`), `sink` (taken); `var` for `let mut` |
| borrows | lifetimes, the borrow checker | no lifetimes to write: views (slices, structs holding one) are second-class, checked to stay inside what they view |
| Rust's spellings | | `&mut T`, `let mut`, `*x`, `move \|\|` are the error `conv.rust` with a `try:` fix; `volec fix --only conventions` rewrites a program |
| allocation | a global allocator, `Box`, `Rc`, `Arc` | explicit: `fn main(gpa: Gpa)`, `Vec::new_in(gpa)`, arenas, fixed buffers |
| effects | none | inferred: `alloc(A)`, `io`, `global`, `panic`, `diverge`, `unsafe`, `thread`, `sync`, `tls`, CPU features; `query effects --why`; `#[pure]`, `#[no_alloc]`, `#[effects(..)]` are checked bounds |
| contracts | crates | `requires`, `ensures`: checked at run time in every build, and used by the optimizer |
| arithmetic | overflow panics in debug, `x / 0` panics | integers always wrap, `x / 0 == 0`, indexing checked: no undefined behaviour in safe code; raw `*T` and C calls need `unsafe` |
| macros, imports | `macro_rules!`, `use x::*` | neither: `println(f"{x}")` is a function; every name is declared, imported by name or written with its path |
| generics | monomorphized or `dyn`; `where` | monomorphized only: no `dyn`, no `where`; lengths are `i64`, text `str` or `[u8]` |
| C | `extern "C"`, `#[repr(C)]` | the same, and `import "stdio.h" as c;` reads a header into `c::` |

The whole mapping is `volec guide rust`; the grammar is
[docs/grammar.md](docs/grammar.md).

## Tools

| | |
|---|---|
| `volec guide` | the language in about 2k tokens; `--find WORDS`, `guide TOPIC` |
| `volec check`, `explain CODE` | every error on one line, with a stable code and `try:` lines |
| `volec query context NAME` | an item's source, its callees and callers; also `refs`, `effects`, `views` |
| `volec edit patch`, `refactor rename` | checked edits (one that adds an error writes nothing), `undo` |
| `volec fix --suggested` | the errors' exact fixes; `fix` adds imports, `pub`, `unsafe` |
| `volec test`, `volec fuzz` | `#[test]`, `#[property]`, `#[fuzz]`, at -O0 and -O2 |
| `volec lsp` | a language server, with a VS Code extension in [editors/vscode](editors/vscode) |
| `std::cli` | command-line parsing for tools written in vole (clap's builder) |

More in [docs/query.md](docs/query.md), [docs/refactor.md](docs/refactor.md)
and [docs/lsp.md](docs/lsp.md).

## Maturity

Vole is at 0.25, before 1.0: no users yet, no stability promise, and
releases break programs (with a `volec fix` migration where one can be
written). The language is still being designed: expect it to change.

- **Works:** the self-hosting compiler (191k lines of vole, built by a
  chain of every release from a frozen Rust seed, each reaching a
  byte-identical fixpoint); std with collections, text, I/O, threads,
  atomics, `std::arch`, `std::gpu` (Metal), `std::window` (Cocoa) and
  `std::cli`; [examples/voltty](examples/voltty), a terminal emulator
  on them.
- **Platforms:** aarch64 macOS first; aarch64 Linux tested in every
  release gate. x86-64 code is generated, but not run since 0.15.
- **Speed:** 0.24's code took 0.89 of `cc -O2`'s time (geometric mean,
  one Apple silicon machine) on our own small suite with C twins; it
  says little about large programs.
- **Known gaps:** a closure's by-value parameters leak; a stopgap
  (`own.move_out`) refuses more iterator uses than it must; no Linux
  backend for std::window; std::gpu is Metal only.

## Build and start

On aarch64 macOS: git, Rust through rustup, the Xcode command line tools.

```sh
git clone https://github.com/magniff/vole && cd vole && git fetch --tags
bootstrap/bootstrap.sh       # replays the release chain; leaves target/volec
target/volec guide           # start here
```

## Links

[releases](docs/releases.md) (and other hosts), [roadmap](docs/roadmap.md),
[examples](examples/README.md), [AGENTS.md](AGENTS.md) (working on the
compiler), [release notes](https://github.com/magniff/vole/releases).
MIT licensed ([LICENSE](LICENSE)).
