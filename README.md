# The Tachyon Programming Language

Tachyon is a compiled systems language designed from the ground up to be
used by AI agents. A new language is one no model has seen in training,
so the compiler has to carry the knowledge: it answers questions about a
program by name, makes semantic edits that are checked before anything is
written, and reports every problem as one line followed by the exact
command to run next. The language underneath is small and explicit, with
no undefined behaviour in safe code and no wildcard imports, so that what
a program means can be read from its text. It compiles to native code on
par with `clang -O2`, and the compiler is written in tachyon itself.

```rust
import "stdio.h" as c;

struct Point { x: f64, y: f64 }

enum Shape { Circle(Point, f64), Rect(Point, Point), Empty }

trait Area {
    fn area(self: &Self) -> f64;
}

impl Area for Shape {
    fn area(self: &Shape) -> f64 {
        match *self {
            Shape::Circle(_, r) => 3.14159 * r * r,
            Shape::Rect(a, b) => (b.x - a.x) * (b.y - a.y),
            Shape::Empty => 0.0,
        }
    }
}

fn total<T: Area>(items: [T]) -> f64 {
    let mut sum = 0.0;
    for s in items {
        sum += s.area();
    }
    sum
}

fn main() -> i32 {
    let o = Point { x: 0.0, y: 0.0 };
    let shapes = [Shape::Circle(o, 1.0), Shape::Rect(o, Point { x: 2.0, y: 3.5 }), Shape::Empty];
    let rest = shapes[1..];
    unsafe { c::printf(c"%.2f %.2f %lu\n", total(shapes[0..]), total(rest), rest.len); }
    0
}
```

```
$ target/tachyonc shapes.tach -o shapes.s && cc -o shapes shapes.s && ./shapes
10.14 7.00 2
```

Structs, enums with exhaustive `match`, traits with bounded generics
(monomorphized, statically dispatched), checked slices, and a C header
imported into its own namespace. Calling C is an `unsafe` operation;
everything else here is safe. Bindings are immutable unless `mut`. The
full grammar is in [docs/grammar.md](docs/grammar.md).

## Built for agents

