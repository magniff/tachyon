// Cranelift backend: lowers the IR to CLIF and emits a native object file.
//
// Every vreg becomes a cranelift-frontend `Variable`, so the frontend builds
// SSA on the fly (Braun et al.) and the register allocator sees real values.
// Stack slots whose address never escapes and that are only read and written
// whole, with one scalar type, are promoted to variables as well (mem2reg);
// everything else stays an explicit stack slot.
//
// Calling convention:
// - tachyon functions use the platform C convention, with tachyon's own
//   rules for compound values on top (sret pointer first, structs by pointer).
// - C variadic calls need care, as Cranelift has no variadic signatures:
//   * x86-64 System V: the caller must put an upper bound on the number of
//     vector registers used in `al`. Calls go through a 7-byte thunk,
//     `mov al, 8; jmp callee`, which leaves arguments and stack untouched.
//   * Apple arm64: variadic arguments are passed on the stack, never in
//     registers. The call signature is padded with dummy arguments until all
//     eight integer and eight vector argument registers are taken, so the
//     variadic ones land on the stack, each in its own 8-byte slot.
//   Variadic arguments are widened to 64 bits so that every one fills a
//   full stack slot.
// - Local tachyon functions get the symbol `tachyon.<name>` so they cannot
//   clash with C symbols (a tachyon `pow` next to libc's `pow`); `main` keeps
//   its name.

use std::collections::{HashMap, HashSet};

use cranelift_codegen::Context;
use cranelift_codegen::control::ControlPlane;
use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::{
    self, AbiParam, ExtFuncData, ExternalName, InstBuilder, MemFlagsData, Signature, StackSlotData,
    StackSlotKind, Type, UserExternalName, types,
};
use cranelift_codegen::isa::{self, CallConv, OwnedTargetIsa};
use cranelift_codegen::settings::{self, Configurable};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Variable};
use cranelift_module::{
    DataDescription, DataId, FuncId, Linkage, Module, ModuleReloc, ModuleRelocTarget,
    default_libcall_names,
};
use cranelift_object::{ObjectBuilder, ObjectModule};

use super::{Artifact, Backend, GeneratorError, OptLevel, Options, Target};
use crate::lowering::*;

pub struct CraneliftBackend;

impl Backend for CraneliftBackend {
    fn compile(&self, program: &IrProgram, options: &Options) -> Result<Artifact, GeneratorError> {
        let mut codegen = Codegen::new(program, options)?;
        codegen.define_all(program, None)?;
        codegen.finish().map(Artifact)
    }
}

// The CLIF of every function after Cranelift's mid-end, followed by the
// machine code it was lowered to.
pub fn clif_text(program: &IrProgram, options: &Options) -> Result<String, GeneratorError> {
    let mut codegen = Codegen::new(program, options)?;
    let mut text = String::new();
    codegen.define_all(program, Some(&mut text))?;
    Ok(text)
}

fn error(message: impl Into<String>) -> GeneratorError {
    GeneratorError {
        message: message.into(),
    }
}

fn make_isa(options: &Options) -> Result<OwnedTargetIsa, GeneratorError> {
    let mut flags = settings::builder();
    let opt = match options.opt_level {
        OptLevel::None => "none",
        OptLevel::Speed => "speed",
    };
    let set = |flags: &mut settings::Builder, name: &str, value: &str| {
        flags
            .set(name, value)
            .map_err(|e| error(format!("cranelift setting {}={}: {}", name, value, e)))
    };
    set(&mut flags, "opt_level", opt)?;
    set(&mut flags, "is_pic", "true")?;
    // Apple arm64 requires frame records; they also keep backtraces usable.
    set(&mut flags, "preserve_frame_pointers", "true")?;
    set(&mut flags, "enable_verifier", "true")?;
    let flags = settings::Flags::new(flags);

    let builder = if Some(options.target) == Target::native() {
        cranelift_native::builder_with_options(true).map_err(error)?
    } else {
        let triple: target_lexicon::Triple = options
            .target
            .triple()
            .parse()
            .map_err(|e| error(format!("bad target triple: {}", e)))?;
        isa::lookup(triple).map_err(|e| error(format!("cranelift: {}", e)))?
    };
    builder
        .finish(flags)
        .map_err(|e| error(format!("cranelift: {}", e)))
}

#[derive(Clone)]
struct FuncDecl {
    id: FuncId,
    // Declared parameter and return types (sret pointer included).
    params: Vec<IRType>,
    ret: Option<IRType>,
    is_extern: bool,
    is_variadic: bool,
}

struct Codegen {
    module: ObjectModule,
    target: Target,
    ptr: Type,
    call_conv: CallConv,
    funcs: HashMap<String, FuncDecl>,
    strings: Vec<DataId>,
    ipow: Option<FuncId>,
    // x86-64 only: `mov al, 8; jmp f` thunks for variadic externs.
    va_thunks: HashMap<String, FuncId>,
}

const IPOW: &str = "__ipow";

fn local_symbol(name: &str) -> String {
    if name == "main" {
        name.to_string()
    } else {
        format!("tachyon.{}", name)
    }
}

// Return type as seen by callers: compound results come back as the sret
// pointer even though the IR records no scalar return type for them.
fn return_type(function: &IRFunction) -> Option<IRType> {
    if function.return_ir.is_some() || function.is_extern {
        return function.return_ir;
    }
    function.blocks.iter().find_map(|bb| match bb.teminator {
        Term::Ret(Some((_, ty))) => Some(ty),
        _ => None,
    })
}

impl Codegen {
    fn new(program: &IrProgram, options: &Options) -> Result<Codegen, GeneratorError> {
        let isa = make_isa(options)?;
        let ptr = isa.pointer_type();
        let call_conv = isa.default_call_conv();
        let builder = ObjectBuilder::new(isa, "tachyon", default_libcall_names())
            .map_err(|e| error(format!("cranelift: {}", e)))?;
        let mut codegen = Codegen {
            module: ObjectModule::new(builder),
            target: options.target,
            ptr,
            call_conv,
            funcs: HashMap::new(),
            strings: Vec::new(),
            ipow: None,
            va_thunks: HashMap::new(),
        };
        codegen.declare(program)?;
        Ok(codegen)
    }

    fn clif_type(&self, ty: IRType) -> Type {
        clif_type(ty, self.ptr)
    }

