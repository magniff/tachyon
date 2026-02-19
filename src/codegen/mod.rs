// x86-64 NASM Code Generator
// "Spill everything" allocator: every vreg lives at [rbp-N].
// System V AMD64 ABI.

use crate::lowering::*;
use std::collections::HashMap;
use std::fmt::Write;

const INT_ARGS: [&str; 6] = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"];

pub struct GeneratorError {
    pub message: String,
}

impl From<std::fmt::Error> for GeneratorError {
    fn from(value: std::fmt::Error) -> Self {
        Self {
            message: value.to_string(),
        }
    }
}

fn sz_word(b: u64) -> &'static str {
    match b {
        1 => "byte",
        2 => "word",
        4 => "dword",
        8 => "qword",
        _ => panic!("sz {}", b),
    }
}

fn rax(b: u64) -> &'static str {
    match b {
        1 => "al",
        2 => "ax",
        4 => "eax",
        8 => "rax",
        _ => panic!(),
    }
}

fn rcx(b: u64) -> &'static str {
    match b {
        1 => "cl",
        2 => "cx",
        4 => "ecx",
        8 => "rcx",
        _ => panic!(),
    }
}

// Frame: maps vregs and slots to [rbp+offset]
struct Frame {
    voff: HashMap<u32, i64>,
    soff: Vec<i64>,
    size: u64,
}

fn frame(function: &IRFunction) -> Frame {
    let mut off: i64 = 0;
    let mut soff = Vec::new();
    for slot in &function.slots {
        let align = slot.align.max(1) as i64;
        off -= slot.size as i64;
        off &= !(align - 1);
        soff.push(off);
    }
    let mut voff = HashMap::new();
    for vreg_num in 0..function.vreg_counter {
        off -= 8;
        voff.insert(vreg_num, off);
    }
    Frame {
        voff,
        soff,
        size: ((-off) as u64 + 15) & !15,
    }
}

// Load vreg into integer register (always 8 bytes — st always writes full rax)
fn load(o: &mut String, r: &str, v: u32, frame: &Frame) {
    let p = frame.voff[&v];
    writeln!(o, "  mov {}, [rbp{:+}]", r, p).unwrap();
}

// Store integer register to vreg (always 8 bytes to keep slot clean)
fn store(o: &mut String, r: &str, v: u32, frame: &Frame) {
    writeln!(o, "  mov [rbp{:+}], {}", frame.voff[&v], r).unwrap();
}

fn load_float(o: &mut String, xmm: &str, v: u32, ty: IRType, frame: &Frame) {
    let m = if ty == IRType::F64 { "movsd" } else { "movss" };
    writeln!(o, "  {} {}, [rbp{:+}]", m, xmm, frame.voff[&v]).unwrap();
}

fn store_float(o: &mut String, xmm: &str, v: u32, ty: IRType, f: &Frame) {
    let m = if ty == IRType::F64 { "movsd" } else { "movss" };
    writeln!(o, "  {} [rbp{:+}], {}", m, f.voff[&v], xmm).unwrap();
}

fn idiv(o: &mut String, sz: u64, signed: bool) {
    if signed {
        match sz {
            1 => {
                writeln!(o, "  cbw").unwrap();
                writeln!(o, "  idiv cl").unwrap();
            }
            2 => {
                writeln!(o, "  cwd").unwrap();
                writeln!(o, "  idiv cx").unwrap();
            }
            4 => {
                writeln!(o, "  cdq").unwrap();
                writeln!(o, "  idiv ecx").unwrap();
            }
            8 => {
                writeln!(o, "  cqo").unwrap();
                writeln!(o, "  idiv rcx").unwrap();
            }
            _ => panic!(),
        }
    } else {
        writeln!(o, "  xor edx, edx").unwrap();
        match sz {
            1 => writeln!(o, "  div cl").unwrap(),
            2 => writeln!(o, "  div cx").unwrap(),
            4 => writeln!(o, "  div ecx").unwrap(),
            8 => writeln!(o, "  div rcx").unwrap(),
            _ => panic!(),
        }
    }
}

