use std::collections::HashMap;
use std::fmt;

use crate::parser::*;
use crate::typechecker::*;

// IR types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum IRType {
    I8,
    I16,
    I32,
    I64,
    F32,
    F64,
    Ptr,
}

impl IRType {
    pub fn size(self) -> u64 {
        match self {
            IRType::I8 => 1,
            IRType::I16 => 2,
            IRType::I32 | IRType::F32 => 4,
            IRType::I64 | IRType::F64 | IRType::Ptr => 8,
        }
    }
    pub fn is_float(self) -> bool {
        matches!(self, IRType::F32 | IRType::F64)
    }
    pub fn is_integer(self) -> bool {
        matches!(self, IRType::I8 | IRType::I16 | IRType::I32 | IRType::I64)
    }
}

impl fmt::Display for IRType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            IRType::I8 => write!(f, "i8"),
            IRType::I16 => write!(f, "i16"),
            IRType::I32 => write!(f, "i32"),
            IRType::I64 => write!(f, "i64"),
            IRType::F32 => write!(f, "f32"),
            IRType::F64 => write!(f, "f64"),
            IRType::Ptr => write!(f, "ptr"),
        }
    }
}

// VReg, Slot, BlockId
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct VReg(pub u32);

impl fmt::Display for VReg {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "v{}", self.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Slot(pub u32);

impl fmt::Display for Slot {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "slot{}", self.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct BlockId(pub u32);

impl fmt::Display for BlockId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "bb{}", self.0)
    }
}

#[derive(Debug, Clone)]
pub struct SlotInfo {
    pub size: u64,
    pub align: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CmpOp {
    Eq,
    Neq,
    Lt,
    Gt,
    LtEq,
    GtEq,
}

impl fmt::Display for CmpOp {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CmpOp::Eq => write!(f, "eq"),
            CmpOp::Neq => write!(f, "neq"),
            CmpOp::Lt => write!(f, "lt"),
            CmpOp::Gt => write!(f, "gt"),
            CmpOp::LtEq => write!(f, "le"),
            CmpOp::GtEq => write!(f, "ge"),
        }
    }
}

// Instructions
#[derive(Debug, Clone)]
pub enum Inst {
    IAdd(VReg, VReg, VReg, IRType),
    ISub(VReg, VReg, VReg, IRType),
    IMul(VReg, VReg, VReg, IRType),
    IDiv(VReg, VReg, VReg, IRType, bool),
    IMod(VReg, VReg, VReg, IRType, bool),
    IShl(VReg, VReg, VReg, IRType),
    IShr(VReg, VReg, VReg, IRType, bool),
    INeg(VReg, VReg, IRType),
    IBitAnd(VReg, VReg, VReg, IRType),
    IBitOr(VReg, VReg, VReg, IRType),
    IBitXor(VReg, VReg, VReg, IRType),
    IBitNot(VReg, VReg, IRType),

    FAdd(VReg, VReg, VReg, IRType),
    FSub(VReg, VReg, VReg, IRType),
    FMul(VReg, VReg, VReg, IRType),
    FDiv(VReg, VReg, VReg, IRType),
    FNeg(VReg, VReg, IRType),

    ICmp(VReg, CmpOp, VReg, VReg, IRType, bool),
    FCmp(VReg, CmpOp, VReg, VReg, IRType),
    BoolNot(VReg, VReg),

    ConstInt(VReg, i64, IRType),
    ConstFloat(VReg, f64, IRType),
    ConstStringPtr(VReg, usize),

    IntToFloat(VReg, VReg, IRType, IRType, bool),
    FloatToInt(VReg, VReg, IRType, IRType, bool),
    FloatToFloat(VReg, VReg, IRType, IRType),
    IntExt(VReg, VReg, IRType, IRType, bool),
    IntTrunc(VReg, VReg, IRType, IRType),

    Load(VReg, VReg, IRType),
    Store(VReg, VReg, IRType),
    MemCopy {
        dst: VReg,
        src: VReg,
        size: u64,
    },

    SlotAddr(VReg, Slot),
    // Address of IrProgram::globals[index]
    GlobalAddr(VReg, usize),
    MemberPtr(VReg, VReg, u64),
    IndexPtr(VReg, VReg, VReg, u64),

    Call {
        dst: Option<(VReg, IRType)>,
        func: String,
        args: Vec<(VReg, IRType)>,
    },
    CallIndirect {
        dst: Option<(VReg, IRType)>,
        callee: VReg,
        args: Vec<(VReg, IRType)>,
    },
    Mov(VReg, VReg),
    // Address of a function, for use as a function pointer
    FuncAddr(VReg, String),
}

// Terminators
#[derive(Debug, Clone)]
pub enum Term {
    Ret(Option<(VReg, IRType)>),
    Jump(BlockId),
    CondBr {
        cond: VReg,
        then_bb: BlockId,
        else_bb: BlockId,
    },
}

// Structures
#[derive(Debug, Clone)]
pub struct BasicBlock {
    pub id: BlockId,
    pub instructions: Vec<Inst>,
    pub teminator: Term,
}

#[derive(Debug, Clone)]
pub struct IRFunction {
    pub name: String,
    pub params: Vec<(VReg, IRType)>,
    pub return_ir: Option<IRType>,
    pub slots: Vec<SlotInfo>,
    pub blocks: Vec<BasicBlock>,
    pub vreg_counter: u32,
    pub is_extern: bool,
    // C variadic (`...`) extern: arguments past `params` follow the
    // platform's variadic calling convention.
    pub is_variadic: bool,
}

#[derive(Debug, Clone)]
pub struct StringConstant {
    pub label: String,
    pub bytes: Vec<u8>,
}

// A `static`: its initial bytes, laid out for the target.
#[derive(Debug, Clone)]
pub struct GlobalData {
    pub name: String,
    pub bytes: Vec<u8>,
    pub align: u64,
    pub mutable: bool,
}

#[derive(Debug, Clone)]
pub struct IrProgram {
    pub functions: Vec<IRFunction>,
    pub strings: Vec<StringConstant>,
    pub globals: Vec<GlobalData>,
}

// Layout
#[derive(Debug, Clone, Copy)]
pub struct Layout {
    pub size: u64,
    pub align: u64,
}

fn align_to(offset: u64, align: u64) -> u64 {
    (offset + align - 1) & !(align - 1)
}

pub fn layout_of(ty: &TypeInternal, structs: &HashMap<String, StructInfo>) -> Layout {
    match ty {
        TypeInternal::I8 | TypeInternal::U8 | TypeInternal::Bool => Layout { size: 1, align: 1 },
        TypeInternal::I16 | TypeInternal::U16 => Layout { size: 2, align: 2 },
        TypeInternal::I32 | TypeInternal::U32 | TypeInternal::F32 => Layout { size: 4, align: 4 },
        TypeInternal::I64 | TypeInternal::U64 | TypeInternal::F64 => Layout { size: 8, align: 8 },
        TypeInternal::Pointer(_) | TypeInternal::Fn { .. } => Layout { size: 8, align: 8 },
        TypeInternal::Unit | TypeInternal::Never => Layout { size: 0, align: 1 },
        TypeInternal::Tuple(es) => compound_layout(es.iter(), structs),
        TypeInternal::Array(e, n) => {
            let el = layout_of(e, structs);
            Layout {
                size: el.size * n,
                align: el.align,
            }
        }
        TypeInternal::Struct(name) => {
            let info = &structs[name];
            compound_layout(info.fields.iter().map(|(_, t)| t), structs)
        }
    }
}

fn compound_layout<'a>(
    fields: impl Iterator<Item = &'a TypeInternal>,
    structs: &HashMap<String, StructInfo>,
) -> Layout {
    let mut offset: u64 = 0;
    let mut max_align: u64 = 1;
    for fty in fields {
        let fl = layout_of(fty, structs);
        max_align = max_align.max(fl.align);
        offset = align_to(offset, fl.align) + fl.size;
    }
    Layout {
        size: align_to(offset, max_align),
        align: max_align,
    }
}

pub fn field_offsets(
    fields: &[TypeInternal],
    structs: &HashMap<String, StructInfo>,
) -> Vec<(u64, Layout)> {
    let mut offset: u64 = 0;
    let mut result = Vec::new();
    for fty in fields {
        let fl = layout_of(fty, structs);
        offset = align_to(offset, fl.align);
        result.push((offset, fl));
        offset += fl.size;
    }
    result
}

pub fn type_internal_to_ir(ty: &TypeInternal) -> Option<IRType> {
    match ty {
        TypeInternal::I8 | TypeInternal::U8 | TypeInternal::Bool => Some(IRType::I8),
        TypeInternal::I16 | TypeInternal::U16 => Some(IRType::I16),
        TypeInternal::I32 | TypeInternal::U32 => Some(IRType::I32),
        TypeInternal::I64 | TypeInternal::U64 => Some(IRType::I64),
        TypeInternal::F32 => Some(IRType::F32),
        TypeInternal::F64 => Some(IRType::F64),
        TypeInternal::Pointer(_) | TypeInternal::Fn { .. } => Some(IRType::Ptr),
        _ => None,
    }
}

fn is_scalar(ty: &TypeInternal) -> bool {
    type_internal_to_ir(ty).is_some()
}
fn is_compound(ty: &TypeInternal) -> bool {
    matches!(
        ty,
        TypeInternal::Struct(_) | TypeInternal::Tuple(_) | TypeInternal::Array(_, _)
    )
}
// Types without a runtime value.
fn is_void(ty: &TypeInternal) -> bool {
    matches!(ty, TypeInternal::Unit | TypeInternal::Never)
}

// A loop that `break`/`continue` can target.
struct LoopTarget {
    label: Option<String>,
    continue_bb: BlockId,
    break_bb: BlockId,
    // Where `break value` stores the loop's value.
    result: Option<(VReg, TypeInternal)>,
}