    fn abi_param(&self, ty: IRType, is_extern: bool) -> AbiParam {
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
        let mut sig = Signature::new(self.call_conv);
        for ty in params {
            sig.params.push(self.abi_param(*ty, is_extern));
        }
        if let Some(ty) = ret {
            sig.returns.push(self.abi_param(ty, is_extern));
        }
        sig
    }

    fn module_error(e: cranelift_module::ModuleError) -> GeneratorError {
        error(format!("cranelift: {:?}", e))
    }

    fn declare(&mut self, program: &IrProgram) -> Result<(), GeneratorError> {
        for function in &program.functions {
            let params: Vec<IRType> = function.params.iter().map(|(_, ty)| *ty).collect();
            let ret = if function.name == "main" && !function.is_extern {
                // C's main returns int; a unit main exits with 0.
                return_type(function).or(Some(IRType::I32))
            } else {
                return_type(function)
            };
            let sig = self.signature(&params, ret, function.is_extern);
            let id = if function.is_extern {
                self.module
                    .declare_function(&function.name, Linkage::Import, &sig)
            } else {
                let linkage = if function.name == "main" {
                    Linkage::Export
                } else {
                    Linkage::Local
                };
                self.module
                    .declare_function(&local_symbol(&function.name), linkage, &sig)
            }
            .map_err(Self::module_error)?;
            self.funcs.insert(
                function.name.clone(),
                FuncDecl {
                    id,
                    params,
                    ret,
                    is_extern: function.is_extern,
                    is_variadic: function.is_variadic,
                },
            );
        }

        // Functions the lowering calls on its own (fmod, pow, __ipow) and
        // thunks for variadic calls.
        for function in &program.functions {
            for bb in &function.blocks {
                for inst in &bb.instructions {
                    let Inst::Call { dst, func, args } = inst else {
                        continue;
                    };
                    if func == IPOW {
                        if self.ipow.is_none() {
                            let sig = self.signature(
                                &[IRType::I64, IRType::I64],
                                Some(IRType::I64),
                                false,
                            );
                            self.ipow = Some(
                                self.module
                                    .declare_function("tachyon.ipow", Linkage::Local, &sig)
                                    .map_err(Self::module_error)?,
                            );
                        }
                    } else if !self.funcs.contains_key(func) {
                        let params: Vec<IRType> = args.iter().map(|(_, ty)| *ty).collect();
                        let ret = dst.map(|(_, ty)| ty);
                        let sig = self.signature(&params, ret, true);
                        let id = self
                            .module
                            .declare_function(func, Linkage::Import, &sig)
                            .map_err(Self::module_error)?;
                        self.funcs.insert(
                            func.clone(),
                            FuncDecl {
                                id,
                                params,
                                ret,
                                is_extern: true,
                                is_variadic: false,
                            },
                        );
                    } else if self.target.is_x86_64()
                        && self.funcs[func].is_variadic
                        && !self.va_thunks.contains_key(func)
                    {
                        let sig = Signature::new(self.call_conv);
                        let id = self
                            .module
                            .declare_function(&format!("tachyon.va.{}", func), Linkage::Local, &sig)
                            .map_err(Self::module_error)?;
                        self.va_thunks.insert(func.clone(), id);
                    }
                }
            }
        }

        for (index, string) in program.strings.iter().enumerate() {
            let id = self
                .module
                .declare_data(
                    &format!("tachyon.str.{}", index),
                    Linkage::Local,
                    true,
                    false,
                )
                .map_err(Self::module_error)?;
            let mut bytes = string.bytes.clone();
            // NUL-terminated for C.
            bytes.push(0);
            let mut description = DataDescription::new();
            description.define(bytes.into_boxed_slice());
            self.module
                .define_data(id, &description)
                .map_err(Self::module_error)?;
            self.strings.push(id);
        }
        Ok(())
    }

    fn define_all(
        &mut self,
        program: &IrProgram,
        mut text: Option<&mut String>,
    ) -> Result<(), GeneratorError> {
        let mut ctx = self.module.make_context();
        let mut builder_ctx = FunctionBuilderContext::new();
        for function in program.functions.iter().filter(|f| !f.is_extern) {
            let decl = self.funcs[&function.name].clone();
            ctx.func.signature = self
                .module
                .declarations()
                .get_function_decl(decl.id)
                .signature
                .clone();
            let translated = Translator::new(self, &mut ctx.func, &mut builder_ctx, decl.ret)
                .translate(function);
            if let Err(e) = translated {
                self.module.clear_context(&mut ctx);
                return Err(e);
            }
            self.compile(&function.name, decl.id, &mut ctx, &mut text)?;
        }
        if let Some(id) = self.ipow {
            ctx.func.signature = self
                .module
                .declarations()
                .get_function_decl(id)
                .signature
                .clone();
            build_ipow(&mut ctx.func, &mut builder_ctx, self.module.target_config());
            self.compile(IPOW, id, &mut ctx, &mut text)?;
        }
        let thunks: Vec<(String, FuncId)> = self
            .va_thunks
            .iter()
            .map(|(k, v)| (k.clone(), *v))
            .collect();
        for (callee, thunk) in thunks {
            self.define_va_thunk(thunk, self.funcs[&callee].id)?;
        }
        Ok(())
    }

    fn compile(
        &mut self,
        name: &str,
        id: FuncId,
        ctx: &mut Context,
        text: &mut Option<&mut String>,
    ) -> Result<(), GeneratorError> {
        if let Some(text) = text.as_deref_mut() {
            ctx.set_disasm(true);
            let compiled = ctx
                .compile(self.module.isa(), &mut ControlPlane::default())
                .map_err(|e| error(format!("cranelift: {}: {:?}", name, e.inner)))?;
            let vcode = compiled.vcode.clone().unwrap_or_default();
            text.push_str(&format!(
                "{}\n; machine code\n{}\n",
                ctx.func.display(),
                vcode
            ));
        }
        self.module.define_function(id, ctx).map_err(|e| match e {
            cranelift_module::ModuleError::Compilation(inner) => error(format!(
                "cranelift: {}: {}",
                name,
                cranelift_codegen::print_errors::pretty_error(&ctx.func, inner)
            )),
            other => Self::module_error(other),
        })?;
        self.module.clear_context(ctx);
        Ok(())
    }

