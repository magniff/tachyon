# Releases and the bootstrap chain

The tachyon compiler is written in tachyon. To build it on a machine that
has no tachyon compiler yet, the chain of releases is replayed from its
root, the seed:

```
seed (Rust)  ──builds──▶  0.1.0  ──builds──▶  next release  ──▶ ... ──▶  HEAD
```

- **The seed** is the original Rust implementation (`seed/`, Cranelift
  backend), tagged `seed`. It is frozen: its toolchain is pinned
  (`seed/rust-toolchain.toml`, `seed/Cargo.lock`), and it only ever has to
  build release 0.1.0. New language features never go into it.
- **Every release** is a git tag (`v0.1.0`, `v0.2.0`, ...) whose tree is
  self-contained: the compiler for that release in tachyon (`compiler/`),
  its examples (`examples/`), its test suite (`tests/`), the documentation
  of its language (`docs/`), and the chain tooling (`bootstrap/`). The tree
  of `v0.1.0` also holds the seed, so that one tag has everything.
- **Each release is built by the previous one**, and checked: it must reach
  the fixpoint (compiled by itself, it emits exactly what its first build
  emits) and pass its own test suite.

`bootstrap/releases.toml` lists the seed's tag and the releases in order,
with the tag, where the compiler's source is, what builds it, how its
binary is invoked, where its test runner is and which hosts it supports.
`bootstrap/bootstrap.sh` replays the chain.

## Versions

| release | tag | built by | hosts | introduced |
|---|---|---|---|---|
| seed | `seed` | Rust 1.98.0 | aarch64-macos, x86_64-macos, x86_64-linux | the language, and its Rust implementation with a Cranelift backend |
| 0.1.0 | `v0.1.0` | seed | aarch64-macos, x86_64-linux, x86_64-macos | the compiler in tachyon: the seed's whole language, compiled to AArch64 (Apple's arm64 ABI) and x86-64 (System V, ELF and Mach-O) assembly; a test suite run without cargo |
| 0.2.0 | `v0.2.0` | 0.1.0 | aarch64-macos, x86_64-linux, x86_64-macos | the optimizer: SSA IR, SCCP, instruction combining, GVN, LICM, inlining, linear-scan register allocation; `-O0`/`-O1`/`-O2` (default `-O2`); random differential testing; `bench/` |
| 0.3.0 | `v0.3.0` | 0.2.0 | aarch64-macos, x86_64-linux, x86_64-macos | aggregates and memory: enums with fields and `match`, methods, slices, C interop (`extern "C"`, `#[repr(C)]`, unions, C's convention for aggregates); SROA, memory forwarding across blocks, dead stores, switches and jump tables; ABI conformance fuzzing |
| 0.4.0 | `v0.4.0` | 0.3.0 | aarch64-macos, x86_64-linux, x86_64-macos | loops and C headers: the compiler written in the 0.3 language; `import "x.h"` (a C preprocessor and declaration reader) and `--emit-header`; `use`, checked `as` to enums, enum ordering, `size_of`/`align_of`, `for x in s`; loop canonicalization, induction variables, rotation, unrolling, unswitching, strength reduction, value ranges and bounds-check elimination, aggressive DCE, tail recursion elimination |
| 0.5.0 | `v0.5.0` | 0.4.0 | aarch64-macos, x86_64-linux, x86_64-macos | generics, modules and the back end: generics by monomorphization, modules (`mod`, `pub`, `use`), several errors per compilation, a small `std`; register allocation by linear scan with interval splitting, a calling convention of tachyon's own, frames aligned above 16, instruction selection by rules, block layout, selects, leaf frames, sibling calls |
| 0.6.0 | `v0.6.0` | 0.5.0 | aarch64-macos, x86_64-linux, x86_64-macos | interprocedural: the compiler written as a module tree; string literals as slices, `if let`, `defer`, structural `==`, a prelude, inline modules, generic type aliases; a cost-model inliner, attribute inference, interprocedural constants, devirtualization, scalar promotion, heap to stack, global DCE; shrink-wrapping; `--time-passes`, `--stats` |

Add a row here, and an entry to `bootstrap/releases.toml`, for every release.

### What's new in 0.6

The compiler's own source is a module tree in the 0.5 language (generics
for its arrays, `Option` for lookups, enum variants by name), checked to
emit byte-identical output to 0.5.0. Releases from 0.6 on name their root
file in `bootstrap/releases.toml`.