fn ibin(o: &mut String, op: &str, d: &VReg, a: &VReg, b: &VReg, ty: IRType, f: &Frame) {
    let s = ty.size();
    load(o, "rax", a.0, f);
    load(o, "rcx", b.0, f);
    writeln!(o, "  {} {}, {}", op, rax(s), rcx(s)).unwrap();
    store(o, "rax", d.0, f);
}

fn fbin(
    o: &mut String,
    op64: &str,
    op32: &str,
    d: &VReg,
    a: &VReg,
    b: &VReg,
    ty: IRType,
    f: &Frame,
) {
    load_float(o, "xmm0", a.0, ty, f);
    load_float(o, "xmm1", b.0, ty, f);
    writeln!(
        o,
        "  {} xmm0, xmm1",
        if ty == IRType::F64 { op64 } else { op32 }
    )
    .unwrap();
    store_float(o, "xmm0", d.0, ty, f);
}

fn call_args(o: &mut String, args: &[(VReg, IRType)], f: &Frame) {
    let mut ii = 0usize;
    let mut fi = 0usize;
    let mut stk = Vec::new();
    for (v, ty) in args {
        if ty.is_float() {
            if fi < 8 {
                load_float(o, &format!("xmm{}", fi), v.0, *ty, f);
                fi += 1;
            } else {
                stk.push((*v, *ty));
            }
        } else {
            if ii < 6 {
                load(o, INT_ARGS[ii], v.0, f);
                ii += 1;
            } else {
                stk.push((*v, *ty));
            }
        }
    }
    for (v, ty) in stk.iter().rev() {
        if ty.is_float() {
            load_float(o, "xmm15", v.0, *ty, f);
            writeln!(o, "  sub rsp, 8").unwrap();
            writeln!(o, "  movsd [rsp], xmm15").unwrap();
        } else {
            load(o, "rax", v.0, f);
            writeln!(o, "  push rax").unwrap();
        }
    }
    if fi > 0 {
        writeln!(o, "  mov al, {}", fi).unwrap();
    } else {
        writeln!(o, "  xor eax, eax").unwrap();
    }
}

// Public entry
pub fn generate(prog: &IrProgram) -> Result<String, GeneratorError> {
    let mut o = String::new();
    writeln!(o, "bits 64")?;
    writeln!(o, "default rel")?;
    writeln!(o, "section .note.GNU-stack noalloc noexec nowrite progbits")?;
    writeln!(o)?;

    for func in &prog.functions {
        if func.is_extern {
            writeln!(o, "extern {}", func.name)?;
        }
    }
    writeln!(o)?;

    // Collect float constants
    let mut fcs: Vec<(String, f64, IRType)> = Vec::new();
    for func in &prog.functions {
        for bb in &func.blocks {
            for inst in &bb.instructions {
                if let Inst::ConstFloat(_, val, ty) = inst {
                    fcs.push((format!("__flt{}", fcs.len()), *val, *ty));
                }
            }
        }
    }

    // .data: strings (null-terminated for C interop)
    writeln!(o, "section .data")?;
    for sc in &prog.strings {
        write!(o, "  {}: db ", sc.label)?;
        for (i, b) in sc.bytes.iter().enumerate() {
            if i > 0 {
                write!(o, ", ")?;
            }
            write!(o, "0x{:02x}", b)?;
        }
        // Always append null terminator for C string compat
        if !sc.bytes.is_empty() {
            write!(o, ", ")?;
        }
        writeln!(o, "0x00")?;
    }
    writeln!(o)?;

    // .rodata: float constants
    writeln!(o, "section .rodata")?;
    for (label, val, ty) in &fcs {
        if *ty == IRType::F64 {
            writeln!(o, "  {}: dq {:.20e}", label, val)?;
        } else {
            writeln!(o, "  {}: dd {:e}", label, *val as f32)?;
        }
    }
    writeln!(o)?;

    // .text
    writeln!(o, "section .text")?;
    for func in &prog.functions {
        if !func.is_extern {
            writeln!(o, "global {}", func.name)?;
        }
    }
    writeln!(o)?;

    let mut fi_global = 0usize;

    for func in &prog.functions {
        if func.is_extern {
            continue;
        }
        let f = frame(func);

        writeln!(o, "{}:", func.name)?;
        writeln!(o, "  push rbp")?;
        writeln!(o, "  mov rbp, rsp")?;
        if f.size > 0 {
            writeln!(o, "  sub rsp, {}", f.size)?;
        }

        // Store incoming params
        let mut ii = 0usize;
        let mut ffi = 0usize;
        for (v, ty) in &func.params {
            if ty.is_float() {
                store_float(&mut o, &format!("xmm{}", ffi), v.0, *ty, &f);
                ffi += 1;
            } else {
                writeln!(o, "  mov [rbp{:+}], {}", f.voff[&v.0], INT_ARGS[ii])?;
                ii += 1;
            }
        }

        // Emit blocks
        for bb in &func.blocks {
            writeln!(o, ".L{}_bb{}:", func.name, bb.id.0)?;
            for inst in &bb.instructions {
                emit_inst(&mut o, inst, &f, &fcs, &mut fi_global, &prog.strings);
            }
            emit_term(&mut o, &bb.teminator, &f, &func.name);
        }
        writeln!(o)?;
    }

    emit_ipow(&mut o);

    Ok(o)
}