    // mov al, 8 ; jmp callee
    fn define_va_thunk(&mut self, thunk: FuncId, callee: FuncId) -> Result<(), GeneratorError> {
        let bytes = [0xb0, 0x08, 0xe9, 0, 0, 0, 0];
        let reloc = ModuleReloc {
            offset: 3,
            kind: cranelift_codegen::binemit::Reloc::X86CallPLTRel4,
            name: ModuleRelocTarget::User {
                namespace: 0,
                index: callee.as_u32(),
            },
            addend: -4,
        };
        self.module
            .define_function_bytes(thunk, 16, &bytes, &[reloc])
            .map_err(Self::module_error)
    }

    fn finish(self) -> Result<Vec<u8>, GeneratorError> {
        self.module
            .finish()
            .emit()
            .map_err(|e| error(format!("object emission: {}", e)))
    }
}

fn clif_type(ty: IRType, ptr: Type) -> Type {
    match ty {
        IRType::I8 => types::I8,
        IRType::I16 => types::I16,
        IRType::I32 => types::I32,
        IRType::I64 => types::I64,
        IRType::F32 => types::F32,
        IRType::F64 => types::F64,
        IRType::Ptr => ptr,
    }
}

// The vreg an instruction defines, if any.
fn inst_def(inst: &Inst) -> Option<(VReg, Option<IRType>)> {
    use Inst::*;
    Some(match inst {
        IAdd(d, _, _, t)
        | ISub(d, _, _, t)
        | IMul(d, _, _, t)
        | IDiv(d, _, _, t, _)
        | IMod(d, _, _, t, _)
        | IShl(d, _, _, t)
        | IShr(d, _, _, t, _)
        | IBitAnd(d, _, _, t)
        | IBitOr(d, _, _, t)
        | IBitXor(d, _, _, t)
        | FAdd(d, _, _, t)
        | FSub(d, _, _, t)
        | FMul(d, _, _, t)
        | FDiv(d, _, _, t) => (*d, Some(*t)),
        INeg(d, _, t) | IBitNot(d, _, t) | FNeg(d, _, t) => (*d, Some(*t)),
        ICmp(d, ..) | FCmp(d, ..) | BoolNot(d, _) => (*d, Some(IRType::I8)),
        ConstInt(d, _, t) | ConstFloat(d, _, t) => (*d, Some(*t)),
        ConstStringPtr(d, _) | SlotAddr(d, _) | MemberPtr(d, _, _) | IndexPtr(d, _, _, _) => {
            (*d, Some(IRType::Ptr))
        }
        FuncAddr(d, _) => (*d, Some(IRType::Ptr)),
        IntToFloat(d, _, _, t, _)
        | FloatToInt(d, _, _, t, _)
        | FloatToFloat(d, _, _, t)
        | IntExt(d, _, _, t, _)
        | IntTrunc(d, _, _, t) => (*d, Some(*t)),
        Load(d, _, t) => (*d, Some(*t)),
        Call { dst, .. } | CallIndirect { dst, .. } => {
            let (d, t) = (*dst)?;
            (d, Some(t))
        }
        // Takes the type of its source.
        Mov(d, _) => (*d, None),
        Store(..) | MemCopy { .. } => return None,
    })
}

// Every vreg an instruction reads.
fn inst_uses(inst: &Inst) -> Vec<VReg> {
    use Inst::*;
    match inst {
        IAdd(_, a, b, _)
        | ISub(_, a, b, _)
        | IMul(_, a, b, _)
        | IDiv(_, a, b, _, _)
        | IMod(_, a, b, _, _)
        | IShl(_, a, b, _)
        | IShr(_, a, b, _, _)
        | IBitAnd(_, a, b, _)
        | IBitOr(_, a, b, _)
        | IBitXor(_, a, b, _)
        | FAdd(_, a, b, _)
        | FSub(_, a, b, _)
        | FMul(_, a, b, _)
        | FDiv(_, a, b, _)
        | ICmp(_, _, a, b, _, _)
        | FCmp(_, _, a, b, _)
        | IndexPtr(_, a, b, _)
        | Store(a, b, _) => vec![*a, *b],
        INeg(_, a, _)
        | IBitNot(_, a, _)
        | FNeg(_, a, _)
        | BoolNot(_, a)
        | IntToFloat(_, a, _, _, _)
        | FloatToInt(_, a, _, _, _)
        | FloatToFloat(_, a, _, _)
        | IntExt(_, a, _, _, _)
        | IntTrunc(_, a, _, _)
        | Load(_, a, _)
        | MemberPtr(_, a, _)
        | Mov(_, a) => vec![*a],
        MemCopy { dst, src, .. } => vec![*dst, *src],
        Call { args, .. } => args.iter().map(|(v, _)| *v).collect(),
        CallIndirect { callee, args, .. } => {
            let mut uses = vec![*callee];
            uses.extend(args.iter().map(|(v, _)| *v));
            uses
        }
        ConstInt(..) | ConstFloat(..) | ConstStringPtr(..) | SlotAddr(..) | FuncAddr(..) => {
            vec![]
        }
    }
}

fn term_uses(term: &Term) -> Vec<VReg> {
    match term {
        Term::Ret(Some((v, _))) => vec![*v],
        Term::CondBr { cond, .. } => vec![*cond],
        Term::Ret(None) | Term::Jump(_) => vec![],
    }
}

// The type of every vreg, from its (first) definition.
fn vreg_types(function: &IRFunction) -> HashMap<u32, IRType> {
    let mut types: HashMap<u32, IRType> = HashMap::new();
    for (v, ty) in &function.params {
        types.insert(v.0, *ty);
    }
    loop {
        let mut changed = false;
        for bb in &function.blocks {
            for inst in &bb.instructions {
                let Some((d, ty)) = inst_def(inst) else {
                    continue;
                };
                if types.contains_key(&d.0) {
                    continue;
                }
                let ty = match (ty, inst) {
                    (Some(ty), _) => Some(ty),
                    (None, Inst::Mov(_, s)) => types.get(&s.0).copied(),
                    _ => None,
                };
                if let Some(ty) = ty {
                    types.insert(d.0, ty);
                    changed = true;
                }
            }
        }
        if !changed {
            return types;
        }
    }
}

