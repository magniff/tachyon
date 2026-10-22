# Effects

Every function in vole 0.16 has an *effect set*: what calling it may
do. The compiler infers it from the function's body and everything the
body calls, closures and generic instances included:

| effect | comes from |
|---|---|
| `alloc(Gpa)`, `alloc(Arena)`, ... | allocating from that allocator type (`alloc(extern)`: C's `malloc`) |
| `io` | a C function that reads or writes: `write`, `read`, stdio |
| `global` | reading or writing a `static var` |
| `panic` | a checked index, `unwrap`, std's panic |
| `diverge` | `while`, `loop`, recursion: it may not return |
| `unsafe` | unsafe operations in its own body |

`volec query effects NAME` prints a function's set, `--why EFFECT`
the chain of calls down to the line that has it, and `--has EFFECT`
lists the functions of a module that have it. A declaration turns a set
into a promise the compiler checks on every build: `#[pure]` (no
`alloc`, `io` or `global`), `#[no_alloc]`, `#[no_io]`, `#[no_panic]`,
`#[effects(...)]` (at most these), and `+ effects(...)` on a closure's
bound.

| example | the program | what it shows |
|---|---|---|
| [pure-and-no-alloc](pure-and-no-alloc/) | statistics over sensor samples | `#[pure]`, `#[no_alloc]`, `#[no_panic]`; the error when a helper three calls down breaks one; `query effects --why`; an allocation through a container's own allocator |
| [effect-bounds](effect-bounds/) | a table library taking closures | `F: Fn(..) -> R + effects(panic)` and `effects()`; the error at the caller's closure; effects per generic instance |
| [trait-purity](trait-purity/) | word frequencies with a hand-written `Hash`, `Eq`, `Ord` | std's `Hash`, `Eq` and `Ord` are `#[pure]` and bind every impl: a hash that writes a static, an eq that prints |
| [effects-for-agents](effects-for-agents/) | Markdown to HTML in a module that leaks | an agent's session: `query effects --has alloc(Gpa)` and `--why` to plan, `refactor --script` to move the module onto an `Arena`, `--check-alloc` to prove it, `#[effects(alloc(Arena), panic)]` to lock it |

Each README is a session: its `console` blocks are run by
`tests/walkthrough/run.sh` in a copy of the example's directory and
checked against what the commands print now, so the errors shown are
the compiler's own, exactly. The examples' programs compile and run;
the broken versions are made in the sessions, by edits the tools
refuse (an edit that adds an error writes nothing and prints the
error). Each program also has a test case in
`tests/examples/effects-NAME.test` (`tests/run.sh effects-` runs them).

## Reading the sets

- `none` is the empty set: a function that only computes.
- `alloc(Gpa)` without `global` means "from a `Gpa` it was given": no
  allocator can be had from nothing (`volec guide allocators`), so a
  function allocates only from allocators it was handed (parameters,
  captures, containers) or reaches through statics.
- `io global` together usually mean printing: std's print functions
  write through a static buffer.
- Callers see the inferred set, which may be smaller than a declared
  one: a declaration is an upper bound.

`volec guide effects` is the reference. [../allocators/](../allocators/)
has the examples for allocation.
