# tachyonc: the tachyon compiler, in tachyon

`compiler/src/*.tach` is one program, compiled together:

```
$ tachyonc compiler/src/*.tach -o tachyonc.s && cc -o tachyonc tachyonc.s -lm
$ tachyonc examples/md5.tach -o md5.s && cc -o md5 md5.s -lm
$ tachyonc --target x86_64-linux compiler/src/*.tach -o linux.s   # cross-compile
$ tachyonc -O0 examples/md5.tach -o md5.s     # -O0, -O1 or -O2 (the default)
$ tachyonc --emit-ir examples/md5.tach -o md5.ir    # the optimized IR
$ tachyonc --tokens file.tach        # the token dump (same format as the seed's `tachyon tokens`)
$ tachyonc --version                 # the release and the host
```

It accepts the whole language of [docs/grammar.md](../docs/grammar.md) and
emits assembly that `cc` assembles and links against libc, for one of:

| target | | |
|---|---|---|
| `aarch64-macos` | AArch64, Apple's arm64 ABI, Mach-O | `cc -arch arm64` |
| `x86_64-linux` | x86-64, System V ABI, ELF, position independent | `cc` (gcc or clang) |
| `x86_64-macos` | x86-64, System V ABI, Mach-O | `cc -arch x86_64` |

The default target is the host, found with `uname`; the assembly for a
target does not depend on the host. Errors are reported in the seed's
format (`error[type error]: ...` / ` --> file: line L, column C` /
`  = help: ...`); compilation stops at the first error.

## Structure

| file | |
|---|---|
| `00_base.tach` | C library declarations, growable arrays, byte buffers, the symbol interner, source files, error reporting |
| `10_lexer.tach` | source text to tokens; token for token the same as the seed's lexer |
| `20_ast.tach` | the AST: an arena of uniform nodes (`NODES`), child lists in `LISTS` |
| `21_parser.tach` | recursive descent for items and statements, a Pratt parser for expressions |
| `30_types.tach` | interned types, layouts, the tables of structs, functions, constants and statics |
| `31_check.tach` | the bidirectional type checker; records a type on every expression node |
| `32_const.tach` | compile-time evaluation: constants, array lengths, static initializers |
| `33_match.tach` | patterns: their checking, refutability, `match`, and exhaustiveness and reachability by usefulness |
| `40_gen.tach` | the driver of code generation, and the `-O0` code generator: walks the checked AST, in terms of the target interface |
| `41_abi.tach` | C's calling convention for aggregates (AArch64 and System V): classification into pieces, locations |
| `41_target.tach` | the target interface: targets, the machine model's virtual registers, object-format details (symbols, sections, labels), and dispatch to the instruction set |
| `42_arm64.tach` | AArch64 for `-O0`: instructions and Apple's arm64 calling convention |
| `43_x86_64.tach` | x86-64 for `-O0`: AT&T-syntax instructions and the System V calling convention |
| `44_ir.tach` | the IR (`-O1` and up): instructions, blocks, functions, printing, verification |
| `45_lower.tach` | the checked AST to IR, building SSA form (Braun et al.) |
| `46_opt.tach` | CFG cleanups, dominators, dead code elimination, and the pass pipeline |
| `47_fold.tach` | constant folding, SCCP, instruction combining |
| `48_gvn.tach` | global value numbering, alias analysis, load and store forwarding, dead stores |
| `48_sroa.tach` | scalar replacement of aggregates; constant local tables to read-only data |
| `49_inline.tach` | inlining over the call graph's components |
| `46_adce.tach` | aggressive dead code elimination over control dependence (post-dominators) |
| `49_licm.tach` | natural loops and loop-invariant code motion |
| `49_loop.tach` | the loop forest, canonical loops, LCSSA, the SSA updater, cloning, loop rotation |
| `49_lsr.tach` | loop strength reduction (pointer induction variables), loop unswitching |
| `49_range.tach` | value ranges and facts: bounds-check elimination, comparison folding, jump threading, comparison chains to switches |
| `49_scev.tach` | induction variables, trip counts, exit values, dead loop deletion, unrolling |
| `49_tre.tach` | tail recursion elimination with accumulators |
| `50_regalloc.tach` | block layout, liveness, linear-scan register allocation |
| `51_emit.tach` | emission of the allocated IR: operands, parallel moves, calls, frames |
| `52_mc_arm64.tach` | AArch64 instructions on physical registers |
| `53_mc_x86_64.tach` | x86-64 instructions on physical registers |
| `90_main.tach` | the command line, and host detection |

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
instruction text is in `42_arm64.tach` and `43_x86_64.tach`; a new
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

The 0.4 source is built by 0.3.0 and uses the 0.3 language:

- **C declarations** in an `extern "C" { ... }` block (`00_base.tach`,
  `90_main.tach`); 0.2's single `extern fn f(...);` declarations were
  removed from the language in 0.4;
- **fieldless enums** for every kind of thing that used to be an integer
  constant: `NodeKind` (AST nodes), `Tok` (tokens), `TyKind` (types), `Op`,
  `Cond` and `Term` (the IR), `Res` (what an identifier names), `AbiClass`,
  `Lattice` (SCCP). `Tok` and `Op` keep their 0.3 numbering
  (`Tok::Plus as i64` is 65): the IR's value numbering hashes opcodes;
- **match** for the dispatch over them (with guards and `|` alternatives);
- **methods**: `IntVec` (`v.push(x)`, `v.pop()`), `HMap` (`m.get(k)`,
  `m.put(k, v)`), and on the enums (`op.name()`, `op.is_pure()`,
  `cond.negate()`, `cond.mirror()`, `kind.text()`);
- **slices** where bytes were passed as a pointer and a length (`intern`,
  `buf_bytes`, `add_string`, `data_bytes`, the symbol table's `text`, the
  string literals `STRS`);
- assignments that evaluate their right side first, so `NODES[n].a =
  parse_expr()` is safe even when `parse_expr` reallocates `NODES`.

Not used yet: enums with fields, tuples, function pointer types, `#[repr]`
types, slicing of arrays. Most data still lives in global arrays indexed by
id (`NODES[n]`, `INSTS[v]`, `TYPES[t]`), and the element sizes passed to
`grow` are written out (`grow(..., 104)`: there is no `size_of`); a struct
whose fields change must have its size updated (`init_ir` checks the IR's).

Features new in 0.4 enter this source in 0.5.

To show that a change to the compiler's source changes nothing it emits,
`tests/compare.sh OLD NEW` compiles a corpus (the test programs, the
examples, the benchmarks, random programs, the compiler's own source at
HEAD and at the last release) with both compilers, at every level for
every target, and compares the assembly, the IR, the token dumps and the
diagnostics byte for byte. The 0.4 migration of this source to the 0.3
language was checked with it: identical output for all 7,500 compilations
(apart from the two programs testing the removed `extern fn`).

## Known limits

- One error per compilation (the seed recovers and reports all of them).
- `#[repr(C, align(N))]` takes N up to 16 (frames are not realigned).
- Targets: AArch64 macOS, x86-64 Linux and macOS. No AArch64 Linux yet.
- The optimizer's limits are listed at the end of
  [docs/optimizer.md](../docs/optimizer.md).
