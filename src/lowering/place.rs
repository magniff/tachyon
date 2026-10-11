// Addresses of places, and moving values between memory locations.

use super::layout::{field_offsets, is_scalar, is_void, scalar_ir};
use super::{IRType, Inst, Lowerer, VReg};
use crate::parser::{Expr, ExprKind, UnaryOp};
use crate::typechecker::TypeInternal;

impl Lowerer<'_> {
    // Address of `expr`. Places (variables, statics, `*p`, `p[i]`, fields
    // and elements of places) yield their own address, so `&p.x` and `&a[i]`
    // alias the original; any other expression is materialized in a fresh
    // slot.
    pub(super) fn lower_address(&mut self, expr: &Expr, ty: &TypeInternal) -> VReg {
        match &expr.kind {
            ExprKind::Ident(name) => {
                if let Some((addr, _)) = self.variable_place(name) {
                    return addr;
                }
            }
            ExprKind::UnaryOp {
                op: UnaryOp::Deref,
                expr: pointer,
            } => {
                let pointer_ty = self.type_of(pointer);
                return self.lower_value(pointer, &pointer_ty);
            }
            ExprKind::Field { expr: base, name } => {
                let base_ty = self.type_of(base);
                let offset = self.struct_field_offset(&base_ty, &name.0);
                let base_addr = self.lower_address(base, &base_ty);
                return self.member_ptr(base_addr, offset);
            }
            ExprKind::TupleField { expr: base, index } => {
                let base_ty = self.type_of(base);
                let offset = self.tuple_field_offset(&base_ty, index.0 as usize);
                let base_addr = self.lower_address(base, &base_ty);
                return self.member_ptr(base_addr, offset);
            }
            ExprKind::Index { expr: base, index } => {
                return self.lower_element_address(base, index, expr);
            }
            _ => {}
        }
        let addr = self.alloc_temp(ty);
        self.lower_into(expr, addr, ty);
        addr
    }

    // Address of `base[index]`: an array element, or `p[i]` from the
    // pointer's value.
    fn lower_element_address(&mut self, base: &Expr, index: &Expr, element: &Expr) -> VReg {
        let base_ty = self.type_of(base);
        let base_addr = match &base_ty {
            TypeInternal::Pointer(_) => self.lower_value(base, &base_ty),
            _ => self.lower_address(base, &base_ty),
        };
        let elem_ty = self.type_of(element);
        let index = self.lower_index(index);
        let elem_size = self.size_of(&elem_ty);
        let addr = self.fresh_vreg();
        self.emit(Inst::IndexPtr(addr, base_addr, index, elem_size));
        addr
    }

    // An index widened to 64 bits by its own signedness: IndexPtr adds the
    // full register, and narrow values may carry garbage in the high bits.
    fn lower_index(&mut self, index: &Expr) -> VReg {
        let index_ty = self.type_of(index);
        let value = self.lower_value(index, &index_ty);
        let ir = scalar_ir(&index_ty);
        if ir.size() >= IRType::I64.size() {
            return value;
        }
        let widened = self.fresh_vreg();
        self.emit(Inst::IntExt(
            widened,
            value,
            ir,
            IRType::I64,
            index_ty.is_signed(),
        ));
        widened
    }

    fn struct_field_offset(&self, ty: &TypeInternal, field: &str) -> u64 {
        let TypeInternal::Struct(name) = ty else {
            panic!("ICE: field access on '{}'", ty)
        };
        let info = &self.checked.structs[name];
        let field_types: Vec<TypeInternal> = info.fields.iter().map(|(_, ty)| ty.clone()).collect();
        let index = info
            .fields
            .iter()
            .position(|(name, _)| name == field)
            .expect("ICE: the checker rejects unknown fields");
        field_offsets(&field_types, &self.checked.structs)[index].0
    }

    fn tuple_field_offset(&self, ty: &TypeInternal, index: usize) -> u64 {
        let TypeInternal::Tuple(elems) = ty else {
            panic!("ICE: tuple index on '{}'", ty)
        };
        field_offsets(elems, &self.checked.structs)[index].0
    }

    // Stores the value of `expr`, of type `ty`, at `addr`.
    pub(super) fn store_expr(&mut self, expr: &Expr, addr: VReg, ty: &TypeInternal) {
        if is_scalar(ty) {
            let value = self.lower_value(expr, ty);
            self.emit(Inst::Store(addr, value, scalar_ir(ty)));
        } else {
            self.lower_into(expr, addr, ty);
        }
    }

    // Copies a value of type `ty` from `src` to `dst`.
    pub(super) fn copy_value(&mut self, dst: VReg, src: VReg, ty: &TypeInternal) {
        if is_scalar(ty) {
            let ir = scalar_ir(ty);
            let value = self.load(src, ir);
            self.emit(Inst::Store(dst, value, ir));
        } else if !is_void(ty) {
            let size = self.size_of(ty);
            self.emit(Inst::MemCopy { dst, src, size });
        }
    }
}
