# tachyonc: the tachyon compiler, in tachyon

`compiler/src` is one program, a module tree whose root is
`compiler/src/main.tach` (from 0.6; in folders by phase from 0.12):

```
$ tachyonc compiler/src/main.tach -o tachyonc.s && cc -o tachyonc tachyonc.s -lm
$ tachyonc examples/md5.tach -o md5.s && cc -o md5 md5.s -lm
$ tachyonc --target x86_64-linux compiler/src/main.tach -o linux.s   # cross-compile
$ tachyonc -O0 examples/md5.tach -o md5.s     # -O0, -O1 or -O2 (the default)
$ tachyonc --emit-ir examples/md5.tach -o md5.ir    # the optimized IR
$ tachyonc --emit-imports prog.tach -o decls.tach   # what `import "x.h" as c;` declares
$ tachyonc --fix-imports prog.tach   # rewrite 0.7's `*` imports and plain header imports (0.8; `fix --only imports`)
$ tachyonc --emit-header prog.tach -o prog.h        # the program's C header
$ tachyonc --tokens file.tach        # the token dump (same format as the seed's `tachyon tokens`)
$ tachyonc --version                 # the release and the host
$ tachyonc --profile-generate p.prof prog.tach -o prog.o   # instrument (0.10)
$ tachyonc --profile-use p.prof prog.tach -o prog.o        # optimize with the counts
$ tachyonc -g prog.tach -o prog      # with DWARF line tables, for debuggers (0.11)
$ tachyonc query def run_gvn compiler/src/main.tach       # questions about a program (0.11)
$ tachyonc edit replace gvn::run_gvn < new.tach   # change an item by name, atomically (0.11)
$ tachyonc check                     # the front end's errors, one per line (0.11)
$ tachyonc fix                       # imports, pub, unsafe blocks: every machine-applicable fix (0.11)
$ tachyonc same-output old/tachyonc  # this compiler's output is OLD's, on the corpus (0.11)
```

