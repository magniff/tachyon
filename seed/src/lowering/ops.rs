// Operators and casts.

use super::layout::{is_scalar, scalar_ir, type_internal_to_ir};
use super::{CmpOp, IRType, Inst, Lowerer, Term, VReg};
use crate::parser::{BinOp, Expr, UnaryOp};
use crate::typechecker::TypeInternal;

fn compare_op(op: BinOp) -> CmpOp {
    match op {
        BinOp::Eq => CmpOp::Eq,
        BinOp::Neq => CmpOp::Neq,
        BinOp::Lt => CmpOp::Lt,
        BinOp::Gt => CmpOp::Gt,
        BinOp::LtEq => CmpOp::LtEq,
        BinOp::GtEq => CmpOp::GtEq,
        _ => unreachable!("'{:?}' is not a comparison", op),
    }
}

impl Lowerer<'_> {
    pub(super) fn lower_binop(&mut self, op: BinOp, lhs: &Expr, rhs: &Expr) -> VReg {
        match op {
            BinOp::And => return self.lower_short_circuit(lhs, rhs, true),
            BinOp::Or => return self.lower_short_circuit(lhs, rhs, false),
            _ => {}
        }
        let lhs_ty = self.type_of(lhs);
        let lhs_value = self.lower_value(lhs, &lhs_ty);
        let rhs_ty = self.type_of(rhs);
        let rhs_value = self.lower_value(rhs, &rhs_ty);
        if !op.is_comparison() {
            return self.emit_arith(op, lhs_value, rhs_value, &lhs_ty);
        }
        let ir = type_internal_to_ir(&lhs_ty).unwrap_or(IRType::I64);
        let result = self.fresh_vreg();
        let cmp = compare_op(op);
        if ir.is_float() {
            self.emit(Inst::FCmp(result, cmp, lhs_value, rhs_value, ir))
        } else {
            self.emit(Inst::ICmp(
                result,
                cmp,
                lhs_value,
                rhs_value,
                ir,
                lhs_ty.is_signed(),
            ))
        }
        result
    }

    // An arithmetic, bitwise or shift operator on operands of type `ty`.
    pub(super) fn emit_arith(
        &mut self,
        op: BinOp,
        lhs: VReg,
        rhs: VReg,
        ty: &TypeInternal,
    ) -> VReg {
        let ir = type_internal_to_ir(ty).unwrap_or(IRType::I64);
        let float = ir.is_float();
        let signed = ty.is_signed();
        let dst = self.fresh_vreg();
        let inst = match op {
            BinOp::Add if float => Inst::FAdd(dst, lhs, rhs, ir),
            BinOp::Add => Inst::IAdd(dst, lhs, rhs, ir),
            BinOp::Sub if float => Inst::FSub(dst, lhs, rhs, ir),
            BinOp::Sub => Inst::ISub(dst, lhs, rhs, ir),
            BinOp::Mul if float => Inst::FMul(dst, lhs, rhs, ir),
            BinOp::Mul => Inst::IMul(dst, lhs, rhs, ir),
            BinOp::Div if float => Inst::FDiv(dst, lhs, rhs, ir),
            BinOp::Div => Inst::IDiv(dst, lhs, rhs, ir, signed),
            // The IR has no float remainder; libm provides it.
            BinOp::Mod if float => Inst::Call {
                dst: Some((dst, ir)),
                func: if ir == IRType::F64 { "fmod" } else { "fmodf" }.into(),
                args: vec![(lhs, ir), (rhs, ir)],
            },
            BinOp::Mod => Inst::IMod(dst, lhs, rhs, ir, signed),
            BinOp::Shl => Inst::IShl(dst, lhs, rhs, ir),
            BinOp::Shr => Inst::IShr(dst, lhs, rhs, ir, signed),
            BinOp::BitAnd => Inst::IBitAnd(dst, lhs, rhs, ir),
            BinOp::BitOr => Inst::IBitOr(dst, lhs, rhs, ir),
            BinOp::BitXor => Inst::IBitXor(dst, lhs, rhs, ir),
            _ => panic!("ICE: '{:?}' is not an arithmetic operator", op),
        };
        self.emit(inst);
        dst
    }

    // `lhs && rhs` (`is_and`) or `lhs || rhs`: `rhs` is only evaluated when
    // `lhs` does not decide the result. The result goes through a slot.
    fn lower_short_circuit(&mut self, lhs: &Expr, rhs: &Expr, is_and: bool) -> VReg {
        // The block where `lhs` alone decides the result.
        let decided = self.fresh_block();
        let rhs_block = self.fresh_block();
        let merge = self.fresh_block();
        let result = self.alloc_slot(1, 1);
        let cond = self.lower_value(lhs, &TypeInternal::Bool);
        let (then_bb, else_bb) = if is_and {
            (rhs_block, decided)
        } else {
            (decided, rhs_block)
        };
        self.finish_block(Term::CondBr {
            cond,
            then_bb,
            else_bb,
        });

        self.start_block(decided);
        let decided_value = self.const_int(!is_and as i64, IRType::I8);
        let addr = self.slot_addr(result);
        self.emit(Inst::Store(addr, decided_value, IRType::I8));
        self.finish_block(Term::Jump(merge));

        self.start_block(rhs_block);
        let rhs_value = self.lower_value(rhs, &TypeInternal::Bool);
        let addr = self.slot_addr(result);
        self.emit(Inst::Store(addr, rhs_value, IRType::I8));
        self.finish_block(Term::Jump(merge));

        self.start_block(merge);
        let value = self.fresh_vreg();
        let addr = self.slot_addr(result);
        self.emit(Inst::Load(value, addr, IRType::I8));
        value
    }

    pub(super) fn lower_unaryop(
        &mut self,
        op: UnaryOp,
        operand: &Expr,
        expected: &TypeInternal,
    ) -> VReg {
        match op {
            UnaryOp::Neg => {
                let ty = self.type_of(operand);
                let ir = scalar_ir(&ty);
                let value = self.lower_value(operand, &ty);
                let result = self.fresh_vreg();
                if ir.is_float() {
                    self.emit(Inst::FNeg(result, value, ir))
                } else {
                    self.emit(Inst::INeg(result, value, ir))
                }
                result
            }
            UnaryOp::Not => {
                let value = self.lower_value(operand, &TypeInternal::Bool);
                let result = self.fresh_vreg();
                self.emit(Inst::BoolNot(result, value));
                result
            }
            UnaryOp::BitNot => {
                let ty = self.type_of(operand);
                let ir = scalar_ir(&ty);
                let value = self.lower_value(operand, &ty);
                let result = self.fresh_vreg();
                self.emit(Inst::IBitNot(result, value, ir));
                result
            }
            UnaryOp::Deref => {
                let pointer_ty = self.type_of(operand);
                let pointer = self.lower_value(operand, &pointer_ty);
                if is_scalar(expected) {
                    self.load(pointer, scalar_ir(expected))
                } else {
                    pointer
                }
            }
            UnaryOp::AddrOf => {
                let ty = self.type_of(operand);
                self.lower_address(operand, &ty)
            }
        }
    }

    // `value as to`, for a value of type `from`.
    pub(super) fn lower_cast(
        &mut self,
        value: VReg,
        from: &TypeInternal,
        to: &TypeInternal,
    ) -> VReg {
        if *from == TypeInternal::Never {
            return self.placeholder(to);
        }
        let from_ir = scalar_ir(from);
        let to_ir = scalar_ir(to);
        if from_ir == to_ir {
            return value;
        }
        let result = self.fresh_vreg();
        let inst = if from.is_integer() && to.is_integer() {
            if to_ir.size() > from_ir.size() {
                Inst::IntExt(result, value, from_ir, to_ir, from.is_signed())
            } else if to_ir.size() < from_ir.size() {
                Inst::IntTrunc(result, value, from_ir, to_ir)
            } else {
                Inst::Mov(result, value)
            }
        } else if from.is_float() && to.is_float() {
            Inst::FloatToFloat(result, value, from_ir, to_ir)
        } else if from.is_integer() && to.is_float() {
            Inst::IntToFloat(result, value, from_ir, to_ir, from.is_signed())
        } else if from.is_float() && to.is_integer() {
            Inst::FloatToInt(result, value, from_ir, to_ir, to.is_signed())
        } else if *from == TypeInternal::Bool && to.is_integer() && to_ir.size() > 1 {
            Inst::IntExt(result, value, IRType::I8, to_ir, false)
        } else {
            // Pointers and integers of the same width, bool to an 8-bit
            // integer.
            Inst::Mov(result, value)
        };
        self.emit(inst);
        result
    }
}
