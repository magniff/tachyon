// Expressions: as values, written into memory, or for effect.

use super::layout::{
    POINTER_SIZE, field_offsets, is_scalar, is_void, scalar_ir, type_internal_to_ir,
};
use super::{CmpOp, IRType, Inst, Lowerer, StringConstant, Term, VReg};
use crate::parser::{Expr, ExprKind, FieldInit, LitValue};
use crate::typechecker::{ConstValue, TypeInternal};

// `[e; n]` copies the element with straight-line code up to this length, and
// with a loop above it.
const MAX_UNROLLED_REPEAT: u64 = 8;

impl Lowerer<'_> {
    // The expression's value as a vreg: a scalar, the address of a compound
    // value, or a placeholder for () and `!`.
    pub(super) fn lower_value(&mut self, expr: &Expr, expected: &TypeInternal) -> VReg {
        if self.diverges(expr) {
            self.lower_effect(expr);
            return self.placeholder(expected);
        }
        if is_void(expected) {
            self.lower_effect(expr);
            return self.unit_value();
        }
        match &expr.kind {
            ExprKind::IntLiteral(_)
            | ExprKind::CharLiteral(_)
            | ExprKind::FloatLiteral(_)
            | ExprKind::SuffixedLiteral(..) => self.lower_number(&expr.kind, expected),
            ExprKind::BoolLiteral(b) => self.const_int(*b as i64, IRType::I8),
            ExprKind::UnitLiteral => self.unit_value(),
            ExprKind::StringLiteral(bytes) => {
                let addr = self.alloc_temp(expected);
                self.lower_string_literal(bytes, addr);
                addr
            }
            ExprKind::CStringLiteral(bytes) => {
                let index = self.string_constant(bytes);
                let ptr = self.fresh_vreg();
                self.emit(Inst::ConstStringPtr(ptr, index));
                ptr
            }
            ExprKind::Ident(name) => self.lower_name(name),
            ExprKind::BinOp { op, lhs, rhs } => self.lower_binop(*op, lhs, rhs),
            ExprKind::UnaryOp { op, expr: operand } => self.lower_unaryop(*op, operand, expected),
            ExprKind::Cast { expr: operand, .. } => {
                let from = self.type_of(operand);
                let to = self.type_of(expr);
                let value = self.lower_value(operand, &from);
                self.lower_cast(value, &from, &to)
            }
            ExprKind::Call { callee, args } => self.lower_call(callee, args),
            ExprKind::Index { .. } | ExprKind::Field { .. } | ExprKind::TupleField { .. } => {
                let ty = self.type_of(expr);
                let addr = self.lower_address(expr, &ty);
                if is_scalar(&ty) {
                    self.load(addr, scalar_ir(&ty))
                } else {
                    addr
                }
            }
            ExprKind::If {
                cond,
                then_block,
                else_block,
            } => self.lower_if_value(cond, then_block, else_block.as_ref(), expected),
            ExprKind::Block(block) => self.lower_block_value(block, expected),
            ExprKind::Loop { label, body } => self.lower_loop(label, body, expected),
            ExprKind::Tuple(_)
            | ExprKind::Array(_)
            | ExprKind::ArrayRepeat(_, _)
            | ExprKind::StructConstructor { .. } => {
                let addr = self.alloc_temp(expected);
                self.lower_into(expr, addr, expected);
                addr
            }
            // Unit-typed or diverging: handled above.
            ExprKind::While { .. }
            | ExprKind::For { .. }
            | ExprKind::Assign { .. }
            | ExprKind::Return(_)
            | ExprKind::Break { .. }
            | ExprKind::Continue { .. }
            | ExprKind::Range { .. }
            | ExprKind::Error => panic!("ICE: unexpected value expression {:?}", expr.span),
        }
    }

    // A numeric literal as a constant of the expected type.
    fn lower_number(&mut self, literal: &ExprKind, expected: &TypeInternal) -> VReg {
        let (int, float) = match *literal {
            ExprKind::IntLiteral(v) | ExprKind::SuffixedLiteral(LitValue::Int(v), _) => {
                (v as i64, v as f64)
            }
            ExprKind::CharLiteral(c) => (c as i64, c as f64),
            ExprKind::FloatLiteral(f) | ExprKind::SuffixedLiteral(LitValue::Float(f), _) => {
                (*f as i64, *f)
            }
            _ => unreachable!("not a numeric literal"),
        };
        let ir = type_internal_to_ir(expected).unwrap_or(IRType::I64);
        if ir.is_float() {
            let vreg = self.fresh_vreg();
            self.emit(Inst::ConstFloat(vreg, float, ir));
            vreg
        } else {
            self.const_int(int, ir)
        }
    }

    // A variable or static (its value), a constant, or a function (its
    // address).
    fn lower_name(&mut self, name: &str) -> VReg {
        if let Some((addr, ty)) = self.variable_place(name) {
            return if is_scalar(&ty) {
                self.load(addr, scalar_ir(&ty))
            } else {
                addr
            };
        }
        if let Some(info) = self.checked.consts.get(name) {
            let ir = scalar_ir(&info.ty);
            return match info.value {
                ConstValue::Int(i) => self.const_int(i as i64, ir),
                ConstValue::Float(f) => {
                    let vreg = self.fresh_vreg();
                    self.emit(Inst::ConstFloat(vreg, f, ir));
                    vreg
                }
                ConstValue::Bool(b) => self.const_int(b as i64, ir),
                ConstValue::Aggregate(_) => panic!("ICE: constants are scalars"),
            };
        }
        let addr = self.fresh_vreg();
        self.emit(Inst::FuncAddr(addr, name.to_string()));
        addr
    }

    // ---- Into memory ----

    // Writes the expression's value, of type `ty`, to memory at `dst`.
    pub(super) fn lower_into(&mut self, expr: &Expr, dst: VReg, ty: &TypeInternal) {
        if self.diverges(expr) {
            self.lower_effect(expr);
            return;
        }
        match &expr.kind {
            ExprKind::StringLiteral(bytes) => self.lower_string_literal(bytes, dst),
            ExprKind::Tuple(elems) => self.lower_tuple_into(elems, dst, ty),
            ExprKind::Array(elems) => {
                let TypeInternal::Array(elem_ty, _) = ty else {
                    panic!("ICE: array literal of type {}", ty)
                };
                let elem_size = self.size_of(elem_ty);
                for (index, elem) in elems.iter().enumerate() {
                    let elem_addr = self.member_ptr(dst, index as u64 * elem_size);
                    self.store_expr(elem, elem_addr, elem_ty);
                }
            }
            ExprKind::ArrayRepeat(value, _) => self.lower_array_repeat_into(value, dst, ty),
            ExprKind::StructConstructor { name, fields } => {
                self.lower_struct_into(&name.0, fields, dst)
            }
            ExprKind::Ident(name) if self.is_variable(name) => {
                let (src, _) = self.variable_place(name).expect("checked by is_variable");
                self.copy_value(dst, src, ty);
            }
            ExprKind::Block(block) => self.lower_block_into(block, dst, ty),
            ExprKind::If {
                cond,
                then_block,
                else_block,
            } => self.lower_if_into(cond, then_block, else_block.as_ref(), dst, ty),
            ExprKind::Field { .. } | ExprKind::TupleField { .. } | ExprKind::Index { .. } => {
                let src = self.lower_address(expr, ty);
                self.copy_value(dst, src, ty);
            }
            _ => {
                // Calls return the sret slot and other compound operands the
                // address of the value, which is copied into place.
                let value = self.lower_value(expr, ty);
                if is_scalar(ty) {
                    self.emit(Inst::Store(dst, value, scalar_ir(ty)));
                } else if !is_void(ty) {
                    let size = self.size_of(ty);
                    self.emit(Inst::MemCopy {
                        dst,
                        src: value,
                        size,
                    });
                }
            }
        }
    }

    fn lower_tuple_into(&mut self, elems: &[Expr], dst: VReg, ty: &TypeInternal) {
        let elem_types = match ty {
            TypeInternal::Tuple(types) => types.clone(),
            _ => elems.iter().map(|elem| self.type_of(elem)).collect(),
        };
        let offsets = field_offsets(&elem_types, &self.checked.structs);
        for ((elem, elem_ty), (offset, _)) in elems.iter().zip(&elem_types).zip(&offsets) {
            let elem_addr = self.member_ptr(dst, *offset);
            self.store_expr(elem, elem_addr, elem_ty);
        }
    }

    // Fields are stored in the order they are written.
    fn lower_struct_into(&mut self, struct_name: &str, fields: &[FieldInit], dst: VReg) {
        let info = self.checked.structs[struct_name].clone();
        let field_types: Vec<TypeInternal> = info.fields.iter().map(|(_, ty)| ty.clone()).collect();
        let offsets = field_offsets(&field_types, &self.checked.structs);
        for field in fields {
            let index = info
                .fields
                .iter()
                .position(|(name, _)| *name == field.name.0)
                .expect("ICE: the checker rejects unknown fields");
            let field_addr = self.member_ptr(dst, offsets[index].0);
            self.store_expr(&field.value, field_addr, &field_types[index]);
        }
    }

    // `[value; n]`: the element is evaluated once into the first slot, then
    // copied into the others.
    fn lower_array_repeat_into(&mut self, value: &Expr, dst: VReg, ty: &TypeInternal) {
        let TypeInternal::Array(elem_ty, len) = ty else {
            panic!("ICE: array literal of type {}", ty)
        };
        if *len == 0 {
            return;
        }
        let elem_size = self.size_of(elem_ty);
        let first = self.member_ptr(dst, 0);
        self.store_expr(value, first, elem_ty);
        if *len <= MAX_UNROLLED_REPEAT {
            for index in 1..*len {
                let elem_addr = self.member_ptr(dst, index * elem_size);
                self.copy_value(elem_addr, first, elem_ty);
            }
        } else {
            self.lower_copy_loop(dst, first, elem_ty, elem_size, *len);
        }
    }

    // for (i = 1; i < len; i++) dst[i] = *first
    fn lower_copy_loop(
        &mut self,
        dst: VReg,
        first: VReg,
        elem_ty: &TypeInternal,
        elem_size: u64,
        len: u64,
    ) {
        let counter = self.alloc_slot(8, 8);
        let header = self.fresh_block();
        let body = self.fresh_block();
        let exit = self.fresh_block();
        let one = self.const_int(1, IRType::I64);
        let counter_addr = self.slot_addr(counter);
        self.emit(Inst::Store(counter_addr, one, IRType::I64));
        self.finish_block(Term::Jump(header));

        self.start_block(header);
        let counter_addr = self.slot_addr(counter);
        let index = self.load(counter_addr, IRType::I64);
        let limit = self.const_int(len as i64, IRType::I64);
        let more = self.fresh_vreg();
        self.emit(Inst::ICmp(
            more,
            CmpOp::Lt,
            index,
            limit,
            IRType::I64,
            false,
        ));
        self.finish_block(Term::CondBr {
            cond: more,
            then_bb: body,
            else_bb: exit,
        });

        self.start_block(body);
        let elem_addr = self.fresh_vreg();
        self.emit(Inst::IndexPtr(elem_addr, dst, index, elem_size));
        self.copy_value(elem_addr, first, elem_ty);
        let step = self.const_int(1, IRType::I64);
        let next = self.fresh_vreg();
        self.emit(Inst::IAdd(next, index, step, IRType::I64));
        let counter_addr = self.slot_addr(counter);
        self.emit(Inst::Store(counter_addr, next, IRType::I64));
        self.finish_block(Term::Jump(header));

        self.start_block(exit);
    }

    // ---- For effect ----

    // Lowers an expression for its side effects only.
    pub(super) fn lower_effect(&mut self, expr: &Expr) {
        match &expr.kind {
            ExprKind::Call { callee, args } => {
                self.lower_call(callee, args);
            }
            ExprKind::Block(block) => self.lower_block_effect(block),
            ExprKind::If {
                cond,
                then_block,
                else_block,
            } => {
                self.lower_if_value(cond, then_block, else_block.as_ref(), &TypeInternal::Unit);
            }
            ExprKind::Loop { label, body } => {
                let ty = self.type_of(expr);
                self.lower_loop(label, body, &ty);
            }
            ExprKind::While { label, cond, body } => self.lower_while(label, cond, body),
            ExprKind::For {
                label,
                pattern,
                iter,
                body,
            } => self.lower_for(label, pattern, iter, body),
            ExprKind::Assign { op, target, value } => self.lower_assign(*op, target, value),
            ExprKind::Return(value) => self.lower_return(value.as_deref()),
            ExprKind::Break { label, value } => self.lower_break(label, value.as_deref()),
            ExprKind::Continue { label } => self.lower_continue(label),
            ExprKind::Range { .. } | ExprKind::Error => {
                panic!("ICE: unexpected expression {:?}", expr.span)
            }
            _ => {
                let ty = self.type_of(expr);
                if !is_void(&ty) {
                    self.lower_value(expr, &ty);
                } else if self.diverges(expr) {
                    // e.g. a cast of `return`: lower the operand for effect
                    if let ExprKind::Cast { expr: operand, .. }
                    | ExprKind::UnaryOp { expr: operand, .. } = &expr.kind
                    {
                        self.lower_effect(operand);
                    }
                }
            }
        }
    }

    // ---- Strings ----

    // Adds `bytes` to the program's string constants; returns its index.
    fn string_constant(&mut self, bytes: &[u8]) -> usize {
        let index = self.strings.len();
        self.strings.push(StringConstant {
            label: format!("__str{}", index),
            bytes: bytes.to_vec(),
        });
        index
    }

    // A string literal: a (pointer, length) pair written to `dst`.
    fn lower_string_literal(&mut self, bytes: &[u8], dst: VReg) {
        let index = self.string_constant(bytes);
        let ptr = self.fresh_vreg();
        self.emit(Inst::ConstStringPtr(ptr, index));
        let ptr_field = self.member_ptr(dst, 0);
        self.emit(Inst::Store(ptr_field, ptr, IRType::Ptr));
        let len = self.const_int(bytes.len() as i64, IRType::I64);
        let len_field = self.member_ptr(dst, POINTER_SIZE);
        self.emit(Inst::Store(len_field, len, IRType::I64));
    }
}
