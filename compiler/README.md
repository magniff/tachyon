# volec: the vole compiler, in vole

`compiler/src` is one program, a module tree whose root is
`compiler/src/main.vl` (from 0.6; in folders by phase from 0.12):

```
$ volec compiler/src/main.vl -o volec.s && cc -o volec volec.s -lm
$ volec examples/md5/main.vl -o md5.s && cc -o md5 md5.s -lm
$ volec --target x86_64-linux compiler/src/main.vl -o linux.s   # cross-compile
$ volec -O0 examples/md5/main.vl -o md5.s     # -O0, -O1 or -O2 (the default)
$ volec --emit-ir examples/md5/main.vl -o md5.ir    # the optimized IR
$ volec --emit-imports prog.vl -o decls.vl   # what `import "x.h" as c;` declares
$ volec --fix-imports prog.vl   # rewrite 0.7's `*` imports and plain header imports (0.8; `fix --only imports`)
$ volec --emit-header prog.vl -o prog.h        # the program's C header
$ volec --tokens file.vl        # the token dump (same format as the seed's `vole tokens`)
$ volec --version                 # the release and the host
$ volec --profile-generate p.prof prog.vl -o prog.o   # instrument (0.10)
$ volec --profile-use p.prof prog.vl -o prog.o        # optimize with the counts
$ volec -g prog.vl -o prog      # with DWARF line tables, for debuggers (0.11)
$ volec query def run_gvn compiler/src/main.vl       # questions about a program (0.11)
$ volec edit replace gvn::run_gvn < new.vl   # change an item by name, atomically (0.11)
$ volec check                     # the front end's errors, one per line (0.11)
$ volec fix                       # imports, pub, unsafe blocks: every machine-applicable fix (0.11)
$ volec same-output old/volec  # this compiler's output is OLD's, on the corpus (0.11)
```

`volec query def|show|refs|callers|items` answers questions about a
program from the front end (definitions, their source, the references
the checker resolved, a module's items), for agents and editors; see
[docs/query.md](../docs/query.md). `volec edit`, `undo`, `check`,
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

The root, `main.vl`, is the driver: the command line, host detection,
and the `mod` items of six folders, one per phase (0.12; before, every
module was a file of `compiler/src`), each a module whose `mod.vl`
declares its files. A file of more than about 1,000 lines became a
folder of its own, by concern (0.12: `volec lint --max-lines 1000` is
clean). Each folder's README lists its modules, in pipeline order where
there is one:

```
compiler/src/
  main.vl    the driver
  base/        the C library, arrays, buffers, symbols, files, diagnostics, the target, timers
  front/       tokens, C imports and headers, std, the AST and parser, modules, types, the checker
  middle/      the IR (-O1, -O2), lowering to SSA, the optimizer's passes and their pipeline
  back/        instruction selection, register allocation, emission, machine code, objects
  gen0/        -O0's code generator and its target interface; the driver of every level
  tools/       query, edit, fix, rewrite, the refactorings, same-output
  guide/       `volec guide`: the language guide, its text from compiler/guide/ (0.13)
```

| folder | its modules ([base](src/base/README.md), [front](src/front/README.md), [middle](src/middle/README.md), [back](src/back/README.md), [gen0](src/gen0/README.md), [tools](src/tools/README.md)) |
|---|---|
| `base/` | `mod.vl` (C library, arrays, buffers, symbols, files), `diag.vl`, `target.vl`, `timer.vl` |
| `front/` | `lexer.vl`, `cpp/`, `cimport/`, `cheader.vl`, `stdsrc.vl`, `ast.vl`, `parser/`, `modules/`, `types.vl`, `check/`, `consteval.vl`, `patterns/`, `generics/`, `traits.vl` |
| `middle/` | `ir/`, `lower/`, `opt.vl` (the pipeline), `fold.vl`, `gvn.vl`, `egraph.vl`, `sroa.vl`, `adce.vl`, `inline.vl`, `ipo.vl`, `tre.vl`, `loops.vl`, `scev.vl`, `range/`, `vectorize/`, `slp.vl`, `lsr.vl`, `licm.vl`, `promote.vl`, `profile.vl`, `unsafecheck.vl` |
| `back/` | `isel/`, `regalloc/`, `layout.vl`, `emit/`, `mc_arm64/`, `mc_x86_64/`, `abi.vl`, `objfile/`, `enc_arm64.vl`, `enc_x86.vl`, `dwarf.vl` |
| `gen0/` | `gen/` (the driver and -O0's generator), `target.vl`, `arm64.vl`, `x86_64.vl` |
| `guide/` | `mod.vl` (the command), `stdapi.vl` (std's API from its source), `text/` (generated by `compiler/guide/embed.sh`) |
| `tools/` | `query/`, `query_text.vl`, `plan/`, `proc.vl`, `edit/`, `patch/`, `fix.vl`, `fiximports.vl`, `fixunsafe.vl`, `tidyimports.vl`, `reexports.vl`, `sameout.vl`, `rewrite/`, `refactor_shape/`, `refactor_mod/`, `refactor_move/`, `script.vl`, `commands.vl` |

Items are private unless another module uses them, and then `pub`; a
module imports by name what it uses from the others, from the module
that defines it: `use crate::front::ast::{NODES, child};` (and its main
enum's variants, e.g. `use crate::middle::ir::Op::{Add, Sub};`; 0.8 has
no `*` imports, and `volec --fix-imports` wrote these lists from the
`*` imports before). There are no re-exports (0.12: `volec fix --only
reexports` rewrote the imports that went through the `pub use` lines the
splits had kept, then removed them), and the `use` lines are merged by
path, sorted and wrapped at 100 columns (`fix --only tidy-imports`). The
modules mirror the numbered files of 0.1 to 0.5 (`00_base.vl` is
`base/mod.vl`, `46_opt.vl` is `middle/opt.vl`, and so on). The
folders were made with `volec refactor move-module`, in one script,
the files split with `refactor split`, and both proven to change no
output with `volec same-output`
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
convention for scalars, so vole functions can be handed to C (e.g. as
`qsort` callbacks); compound values are passed as a pointer to a copy and
returned through a result pointer (`x8` on AArch64; on x86-64 the hidden
first argument `rdi`, as C does). Integers are kept sign- or zero-extended
to 64 bits, so narrow arithmetic only needs a final extension. All
instruction text is in `gen0/arm64.vl` and `gen0/x86_64.vl`; a new
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

- **modules**: one per file under the root `main.vl`, `pub` on what other
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
by name: `volec --fix-imports compiler/src/main.vl` replaced its 380
`*` imports (the compilers built before and after are byte-identical).

Not used yet: enums with fields, function pointer types, `#[repr]` types,
std's `Vec`. Most data lives in global arrays indexed by id (`NODES[n]`,
`INSTS[v]`, `TYPES[t]`), `pub static mut` in the module that owns them.

0.5.0 read `std` only when the files of the command line named it (fixed
in 0.6), so `main.vl` named it (`use std::Option;`, removed in 0.12 as
unused: from 0.6 a prelude name loads std).

Features new in 0.6 enter this source in 0.7.

Error recovery uses `_setjmp`/`_longjmp` (see `err_end` in `base/diag.vl`): a
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
