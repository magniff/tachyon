# Refactor the IR module: one rename, one move

This is a pure refactoring of the compiler's IR module, `crate::middle::ir`
(`compiler/src/middle/ir/mod.tach`). The compiler must behave exactly as
before.

## 1. Rename `ir_make` to `ir_new_inst`

The IR's constructors are `ir_new_func`, `ir_new_block` and `ir_new_slot`.
The one that makes a new instruction, which is not yet in any block, is
called `ir_make`. That name does not say what it makes, and it breaks the
pattern. Rename `crate::middle::ir::ir_make` to `ir_new_inst`. Keep it in
`crate::middle::ir` and change every use in the compiler. No definition,
wrapper, alias or use of `ir_make` may remain in `compiler/src`. Update
any comment that names it too (comments are not graded).

## 2. Move the instruction builders into `crate::middle::ir::build`

Eight helpers each make an instruction and append it to the current block
(`CUR`): `emit_ir`, `ir_const`, `ir_binary`, `ir_cmp`, `ir_load`,
`ir_store`, `ir_slot_addr` and `ir_offset`. Only the lowering
(`crate::middle::lower`) uses them. Move all eight into a new module
`crate::middle::ir::build`: the file `compiler/src/middle/ir/build.tach`,
declared in `crate::middle::ir` as `pub mod build;`.

- Keep their names, signatures and bodies (apart from the rename above).
- Each one must be defined only in `crate::middle::ir::build`. No copy,
  wrapper or re-export (`pub use`) may stay in `crate::middle::ir` or
  anywhere else.
- Every module that uses them imports them from `crate::middle::ir::build`.

## Acceptance

- The compiler builds with `bootstrap/eval-build.sh`, and
  `target/tachyonc check` reports no errors.
- No other code changes. The number of calls to `ir_new_inst` and to each
  moved function is the same as before.
- Behaviour is unchanged. Before your first rebuild, save the starting
  compiler: `cp target/tachyonc target/old-tachyonc`. Then
  `target/tachyonc same-output target/old-tachyonc --corpus compiler/src --corpus examples`
  must report `identical`.
- These pass: `tests/run.sh vec`, `tests/run.sh struct`, `tests/run.sh loop`
  and `tests/run.sh slice`.
- This is a refactoring, so you do not need to add a test.
