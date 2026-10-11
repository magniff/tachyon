# tachyonc: the tachyon compiler, in tachyon

`compiler/src/*.tach` is one program, compiled together:

```
$ tachyonc compiler/src/*.tach -o tachyonc.s && cc -o tachyonc tachyonc.s -lm
$ tachyonc examples/md5.tach -o md5.s && cc -o md5 md5.s -lm
$ tachyonc --target x86_64-linux compiler/src/*.tach -o linux.s   # cross-compile
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
| `40_gen.tach` | the code generator: walks the checked AST, in terms of the target interface |
| `41_target.tach` | the target interface: targets, the machine model's virtual registers, object-format details (symbols, sections, labels), and dispatch to the instruction set |
| `42_arm64.tach` | AArch64: instructions and Apple's arm64 calling convention |
| `43_x86_64.tach` | x86-64: AT&T-syntax instructions and the System V calling convention |
| `90_main.tach` | the command line, and host detection |

The code generator uses a simple machine model: every expression leaves its
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

Semantics follow the seed exactly where programs can observe them, on every
target: evaluation order (an assignment computes its target's address
before the value; a compound assignment reads the old value before
evaluating the right-hand side), wrapping arithmetic, shift amounts taken
modulo 32 for types up to 32 bits and modulo 64 for 64-bit ones, saturating
float-to-integer casts, and NaN-aware comparisons. One difference: integer
division by zero is not trapped (`x / 0` is 0 and `x % 0` is `x`, the
behaviour of AArch64's divide instructions, reproduced on x86-64), where
the seed traps.

## The language subset of its own source

A release's compiler source may only use what the previous release's binary
supports (see [docs/releases.md](../docs/releases.md)). The 0.1 source,
built by the seed, uses:

- items: `fn`, `extern fn` (including `-> !`), `struct`, `const`, `static`
  and `static mut` (with struct literals and casts as initializers);
- types: `i64`, `i32`, `u64`, `u32`, `u8`, `bool`, `f64`, `f32`, pointers
  (`*T`, `**T`) and fixed arrays (`[T; N]`);
- statements: `let`, `let mut`;
- expressions: arithmetic, bitwise, shift, comparison and logical operators,
  compound assignment, `as` casts, `&` and `*`, indexing of arrays and
  pointers, field access, struct literals, array literals and `[v; n]`,
  calls;
- control flow: `if`/`else if`/`else` (also as values), `while`, `for` over
  `a..b`, `loop`, `break`, `continue`, `return`;
- literals: integers (decimal and hex), characters, floats, `c"..."`,
  `true`/`false`.

It does not use tuples, function pointer types, type aliases, loop labels,
`break` with a value, `..=`, `"..."` strings or block comments; all of these
are supported by the compiler itself and covered by the test suite.

One rule its source follows that is easy to miss: since an assignment
computes the target's address first, `NODES[n].a = parse_expr()` would write
into the old array if `parse_expr` grows (reallocates) `NODES`. Such calls
are made into a local first.

## Known limits of 0.1

- One error per compilation (the seed recovers and reports all of them).
- Structs passed to or returned from C functions by value use tachyon's
  convention, not C's (`div` returning `div_t` is wrong): the same limit as
  the seed (`tests/run/abi_extern_small_struct.tach` is an XFAIL).
- Targets: AArch64 macOS, x86-64 Linux and macOS. No AArch64 Linux yet.
- No optimizations: the output is straightforward stack-machine code.