The language (see [grammar.md](grammar.md), "Additions of 0.6"); two
changes are breaking:

- **String literals are `[u8]` slices** (they were `(*u8, u64)` tuples):
  `.ptr` and `.len`, and `println("hello")` works. `c"..."` is still a
  `*u8`.
- **Two `*` imports bringing different things under one name** make it an
  error where the name is used (0.5 took the first).
- `if let` and `while let`; `defer` (run when the block is left, last
  first, on every way out but a panic); `==` and `!=` on structs, tuples,
  arrays and enums with fields, field by field; a prelude (`Option`,
  `Some`, `None`, `Result`, `Ok`, `Err`, `Vec`, `print`, `println`
  without `use`, shadowed by anything the program declares or imports);
  `#[inline]`, `#[inline(never)]`, `#[cold]`; inline modules
  `mod m { ... }`; generic type aliases; attributes before `pub`.

The optimizer (see [optimizer.md](optimizer.md)): a whole-program layer
at `-O2`: interprocedural constants (arguments into internal functions,
results out) and devirtualization, inlining bottom-up over the call graph
with a cost model and budgets, function attribute inference (readnone,
readonly, noreturn, willreturn, nopanic, nocapture; `--print-attrs`) used
by GVN, LICM and dead code elimination, scalar promotion of memory in
loops, small non-escaping heap allocations moved to the stack, global
dead code elimination, value ranges of sums and products. The back end:
shrink-wrapping (the frame only on the paths that need it), coalescing
hints for phis, comparisons with immediates. `--time-passes` and
`--stats` measure the compiler and its output; compile times are part of
every release from now on (see [roadmap.md](roadmap.md)).

### What's new in 0.5

The language (see [grammar.md](grammar.md), "Additions of 0.5"):

- **Generics** by monomorphization, checked at instantiation: generic
  functions, structs, enums and `impl` blocks, methods with type
  parameters of their own; type arguments written (`Vec<i64>`,
  `max::<i64>(..)`, `Vec::<u8>::new()`) or inferred from the arguments
  and the expected type. An error inside an instance names the
  instantiation chain. Bounds (traits) are left for later; adding them
  will not change what today's programs mean.
- **Modules**: a file is a module (`mod m;` loads `m.tach` or
  `m/mod.tach`); items are private unless `pub`; paths with `crate`,
  `self`, `super`; `use a::b::{c, d as e}`, `use a::b::*`, `pub use`;
  `import "h.h" as c;` puts a header's declarations under `c::`. Several
  files on the command line still make one root module.
- **Several errors per compilation**: the parser and the checker recover,
  and errors that follow from an earlier one are not reported.
- **A small standard library**, built into the compiler: `std::Option`,
  `Result`, `Vec`, `Buf`, printing.
- `size_of` and `align_of` are always the builtins; `#[repr(C,
  align(N))]` up to 4096, and C records aligned above 16 import normally.
- The layout and calling convention of plain functions and default
  types stay unspecified: at `-O1`/`-O2` plain functions now use a
  convention of tachyon's own; everything C can reach keeps C's.

The back end (see [optimizer.md](optimizer.md)): register allocation by
linear scan on SSA with lifetime holes and interval splitting, coalescing
hints and rematerialization, checked by `--verify-regalloc`; a calling
convention of its own (16 integer and 16 float argument registers on
AArch64, aggregates in registers); realigned frames; instruction selection
by per-target rule tables (scaled-index addressing, `lea`, `madd`, shifted
operands, `ubfx`, `tbz`, `csel`/`csinc`/`cmov` selects, libm calls as
instructions where exact); block layout by fall-through with cold paths
last and tail duplication; `stp`/`ldp` and other post-allocation
peepholes; leaf functions without frames; sibling calls; `setjmp` and
other calls that return twice handled soundly. Tests: `ASM(T):`
directives, `ERROR-COUNT:`, several `ERROR:` lines; random programs in
generics, register-pressure and calls modes; `--emit-mir`.

