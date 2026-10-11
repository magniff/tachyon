// x86-64 NASM Code Generator
// "Spill everything" allocator: every vreg lives at [rbp-N].
// System V AMD64 ABI.
// Function symbols are written as `$name` so that names which are NASM
// keywords or register names (abs, byte, rax, ...) still assemble.

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

// Quotient ends up in rax, remainder in rdx. 8- and 16-bit operands are
// widened to 32 bits: `div r8` leaves the remainder in ah, not dl.
fn idiv(o: &mut String, sz: u64, signed: bool) {
    if signed {
        match sz {
            1 | 2 => {
                writeln!(o, "  movsx eax, {}", rax(sz)).unwrap();
                writeln!(o, "  movsx ecx, {}", rcx(sz)).unwrap();
                writeln!(o, "  cdq").unwrap();
                writeln!(o, "  idiv ecx").unwrap();
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
        if sz < 4 {
            writeln!(o, "  movzx eax, {}", rax(sz)).unwrap();
            writeln!(o, "  movzx ecx, {}", rcx(sz)).unwrap();
        }
        writeln!(o, "  xor edx, edx").unwrap();
        match sz {
            1 | 2 | 4 => writeln!(o, "  div ecx").unwrap(),
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

// Sets up arguments for a call and returns how many bytes of stack
// arguments (including alignment padding) the caller must pop afterwards.
// rsp is 16-byte aligned on entry (the frame size is a multiple of 16), so
// an odd number of stack arguments needs 8 bytes of padding.
fn call_args(o: &mut String, args: &[(VReg, IRType)], f: &Frame) -> u64 {
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
    let pad = if stk.len() % 2 == 1 { 8 } else { 0 };
    if pad > 0 {
        writeln!(o, "  sub rsp, {}", pad).unwrap();
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
    stk.len() as u64 * 8 + pad
}

fn pop_call_args(o: &mut String, bytes: u64) {
    if bytes > 0 {
        writeln!(o, "  add rsp, {}", bytes).unwrap();
    }
}

// Object format and platform the assembly is written for. Both are x86-64
// System V; they differ only in the object-file header and symbol naming.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Target {
    // nasm -f elf64, linked with `gcc -no-pie`.
    LinuxX86_64,
    // nasm -f macho64, linked with `clang -arch x86_64`. C symbols carry a
    // leading underscore, which nasm adds to every global and extern.
    MacosX86_64,
}

impl Target {
    pub fn host() -> Target {
        if cfg!(target_os = "macos") {
            Target::MacosX86_64
        } else {
            Target::LinuxX86_64
        }
    }

    pub fn nasm_format(self) -> &'static str {
        match self {
            Target::LinuxX86_64 => "elf64",
            Target::MacosX86_64 => "macho64",
        }
    }
}

// Public entry
pub fn generate(prog: &IrProgram) -> Result<String, GeneratorError> {
    generate_for(prog, Target::LinuxX86_64)
}

pub fn generate_for(prog: &IrProgram, target: Target) -> Result<String, GeneratorError> {
    let mut o = String::new();
    if target == Target::MacosX86_64 {
        writeln!(o, "%pragma macho gprefix _")?;
    }
    writeln!(o, "bits 64")?;
    writeln!(o, "default rel")?;
    if target == Target::LinuxX86_64 {
        writeln!(o, "section .note.GNU-stack noalloc noexec nowrite progbits")?;
    }
    writeln!(o)?;

    for func in &prog.functions {
        if func.is_extern {
            writeln!(o, "extern ${}", func.name)?;
        }
    }
    // Calls the lowering introduces on its own (fmod, pow, ...) need an
    // extern declaration even when the program never declared them.
    let mut implicit_externs: Vec<&str> = Vec::new();
    for func in &prog.functions {
        for bb in &func.blocks {
            for inst in &bb.instructions {
                if let Inst::Call { func: callee, .. } = inst {
                    let known =
                        callee == "__ipow" || prog.functions.iter().any(|f| &f.name == callee);
                    if !known && !implicit_externs.contains(&callee.as_str()) {
                        implicit_externs.push(callee);
                    }
                }
            }
        }
    }
    for name in implicit_externs {
        writeln!(o, "extern ${}", name)?;
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
            writeln!(o, "  {}: dq 0x{:016x} ; {:?}", label, val.to_bits(), val)?;
        } else {
            let val = *val as f32;
            writeln!(o, "  {}: dd 0x{:08x} ; {:?}", label, val.to_bits(), val)?;
        }
    }
    writeln!(o)?;

    // .text
    writeln!(o, "section .text")?;
    for func in &prog.functions {
        if !func.is_extern {
            writeln!(o, "global ${}", func.name)?;
        }
    }
    writeln!(o)?;

    let mut fi_global = 0usize;
    let mut label_counter = 0usize;

    for func in &prog.functions {
        if func.is_extern {
            continue;
        }
        let f = frame(func);

        writeln!(o, "${}:", func.name)?;
        writeln!(o, "  push rbp")?;
        writeln!(o, "  mov rbp, rsp")?;
        if f.size > 0 {
            writeln!(o, "  sub rsp, {}", f.size)?;
        }

        // Store incoming params. Past the 6 integer / 8 float registers,
        // arguments live in the caller's frame starting at [rbp+16].
        let mut ii = 0usize;
        let mut ffi = 0usize;
        let mut stack_off = 16i64;
        for (v, ty) in &func.params {
            if ty.is_float() {
                if ffi < 8 {
                    store_float(&mut o, &format!("xmm{}", ffi), v.0, *ty, &f);
                    ffi += 1;
                } else {
                    let m = if *ty == IRType::F64 { "movsd" } else { "movss" };
                    writeln!(o, "  {} xmm15, [rbp{:+}]", m, stack_off)?;
                    store_float(&mut o, "xmm15", v.0, *ty, &f);
                    stack_off += 8;
                }
            } else if ii < INT_ARGS.len() {
                writeln!(o, "  mov [rbp{:+}], {}", f.voff[&v.0], INT_ARGS[ii])?;
                ii += 1;
            } else {
                writeln!(o, "  mov rax, [rbp{:+}]", stack_off)?;
                store(&mut o, "rax", v.0, &f);
                stack_off += 8;
            }
        }

        // Emit blocks
        for bb in &func.blocks {
            writeln!(o, ".L{}_bb{}:", func.name, bb.id.0)?;
            for inst in &bb.instructions {
                emit_inst(
                    &mut o,
                    inst,
                    prog,
                    &f,
                    &fcs,
                    &mut fi_global,
                    &mut label_counter,
                );
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
    prog: &IrProgram,
    f: &Frame,
    fcs: &[(String, f64, IRType)],
    fi: &mut usize,
    labels: &mut usize,
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
            if s == 8 {
                writeln!(o, "  imul rax, rcx").unwrap();
            } else {
                writeln!(o, "  imul eax, ecx").unwrap();
            }
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
            let cmp = if *t == IRType::F64 {
                "comisd"
            } else {
                "comiss"
            };
            // An unordered compare (either side NaN) sets ZF, PF and CF.
            // `<` and `<=` swap operands so they test CF=0, which is false
            // for NaN; `==` and `!=` consult PF explicitly.
            match op {
                CmpOp::Eq => {
                    writeln!(o, "  {} xmm0, xmm1", cmp).unwrap();
                    writeln!(o, "  sete al").unwrap();
                    writeln!(o, "  setnp cl").unwrap();
                    writeln!(o, "  and al, cl").unwrap();
                }
                CmpOp::Neq => {
                    writeln!(o, "  {} xmm0, xmm1", cmp).unwrap();
                    writeln!(o, "  setne al").unwrap();
                    writeln!(o, "  setp cl").unwrap();
                    writeln!(o, "  or al, cl").unwrap();
                }
                CmpOp::Gt => {
                    writeln!(o, "  {} xmm0, xmm1", cmp).unwrap();
                    writeln!(o, "  seta al").unwrap();
                }
                CmpOp::GtEq => {
                    writeln!(o, "  {} xmm0, xmm1", cmp).unwrap();
                    writeln!(o, "  setae al").unwrap();
                }
                CmpOp::Lt => {
                    writeln!(o, "  {} xmm1, xmm0", cmp).unwrap();
                    writeln!(o, "  seta al").unwrap();
                }
                CmpOp::LtEq => {
                    writeln!(o, "  {} xmm1, xmm0", cmp).unwrap();
                    writeln!(o, "  setae al").unwrap();
                }
            }
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
            writeln!(o, "  lea rax, [{}]", prog.strings[*idx].label).unwrap();
            store(o, "rax", d.0, f);
        }
        Inst::IntToFloat(d, s, from, to, signed) => {
            let fs = from.size();
            let (cvt, add) = if *to == IRType::F64 {
                ("cvtsi2sd", "addsd")
            } else {
                ("cvtsi2ss", "addss")
            };
            load(o, "rax", s.0, f);
            if *signed {
                if fs < 4 {
                    writeln!(o, "  movsx eax, {}", rax(fs)).unwrap();
                }
                if fs <= 4 {
                    writeln!(o, "  {} xmm0, eax", cvt).unwrap();
                } else {
                    writeln!(o, "  {} xmm0, rax", cvt).unwrap();
                }
            } else if fs < 8 {
                // Zero-extend into rax; a signed 64-bit convert is then exact.
                match fs {
                    1 | 2 => writeln!(o, "  movzx eax, {}", rax(fs)).unwrap(),
                    _ => writeln!(o, "  mov eax, eax").unwrap(),
                }
                writeln!(o, "  {} xmm0, rax", cvt).unwrap();
            } else {
                // u64 with the top bit set: halve (keeping the low bit for
                // correct rounding), convert, then double.
                let n = *labels;
                *labels += 1;
                writeln!(o, "  test rax, rax").unwrap();
                writeln!(o, "  js .Lu2f_big{}", n).unwrap();
                writeln!(o, "  {} xmm0, rax", cvt).unwrap();
                writeln!(o, "  jmp .Lu2f_done{}", n).unwrap();
                writeln!(o, ".Lu2f_big{}:", n).unwrap();
                writeln!(o, "  mov rcx, rax").unwrap();
                writeln!(o, "  shr rcx, 1").unwrap();
                writeln!(o, "  and eax, 1").unwrap();
                writeln!(o, "  or rcx, rax").unwrap();
                writeln!(o, "  {} xmm0, rcx", cvt).unwrap();
                writeln!(o, "  {} xmm0, xmm0", add).unwrap();
                writeln!(o, ".Lu2f_done{}:", n).unwrap();
            }
            store_float(o, "xmm0", d.0, *to, f);
        }
        Inst::FloatToInt(d, s, from, to, signed) => {
            load_float(o, "xmm0", s.0, *from, f);
            let (cvt, cmp, sub) = if *from == IRType::F64 {
                ("cvttsd2si", "comisd", "subsd")
            } else {
                ("cvttss2si", "comiss", "subss")
            };
            if *signed && to.size() <= 4 {
                writeln!(o, "  {} eax, xmm0", cvt).unwrap();
            } else if *signed || to.size() <= 4 {
                // Unsigned targets up to 32 bits fit a signed 64-bit convert.
                writeln!(o, "  {} rax, xmm0", cvt).unwrap();
            } else {
                // u64: values >= 2^63 are converted after subtracting 2^63.
                let n = *labels;
                *labels += 1;
                if *from == IRType::F64 {
                    writeln!(o, "  mov rax, 0x43e0000000000000").unwrap();
                    writeln!(o, "  movq xmm1, rax").unwrap();
                } else {
                    writeln!(o, "  mov eax, 0x5f000000").unwrap();
                    writeln!(o, "  movd xmm1, eax").unwrap();
                }
                writeln!(o, "  {} xmm0, xmm1", cmp).unwrap();
                writeln!(o, "  jae .Lf2u_big{}", n).unwrap();
                writeln!(o, "  {} rax, xmm0", cvt).unwrap();
                writeln!(o, "  jmp .Lf2u_done{}", n).unwrap();
                writeln!(o, ".Lf2u_big{}:", n).unwrap();
                writeln!(o, "  {} xmm0, xmm1", sub).unwrap();
                writeln!(o, "  {} rax, xmm0", cvt).unwrap();
                writeln!(o, "  btc rax, 63").unwrap();
                writeln!(o, ".Lf2u_done{}:", n).unwrap();
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
                    // Writing a 32-bit register zeroes bits 32..63, so a
                    // 64-bit target needs the 64-bit form of movsx.
                    (1, 4) => {
                        writeln!(o, "  movsx eax, al").unwrap();
                    }
                    (1, 8) => {
                        writeln!(o, "  movsx rax, al").unwrap();
                    }
                    (2, 4) => {
                        writeln!(o, "  movsx eax, ax").unwrap();
                    }
                    (2, 8) => {
                        writeln!(o, "  movsx rax, ax").unwrap();
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
            let pushed = call_args(o, args, f);
            writeln!(o, "  call ${}", func).unwrap();
            pop_call_args(o, pushed);
            if let Some((d, t)) = dst {
                if t.is_float() {
                    store_float(o, "xmm0", d.0, *t, f);
                } else {
                    store(o, "rax", d.0, f);
                }
            }
        }
        Inst::CallIndirect { dst, callee, args } => {
            let pushed = call_args(o, args, f);
            load(o, "r10", callee.0, f);
            writeln!(o, "  call r10").unwrap();
            pop_call_args(o, pushed);
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
        Inst::FuncAddr(d, name) => {
            // Functions from shared libraries are addressed through the GOT
            // (required for Mach-O, and valid for ELF).
            let is_extern = prog.functions.iter().any(|g| &g.name == name && g.is_extern);
            if is_extern {
                writeln!(o, "  mov rax, [rel ${} wrt ..gotpcrel]", name).unwrap();
            } else {
                writeln!(o, "  lea rax, [rel ${}]", name).unwrap();
            }
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
