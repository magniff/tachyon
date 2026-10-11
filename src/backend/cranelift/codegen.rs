// The object module: declares every function and data object, translates
// and compiles the functions, and emits the object file.

use std::collections::HashMap;

use cranelift_codegen::Context;
use cranelift_codegen::control::ControlPlane;
use cranelift_codegen::ir::{AbiParam, Signature, Type, types};
use cranelift_codegen::isa::CallConv;
use cranelift_module::{
    DataDescription, DataId, FuncId, Linkage, Module, ModuleError, ModuleReloc, ModuleRelocTarget,
    default_libcall_names,
};
use cranelift_object::{ObjectBuilder, ObjectModule};

use super::translate::Translator;
use super::{error, make_isa};
use crate::backend::{GeneratorError, Options, Target};
use crate::lowering::{IRFunction, IRType, Inst, IrProgram, Term};

// The x86-64 variadic thunk, `mov al, 8; jmp <callee>`: `al` is an upper
// bound on the vector registers used, and a jump leaves the arguments and
// the stack untouched.
const VARIADIC_THUNK: [u8; 7] = [0xb0, 0x08, 0xe9, 0, 0, 0, 0];
// Where the jump's 32-bit displacement starts in the thunk.
const VARIADIC_THUNK_JUMP_OFFSET: u32 = 3;
const VARIADIC_THUNK_ALIGN: u64 = 16;

#[derive(Clone)]
pub(super) struct DeclaredFunction {
    pub id: FuncId,
    // Declared parameter and return types (sret pointer included).
    pub params: Vec<IRType>,
    pub ret: Option<IRType>,
    pub is_extern: bool,
    pub is_variadic: bool,
}

pub(super) struct Codegen {
    pub module: ObjectModule,
    pub target: Target,
    pub pointer_type: Type,
    pub call_conv: CallConv,
    pub functions: HashMap<String, DeclaredFunction>,
    pub strings: Vec<DataId>,
    pub globals: Vec<DataId>,
    // x86-64 only: variadic thunks for variadic externs, by callee name.
    pub variadic_thunks: HashMap<String, FuncId>,
}

fn local_symbol(name: &str) -> String {
    if name == "main" {
        name.to_string()
    } else {
        format!("tachyon.{}", name)
    }
}

// Return type as seen by callers: compound results come back as the sret
// pointer even though the IR records no scalar return type for them.
fn caller_return_type(function: &IRFunction) -> Option<IRType> {
    if function.return_type.is_some() || function.is_extern {
        return function.return_type;
    }
    function
        .blocks
        .iter()
        .find_map(|block| match block.terminator {
            Term::Ret(Some((_, ty))) => Some(ty),
            _ => None,
        })
}

pub(super) fn clif_type(ty: IRType, pointer_type: Type) -> Type {
    match ty {
        IRType::I8 => types::I8,
        IRType::I16 => types::I16,
        IRType::I32 => types::I32,
        IRType::I64 => types::I64,
        IRType::F32 => types::F32,
        IRType::F64 => types::F64,
        IRType::Ptr => pointer_type,
    }
}

fn module_error(e: ModuleError) -> GeneratorError {
    error(format!("cranelift: {:?}", e))
}

impl Codegen {
    pub fn new(program: &IrProgram, options: &Options) -> Result<Codegen, GeneratorError> {
        let isa = make_isa(options)?;
        let pointer_type = isa.pointer_type();
        let call_conv = isa.default_call_conv();
        let builder = ObjectBuilder::new(isa, "tachyon", default_libcall_names())
            .map_err(|e| error(format!("cranelift: {}", e)))?;
        let mut codegen = Codegen {
            module: ObjectModule::new(builder),
            target: options.target,
            pointer_type,
            call_conv,
            functions: HashMap::new(),
            strings: Vec::new(),
            globals: Vec::new(),
            variadic_thunks: HashMap::new(),
        };
        codegen.declare_functions(program)?;
        codegen.declare_implicit_callees(program)?;
        codegen.define_strings(program)?;
        codegen.define_globals(program)?;
        Ok(codegen)
    }