### What's new in 0.4

The compiler's own source is written in the 0.3 language (enums and
`match` for every kind of node, token, type and instruction; methods;
slices; `extern "C"` blocks), checked to emit byte-identical output to
0.3.0 by `tests/compare.sh`, which compares two compilers over the suite,
examples, benchmarks, random programs and the compiler itself.

The language (see [grammar.md](grammar.md)); two changes are breaking:

- **A slice's `len` is `i64`** (it was `u64`); indexing accepts any
  integer type.
- **The 0.2 form `extern fn f();` is removed**; use `extern "C" { ... }`.
- **`import "stdio.h";`** reads C headers: a C preprocessor and a C
  declaration reader, with the target's own predefined macros and include
  path (from `cc`, or `$TACHYON_CC`), so a header means what it means to
  C. Structs and unions (bit-fields, `packed`, `aligned`, `#pragma pack`)
  become `#[repr(C)]` types, typedefs and enums aliases, enumerators and
  constant macros typed constants, asm-label renames `#[link_name]`;
  what tachyon cannot express (`long double` on x86-64, `_Complex`,
  `__int128`, inline functions...) is left out, with an error naming the
  reason when it is used. `-I` adds directories; `--emit-imports` shows
  the result.
- **`--emit-header`** writes a C header for a program's `extern "C"`
  functions and statics and the types they need, each checked with a
  `_Static_assert` of its size and alignment.
- `use E::*;` and `use E::{A, B};`; `const` of enum types and of `c"..."`;
  `n as E`, checked (an invalid value exits with 101); `<`, `<=`, `>`,
  `>=` on fieldless enums and variant ranges in patterns; `size_of(T)` and
  `align_of(T)`; `for x in s` over slices and arrays; raw identifiers
  (`r#type`); `#[link_name]`; `#[repr(C, packed(N))]`. `import` and `use`
  are keywords.

The loop optimizer (see [optimizer.md](optimizer.md)): loop canonical form
and LCSSA, rotation, induction variables and exact trip counts, full and
partial unrolling, unswitching, strength reduction of addresses, value
ranges (bounds checks they prove are removed, guarded `match` arms become
decision trees, chains of tests become switches), dead loop deletion,
aggressive dead code elimination, tail recursion elimination with
accumulators. Tests: a loop mode for the random program generator
(`tests/fuzz/run.sh -l`), the ABI fuzzer through `import` (`-i`) and
through `--emit-header` (`-H`), a layout check of imported C records
against `cc` (`tests/cimport/layout.sh`), a stencil benchmark.

### What's new in 0.3

The language grew (see [grammar.md](grammar.md)); one change is breaking:

- **Assignment evaluates its right-hand side first**, then the place (a
  compound assignment then reads the old value), as Rust does; before, the
  place's address came first. `a[i].x = f()` is now safe when `f` moves
  `a`.
- **Enums**, fieldless (with discriminants, castable to integers, compared
  with `==`) or with tuple variants; **`match`** with literal, range,
  constant, binding, wildcard, tuple, variant and or-patterns and guards,
  checked for exhaustiveness (a missing case is named) and unreachable
  arms; `let` and `for` patterns must be irrefutable.
- **Methods** in `impl` blocks (`self: T` or `self: *T`, with `&` and `*`
  added at the call), associated functions (`T::f()`), `Self`; a field
  through a pointer to a struct (`p.f`).
- **Slices** `[T]`: `a[lo..hi]` (and `..`, `lo..`, `..hi`, `..=`) of arrays
  and slices, checked, and of raw pointers, unchecked; `s.len`, `s.ptr`;
  checked indexing. A failed check prints `index out of bounds: index I,
  length N` (or the range) on stderr and exits with 101.
