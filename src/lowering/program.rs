// Top level: statics, extern declarations and functions.

use std::collections::HashMap;

use super::layout::{
    field_offsets, is_compound, is_scalar, layout_of, scalar_ir, type_internal_to_ir,
};
use super::{GlobalData, IRFunction, IRType, Inst, IrProgram, Lowerer, Term, VReg};
use crate::parser::{ExternDecl, FunctionDecl, Item, Program, StaticDecl};
use crate::typechecker::{ConstValue, TypeInternal};

impl Lowerer<'_> {
    pub(super) fn lower_program(&mut self, program: &Program) -> IrProgram {
        // Statics first, so functions can refer to them.
        for item in &program.items {
            if let Item::Static(decl) = item {
                self.lower_static(decl);
            }
        }
        let mut functions = Vec::new();
        for item in &program.items {
            match item {
                Item::Function(decl) => functions.push(self.lower_function(decl)),
                Item::Extern(decl) => functions.push(self.lower_extern(decl)),
                _ => {}
            }
        }
        IrProgram {
            functions,
            strings: std::mem::take(&mut self.strings),
            globals: std::mem::take(&mut self.globals),
        }
    }

    fn lower_static(&mut self, decl: &StaticDecl) {
        let info = &self.checked.statics[&decl.name.0];
        let layout = layout_of(&info.ty, &self.checked.structs);
        let mut bytes = vec![0u8; layout.size as usize];
        self.write_const(&info.value, &info.ty, &mut bytes, 0);
        self.global_index
            .insert(decl.name.0.clone(), self.globals.len());
        self.globals.push(GlobalData {
            name: decl.name.0.clone(),
            bytes,
            align: layout.align,
            mutable: info.mutable,
        });
    }

    // Stores a constant's bytes (little-endian) at `offset` of `out`.
    fn write_const(&self, value: &ConstValue, ty: &TypeInternal, out: &mut [u8], offset: usize) {
        let size = self.size_of(ty) as usize;
        match value {
            ConstValue::Int(v) => {
                out[offset..offset + size].copy_from_slice(&(*v as u128).to_le_bytes()[..size]);
            }
            ConstValue::Float(f) if *ty == TypeInternal::F32 => {
                out[offset..offset + 4].copy_from_slice(&(*f as f32).to_le_bytes());
            }
            ConstValue::Float(f) => out[offset..offset + 8].copy_from_slice(&f.to_le_bytes()),
            ConstValue::Bool(b) => out[offset] = *b as u8,
            ConstValue::Aggregate(values) => {
                let elem_types = self.element_types(ty);
                let offsets = field_offsets(&elem_types, &self.checked.structs);
                for ((value, elem_ty), (elem_offset, _)) in
                    values.iter().zip(&elem_types).zip(&offsets)
                {
                    self.write_const(value, elem_ty, out, offset + *elem_offset as usize);
                }
            }
        }
    }

    // The types of an aggregate's elements, in memory order.
    fn element_types(&self, ty: &TypeInternal) -> Vec<TypeInternal> {
        match ty {
            TypeInternal::Array(elem, len) => vec![(**elem).clone(); *len as usize],
            TypeInternal::Tuple(elems) => elems.clone(),
            TypeInternal::Struct(name) => self.checked.structs[name]
                .fields
                .iter()
                .map(|(_, ty)| ty.clone())
                .collect(),
            _ => Vec::new(),
        }
    }

    fn lower_extern(&mut self, decl: &ExternDecl) -> IRFunction {
        let signature = &self.checked.functions[&decl.name.0];
        let params = signature
            .params
            .iter()
            .map(|(_, ty)| (VReg(0), type_internal_to_ir(ty).unwrap_or(IRType::Ptr)))
            .collect();
        IRFunction {
            name: decl.name.0.clone(),
            params,
            return_type: type_internal_to_ir(&signature.return_ty),
            slots: vec![],
            blocks: vec![],
            vreg_count: 0,
            is_extern: true,
            is_variadic: signature.is_variadic,
        }
    }

    fn lower_function(&mut self, decl: &FunctionDecl) -> IRFunction {
        let signature = self.checked.functions[&decl.name.0].clone();
        self.reset_function_state(signature.return_ty.clone());
        let entry = self.fresh_block();
        self.start_block(entry);
        let params = self.lower_params(&signature.params);

        self.push_scope();
        let diverged = self.lower_stmts(&decl.body);
        let term = match &decl.body.expr {
            Some(tail) if !diverged => self.lower_return_value(tail),
            _ => Term::Ret(None),
        };
        self.finish_block(term);
        self.pop_scope();

        IRFunction {
            name: decl.name.0.clone(),
            params,
            return_type: type_internal_to_ir(&signature.return_ty),
            slots: std::mem::take(&mut self.slots),
            blocks: std::mem::take(&mut self.finished_blocks),
            vreg_count: self.next_vreg,
            is_extern: false,
            is_variadic: false,
        }
    }

    fn reset_function_state(&mut self, return_ty: TypeInternal) {
        self.finished_blocks.clear();
        self.current_insts.clear();
        self.slots.clear();
        self.next_vreg = 0;
        self.next_block = 0;
        self.scopes = vec![HashMap::new()];
        self.return_ty = return_ty;
        self.sret = None;
        self.loops.clear();
    }

    // The function's IR parameters. Compound results are written through a
    // hidden first argument pointing at a slot in the caller's frame (SysV
    // "sret"). Parameters live in slots, like every local; compound ones
    // arrive as pointers and are copied.
    fn lower_params(&mut self, params: &[(String, TypeInternal)]) -> Vec<(VReg, IRType)> {
        let mut ir_params = Vec::new();
        if is_compound(&self.return_ty) {
            let sret = self.fresh_vreg();
            ir_params.push((sret, IRType::Ptr));
            self.sret = Some(sret);
        }
        for (name, ty) in params {
            let addr = self.alloc_temp(ty);
            let value = self.fresh_vreg();
            if is_scalar(ty) {
                let ir = scalar_ir(ty);
                ir_params.push((value, ir));
                self.emit(Inst::Store(addr, value, ir));
            } else {
                ir_params.push((value, IRType::Ptr));
                let size = self.size_of(ty);
                self.emit(Inst::MemCopy {
                    dst: addr,
                    src: value,
                    size,
                });
            }
            if name != "_" {
                self.define(name.clone(), addr, ty.clone());
            }
        }
        ir_params
    }
}
