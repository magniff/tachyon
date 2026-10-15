# 22-refactor-rename: rename `ir_make`, move the IR builders

**The change.** This task is a pure refactoring across modules in the
middle end:

1. It renames `crate::middle::ir::ir_make` to `ir_new_inst`. That is 88
   references in 24 files at the 0.15 base, spread over the optimizer
   passes, the vectorizer, the lowering and the instruction selector. The
   new name follows the IR's other constructors (`ir_new_func`,
   `ir_new_block`, `ir_new_slot`).
2. It moves the eight helpers that make an instruction and append it to
   `CUR` (`emit_ir`, `ir_const`, `ir_binary`, `ir_cmp`, `ir_load`,
   `ir_store`, `ir_slot_addr`, `ir_offset`) out of `ir/mod.tach` into a
   new module `crate::middle::ir::build` (`compiler/src/middle/ir/build.tach`).
   This fixes the `use` lines of the 7 lowering files that call them. The
   moved helpers still call the renamed function, so the two steps
   interact.

**Why it is realistic.** Renaming a widely used function and splitting a
module are everyday maintenance, and `tachyonc refactor rename`,
`refactor new-module` and `refactor move` were built for exactly this.
An agent that uses them finishes in a few minutes. An agent working by
hand has about 30 files of call sites and multi-line `use` lists to fix.

**Grading** (about 1.5 min in all):

- the build, with the fixpoint (~10 s);
- the suite filters `vec`, `struct`, `loop` and `slice`: 56 run cases
  across the lowering paths (~30 s);
- `same-output` against the starter on `compiler/src` and `examples`
  (~10-15 s). The compiler's output must not change.
- `grade.sh` (~6 s), which checks the structure:
  - `ir_make` occurs nowhere in `compiler/src` code. Comments are cut
    before the word is searched for, so comments are not graded.
  - `crate::middle::ir::ir_new_inst` is defined.
  - Its call count (`query refs --kind call --count`) equals the count
    for `ir_make` in the starter, which is computed at grading time.
  - Each moved function is defined in `compiler/src/middle/ir/build.tach`
    (or `build/mod.tach`), and has exactly one `fn NAME` in `compiler/src`.
  - Each moved function's call count equals its count in the starter.
  - No `pub use` statement anywhere in `compiler/src` names a moved
    function (no re-export).

  Calls are counted rather than all references because the move adds
  `use` lines.

**The reference solution** (`solution.patch`) was made with
`refactor rename crate::middle::ir::ir_make ir_new_inst`,
`refactor new-module crate::middle::ir::build`,
`refactor move crate::middle::ir::{the eight} --to crate::middle::ir::build`
and a header comment added with `edit replace crate::middle::ir::build::header`.
The starter is the base itself, so there is no `starter.patch`.

**At v0.16.0.** The grader takes its reference counts from the starter,
so new call sites in 0.16 are handled. Only the names are fixed: `ir_make`,
the eight helpers, `crate::middle::ir` and the free path
`crate::middle::ir::build`. Before the eval, check that they still exist:
`target/tachyonc query def crate::middle::ir::ir_make crate::middle::ir::emit_ir`.
If one of them was renamed or moved in 0.16, edit task.md and grade.sh
to match. 0.16's source changes (`?`, derive, interpolation) may also
stop `solution.patch` from applying. To regenerate it, run the commands
above in a fresh copy of v0.16.0 (`git archive v0.16.0 | tar -x`), then
take `git diff` after `git add -N compiler/src/middle/ir/build.tach`.
If 0.16 adds a module named `build` under `middle::ir`, choose another
name in all three files.