// mem2reg: slots that can live in a variable. A slot qualifies when each of
// its address vregs is defined once, by its SlotAddr, and is used only as the
// address of whole-slot loads and stores of a single scalar type.
// Returns address vreg -> (slot, type).
fn promotable_slots(function: &IRFunction) -> HashMap<u32, (u32, IRType)> {
    let mut defs: HashMap<u32, usize> = HashMap::new();
    let mut slot_of: HashMap<u32, u32> = HashMap::new();
    for bb in &function.blocks {
        for inst in &bb.instructions {
            if let Some((d, _)) = inst_def(inst) {
                *defs.entry(d.0).or_default() += 1;
            }
            if let Inst::SlotAddr(d, slot) = inst {
                slot_of.insert(d.0, slot.0);
            }
        }
    }
    for (v, _) in &function.params {
        *defs.entry(v.0).or_default() += 1;
    }

    let mut escaped: HashSet<u32> = HashSet::new();
    let mut access: HashMap<u32, IRType> = HashMap::new();
    let mut access_ok = |slot: u32, ty: IRType, escaped: &mut HashSet<u32>| match access.get(&slot)
    {
        Some(seen) if *seen != ty => {
            escaped.insert(slot);
        }
        Some(_) => {}
        None => {
            access.insert(slot, ty);
        }
    };
    for bb in &function.blocks {
        for inst in &bb.instructions {
            let mut uses = inst_uses(inst);
            match inst {
                Inst::Load(_, addr, ty) if slot_of.contains_key(&addr.0) => {
                    access_ok(slot_of[&addr.0], *ty, &mut escaped);
                    uses.clear();
                }
                Inst::Store(addr, _, ty) if slot_of.contains_key(&addr.0) => {
                    access_ok(slot_of[&addr.0], *ty, &mut escaped);
                    // The stored value may itself be a slot address.
                    uses.remove(0);
                }
                _ => {}
            }
            for v in uses {
                if let Some(slot) = slot_of.get(&v.0) {
                    escaped.insert(*slot);
                }
            }
        }
        for v in term_uses(&bb.teminator) {
            if let Some(slot) = slot_of.get(&v.0) {
                escaped.insert(*slot);
            }
        }
    }
    for (v, slot) in &slot_of {
        if defs.get(v).copied().unwrap_or(0) != 1 {
            escaped.insert(*slot);
        }
    }

    slot_of
        .iter()
        .filter_map(|(v, slot)| {
            let ty = *access.get(slot)?;
            let size = function.slots[*slot as usize].size;
            (!escaped.contains(slot) && ty.size() == size).then_some((*v, (*slot, ty)))
        })
        .collect()
}

struct Translator<'a> {
    b: FunctionBuilder<'a>,
    cg: &'a mut Codegen,
    ret: Option<IRType>,
    blocks: HashMap<u32, ir::Block>,
    vars: HashMap<u32, Variable>,
    vtypes: HashMap<u32, IRType>,
    // Address vreg of a promoted slot -> the slot's variable.
    promoted: HashMap<u32, Variable>,
    stack_slots: HashMap<u32, ir::StackSlot>,
    func_refs: HashMap<FuncId, ir::FuncRef>,
    data_refs: HashMap<DataId, ir::GlobalValue>,
    // Set when the function uses something this backend cannot express.
    unsupported: Option<String>,
}

fn flags() -> MemFlagsData {
    MemFlagsData::new()
}