`tachyonc query def|show|refs|callers|items` answers questions about a
program from the front end (definitions, their source, the references
the checker resolved, a module's items), for agents and editors; see
[docs/query.md](../docs/query.md). `tachyonc edit`, `undo`, `check`,
`fix`, `lint`, `same-output` and the planning queries (`query stats`,
`deps`, `unused`, `impact`) change a program by name, atomically; see
[docs/refactor.md](../docs/refactor.md).

It accepts the whole language of [docs/grammar.md](../docs/grammar.md) and
emits assembly that `cc` assembles and links against libc, for one of:

| target | | |
|---|---|---|
| `aarch64-macos` | AArch64, Apple's arm64 ABI, Mach-O | `cc -arch arm64` |
| `x86_64-linux` | x86-64, System V ABI, ELF, position independent | `cc` (gcc or clang) |
| `x86_64-macos` | x86-64, System V ABI, Mach-O | `cc -arch x86_64` |
| `aarch64-linux` | AArch64, the standard AAPCS64, ELF, position independent (0.11) | `cc` (gcc or clang) |

The default target is the host, found with `uname`; the assembly for a
target does not depend on the host. Errors are reported in the seed's
format (`error[type error]: ...` / ` --> file: line L, column C` /
`  = help: ...`); the parser and the checker recover, so one compilation
reports up to 50 errors.

## Structure

The root, `main.tach`, is the driver: the command line, host detection,
and the `mod` items of six folders, one per phase (0.12; before, every
module was a file of `compiler/src`), each a module whose `mod.tach`
declares its files. A file of more than about 1,000 lines became a
folder of its own, by concern (0.12: `tachyonc lint --max-lines 1000` is
clean). Each folder's README lists its modules, in pipeline order where
there is one:

```
compiler/src/
  main.tach    the driver
  base/        the C library, arrays, buffers, symbols, files, diagnostics, the target, timers
  front/       tokens, C imports and headers, std, the AST and parser, modules, types, the checker
  middle/      the IR (-O1, -O2), lowering to SSA, the optimizer's passes and their pipeline
  back/        instruction selection, register allocation, emission, machine code, objects
  gen0/        -O0's code generator and its target interface; the driver of every level
  tools/       query, edit, fix, rewrite, the refactorings, same-output
```

| folder | its modules ([base](src/base/README.md), [front](src/front/README.md), [middle](src/middle/README.md), [back](src/back/README.md), [gen0](src/gen0/README.md), [tools](src/tools/README.md)) |
|---|---|
| `base/` | `mod.tach` (C library, arrays, buffers, symbols, files), `diag.tach`, `target.tach`, `timer.tach` |
| `front/` | `lexer.tach`, `cpp/`, `cimport/`, `cheader.tach`, `stdsrc.tach`, `ast.tach`, `parser/`, `modules/`, `types.tach`, `check/`, `consteval.tach`, `patterns/`, `generics/`, `traits.tach` |
| `middle/` | `ir/`, `lower/`, `opt.tach` (the pipeline), `fold.tach`, `gvn.tach`, `egraph.tach`, `sroa.tach`, `adce.tach`, `inline.tach`, `ipo.tach`, `tre.tach`, `loops.tach`, `scev.tach`, `range/`, `vectorize/`, `slp.tach`, `lsr.tach`, `licm.tach`, `promote.tach`, `profile.tach`, `unsafecheck.tach` |
| `back/` | `isel/`, `regalloc/`, `layout.tach`, `emit/`, `mc_arm64/`, `mc_x86_64/`, `abi.tach`, `objfile/`, `enc_arm64.tach`, `enc_x86.tach`, `dwarf.tach` |
| `gen0/` | `gen/` (the driver and -O0's generator), `target.tach`, `arm64.tach`, `x86_64.tach` |
| `tools/` | `query/`, `query_text.tach`, `plan/`, `proc.tach`, `edit/`, `patch/`, `fix.tach`, `fiximports.tach`, `fixunsafe.tach`, `tidyimports.tach`, `reexports.tach`, `sameout.tach`, `rewrite/`, `refactor_shape/`, `refactor_mod/`, `refactor_move/`, `script.tach`, `commands.tach` |

Items are private unless another module uses them, and then `pub`; a
module imports by name what it uses from the others, from the module
that defines it: `use crate::front::ast::{NODES, child};` (and its main
enum's variants, e.g. `use crate::middle::ir::Op::{Add, Sub};`; 0.8 has
no `*` imports, and `tachyonc --fix-imports` wrote these lists from the
`*` imports before). There are no re-exports (0.12: `tachyonc fix --only
reexports` rewrote the imports that went through the `pub use` lines the
splits had kept, then removed them), and the `use` lines are merged by
path, sorted and wrapped at 100 columns (`fix --only tidy-imports`). The
modules mirror the numbered files of 0.1 to 0.5 (`00_base.tach` is
`base/mod.tach`, `46_opt.tach` is `middle/opt.tach`, and so on). The
folders were made with `tachyonc refactor move-module`, in one script,
the files split with `refactor split`, and both proven to change no
output with `tachyonc same-output`
([docs/refactor-modules.md](../docs/refactor-modules.md)).

Two back ends share the front end. At `-O1` and `-O2` (the default) the
checked AST is lowered to an SSA IR, optimized, register-allocated and
emitted (see [docs/optimizer.md](../docs/optimizer.md)). At `-O0` the 0.1
code generator is used unchanged; it is kept as the reference the
optimized levels are tested against. That code generator uses a simple
machine model: every expression leaves its
value in an accumulator (`x0`/`rax`, `d0`/`xmm0` for floats, or the address
of a struct, tuple or array), operands wait on a stack of 16-byte
temporaries, and every local lives in a frame slot. Calls follow the C
convention for scalars, so tachyon functions can be handed to C (e.g. as
`qsort` callbacks); compound values are passed as a pointer to a copy and
returned through a result pointer (`x8` on AArch64; on x86-64 the hidden
first argument `rdi`, as C does). Integers are kept sign- or zero-extended
to 64 bits, so narrow arithmetic only needs a final extension. All
instruction text is in `gen0/arm64.tach` and `gen0/x86_64.tach`; a new
instruction set is a new file implementing the same interface (see "Adding
a host" in [docs/releases.md](../docs/releases.md)).

Semantics follow the seed where programs can observe them (except where
0.3 changed the language: an assignment evaluates its right-hand side
before its target's address, then a compound assignment reads the old
value), on every target: wrapping arithmetic, shift amounts taken
modulo 32 for types up to 32 bits and modulo 64 for 64-bit ones, saturating
float-to-integer casts, and NaN-aware comparisons. One difference: integer
division by zero is not trapped (`x / 0` is 0 and `x % 0` is `x`, the
behaviour of AArch64's divide instructions, reproduced on x86-64), where
the seed traps.

## The language subset of its own source

A release's compiler source may only use what the previous release's binary
supports (see [docs/releases.md](../docs/releases.md)), so a feature that
appears in release N enters the compiler's own source in N+1.

The 0.6 source is built by 0.5.0 and uses the 0.5 language:

- **modules**: one per file under the root `main.tach`, `pub` on what other
  modules use, `use crate::m::*;` and `use crate::m::Enum::*;` (from 0.4's
  `use E::*`: `Fn`, `Struct`, ... in the parser instead of `Tok::Fn`;
  variants whose names clash with an item in scope, and those named
  `None`, stay qualified);
- **generics**: the growable arrays are `grow<T>(data, count, &cap)` and
  `alloc_array::<T>(n)`, sized by `size_of(T)` (0.4): no element size is
  written out any more, and the IR's and the allocator's struct-size checks
  are gone with them;
- **the standard library**: `Option<T>` for lookups that may find nothing
  (`lookup_local`, `tparam_index`, `power_of_two`). `IntVec` stays (std's
  `Vec<T>` checks every index, and the compiler indexes its arrays
  directly in its hot loops);
- from 0.3 and 0.4: `extern "C"` blocks, fieldless enums (`NodeKind`,
  `Tok`, `TyKind`, `Op`, `Cond`, `Term`, `Res`, `AbiClass`, `Lattice`, `CT`,
  `CK`) with `match`, methods (`IntVec`, `HMap`, the enums), slices for
  byte strings, assignments that evaluate their right side first.

The 0.8 source, built by 0.7.0 and by itself, imports every name it uses
by name: `tachyonc --fix-imports compiler/src/main.tach` replaced its 380
`*` imports (the compilers built before and after are byte-identical).

Not used yet: enums with fields, function pointer types, `#[repr]` types,
std's `Vec`. Most data lives in global arrays indexed by id (`NODES[n]`,
`INSTS[v]`, `TYPES[t]`), `pub static mut` in the module that owns them.

0.5.0 read `std` only when the files of the command line named it (fixed
in 0.6), so `main.tach` named it (`use std::Option;`, removed in 0.12 as
unused: from 0.6 a prelude name loads std).

Features new in 0.6 enter this source in 0.7.

Error recovery uses `_setjmp`/`_longjmp` (see `err_end` in `base/diag.tach`): a
function that sets a recovery point calls the work and then more code,
never the work as a tail call, so its frame is alive when the jump comes
back.

To show that a change to the compiler's source changes nothing it emits,
`tests/compare.sh OLD NEW` compiles a corpus (the test programs, the
examples, the benchmarks, random programs, the compiler's own source at
HEAD and at the last release) with both compilers, at every level for
every target, and compares the assembly, the IR, the token dumps, the C
headers and the diagnostics byte for byte. The corpus: the test programs
(also those of several modules), the examples, the benchmarks, random
programs in every mode of the generator, C interop programs (half of them
through `import`, the others also through `--emit-header`), and the
compiler's own source at HEAD and at the last release. The 0.4 migration of
this source to the 0.3 language and the 0.6 one to the 0.5 language were
checked with it: identical output for every compilation (apart from the
tests of what they changed on purpose).

## Known limits

- Targets: AArch64 macOS and Linux, x86-64 Linux and macOS. On AArch64
  Linux the bootstrap chain cannot run (see "aarch64-linux" in
  [docs/releases.md](../docs/releases.md)): the compiler is cross-built.
- The optimizer's limits are listed at the end of
  [docs/optimizer.md](../docs/optimizer.md).