    pub fn clif_type(&self, ty: IRType) -> Type {
        clif_type(ty, self.pointer_type)
    }

    pub fn abi_param(&self, ty: IRType, is_extern: bool) -> AbiParam {
        let param = AbiParam::new(self.clif_type(ty));
        // C callers widen small integer arguments (required on Apple arm64,
        // relied upon by clang on x86-64). The IR has lost signedness, so
        // zero-extension is the best available guess.
        if is_extern && matches!(ty, IRType::I8 | IRType::I16) {
            param.uext()
        } else {
            param
        }
    }

    fn signature(&self, params: &[IRType], ret: Option<IRType>, is_extern: bool) -> Signature {
        let mut signature = Signature::new(self.call_conv);
        for ty in params {
            signature.params.push(self.abi_param(*ty, is_extern));
        }
        if let Some(ty) = ret {
            signature.returns.push(self.abi_param(ty, is_extern));
        }
        signature
    }

    // ---- Declarations ----

    fn declare_functions(&mut self, program: &IrProgram) -> Result<(), GeneratorError> {
        for function in &program.functions {
            let params: Vec<IRType> = function.params.iter().map(|(_, ty)| *ty).collect();
            let mut ret = caller_return_type(function);
            if function.name == "main" && !function.is_extern {
                // C's main returns int; a unit main exits with 0.
                ret = ret.or(Some(IRType::I32));
            }
            let signature = self.signature(&params, ret, function.is_extern);
            let id = if function.is_extern {
                self.module
                    .declare_function(&function.name, Linkage::Import, &signature)
            } else {
                let linkage = if function.name == "main" {
                    Linkage::Export
                } else {
                    Linkage::Local
                };
                self.module
                    .declare_function(&local_symbol(&function.name), linkage, &signature)
            }
            .map_err(module_error)?;
            let declared = DeclaredFunction {
                id,
                params,
                ret,
                is_extern: function.is_extern,
                is_variadic: function.is_variadic,
            };
            self.functions.insert(function.name.clone(), declared);
        }
        Ok(())
    }

    // Functions the lowering calls on its own (fmod, fmodf), and thunks for
    // variadic calls on x86-64.
    fn declare_implicit_callees(&mut self, program: &IrProgram) -> Result<(), GeneratorError> {
        let calls = program
            .functions
            .iter()
            .flat_map(|function| &function.blocks)
            .flat_map(|block| &block.instructions)
            .filter_map(|inst| match inst {
                Inst::Call { dst, func, args } => Some((dst, func, args)),
                _ => None,
            });
        for (dst, func, args) in calls {
            if !self.functions.contains_key(func) {
                let params: Vec<IRType> = args.iter().map(|(_, ty)| *ty).collect();
                let ret = dst.map(|(_, ty)| ty);
                let signature = self.signature(&params, ret, true);
                let id = self
                    .module
                    .declare_function(func, Linkage::Import, &signature)
                    .map_err(module_error)?;
                let declared = DeclaredFunction {
                    id,
                    params,
                    ret,
                    is_extern: true,
                    is_variadic: false,
                };
                self.functions.insert(func.clone(), declared);
            } else if self.target.is_x86_64()
                && self.functions[func].is_variadic
                && !self.variadic_thunks.contains_key(func)
            {
                let id = self
                    .module
                    .declare_function(
                        &format!("tachyon.va.{}", func),
                        Linkage::Local,
                        &Signature::new(self.call_conv),
                    )
                    .map_err(module_error)?;
                self.variadic_thunks.insert(func.clone(), id);
            }
        }
        Ok(())
    }

    fn define_data(
        &mut self,
        name: &str,
        writable: bool,
        bytes: Vec<u8>,
        align: Option<u64>,
    ) -> Result<DataId, GeneratorError> {
        let id = self
            .module
            .declare_data(name, Linkage::Local, writable, false)
            .map_err(module_error)?;
        let mut description = DataDescription::new();
        description.define(bytes.into_boxed_slice());
        if let Some(align) = align {
            description.set_align(align);
        }
        self.module
            .define_data(id, &description)
            .map_err(module_error)?;
        Ok(id)
    }