impl<'a> Translator<'a> {
    fn new(
        cg: &'a mut Codegen,
        func: &'a mut ir::Function,
        builder_ctx: &'a mut FunctionBuilderContext,
        ret: Option<IRType>,
    ) -> Translator<'a> {
        Translator {
            b: FunctionBuilder::new(func, builder_ctx),
            cg,
            ret,
            blocks: HashMap::new(),
            vars: HashMap::new(),
            vtypes: HashMap::new(),
            promoted: HashMap::new(),
            stack_slots: HashMap::new(),
            func_refs: HashMap::new(),
            data_refs: HashMap::new(),
            unsupported: None,
        }
    }

    fn ty(&self, ty: IRType) -> Type {
        self.cg.clif_type(ty)
    }

    fn block(&mut self, id: BlockId) -> ir::Block {
        if let Some(block) = self.blocks.get(&id.0) {
            return *block;
        }
        let block = self.b.create_block();
        self.blocks.insert(id.0, block);
        block
    }

    fn var(&mut self, v: VReg) -> Variable {
        if let Some(var) = self.vars.get(&v.0) {
            return *var;
        }
        let ty = self.vtypes.get(&v.0).copied().unwrap_or(IRType::I64);
        let var = self.b.declare_var(self.cg.clif_type(ty));
        self.vars.insert(v.0, var);
        var
    }

    fn get(&mut self, v: VReg) -> ir::Value {
        let var = self.var(v);
        self.b.use_var(var)
    }

    fn get_as(&mut self, v: VReg, ty: Type) -> ir::Value {
        let value = self.get(v);
        self.coerce(value, ty)
    }

    fn set(&mut self, v: VReg, value: ir::Value) {
        let var = self.var(v);
        let want = self.ty(self.vtypes.get(&v.0).copied().unwrap_or(IRType::I64));
        let value = self.coerce(value, want);
        self.b.def_var(var, value);
    }

    // Reinterpret a value at another width or class. The IR treats vregs as
    // 64-bit values whose low bytes are read, so narrowing is a truncation
    // and widening a zero-extension.
    fn coerce(&mut self, value: ir::Value, to: Type) -> ir::Value {
        let from = self.b.func.dfg.value_type(value);
        if from == to {
            return value;
        }
        if from.is_int() && to.is_int() {
            if from.bits() > to.bits() {
                self.b.ins().ireduce(to, value)
            } else {
                self.b.ins().uextend(to, value)
            }
        } else if from.bits() == to.bits() {
            self.b.ins().bitcast(to, flags(), value)
        } else if from.is_float() && to.is_int() {
            let bits = Type::int(from.bits() as u16).unwrap();
            let raw = self.b.ins().bitcast(bits, flags(), value);
            self.coerce(raw, to)
        } else {
            let bits = Type::int(to.bits() as u16).unwrap();
            let raw = self.coerce(value, bits);
            self.b.ins().bitcast(to, flags(), raw)
        }
    }

    fn iconst(&mut self, ty: Type, value: i64) -> ir::Value {
        let masked = if ty.bits() < 64 {
            value & ((1i64 << ty.bits()) - 1)
        } else {
            value
        };
        self.b.ins().iconst(ty, masked)
    }

    fn zero(&mut self, ty: Type) -> ir::Value {
        if ty == types::F32 {
            self.b.ins().f32const(0.0)
        } else if ty == types::F64 {
            self.b.ins().f64const(0.0)
        } else {
            self.b.ins().iconst(ty, 0)
        }
    }

    fn func_ref(&mut self, id: FuncId) -> ir::FuncRef {
        if let Some(r) = self.func_refs.get(&id) {
            return *r;
        }
        let r = self.cg.module.declare_func_in_func(id, self.b.func);
        self.func_refs.insert(id, r);
        r
    }

    fn data_ref(&mut self, id: DataId) -> ir::GlobalValue {
        if let Some(r) = self.data_refs.get(&id) {
            return *r;
        }
        let r = self.cg.module.declare_data_in_func(id, self.b.func);
        self.data_refs.insert(id, r);
        r
    }

    fn translate(mut self, function: &IRFunction) -> Result<(), GeneratorError> {
        self.vtypes = vreg_types(function);
        let promotable = promotable_slots(function);

        for (index, slot) in function.slots.iter().enumerate() {
            let index = index as u32;
            let promoted = promotable.values().find(|(s, _)| *s == index);
            if promoted.is_some() {
                continue;
            }
            let align = slot.align.clamp(1, 16);
            let data = StackSlotData::new(
                StackSlotKind::ExplicitSlot,
                slot.size.max(1) as u32,
                align.trailing_zeros() as u8,
            );
            let ss = self.b.create_sized_stack_slot(data);
            self.stack_slots.insert(index, ss);
        }
        let mut slot_vars: HashMap<u32, Variable> = HashMap::new();
        for (addr, (slot, ty)) in &promotable {
            let var = *slot_vars
                .entry(*slot)
                .or_insert_with(|| self.b.declare_var(clif_type(*ty, self.cg.ptr)));
            self.promoted.insert(*addr, var);
        }

        let entry = self.b.create_block();
        self.b.append_block_params_for_function_params(entry);
        self.b.switch_to_block(entry);
        let params: Vec<ir::Value> = self.b.block_params(entry).to_vec();
        for ((v, _), value) in function.params.iter().zip(params) {
            self.set(*v, value);
        }
        let first = self.block(BlockId(0));
        self.b.ins().jump(first, &[]);

        let mut defined: HashSet<u32> = HashSet::new();
        for bb in &function.blocks {
            let block = self.block(bb.id);
            defined.insert(bb.id.0);
            self.b.switch_to_block(block);
            for inst in &bb.instructions {
                self.inst(inst);
            }
            self.term(&bb.teminator);
        }
        // Branch targets the lowering never filled in cannot be reached.
        let missing: Vec<ir::Block> = self
            .blocks
            .iter()
            .filter(|(id, _)| !defined.contains(id))
            .map(|(_, b)| *b)
            .collect();
        for block in missing {
            self.b.switch_to_block(block);
            self.b.ins().trap(ir::TrapCode::unwrap_user(1));
        }
        self.b.seal_all_blocks();
        let config = self.cg.module.target_config();
        self.b.finalize(config);
        match self.unsupported {
            Some(message) => Err(error(format!("{}: {}", function.name, message))),
            None => Ok(()),
        }
    }

    fn term(&mut self, term: &Term) {
        match term {
            Term::Ret(value) => {
                let ret = self.ret.map(|t| self.ty(t));
                match (ret, value) {
                    (Some(ty), Some((v, _))) => {
                        let value = self.get_as(*v, ty);
                        self.b.ins().return_(&[value]);
                    }
                    (Some(ty), None) => {
                        let value = self.zero(ty);
                        self.b.ins().return_(&[value]);
                    }
                    (None, _) => {
                        self.b.ins().return_(&[]);
                    }
                }
            }
            Term::Jump(target) => {
                let block = self.block(*target);
                self.b.ins().jump(block, &[]);
            }
            Term::CondBr {
                cond,
                then_bb,
                else_bb,
            } => {
                // Booleans are bytes; only the low byte is meaningful.
                let cond = self.get_as(*cond, types::I8);
                let then_block = self.block(*then_bb);
                let else_block = self.block(*else_bb);
                self.b.ins().brif(cond, then_block, &[], else_block, &[]);
            }
        }
    }

    fn binary(&mut self, a: VReg, b: VReg, ty: IRType) -> (ir::Value, ir::Value) {
        let ty = self.ty(ty);
        (self.get_as(a, ty), self.get_as(b, ty))
    }

    // x86 semantics on every target: the shift count is masked to 5
    // bits for operands up to 32 bits and 6 bits for 64-bit operands, so
    // shifting an i8 by 8..31 shifts everything out.
    fn shift(&mut self, a: VReg, b: VReg, ty: IRType, kind: ShiftKind) -> ir::Value {
        let t = self.ty(ty);
        let value = self.get_as(a, t);
        let amount = self.get(b);
        if t.bits() >= 32 {
            return match kind {
                ShiftKind::Shl => self.b.ins().ishl(value, amount),
                ShiftKind::Ushr => self.b.ins().ushr(value, amount),
                ShiftKind::Sshr => self.b.ins().sshr(value, amount),
            };
        }
        let wide = match kind {
            ShiftKind::Sshr => self.b.ins().sextend(types::I32, value),
            _ => self.b.ins().uextend(types::I32, value),
        };
        let shifted = match kind {
            ShiftKind::Shl => self.b.ins().ishl(wide, amount),
            ShiftKind::Ushr => self.b.ins().ushr(wide, amount),
            ShiftKind::Sshr => self.b.ins().sshr(wide, amount),
        };
        self.b.ins().ireduce(t, shifted)
    }

    fn inst(&mut self, inst: &Inst) {
        use Inst::*;
        match inst {
            IAdd(d, a, b, t) => {
                let (x, y) = self.binary(*a, *b, *t);
                let r = self.b.ins().iadd(x, y);
                self.set(*d, r);
            }
            ISub(d, a, b, t) => {
                let (x, y) = self.binary(*a, *b, *t);
                let r = self.b.ins().isub(x, y);
                self.set(*d, r);
            }
            IMul(d, a, b, t) => {
                let (x, y) = self.binary(*a, *b, *t);
                let r = self.b.ins().imul(x, y);
                self.set(*d, r);
            }
            IDiv(d, a, b, t, signed) => {
                let (x, y) = self.binary(*a, *b, *t);
                let r = if *signed {
                    self.b.ins().sdiv(x, y)
                } else {
                    self.b.ins().udiv(x, y)
                };
                self.set(*d, r);
            }
            IMod(d, a, b, t, signed) => {
                let (x, y) = self.binary(*a, *b, *t);
                let r = if *signed {
                    self.b.ins().srem(x, y)
                } else {
                    self.b.ins().urem(x, y)
                };
                self.set(*d, r);
            }
            IShl(d, a, b, t) => {
                let r = self.shift(*a, *b, *t, ShiftKind::Shl);
                self.set(*d, r);
            }
            IShr(d, a, b, t, signed) => {
                let kind = if *signed {
                    ShiftKind::Sshr
                } else {
                    ShiftKind::Ushr
                };
                let r = self.shift(*a, *b, *t, kind);
                self.set(*d, r);
            }
            INeg(d, a, t) => {
                let ty = self.ty(*t);
                let x = self.get_as(*a, ty);
                let r = self.b.ins().ineg(x);
                self.set(*d, r);
            }
            IBitAnd(d, a, b, t) => {
                let (x, y) = self.binary(*a, *b, *t);
                let r = self.b.ins().band(x, y);
                self.set(*d, r);
            }
            IBitOr(d, a, b, t) => {
                let (x, y) = self.binary(*a, *b, *t);
                let r = self.b.ins().bor(x, y);
                self.set(*d, r);
            }
            IBitXor(d, a, b, t) => {
                let (x, y) = self.binary(*a, *b, *t);
                let r = self.b.ins().bxor(x, y);
                self.set(*d, r);
            }
            IBitNot(d, a, t) => {
                let ty = self.ty(*t);
                let x = self.get_as(*a, ty);
                let r = self.b.ins().bnot(x);
                self.set(*d, r);
            }
            FAdd(d, a, b, t) => {
                let (x, y) = self.binary(*a, *b, *t);
                let r = self.b.ins().fadd(x, y);
                self.set(*d, r);
            }
            FSub(d, a, b, t) => {
                let (x, y) = self.binary(*a, *b, *t);
                let r = self.b.ins().fsub(x, y);
                self.set(*d, r);
            }
            FMul(d, a, b, t) => {
                let (x, y) = self.binary(*a, *b, *t);
                let r = self.b.ins().fmul(x, y);
                self.set(*d, r);
            }
            FDiv(d, a, b, t) => {
                let (x, y) = self.binary(*a, *b, *t);
                let r = self.b.ins().fdiv(x, y);
                self.set(*d, r);
            }
            FNeg(d, a, t) => {
                let ty = self.ty(*t);
                let x = self.get_as(*a, ty);
                let r = self.b.ins().fneg(x);
                self.set(*d, r);
            }
            ICmp(d, op, a, b, t, signed) => {
                let (x, y) = self.binary(*a, *b, *t);
                let cc = match (op, signed) {
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
                };
                let r = self.b.ins().icmp(cc, x, y);
                self.set(*d, r);
            }
            FCmp(d, op, a, b, t) => {
                let (x, y) = self.binary(*a, *b, *t);
                // Ordered comparisons are false for NaN; `!=` is true.
                let cc = match op {
                    CmpOp::Eq => FloatCC::Equal,
                    CmpOp::Neq => FloatCC::NotEqual,
                    CmpOp::Lt => FloatCC::LessThan,
                    CmpOp::Gt => FloatCC::GreaterThan,
                    CmpOp::LtEq => FloatCC::LessThanOrEqual,
                    CmpOp::GtEq => FloatCC::GreaterThanOrEqual,
                };
                let r = self.b.ins().fcmp(cc, x, y);
                self.set(*d, r);
            }
            BoolNot(d, a) => {
                let x = self.get_as(*a, types::I8);
                let r = self.b.ins().bxor_imm_u(x, 1);
                self.set(*d, r);
            }
            ConstInt(d, value, t) => {
                let ty = self.ty(*t);
                let r = self.iconst(ty, *value);
                self.set(*d, r);
            }
            ConstFloat(d, value, t) => {
                let r = if *t == IRType::F32 {
                    self.b.ins().f32const(*value as f32)
                } else {
                    self.b.ins().f64const(*value)
                };
                self.set(*d, r);
            }
            ConstStringPtr(d, index) => {
                let gv = self.data_ref(self.cg.strings[*index]);
                let ptr = self.cg.ptr;
                let r = self.b.ins().symbol_value(ptr, gv);
                self.set(*d, r);
            }
            IntToFloat(d, s, from, to, signed) => {
                let from_ty = self.ty(*from);
                let to_ty = self.ty(*to);
                let mut x = self.get_as(*s, from_ty);
                if from_ty.bits() < 32 {
                    x = if *signed {
                        self.b.ins().sextend(types::I32, x)
                    } else {
                        self.b.ins().uextend(types::I32, x)
                    };
                }
                let r = if *signed {
                    self.b.ins().fcvt_from_sint(to_ty, x)
                } else {
                    self.b.ins().fcvt_from_uint(to_ty, x)
                };
                self.set(*d, r);
            }
            FloatToInt(d, s, from, to, signed) => {
                let from_ty = self.ty(*from);
                let to_ty = self.ty(*to);
                let x = self.get_as(*s, from_ty);
                // Saturating conversions (NaN -> 0) instead of trapping.
                // Narrow results wrap: convert at 32 bits (signed) or 64 bits
                // (unsigned), then truncate.
                let r = if *signed && to_ty.bits() <= 32 {
                    let wide = self.b.ins().fcvt_to_sint_sat(types::I32, x);
                    self.coerce(wide, to_ty)
                } else if *signed {
                    self.b.ins().fcvt_to_sint_sat(types::I64, x)
                } else if to_ty.bits() <= 32 {
                    let wide = self.b.ins().fcvt_to_sint_sat(types::I64, x);
                    self.coerce(wide, to_ty)
                } else {
                    // u64: below 2^63 a signed conversion also wraps
                    // negative values; above it, convert unsigned.
                    let limit = if from_ty == types::F64 {
                        self.b.ins().f64const(9223372036854775808.0)
                    } else {
                        self.b.ins().f32const(9223372036854775808.0)
                    };
                    let big = self.b.ins().fcmp(FloatCC::GreaterThanOrEqual, x, limit);
                    let as_signed = self.b.ins().fcvt_to_sint_sat(types::I64, x);
                    let as_unsigned = self.b.ins().fcvt_to_uint_sat(types::I64, x);
                    self.b.ins().select(big, as_unsigned, as_signed)
                };
                self.set(*d, r);
            }
            FloatToFloat(d, s, from, to) => {
                let from_ty = self.ty(*from);
                let to_ty = self.ty(*to);
                let x = self.get_as(*s, from_ty);
                let r = if from_ty == to_ty {
                    x
                } else if to_ty == types::F64 {
                    self.b.ins().fpromote(to_ty, x)
                } else {
                    self.b.ins().fdemote(to_ty, x)
                };
                self.set(*d, r);
            }
            IntExt(d, s, from, to, signed) => {
                let from_ty = self.ty(*from);
                let to_ty = self.ty(*to);
                let x = self.get_as(*s, from_ty);
                let r = if from_ty.bits() >= to_ty.bits() {
                    self.coerce(x, to_ty)
                } else if *signed {
                    self.b.ins().sextend(to_ty, x)
                } else {
                    self.b.ins().uextend(to_ty, x)
                };
                self.set(*d, r);
            }
            IntTrunc(d, s, from, to) => {
                let from_ty = self.ty(*from);
                let to_ty = self.ty(*to);
                let x = self.get_as(*s, from_ty);
                let r = self.coerce(x, to_ty);
                self.set(*d, r);
            }
            Load(d, addr, t) => {
                let r = if let Some(var) = self.promoted.get(&addr.0) {
                    self.b.use_var(*var)
                } else {
                    let ty = self.ty(*t);
                    let ptr = self.cg.ptr;
                    let a = self.get_as(*addr, ptr);
                    self.b.ins().load(ty, flags(), a, 0)
                };
                self.set(*d, r);
            }
            Store(addr, value, t) => {
                let ty = self.ty(*t);
                let x = self.get_as(*value, ty);
                if let Some(var) = self.promoted.get(&addr.0) {
                    self.b.def_var(*var, x);
                } else {
                    let ptr = self.cg.ptr;
                    let a = self.get_as(*addr, ptr);
                    self.b.ins().store(flags(), x, a, 0);
                }
            }
            MemCopy { dst, src, size } => {
                if *size == 0 {
                    return;
                }
                let ptr = self.cg.ptr;
                let dst = self.get_as(*dst, ptr);
                let src = self.get_as(*src, ptr);
                let config = self.cg.module.target_config();
                // Small copies load everything before storing, larger ones
                // call memmove: source and destination may overlap.
                self.b
                    .emit_small_memory_copy(config, dst, src, *size, 1, 1, false, flags());
            }
            SlotAddr(d, slot) => {
                if self.promoted.contains_key(&d.0) {
                    return;
                }
                let ss = self.stack_slots[&slot.0];
                let ptr = self.cg.ptr;
                let r = self.b.ins().stack_addr(ptr, ss, 0);
                self.set(*d, r);
            }
            MemberPtr(d, base, offset) => {
                let ptr = self.cg.ptr;
                let x = self.get_as(*base, ptr);
                let r = self.b.ins().iadd_imm_u(x, *offset as i64);
                self.set(*d, r);
            }
            IndexPtr(d, base, index, size) => {
                let ptr = self.cg.ptr;
                let x = self.get_as(*base, ptr);
                let i = self.get_as(*index, ptr);
                let scaled = self.b.ins().imul_imm_u(i, *size as i64);
                let r = self.b.ins().iadd(x, scaled);
                self.set(*d, r);
            }
            Call { dst, func, args } => self.call(*dst, func, args),
            CallIndirect { dst, callee, args } => {
                let mut sig = Signature::new(self.cg.call_conv);
                let mut values = Vec::new();
                for (v, ty) in args {
                    let t = self.ty(*ty);
                    sig.params.push(AbiParam::new(t));
                    values.push(self.get_as(*v, t));
                }
                if let Some((_, ty)) = dst {
                    sig.returns.push(AbiParam::new(self.ty(*ty)));
                }
                let sig = self.b.import_signature(sig);
                let ptr = self.cg.ptr;
                let target = self.get_as(*callee, ptr);
                let call = self.b.ins().call_indirect(sig, target, &values);
                if let Some((d, _)) = dst {
                    let r = self.b.inst_results(call)[0];
                    self.set(*d, r);
                }
            }
            Mov(d, s) => {
                let r = self.get(*s);
                self.set(*d, r);
            }
            FuncAddr(d, name) => {
                let id = self.cg.funcs[name].id;
                let r = self.func_ref(id);
                let ptr = self.cg.ptr;
                let addr = self.b.ins().func_addr(ptr, r);
                self.set(*d, addr);
            }
        }
    }

    fn call(&mut self, dst: Option<(VReg, IRType)>, func: &str, args: &[(VReg, IRType)]) {
        if func == IPOW {
            let id = self.cg.ipow.expect("ipow declared");
            let r = self.func_ref(id);
            let x = self.get_as(args[0].0, types::I64);
            let y = self.get_as(args[1].0, types::I64);
            let call = self.b.ins().call(r, &[x, y]);
            if let Some((d, _)) = dst {
                let result = self.b.inst_results(call)[0];
                self.set(d, result);
            }
            return;
        }
        let decl = self.cg.funcs[func].clone();
        if decl.is_extern && !decl.is_variadic && args.len() != decl.params.len() {
            // The lowering passes compound results through a hidden pointer,
            // which C functions do not take.
            self.unsupported = Some(format!(
                "calling C function '{}' with a struct result is not supported yet",
                func
            ));
            self.b.ins().trap(ir::TrapCode::unwrap_user(1));
            let dead = self.b.create_block();
            self.b.switch_to_block(dead);
            if let Some((d, ty)) = dst {
                let t = self.ty(ty);
                let zero = self.zero(t);
                self.set(d, zero);
            }
            return;
        }
        let call = if decl.is_variadic {
            self.variadic_call(func, &decl, args)
        } else {
            let r = self.func_ref(decl.id);
            let mut values = Vec::new();
            for (index, (v, ty)) in args.iter().enumerate() {
                let t = self.ty(decl.params.get(index).copied().unwrap_or(*ty));
                values.push(self.get_as(*v, t));
            }
            self.b.ins().call(r, &values)
        };
        if let Some((d, ty)) = dst {
            let results = self.b.inst_results(call).to_vec();
            let r = match results.first() {
                Some(r) => *r,
                None => {
                    let t = self.ty(ty);
                    self.zero(t)
                }
            };
            self.set(d, r);
        }
    }

    // See the module comment for the two conventions handled here.
    fn variadic_call(&mut self, func: &str, decl: &FuncDecl, args: &[(VReg, IRType)]) -> ir::Inst {
        let mut sig = Signature::new(self.cg.call_conv);
        let mut values = Vec::new();
        let (fixed, rest) = args.split_at(decl.params.len());
        for ((v, _), ty) in fixed.iter().zip(&decl.params) {
            let t = self.ty(*ty);
            sig.params.push(self.cg.abi_param(*ty, true));
            values.push(self.get_as(*v, t));
        }
        if self.cg.target == Target::MacosAarch64 && !rest.is_empty() {
            let ints = decl.params.iter().filter(|t| !t.is_float()).count();
            let floats = decl.params.len() - ints;
            for _ in ints.min(8)..8 {
                sig.params.push(AbiParam::new(types::I64));
                values.push(self.b.ins().iconst(types::I64, 0));
            }
            for _ in floats.min(8)..8 {
                sig.params.push(AbiParam::new(types::F64));
                values.push(self.b.ins().f64const(0.0));
            }
        }
        for (v, ty) in rest {
            let t = if ty.is_float() {
                types::F64
            } else {
                types::I64
            };
            let value = self.get(*v);
            let value = if ty.is_float() {
                let value = self.coerce(value, self.cg.clif_type(*ty));
                if *ty == IRType::F32 {
                    self.b.ins().fpromote(types::F64, value)
                } else {
                    value
                }
            } else {
                self.coerce(value, t)
            };
            sig.params.push(AbiParam::new(t));
            values.push(value);
        }
        if let Some(ty) = decl.ret {
            sig.returns.push(self.cg.abi_param(ty, true));
        }
        let (target, colocated) = match self.cg.va_thunks.get(func) {
            Some(thunk) => (*thunk, true),
            None => (decl.id, false),
        };
        let sig = self.b.import_signature(sig);
        let name = self
            .b
            .func
            .declare_imported_user_function(UserExternalName {
                namespace: 0,
                index: target.as_u32(),
            });
        let r = self.b.import_function(ExtFuncData {
            name: ExternalName::user(name),
            signature: sig,
            colocated,
            patchable: false,
        });
        self.b.ins().call(r, &values)
    }
}

