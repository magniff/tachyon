// `if` and loops, `break` and `continue`.

use super::layout::{is_compound, is_scalar, is_void, scalar_ir};
use super::{BlockId, CmpOp, Inst, LoopTarget, Lowerer, Term, VReg};
use crate::parser::{Block, Expr, ExprKind, Pattern, PatternKind, Spanned};
use crate::typechecker::TypeInternal;

type Label = Option<Spanned<String>>;

fn label_name(label: &Label) -> Option<String> {
    label.as_ref().map(|(name, _)| name.clone())
}

impl Lowerer<'_> {
    // ---- if ----

    // The value of an `if` of type `expected`: a scalar, the address of a
    // compound, or a placeholder for () and `!`.
    pub(super) fn lower_if_value(
        &mut self,
        cond: &Expr,
        then_block: &Block,
        else_block: Option<&Block>,
        expected: &TypeInternal,
    ) -> VReg {
        if is_compound(expected) {
            let addr = self.alloc_temp(expected);
            self.lower_if_into(cond, then_block, else_block, addr, expected);
            return addr;
        }
        let (then_bb, else_bb, merge) = self.lower_if_branch(cond, else_block.is_some());
        let Some(else_block) = else_block.filter(|_| is_scalar(expected)) else {
            // No value: () (or `!`).
            self.start_block(then_bb);
            self.lower_block_effect(then_block);
            self.finish_block(Term::Jump(merge));
            if let Some(else_block) = else_block {
                self.start_block(else_bb);
                self.lower_block_effect(else_block);
                self.finish_block(Term::Jump(merge));
            }
            self.start_block(merge);
            return self.unit_value();
        };

        // Each branch stores its value in a slot; the merge block loads it.
        let ir = scalar_ir(expected);
        let result = self.alloc_slot(ir.size(), ir.size());
        for (block, body) in [(then_bb, then_block), (else_bb, else_block)] {
            self.start_block(block);
            let value = self.lower_block_value(body, expected);
            let addr = self.slot_addr(result);
            self.emit(Inst::Store(addr, value, ir));
            self.finish_block(Term::Jump(merge));
        }
        self.start_block(merge);
        let value = self.fresh_vreg();
        let addr = self.slot_addr(result);
        self.emit(Inst::Load(value, addr, ir));
        value
    }

    // Writes the value of an `if` of type `ty` to `dst`.
    pub(super) fn lower_if_into(
        &mut self,
        cond: &Expr,
        then_block: &Block,
        else_block: Option<&Block>,
        dst: VReg,
        ty: &TypeInternal,
    ) {
        let (then_bb, else_bb, merge) = self.lower_if_branch(cond, else_block.is_some());
        self.start_block(then_bb);
        self.lower_block_into(then_block, dst, ty);
        self.finish_block(Term::Jump(merge));
        if let Some(else_block) = else_block {
            self.start_block(else_bb);
            self.lower_block_into(else_block, dst, ty);
            self.finish_block(Term::Jump(merge));
        }
        self.start_block(merge);
    }

    // Evaluates the condition and branches on it. Returns the then, else and
    // merge blocks; without an `else` the else block is the merge block.
    fn lower_if_branch(&mut self, cond: &Expr, has_else: bool) -> (BlockId, BlockId, BlockId) {
        let cond = self.lower_value(cond, &TypeInternal::Bool);
        let then_bb = self.fresh_block();
        let merge = self.fresh_block();
        let else_bb = if has_else { self.fresh_block() } else { merge };
        self.finish_block(Term::CondBr {
            cond,
            then_bb,
            else_bb,
        });
        (then_bb, else_bb, merge)
    }

    // ---- Loops ----

    // Lowers `body` as the body of a loop that `continue`s at
    // `continue_block` and `break`s to `break_block`.
    fn lower_loop_body(&mut self, target: LoopTarget, body: &Block) {
        self.loops.push(target);
        self.lower_block_effect(body);
        self.loops.pop();
    }

    // `loop { body }`; its value (of type `ty`) comes from `break value`.
    pub(super) fn lower_loop(&mut self, label: &Label, body: &Block, ty: &TypeInternal) -> VReg {
        let result = if is_void(ty) {
            None
        } else {
            Some((self.alloc_temp(ty), ty.clone()))
        };
        let header = self.fresh_block();
        let exit = self.fresh_block();
        self.finish_block(Term::Jump(header));
        self.start_block(header);
        let target = LoopTarget {
            label: label_name(label),
            continue_block: header,
            break_block: exit,
            result: result.clone(),
        };
        self.lower_loop_body(target, body);
        self.finish_block(Term::Jump(header));
        self.start_block(exit);
        match result {
            Some((addr, ty)) if is_scalar(&ty) => self.load(addr, scalar_ir(&ty)),
            Some((addr, _)) => addr,
            None => self.unit_value(),
        }
    }

    pub(super) fn lower_while(&mut self, label: &Label, cond: &Expr, body: &Block) {
        let header = self.fresh_block();
        let body_block = self.fresh_block();
        let exit = self.fresh_block();
        self.finish_block(Term::Jump(header));
        self.start_block(header);
        let cond = self.lower_value(cond, &TypeInternal::Bool);
        self.finish_block(Term::CondBr {
            cond,
            then_bb: body_block,
            else_bb: exit,
        });
        self.start_block(body_block);
        let target = LoopTarget {
            label: label_name(label),
            continue_block: header,
            break_block: exit,
            result: None,
        };
        self.lower_loop_body(target, body);
        self.finish_block(Term::Jump(header));
        self.start_block(exit);
    }

    // `for i in a..b { body }` (or `a..=b`): the bounds are evaluated once;
    // the counter never steps past the end, so `0..=255u8` terminates.
    pub(super) fn lower_for(
        &mut self,
        label: &Label,
        pattern: &Pattern,
        iter: &Expr,
        body: &Block,
    ) {
        let ExprKind::Range {
            start,
            end,
            inclusive,
        } = &iter.kind
        else {
            panic!("ICE: the checker only accepts 'for' over a range")
        };
        let elem_ty = self.type_of(iter);
        let ir = scalar_ir(&elem_ty);
        let counter = self.alloc_temp(&elem_ty);
        let limit = self.alloc_temp(&elem_ty);
        let start_value = self.lower_value(start, &elem_ty);
        self.emit(Inst::Store(counter, start_value, ir));
        let end_value = self.lower_value(end, &elem_ty);
        self.emit(Inst::Store(limit, end_value, ir));

        let header = self.fresh_block();
        let body_block = self.fresh_block();
        let latch = self.fresh_block();
        let exit = self.fresh_block();
        self.finish_block(Term::Jump(header));

        self.start_block(header);
        let cmp = if *inclusive { CmpOp::LtEq } else { CmpOp::Lt };
        let index = self.lower_for_test(counter, limit, cmp, &elem_ty, body_block, exit);

        self.start_block(body_block);
        self.push_scope();
        if let PatternKind::Binding { name, .. } = &pattern.kind {
            // Each iteration binds a copy: changing it does not affect the
            // counter.
            let var = self.alloc_temp(&elem_ty);
            self.emit(Inst::Store(var, index, ir));
            self.define(name.clone(), var, elem_ty.clone());
        }
        let target = LoopTarget {
            label: label_name(label),
            continue_block: latch,
            break_block: exit,
            result: None,
        };
        self.lower_loop_body(target, body);
        self.pop_scope();
        self.finish_block(Term::Jump(latch));

        self.start_block(latch);
        self.lower_for_step(counter, limit, *inclusive, &elem_ty, header, exit);
        self.start_block(exit);
    }

    // The header of a `for` loop: loads the counter, and continues to the
    // body while `counter cmp limit`. Returns the loaded counter.
    fn lower_for_test(
        &mut self,
        counter: VReg,
        limit: VReg,
        cmp: CmpOp,
        elem_ty: &TypeInternal,
        body: BlockId,
        exit: BlockId,
    ) -> VReg {
        let ir = scalar_ir(elem_ty);
        let index = self.load(counter, ir);
        let last = self.load(limit, ir);
        let more = self.fresh_vreg();
        self.emit(Inst::ICmp(more, cmp, index, last, ir, elem_ty.is_signed()));
        self.finish_block(Term::CondBr {
            cond: more,
            then_bb: body,
            else_bb: exit,
        });
        index
    }

    // The latch of a `for` loop: steps the counter and jumps back to the
    // header. An inclusive range stops at its end instead of stepping past
    // it (the end may be the type's maximum).
    fn lower_for_step(
        &mut self,
        counter: VReg,
        limit: VReg,
        inclusive: bool,
        elem_ty: &TypeInternal,
        header: BlockId,
        exit: BlockId,
    ) {
        let ir = scalar_ir(elem_ty);
        let current = self.load(counter, ir);
        if inclusive {
            let last = self.load(limit, ir);
            let done = self.fresh_vreg();
            self.emit(Inst::ICmp(
                done,
                CmpOp::Eq,
                current,
                last,
                ir,
                elem_ty.is_signed(),
            ));
            let step_block = self.fresh_block();
            self.finish_block(Term::CondBr {
                cond: done,
                then_bb: exit,
                else_bb: step_block,
            });
            self.start_block(step_block);
        }
        let one = self.const_int(1, ir);
        let next = self.fresh_vreg();
        self.emit(Inst::IAdd(next, current, one, ir));
        self.emit(Inst::Store(counter, next, ir));
        self.finish_block(Term::Jump(header));
    }

    // ---- break and continue ----

    // The index in `self.loops` of the loop a `break`/`continue` targets.
    fn loop_index(&self, label: &Label) -> usize {
        match label {
            None => self.loops.len() - 1,
            Some((name, _)) => self
                .loops
                .iter()
                .rposition(|target| target.label.as_deref() == Some(name.as_str()))
                .expect("ICE: the checker resolves loop labels"),
        }
    }

    pub(super) fn lower_break(&mut self, label: &Label, value: Option<&Expr>) {
        let index = self.loop_index(label);
        let result = self.loops[index].result.clone();
        if let Some(value) = value {
            match result {
                Some((addr, ty)) => self.store_expr(value, addr, &ty),
                None => self.lower_effect(value),
            }
        }
        let target = self.loops[index].break_block;
        self.terminate(Term::Jump(target));
    }

    pub(super) fn lower_continue(&mut self, label: &Label) {
        let index = self.loop_index(label);
        let target = self.loops[index].continue_block;
        self.terminate(Term::Jump(target));
    }
}