    fn define_strings(&mut self, program: &IrProgram) -> Result<(), GeneratorError> {
        for (index, string) in program.strings.iter().enumerate() {
            let mut bytes = string.bytes.clone();
            // NUL-terminated for C.
            bytes.push(0);
            let id = self.define_data(&format!("tachyon.str.{}", index), true, bytes, None)?;
            self.strings.push(id);
        }
        Ok(())
    }

    fn define_globals(&mut self, program: &IrProgram) -> Result<(), GeneratorError> {
        for global in &program.globals {
            let mut bytes = global.bytes.clone();
            // Zero-sized data objects are not allowed.
            if bytes.is_empty() {
                bytes.push(0);
            }
            let id = self.define_data(
                &format!("tachyon.global.{}", global.name),
                global.mutable,
                bytes,
                Some(global.align.max(1)),
            )?;
            self.globals.push(id);
        }
        Ok(())
    }

    // ---- Definitions ----

    // Translates and compiles every function; with `text`, also appends
    // each one's CLIF and machine code to it.
    pub fn define_all(
        &mut self,
        program: &IrProgram,
        mut text: Option<&mut String>,
    ) -> Result<(), GeneratorError> {
        let mut context = self.module.make_context();
        let mut builder_context = cranelift_frontend::FunctionBuilderContext::new();
        for function in program.functions.iter().filter(|f| !f.is_extern) {
            let declared = self.functions[&function.name].clone();
            context.func.signature = self
                .module
                .declarations()
                .get_function_decl(declared.id)
                .signature
                .clone();
            let translated =
                Translator::new(self, &mut context.func, &mut builder_context, declared.ret)
                    .translate(function);
            if let Err(e) = translated {
                self.module.clear_context(&mut context);
                return Err(e);
            }
            self.compile_function(&function.name, declared.id, &mut context, &mut text)?;
        }
        let thunks: Vec<(String, FuncId)> = self
            .variadic_thunks
            .iter()
            .map(|(callee, thunk)| (callee.clone(), *thunk))
            .collect();
        for (callee, thunk) in thunks {
            self.define_variadic_thunk(thunk, self.functions[&callee].id)?;
        }
        Ok(())
    }

    fn compile_function(
        &mut self,
        name: &str,
        id: FuncId,
        context: &mut Context,
        text: &mut Option<&mut String>,
    ) -> Result<(), GeneratorError> {
        if let Some(text) = text.as_deref_mut() {
            context.set_disasm(true);
            let compiled = context
                .compile(self.module.isa(), &mut ControlPlane::default())
                .map_err(|e| error(format!("cranelift: {}: {:?}", name, e.inner)))?;
            let vcode = compiled.vcode.clone().unwrap_or_default();
            text.push_str(&format!(
                "{}\n; machine code\n{}\n",
                context.func.display(),
                vcode
            ));
        }
        self.module
            .define_function(id, context)
            .map_err(|e| match e {
                ModuleError::Compilation(inner) => error(format!(
                    "cranelift: {}: {}",
                    name,
                    cranelift_codegen::print_errors::pretty_error(&context.func, inner)
                )),
                other => module_error(other),
            })?;
        self.module.clear_context(context);
        Ok(())
    }

    fn define_variadic_thunk(
        &mut self,
        thunk: FuncId,
        callee: FuncId,
    ) -> Result<(), GeneratorError> {
        let jump_target = ModuleReloc {
            offset: VARIADIC_THUNK_JUMP_OFFSET,
            kind: cranelift_codegen::binemit::Reloc::X86CallPLTRel4,
            name: ModuleRelocTarget::User {
                namespace: 0,
                index: callee.as_u32(),
            },
            // The displacement is relative to the end of the instruction.
            addend: -4,
        };
        self.module
            .define_function_bytes(thunk, VARIADIC_THUNK_ALIGN, &VARIADIC_THUNK, &[jump_target])
            .map_err(module_error)
    }

    pub fn finish(self) -> Result<Vec<u8>, GeneratorError> {
        self.module
            .finish()
            .emit()
            .map_err(|e| error(format!("object emission: {}", e)))
    }
}