// Lowering context
struct Lowerer<'a> {
    checked: &'a CheckedProgram,
    blocks: Vec<BasicBlock>,
    cur_insts: Vec<Inst>,
    cur_bb: BlockId,
    slots: Vec<SlotInfo>,
    vreg_n: u32,
    bb_n: u32,
    // Every local lives in memory: its address and type.
    scopes: Vec<HashMap<String, (VReg, TypeInternal)>>,
    return_ty: TypeInternal,
    // Hidden pointer to the caller's result slot for compound returns
    sret: Option<VReg>,
    loop_stack: Vec<LoopTarget>,
    strings: Vec<StringConstant>,
    globals: Vec<GlobalData>,
    global_index: HashMap<String, usize>,
}

impl<'a> Lowerer<'a> {
    fn new(checked: &'a CheckedProgram) -> Self {
        Self {
            checked,
            blocks: Vec::new(),
            cur_insts: Vec::new(),
            cur_bb: BlockId(0),
            slots: Vec::new(),
            vreg_n: 0,
            bb_n: 0,
            scopes: vec![HashMap::new()],
            return_ty: TypeInternal::Unit,
            sret: None,
            loop_stack: Vec::new(),
            strings: Vec::new(),
            globals: Vec::new(),
            global_index: HashMap::new(),
        }
    }

    fn fresh_vreg(&mut self) -> VReg {
        let v = VReg(self.vreg_n);
        self.vreg_n += 1;
        v
    }
    fn fresh_bb(&mut self) -> BlockId {
        let b = BlockId(self.bb_n);
        self.bb_n += 1;
        b
    }
    fn alloc_slot(&mut self, size: u64, align: u64) -> Slot {
        let s = Slot(self.slots.len() as u32);
        self.slots.push(SlotInfo { size, align });
        s
    }
    fn alloc_slot_for(&mut self, ty: &TypeInternal) -> Slot {
        let l = layout_of(ty, &self.checked.structs);
        self.alloc_slot(l.size, l.align)
    }
    // A fresh stack slot for a value of `ty`, and its address.
    fn temp_for(&mut self, ty: &TypeInternal) -> VReg {
        let slot = self.alloc_slot_for(ty);
        let addr = self.fresh_vreg();
        self.emit(Inst::SlotAddr(addr, slot));
        addr
    }
    fn emit(&mut self, i: Inst) {
        self.cur_insts.push(i);
    }
    fn seal(&mut self, t: Term) {
        self.blocks.push(BasicBlock {
            id: self.cur_bb,
            instructions: std::mem::take(&mut self.cur_insts),
            teminator: t,
        });
    }
    fn start(&mut self, id: BlockId) {
        self.cur_bb = id;
        self.cur_insts = Vec::new();
    }
    // Ends the current block with `t` and continues in a fresh block that
    // nothing jumps to (code after `return`, `break`, ...).
    fn seal_and_start_dead(&mut self, t: Term) {
        self.seal(t);
        let dead = self.fresh_bb();
        self.start(dead);
    }
    fn push_scope(&mut self) {
        self.scopes.push(HashMap::new());
    }
    fn pop_scope(&mut self) {
        self.scopes.pop();
    }
    fn define(&mut self, name: String, addr: VReg, ty: TypeInternal) {
        self.scopes.last_mut().unwrap().insert(name, (addr, ty));
    }
    fn lookup_local(&self, name: &str) -> Option<&(VReg, TypeInternal)> {
        self.scopes.iter().rev().find_map(|s| s.get(name))
    }
    // The storage of a variable or static: its address and type. Constants
    // and functions have none.
    fn ident_place(&mut self, name: &str) -> Option<(VReg, TypeInternal)> {
        if let Some(place) = self.lookup_local(name) {
            return Some(place.clone());
        }
        let index = *self.global_index.get(name)?;
        let addr = self.fresh_vreg();
        self.emit(Inst::GlobalAddr(addr, index));
        Some((addr, self.checked.statics[name].ty.clone()))
    }
    fn const_zero(&mut self) -> VReg {
        let v = self.fresh_vreg();
        self.emit(Inst::ConstInt(v, 0, IRType::I8));
        v
    }
    // A placeholder value of type `ty` for code that is never reached.
    fn dummy(&mut self, ty: &TypeInternal) -> VReg {
        match type_internal_to_ir(ty) {
            Some(ir) if ir.is_float() => {
                let v = self.fresh_vreg();
                self.emit(Inst::ConstFloat(v, 0.0, ir));
                v
            }
            Some(ir) => {
                let v = self.fresh_vreg();
                self.emit(Inst::ConstInt(v, 0, ir));
                v
            }
            None if is_compound(ty) => self.temp_for(ty),
            None => self.const_zero(),
        }
    }

    // The type the checker gave the expression in its context.
    fn expr_ty(&self, expr: &Expr) -> TypeInternal {
        self.checked.type_of(expr).clone()
    }

    fn diverges(&self, expr: &Expr) -> bool {
        self.checked.diverges(expr)
    }

    fn struct_field_offset(&self, ty: &TypeInternal, field: &str) -> (u64, TypeInternal) {
        let s = if let TypeInternal::Struct(s) = ty {
            s
        } else {
            panic!("ICE")
        };
        let info = &self.checked.structs[s];
        let ftys: Vec<TypeInternal> = info.fields.iter().map(|(_, t)| t.clone()).collect();
        let offs = field_offsets(&ftys, &self.checked.structs);
        let idx = info.fields.iter().position(|(n, _)| n == field).unwrap();
        (offs[idx].0, ftys[idx].clone())
    }

    fn tuple_field_offset(&self, ty: &TypeInternal, idx: usize) -> (u64, TypeInternal) {
        let es = if let TypeInternal::Tuple(es) = ty {
            es
        } else {
            panic!("ICE")
        };
        let offs = field_offsets(es, &self.checked.structs);
        (offs[idx].0, es[idx].clone())
    }