**The compiler teaches the language.** A newcomer has never seen tachyon,
so `tachyonc guide` prints a core sized for a context window (about 2k
tokens): where tachyon looks like Rust and means something else, as
paired Rust and tachyon lines, std's most used items, the first errors
with their fixes. The rest is on demand: `guide TOPIC`, `guide --find
WORDS`, `guide TOPIC#SECTION` (std's API is generated from its source).
It is built into the compiler, so it matches its version, and every
example in it is compiled and run by the test suite.

**The compiler is the toolset.** Agents read and change code through
`tachyonc` instead of `grep`, `sed` and whole-file rewrites. Names are
resolved by the compiler, so a query sees uses through imports and
ignores comments and strings:

| to | run |
|---|---|
| read one item's source | `tachyonc query show Shape::area` |
| find every resolved reference | `tachyonc query refs Area` (`--count`, `--in MODULE`) |
| get a definition and signature | `tachyonc query def total` |
| list a module, like a header | `tachyonc query items crate::middle::gvn` |
| change a few lines inside an item | `tachyonc edit patch Shape::area --old 'r * r' --new 'r * r * 1.0'` |
| rename, with every reference (and file) | `tachyonc refactor rename Area Measure` |
| move items, imports and `pub` fixed | `tachyonc refactor move util::clamp --to crate::math` |
| split a large module into files | `tachyonc refactor split crate::check --plan` |
| replace an idiom, typed | `tachyonc rewrite 'grow($v, $n)' '$v.reserve($n)' --where '$v: *IntVec'` |
| see the front end's errors | `tachyonc check` (one line each) |
| apply every mechanical fix | `tachyonc fix` (imports, unused, `pub`, `unsafe`) |
| prove a refactoring changed nothing | `tachyonc same-output OLD_TACHYONC` |

Also `refactor signature`, `field` and `variant` (every call, literal and
`match` updated), `refactor --script` (many steps, checked once), and the
planning queries `stats`, `deps`, `unused` and `impact`. Every edit is
atomic: the front end checks the edited program first, and an edit that
adds an error writes nothing. Edits are journaled; `tachyonc undo` takes
the last one back. See [docs/query.md](docs/query.md),
[docs/refactor.md](docs/refactor.md),
[docs/refactor-shape.md](docs/refactor-shape.md) and
[docs/refactor-modules.md](docs/refactor-modules.md).

**Diagnostics name the next command.** A problem is one stderr line,
`SEVERITY CODE: MESSAGE`, with a stable code, then `try:` lines to run as
they are:

```
$ tachyonc edit patch Shape::area --old 'r * r' --new 'r * rr' shapes.tach
shapes.tach:14:50: error[type error] undefined variable 'rr' | help: did you mean 'r'?
error edit.breaks: 1 new error; nothing written
try: tachyonc edit patch Shape::area --old 'r * r' --new 'r * rr' shapes.tach --no-check
```

Query output is one fact per line with TAB-separated fields and no
padding; long answers are summarized (references per file, with
`note query.truncated`) instead of flooding a context window. Compiler
errors take `--diagnostics=short`: `FILE:LINE:COL: error[KIND] MESSAGE |
help: HELP`, where an unknown name's help is the `use` line that imports
it.

**No undefined behaviour in safe code.** Integer overflow wraps, division
by zero is defined (`x / 0 == 0`), shifts and float-to-integer
conversions are defined, indexing and slicing are bounds-checked (exit
code 101 with a message), and there are no uninitialized variables. Raw
pointer dereference, calls into C and union reads are allowed only inside
`unsafe`; `--check-unsafe` checks those accesses at run time. Since
0.17, value semantics close the last gap without lifetime annotations:
owned values move and are dropped at the end of their scope, references
(`&T`, `&mut T`) and slices are checked so that none outlives or is
invalidated under what it views (aliasing XOR mutation). See
"Undefined behaviour" in [docs/grammar.md](docs/grammar.md) and
`tachyonc guide memory`.

**Every name is traceable.** There are no wildcard imports: every name a
file uses is declared there, imported by name, or written with its path,
including C declarations (`c::printf`). `tachyonc fix --only imports` adds
the `use` lines a program is missing.

**Deterministic builds.** The output is byte-for-byte reproducible and
independent of the host. Every release compiles itself to identical
output (the fixpoint), and the compiler cross-built for aarch64-linux is
checked to rebuild there to the same object, byte for byte.

**Measured, not assumed.** Every release traces how agents read, search
and edit tachyon code, and how much of it went through `tachyonc` rather
than the shell; the gaps decide the next release's tools. In the first
measurement with the query tools, 64% of source reads went through
`tachyonc query`, against a history in which 56% of all source operations
were line-range reads (`sed -n`, `head`). Edits inside a function were
still mostly scripted text replacement, which is why 0.12 added `edit
patch`. The record is [docs/agent-tool-usage.md](docs/agent-tool-usage.md).
From 0.14, an agent eval (about twelve fixed tasks with hidden tests,
each with a Rust twin as control) is part of the release gate.

## Performance

Generated-code speed and compile speed are both release criteria: no
release may make a benchmark slower beyond noise, and an optimization has
to pay for its compile time. The optimizer works on an SSA IR with an
e-graph, inlining, loop optimizations, bounds-check elimination, loop and
SLP vectorization and profile guidance, and the back end writes Mach-O
and ELF objects directly ([docs/optimizer.md](docs/optimizer.md)).

Release 0.11 on Apple silicon (fastest of 9 runs, ms):

| program | tachyon -O2 | clang -O2 |
|---|---|---|
| binarytrees | 156 | 163 |
| collatz | 292 | 295 |
| fannkuch | 118 | 142 |
| fib | 14 | 14 |
| interp | 41 | 42 |
| json | 109 | 93 |
| mandelbrot | 171 | 166 |
| matmul | 19 | 44 |
| nbody | 32 | 29 |
| sieve | 70 | 79 |
| sort | 64 | 59 |
| stencil | 8 | 8 |
| wordcount | 89 | 71 |
| **geometric mean, against clang** | **0.953** | **1** |

Tachyon is ahead on matmul (vectorized), fannkuch and sieve, and behind
on json, wordcount, nbody, sort and mandelbrot; what remains against
clang (bounds checks, FMA) is in the optimizer notes. These are thirteen
small programs, measured on one machine (aarch64-macos); they say little
about large applications. Every release's numbers are in
[docs/roadmap.md](docs/roadmap.md), "Benchmarks".

Compile speed, on the compiler's own source (71,900 lines, 0.11): 143 ms
to an object at `-O0`, 1.21 s at `-O2` (1.23 s to an executable, `cc`
linking); `tachyonc check` answers in 44 ms and `query refs` in 49 ms.

## C interop

C compatibility is opt-in and exact where it is asked for:

- `extern "C"` blocks, `extern "C" fn` definitions and pointers, varargs;
- `#[repr(C)]` structs, unions and enums, `#[repr(u8)]` tags, `packed`, `align(N)`;
- `import "h.h" as c;` reads a header as the target's C compiler does and
  names its declarations through `c` (`--emit-imports` shows them);
- `--emit-header` writes a program's C header, asserting every layout.

A fuzzer (`tests/abi/run.sh`) calls random C signatures both ways:
declared, imported from a header, and through the emitted header. Record
layouts are compared with C for every record of 55 to 65 system headers.

## Getting it

The compiler is written in tachyon, so the first binary comes from the
release chain: the seed, a frozen Rust implementation, builds 0.1.0, each
release builds the next, and the last builds the working tree. Every step
must reach its fixpoint and pass its release's test suite
([docs/releases.md](docs/releases.md)).

| host | needs |
|---|---|
| aarch64-macos, x86_64-macos | git, Rust via rustup, the Xcode command line tools |
| x86_64-linux | git, Rust via rustup, gcc or clang with the libc headers |
| aarch64-linux | a C compiler; the compiler is cross-built on another host, then rebuilds itself natively |

The seed pins Rust 1.98.0 (`seed/rust-toolchain.toml`), which rustup
installs on first use.

```sh
git clone <repository> tachyon && cd tachyon && git fetch --tags
bootstrap/bootstrap.sh                   # the chain; leaves target/tachyonc
```

Build and run a program, then test:

```sh
target/tachyonc examples/md5/main.tach -o md5   # an executable (cc links it)
./md5 < README.md
tests/run.sh                             # the test suite, for the host
tests/run.sh -O 0 match                  # cases named *match*, at -O0
bootstrap/gate.sh --quick                # chain, suite, short fuzz: a few minutes
bootstrap/gate.sh --release              # the full release gate, one table
```

`--target` cross-compiles to any of the four platforms; `-O0`, `-O1` and
`-O2` (the default) must behave the same, which a random-program fuzzer
checks every release; `-g` writes DWARF line tables.

## Status

Tachyon is at 0.x: the language is not stable, and minor releases may
break programs (with a `tachyonc fix` migration from 0.14 on). The
current release is 0.17.0: memory safety by mutable value semantics
(owned values move and are dropped at the end of their scope, references
and slices are checked with inferred view summaries and no lifetime
annotations, `tachyonc fix --values` migrates 0.16 code), on 0.16's
effects and explicit allocators. See [docs/releases.md](docs/releases.md)
for every release. Next:

- **0.17.1**: references as results and type arguments, arena handles as
  references, the rest of 0.17's value-semantics items
- **0.18**: contracts (`requires`, `ensures`), `test` blocks, property and fuzz tests;
  the compiler's own source on value semantics and arenas; code generation on threads
- **0.19 to 0.23**: `std::arch` intrinsics, collections, text and I/O,
  concurrency, GPU support, windows and a terminal emulator on std

**Toward 1.0.** 1.0 is not a feature milestone. It ships when the
surface language has been reworked against real programs, the tools
include a language server and a formatter, there are no known
miscompiles, and a written specification exists. From 1.0, breaking
changes wait for 2.0. See [docs/roadmap.md](docs/roadmap.md) and
[docs/agents.md](docs/agents.md).

## Layout

| | |
|---|---|
| `compiler/` | the compiler, in tachyon, in folders by phase: `front`, `middle`, `back`, `gen0`, `base`, `tools` ([compiler/README.md](compiler/README.md)) |
| `docs/` | the grammar, the optimizer, the tools, releases and the roadmap |
| `examples/` | example programs, one folder each with a README: C interop, algorithms, the language tour ([examples/README.md](examples/README.md)) |
| `tests/`, `bench/` | the test suite and fuzzers, the benchmarks with their C versions |
| `bootstrap/` | the release chain (`releases.toml`), `bootstrap.sh`, `gate.sh`, the Linux checks |
| `seed/` | the frozen Rust implementation at the root of the chain |
| `AGENTS.md` | how to work on the compiler through its own tools |

MIT licensed ([LICENSE](LICENSE)).
