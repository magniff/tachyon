// IR instructions to CLIF.

use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::{self, InstBuilder, types};
use cranelift_frontend::FuncInstBuilder;
use cranelift_module::Module;

use super::translate::{Translator, mem_flags};
use crate::lowering::{CmpOp, IRType, Inst, VReg};

// 2^63, the smallest float that does not convert to i64.
const TWO_POW_63: f64 = 9223372036854775808.0;

#[derive(Clone, Copy)]
enum ShiftKind {
    Shl,
    Ushr,
    Sshr,
}

fn int_condition(op: CmpOp, signed: bool) -> IntCC {
    match (op, signed) {
        (CmpOp::Eq, _) => IntCC::Equal,
        (CmpOp::Neq, _) => IntCC::NotEqual,
        (CmpOp::Lt, true) => IntCC::SignedLessThan,
        (CmpOp::Lt, false) => IntCC::UnsignedLessThan,
        (CmpOp::Gt, true) => IntCC::SignedGreaterThan,
        (CmpOp::Gt, false) => IntCC::UnsignedGreaterThan,
        (CmpOp::LtEq, true) => IntCC::SignedLessThanOrEqual,
        (CmpOp::LtEq, false) => IntCC::UnsignedLessThanOrEqual,
        (CmpOp::GtEq, true) => IntCC::SignedGreaterThanOrEqual,
        (CmpOp::GtEq, false) => IntCC::UnsignedGreaterThanOrEqual,
    }
}

// Ordered comparisons are false for NaN; `!=` is true.
fn float_condition(op: CmpOp) -> FloatCC {
    match op {
        CmpOp::Eq => FloatCC::Equal,
        CmpOp::Neq => FloatCC::NotEqual,
        CmpOp::Lt => FloatCC::LessThan,
        CmpOp::Gt => FloatCC::GreaterThan,
        CmpOp::LtEq => FloatCC::LessThanOrEqual,
        CmpOp::GtEq => FloatCC::GreaterThanOrEqual,
    }
}

