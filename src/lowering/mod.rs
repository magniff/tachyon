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
}

#[derive(Debug, Clone)]
pub struct StringConstant {
    pub label: String,
    pub bytes: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct IrProgram {
    pub functions: Vec<IRFunction>,
    pub strings: Vec<StringConstant>,
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
        TypeInternal::Pointer(_) | TypeInternal::FnPtr(_, _) => Layout { size: 8, align: 8 },
        TypeInternal::Unit => Layout { size: 0, align: 1 },
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
        TypeInternal::Pointer(_) | TypeInternal::FnPtr(_, _) => Some(IRType::Ptr),
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

fn ir_to_lang_ty(ir: IRType) -> TypeInternal {
    match ir {
        IRType::I8 => TypeInternal::I8,
        IRType::I16 => TypeInternal::I16,
        IRType::I32 => TypeInternal::I32,
        IRType::I64 => TypeInternal::I64,
        IRType::F32 => TypeInternal::F32,
        IRType::F64 => TypeInternal::F64,
        IRType::Ptr => TypeInternal::Pointer(Box::new(TypeInternal::U8)),
    }
}

// Where a local lives
#[derive(Debug, Clone)]
enum Place {
    // We'll place everything into Addresses for now
    Address(VReg, TypeInternal),
    #[allow(dead_code)]
    Register(VReg, IRType),
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
    scopes: Vec<HashMap<String, Place>>,
    return_ty: TypeInternal,
    loop_stack: Vec<(BlockId, BlockId)>,
    strings: Vec<StringConstant>,
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
            loop_stack: Vec::new(),
            strings: Vec::new(),
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
    fn push_scope(&mut self) {
        self.scopes.push(HashMap::new());
    }
    fn pop_scope(&mut self) {
        self.scopes.pop();
    }
    fn define(&mut self, name: String, p: Place) {
        self.scopes.last_mut().unwrap().insert(name, p);
    }
    fn lookup(&self, name: &str) -> &Place {
        for s in self.scopes.iter().rev() {
            if let Some(p) = s.get(name) {
                return p;
            }
        }
        panic!("ICE: undefined '{}'", name);
    }
    fn const_zero(&mut self) -> VReg {
        let v = self.fresh_vreg();
        self.emit(Inst::ConstInt(v, 0, IRType::I8));
        v
    }

    fn resolve_ast_type(&self, t: &Type) -> TypeInternal {
        match &t.kind {
            TypeKind::Named(n) => match n.as_str() {
                "i8" => TypeInternal::I8,
                "i16" => TypeInternal::I16,
                "i32" => TypeInternal::I32,
                "i64" => TypeInternal::I64,
                "u8" => TypeInternal::U8,
                "u16" => TypeInternal::U16,
                "u32" => TypeInternal::U32,
                "u64" => TypeInternal::U64,
                "f32" => TypeInternal::F32,
                "f64" => TypeInternal::F64,
                "bool" => TypeInternal::Bool,
                "usize" => TypeInternal::U64,
                _ => TypeInternal::Struct(n.clone()),
            },
            TypeKind::Unit => TypeInternal::Unit,
            TypeKind::Tuple(ts) => {
                TypeInternal::Tuple(ts.iter().map(|x| self.resolve_ast_type(x)).collect())
            }
            TypeKind::Array(e, n) => TypeInternal::Array(Box::new(self.resolve_ast_type(e)), *n),
            TypeKind::Pointer(i) => TypeInternal::Pointer(Box::new(self.resolve_ast_type(i))),
            TypeKind::FnPtr(ps, r) => {
                let pts: Vec<_> = ps.iter().map(|x| self.resolve_ast_type(x)).collect();
                let rt = r
                    .as_ref()
                    .map(|x| self.resolve_ast_type(x))
                    .unwrap_or(TypeInternal::Unit);
                TypeInternal::FnPtr(pts, Box::new(rt))
            }
        }
    }

    fn expr_ty(&self, expr: &Expr) -> TypeInternal {
        match &expr.kind {
            ExprKind::IntLiteral(_) => TypeInternal::I64,
            ExprKind::FloatLiteral(_) => TypeInternal::F64,
            ExprKind::BoolLiteral(_) => TypeInternal::Bool,
            ExprKind::UnitLiteral => TypeInternal::Unit,
            ExprKind::StringLiteral(_) => TypeInternal::Tuple(vec![
                TypeInternal::Pointer(Box::new(TypeInternal::U8)),
                TypeInternal::U64,
            ]),
            ExprKind::Ident(name) => match self.lookup(name) {
                Place::Register(_, ir) => ir_to_lang_ty(*ir),
                Place::Address(_, ty) => ty.clone(),
            },
            ExprKind::BinOp { op, lhs, .. } => match op {
                BinOp::Eq
                | BinOp::Neq
                | BinOp::Lt
                | BinOp::Gt
                | BinOp::LtEq
                | BinOp::GtEq
                | BinOp::And
                | BinOp::Or => TypeInternal::Bool,
                _ => self.expr_ty(lhs),
            },
            ExprKind::UnaryOp { op, expr: inner } => match op {
                UnaryOp::Not => TypeInternal::Bool,
                UnaryOp::Deref => {
                    if let TypeInternal::Pointer(p) = self.expr_ty(inner) {
                        *p
                    } else {
                        panic!("ICE")
                    }
                }
                UnaryOp::AddrOf => TypeInternal::Pointer(Box::new(self.expr_ty(inner))),
                _ => self.expr_ty(inner),
            },
            ExprKind::Cast { ty, .. } => self.resolve_ast_type(ty),
            ExprKind::Call { callee, .. } => {
                if let ExprKind::Ident(n) = &callee.kind {
                    if let Some(sig) = self.checked.functions.get(n) {
                        return sig.return_ty.clone();
                    }
                }
                if let TypeInternal::FnPtr(_, r) = self.expr_ty(callee) {
                    *r
                } else {
                    panic!("ICE")
                }
            }
            ExprKind::Index { expr: a, .. } => {
                if let TypeInternal::Array(e, _) = self.expr_ty(a) {
                    *e
                } else {
                    panic!("ICE")
                }
            }
            ExprKind::Field { expr: inner, name } => {
                if let TypeInternal::Struct(s) = self.expr_ty(inner) {
                    self.checked.structs[&s]
                        .fields
                        .iter()
                        .find(|(n, _)| n == &name.0)
                        .unwrap()
                        .1
                        .clone()
                } else {
                    panic!("ICE")
                }
            }
            ExprKind::TupleField { expr: inner, index } => {
                if let TypeInternal::Tuple(es) = self.expr_ty(inner) {
                    es[index.0 as usize].clone()
                } else {
                    panic!("ICE")
                }
            }
            ExprKind::Tuple(es) => {
                TypeInternal::Tuple(es.iter().map(|e| self.expr_ty(e)).collect())
            }
            ExprKind::Array(es) => {
                TypeInternal::Array(Box::new(self.expr_ty(&es[0])), es.len() as u64)
            }
            ExprKind::ArrayRepeat(v, c) => {
                let n = if let ExprKind::IntLiteral(n) = c.kind {
                    n
                } else {
                    panic!("ICE")
                };
                TypeInternal::Array(Box::new(self.expr_ty(v)), n)
            }
            ExprKind::StructConstructor { name, .. } => TypeInternal::Struct(name.0.clone()),
            ExprKind::Block(b) => {
                if let Some(t) = &b.expr {
                    self.expr_ty(t)
                } else {
                    TypeInternal::Unit
                }
            }
            ExprKind::If {
                then_block,
                else_block,
                ..
            } => {
                if else_block.is_some() {
                    if let Some(t) = &then_block.expr {
                        self.expr_ty(t)
                    } else {
                        TypeInternal::Unit
                    }
                } else {
                    TypeInternal::Unit
                }
            }
        }
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

    fn call_param_tys(&self, callee: &Expr) -> Vec<TypeInternal> {
        if let ExprKind::Ident(n) = &callee.kind {
            if let Some(sig) = self.checked.functions.get(n) {
                return sig.params.iter().map(|(_, t)| t.clone()).collect();
            }
        }
        if let TypeInternal::FnPtr(ps, _) = self.expr_ty(callee) {
            ps
        } else {
            panic!("ICE")
        }
    }

    // Top-level
    fn lower_program(&mut self, program: &Program) -> IrProgram {
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
                        return_ir: if signature.return_ty == TypeInternal::Unit {
                            None
                        } else {
                            type_internal_to_ir(&signature.return_ty)
                        },
                        slots: vec![],
                        blocks: vec![],
                        vreg_counter: 0,
                        is_extern: true,
                    });
                }
                Item::Struct(_) => {}
            }
        }
        IrProgram {
            functions,
            strings: std::mem::take(&mut self.strings),
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
        self.loop_stack.clear();

        let entry = self.fresh_bb();
        self.start(entry);

        let mut ir_params = Vec::new();
        for (pname, pty) in &sig.params {
            if is_scalar(pty) {
                let ir = type_internal_to_ir(pty).unwrap();
                let v = self.fresh_vreg();
                ir_params.push((v, ir));
                // Store into slot so param can be reassigned
                let slot = self.alloc_slot(ir.size(), ir.size());
                let addr = self.fresh_vreg();
                self.emit(Inst::SlotAddr(addr, slot));
                self.emit(Inst::Store(addr, v, ir));
                self.define(pname.clone(), Place::Address(addr, pty.clone()));
            } else {
                let slot = self.alloc_slot_for(pty);
                let addr = self.fresh_vreg();
                self.emit(Inst::SlotAddr(addr, slot));
                let src = self.fresh_vreg();
                ir_params.push((src, IRType::Ptr));
                let sz = layout_of(pty, &self.checked.structs).size;
                self.emit(Inst::MemCopy {
                    dst: addr,
                    src,
                    size: sz,
                });
                self.define(pname.clone(), Place::Address(addr, pty.clone()));
            }
        }

        let ret = sig.return_ty.clone();
        self.lower_block_stmts(&fd.body);

        if let Some(tail) = &fd.body.expr {
            if ret == TypeInternal::Unit {
                self.lower_expr_discard(tail);
                self.seal(Term::Ret(None));
            } else if is_scalar(&ret) {
                let v = self.lower_expr_to_operand(tail, &ret);
                let ir = type_internal_to_ir(&ret).unwrap();
                self.seal(Term::Ret(Some((v, ir))));
            } else {
                let slot = self.alloc_slot_for(&ret);
                let addr = self.fresh_vreg();
                self.emit(Inst::SlotAddr(addr, slot));
                self.lower_expr_to_addr(tail, addr, &ret);
                self.seal(Term::Ret(Some((addr, IRType::Ptr))));
            }
        } else {
            self.seal(Term::Ret(None));
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
        }
    }

    // Block stmts (opens scope, caller pops)
    fn lower_block_stmts(&mut self, block: &Block) {
        self.push_scope();
        for stmt in &block.stmts {
            self.lower_stmt(stmt);
        }
    }

    // Statements
    fn lower_stmt(&mut self, stmt: &Stmt) {
        match stmt {
            Stmt::Let(ls) => self.lower_let(ls),
            Stmt::Assign(a) => self.lower_assign(a),
            Stmt::Return(r) => self.lower_return(r),
            Stmt::Break(_) => self.lower_break(),
            Stmt::Continue(_) => self.lower_continue(),
            Stmt::Loop(l) => self.lower_loop(l),
            Stmt::Expr(es) => {
                self.lower_expr_discard(&es.expr);
            }
        }
    }

    fn lower_let(&mut self, ls: &LetStmt) {
        let ty = if let Some(ann) = &ls.ty {
            self.resolve_ast_type(ann)
        } else {
            self.expr_ty(&ls.init)
        };
        if ty == TypeInternal::Unit {
            self.lower_expr_discard(&ls.init);
            return;
        }
        // Always use a stack slot, even for scalars. This ensures that
        // assignments in loops/branches update the canonical location and
        // reads in other basic blocks see the latest value.
        let slot = self.alloc_slot_for(&ty);
        let addr = self.fresh_vreg();
        self.emit(Inst::SlotAddr(addr, slot));
        if is_scalar(&ty) {
            let v = self.lower_expr_to_operand(&ls.init, &ty);
            self.emit(Inst::Store(addr, v, type_internal_to_ir(&ty).unwrap()));
        } else {
            self.lower_expr_to_addr(&ls.init, addr, &ty);
        }
        self.define(ls.name.0.clone(), Place::Address(addr, ty));
    }

    fn lower_assign(&mut self, a: &AssignStmt) {
        let (addr, tgt_ty) = self.lower_lvalue_addr(&a.target);
        match a.op {
            AssignOp::Assign => {
                if is_scalar(&tgt_ty) {
                    let v = self.lower_expr_to_operand(&a.value, &tgt_ty);
                    self.emit(Inst::Store(addr, v, type_internal_to_ir(&tgt_ty).unwrap()));
                } else {
                    self.lower_expr_to_addr(&a.value, addr, &tgt_ty);
                }
            }
            AssignOp::AddAssign
            | AssignOp::SubAssign
            | AssignOp::ShlAssign
            | AssignOp::ShrAssign => {
                let ir = type_internal_to_ir(&tgt_ty).unwrap();
                let old = self.fresh_vreg();
                self.emit(Inst::Load(old, addr, ir));
                let rhs_ty = if matches!(a.op, AssignOp::ShlAssign | AssignOp::ShrAssign) {
                    self.expr_ty(&a.value)
                } else {
                    tgt_ty.clone()
                };
                let rhs = self.lower_expr_to_operand(&a.value, &rhs_ty);
                let res = self.fresh_vreg();
                let signed = tgt_ty.is_signed();
                match a.op {
                    AssignOp::AddAssign => {
                        if ir.is_float() {
                            self.emit(Inst::FAdd(res, old, rhs, ir));
                        } else {
                            self.emit(Inst::IAdd(res, old, rhs, ir));
                        }
                    }
                    AssignOp::SubAssign => {
                        if ir.is_float() {
                            self.emit(Inst::FSub(res, old, rhs, ir));
                        } else {
                            self.emit(Inst::ISub(res, old, rhs, ir));
                        }
                    }
                    AssignOp::ShlAssign => self.emit(Inst::IShl(res, old, rhs, ir)),
                    AssignOp::ShrAssign => self.emit(Inst::IShr(res, old, rhs, ir, signed)),
                    _ => unreachable!(),
                }
                self.emit(Inst::Store(addr, res, ir));
            }
        }
    }

    fn lower_return(&mut self, r: &ReturnStmt) {
        let ret_ty = self.return_ty.clone();
        match &r.value {
            Some(e) if ret_ty == TypeInternal::Unit => {
                self.lower_expr_discard(e);
                self.seal(Term::Ret(None));
            }
            Some(e) if is_scalar(&ret_ty) => {
                let v = self.lower_expr_to_operand(e, &ret_ty);
                self.seal(Term::Ret(Some((v, type_internal_to_ir(&ret_ty).unwrap()))));
            }
            Some(e) => {
                let slot = self.alloc_slot_for(&ret_ty);
                let addr = self.fresh_vreg();
                self.emit(Inst::SlotAddr(addr, slot));
                self.lower_expr_to_addr(e, addr, &ret_ty);
                self.seal(Term::Ret(Some((addr, IRType::Ptr))));
            }
            None => self.seal(Term::Ret(None)),
        }
        let dead = self.fresh_bb();
        self.start(dead);
    }

    fn lower_break(&mut self) {
        let (_, brk) = *self.loop_stack.last().unwrap();
        self.seal(Term::Jump(brk));
        let dead = self.fresh_bb();
        self.start(dead);
    }

    fn lower_continue(&mut self) {
        let (cont, _) = *self.loop_stack.last().unwrap();
        self.seal(Term::Jump(cont));
        let dead = self.fresh_bb();
        self.start(dead);
    }

    fn lower_loop(&mut self, l: &LoopStmt) {
        let header = self.fresh_bb();
        let exit = self.fresh_bb();
        self.seal(Term::Jump(header));
        self.start(header);
        self.loop_stack.push((header, exit));
        self.lower_block_stmts(&l.body);
        if let Some(tail) = &l.body.expr {
            self.lower_expr_discard(tail);
        }
        self.pop_scope();
        self.loop_stack.pop();
        self.seal(Term::Jump(header));
        self.start(exit);
    }

    // LValue → address + type
    fn lower_lvalue_addr(&mut self, lv: &LValue) -> (VReg, TypeInternal) {
        match &lv.kind {
            LValueKind::Ident(name) => {
                let place = self.lookup(name).clone();
                match place {
                    Place::Register(v, ir) => {
                        // Promote scalar to slot for assignment
                        let slot = self.alloc_slot(ir.size(), ir.size());
                        let addr = self.fresh_vreg();
                        self.emit(Inst::SlotAddr(addr, slot));
                        self.emit(Inst::Store(addr, v, ir));
                        let ty = ir_to_lang_ty(ir);
                        self.define(name.clone(), Place::Address(addr, ty.clone()));
                        (addr, ty)
                    }
                    Place::Address(addr, ty) => (addr, ty),
                }
            }
            LValueKind::Deref(inner) => {
                let inner_ty = self.expr_ty(inner);
                if let TypeInternal::Pointer(pointee) = &inner_ty {
                    let ptr = self.lower_expr_to_operand(inner, &inner_ty);
                    (ptr, *pointee.clone())
                } else {
                    panic!("ICE: deref non-ptr lvalue")
                }
            }
            LValueKind::Field(inner, fname) => {
                let (base, base_ty) = self.lower_lvalue_addr(inner);
                let (off, fty) = self.struct_field_offset(&base_ty, &fname.0);
                let ptr = self.fresh_vreg();
                self.emit(Inst::MemberPtr(ptr, base, off));
                (ptr, fty)
            }
            LValueKind::Index(inner, idx_expr) => {
                let (base, base_ty) = self.lower_lvalue_addr(inner);
                let elem_ty = if let TypeInternal::Array(e, _) = &base_ty {
                    e.as_ref().clone()
                } else {
                    panic!("ICE")
                };
                let idx_ty = self.expr_ty(idx_expr);
                let idx = self.lower_expr_to_operand(idx_expr, &idx_ty);
                let esz = layout_of(&elem_ty, &self.checked.structs).size;
                let ptr = self.fresh_vreg();
                self.emit(Inst::IndexPtr(ptr, base, idx, esz));
                (ptr, elem_ty)
            }
        }
    }

    // Expr → VReg (scalar or address-of-compound)
    fn lower_expr_to_operand(&mut self, expr: &Expr, expected: &TypeInternal) -> VReg {
        if *expected == TypeInternal::Unit {
            self.lower_expr_discard(expr);
            return self.const_zero();
        }

        match &expr.kind {
            ExprKind::IntLiteral(val) => {
                let ir = type_internal_to_ir(expected).unwrap_or(IRType::I64);
                let v = self.fresh_vreg();
                self.emit(Inst::ConstInt(v, *val as i64, ir));
                v
            }
            ExprKind::FloatLiteral(val) => {
                let ir = type_internal_to_ir(expected).unwrap_or(IRType::F64);
                let v = self.fresh_vreg();
                self.emit(Inst::ConstFloat(v, **val, ir));
                v
            }
            ExprKind::BoolLiteral(b) => {
                let v = self.fresh_vreg();
                self.emit(Inst::ConstInt(v, *b as i64, IRType::I8));
                v
            }
            ExprKind::UnitLiteral => self.const_zero(),

            ExprKind::StringLiteral(s) => {
                let slot = self.alloc_slot(16, 8);
                let addr = self.fresh_vreg();
                self.emit(Inst::SlotAddr(addr, slot));
                self.lower_string_literal(s, addr);
                addr
            }

            ExprKind::Ident(name) => {
                let place = self.lookup(name).clone();
                match place {
                    Place::Register(v, _) => v,
                    Place::Address(addr, ref ty) if is_scalar(ty) => {
                        let ir = type_internal_to_ir(ty).unwrap();
                        let v = self.fresh_vreg();
                        self.emit(Inst::Load(v, addr, ir));
                        v
                    }
                    Place::Address(addr, _) => addr,
                }
            }

            ExprKind::BinOp { op, lhs, rhs } => self.lower_binop(op, lhs, rhs, expected),
            ExprKind::UnaryOp { op, expr: inner } => self.lower_unaryop(op, inner, expected),
            ExprKind::Cast { expr: inner, ty } => {
                let from = self.expr_ty(inner);
                let to = self.resolve_ast_type(ty);
                let src = self.lower_expr_to_operand(inner, &from);
                self.lower_cast(src, &from, &to)
            }
            ExprKind::Call { callee, args } => self.lower_call(callee, args, expected),

            ExprKind::Index { expr: arr, index } => {
                let arr_ty = self.expr_ty(arr);
                let elem_ty = if let TypeInternal::Array(e, _) = &arr_ty {
                    e.as_ref().clone()
                } else {
                    panic!("ICE")
                };
                let base = self.expr_addr_of(arr, &arr_ty);
                let idx_ty = self.expr_ty(index);
                let idx = self.lower_expr_to_operand(index, &idx_ty);
                let esz = layout_of(&elem_ty, &self.checked.structs).size;
                let ptr = self.fresh_vreg();
                self.emit(Inst::IndexPtr(ptr, base, idx, esz));
                if is_scalar(&elem_ty) {
                    let v = self.fresh_vreg();
                    self.emit(Inst::Load(v, ptr, type_internal_to_ir(&elem_ty).unwrap()));
                    v
                } else {
                    ptr
                }
            }

            ExprKind::Field { expr: inner, name } => {
                let inner_ty = self.expr_ty(inner);
                let (off, fty) = self.struct_field_offset(&inner_ty, &name.0);
                let base = self.expr_addr_of(inner, &inner_ty);
                let ptr = self.fresh_vreg();
                self.emit(Inst::MemberPtr(ptr, base, off));
                if is_scalar(&fty) {
                    let v = self.fresh_vreg();
                    self.emit(Inst::Load(v, ptr, type_internal_to_ir(&fty).unwrap()));
                    v
                } else {
                    ptr
                }
            }

            ExprKind::TupleField { expr: inner, index } => {
                let inner_ty = self.expr_ty(inner);
                let (off, ety) = self.tuple_field_offset(&inner_ty, index.0 as usize);
                let base = self.expr_addr_of(inner, &inner_ty);
                let ptr = self.fresh_vreg();
                self.emit(Inst::MemberPtr(ptr, base, off));
                if is_scalar(&ety) {
                    let v = self.fresh_vreg();
                    self.emit(Inst::Load(v, ptr, type_internal_to_ir(&ety).unwrap()));
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

            ExprKind::Block(block) => {
                self.lower_block_stmts(block);
                let r = if let Some(tail) = &block.expr {
                    self.lower_expr_to_operand(tail, expected)
                } else {
                    self.const_zero()
                };
                self.pop_scope();
                r
            }

            ExprKind::Tuple(_)
            | ExprKind::Array(_)
            | ExprKind::ArrayRepeat(_, _)
            | ExprKind::StructConstructor { .. } => {
                let slot = self.alloc_slot_for(expected);
                let addr = self.fresh_vreg();
                self.emit(Inst::SlotAddr(addr, slot));
                self.lower_expr_to_addr(expr, addr, expected);
                addr
            }
        }
    }

    // Expr → write result to memory at dst
    fn lower_expr_to_addr(&mut self, expr: &Expr, dst: VReg, ty: &TypeInternal) {
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
                let ety = if let TypeInternal::Array(e, _) = ty {
                    e.as_ref().clone()
                } else {
                    self.expr_ty(&elems[0])
                };
                let esz = layout_of(&ety, &self.checked.structs).size;
                for (i, elem) in elems.iter().enumerate() {
                    let fp = self.fresh_vreg();
                    self.emit(Inst::MemberPtr(fp, dst, i as u64 * esz));
                    self.store_or_recurse(elem, fp, &ety);
                }
            }

            ExprKind::ArrayRepeat(val, count) => {
                let ety = if let TypeInternal::Array(e, _) = ty {
                    e.as_ref().clone()
                } else {
                    self.expr_ty(val)
                };
                let n = if let ExprKind::IntLiteral(c) = count.kind {
                    c
                } else {
                    panic!("ICE")
                };
                let esz = layout_of(&ety, &self.checked.structs).size;
                for i in 0..n {
                    let fp = self.fresh_vreg();
                    self.emit(Inst::MemberPtr(fp, dst, i * esz));
                    self.store_or_recurse(val, fp, &ety);
                }
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

            ExprKind::Ident(name) => {
                let place = self.lookup(name).clone();
                match place {
                    Place::Address(src, _) => {
                        let sz = layout_of(ty, &self.checked.structs).size;
                        self.emit(Inst::MemCopy { dst, src, size: sz });
                    }
                    Place::Register(v, ir) => self.emit(Inst::Store(dst, v, ir)),
                }
            }

            ExprKind::Block(block) => {
                self.lower_block_stmts(block);
                if let Some(tail) = &block.expr {
                    self.lower_expr_to_addr(tail, dst, ty);
                }
                self.pop_scope();
            }

            ExprKind::If {
                cond,
                then_block,
                else_block,
            } => self.lower_if_to_addr(cond, then_block, else_block.as_ref(), dst, ty),

            ExprKind::Call { callee, args } => {
                let v = self.lower_call(callee, args, ty);
                if is_compound(ty) {
                    let sz = layout_of(ty, &self.checked.structs).size;
                    self.emit(Inst::MemCopy {
                        dst,
                        src: v,
                        size: sz,
                    });
                }
            }

            ExprKind::Field {
                expr: inner,
                name: fname,
            } => {
                let it = self.expr_ty(inner);
                let (off, fty) = self.struct_field_offset(&it, &fname.0);
                let base = self.expr_addr_of(inner, &it);
                let ptr = self.fresh_vreg();
                self.emit(Inst::MemberPtr(ptr, base, off));
                self.copy_to_dst(dst, ptr, &fty);
            }

            ExprKind::TupleField { expr: inner, index } => {
                let it = self.expr_ty(inner);
                let (off, ety) = self.tuple_field_offset(&it, index.0 as usize);
                let base = self.expr_addr_of(inner, &it);
                let ptr = self.fresh_vreg();
                self.emit(Inst::MemberPtr(ptr, base, off));
                self.copy_to_dst(dst, ptr, &ety);
            }

            _ => {
                let v = self.lower_expr_to_operand(expr, ty);
                self.emit(Inst::Store(dst, v, type_internal_to_ir(ty).unwrap()));
            }
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
        } else {
            let sz = layout_of(ty, &self.checked.structs).size;
            self.emit(Inst::MemCopy { dst, src, size: sz });
        }
    }

    fn expr_addr_of(&mut self, expr: &Expr, ty: &TypeInternal) -> VReg {
        if let ExprKind::Ident(name) = &expr.kind {
            let place = self.lookup(name).clone();
            match place {
                Place::Address(addr, _) => return addr,
                Place::Register(v, ir) => {
                    let slot = self.alloc_slot(ir.size(), ir.size());
                    let addr = self.fresh_vreg();
                    self.emit(Inst::SlotAddr(addr, slot));
                    self.emit(Inst::Store(addr, v, ir));
                    return addr;
                }
            }
        }
        let slot = self.alloc_slot_for(ty);
        let addr = self.fresh_vreg();
        self.emit(Inst::SlotAddr(addr, slot));
        self.lower_expr_to_addr(expr, addr, ty);
        addr
    }

    fn lower_expr_discard(&mut self, expr: &Expr) {
        match &expr.kind {
            ExprKind::Call { callee, args } => {
                self.lower_call(callee, args, &TypeInternal::Unit);
            }
            ExprKind::Block(b) => {
                self.lower_block_stmts(b);
                if let Some(tail) = &b.expr {
                    self.lower_expr_discard(tail);
                }
                self.pop_scope();
            }
            ExprKind::If {
                cond,
                then_block,
                else_block,
            } => {
                self.lower_if_expr(cond, then_block, else_block.as_ref(), &TypeInternal::Unit);
            }
            _ => {
                let ty = self.expr_ty(expr);
                if ty != TypeInternal::Unit {
                    let _ = self.lower_expr_to_operand(expr, &ty);
                }
            }
        }
    }

    // String literal
    fn lower_string_literal(&mut self, s: &str, dst: VReg) {
        let idx = self.strings.len();
        self.strings.push(StringConstant {
            label: format!("__str{}", idx),
            bytes: s.as_bytes().to_vec(),
        });
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
    fn lower_binop(
        &mut self,
        op: &BinOp,
        lhs: &Expr,
        rhs: &Expr,
        _expected: &TypeInternal,
    ) -> VReg {
        if matches!(op, BinOp::And) {
            return self.lower_sc_and(lhs, rhs);
        }
        if matches!(op, BinOp::Or) {
            return self.lower_sc_or(lhs, rhs);
        }

        let lhs_ty = self.expr_ty(lhs);
        let a = self.lower_expr_to_operand(lhs, &lhs_ty);
        let rhs_ty = if matches!(op, BinOp::Shl | BinOp::Shr) {
            self.expr_ty(rhs)
        } else {
            lhs_ty.clone()
        };
        let b = self.lower_expr_to_operand(rhs, &rhs_ty);
        let ir = type_internal_to_ir(&lhs_ty).unwrap_or(IRType::I64);
        let signed = lhs_ty.is_signed();
        let d = self.fresh_vreg();

        match op {
            BinOp::Add => {
                if ir.is_float() {
                    self.emit(Inst::FAdd(d, a, b, ir))
                } else {
                    self.emit(Inst::IAdd(d, a, b, ir))
                }
            }
            BinOp::Sub => {
                if ir.is_float() {
                    self.emit(Inst::FSub(d, a, b, ir))
                } else {
                    self.emit(Inst::ISub(d, a, b, ir))
                }
            }
            BinOp::Mul => {
                if ir.is_float() {
                    self.emit(Inst::FMul(d, a, b, ir))
                } else {
                    self.emit(Inst::IMul(d, a, b, ir))
                }
            }
            BinOp::Div => {
                if ir.is_float() {
                    self.emit(Inst::FDiv(d, a, b, ir))
                } else {
                    self.emit(Inst::IDiv(d, a, b, ir, signed))
                }
            }
            BinOp::Mod => {
                if ir.is_float() {
                    let f = if ir == IRType::F64 { "fmod" } else { "fmodf" };
                    self.emit(Inst::Call {
                        dst: Some((d, ir)),
                        func: f.into(),
                        args: vec![(a, ir), (b, ir)],
                    });
                } else {
                    self.emit(Inst::IMod(d, a, b, ir, signed))
                }
            }
            BinOp::Pow => {
                if ir.is_float() {
                    let f = if ir == IRType::F64 { "pow" } else { "powf" };
                    self.emit(Inst::Call {
                        dst: Some((d, ir)),
                        func: f.into(),
                        args: vec![(a, ir), (b, ir)],
                    });
                } else {
                    self.emit(Inst::Call {
                        dst: Some((d, ir)),
                        func: "__ipow".into(),
                        args: vec![(a, ir), (b, ir)],
                    });
                }
            }
            BinOp::Shl => self.emit(Inst::IShl(d, a, b, ir)),
            BinOp::Shr => self.emit(Inst::IShr(d, a, b, ir, signed)),
            BinOp::BitAnd => self.emit(Inst::IBitAnd(d, a, b, ir)),
            BinOp::BitOr => self.emit(Inst::IBitOr(d, a, b, ir)),
            BinOp::BitXor => self.emit(Inst::IBitXor(d, a, b, ir)),
            BinOp::Eq | BinOp::Neq | BinOp::Lt | BinOp::Gt | BinOp::LtEq | BinOp::GtEq => {
                let c = match op {
                    BinOp::Eq => CmpOp::Eq,
                    BinOp::Neq => CmpOp::Neq,
                    BinOp::Lt => CmpOp::Lt,
                    BinOp::Gt => CmpOp::Gt,
                    BinOp::LtEq => CmpOp::LtEq,
                    _ => CmpOp::GtEq,
                };
                if ir.is_float() {
                    self.emit(Inst::FCmp(d, c, a, b, ir))
                } else {
                    self.emit(Inst::ICmp(d, c, a, b, ir, signed))
                }
            }
            BinOp::And | BinOp::Or => unreachable!(),
        }
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
            UnaryOp::Pos => {
                let ty = self.expr_ty(inner);
                self.lower_expr_to_operand(inner, &ty)
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

    // Function call
    fn lower_call(&mut self, callee: &Expr, args: &[Expr], expected: &TypeInternal) -> VReg {
        let ptys = self.call_param_tys(callee);
        let mut ir_args = Vec::new();
        for (i, arg) in args.iter().enumerate() {
            let pty = &ptys[i];
            if is_scalar(pty) {
                let v = self.lower_expr_to_operand(arg, pty);
                ir_args.push((v, type_internal_to_ir(pty).unwrap()));
            } else {
                let addr = self.expr_addr_of(arg, pty);
                ir_args.push((addr, IRType::Ptr));
            }
        }

        let is_direct = if let ExprKind::Ident(n) = &callee.kind {
            self.checked.functions.contains_key(n)
        } else {
            false
        };

        if *expected == TypeInternal::Unit {
            if is_direct {
                let n = if let ExprKind::Ident(n) = &callee.kind {
                    n.clone()
                } else {
                    unreachable!()
                };
                self.emit(Inst::Call {
                    dst: None,
                    func: n,
                    args: ir_args,
                });
            } else {
                let cv = self.lower_expr_to_operand(callee, &self.expr_ty(callee));
                self.emit(Inst::CallIndirect {
                    dst: None,
                    callee: cv,
                    args: ir_args,
                });
            }
            return self.const_zero();
        }
        let ri = type_internal_to_ir(expected).unwrap_or(IRType::Ptr);
        let d = self.fresh_vreg();
        if is_direct {
            let n = if let ExprKind::Ident(n) = &callee.kind {
                n.clone()
            } else {
                unreachable!()
            };
            self.emit(Inst::Call {
                dst: Some((d, ri)),
                func: n,
                args: ir_args,
            });
        } else {
            let cv = self.lower_expr_to_operand(callee, &self.expr_ty(callee));
            self.emit(Inst::CallIndirect {
                dst: Some((d, ri)),
                callee: cv,
                args: ir_args,
            });
        }
        d
    }

    // If expressions
    fn lower_if_expr(
        &mut self,
        cond: &Expr,
        then_b: &Block,
        else_b: Option<&Block>,
        expected: &TypeInternal,
    ) -> VReg {
        let cv = self.lower_expr_to_operand(cond, &TypeInternal::Bool);

        if *expected == TypeInternal::Unit || else_b.is_none() {
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
            self.lower_block_stmts(then_b);
            if let Some(t) = &then_b.expr {
                self.lower_expr_discard(t);
            }
            self.pop_scope();
            self.seal(Term::Jump(merge));
            if let Some(eb) = else_b {
                self.start(ebb);
                self.lower_block_stmts(eb);
                if let Some(t) = &eb.expr {
                    self.lower_expr_discard(t);
                }
                self.pop_scope();
                self.seal(Term::Jump(merge));
            }
            self.start(merge);
            return self.const_zero();
        }

        let eb = else_b.unwrap();
        if is_scalar(expected) {
            let tbb = self.fresh_bb();
            let ebb = self.fresh_bb();
            let merge = self.fresh_bb();
            let ir = type_internal_to_ir(expected).unwrap();
            let slot = self.alloc_slot(ir.size(), ir.size());
            self.seal(Term::CondBr {
                cond: cv,
                then_bb: tbb,
                else_bb: ebb,
            });

            self.start(tbb);
            self.lower_block_stmts(then_b);
            let tv = if let Some(t) = &then_b.expr {
                self.lower_expr_to_operand(t, expected)
            } else {
                self.const_zero()
            };
            let s1 = self.fresh_vreg();
            self.emit(Inst::SlotAddr(s1, slot));
            self.emit(Inst::Store(s1, tv, ir));
            self.pop_scope();
            self.seal(Term::Jump(merge));

            self.start(ebb);
            self.lower_block_stmts(eb);
            let ev = if let Some(t) = &eb.expr {
                self.lower_expr_to_operand(t, expected)
            } else {
                self.const_zero()
            };
            let s2 = self.fresh_vreg();
            self.emit(Inst::SlotAddr(s2, slot));
            self.emit(Inst::Store(s2, ev, ir));
            self.pop_scope();
            self.seal(Term::Jump(merge));

            self.start(merge);
            let r = self.fresh_vreg();
            let s3 = self.fresh_vreg();
            self.emit(Inst::SlotAddr(s3, slot));
            self.emit(Inst::Load(r, s3, ir));
            r
        } else {
            let slot = self.alloc_slot_for(expected);
            let addr = self.fresh_vreg();
            self.emit(Inst::SlotAddr(addr, slot));
            self.lower_if_to_addr(cond, then_b, else_b, addr, expected);
            addr
        }
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
        self.lower_block_stmts(then_b);
        if let Some(t) = &then_b.expr {
            self.lower_expr_to_addr(t, dst, ty);
        }
        self.pop_scope();
        self.seal(Term::Jump(merge));
        if let Some(eb) = else_b {
            self.start(ebb);
            self.lower_block_stmts(eb);
            if let Some(t) = &eb.expr {
                self.lower_expr_to_addr(t, dst, ty);
            }
            self.pop_scope();
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
        parse(&crate::lexer::Lexer::new(src).tokenize().unwrap())
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
        let s = ir_str("fn f() { let i: i32 = 0; loop { if i == 10 { break; }; i += 1; } }");
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
        let s = ir_str("fn f() { let x: i32 = 1; x += 10; }");
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
    fn test_power_int() {
        let s = ir_str("fn f() -> i64 { 2 ** 10 }");
        assert!(s.contains("call") && s.contains("__ipow"));
    }
    #[test]
    fn test_power_float() {
        let s = ir_str("fn f() -> f64 { let x: f64 = 2.0; x ** 3.0 }");
        assert!(s.contains("call") && s.contains("pow"));
    }
    #[test]
    fn test_continue() {
        let s = ir_str(
            "fn f() { let i: i32 = 0; loop { i += 1; if i == 5 { continue; }; if i == 10 { break; }; } }",
        );
        assert!(s.contains("jmp bb"));
    }
    #[test]
    fn test_array_repeat() {
        let s = ir_str("fn f() -> i64 { let a = [0; 5]; a[3] }");
        assert!(s.contains("indexptr"));
    }
}
