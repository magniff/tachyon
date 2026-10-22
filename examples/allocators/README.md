# Allocators

Allocation in vole is explicit (since 0.16): nothing allocates unless it is
given an allocator. A program's general-purpose allocator (`Gpa`) is a
parameter of its `main`, a function that allocates takes one, and a
container (`Vec`, `Buf`, `HashMap`) holds the one it was made with. The
allocator is part of a container's type (`Vec<T, A: Allocator = Gpa>`),
so the same code can build its data on the heap, in an arena that is
freed all at once, or in a fixed buffer with no heap at all.

| example | the program | what it shows |
|---|---|---|
| [gpa-from-main](gpa-from-main/) | order totals from stdin | `fn main(gpa: Gpa)`, passing it down, a container's own allocator, generic `A: Allocator`; the errors when you forget, `fix --only alloc016`, `refactor signature --fill-calls`; `#[sealed]` `Gpa` |
| [arena-parser](arena-parser/) | an S-expression tokenizer and parser | a tree built in an arena (`arena_scope`, `Arena::scope`) and freed at once, timed against `Gpa`; arena-friendly allocation; what an allocator handle costs |
| [scoped-arena](scoped-arena/) | a key-value store, a request per line | per-request scratch memory with `arena_scope`; what outlives a request; the compile errors when a value escapes its scope; the view that still can |
| [fixed-buffer](fixed-buffer/) | a reverse-Polish calculator in 512 bytes | `fn main()` with no `Gpa`, `FixedBuf` over a stack array, `try_push` and `AllocError`, `#[effects(alloc(FixedBuf), panic)]` |
| [check-alloc](check-alloc/) | the memory bugs left to find at run time | 0.16's bugs (a copied handle freed, a view across `push` or out of a scope, a double free) as compile errors; what `--check-alloc` still reports: a leak, a raw pointer after `push`, a double free in `unsafe` code |

Each README is a session: its `console` blocks are run by
`tests/walkthrough/run.sh` in a copy of the example's directory and
checked against what the commands print now, so the errors and traps
shown are the compiler's own, exactly. Each program also has a test
case in `tests/examples/allocators-NAME*.test` (`tests/run.sh
allocators` runs them).

## Which allocator

| allocator | made by | frees | for |
|---|---|---|---|
| `Gpa` | the runtime: `fn main(gpa: Gpa)` | each block, when its owner is dropped | anything whose lifetime is its own |
| `ScopedArena` | `arena_scope(gpa, \|a\| ...)`, `arena.scope(\|a\| ...)` | everything at the scope's end | temporaries of one task: a request, a frame, a parse |
| `Arena` | `Arena::new_in(gpa)` | everything at once: `reset`, `free_all` (unsafe) | data that lives together for longer than a call |
| `FixedBuf` | `FixedBuf::new(&mem[..])` over memory you own (it holds it inout) | `reset` (unsafe) | no heap, or a hard budget |

`volec guide allocators` is the reference; `volec guide effects`
explains `alloc(Gpa)`, `alloc(Arena)` and the rest of what
`volec query effects` prints. [../effects/](../effects/) has the
examples for effects.