impl Translator<'_> {
    // In the patterns below `d` is the destination, `a` and `b` are the
    // operands and `t` is the IR type.
    pub(super) fn inst(&mut self, inst: &Inst) {
        use Inst::*;
        match inst {
            IAdd(d, a, b, t) => self.binary(*d, *a, *b, *t, |ins, x, y| ins.iadd(x, y)),
            ISub(d, a, b, t) => self.binary(*d, *a, *b, *t, |ins, x, y| ins.isub(x, y)),
            IMul(d, a, b, t) => self.binary(*d, *a, *b, *t, |ins, x, y| ins.imul(x, y)),
            IDiv(d, a, b, t, true) => self.binary(*d, *a, *b, *t, |ins, x, y| ins.sdiv(x, y)),
            IDiv(d, a, b, t, false) => self.binary(*d, *a, *b, *t, |ins, x, y| ins.udiv(x, y)),
            IMod(d, a, b, t, true) => self.binary(*d, *a, *b, *t, |ins, x, y| ins.srem(x, y)),
            IMod(d, a, b, t, false) => self.binary(*d, *a, *b, *t, |ins, x, y| ins.urem(x, y)),
            IShl(d, a, b, t) => self.shift(*d, *a, *b, *t, ShiftKind::Shl),
            IShr(d, a, b, t, true) => self.shift(*d, *a, *b, *t, ShiftKind::Sshr),
            IShr(d, a, b, t, false) => self.shift(*d, *a, *b, *t, ShiftKind::Ushr),
            IBitAnd(d, a, b, t) => self.binary(*d, *a, *b, *t, |ins, x, y| ins.band(x, y)),
            IBitOr(d, a, b, t) => self.binary(*d, *a, *b, *t, |ins, x, y| ins.bor(x, y)),
            IBitXor(d, a, b, t) => self.binary(*d, *a, *b, *t, |ins, x, y| ins.bxor(x, y)),
            INeg(d, a, t) => self.unary(*d, *a, *t, |ins, x| ins.ineg(x)),
            IBitNot(d, a, t) => self.unary(*d, *a, *t, |ins, x| ins.bnot(x)),
            FAdd(d, a, b, t) => self.binary(*d, *a, *b, *t, |ins, x, y| ins.fadd(x, y)),
            FSub(d, a, b, t) => self.binary(*d, *a, *b, *t, |ins, x, y| ins.fsub(x, y)),
            FMul(d, a, b, t) => self.binary(*d, *a, *b, *t, |ins, x, y| ins.fmul(x, y)),
            FDiv(d, a, b, t) => self.binary(*d, *a, *b, *t, |ins, x, y| ins.fdiv(x, y)),
            FNeg(d, a, t) => self.unary(*d, *a, *t, |ins, x| ins.fneg(x)),
            ICmp(d, op, a, b, t, signed) => {
                let condition = int_condition(*op, *signed);
                self.binary(*d, *a, *b, *t, |ins, x, y| ins.icmp(condition, x, y));
            }
            FCmp(d, op, a, b, t) => {
                let condition = float_condition(*op);
                self.binary(*d, *a, *b, *t, |ins, x, y| ins.fcmp(condition, x, y));
            }
            BoolNot(d, a) => self.unary(*d, *a, IRType::I8, |ins, x| ins.bxor_imm_u(x, 1)),
            ConstInt(d, value, t) => {
                let result = self.iconst(self.clif_type(*t), *value);
                self.def_vreg(*d, result);
            }
            ConstFloat(d, value, t) => self.float_constant(*d, *value, *t),
            ConstStringPtr(d, index) => self.data_address(*d, self.codegen.strings[*index]),
            GlobalAddr(d, index) => self.data_address(*d, self.codegen.globals[*index]),
            IntToFloat(d, src, from, to, signed) => {
                self.int_to_float(*d, *src, *from, *to, *signed)
            }
            FloatToInt(d, src, from, to, signed) => {
                self.float_to_int(*d, *src, *from, *to, *signed)
            }
            FloatToFloat(d, src, from, to) => self.float_to_float(*d, *src, *from, *to),
            IntExt(d, src, from, to, signed) => self.int_extend(*d, *src, *from, *to, *signed),
            IntTrunc(d, src, from, to) => self.int_truncate(*d, *src, *from, *to),
            Load(d, addr, t) => self.load(*d, *addr, *t),
            Store(addr, value, t) => self.store(*addr, *value, *t),
            MemCopy { dst, src, size } => self.memory_copy(*dst, *src, *size),
            SlotAddr(d, slot) => self.slot_address(*d, slot.0),
            MemberPtr(d, base, offset) => self.member_pointer(*d, *base, *offset),
            IndexPtr(d, base, index, size) => self.index_pointer(*d, *base, *index, *size),
            Call { dst, func, args } => self.call(*dst, func, args),
            CallIndirect { dst, callee, args } => self.call_indirect(*dst, *callee, args),
            Mov(d, src) => {
                let value = self.use_vreg(*src);
                self.def_vreg(*d, value);
            }
            FuncAddr(d, name) => self.function_address(*d, name),
        }
    }

    // ---- Arithmetic ----

    // dst = op(lhs, rhs), with both operands as `ty`.
    fn binary(
        &mut self,
        dst: VReg,
        lhs: VReg,
        rhs: VReg,
        ty: IRType,
        op: impl FnOnce(FuncInstBuilder<'_, '_>, ir::Value, ir::Value) -> ir::Value,
    ) {
        let ty = self.clif_type(ty);
        let lhs = self.use_vreg_as(lhs, ty);
        let rhs = self.use_vreg_as(rhs, ty);
        let result = op(self.builder.ins(), lhs, rhs);
        self.def_vreg(dst, result);
    }

    // dst = op(operand), with the operand as `ty`.
    fn unary(
        &mut self,
        dst: VReg,
        operand: VReg,
        ty: IRType,
        op: impl FnOnce(FuncInstBuilder<'_, '_>, ir::Value) -> ir::Value,
    ) {
        let ty = self.clif_type(ty);
        let operand = self.use_vreg_as(operand, ty);
        let result = op(self.builder.ins(), operand);
        self.def_vreg(dst, result);
    }

    // x86 semantics on every target: the shift count is masked to 5 bits
    // for operands up to 32 bits and 6 bits for 64-bit operands, so
    // shifting an i8 by 8..31 shifts everything out.
    fn shift(&mut self, dst: VReg, value: VReg, amount: VReg, ty: IRType, kind: ShiftKind) {
        let ty = self.clif_type(ty);
        let value = self.use_vreg_as(value, ty);
        let amount = self.use_vreg(amount);
        let shift = |ins: FuncInstBuilder<'_, '_>, value, amount| match kind {
            ShiftKind::Shl => ins.ishl(value, amount),
            ShiftKind::Ushr => ins.ushr(value, amount),
            ShiftKind::Sshr => ins.sshr(value, amount),
        };
        let result = if ty.bits() >= 32 {
            shift(self.builder.ins(), value, amount)
        } else {
            let wide = match kind {
                ShiftKind::Sshr => self.builder.ins().sextend(types::I32, value),
                _ => self.builder.ins().uextend(types::I32, value),
            };
            let shifted = shift(self.builder.ins(), wide, amount);
            self.builder.ins().ireduce(ty, shifted)
        };
        self.def_vreg(dst, result);
    }

    fn float_constant(&mut self, dst: VReg, value: f64, ty: IRType) {
        let result = if ty == IRType::F32 {
            self.builder.ins().f32const(value as f32)
        } else {
            self.builder.ins().f64const(value)
        };
        self.def_vreg(dst, result);
    }

    // ---- Conversions ----

    fn int_to_float(&mut self, dst: VReg, src: VReg, from: IRType, to: IRType, signed: bool) {
        let from = self.clif_type(from);
        let to = self.clif_type(to);
        let mut value = self.use_vreg_as(src, from);
        // There are no conversions from 8- and 16-bit integers.
        if from.bits() < 32 {
            value = if signed {
                self.builder.ins().sextend(types::I32, value)
            } else {
                self.builder.ins().uextend(types::I32, value)
            };
        }
        let result = if signed {
            self.builder.ins().fcvt_from_sint(to, value)
        } else {
            self.builder.ins().fcvt_from_uint(to, value)
        };
        self.def_vreg(dst, result);
    }

    // Saturating conversions (NaN -> 0) instead of trapping. Narrow results
    // wrap: convert at 32 bits (signed) or 64 bits (unsigned), then
    // truncate.
    fn float_to_int(&mut self, dst: VReg, src: VReg, from: IRType, to: IRType, signed: bool) {
        let from = self.clif_type(from);
        let to = self.clif_type(to);
        let value = self.use_vreg_as(src, from);
        let result = if signed && to.bits() <= 32 {
            let wide = self.builder.ins().fcvt_to_sint_sat(types::I32, value);
            self.coerce(wide, to)
        } else if signed {
            self.builder.ins().fcvt_to_sint_sat(types::I64, value)
        } else if to.bits() <= 32 {
            let wide = self.builder.ins().fcvt_to_sint_sat(types::I64, value);
            self.coerce(wide, to)
        } else {
            self.float_to_u64(value, from)
        };
        self.def_vreg(dst, result);
    }

    // u64: below 2^63 a signed conversion also wraps negative values; above
    // it, convert unsigned.
    fn float_to_u64(&mut self, value: ir::Value, from: ir::Type) -> ir::Value {
        let limit = if from == types::F64 {
            self.builder.ins().f64const(TWO_POW_63)
        } else {
            self.builder.ins().f32const(TWO_POW_63 as f32)
        };
        let big = self
            .builder
            .ins()
            .fcmp(FloatCC::GreaterThanOrEqual, value, limit);
        let as_signed = self.builder.ins().fcvt_to_sint_sat(types::I64, value);
        let as_unsigned = self.builder.ins().fcvt_to_uint_sat(types::I64, value);
        self.builder.ins().select(big, as_unsigned, as_signed)
    }

    fn float_to_float(&mut self, dst: VReg, src: VReg, from: IRType, to: IRType) {
        let from = self.clif_type(from);
        let to = self.clif_type(to);
        let value = self.use_vreg_as(src, from);
        let result = if from == to {
            value
        } else if to == types::F64 {
            self.builder.ins().fpromote(to, value)
        } else {
            self.builder.ins().fdemote(to, value)
        };
        self.def_vreg(dst, result);
    }

    fn int_truncate(&mut self, dst: VReg, src: VReg, from: IRType, to: IRType) {
        let value = self.use_vreg_as(src, self.clif_type(from));
        let result = self.coerce(value, self.clif_type(to));
        self.def_vreg(dst, result);
    }

    fn int_extend(&mut self, dst: VReg, src: VReg, from: IRType, to: IRType, signed: bool) {
        let from = self.clif_type(from);
        let to = self.clif_type(to);
        let value = self.use_vreg_as(src, from);
        let result = if from.bits() >= to.bits() {
            self.coerce(value, to)
        } else if signed {
            self.builder.ins().sextend(to, value)
        } else {
            self.builder.ins().uextend(to, value)
        };
        self.def_vreg(dst, result);
    }

    // ---- Memory ----

    fn data_address(&mut self, dst: VReg, data: cranelift_module::DataId) {
        let global = self.data_ref(data);
        let pointer_type = self.pointer_type();
        let result = self.builder.ins().symbol_value(pointer_type, global);
        self.def_vreg(dst, result);
    }

    // The address of a stack slot; promoted slots have none.
    fn slot_address(&mut self, dst: VReg, slot: u32) {
        if self.promoted.contains_key(&dst.0) {
            return;
        }
        let stack_slot = self.stack_slots[&slot];
        let pointer_type = self.pointer_type();
        let result = self.builder.ins().stack_addr(pointer_type, stack_slot, 0);
        self.def_vreg(dst, result);
    }

    // dst = base + offset
    fn member_pointer(&mut self, dst: VReg, base: VReg, offset: u64) {
        let base = self.use_vreg_as(base, self.pointer_type());
        let result = self.builder.ins().iadd_imm_u(base, offset as i64);
        self.def_vreg(dst, result);
    }

    // dst = base + index * size
    fn index_pointer(&mut self, dst: VReg, base: VReg, index: VReg, size: u64) {
        let base = self.use_vreg_as(base, self.pointer_type());
        let index = self.use_vreg_as(index, self.pointer_type());
        let scaled = self.builder.ins().imul_imm_u(index, size as i64);
        let result = self.builder.ins().iadd(base, scaled);
        self.def_vreg(dst, result);
    }

    fn function_address(&mut self, dst: VReg, name: &str) {
        let func_ref = self.func_ref(self.codegen.functions[name].id);
        let pointer_type = self.pointer_type();
        let result = self.builder.ins().func_addr(pointer_type, func_ref);
        self.def_vreg(dst, result);
    }

    fn load(&mut self, dst: VReg, addr: VReg, ty: IRType) {
        let result = if let Some(variable) = self.promoted.get(&addr.0) {
            self.builder.use_var(*variable)
        } else {
            let ty = self.clif_type(ty);
            let addr = self.use_vreg_as(addr, self.pointer_type());
            self.builder.ins().load(ty, mem_flags(), addr, 0)
        };
        self.def_vreg(dst, result);
    }

    fn store(&mut self, addr: VReg, value: VReg, ty: IRType) {
        let value = self.use_vreg_as(value, self.clif_type(ty));
        if let Some(variable) = self.promoted.get(&addr.0) {
            self.builder.def_var(*variable, value);
        } else {
            let addr = self.use_vreg_as(addr, self.pointer_type());
            self.builder.ins().store(mem_flags(), value, addr, 0);
        }
    }

    // Small copies load everything before storing, larger ones call
    // memmove: source and destination may overlap.
    fn memory_copy(&mut self, dst: VReg, src: VReg, size: u64) {
        if size == 0 {
            return;
        }
        let dst = self.use_vreg_as(dst, self.pointer_type());
        let src = self.use_vreg_as(src, self.pointer_type());
        let config = self.codegen.module.target_config();
        self.builder
            .emit_small_memory_copy(config, dst, src, size, 1, 1, false, mem_flags());
    }
}
