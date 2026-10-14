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
declares its files:

```
compiler/src/
  main.tach    the driver
  base/        the C library, arrays, buffers, symbols, files, errors, timers
  front/       tokens, C imports and headers, std, the AST, modules, types, the checker
  middle/      the IR (-O1, -O2), lowering to SSA, the optimizer's passes
  back/        instruction selection, register allocation, emission, machine code, objects
  gen0/        -O0's code generator and its target interface; the driver of every level
  tools/       query, edit, fix, rewrite, the refactorings, same-output
```

Items are private unless another module uses them, and then `pub`; a
module imports by name what it uses from the others, `use
crate::front::ast::{NODES, child};` (and its main enum's variants, e.g.
`use crate::middle::ir::Op::{Add, Sub};`; 0.8 has no `*` imports, and
`tachyonc --fix-imports` wrote these lists from the `*` imports before).
The modules mirror the numbered files of 0.1 to 0.5 (`00_base.tach` is
`base/mod.tach`, `46_opt.tach` is `middle/opt.tach`, and so on). The
folders were made with `tachyonc refactor move-module`, in one script, and
proven to change no output with `tachyonc same-output`
([docs/refactor-modules.md](../docs/refactor-modules.md)).

| file | |
|---|---|
| `main.tach` | the root and the driver: the `mod` items of the folders, the command line, and host detection |
| **base/** | |
| `base/mod.tach` | C library declarations, growable arrays, byte buffers, the symbol interner and its growing tables, source files, error reporting and recovery (several errors at once) |
| `base/timer.tach` | `--time-passes`: the CPU time of each phase |
| **front/** | |
| `front/lexer.tach` | source text to tokens; token for token the same as the seed's lexer |
| `front/cpp.tach` | `import` (1/2): the C preprocessor, with the target C compiler's macros and include path |
| `front/cimport.tach` | `import` (2/2): C declarations and layouts, written out as tachyon source |
| `front/cheader.tach` | `--emit-header`: the C header of a program |
| `front/stdsrc.tach` | the standard library's source, built in (generated from `compiler/std/std.tach` by `compiler/std/embed.sh`) |
| `front/ast.tach` | the AST: an arena of uniform nodes (`NODES`), child lists in `LISTS` |
| `front/parser.tach` | recursive descent for items and statements, a Pratt parser for expressions; recovery at statements and items |
| `front/modules.tach` | modules: loading `mod` files, the module tree, item keys, scopes (`use`, `pub`, paths) |
| `front/types.tach` | interned types, layouts, the tables of structs, functions, constants and statics |
| `front/check.tach` | the bidirectional type checker; records a type on every expression node |
| `front/consteval.tach` | compile-time evaluation: constants, array lengths, static initializers |
| `front/patterns.tach` | patterns: their checking, refutability, `match`, and exhaustiveness and reachability by usefulness |
| `front/generics.tach` | generics: instances of structs, enums and functions (copies of their templates), inference of type arguments, symbols |
| `front/traits.tach` | traits (0.9): bounded generics, by monomorphization |
| **middle/** | |
| `middle/ir.tach` | the IR (`-O1` and up): instructions, blocks, functions, printing, verification |
| `middle/lower.tach` | the checked AST to IR, building SSA form (Braun et al.) |
| `middle/opt.tach` | CFG cleanups, dominators, dead code elimination, and the pass pipeline |
| `middle/adce.tach` | aggressive dead code elimination over control dependence (post-dominators) |
| `middle/fold.tach` | constant folding, SCCP, instruction combining |
| `middle/gvn.tach` | global value numbering, alias analysis, load and store forwarding, dead stores |
| `middle/egraph.tach` | rewrite rules by equality saturation, in GVN (0.9) |
| `middle/sroa.tach` | scalar replacement of aggregates; constant local tables to read-only data |
| `middle/inline.tach` | inlining over the call graph's components |
| `middle/ipo.tach` | interprocedural analyses: function attributes over the call graph (0.6) |
| `middle/licm.tach` | natural loops and loop-invariant code motion |
| `middle/loops.tach` | the loop forest, canonical loops, LCSSA, the SSA updater, cloning, loop rotation |
| `middle/lsr.tach` | loop strength reduction (pointer induction variables), loop unswitching |
| `middle/range.tach` | value ranges and facts: bounds-check elimination, comparison folding, jump threading, comparison chains to switches |
| `middle/scev.tach` | induction variables, trip counts, exit values, dead loop deletion, unrolling |
| `middle/tre.tach` | tail recursion elimination with accumulators |
| `middle/promote.tach` | scalar promotion of memory locations in loops (0.6) |
| `middle/vectorize.tach` | the loop vectorizer (0.10): innermost and outer loops, run-time guards, remainders; its cost model, and unrolling with run-time trip counts in its frame (0.11) |
| `middle/slp.tach` | the SLP vectorizer (0.11): groups of stores to the lanes of a vector, their values packed |
| `middle/profile.tach` | profiles (0.10): instrumentation, the runtime's source, reading a profile |
| `middle/unsafecheck.tach` | `--check-unsafe` (0.10): unsafe code's raw-pointer accesses checked at run time |
| **back/** | |
| `back/isel.tach` | instruction selection: the optimized IR to machine operations |
| `back/regalloc.tach` | liveness, linear-scan register allocation |
| `back/layout.tach` | block layout: the order blocks are emitted in |
| `back/emit.tach` | emission of the allocated IR: operands, parallel moves, calls, frames |
| `back/abi.tach` | C's calling convention for aggregates (AArch64 and System V): classification into pieces, locations; shared with `-O0` |
| `back/mc_arm64.tach` | AArch64 instructions on physical registers |
| `back/mc_x86_64.tach` | x86-64 instructions on physical registers |
| `back/objfile.tach` | the assembler: Mach-O and ELF objects from the assembly text, line tables from `.loc`s, compact unwind from CFI (0.11) |
| `back/enc_arm64.tach`, `back/enc_x86.tach` | instruction encoding for the assembler |
| `back/dwarf.tach` | `-g` (0.11): `.file`/`.loc` from source positions, the compile unit and its functions (.debug_info), CFI on Mach-O |
| **gen0/** | |
| `gen0/gen.tach` | the driver of code generation (every level), and the `-O0` code generator: walks the checked AST, in terms of the target interface |
| `gen0/target.tach` | the target interface: targets, the machine model's virtual registers, object-format details (symbols, sections, labels), and dispatch to the instruction set |
| `gen0/arm64.tach` | AArch64 for `-O0`: instructions, Apple's arm64 calling convention and AAPCS64's, Mach-O and ELF symbol syntax |
| `gen0/x86_64.tach` | x86-64 for `-O0`: AT&T-syntax instructions and the System V calling convention |
| **tools/** | |
| `tools/query.tach` | `tachyonc query` (0.11): definitions, their source, resolved references and module items, from the front end (see [docs/query.md](../docs/query.md)) |
| `tools/query_text.tach` | `query text`, `query show FILE`, a module's regions (0.12) |
| `tools/plan.tach` | the planning queries (0.11): `query stats`, `deps`, `unused`, `impact`; `tachyonc lint` (see [docs/refactor.md](../docs/refactor.md)) |
| `tools/proc.tach` | processes and files for the tools: running a program for its output, workers, renames, directories |
| `tools/edit.tach` | the edit engine (0.11): byte-range replacements applied atomically (checked by the front end before they are written), diffs, the journal; `tachyonc edit`, `undo`, `check` |
| `tools/patch.tach` | `edit patch`, `edit insert --in` (0.12): edits inside an item, by its text |
| `tools/fix.tach` | `tachyonc fix` (0.11): missing and unused imports, `pub`, unsafe blocks, wildcard imports, as one edit |
| `tools/fiximports.tach`, `tools/fixunsafe.tach` | `fix --only imports` (0.8's `--fix-imports`) and `fix --only unsafe` (0.9's `--fix-unsafe`) |
| `tools/sameout.tach` | `tachyonc same-output` (0.11): this compiler's output against another's, on a corpus |
| `tools/rewrite.tach` | `tachyonc rewrite` (0.11): typed structural search and replace on the nodes as parsed (see [docs/refactor-shape.md](../docs/refactor-shape.md)) |
| `tools/refactor_shape.tach` | `tachyonc refactor signature`, `field`, `variant` (0.11): a definition's shape changed with every use |
| `tools/refactor_mod/` | `refactor rename`, `new-module`, `move-module` (0.11; see [docs/refactor-modules.md](../docs/refactor-modules.md)) |
| `tools/refactor_move/` | `refactor move` and `split` (0.11) |
| `tools/script.tach` | `tachyonc refactor --script` (0.11): commands run in turn on each other's copies, checked once |
| `tools/commands.tach` | the table of the commands that change a program (0.11), shared by the command line and scripts |

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

0.5.0 reads `std` only when the files of the command line name it (fixed
in 0.6), so `main.tach` names it (`use std::Option;`).

Features new in 0.6 enter this source in 0.7.

Error recovery uses `_setjmp`/`_longjmp` (see `err_end` in `base/mod.tach`): a
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