enum ShiftKind {
    Shl,
    Ushr,
    Sshr,
}

// __ipow(base, exp): exponentiation by squaring on 64-bit integers.
fn build_ipow(
    func: &mut ir::Function,
    builder_ctx: &mut FunctionBuilderContext,
    config: cranelift_codegen::isa::TargetFrontendConfig,
) {
    let mut b = FunctionBuilder::new(func, builder_ctx);
    let entry = b.create_block();
    let header = b.create_block();
    let body = b.create_block();
    let done = b.create_block();
    b.append_block_params_for_function_params(entry);
    let result = b.declare_var(types::I64);
    let base = b.declare_var(types::I64);
    let exp = b.declare_var(types::I64);

    b.switch_to_block(entry);
    let params = b.block_params(entry).to_vec();
    let one = b.ins().iconst(types::I64, 1);
    b.def_var(result, one);
    b.def_var(base, params[0]);
    b.def_var(exp, params[1]);
    b.ins().jump(header, &[]);

    b.switch_to_block(header);
    let e = b.use_var(exp);
    b.ins().brif(e, body, &[], done, &[]);

    b.switch_to_block(body);
    let e = b.use_var(exp);
    let x = b.use_var(base);
    let r = b.use_var(result);
    let odd = b.ins().band_imm_u(e, 1);
    let times = b.ins().imul(r, x);
    let r = b.ins().select(odd, times, r);
    b.def_var(result, r);
    let x = b.ins().imul(x, x);
    b.def_var(base, x);
    let e = b.ins().ushr_imm_u(e, 1);
    b.def_var(exp, e);
    b.ins().jump(header, &[]);

    b.switch_to_block(done);
    let r = b.use_var(result);
    b.ins().return_(&[r]);

    b.seal_all_blocks();
    b.finalize(config);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn function(slots: usize, instructions: Vec<Inst>) -> IRFunction {
        IRFunction {
            name: "f".into(),
            params: vec![],
            return_ir: None,
            slots: (0..slots).map(|_| SlotInfo { size: 8, align: 8 }).collect(),
            blocks: vec![BasicBlock {
                id: BlockId(0),
                instructions,
                teminator: Term::Ret(None),
            }],
            vreg_counter: 16,
            is_extern: false,
            is_variadic: false,
        }
    }

    #[test]
    fn promotes_whole_slot_scalar_access() {
        let f = function(
            1,
            vec![
                Inst::SlotAddr(VReg(0), Slot(0)),
                Inst::ConstInt(VReg(1), 5, IRType::I64),
                Inst::Store(VReg(0), VReg(1), IRType::I64),
                Inst::Load(VReg(2), VReg(0), IRType::I64),
            ],
        );
        assert_eq!(promotable_slots(&f).get(&0), Some(&(0, IRType::I64)));
    }

    #[test]
    fn escaping_address_is_not_promoted() {
        let f = function(
            1,
            vec![
                Inst::SlotAddr(VReg(0), Slot(0)),
                Inst::Call {
                    dst: None,
                    func: "g".into(),
                    args: vec![(VReg(0), IRType::Ptr)],
                },
                Inst::Load(VReg(1), VReg(0), IRType::I64),
            ],
        );
        assert!(promotable_slots(&f).is_empty());
    }

    #[test]
    fn address_stored_as_a_value_escapes() {
        let f = function(
            2,
            vec![
                Inst::SlotAddr(VReg(0), Slot(0)),
                Inst::SlotAddr(VReg(1), Slot(1)),
                Inst::Store(VReg(1), VReg(0), IRType::Ptr),
            ],
        );
        let promoted = promotable_slots(&f);
        assert!(!promoted.contains_key(&0), "slot 0's address escapes");
        assert!(promoted.contains_key(&1), "slot 1 only holds a value");
    }

    #[test]
    fn partial_or_mixed_access_is_not_promoted() {
        let f = function(
            2,
            vec![
                Inst::SlotAddr(VReg(0), Slot(0)),
                Inst::Load(VReg(1), VReg(0), IRType::I32),
                Inst::SlotAddr(VReg(2), Slot(1)),
                Inst::Load(VReg(3), VReg(2), IRType::I64),
                Inst::Load(VReg(4), VReg(2), IRType::F64),
                Inst::MemberPtr(VReg(5), VReg(2), 0),
            ],
        );
        assert!(promotable_slots(&f).is_empty());
    }
}