fn emit_inst(
    o: &mut String,
    inst: &Inst,
    f: &Frame,
    fcs: &[(String, f64, IRType)],
    fi: &mut usize,
    strs: &[StringConstant],
) {
    match inst {
        Inst::IAdd(d, a, b, t) => ibin(o, "add", d, a, b, *t, f),
        Inst::ISub(d, a, b, t) => ibin(o, "sub", d, a, b, *t, f),
        Inst::IBitAnd(d, a, b, t) => ibin(o, "and", d, a, b, *t, f),
        Inst::IBitOr(d, a, b, t) => ibin(o, "or", d, a, b, *t, f),
        Inst::IBitXor(d, a, b, t) => ibin(o, "xor", d, a, b, *t, f),
        Inst::IMul(d, a, b, t) => {
            let s = t.size();
            load(o, "rax", a.0, f);
            load(o, "rcx", b.0, f);
            writeln!(o, "  imul {}, {}", rax(s), rcx(s)).unwrap();
            store(o, "rax", d.0, f);
        }
        Inst::IDiv(d, a, b, t, sg) => {
            let s = t.size();
            load(o, "rax", a.0, f);
            load(o, "rcx", b.0, f);
            idiv(o, s, *sg);
            store(o, "rax", d.0, f);
        }
        Inst::IMod(d, a, b, t, sg) => {
            let s = t.size();
            load(o, "rax", a.0, f);
            load(o, "rcx", b.0, f);
            idiv(o, s, *sg);
            store(o, "rdx", d.0, f);
        }
        Inst::IShl(d, a, b, t) => {
            let s = t.size();
            load(o, "rax", a.0, f);
            load(o, "rcx", b.0, f);
            writeln!(o, "  shl {}, cl", rax(s)).unwrap();
            store(o, "rax", d.0, f);
        }
        Inst::IShr(d, a, b, t, sg) => {
            let s = t.size();
            load(o, "rax", a.0, f);
            load(o, "rcx", b.0, f);
            writeln!(o, "  {} {}, cl", if *sg { "sar" } else { "shr" }, rax(s)).unwrap();
            store(o, "rax", d.0, f);
        }
        Inst::INeg(d, a, t) => {
            let s = t.size();
            load(o, "rax", a.0, f);
            writeln!(o, "  neg {}", rax(s)).unwrap();
            store(o, "rax", d.0, f);
        }
        Inst::IBitNot(d, a, t) => {
            let s = t.size();
            load(o, "rax", a.0, f);
            writeln!(o, "  not {}", rax(s)).unwrap();
            store(o, "rax", d.0, f);
        }
        Inst::FAdd(d, a, b, t) => fbin(o, "addsd", "addss", d, a, b, *t, f),
        Inst::FSub(d, a, b, t) => fbin(o, "subsd", "subss", d, a, b, *t, f),
        Inst::FMul(d, a, b, t) => fbin(o, "mulsd", "mulss", d, a, b, *t, f),
        Inst::FDiv(d, a, b, t) => fbin(o, "divsd", "divss", d, a, b, *t, f),
        Inst::FNeg(d, a, t) => {
            load_float(o, "xmm0", a.0, *t, f);
            if *t == IRType::F64 {
                writeln!(o, "  mov rax, 0x8000000000000000").unwrap();
                writeln!(o, "  movq xmm1, rax").unwrap();
                writeln!(o, "  xorpd xmm0, xmm1").unwrap();
            } else {
                writeln!(o, "  mov eax, 0x80000000").unwrap();
                writeln!(o, "  movd xmm1, eax").unwrap();
                writeln!(o, "  xorps xmm0, xmm1").unwrap();
            }
            store_float(o, "xmm0", d.0, *t, f);
        }
        Inst::ICmp(d, op, a, b, t, sg) => {
            let s = t.size();
            load(o, "rax", a.0, f);
            load(o, "rcx", b.0, f);
            writeln!(o, "  cmp {}, {}", rax(s), rcx(s)).unwrap();
            let cc = match (op, sg) {
                (CmpOp::Eq, _) => "sete",
                (CmpOp::Neq, _) => "setne",
                (CmpOp::Lt, true) => "setl",
                (CmpOp::Lt, false) => "setb",
                (CmpOp::Gt, true) => "setg",
                (CmpOp::Gt, false) => "seta",
                (CmpOp::LtEq, true) => "setle",
                (CmpOp::LtEq, false) => "setbe",
                (CmpOp::GtEq, true) => "setge",
                (CmpOp::GtEq, false) => "setae",
            };
            writeln!(o, "  {} al", cc).unwrap();
            writeln!(o, "  movzx eax, al").unwrap();
            store(o, "rax", d.0, f);
        }
        Inst::FCmp(d, op, a, b, t) => {
            load_float(o, "xmm0", a.0, *t, f);
            load_float(o, "xmm1", b.0, *t, f);
            writeln!(
                o,
                "  {} xmm0, xmm1",
                if *t == IRType::F64 {
                    "comisd"
                } else {
                    "comiss"
                }
            )
            .unwrap();
            let cc = match op {
                CmpOp::Eq => "sete",
                CmpOp::Neq => "setne",
                CmpOp::Lt => "setb",
                CmpOp::Gt => "seta",
                CmpOp::LtEq => "setbe",
                CmpOp::GtEq => "setae",
            };
            writeln!(o, "  {} al", cc).unwrap();
            writeln!(o, "  movzx eax, al").unwrap();
            store(o, "rax", d.0, f);
        }
        Inst::BoolNot(d, a) => {
            load(o, "rax", a.0, f);
            writeln!(o, "  xor al, 1").unwrap();
            store(o, "rax", d.0, f);
        }

        Inst::ConstInt(d, val, t) => {
            let s = t.size();
            if *val == 0 {
                writeln!(o, "  xor eax, eax").unwrap();
            } else if s <= 4 {
                writeln!(o, "  mov {}, {}", rax(s), *val as i32).unwrap();
            } else {
                writeln!(o, "  mov rax, {}", val).unwrap();
            }
            store(o, "rax", d.0, f);
        }
        Inst::ConstFloat(d, _, t) => {
            let lbl = &fcs[*fi].0;
            writeln!(
                o,
                "  {} xmm0, [{}]",
                if *t == IRType::F64 { "movsd" } else { "movss" },
                lbl
            )
            .unwrap();
            store_float(o, "xmm0", d.0, *t, f);
            *fi += 1;
        }
        Inst::ConstStringPtr(d, idx) => {
            writeln!(o, "  lea rax, [{}]", strs[*idx].label).unwrap();
            store(o, "rax", d.0, f);
        }
        Inst::IntToFloat(d, s, from, to, signed) => {
            let fs = from.size();
            load(o, "rax", s.0, f);
            if *signed && fs < 4 {
                writeln!(o, "  movsx eax, {}", rax(fs)).unwrap();
            } else if !signed && fs < 8 && fs > 1 {
                writeln!(o, "  movzx eax, {}", rax(fs)).unwrap();
            }
            let cvt = if *to == IRType::F64 {
                "cvtsi2sd"
            } else {
                "cvtsi2ss"
            };
            if fs <= 4 {
                writeln!(o, "  {} xmm0, eax", cvt).unwrap();
            } else {
                writeln!(o, "  {} xmm0, rax", cvt).unwrap();
            }
            store_float(o, "xmm0", d.0, *to, f);
        }
        Inst::FloatToInt(d, s, from, to, _) => {
            load_float(o, "xmm0", s.0, *from, f);
            let cvt = if *from == IRType::F64 {
                "cvttsd2si"
            } else {
                "cvttss2si"
            };
            if to.size() <= 4 {
                writeln!(o, "  {} eax, xmm0", cvt).unwrap();
            } else {
                writeln!(o, "  {} rax, xmm0", cvt).unwrap();
            }
            store(o, "rax", d.0, f);
        }
        Inst::FloatToFloat(d, s, from, to) => {
            load_float(o, "xmm0", s.0, *from, f);
            if *from == IRType::F32 {
                writeln!(o, "  cvtss2sd xmm0, xmm0").unwrap();
            } else {
                writeln!(o, "  cvtsd2ss xmm0, xmm0").unwrap();
            }
            store_float(o, "xmm0", d.0, *to, f);
        }
        Inst::IntExt(d, s, from, to, signed) => {
            let fs = from.size();
            let ts = to.size();
            load(o, "rax", s.0, f);
            if *signed {
                match (fs, ts) {
                    (1, 2) => {
                        writeln!(o, "  movsx ax, al").unwrap();
                    }
                    (1, 4) | (1, 8) => {
                        writeln!(o, "  movsx eax, al").unwrap();
                    }
                    (2, 4) | (2, 8) => {
                        writeln!(o, "  movsx eax, ax").unwrap();
                    }
                    (4, 8) => {
                        writeln!(o, "  movsxd rax, eax").unwrap();
                    }
                    _ => {}
                }
            } else {
                match (fs, ts) {
                    (1, _) => {
                        writeln!(o, "  movzx eax, al").unwrap();
                    }
                    (2, _) => {
                        writeln!(o, "  movzx eax, ax").unwrap();
                    }
                    (4, 8) => {
                        writeln!(o, "  mov eax, eax").unwrap();
                    }
                    _ => {}
                }
            }
            store(o, "rax", d.0, f);
        }
        Inst::IntTrunc(d, s, _, _) => {
            load(o, "rax", s.0, f);
            store(o, "rax", d.0, f);
        }
        Inst::Load(d, addr, t) => {
            let s = t.size();
            load(o, "rax", addr.0, f);
            if t.is_float() {
                writeln!(
                    o,
                    "  {} xmm0, [rax]",
                    if *t == IRType::F64 { "movsd" } else { "movss" }
                )
                .unwrap();
                store_float(o, "xmm0", d.0, *t, f);
            } else {
                match s {
                    1 => writeln!(o, "  movzx rax, byte [rax]").unwrap(),
                    2 => writeln!(o, "  movzx rax, word [rax]").unwrap(),
                    4 => writeln!(o, "  mov eax, [rax]").unwrap(), // zero-extends to rax
                    8 => writeln!(o, "  mov rax, [rax]").unwrap(),
                    _ => panic!("load sz {}", s),
                }
                store(o, "rax", d.0, f);
            }
        }
        Inst::Store(addr, val, t) => {
            let s = t.size();
            load(o, "rcx", addr.0, f);
            if t.is_float() {
                load_float(o, "xmm0", val.0, *t, f);
                writeln!(
                    o,
                    "  {} [rcx], xmm0",
                    if *t == IRType::F64 { "movsd" } else { "movss" }
                )
                .unwrap();
            } else {
                load(o, "rax", val.0, f);
                writeln!(o, "  mov {} [rcx], {}", sz_word(s), rax(s)).unwrap();
            }
        }
        Inst::MemCopy { dst, src, size } => {
            if *size == 0 {
                return;
            }
            load(o, "rdi", dst.0, f);
            load(o, "rsi", src.0, f);
            writeln!(o, "  mov rcx, {}", size).unwrap();
            writeln!(o, "  rep movsb").unwrap();
        }
        Inst::SlotAddr(d, slot) => {
            writeln!(o, "  lea rax, [rbp{:+}]", f.soff[slot.0 as usize]).unwrap();
            store(o, "rax", d.0, f);
        }
        Inst::MemberPtr(d, base, off) => {
            load(o, "rax", base.0, f);
            if *off != 0 {
                writeln!(o, "  add rax, {}", off).unwrap();
            }
            store(o, "rax", d.0, f);
        }
        Inst::IndexPtr(d, base, idx, esz) => {
            load(o, "rax", base.0, f);
            load(o, "rcx", idx.0, f);
            if *esz > 1 {
                writeln!(o, "  imul rcx, {}", esz).unwrap();
            }
            writeln!(o, "  add rax, rcx").unwrap();
            store(o, "rax", d.0, f);
        }

        Inst::Call { dst, func, args } => {
            call_args(o, args, f);
            writeln!(o, "  call {}", func).unwrap();
            if let Some((d, t)) = dst {
                if t.is_float() {
                    store_float(o, "xmm0", d.0, *t, f);
                } else {
                    store(o, "rax", d.0, f);
                }
            }
        }
        Inst::CallIndirect { dst, callee, args } => {
            call_args(o, args, f);
            load(o, "r10", callee.0, f);
            writeln!(o, "  call r10").unwrap();
            if let Some((d, t)) = dst {
                if t.is_float() {
                    store_float(o, "xmm0", d.0, *t, f);
                } else {
                    store(o, "rax", d.0, f);
                }
            }
        }
        Inst::Mov(d, s) => {
            load(o, "rax", s.0, f);
            store(o, "rax", d.0, f);
        }
    }
}

