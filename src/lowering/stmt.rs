// Blocks, statements, assignment and `return`.

use super::layout::{field_offsets, is_scalar, is_void, scalar_ir};
use super::{IRType, Inst, Lowerer, Term, VReg};
use crate::parser::{AssignOp, BinOp, Block, Expr, ExprKind, LetStmt, Pattern, PatternKind, Stmt};
use crate::typechecker::TypeInternal;

impl Lowerer<'_> {
    // Lowers the block's statements in the current scope; stops after one
    // that diverges (the rest is unreachable) and returns whether it did.
    pub(super) fn lower_stmts(&mut self, block: &Block) -> bool {
        for stmt in &block.stmts {
            let diverges = match stmt {
                Stmt::Let(let_stmt) => {
                    self.lower_let(let_stmt);
                    self.diverges(&let_stmt.init)
                }
                Stmt::Expr(expr_stmt) => {
                    self.lower_effect(&expr_stmt.expr);
                    self.diverges(&expr_stmt.expr)
                }
            };
            if diverges {
                return true;
            }
        }
        false
    }

    // The block's value, of type `expected`.
    pub(super) fn lower_block_value(&mut self, block: &Block, expected: &TypeInternal) -> VReg {
        self.push_scope();
        let diverged = self.lower_stmts(block);
        let value = match &block.expr {
            Some(tail) if !diverged => self.lower_value(tail, expected),
            _ => self.placeholder(expected),
        };
        self.pop_scope();
        value
    }

    // Writes the block's value of type `ty` to `dst`.
    pub(super) fn lower_block_into(&mut self, block: &Block, dst: VReg, ty: &TypeInternal) {
        self.push_scope();
        if !self.lower_stmts(block)
            && let Some(tail) = &block.expr
        {
            self.lower_into(tail, dst, ty);
        }
        self.pop_scope();
    }

    pub(super) fn lower_block_effect(&mut self, block: &Block) {
        self.push_scope();
        if !self.lower_stmts(block)
            && let Some(tail) = &block.expr
        {
            self.lower_effect(tail);
        }
        self.pop_scope();
    }

    // Every binding gets its own stack slot, even scalars: assignments in
    // loops and branches then update the canonical location, and reads in
    // other blocks see the latest value.
    fn lower_let(&mut self, let_stmt: &LetStmt) {
        let ty = self.type_of(&let_stmt.init);
        match &let_stmt.pattern.kind {
            PatternKind::Wildcard => self.lower_effect(&let_stmt.init),
            PatternKind::Binding { name, .. } => {
                let addr = self.alloc_temp(&ty);
                self.store_expr(&let_stmt.init, addr, &ty);
                self.define(name.clone(), addr, ty);
            }
            PatternKind::Tuple(_) => {
                // Destructure a private copy of the value.
                let addr = self.alloc_temp(&ty);
                self.lower_into(&let_stmt.init, addr, &ty);
                self.bind_pattern_at(&let_stmt.pattern, addr, &ty);
            }
        }
    }

    // Binds the names in `pattern` to the parts of the value at `addr`.
    pub(super) fn bind_pattern_at(&mut self, pattern: &Pattern, addr: VReg, ty: &TypeInternal) {
        match &pattern.kind {
            PatternKind::Wildcard => {}
            PatternKind::Binding { name, .. } => self.define(name.clone(), addr, ty.clone()),
            PatternKind::Tuple(patterns) => {
                let TypeInternal::Tuple(elems) = ty else {
                    return;
                };
                let offsets = field_offsets(elems, &self.checked.structs);
                for ((pattern, elem_ty), (offset, _)) in patterns.iter().zip(elems).zip(&offsets) {
                    let elem_addr = self.member_ptr(addr, *offset);
                    self.bind_pattern_at(pattern, elem_addr, elem_ty);
                }
            }
        }
    }

    pub(super) fn lower_assign(&mut self, op: AssignOp, target: &Expr, value: &Expr) {
        let target_ty = self.type_of(target);
        let addr = self.lower_address(target, &target_ty);
        match op.binop() {
            None => self.lower_plain_assign(addr, value, &target_ty),
            Some(op) => self.lower_compound_assign(op, addr, value, &target_ty),
        }
    }

    // `target = value`, with the target's address already computed.
    fn lower_plain_assign(&mut self, addr: VReg, value: &Expr, ty: &TypeInternal) {
        if is_scalar(ty) {
            let lowered = self.lower_value(value, ty);
            self.emit(Inst::Store(addr, lowered, scalar_ir(ty)));
        } else if matches!(value.kind, ExprKind::Ident(_) | ExprKind::Call { .. }) {
            self.lower_into(value, addr, ty);
        } else {
            // The value may read the target (`p = P { x: p.y, y: p.x }`),
            // so build it aside and copy it over afterwards.
            let temp = self.lower_address(value, ty);
            let size = self.size_of(ty);
            self.emit(Inst::MemCopy {
                dst: addr,
                src: temp,
                size,
            });
        }
    }

    // `target op= value`: load, operate, store.
    fn lower_compound_assign(&mut self, op: BinOp, addr: VReg, value: &Expr, ty: &TypeInternal) {
        let ir = scalar_ir(ty);
        let old = self.load(addr, ir);
        // A shift amount keeps its own type.
        let value_ty = if matches!(op, BinOp::Shl | BinOp::Shr) {
            self.type_of(value)
        } else {
            ty.clone()
        };
        let operand = self.lower_value(value, &value_ty);
        let result = self.emit_arith(op, old, operand, ty);
        self.emit(Inst::Store(addr, result, ir));
    }

    pub(super) fn lower_return(&mut self, value: Option<&Expr>) {
        let term = match value {
            Some(value) => self.lower_return_value(value),
            None => Term::Ret(None),
        };
        self.terminate(term);
    }

    // Lowers the returned value; the terminator that returns it.
    pub(super) fn lower_return_value(&mut self, value: &Expr) -> Term {
        let return_ty = self.return_ty.clone();
        if is_void(&return_ty) {
            self.lower_effect(value);
            Term::Ret(None)
        } else if is_scalar(&return_ty) {
            let lowered = self.lower_value(value, &return_ty);
            Term::Ret(Some((lowered, scalar_ir(&return_ty))))
        } else {
            let sret = self
                .sret
                .expect("ICE: a function with a compound result has an sret parameter");
            self.lower_into(value, sret, &return_ty);
            Term::Ret(Some((sret, IRType::Ptr)))
        }
    }
}