- **C interop** is explicit, as in Rust: `extern "C" { fn ...; static ...; }`
  imports, `extern "C" fn` definitions (unmangled, callable from C) and
  pointer types, `extern "C" static` exports, `#[repr(C)]` structs, enums
  (an `int` tag, then a union of structs) and unions, `#[repr(C, packed)]`,
  `#[repr(C, align(N))]`, `#[repr(u8)]` and friends for enum tags.
  Everything in an `extern "C"` signature must be FFI-safe, which the
  compiler checks. Aggregates follow C's calling convention exactly
  (AArch64 HFAs and x-register pairs, System V eightbytes, MEMORY,
  packed and aligned types, variadic calls). The 0.2 form `extern fn f();`
  is still accepted (deprecated, meaning `extern "C"`); the compiler's own
  source uses it until 0.4.
- **Default layouts and conventions are unspecified**: a plain struct's
  fields are now ordered to save padding; only `#[repr(C)]` types have C's
  layout.
- Reserved words `enum`, `match`, `impl`, `union` are keywords; `self` and
  `Self` are no longer reserved.

The optimizer (see [optimizer.md](optimizer.md)): scalar replacement of
aggregates, an alias analysis that follows addresses to their objects
through variable offsets, load and store forwarding along the dominator
tree, copies read through and removed, dead store elimination, constant
local tables moved to read-only data, a `switch` terminator with jump
tables and binary searches. Tests: `tests/run.sh` and the fuzzers run in
parallel (`-j`); `// STDERR:` and `// CSOURCE:` directives; the random
program generator covers the new language; `tests/abi/run.sh` checks C
interop with random signatures in both directions.

### What's new in 0.2

The language is unchanged (every 0.1 program compiles and means the same).
The compiler gained a middle end and a register-allocating back end,
described in [optimizer.md](optimizer.md):

- `-O0` is the 0.1 code generator; `-O1` lowers to an SSA IR and runs SCCP,
  instruction combining, CFG simplification, GVN with load and store
  forwarding, and dead code elimination, then allocates registers by linear
  scan; `-O2`, the default, adds inlining and loop-invariant code motion.
- `--emit-ir`, `--verify-ir` and `--print-after-all` show and check the IR.
- One fix that is visible: `main` without a result type now exits with 0
  (it exited with whatever was left in the result register).
- Tests: `tests/run.sh -O LEVEL`, IR checks (`// CHECK:`, `// CHECK-NOT:`,
  `// CHECK-OPT:`), random differential testing (`tests/fuzz/run.sh`).
