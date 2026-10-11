# tachyonc: the tachyon compiler, in tachyon

`compiler/src/*.tach` is one program, compiled together:

```
$ tachyonc compiler/src/*.tach -o tachyonc.s && clang -arch arm64 -o tachyonc tachyonc.s
$ tachyonc examples/md5.tach -o md5.s && clang -arch arm64 -o md5 md5.s
$ tachyonc --tokens file.tach        # the token dump (same format as stage0's `tachyon tokens`)
$ tachyonc --version
```

It accepts the whole language of [docs/grammar.md](../docs/grammar.md) and
emits AArch64 assembly for macOS (Apple's arm64 ABI), which clang assembles
and links against libc. Errors are reported in stage0's format
(`error[type error]: ...` / ` --> file: line L, column C` / `  = help: ...`);
compilation stops at the first error.

## Structure

| file | |
|---|---|
| `00_base.tach` | C library declarations, growable arrays, byte buffers, the symbol interner, source files, error reporting |
| `10_lexer.tach` | source text to tokens; token for token the same as stage0's lexer |
| `20_ast.tach` | the AST: an arena of uniform nodes (`NODES`), child lists in `LISTS` |
| `21_parser.tach` | recursive descent for items and statements, a Pratt parser for expressions |
| `30_types.tach` | interned types, layouts, the tables of structs, functions, constants and statics |
| `31_check.tach` | the bidirectional type checker; records a type on every expression node |
| `32_const.tach` | compile-time evaluation: constants, array lengths, static initializers |
| `40_gen.tach` | the code generator: walks the checked AST |
| `41_arm64.tach` | the target layer: AArch64 instructions, the ABI, data directives |
| `90_main.tach` | the command line |

The code generator uses a simple machine model: every expression leaves its
value in an accumulator (`x0`, `d0`/`s0`, or `x0` holding the address of a
struct, tuple or array), operands wait on a stack of 16-byte temporaries,
and every local lives in a frame slot. Calls follow the C convention for
scalars, so tachyon functions can be handed to C (e.g. as `qsort`
callbacks); compound values are passed as a pointer to a copy and returned
through `x8`. Integers are kept sign- or zero-extended to 64 bits, so
narrow arithmetic only needs a final extension. All target-specific text is
in `41_arm64.tach`; another target (Linux, x86-64) would replace that file
and the target-specific parts of the call sequence in `40_gen.tach`.

Semantics follow stage0 exactly where programs can observe them: evaluation
order (an assignment computes its target's address before the value; a
compound assignment reads the old value before evaluating the right-hand
side), wrapping arithmetic, shift amounts taken modulo 32 for types up to 32
bits and modulo 64 for 64-bit ones, saturating float-to-integer casts, and
NaN-aware comparisons.

## The language subset of its own source

A release's compiler source may only use what the previous release's binary
supports (see [docs/releases.md](../docs/releases.md)). The 1.0 source,
built by stage0, uses:

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

## Known limits of 1.0

- One error per compilation (stage0 recovers and reports all of them).
- Structs passed to or returned from C functions by value use tachyon's
  convention, not C's (`div` returning `div_t` is wrong): the same limit as
  stage0 (`tests/run/abi_extern_small_struct.tach` is an XFAIL).
- macOS on arm64 only.
- No optimizations: the output is straightforward stack-machine code.