    // The function a call names directly; a local of the same name shadows
    // the function and makes the call indirect.
    fn direct_callee(&self, callee: &Expr) -> Option<&'a FnSig> {
        match &callee.kind {
            ExprKind::Ident(n) if self.lookup_local(n).is_none() => self.checked.functions.get(n),
            _ => None,
        }
    }

    fn call_return_ty(&self, callee: &Expr) -> TypeInternal {
        if let Some(sig) = self.direct_callee(callee) {
            return sig.return_ty.clone();
        }
        if let TypeInternal::Fn { result, .. } = self.expr_ty(callee) {
            *result
        } else {
            panic!("ICE")
        }
    }

    fn is_variadic_call(&self, callee: &Expr) -> bool {
        self.direct_callee(callee)
            .is_some_and(|sig| sig.is_variadic)
    }

    fn call_param_tys(&self, callee: &Expr) -> Vec<TypeInternal> {
        if let Some(sig) = self.direct_callee(callee) {
            return sig.params.iter().map(|(_, t)| t.clone()).collect();
        }
        if let TypeInternal::Fn { params, .. } = self.expr_ty(callee) {
            params
        } else {
            panic!("ICE")
        }
    }

    // Top-level
    fn lower_program(&mut self, program: &Program) -> IrProgram {
        // Statics first, so functions can refer to them.
        for item in &program.items {
            if let Item::Static(sd) = item {
                let info = &self.checked.statics[&sd.name.0];
                let layout = layout_of(&info.ty, &self.checked.structs);
                let mut bytes = vec![0u8; layout.size as usize];
                self.write_const(&info.value, &info.ty, &mut bytes, 0);
                self.global_index
                    .insert(sd.name.0.clone(), self.globals.len());
                self.globals.push(GlobalData {
                    name: sd.name.0.clone(),
                    bytes,
                    align: layout.align,
                    mutable: info.mutable,
                });
            }
        }
        let mut functions = Vec::new();
        for item in &program.items {
            match item {
                Item::Function(fd) => functions.push(self.lower_function(fd)),
                Item::Extern(ed) => {
                    let signature = &self.checked.functions[&ed.name.0];
                    let params: Vec<_> = signature
                        .params
                        .iter()
                        .map(|(_, ty)| (VReg(0), type_internal_to_ir(ty).unwrap_or(IRType::Ptr)))
                        .collect();
                    functions.push(IRFunction {
                        name: ed.name.0.clone(),
                        params,
                        return_ir: type_internal_to_ir(&signature.return_ty),
                        slots: vec![],
                        blocks: vec![],
                        vreg_counter: 0,
                        is_extern: true,
                        is_variadic: signature.is_variadic,
                    });
                }
                _ => {}
            }
        }
        IrProgram {
            functions,
            strings: std::mem::take(&mut self.strings),
            globals: std::mem::take(&mut self.globals),
        }
    }

    // Stores a constant's bytes (little-endian) at `offset` of `out`.
    fn write_const(&self, value: &ConstValue, ty: &TypeInternal, out: &mut [u8], offset: usize) {
        let size = layout_of(ty, &self.checked.structs).size as usize;
        match value {
            ConstValue::Int(v) => {
                out[offset..offset + size].copy_from_slice(&(*v as u128).to_le_bytes()[..size]);
            }
            ConstValue::Float(f) => {
                if *ty == TypeInternal::F32 {
                    out[offset..offset + 4].copy_from_slice(&(*f as f32).to_le_bytes());
                } else {
                    out[offset..offset + 8].copy_from_slice(&f.to_le_bytes());
                }
            }
            ConstValue::Bool(b) => out[offset] = *b as u8,
            ConstValue::Aggregate(values) => {
                let elem_tys: Vec<TypeInternal> = match ty {
                    TypeInternal::Array(elem, n) => vec![(**elem).clone(); *n as usize],
                    TypeInternal::Tuple(elems) => elems.clone(),
                    TypeInternal::Struct(name) => self.checked.structs[name]
                        .fields
                        .iter()
                        .map(|(_, t)| t.clone())
                        .collect(),
                    _ => Vec::new(),
                };
                let offsets = field_offsets(&elem_tys, &self.checked.structs);
                for ((v, t), (off, _)) in values.iter().zip(&elem_tys).zip(&offsets) {
                    self.write_const(v, t, out, offset + *off as usize);
                }
            }
        }
    }

    fn lower_function(&mut self, fd: &FunctionDecl) -> IRFunction {
        let sig = self.checked.functions[&fd.name.0].clone();
        self.blocks.clear();
        self.cur_insts.clear();
        self.slots.clear();
        self.vreg_n = 0;
        self.bb_n = 0;
        self.scopes = vec![HashMap::new()];
        self.return_ty = sig.return_ty.clone();
        self.sret = None;
        self.loop_stack.clear();

        let entry = self.fresh_bb();
        self.start(entry);

        let mut ir_params = Vec::new();
        // Compound results are written through a hidden first argument
        // pointing at a slot in the caller's frame (SysV "sret").
        if is_compound(&sig.return_ty) {
            let v = self.fresh_vreg();
            ir_params.push((v, IRType::Ptr));
            self.sret = Some(v);
        }
        for (pname, pty) in &sig.params {
            // Parameters live in slots, like every local.
            let addr = self.temp_for(pty);
            let v = self.fresh_vreg();
            if is_scalar(pty) {
                let ir = type_internal_to_ir(pty).unwrap();
                ir_params.push((v, ir));
                self.emit(Inst::Store(addr, v, ir));
            } else {
                ir_params.push((v, IRType::Ptr));
                let size = layout_of(pty, &self.checked.structs).size;
                self.emit(Inst::MemCopy {
                    dst: addr,
                    src: v,
                    size,
                });
            }
            if pname != "_" {
                self.define(pname.clone(), addr, pty.clone());
            }
        }

        let ret = sig.return_ty.clone();
        self.push_scope();
        let diverged = self.lower_stmts(&fd.body);
        match &fd.body.expr {
            Some(tail) if !diverged => {
                if is_void(&ret) {
                    self.lower_expr_discard(tail);
                    self.seal(Term::Ret(None));
                } else if is_scalar(&ret) {
                    let v = self.lower_expr_to_operand(tail, &ret);
                    let ir = type_internal_to_ir(&ret).unwrap();
                    self.seal(Term::Ret(Some((v, ir))));
                } else {
                    let addr = self.sret.expect("ICE: compound return without sret");
                    self.lower_expr_to_addr(tail, addr, &ret);
                    self.seal(Term::Ret(Some((addr, IRType::Ptr))));
                }
            }
            _ => self.seal(Term::Ret(None)),
        }
        self.pop_scope();

        IRFunction {
            name: fd.name.0.clone(),
            params: ir_params,
            return_ir: type_internal_to_ir(&sig.return_ty),
            slots: std::mem::take(&mut self.slots),
            blocks: std::mem::take(&mut self.blocks),
            vreg_counter: self.vreg_n,
            is_extern: false,
            is_variadic: false,
        }
    }

    // ---- Blocks and statements ----

    // Lowers the block's statements in the current scope; stops after one
    // that diverges (the rest is unreachable) and returns whether it did.
    fn lower_stmts(&mut self, block: &Block) -> bool {
        for stmt in &block.stmts {
            self.lower_stmt(stmt);
            let diverges = match stmt {
                Stmt::Let(ls) => self.diverges(&ls.init),
                Stmt::Expr(es) => self.diverges(&es.expr),
            };
            if diverges {
                return true;
            }
        }
        false
    }

    fn lower_block_value(&mut self, block: &Block, expected: &TypeInternal) -> VReg {
        self.push_scope();
        let diverged = self.lower_stmts(block);
        let v = match &block.expr {
            Some(tail) if !diverged => self.lower_expr_to_operand(tail, expected),
            _ => self.dummy(expected),
        };
        self.pop_scope();
        v
    }

    fn lower_block_to_addr(&mut self, block: &Block, dst: VReg, ty: &TypeInternal) {
        self.push_scope();
        if !self.lower_stmts(block)
            && let Some(tail) = &block.expr
        {
            self.lower_expr_to_addr(tail, dst, ty);
        }
        self.pop_scope();
    }

    fn lower_block_discard(&mut self, block: &Block) {
        self.push_scope();
        if !self.lower_stmts(block)
            && let Some(tail) = &block.expr
        {
            self.lower_expr_discard(tail);
        }
        self.pop_scope();
    }

    fn lower_stmt(&mut self, stmt: &Stmt) {
        match stmt {
            Stmt::Let(ls) => self.lower_let(ls),
            Stmt::Expr(es) => self.lower_expr_discard(&es.expr),
        }
    }

    // Every binding gets its own stack slot, even scalars: assignments in
    // loops and branches then update the canonical location, and reads in
    // other blocks see the latest value.
    fn lower_let(&mut self, ls: &LetStmt) {
        let ty = self.expr_ty(&ls.init);
        match &ls.pattern.kind {
            PatternKind::Wildcard => self.lower_expr_discard(&ls.init),
            PatternKind::Binding { name, .. } => {
                let addr = self.temp_for(&ty);
                self.store_or_recurse(&ls.init, addr, &ty);
                self.define(name.clone(), addr, ty);
            }
            PatternKind::Tuple(_) => {
                // Destructure a private copy of the value.
                let addr = self.temp_for(&ty);
                self.lower_expr_to_addr(&ls.init, addr, &ty);
                self.bind_pattern_at(&ls.pattern, addr, &ty);
            }
        }
    }

    // Binds the names in `pattern` to the parts of the value at `addr`.
    fn bind_pattern_at(&mut self, pattern: &Pattern, addr: VReg, ty: &TypeInternal) {
        match &pattern.kind {
            PatternKind::Wildcard => {}
            PatternKind::Binding { name, .. } => self.define(name.clone(), addr, ty.clone()),
            PatternKind::Tuple(pats) => {
                let TypeInternal::Tuple(elems) = ty else {
                    return;
                };
                let offsets = field_offsets(elems, &self.checked.structs);
                for ((p, t), (off, _)) in pats.iter().zip(elems).zip(&offsets) {
                    let ptr = self.fresh_vreg();
                    self.emit(Inst::MemberPtr(ptr, addr, *off));
                    self.bind_pattern_at(p, ptr, t);
                }
            }
        }
    }

    fn lower_assign(&mut self, op: AssignOp, target: &Expr, value: &Expr) {
        let tgt_ty = self.expr_ty(target);
        let addr = self.expr_addr_of(target, &tgt_ty);
        let Some(bop) = op.binop() else {
            if is_scalar(&tgt_ty) {
                let v = self.lower_expr_to_operand(value, &tgt_ty);
                self.emit(Inst::Store(addr, v, type_internal_to_ir(&tgt_ty).unwrap()));
            } else if matches!(value.kind, ExprKind::Ident(_) | ExprKind::Call { .. }) {
                self.lower_expr_to_addr(value, addr, &tgt_ty);
            } else {
                // The value may read the target (`p = P { x: p.y, y: p.x }`),
                // so build it aside and copy it over afterwards.
                let tmp = self.expr_addr_of(value, &tgt_ty);
                let size = layout_of(&tgt_ty, &self.checked.structs).size;
                self.emit(Inst::MemCopy {
                    dst: addr,
                    src: tmp,
                    size,
                });
            }
            return;
        };
        let ir = type_internal_to_ir(&tgt_ty).unwrap();
        let old = self.fresh_vreg();
        self.emit(Inst::Load(old, addr, ir));
        let rhs_ty = if matches!(bop, BinOp::Shl | BinOp::Shr) {
            self.expr_ty(value)
        } else {
            tgt_ty.clone()
        };
        let rhs = self.lower_expr_to_operand(value, &rhs_ty);
        let res = self.emit_arith(bop, old, rhs, &tgt_ty);
        self.emit(Inst::Store(addr, res, ir));
    }

    fn lower_return(&mut self, value: Option<&Expr>) {
        let ret_ty = self.return_ty.clone();
        match value {
            Some(e) if is_void(&ret_ty) => {
                self.lower_expr_discard(e);
                self.seal_and_start_dead(Term::Ret(None));
            }
            Some(e) if is_scalar(&ret_ty) => {
                let v = self.lower_expr_to_operand(e, &ret_ty);
                let ir = type_internal_to_ir(&ret_ty).unwrap();
                self.seal_and_start_dead(Term::Ret(Some((v, ir))));
            }
            Some(e) => {
                let addr = self.sret.expect("ICE: compound return without sret");
                self.lower_expr_to_addr(e, addr, &ret_ty);
                self.seal_and_start_dead(Term::Ret(Some((addr, IRType::Ptr))));
            }
            None => self.seal_and_start_dead(Term::Ret(None)),
        }
    }

    fn loop_target(&self, label: &Option<Spanned<String>>) -> usize {
        match label {
            None => self.loop_stack.len() - 1,
            Some((name, _)) => self
                .loop_stack
                .iter()
                .rposition(|l| l.label.as_deref() == Some(name.as_str()))
                .expect("ICE: unknown label"),
        }
    }

    fn lower_break(&mut self, label: &Option<Spanned<String>>, value: Option<&Expr>) {
        let target = self.loop_target(label);
        let result = self.loop_stack[target].result.clone();
        if let Some(v) = value {
            match result {
                Some((addr, ty)) => self.store_or_recurse(v, addr, &ty),
                None => self.lower_expr_discard(v),
            }
        }
        let bb = self.loop_stack[target].break_bb;
        self.seal_and_start_dead(Term::Jump(bb));
    }

    fn lower_continue(&mut self, label: &Option<Spanned<String>>) {
        let target = self.loop_target(label);
        let bb = self.loop_stack[target].continue_bb;
        self.seal_and_start_dead(Term::Jump(bb));
    }

    // `loop { body }`; its value (of type `ty`) comes from `break value`.
    fn lower_loop(
        &mut self,
        label: &Option<Spanned<String>>,
        body: &Block,
        ty: &TypeInternal,
    ) -> VReg {
        let result = if is_void(ty) {
            None
        } else {
            Some((self.temp_for(ty), ty.clone()))
        };
        let header = self.fresh_bb();
        let exit = self.fresh_bb();
        self.seal(Term::Jump(header));
        self.start(header);
        self.loop_stack.push(LoopTarget {
            label: label.as_ref().map(|l| l.0.clone()),
            continue_bb: header,
            break_bb: exit,
            result: result.clone(),
        });
        self.lower_block_discard(body);
        self.loop_stack.pop();
        self.seal(Term::Jump(header));
        self.start(exit);
        match result {
            Some((addr, ty)) if is_scalar(&ty) => {
                let v = self.fresh_vreg();
                self.emit(Inst::Load(v, addr, type_internal_to_ir(&ty).unwrap()));
                v
            }
            Some((addr, _)) => addr,
            None => self.const_zero(),
        }
    }

    fn lower_while(&mut self, label: &Option<Spanned<String>>, cond: &Expr, body: &Block) {
        let header = self.fresh_bb();
        let body_bb = self.fresh_bb();
        let exit = self.fresh_bb();
        self.seal(Term::Jump(header));
        self.start(header);
        let c = self.lower_expr_to_operand(cond, &TypeInternal::Bool);
        self.seal(Term::CondBr {
            cond: c,
            then_bb: body_bb,
            else_bb: exit,
        });
        self.start(body_bb);
        self.loop_stack.push(LoopTarget {
            label: label.as_ref().map(|l| l.0.clone()),
            continue_bb: header,
            break_bb: exit,
            result: None,
        });
        self.lower_block_discard(body);
        self.loop_stack.pop();
        self.seal(Term::Jump(header));
        self.start(exit);
    }

    // `for i in a..b { body }` (or `a..=b`): the bounds are evaluated once;
    // the counter never steps past the end, so `0..=255u8` terminates.
    fn lower_for(
        &mut self,
        label: &Option<Spanned<String>>,
        pattern: &Pattern,
        iter: &Expr,
        body: &Block,
    ) {
        let ExprKind::Range {
            start,
            end,
            inclusive,
        } = &iter.kind
        else {
            panic!("ICE: for over a non-range")
        };
        let elem = self.expr_ty(iter);
        let ir = type_internal_to_ir(&elem).unwrap();
        let signed = elem.is_signed();
        let counter = self.temp_for(&elem);
        let limit = self.temp_for(&elem);
        let s = self.lower_expr_to_operand(start, &elem);
        self.emit(Inst::Store(counter, s, ir));
        let e = self.lower_expr_to_operand(end, &elem);
        self.emit(Inst::Store(limit, e, ir));

        let header = self.fresh_bb();
        let body_bb = self.fresh_bb();
        let latch = self.fresh_bb();
        let exit = self.fresh_bb();
        self.seal(Term::Jump(header));

        self.start(header);
        let i = self.fresh_vreg();
        self.emit(Inst::Load(i, counter, ir));
        let n = self.fresh_vreg();
        self.emit(Inst::Load(n, limit, ir));
        let more = self.fresh_vreg();
        let cmp = if *inclusive { CmpOp::LtEq } else { CmpOp::Lt };
        self.emit(Inst::ICmp(more, cmp, i, n, ir, signed));
        self.seal(Term::CondBr {
            cond: more,
            then_bb: body_bb,
            else_bb: exit,
        });

        self.start(body_bb);
        self.push_scope();
        if let PatternKind::Binding { name, .. } = &pattern.kind {
            // Each iteration binds a copy: changing it does not affect the
            // counter.
            let var = self.temp_for(&elem);
            self.emit(Inst::Store(var, i, ir));
            self.define(name.clone(), var, elem.clone());
        }
        self.loop_stack.push(LoopTarget {
            label: label.as_ref().map(|l| l.0.clone()),
            continue_bb: latch,
            break_bb: exit,
            result: None,
        });
        self.lower_block_discard(body);
        self.loop_stack.pop();
        self.pop_scope();
        self.seal(Term::Jump(latch));

        self.start(latch);
        let cur = self.fresh_vreg();
        self.emit(Inst::Load(cur, counter, ir));
        if *inclusive {
            // Stop at the end instead of stepping past it (it may be the
            // type's maximum).
            let last = self.fresh_vreg();
            self.emit(Inst::Load(last, limit, ir));
            let done = self.fresh_vreg();
            self.emit(Inst::ICmp(done, CmpOp::Eq, cur, last, ir, signed));
            let step_bb = self.fresh_bb();
            self.seal(Term::CondBr {
                cond: done,
                then_bb: exit,
                else_bb: step_bb,
            });
            self.start(step_bb);
        }
        let one = self.fresh_vreg();
        self.emit(Inst::ConstInt(one, 1, ir));
        let next = self.fresh_vreg();
        self.emit(Inst::IAdd(next, cur, one, ir));
        self.emit(Inst::Store(counter, next, ir));
        self.seal(Term::Jump(header));

        self.start(exit);
    }

    // ---- Expressions ----

    // Expr → VReg (scalar or address-of-compound)
    fn lower_expr_to_operand(&mut self, expr: &Expr, expected: &TypeInternal) -> VReg {
        if self.diverges(expr) {
            self.lower_expr_discard(expr);
            return self.dummy(expected);
        }
        if is_void(expected) {
            self.lower_expr_discard(expr);
            return self.const_zero();
        }

        match &expr.kind {
            ExprKind::IntLiteral(_)
            | ExprKind::CharLiteral(_)
            | ExprKind::FloatLiteral(_)
            | ExprKind::SuffixedLiteral(..) => {
                let (int, float) = match expr.kind {
                    ExprKind::IntLiteral(v) | ExprKind::SuffixedLiteral(LitValue::Int(v), _) => {
                        (v as i64, v as f64)
                    }
                    ExprKind::CharLiteral(c) => (c as i64, c as f64),
                    ExprKind::FloatLiteral(f)
                    | ExprKind::SuffixedLiteral(LitValue::Float(f), _) => (*f as i64, *f),
                    _ => unreachable!(),
                };
                let ir = type_internal_to_ir(expected).unwrap_or(IRType::I64);
                let v = self.fresh_vreg();
                if ir.is_float() {
                    self.emit(Inst::ConstFloat(v, float, ir));
                } else {
                    self.emit(Inst::ConstInt(v, int, ir));
                }
                v
            }
            ExprKind::BoolLiteral(b) => {
                let v = self.fresh_vreg();
                self.emit(Inst::ConstInt(v, *b as i64, IRType::I8));
                v
            }
            ExprKind::UnitLiteral => self.const_zero(),

            ExprKind::StringLiteral(s) => {
                let addr = self.temp_for(expected);
                self.lower_string_literal(s, addr);
                addr
            }
            ExprKind::CStringLiteral(s) => {
                let index = self.string_constant(s);
                let v = self.fresh_vreg();
                self.emit(Inst::ConstStringPtr(v, index));
                v
            }

            ExprKind::Ident(name) => {
                if let Some((addr, ty)) = self.ident_place(name) {
                    return if is_scalar(&ty) {
                        let ir = type_internal_to_ir(&ty).unwrap();
                        let v = self.fresh_vreg();
                        self.emit(Inst::Load(v, addr, ir));
                        v
                    } else {
                        addr
                    };
                }
                if let Some(info) = self.checked.consts.get(name) {
                    let ir = type_internal_to_ir(&info.ty).unwrap();
                    let v = self.fresh_vreg();
                    match info.value {
                        ConstValue::Int(i) => self.emit(Inst::ConstInt(v, i as i64, ir)),
                        ConstValue::Float(f) => self.emit(Inst::ConstFloat(v, f, ir)),
                        ConstValue::Bool(b) => self.emit(Inst::ConstInt(v, b as i64, ir)),
                        ConstValue::Aggregate(_) => panic!("ICE: aggregate constant"),
                    }
                    return v;
                }
                let v = self.fresh_vreg();
                self.emit(Inst::FuncAddr(v, name.clone()));
                v
            }

            ExprKind::BinOp { op, lhs, rhs } => self.lower_binop(op, lhs, rhs),
            ExprKind::UnaryOp { op, expr: inner } => self.lower_unaryop(op, inner, expected),
            ExprKind::Cast { expr: inner, .. } => {
                let from = self.expr_ty(inner);
                let to = self.expr_ty(expr);
                let src = self.lower_expr_to_operand(inner, &from);
                self.lower_cast(src, &from, &to)
            }
            ExprKind::Call { callee, args } => self.lower_call(callee, args),

            ExprKind::Index { .. } | ExprKind::Field { .. } | ExprKind::TupleField { .. } => {
                let ty = self.expr_ty(expr);
                let ptr = self.expr_addr_of(expr, &ty);
                if is_scalar(&ty) {
                    let v = self.fresh_vreg();
                    self.emit(Inst::Load(v, ptr, type_internal_to_ir(&ty).unwrap()));
                    v
                } else {
                    ptr
                }
            }

            ExprKind::If {
                cond,
                then_block,
                else_block,
            } => self.lower_if_expr(cond, then_block, else_block.as_ref(), expected),

            ExprKind::Block(block) => self.lower_block_value(block, expected),

            ExprKind::Loop { label, body } => self.lower_loop(label, body, expected),

            ExprKind::Tuple(_)
            | ExprKind::Array(_)
            | ExprKind::ArrayRepeat(_, _)
            | ExprKind::StructConstructor { .. } => {
                let addr = self.temp_for(expected);
                self.lower_expr_to_addr(expr, addr, expected);
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

    // Expr → write result to memory at dst
    fn lower_expr_to_addr(&mut self, expr: &Expr, dst: VReg, ty: &TypeInternal) {
        if self.diverges(expr) {
            self.lower_expr_discard(expr);
            return;
        }
        match &expr.kind {
            ExprKind::StringLiteral(s) => self.lower_string_literal(s, dst),

            ExprKind::Tuple(elems) => {
                let etys = if let TypeInternal::Tuple(ts) = ty {
                    ts.clone()
                } else {
                    elems.iter().map(|e| self.expr_ty(e)).collect()
                };
                let offs = field_offsets(&etys, &self.checked.structs);
                for (i, elem) in elems.iter().enumerate() {
                    let fp = self.fresh_vreg();
                    self.emit(Inst::MemberPtr(fp, dst, offs[i].0));
                    self.store_or_recurse(elem, fp, &etys[i]);
                }
            }

            ExprKind::Array(elems) => {
                let TypeInternal::Array(ety, _) = ty else {
                    panic!("ICE: array literal of type {}", ty)
                };
                let esz = layout_of(ety, &self.checked.structs).size;
                for (i, elem) in elems.iter().enumerate() {
                    let fp = self.fresh_vreg();
                    self.emit(Inst::MemberPtr(fp, dst, i as u64 * esz));
                    self.store_or_recurse(elem, fp, ety);
                }
            }

            ExprKind::ArrayRepeat(val, _) => {
                let TypeInternal::Array(ety, n) = ty else {
                    panic!("ICE: array literal of type {}", ty)
                };
                let (ety, n) = ((**ety).clone(), *n);
                if n == 0 {
                    return;
                }
                // Evaluate the element once into slot 0, then copy it into
                // the others: unrolled for short arrays, as a loop otherwise.
                let esz = layout_of(&ety, &self.checked.structs).size;
                let first = self.fresh_vreg();
                self.emit(Inst::MemberPtr(first, dst, 0));
                self.store_or_recurse(val, first, &ety);
                if n <= 8 {
                    for i in 1..n {
                        let fp = self.fresh_vreg();
                        self.emit(Inst::MemberPtr(fp, dst, i * esz));
                        self.copy_to_dst(fp, first, &ety);
                    }
                    return;
                }
                let counter = self.alloc_slot(8, 8);
                let header = self.fresh_bb();
                let body = self.fresh_bb();
                let exit = self.fresh_bb();
                let one = self.fresh_vreg();
                self.emit(Inst::ConstInt(one, 1, IRType::I64));
                let c0 = self.fresh_vreg();
                self.emit(Inst::SlotAddr(c0, counter));
                self.emit(Inst::Store(c0, one, IRType::I64));
                self.seal(Term::Jump(header));

                self.start(header);
                let c1 = self.fresh_vreg();
                self.emit(Inst::SlotAddr(c1, counter));
                let i = self.fresh_vreg();
                self.emit(Inst::Load(i, c1, IRType::I64));
                let limit = self.fresh_vreg();
                self.emit(Inst::ConstInt(limit, n as i64, IRType::I64));
                let more = self.fresh_vreg();
                self.emit(Inst::ICmp(more, CmpOp::Lt, i, limit, IRType::I64, false));
                self.seal(Term::CondBr {
                    cond: more,
                    then_bb: body,
                    else_bb: exit,
                });

                self.start(body);
                let fp = self.fresh_vreg();
                self.emit(Inst::IndexPtr(fp, dst, i, esz));
                self.copy_to_dst(fp, first, &ety);
                let step = self.fresh_vreg();
                self.emit(Inst::ConstInt(step, 1, IRType::I64));
                let next = self.fresh_vreg();
                self.emit(Inst::IAdd(next, i, step, IRType::I64));
                let c2 = self.fresh_vreg();
                self.emit(Inst::SlotAddr(c2, counter));
                self.emit(Inst::Store(c2, next, IRType::I64));
                self.seal(Term::Jump(header));

                self.start(exit);
            }

            ExprKind::StructConstructor { name, fields } => {
                let info = self.checked.structs[&name.0].clone();
                let ftys: Vec<TypeInternal> = info.fields.iter().map(|(_, t)| t.clone()).collect();
                let offs = field_offsets(&ftys, &self.checked.structs);
                for fi in fields {
                    let idx = info
                        .fields
                        .iter()
                        .position(|(n, _)| n == &fi.name.0)
                        .unwrap();
                    let fp = self.fresh_vreg();
                    self.emit(Inst::MemberPtr(fp, dst, offs[idx].0));
                    self.store_or_recurse(&fi.value, fp, &ftys[idx]);
                }
            }

            ExprKind::Ident(name)
                if self.lookup_local(name).is_some() || self.global_index.contains_key(name) =>
            {
                let (src, _) = self.ident_place(name).unwrap();
                self.copy_to_dst(dst, src, ty);
            }

            ExprKind::Block(block) => self.lower_block_to_addr(block, dst, ty),

            ExprKind::If {
                cond,
                then_block,
                else_block,
            } => self.lower_if_to_addr(cond, then_block, else_block.as_ref(), dst, ty),

            ExprKind::Field { .. } | ExprKind::TupleField { .. } | ExprKind::Index { .. } => {
                let ptr = self.expr_addr_of(expr, ty);
                self.copy_to_dst(dst, ptr, ty);
            }

            _ => {
                // Calls return the sret slot and other compound operands the
                // address of the value, which is copied into place.
                let v = self.lower_expr_to_operand(expr, ty);
                if is_scalar(ty) {
                    self.emit(Inst::Store(dst, v, type_internal_to_ir(ty).unwrap()));
                } else if !is_void(ty) {
                    let size = layout_of(ty, &self.checked.structs).size;
                    self.emit(Inst::MemCopy { dst, src: v, size });
                }
            }
        }
    }

    // Array index widened to 64 bits by its own signedness: IndexPtr adds the
    // full register, and narrow values may carry garbage in the high bits.
    fn lower_index(&mut self, index: &Expr) -> VReg {
        let idx_ty = self.expr_ty(index);
        let idx = self.lower_expr_to_operand(index, &idx_ty);
        let ir = type_internal_to_ir(&idx_ty).unwrap();
        if ir.size() < 8 {
            let d = self.fresh_vreg();
            self.emit(Inst::IntExt(d, idx, ir, IRType::I64, idx_ty.is_signed()));
            d
        } else {
            idx
        }
    }

    fn store_or_recurse(&mut self, expr: &Expr, addr: VReg, ty: &TypeInternal) {
        if is_scalar(ty) {
            let v = self.lower_expr_to_operand(expr, ty);
            self.emit(Inst::Store(addr, v, type_internal_to_ir(ty).unwrap()));
        } else {
            self.lower_expr_to_addr(expr, addr, ty);
        }
    }

    fn copy_to_dst(&mut self, dst: VReg, src: VReg, ty: &TypeInternal) {
        if is_scalar(ty) {
            let ir = type_internal_to_ir(ty).unwrap();
            let v = self.fresh_vreg();
            self.emit(Inst::Load(v, src, ir));
            self.emit(Inst::Store(dst, v, ir));
        } else if !is_void(ty) {
            let sz = layout_of(ty, &self.checked.structs).size;
            self.emit(Inst::MemCopy { dst, src, size: sz });
        }
    }

    // Address of `expr`. Places (variables, statics, `*p`, `p[i]`, fields
    // and elements of places) yield their own address, so `&p.x` and `&a[i]`
    // alias the original; any other expression is materialized in a fresh
    // slot.
    fn expr_addr_of(&mut self, expr: &Expr, ty: &TypeInternal) -> VReg {
        match &expr.kind {
            ExprKind::Ident(name) => {
                if let Some((addr, _)) = self.ident_place(name) {
                    return addr;
                }
            }
            ExprKind::UnaryOp {
                op: UnaryOp::Deref,
                expr: inner,
            } => {
                let it = self.expr_ty(inner);
                return self.lower_expr_to_operand(inner, &it);
            }
            ExprKind::Field { expr: inner, name } => {
                let it = self.expr_ty(inner);
                let (off, _) = self.struct_field_offset(&it, &name.0);
                let base = self.expr_addr_of(inner, &it);
                let ptr = self.fresh_vreg();
                self.emit(Inst::MemberPtr(ptr, base, off));
                return ptr;
            }
            ExprKind::TupleField { expr: inner, index } => {
                let it = self.expr_ty(inner);
                let (off, _) = self.tuple_field_offset(&it, index.0 as usize);
                let base = self.expr_addr_of(inner, &it);
                let ptr = self.fresh_vreg();
                self.emit(Inst::MemberPtr(ptr, base, off));
                return ptr;
            }
            ExprKind::Index { expr: base, index } => {
                let base_ty = self.expr_ty(base);
                let base_addr = match &base_ty {
                    // `p[i]` indexes from the pointer's value
                    TypeInternal::Pointer(_) => self.lower_expr_to_operand(base, &base_ty),
                    _ => self.expr_addr_of(base, &base_ty),
                };
                let elem_ty = self.expr_ty(expr);
                let idx = self.lower_index(index);
                let esz = layout_of(&elem_ty, &self.checked.structs).size;
                let ptr = self.fresh_vreg();
                self.emit(Inst::IndexPtr(ptr, base_addr, idx, esz));
                return ptr;
            }
            _ => {}
        }
        let addr = self.temp_for(ty);
        self.lower_expr_to_addr(expr, addr, ty);
        addr
    }

    // Lowers an expression for its effects only.
    fn lower_expr_discard(&mut self, expr: &Expr) {
        match &expr.kind {
            ExprKind::Call { callee, args } => {
                self.lower_call(callee, args);
            }
            ExprKind::Block(b) => self.lower_block_discard(b),
            ExprKind::If {
                cond,
                then_block,
                else_block,
            } => {
                self.lower_if_expr(cond, then_block, else_block.as_ref(), &TypeInternal::Unit);
            }
            ExprKind::Loop { label, body } => {
                let ty = self.expr_ty(expr);
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
                let ty = self.expr_ty(expr);
                if !is_void(&ty) {
                    let _ = self.lower_expr_to_operand(expr, &ty);
                } else if self.diverges(expr) {
                    // e.g. a cast of `return`: lower the operand for effect
                    match &expr.kind {
                        ExprKind::Cast { expr: inner, .. }
                        | ExprKind::UnaryOp { expr: inner, .. } => self.lower_expr_discard(inner),
                        _ => {}
                    }
                }
            }
        }
    }

    fn string_constant(&mut self, s: &[u8]) -> usize {
        let idx = self.strings.len();
        self.strings.push(StringConstant {
            label: format!("__str{}", idx),
            bytes: s.to_vec(),
        });
        idx
    }

    // String literal: a (*u8, u64) pair
    fn lower_string_literal(&mut self, s: &[u8], dst: VReg) {
        let idx = self.string_constant(s);
        let ptr = self.fresh_vreg();
        self.emit(Inst::ConstStringPtr(ptr, idx));
        let p0 = self.fresh_vreg();
        self.emit(Inst::MemberPtr(p0, dst, 0));
        self.emit(Inst::Store(p0, ptr, IRType::Ptr));
        let len = self.fresh_vreg();
        self.emit(Inst::ConstInt(len, s.len() as i64, IRType::I64));
        let p8 = self.fresh_vreg();
        self.emit(Inst::MemberPtr(p8, dst, 8));
        self.emit(Inst::Store(p8, len, IRType::I64));
    }

    // Binary operators
    fn lower_binop(&mut self, op: &BinOp, lhs: &Expr, rhs: &Expr) -> VReg {
        if matches!(op, BinOp::And) {
            return self.lower_sc_and(lhs, rhs);
        }
        if matches!(op, BinOp::Or) {
            return self.lower_sc_or(lhs, rhs);
        }
        let lhs_ty = self.expr_ty(lhs);
        let a = self.lower_expr_to_operand(lhs, &lhs_ty);
        let rhs_ty = self.expr_ty(rhs);
        let b = self.lower_expr_to_operand(rhs, &rhs_ty);
        if !op.is_comparison() {
            return self.emit_arith(*op, a, b, &lhs_ty);
        }
        let ir = type_internal_to_ir(&lhs_ty).unwrap_or(IRType::I64);
        let c = match op {
            BinOp::Eq => CmpOp::Eq,
            BinOp::Neq => CmpOp::Neq,
            BinOp::Lt => CmpOp::Lt,
            BinOp::Gt => CmpOp::Gt,
            BinOp::LtEq => CmpOp::LtEq,
            _ => CmpOp::GtEq,
        };
        let d = self.fresh_vreg();
        if ir.is_float() {
            self.emit(Inst::FCmp(d, c, a, b, ir))
        } else {
            self.emit(Inst::ICmp(d, c, a, b, ir, lhs_ty.is_signed()))
        }
        d
    }

    // An arithmetic, bitwise or shift operator on operands of type `ty`.
    fn emit_arith(&mut self, op: BinOp, a: VReg, b: VReg, ty: &TypeInternal) -> VReg {
        let ir = type_internal_to_ir(ty).unwrap_or(IRType::I64);
        let signed = ty.is_signed();
        let d = self.fresh_vreg();
        let inst = match op {
            BinOp::Add if ir.is_float() => Inst::FAdd(d, a, b, ir),
            BinOp::Add => Inst::IAdd(d, a, b, ir),
            BinOp::Sub if ir.is_float() => Inst::FSub(d, a, b, ir),
            BinOp::Sub => Inst::ISub(d, a, b, ir),
            BinOp::Mul if ir.is_float() => Inst::FMul(d, a, b, ir),
            BinOp::Mul => Inst::IMul(d, a, b, ir),
            BinOp::Div if ir.is_float() => Inst::FDiv(d, a, b, ir),
            BinOp::Div => Inst::IDiv(d, a, b, ir, signed),
            BinOp::Mod if ir.is_float() => {
                let f = if ir == IRType::F64 { "fmod" } else { "fmodf" };
                Inst::Call {
                    dst: Some((d, ir)),
                    func: f.into(),
                    args: vec![(a, ir), (b, ir)],
                }
            }
            BinOp::Mod => Inst::IMod(d, a, b, ir, signed),
            BinOp::Shl => Inst::IShl(d, a, b, ir),
            BinOp::Shr => Inst::IShr(d, a, b, ir, signed),
            BinOp::BitAnd => Inst::IBitAnd(d, a, b, ir),
            BinOp::BitOr => Inst::IBitOr(d, a, b, ir),
            BinOp::BitXor => Inst::IBitXor(d, a, b, ir),
            _ => panic!("ICE: not an arithmetic operator"),
        };
        self.emit(inst);
        d
    }

    fn lower_sc_and(&mut self, lhs: &Expr, rhs: &Expr) -> VReg {
        let false_bb = self.fresh_bb();
        let rhs_bb = self.fresh_bb();
        let merge = self.fresh_bb();
        let slot = self.alloc_slot(1, 1);
        let a = self.lower_expr_to_operand(lhs, &TypeInternal::Bool);
        self.seal(Term::CondBr {
            cond: a,
            then_bb: rhs_bb,
            else_bb: false_bb,
        });
        self.start(false_bb);
        let z = self.fresh_vreg();
        self.emit(Inst::ConstInt(z, 0, IRType::I8));
        let s1 = self.fresh_vreg();
        self.emit(Inst::SlotAddr(s1, slot));
        self.emit(Inst::Store(s1, z, IRType::I8));
        self.seal(Term::Jump(merge));
        self.start(rhs_bb);
        let b = self.lower_expr_to_operand(rhs, &TypeInternal::Bool);
        let s2 = self.fresh_vreg();
        self.emit(Inst::SlotAddr(s2, slot));
        self.emit(Inst::Store(s2, b, IRType::I8));
        self.seal(Term::Jump(merge));
        self.start(merge);
        let r = self.fresh_vreg();
        let s3 = self.fresh_vreg();
        self.emit(Inst::SlotAddr(s3, slot));
        self.emit(Inst::Load(r, s3, IRType::I8));
        r
    }

    fn lower_sc_or(&mut self, lhs: &Expr, rhs: &Expr) -> VReg {
        let true_bb = self.fresh_bb();
        let rhs_bb = self.fresh_bb();
        let merge = self.fresh_bb();
        let slot = self.alloc_slot(1, 1);
        let a = self.lower_expr_to_operand(lhs, &TypeInternal::Bool);
        self.seal(Term::CondBr {
            cond: a,
            then_bb: true_bb,
            else_bb: rhs_bb,
        });
        self.start(true_bb);
        let o = self.fresh_vreg();
        self.emit(Inst::ConstInt(o, 1, IRType::I8));
        let s1 = self.fresh_vreg();
        self.emit(Inst::SlotAddr(s1, slot));
        self.emit(Inst::Store(s1, o, IRType::I8));
        self.seal(Term::Jump(merge));
        self.start(rhs_bb);
        let b = self.lower_expr_to_operand(rhs, &TypeInternal::Bool);
        let s2 = self.fresh_vreg();
        self.emit(Inst::SlotAddr(s2, slot));
        self.emit(Inst::Store(s2, b, IRType::I8));
        self.seal(Term::Jump(merge));
        self.start(merge);
        let r = self.fresh_vreg();
        let s3 = self.fresh_vreg();
        self.emit(Inst::SlotAddr(s3, slot));
        self.emit(Inst::Load(r, s3, IRType::I8));
        r
    }

    // Unary operators
    fn lower_unaryop(&mut self, op: &UnaryOp, inner: &Expr, expected: &TypeInternal) -> VReg {
        match op {
            UnaryOp::Neg => {
                let ty = self.expr_ty(inner);
                let ir = type_internal_to_ir(&ty).unwrap();
                let v = self.lower_expr_to_operand(inner, &ty);
                let d = self.fresh_vreg();
                if ir.is_float() {
                    self.emit(Inst::FNeg(d, v, ir))
                } else {
                    self.emit(Inst::INeg(d, v, ir))
                }
                d
            }
            UnaryOp::Not => {
                let v = self.lower_expr_to_operand(inner, &TypeInternal::Bool);
                let d = self.fresh_vreg();
                self.emit(Inst::BoolNot(d, v));
                d
            }
            UnaryOp::BitNot => {
                let ty = self.expr_ty(inner);
                let ir = type_internal_to_ir(&ty).unwrap();
                let v = self.lower_expr_to_operand(inner, &ty);
                let d = self.fresh_vreg();
                self.emit(Inst::IBitNot(d, v, ir));
                d
            }
            UnaryOp::Deref => {
                let it = self.expr_ty(inner);
                let ptr = self.lower_expr_to_operand(inner, &it);
                if is_scalar(expected) {
                    let d = self.fresh_vreg();
                    self.emit(Inst::Load(d, ptr, type_internal_to_ir(expected).unwrap()));
                    d
                } else {
                    ptr
                }
            }
            UnaryOp::AddrOf => {
                let it = self.expr_ty(inner);
                self.expr_addr_of(inner, &it)
            }
        }
    }

    // Cast
    fn lower_cast(&mut self, src: VReg, from: &TypeInternal, to: &TypeInternal) -> VReg {
        if *from == TypeInternal::Never {
            return self.dummy(to);
        }
        let fi = type_internal_to_ir(from).unwrap();
        let ti = type_internal_to_ir(to).unwrap();
        if fi == ti {
            return src;
        }
        let d = self.fresh_vreg();
        let fs = from.is_signed();
        if from.is_integer() && to.is_integer() {
            if ti.size() > fi.size() {
                self.emit(Inst::IntExt(d, src, fi, ti, fs))
            } else if ti.size() < fi.size() {
                self.emit(Inst::IntTrunc(d, src, fi, ti))
            } else {
                self.emit(Inst::Mov(d, src))
            }
        } else if from.is_float() && to.is_float() {
            self.emit(Inst::FloatToFloat(d, src, fi, ti))
        } else if from.is_integer() && to.is_float() {
            self.emit(Inst::IntToFloat(d, src, fi, ti, fs))
        } else if from.is_float() && to.is_integer() {
            self.emit(Inst::FloatToInt(d, src, fi, ti, to.is_signed()))
        } else if *from == TypeInternal::Bool && to.is_integer() {
            if ti.size() > 1 {
                self.emit(Inst::IntExt(d, src, IRType::I8, ti, false))
            } else {
                self.emit(Inst::Mov(d, src))
            }
        } else {
            self.emit(Inst::Mov(d, src))
        }
        d
    }

    // Function call; returns the scalar result, the address of a compound
    // result, or a placeholder for () and `!`.
    fn lower_call(&mut self, callee: &Expr, arguments: &[Expr]) -> VReg {
        let ptys = self.call_param_tys(callee);
        let ret_ty = self.call_return_ty(callee);
        let variadic = self.is_variadic_call(callee);
        let mut ir_arguments = Vec::new();
        let sret = if is_compound(&ret_ty) {
            let addr = self.temp_for(&ret_ty);
            ir_arguments.push((addr, IRType::Ptr));
            Some(addr)
        } else {
            None
        };
        for (index, argument) in arguments.iter().enumerate() {
            let pty = match ptys.get(index) {
                Some(pty) => pty.clone(),
                None => self.expr_ty(argument),
            };
            if variadic && index >= ptys.len() && is_scalar(&pty) {
                // C default argument promotions: f32 -> f64, small ints -> int
                let v = self.lower_expr_to_operand(argument, &pty);
                let promoted = match pty {
                    TypeInternal::F32 => TypeInternal::F64,
                    TypeInternal::I8 | TypeInternal::I16 => TypeInternal::I32,
                    TypeInternal::U8 | TypeInternal::U16 | TypeInternal::Bool => TypeInternal::U32,
                    ref other => other.clone(),
                };
                let v = self.lower_cast(v, &pty, &promoted);
                ir_arguments.push((v, type_internal_to_ir(&promoted).unwrap()));
            } else if is_scalar(&pty) {
                let v = self.lower_expr_to_operand(argument, &pty);
                ir_arguments.push((v, type_internal_to_ir(&pty).unwrap()));
            } else {
                let addr = self.expr_addr_of(argument, &pty);
                ir_arguments.push((addr, IRType::Ptr));
            }
        }

        let dst = type_internal_to_ir(&ret_ty).map(|ir| (self.fresh_vreg(), ir));
        match self.direct_callee(callee) {
            Some(sig) => self.emit(Inst::Call {
                dst,
                func: sig.name.clone(),
                args: ir_arguments,
            }),
            None => {
                let callee_ty = self.expr_ty(callee);
                let cv = self.lower_expr_to_operand(callee, &callee_ty);
                self.emit(Inst::CallIndirect {
                    dst,
                    callee: cv,
                    args: ir_arguments,
                });
            }
        }
        match (sret, dst) {
            (Some(addr), _) => addr,
            (None, Some((d, _))) => d,
            (None, None) => self.const_zero(),
        }
    }

    // If expressions
    fn lower_if_expr(
        &mut self,
        cond: &Expr,
        then_b: &Block,
        else_b: Option<&Block>,
        expected: &TypeInternal,
    ) -> VReg {
        if is_compound(expected) {
            let addr = self.temp_for(expected);
            self.lower_if_to_addr(cond, then_b, else_b, addr, expected);
            return addr;
        }
        let cv = self.lower_expr_to_operand(cond, &TypeInternal::Bool);
        let tbb = self.fresh_bb();
        let merge = self.fresh_bb();
        let ebb = if else_b.is_some() {
            self.fresh_bb()
        } else {
            merge
        };
        self.seal(Term::CondBr {
            cond: cv,
            then_bb: tbb,
            else_bb: ebb,
        });

        let Some(eb) = else_b.filter(|_| is_scalar(expected)) else {
            // No value: () (or `!`).
            self.start(tbb);
            self.lower_block_discard(then_b);
            self.seal(Term::Jump(merge));
            if let Some(eb) = else_b {
                self.start(ebb);
                self.lower_block_discard(eb);
                self.seal(Term::Jump(merge));
            }
            self.start(merge);
            return self.const_zero();
        };

        let ir = type_internal_to_ir(expected).unwrap();
        let slot = self.alloc_slot(ir.size(), ir.size());
        self.start(tbb);
        let tv = self.lower_block_value(then_b, expected);
        let s1 = self.fresh_vreg();
        self.emit(Inst::SlotAddr(s1, slot));
        self.emit(Inst::Store(s1, tv, ir));
        self.seal(Term::Jump(merge));

        self.start(ebb);
        let ev = self.lower_block_value(eb, expected);
        let s2 = self.fresh_vreg();
        self.emit(Inst::SlotAddr(s2, slot));
        self.emit(Inst::Store(s2, ev, ir));
        self.seal(Term::Jump(merge));

        self.start(merge);
        let r = self.fresh_vreg();
        let s3 = self.fresh_vreg();
        self.emit(Inst::SlotAddr(s3, slot));
        self.emit(Inst::Load(r, s3, ir));
        r
    }

    fn lower_if_to_addr(
        &mut self,
        cond: &Expr,
        then_b: &Block,
        else_b: Option<&Block>,
        dst: VReg,
        ty: &TypeInternal,
    ) {
        let cv = self.lower_expr_to_operand(cond, &TypeInternal::Bool);
        let tbb = self.fresh_bb();
        let merge = self.fresh_bb();
        let ebb = if else_b.is_some() {
            self.fresh_bb()
        } else {
            merge
        };
        self.seal(Term::CondBr {
            cond: cv,
            then_bb: tbb,
            else_bb: ebb,
        });
        self.start(tbb);
        self.lower_block_to_addr(then_b, dst, ty);
        self.seal(Term::Jump(merge));
        if let Some(eb) = else_b {
            self.start(ebb);
            self.lower_block_to_addr(eb, dst, ty);
            self.seal(Term::Jump(merge));
        }
        self.start(merge);
    }
}

// Public API
pub fn lower(program: &Program, checked: &CheckedProgram) -> IrProgram {
    let mut ctx = Lowerer::new(checked);
    ctx.lower_program(program)
}

// IR pretty-printer
pub fn print_ir(prog: &IrProgram) -> String {
    let mut out = String::new();
    for (i, g) in prog.globals.iter().enumerate() {
        out += &format!(
            "global{} {}{}: {:?}\n",
            i,
            if g.mutable { "mut " } else { "" },
            g.name,
            g.bytes
        );
    }
    for sc in &prog.strings {
        out += &format!(
            "{}: {:?}\n",
            sc.label,
            std::str::from_utf8(&sc.bytes).unwrap_or("?")
        );
    }
    for func in &prog.functions {
        if func.is_extern {
            out += &format!("extern fn {}(", func.name);
            for (i, (_, ty)) in func.params.iter().enumerate() {
                if i > 0 {
                    out += ", ";
                }
                out += &format!("{}", ty);
            }
            out += ")";
            if let Some(r) = func.return_ir {
                out += &format!(" -> {}", r);
            }
            out += "\n";
            continue;
        }
        out += &format!("fn {}(", func.name);
        for (i, (v, ty)) in func.params.iter().enumerate() {
            if i > 0 {
                out += ", ";
            }
            out += &format!("{}: {}", v, ty);
        }
        out += ")";
        if let Some(r) = func.return_ir {
            out += &format!(" -> {}", r);
        }
        out += " {\n";
        for (i, slot) in func.slots.iter().enumerate() {
            out += &format!("  slot{}: size={}, align={}\n", i, slot.size, slot.align);
        }
        for bb in &func.blocks {
            out += &format!("  {}:\n", bb.id);
            for inst in &bb.instructions {
                out += &format!("    {}\n", fmt_inst(inst));
            }
            out += &format!("    {}\n", fmt_term(&bb.teminator));
        }
        out += "}\n";
    }
    out
}

fn fmt_inst(i: &Inst) -> String {
    match i {
        Inst::IAdd(d, a, b, t) => format!("{} = iadd.{} {}, {}", d, t, a, b),
        Inst::ISub(d, a, b, t) => format!("{} = isub.{} {}, {}", d, t, a, b),
        Inst::IMul(d, a, b, t) => format!("{} = imul.{} {}, {}", d, t, a, b),
        Inst::IDiv(d, a, b, t, s) => format!(
            "{} = idiv.{}{} {}, {}",
            d,
            t,
            if *s { "s" } else { "u" },
            a,
            b
        ),
        Inst::IMod(d, a, b, t, s) => format!(
            "{} = imod.{}{} {}, {}",
            d,
            t,
            if *s { "s" } else { "u" },
            a,
            b
        ),
        Inst::IShl(d, a, b, t) => format!("{} = ishl.{} {}, {}", d, t, a, b),
        Inst::IShr(d, a, b, t, s) => format!(
            "{} = ishr.{}{} {}, {}",
            d,
            t,
            if *s { "a" } else { "l" },
            a,
            b
        ),
        Inst::INeg(d, a, t) => format!("{} = ineg.{} {}", d, t, a),
        Inst::IBitAnd(d, a, b, t) => format!("{} = iand.{} {}, {}", d, t, a, b),
        Inst::IBitOr(d, a, b, t) => format!("{} = ior.{} {}, {}", d, t, a, b),
        Inst::IBitXor(d, a, b, t) => format!("{} = ixor.{} {}, {}", d, t, a, b),
        Inst::IBitNot(d, a, t) => format!("{} = inot.{} {}", d, t, a),
        Inst::FAdd(d, a, b, t) => format!("{} = fadd.{} {}, {}", d, t, a, b),
        Inst::FSub(d, a, b, t) => format!("{} = fsub.{} {}, {}", d, t, a, b),
        Inst::FMul(d, a, b, t) => format!("{} = fmul.{} {}, {}", d, t, a, b),
        Inst::FDiv(d, a, b, t) => format!("{} = fdiv.{} {}, {}", d, t, a, b),
        Inst::FNeg(d, a, t) => format!("{} = fneg.{} {}", d, t, a),
        Inst::ICmp(d, op, a, b, t, s) => format!(
            "{} = icmp.{}{} {} {}, {}",
            d,
            t,
            if *s { "s" } else { "u" },
            op,
            a,
            b
        ),
        Inst::FCmp(d, op, a, b, t) => format!("{} = fcmp.{} {} {}, {}", d, t, op, a, b),
        Inst::BoolNot(d, a) => format!("{} = bnot {}", d, a),
        Inst::ConstInt(d, v, t) => format!("{} = const.{} {}", d, t, v),
        Inst::ConstFloat(d, v, t) => format!("{} = constf.{} {}", d, t, v),
        Inst::ConstStringPtr(d, idx) => format!("{} = strptr __str{}", d, idx),
        Inst::IntToFloat(d, s, f, t, sg) => format!(
            "{} = itof.{}->{} {} ({})",
            d,
            f,
            t,
            s,
            if *sg { "s" } else { "u" }
        ),
        Inst::FloatToInt(d, s, f, t, sg) => format!(
            "{} = ftoi.{}->{} {} ({})",
            d,
            f,
            t,
            s,
            if *sg { "s" } else { "u" }
        ),
        Inst::FloatToFloat(d, s, f, t) => format!("{} = ftof.{}->{} {}", d, f, t, s),
        Inst::IntExt(d, s, f, t, sg) => format!(
            "{} = ext.{}->{} {} ({})",
            d,
            f,
            t,
            s,
            if *sg { "s" } else { "u" }
        ),
        Inst::IntTrunc(d, s, f, t) => format!("{} = trunc.{}->{} {}", d, f, t, s),
        Inst::Load(d, a, t) => format!("{} = load.{} [{}]", d, t, a),
        Inst::Store(a, v, t) => format!("store.{} [{}], {}", t, a, v),
        Inst::MemCopy { dst, src, size } => format!("memcpy [{}], [{}], {}", dst, src, size),
        Inst::SlotAddr(d, s) => format!("{} = slotaddr {}", d, s),
        Inst::GlobalAddr(d, index) => format!("{} = globaladdr @global{}", d, index),
        Inst::MemberPtr(d, b, off) => format!("{} = memberptr {}, +{}", d, b, off),
        Inst::IndexPtr(d, b, idx, sz) => format!("{} = indexptr {}, {}, elem={}", d, b, idx, sz),
        Inst::Call { dst, func, args } => {
            let a: Vec<_> = args.iter().map(|(v, t)| format!("{}:{}", v, t)).collect();
            match dst {
                Some((d, t)) => format!("{} = call.{} {}({})", d, t, func, a.join(", ")),
                None => format!("call {}({})", func, a.join(", ")),
            }
        }
        Inst::CallIndirect { dst, callee, args } => {
            let a: Vec<_> = args.iter().map(|(v, t)| format!("{}:{}", v, t)).collect();
            match dst {
                Some((d, t)) => format!("{} = calli.{} {}({})", d, t, callee, a.join(", ")),
                None => format!("calli {}({})", callee, a.join(", ")),
            }
        }
        Inst::Mov(d, s) => format!("{} = mov {}", d, s),
        Inst::FuncAddr(d, name) => format!("{} = funcaddr @{}", d, name),
    }
}

fn fmt_term(t: &Term) -> String {
    match t {
        Term::Ret(None) => "ret".into(),
        Term::Ret(Some((v, t))) => format!("ret.{} {}", t, v),
        Term::Jump(b) => format!("jmp {}", b),
        Term::CondBr {
            cond,
            then_bb,
            else_bb,
        } => format!("br {}, {}, {}", cond, then_bb, else_bb),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    pub fn parse_source(src: &str) -> Result<Program, ParserError> {
        crate::parser::parse(crate::lexer::Lexer::new(src).tokenize().unwrap())
            .map_err(|mut errors| errors.remove(0))
    }

    fn lower_ok(src: &str) -> IrProgram {
        let prog = parse_source(src).unwrap_or_else(|e| panic!("parse: {}", e));
        let checked =
            crate::typechecker::typecheck(&prog).unwrap_or_else(|e| panic!("typecheck: {:?}", e));
        lower(&prog, &checked)
    }

    fn ir_str(src: &str) -> String {
        print_ir(&lower_ok(src))
    }

    #[test]
    fn test_empty_fn() {
        let s = ir_str("fn main() {}");
        assert!(s.contains("fn main()"));
        assert!(s.contains("ret"));
    }
    #[test]
    fn test_return_int() {
        let s = ir_str("fn foo() -> i32 { 42 }");
        assert!(s.contains("const.i32 42"));
        assert!(s.contains("ret.i32"));
    }
    #[test]
    fn test_let_return() {
        let s = ir_str("fn f() -> i32 { let x: i32 = 10; x }");
        assert!(s.contains("const.i32 10"));
    }
    #[test]
    fn test_iadd() {
        let s = ir_str("fn f() -> i32 { let a: i32 = 3; let b: i32 = 4; a + b }");
        assert!(s.contains("iadd.i32"));
    }
    #[test]
    fn test_fmul() {
        let s = ir_str("fn f() -> f64 { let a: f64 = 1.0; let b: f64 = 2.0; a * b }");
        assert!(s.contains("fmul.f64"));
    }
    #[test]
    fn test_icmp() {
        let s = ir_str("fn f() -> bool { let a: i32 = 1; a < 2 }");
        assert!(s.contains("icmp.i32"));
    }
    #[test]
    fn test_if_else() {
        let s = ir_str("fn f() -> i32 { if true { 1 } else { 2 } }");
        assert!(s.contains("br "));
    }
    #[test]
    fn test_loop_break() {
        let s = ir_str("fn f() { let mut i: i32 = 0; loop { if i == 10 { break; }; i += 1; } }");
        assert!(s.contains("jmp bb"));
        assert!(s.contains("icmp"));
    }
    #[test]
    fn test_struct() {
        let s = ir_str(
            "struct P { x: i32, y: i32 } fn f() -> i32 { let p = P { x: 10, y: 20 }; p.x + p.y }",
        );
        assert!(s.contains("memberptr"));
        assert!(s.contains("iadd.i32"));
    }
    #[test]
    fn test_struct_return_uses_sret() {
        let prog = lower_ok(
            "struct P { x: i64, y: i64 } fn mk(a: i64) -> P { P { x: a, y: a } } \
             fn main() -> i64 { let p = mk(1); p.x }",
        );
        let mk = prog.functions.iter().find(|f| f.name == "mk").unwrap();
        // Hidden result pointer comes first, then the declared parameter
        assert_eq!(mk.params.len(), 2);
        assert_eq!(mk.params[0].1, IRType::Ptr);
        // The callee writes into the caller's slot instead of its own frame
        assert!(mk.slots.iter().all(|s| s.size != 16));
        let main = prog.functions.iter().find(|f| f.name == "main").unwrap();
        let call = main
            .blocks
            .iter()
            .flat_map(|b| &b.instructions)
            .find_map(|i| match i {
                Inst::Call { func, dst, args } if func == "mk" => Some((dst, args)),
                _ => None,
            })
            .unwrap();
        assert!(call.0.is_none());
        assert_eq!(call.1.len(), 2);
    }
    #[test]
    fn test_variadic_promotes_f32_and_small_ints() {
        let prog = lower_ok(
            "extern fn printf(f: *u8, ...) -> i32; \
             fn main() { let x: f32 = 1.0; let y: u8 = 2; printf(\"\".0, x, y); }",
        );
        let main = prog.functions.iter().find(|f| f.name == "main").unwrap();
        let args = main
            .blocks
            .iter()
            .flat_map(|b| &b.instructions)
            .find_map(|i| match i {
                Inst::Call { func, args, .. } if func == "printf" => Some(args),
                _ => None,
            })
            .unwrap();
        let tys: Vec<IRType> = args.iter().map(|(_, t)| *t).collect();
        assert_eq!(tys, vec![IRType::Ptr, IRType::F64, IRType::I32]);
    }
    #[test]
    fn test_array() {
        let s = ir_str("fn f() -> i64 { let a = [1, 2, 3]; a[1] }");
        assert!(s.contains("indexptr"));
    }
    #[test]
    fn test_string() {
        let s = ir_str(r#"fn f() { let s = "hello"; }"#);
        assert!(s.contains("__str0"));
        assert!(s.contains("strptr"));
    }
    #[test]
    fn test_call() {
        let s = ir_str("fn add(a: i32, b: i32) -> i32 { a + b } fn f() -> i32 { add(3, 4) }");
        assert!(s.contains("call.i32 add"));
    }
    #[test]
    fn test_extern() {
        let s = ir_str("extern fn puts(s: *u8) -> i32; fn f() {}");
        assert!(s.contains("extern fn puts"));
    }
    #[test]
    fn test_short_circuit_and() {
        let s = ir_str("fn f() -> bool { true && false }");
        assert!(s.contains("br ")); // must have conditional branch for short-circuit
    }
    #[test]
    fn test_short_circuit_or() {
        let s = ir_str("fn f() -> bool { false || true }");
        assert!(s.contains("br "));
    }
    #[test]
    fn test_shift() {
        let s = ir_str("fn f() -> i32 { let x: i32 = 1; x << 4 }");
        assert!(s.contains("ishl.i32"));
    }
    #[test]
    fn test_cast() {
        let s = ir_str("fn f() -> f64 { let x: i32 = 42; x as f64 }");
        assert!(s.contains("itof"));
    }
    #[test]
    fn test_unary_neg() {
        let s = ir_str("fn f() -> i32 { let x: i32 = 5; -x }");
        assert!(s.contains("ineg.i32"));
    }
    #[test]
    fn test_bool_not() {
        let s = ir_str("fn f() -> bool { !true }");
        assert!(s.contains("bnot"));
    }
    #[test]
    fn test_pointer_deref() {
        let s = ir_str("fn f() -> i32 { let x: i32 = 42; let p = &x; *p }");
        assert!(s.contains("slotaddr"));
        assert!(s.contains("load.i32"));
    }
    #[test]
    fn test_tuple() {
        let s = ir_str("fn f() -> i32 { let t: (i32, i64) = (1, 2); t.0 }");
        assert!(s.contains("memberptr"));
        assert!(s.contains("load.i32"));
    }
    #[test]
    fn test_compound_assign() {
        let s = ir_str("fn f() { let mut x: i32 = 1; x += 10; }");
        assert!(s.contains("iadd.i32"));
        assert!(s.contains("store.i32"));
    }
    #[test]
    fn test_return_stmt() {
        let s = ir_str("fn f() -> i32 { return 42; }");
        assert!(s.contains("const.i32 42"));
        assert!(s.contains("ret.i32"));
    }
    #[test]
    fn test_nested_blocks() {
        let s = ir_str("fn f() -> i32 { let x: i32 = { let y: i32 = 5; y + 1 }; x }");
        assert!(s.contains("iadd.i32"));
    }
    #[test]
    fn test_float_mod_calls_fmod() {
        let s = ir_str("fn f() -> f64 { let x: f64 = 7.0; x % 3.0 }");
        assert!(s.contains("call") && s.contains("fmod"));
    }
    #[test]
    fn test_continue() {
        let s = ir_str(
            "fn f() { let mut i: i32 = 0; loop { i += 1; if i == 5 { continue; }; if i == 10 { break; }; } }",
        );
        assert!(s.contains("jmp bb"));
    }
    #[test]
    fn test_array_repeat() {
        let s = ir_str("fn f() -> i64 { let a = [0; 5]; a[3] }");
        assert!(s.contains("indexptr"));
    }
}