- `bench/run.sh` times programs at every level against the previous
  release, the seed and C (`cc -O2`); results are in
  [roadmap.md](roadmap.md#benchmarks).

## Hosts

A host is where the chain runs; every release builds for the host it runs
on. `bootstrap/bootstrap.sh` detects it with `uname` and fails early, with a
message, on a host that some release in the chain does not support.

| host | machines | needs |
|---|---|---|
| `aarch64-macos` | Macs with Apple silicon | git, Rust (rustup), the Xcode command line tools (`cc` is clang) |
| `x86_64-macos` | Intel Macs | the same |
| `x86_64-linux` | x86-64 Linux with glibc | git, Rust (rustup), a C compiler with the libc headers (`gcc` and `libc6-dev` on Debian/Ubuntu, or clang) |

Every host also needs the POSIX utilities that any Unix has (`sh`, `awk`,
`sed`, `tar`, `cmp`, `mktemp`); the scripts use nothing beyond POSIX, and
no tool of another host (no clang on Linux, no macOS-only command).
`bootstrap.sh` lists every missing tool at once. `CC` selects another C
compiler.

Rust: install rustup (https://rustup.rs). The seed's directory pins Rust
1.98.0 in `seed/rust-toolchain.toml`, and rustup installs it on first use;
if your rustup does not install toolchains automatically, run
`rustup toolchain install` once inside `seed/`.

On Apple silicon, `bootstrap.sh --host x86_64-macos` builds and checks the
chain for Intel Macs, running the x86-64 binaries under Rosetta 2.

## Semantic versioning

The version is about the **language** the compiler accepts. While the major
version is 0, the language is not stable:

- **0.x minor** (0.1.0 → 0.2.0): new features, and possibly breaking
  changes (something that compiled is rejected, or means something else).
  The release notes in the table above say which.
- **0.x patch** (0.1.0 → 0.1.1): fixes only; every program that compiled
  still compiles and means the same.

From 1.0.0 on, the usual rules apply: patch for fixes, minor for compatible
additions, major for breaking changes.

Whatever the version, a breaking change goes through two releases because
of the release rule below: the release that makes the change is still
written in the old language, and only the next one may use the new one.

## The release rule

**The compiler source of a release may only use language features that the
previous release's binary supports.** The binary of release N-1 is what
builds release N on a new machine; if N's source used a feature N-1 does not
have, the chain breaks.

A new feature is therefore adopted in two releases:

1. Implement the feature in the compiler, keeping the compiler's own source
   in the old language. Add tests for it to the suite. Cut a release.
2. Only after that release exists may the compiler's source use the feature
   (in the next release).

`compiler/README.md` lists the language subset the current source uses.

## Cutting a release

Say the last release is 0.2.0 and you have implemented a feature on main.

1. Check the source rule: the compiler in `compiler/src` must still build
   with the previous release:
   ```
   $ bootstrap/bootstrap.sh            # builds the seed, 0.1.0 and 0.2.0, then HEAD with 0.2.0
   ```
2. Add the tests for the new behaviour to `tests/` (`tests/run/*.tach` with
   `// EXPECT:` ... directives; see `tests/run.sh`), and examples if useful.
   Update `docs/grammar.md` for language changes.
3. Bump the version string in `compiler/src/main.tach` (`version()`).
4. Add the release to `bootstrap/releases.toml`:
   ```toml
   [[release]]
   version = "0.3.0"
   tag = "v0.3.0"
   compiler = "compiler/src"
   root = "main.tach"          # from 0.6: the root of the compiler's module tree
   built_by = "0.2.0"
   cli = "tachyonc-0.1"
   tests = "tests/run.sh"
   hosts = ["aarch64-macos", "x86_64-linux", "x86_64-macos"]
   summary = "What 0.3.0 introduced."
   ```
   and a row to the table above.
5. Run the whole chain with the new entry, in working-tree mode (the tag
   does not exist yet, so the new release is the working tree), on every
   host it lists:
   ```
   $ bootstrap/bootstrap.sh --worktree --dev
   $ bootstrap/linux-check.sh --worktree --dev       # x86_64-linux, in a container
   ```
   Then commit, and tag the commit: `git tag v0.3.0`. From now on,
   `bootstrap/bootstrap.sh` builds the seed, 0.1.0, 0.2.0, then 0.3.0 from
   its tag, then HEAD.
6. Now (and not before) the compiler's source may use the new feature.

If a release changes how its binary is invoked or what it emits (another
command line), give it a new `cli` value and teach `compile_with` in
`bootstrap/bootstrap.sh` about it; the script keeps every interface that a
release in the chain uses. How a release's *source* is laid out is the
`root` key's business: from 0.6 the compiler is a module tree whose root
file (`compiler/src/main.tach`) is the only file on the command line; a
release without `root` (0.1.0 to 0.5.0) is compiled from all the `.tach`
files of its `compiler` directory, as one module. The builder's `cli` says
how to invoke the builder; the release's `root` says what to give it.

## Adding a host

A new host (say `aarch64-linux`) needs:

1. A backend for it in the compiler: an instruction set file next to
   `compiler/src/arm64.tach` and `x86_64.tach` (or a new object
   format and ABI in an existing one), a target name in
   `compiler/src/target.tach`, and its detection in `host_target()` in
   `main.tach`. The release that adds it is built on an existing host,
   and is checked on the new one by cross-compiling: its assembly for the
   new target must be the same wherever it is produced, and the suite must
   pass there (`tests/run.sh -t <target>`).
2. The host in `bootstrap/bootstrap.sh` and `tests/run.sh` (the `uname`
   mapping and how `cc` links for it).
3. The host in `hosts` of that release and of HEAD in `releases.toml`.

The chain on the new host starts at the seed, so the seed must run there
too, or every release before the one adding the host must already support
it. When neither holds, a new seed release (a frozen tag that runs there)
starts the chain; that is a decision to document here.

## Building and testing

With a compiler binary at hand (`target/tachyonc`, as `bootstrap.sh` leaves
it), on aarch64-macos:

```
$ target/tachyonc compiler/src/main.tach -o tachyonc.s   # the compiler (its root file), by itself
$ cc -arch arm64 -o tachyonc tachyonc.s -lm
$ tests/run.sh -c ./tachyonc                            # the test suite, for the host
$ tests/run.sh -c ./tachyonc prog_                      # only cases named *prog_*
$ tests/run.sh -c ./tachyonc -t x86_64-macos            # x86-64, under Rosetta
$ tests/run.sh -c ./tachyonc -O 0                       # at another optimization level
$ tests/fuzz/run.sh -c ./tachyonc -n 500                # random programs, -O0 vs -O1 vs -O2
$ tests/abi/run.sh -c ./tachyonc -n 150                 # C interop: random signatures, both ways
$ bench/run.sh -c ./tachyonc                            # benchmarks
```

and on x86_64-linux:

```
$ target/tachyonc compiler/src/main.tach -o tachyonc.s
$ cc -o tachyonc tachyonc.s -lm
$ tests/run.sh -c ./tachyonc
```

`tachyonc --target T` picks the target (`aarch64-macos`, `x86_64-linux`,
`x86_64-macos`); the default is the host. The assembly for a target is the
same on every host, so a compiler can cross-compile itself.

`tests/run.sh` is a POSIX shell script: it needs the compiler and `cc`, not
cargo. Its directives (`// EXPECT:`, `// EXIT:`, `// ARGS:`, `// STDIN:`,
`// ERROR:`, `// XFAIL:`, `// XFAIL(<target>):`, `// CHECK:`,
`// CHECK-NOT:`, `// CHECK-OPT:`, `// STDERR:`, `// CSOURCE:`) are described
at its top. A release's suite must pass at every optimization level. The
runners take `-j N` (default: the number of CPUs); their reports do not
depend on it.

The seed keeps its own tests, run with cargo:

```
$ cd seed && cargo test
```

## The whole chain on a new machine

On macOS (Apple silicon or Intel):

```
$ xcode-select --install                                  # git and clang
$ curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
$ git clone <repository> tachyon && cd tachyon && git fetch --tags
$ bootstrap/bootstrap.sh
```

On x86-64 Linux (Debian/Ubuntu shown):

```
$ sudo apt-get install git gcc libc6-dev curl ca-certificates
$ curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
$ git clone <repository> tachyon && cd tachyon && git fetch --tags
$ bootstrap/bootstrap.sh
```

This builds the seed from the `seed` tag with cargo, builds 0.1.0 (from
`v0.1.0`) with the seed, checks 0.1.0's fixpoint, runs 0.1.0's test suite,
does the same for every later release (0.2.0 is built by 0.1.0), and
finally for HEAD. It prints a
summary and leaves the HEAD compiler in `target/tachyonc`.

To check the Linux chain from any machine with docker:

```
$ bootstrap/linux-check.sh                   # HEAD and the tags, from a fresh clone
$ bootstrap/linux-check.sh --seed-tests      # also the seed's cargo tests on Linux
$ bootstrap/linux-check.sh --all-levels --fuzz=200   # also -O0/-O1/-O2 and random programs
$ bootstrap/linux-check.sh --abi=150 --bench          # also C interop fuzzing and the benchmarks
```

It builds a minimal Debian image (`bootstrap/ci/linux-x86_64.Dockerfile`:
only git, gcc, libc6-dev, curl, ca-certificates and rustup), clones the
repository inside it, runs `bootstrap.sh`, and checks the md5 example
against `md5sum`.

Built steps are cached in `target/bootstrap/<host>/`; a rerun only rebuilds
HEAD. Options of `bootstrap.sh`:

```
--until 0.1.0      stop after a release: a from-scratch build of any release
--worktree         build the working tree instead of HEAD in the last step
--dev              before the tags exist: missing release tags are skipped, and
                   the seed comes from the working tree without a `seed` tag
--host HOST        build for HOST instead of the detected host
--seed-bin PATH    use an existing seed binary
--clean            empty the cache first
--out PATH         also copy the final compiler to PATH
```