fn emit_term(o: &mut String, term: &Term, f: &Frame, fn_: &str) {
    match term {
        Term::Ret(None) => {
            writeln!(o, "  mov rsp, rbp").unwrap();
            writeln!(o, "  pop rbp").unwrap();
            writeln!(o, "  ret").unwrap();
        }
        Term::Ret(Some((v, t))) => {
            if t.is_float() {
                load_float(o, "xmm0", v.0, *t, f);
            } else {
                load(o, "rax", v.0, f);
            }
            writeln!(o, "  mov rsp, rbp").unwrap();
            writeln!(o, "  pop rbp").unwrap();
            writeln!(o, "  ret").unwrap();
        }
        Term::Jump(bb) => {
            writeln!(o, "  jmp .L{}_bb{}", fn_, bb.0).unwrap();
        }
        Term::CondBr {
            cond,
            then_bb,
            else_bb,
        } => {
            load(o, "rax", cond.0, f);
            writeln!(o, "  test al, al").unwrap();
            writeln!(o, "  jnz .L{}_bb{}", fn_, then_bb.0).unwrap();
            writeln!(o, "  jmp .L{}_bb{}", fn_, else_bb.0).unwrap();
        }
    }
}

fn emit_ipow(o: &mut String) {
    writeln!(o, "__ipow:").unwrap();
    writeln!(o, "  mov rax, 1").unwrap();
    writeln!(o, "  test rsi, rsi").unwrap();
    writeln!(o, "  jz .ipow_done").unwrap();
    writeln!(o, ".ipow_loop:").unwrap();
    writeln!(o, "  test rsi, 1").unwrap();
    writeln!(o, "  jz .ipow_even").unwrap();
    writeln!(o, "  imul rax, rdi").unwrap();
    writeln!(o, ".ipow_even:").unwrap();
    writeln!(o, "  imul rdi, rdi").unwrap();
    writeln!(o, "  shr rsi, 1").unwrap();
    writeln!(o, "  jnz .ipow_loop").unwrap();
    writeln!(o, ".ipow_done:").unwrap();
    writeln!(o, "  ret").unwrap();
}
