// Calls: direct, indirect, and C variadic (see the module comment for the
// two variadic conventions).

use cranelift_codegen::ir::{
    self, AbiParam, ExtFuncData, ExternalName, InstBuilder, Signature, UserExternalName, types,
};

use super::codegen::DeclaredFunction;
use super::translate::Translator;
use crate::backend::Target;
use crate::lowering::{IRType, VReg};

// Argument registers of each class in the Apple arm64 convention.
const ARM64_ARGUMENT_REGISTERS: usize = 8;

impl Translator<'_> {
    pub(super) fn call(
        &mut self,
        dst: Option<(VReg, IRType)>,
        func: &str,
        args: &[(VReg, IRType)],
    ) {
        let callee = self.codegen.functions[func].clone();
        if callee.is_extern && !callee.is_variadic && args.len() != callee.params.len() {
            // The lowering passes compound results through a hidden pointer,
            // which C functions do not take.
            self.unsupported = Some(format!(
                "calling C function '{}' with a struct result is not supported yet",
                func
            ));
            self.unreachable_result(dst);
            return;
        }
        let call = if callee.is_variadic {
            self.variadic_call(func, &callee, args)
        } else {
            let func_ref = self.func_ref(callee.id);
            let mut values = Vec::new();
            for (index, (vreg, ty)) in args.iter().enumerate() {
                let ty = self.clif_type(callee.params.get(index).copied().unwrap_or(*ty));
                values.push(self.use_vreg_as(*vreg, ty));
            }
            self.builder.ins().call(func_ref, &values)
        };
        if let Some((dst, ty)) = dst {
            let result = match self.builder.inst_results(call).first() {
                Some(result) => *result,
                None => {
                    let ty = self.clif_type(ty);
                    self.zero(ty)
                }
            };
            self.def_vreg(dst, result);
        }
    }

    // Traps instead of a call that cannot be made, and continues in a block
    // nothing reaches, where `dst` holds zero.
    fn unreachable_result(&mut self, dst: Option<(VReg, IRType)>) {
        self.trap();
        let dead = self.builder.create_block();
        self.builder.switch_to_block(dead);
        if let Some((dst, ty)) = dst {
            let ty = self.clif_type(ty);
            let zero = self.zero(ty);
            self.def_vreg(dst, zero);
        }
    }

    pub(super) fn call_indirect(
        &mut self,
        dst: Option<(VReg, IRType)>,
        callee: VReg,
        args: &[(VReg, IRType)],
    ) {
        let mut signature = Signature::new(self.codegen.call_conv);
        let mut values = Vec::new();
        for (vreg, ty) in args {
            let ty = self.clif_type(*ty);
            signature.params.push(AbiParam::new(ty));
            values.push(self.use_vreg_as(*vreg, ty));
        }
        if let Some((_, ty)) = dst {
            signature.returns.push(AbiParam::new(self.clif_type(ty)));
        }
        let signature = self.builder.import_signature(signature);
        let target = self.use_vreg_as(callee, self.pointer_type());
        let call = self.builder.ins().call_indirect(signature, target, &values);
        if let Some((dst, _)) = dst {
            let result = self.builder.inst_results(call)[0];
            self.def_vreg(dst, result);
        }
    }

    // A call with a signature built for this call site: the fixed
    // parameters, padding on Apple arm64, then the variadic arguments.
    fn variadic_call(
        &mut self,
        func: &str,
        callee: &DeclaredFunction,
        args: &[(VReg, IRType)],
    ) -> ir::Inst {
        let mut signature = Signature::new(self.codegen.call_conv);
        let mut values = Vec::new();
        let (fixed, variadic) = args.split_at(callee.params.len());
        for ((vreg, _), ty) in fixed.iter().zip(&callee.params) {
            let clif_ty = self.clif_type(*ty);
            signature.params.push(self.codegen.abi_param(*ty, true));
            values.push(self.use_vreg_as(*vreg, clif_ty));
        }
        if self.codegen.target == Target::MacosAarch64 && !variadic.is_empty() {
            self.pad_argument_registers(&callee.params, &mut signature, &mut values);
        }
        for (vreg, ty) in variadic {
            let (param_ty, value) = self.variadic_arg(*vreg, *ty);
            signature.params.push(AbiParam::new(param_ty));
            values.push(value);
        }
        if let Some(ty) = callee.ret {
            signature.returns.push(self.codegen.abi_param(ty, true));
        }
        let func_ref = self.import_variadic_target(func, callee, signature);
        self.builder.ins().call(func_ref, &values)
    }

    // Apple arm64 passes variadic arguments on the stack: fill the integer
    // and vector argument registers the fixed parameters leave free with
    // dummy arguments.
    fn pad_argument_registers(
        &mut self,
        fixed_params: &[IRType],
        signature: &mut Signature,
        values: &mut Vec<ir::Value>,
    ) {
        let ints = fixed_params.iter().filter(|ty| !ty.is_float()).count();
        let floats = fixed_params.len() - ints;
        for _ in ints.min(ARM64_ARGUMENT_REGISTERS)..ARM64_ARGUMENT_REGISTERS {
            signature.params.push(AbiParam::new(types::I64));
            values.push(self.builder.ins().iconst(types::I64, 0));
        }
        for _ in floats.min(ARM64_ARGUMENT_REGISTERS)..ARM64_ARGUMENT_REGISTERS {
            signature.params.push(AbiParam::new(types::F64));
            values.push(self.builder.ins().f64const(0.0));
        }
    }

    // A variadic argument widened to 64 bits (f32 to f64), so that every one
    // fills a full stack slot. Returns its parameter type and value.
    fn variadic_arg(&mut self, vreg: VReg, ty: IRType) -> (ir::Type, ir::Value) {
        let value = self.use_vreg(vreg);
        if !ty.is_float() {
            return (types::I64, self.coerce(value, types::I64));
        }
        let value = self.coerce(value, self.clif_type(ty));
        let value = if ty == IRType::F32 {
            self.builder.ins().fpromote(types::F64, value)
        } else {
            value
        };
        (types::F64, value)
    }

    // The callee with this call site's signature: the x86-64 thunk if there
    // is one, otherwise the function itself.
    fn import_variadic_target(
        &mut self,
        func: &str,
        callee: &DeclaredFunction,
        signature: Signature,
    ) -> ir::FuncRef {
        let (target, colocated) = match self.codegen.variadic_thunks.get(func) {
            Some(thunk) => (*thunk, true),
            None => (callee.id, false),
        };
        let signature = self.builder.import_signature(signature);
        let name = self
            .builder
            .func
            .declare_imported_user_function(UserExternalName {
                namespace: 0,
                index: target.as_u32(),
            });
        self.builder.import_function(ExtFuncData {
            name: ExternalName::user(name),
            signature,
            colocated,
            patchable: false,
        })
    }
}
