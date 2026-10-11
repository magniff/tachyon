// The lowered IR: functions of basic blocks over virtual registers (vregs)
// and stack slots. Not SSA: every local lives in a slot, and a vreg holds a
// scalar or the address of a compound value.

use std::fmt;

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
    // Size in bytes.
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
        let name = match self {
            IRType::I8 => "i8",
            IRType::I16 => "i16",
            IRType::I32 => "i32",
            IRType::I64 => "i64",
            IRType::F32 => "f32",
            IRType::F64 => "f64",
            IRType::Ptr => "ptr",
        };
        f.write_str(name)
    }
}

// A virtual register.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct VReg(pub u32);

impl fmt::Display for VReg {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "v{}", self.0)
    }
}

// A stack slot: an index into IRFunction::slots.
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
        let name = match self {
            CmpOp::Eq => "eq",
            CmpOp::Neq => "neq",
            CmpOp::Lt => "lt",
            CmpOp::Gt => "gt",
            CmpOp::LtEq => "le",
            CmpOp::GtEq => "ge",
        };
        f.write_str(name)
    }
}

// Instructions. The first vreg is the destination; a trailing `bool` says
// whether the operation is signed (for shifts: arithmetic).
#[derive(Debug, Clone)]
pub enum Inst {
    // dst = lhs op rhs
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

    // dst = lhs op rhs, a bool (i8); the IRType is the operands'.
    ICmp(VReg, CmpOp, VReg, VReg, IRType, bool),
    FCmp(VReg, CmpOp, VReg, VReg, IRType),
    BoolNot(VReg, VReg),

    ConstInt(VReg, i64, IRType),
    ConstFloat(VReg, f64, IRType),
    // Address of IrProgram::strings[index]
    ConstStringPtr(VReg, usize),

    // dst = convert(src) from the first IRType to the second.
    IntToFloat(VReg, VReg, IRType, IRType, bool),
    FloatToInt(VReg, VReg, IRType, IRType, bool),
    FloatToFloat(VReg, VReg, IRType, IRType),
    IntExt(VReg, VReg, IRType, IRType, bool),
    IntTrunc(VReg, VReg, IRType, IRType),

    // dst = *addr
    Load(VReg, VReg, IRType),
    // *addr = value
    Store(VReg, VReg, IRType),
    // Copies `size` bytes; the regions may overlap.
    MemCopy {
        dst: VReg,
        src: VReg,
        size: u64,
    },

    SlotAddr(VReg, Slot),
    // Address of IrProgram::globals[index]
    GlobalAddr(VReg, usize),
    // dst = base + offset
    MemberPtr(VReg, VReg, u64),
    // dst = base + index * element size
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

#[derive(Debug, Clone)]
pub struct BasicBlock {
    pub id: BlockId,
    pub instructions: Vec<Inst>,
    pub terminator: Term,
}

#[derive(Debug, Clone)]
pub struct IRFunction {
    pub name: String,
    pub params: Vec<(VReg, IRType)>,
    // The scalar result type, if any. A function with a compound result
    // takes a hidden sret pointer as its first parameter and returns it.
    pub return_type: Option<IRType>,
    pub slots: Vec<SlotInfo>,
    pub blocks: Vec<BasicBlock>,
    // Vregs are numbered 0..vreg_count.
    pub vreg_count: u32,
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
