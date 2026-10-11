// Calls, direct and through function pointers.

use super::layout::{is_compound, is_scalar, scalar_ir, type_internal_to_ir};
use super::{IRType, Inst, Lowerer, VReg};
use crate::parser::{Expr, ExprKind};
use crate::typechecker::{FnSig, TypeInternal};

// What a call needs to know about the function it calls.
struct CalleeInfo<'a> {
    // The function a call names directly; None for an indirect call.
    direct: Option<&'a FnSig>,
    param_types: Vec<TypeInternal>,
    return_ty: TypeInternal,
    is_variadic: bool,
}

// C's default argument promotions for variadic arguments: f32 -> f64,
// small integers -> int.
fn promote_variadic(ty: &TypeInternal) -> TypeInternal {
    match ty {
        TypeInternal::F32 => TypeInternal::F64,
        TypeInternal::I8 | TypeInternal::I16 => TypeInternal::I32,
        TypeInternal::U8 | TypeInternal::U16 | TypeInternal::Bool => TypeInternal::U32,
        other => other.clone(),
    }
}

impl<'a> Lowerer<'a> {
    fn callee_info(&self, callee: &Expr) -> CalleeInfo<'a> {
        // A local of the same name shadows the function and makes the call
        // indirect.
        let direct = match &callee.kind {
            ExprKind::Ident(name) if self.lookup_local(name).is_none() => {
                self.checked.functions.get(name)
            }
            _ => None,
        };
        if let Some(sig) = direct {
            return CalleeInfo {
                direct,
                param_types: sig.param_types(),
                return_ty: sig.return_ty.clone(),
                is_variadic: sig.is_variadic,
            };
        }
        let TypeInternal::Fn { params, result } = self.type_of(callee) else {
            panic!("ICE: the checker only accepts calls of functions")
        };
        CalleeInfo {
            direct: None,
            param_types: params,
            return_ty: *result,
            is_variadic: false,
        }
    }

    // A call; returns the scalar result, the address of a compound result,
    // or a placeholder for () and `!`.
    pub(super) fn lower_call(&mut self, callee: &Expr, args: &[Expr]) -> VReg {
        let info = self.callee_info(callee);
        let mut ir_args = Vec::new();
        // A compound result goes to a slot in this frame, passed first.
        let sret = if is_compound(&info.return_ty) {
            let addr = self.alloc_temp(&info.return_ty);
            ir_args.push((addr, IRType::Ptr));
            Some(addr)
        } else {
            None
        };
        for (index, arg) in args.iter().enumerate() {
            let ir_arg = match info.param_types.get(index) {
                Some(param_ty) => self.lower_arg(arg, param_ty),
                None if info.is_variadic => self.lower_variadic_arg(arg),
                None => {
                    let ty = self.type_of(arg);
                    self.lower_arg(arg, &ty)
                }
            };
            ir_args.push(ir_arg);
        }

        let dst = type_internal_to_ir(&info.return_ty).map(|ir| (self.fresh_vreg(), ir));
        match info.direct {
            Some(sig) => self.emit(Inst::Call {
                dst,
                func: sig.name.clone(),
                args: ir_args,
            }),
            None => {
                let callee_ty = self.type_of(callee);
                let callee = self.lower_value(callee, &callee_ty);
                self.emit(Inst::CallIndirect {
                    dst,
                    callee,
                    args: ir_args,
                });
            }
        }
        match (sret, dst) {
            (Some(addr), _) => addr,
            (None, Some((result, _))) => result,
            (None, None) => self.unit_value(),
        }
    }

    // A scalar argument by value, a compound one by address.
    fn lower_arg(&mut self, arg: &Expr, ty: &TypeInternal) -> (VReg, IRType) {
        if is_scalar(ty) {
            (self.lower_value(arg, ty), scalar_ir(ty))
        } else {
            (self.lower_address(arg, ty), IRType::Ptr)
        }
    }

    // An argument past a variadic function's parameters, promoted as C
    // expects.
    fn lower_variadic_arg(&mut self, arg: &Expr) -> (VReg, IRType) {
        let ty = self.type_of(arg);
        if !is_scalar(&ty) {
            return self.lower_arg(arg, &ty);
        }
        let value = self.lower_value(arg, &ty);
        let promoted = promote_variadic(&ty);
        let value = self.lower_cast(value, &ty, &promoted);
        (value, scalar_ir(&promoted))
    }
}
