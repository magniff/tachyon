// A textual form of the IR, for tests and debugging.

use super::{IRFunction, Inst, IrProgram, Term};

pub fn print_ir(program: &IrProgram) -> String {
    let mut out = String::new();
    for (index, global) in program.globals.iter().enumerate() {
        out += &format!(
            "global{} {}{}: {:?}\n",
            index,
            if global.mutable { "mut " } else { "" },
            global.name,
            global.bytes
        );
    }
    for string in &program.strings {
        out += &format!(
            "{}: {:?}\n",
            string.label,
            std::str::from_utf8(&string.bytes).unwrap_or("?")
        );
    }
    for function in &program.functions {
        if function.is_extern {
            print_extern(&mut out, function);
        } else {
            print_function(&mut out, function);
        }
    }
    out
}

fn print_extern(out: &mut String, function: &IRFunction) {
    let params: Vec<String> = function
        .params
        .iter()
        .map(|(_, ty)| ty.to_string())
        .collect();
    *out += &format!("extern fn {}({})", function.name, params.join(", "));
    if let Some(ty) = function.return_type {
        *out += &format!(" -> {}", ty);
    }
    *out += "\n";
}

fn print_function(out: &mut String, function: &IRFunction) {
    let params: Vec<String> = function
        .params
        .iter()
        .map(|(vreg, ty)| format!("{}: {}", vreg, ty))
        .collect();
    *out += &format!("fn {}({})", function.name, params.join(", "));
    if let Some(ty) = function.return_type {
        *out += &format!(" -> {}", ty);
    }
    *out += " {\n";
    for (index, slot) in function.slots.iter().enumerate() {
        *out += &format!(
            "  slot{}: size={}, align={}\n",
            index, slot.size, slot.align
        );
    }
    for block in &function.blocks {
        *out += &format!("  {}:\n", block.id);
        for inst in &block.instructions {
            *out += &format!("    {}\n", format_inst(inst));
        }
        *out += &format!("    {}\n", format_term(&block.terminator));
    }
    *out += "}\n";
}

// The suffix of a signed ("s") or unsigned ("u") operation.
fn sign(signed: bool) -> &'static str {
    if signed { "s" } else { "u" }
}

fn format_args(args: &[(super::VReg, super::IRType)]) -> String {
    let args: Vec<String> = args
        .iter()
        .map(|(vreg, ty)| format!("{}:{}", vreg, ty))
        .collect();
    args.join(", ")
}

fn format_inst(inst: &Inst) -> String {
    match inst {
        Inst::IAdd(d, a, b, t) => format!("{} = iadd.{} {}, {}", d, t, a, b),
        Inst::ISub(d, a, b, t) => format!("{} = isub.{} {}, {}", d, t, a, b),
        Inst::IMul(d, a, b, t) => format!("{} = imul.{} {}, {}", d, t, a, b),
        Inst::IDiv(d, a, b, t, s) => format!("{} = idiv.{}{} {}, {}", d, t, sign(*s), a, b),
        Inst::IMod(d, a, b, t, s) => format!("{} = imod.{}{} {}, {}", d, t, sign(*s), a, b),
        Inst::IShl(d, a, b, t) => format!("{} = ishl.{} {}, {}", d, t, a, b),
        Inst::IShr(d, a, b, t, arithmetic) => format!(
            "{} = ishr.{}{} {}, {}",
            d,
            t,
            if *arithmetic { "a" } else { "l" },
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
        Inst::ICmp(d, op, a, b, t, s) => {
            format!("{} = icmp.{}{} {} {}, {}", d, t, sign(*s), op, a, b)
        }
        Inst::FCmp(d, op, a, b, t) => format!("{} = fcmp.{} {} {}, {}", d, t, op, a, b),
        Inst::BoolNot(d, a) => format!("{} = bnot {}", d, a),
        Inst::ConstInt(d, v, t) => format!("{} = const.{} {}", d, t, v),
        Inst::ConstFloat(d, v, t) => format!("{} = constf.{} {}", d, t, v),
        Inst::ConstStringPtr(d, index) => format!("{} = strptr __str{}", d, index),
        Inst::IntToFloat(d, src, from, to, s) => {
            format!("{} = itof.{}->{} {} ({})", d, from, to, src, sign(*s))
        }
        Inst::FloatToInt(d, src, from, to, s) => {
            format!("{} = ftoi.{}->{} {} ({})", d, from, to, src, sign(*s))
        }
        Inst::FloatToFloat(d, src, from, to) => format!("{} = ftof.{}->{} {}", d, from, to, src),
        Inst::IntExt(d, src, from, to, s) => {
            format!("{} = ext.{}->{} {} ({})", d, from, to, src, sign(*s))
        }
        Inst::IntTrunc(d, src, from, to) => format!("{} = trunc.{}->{} {}", d, from, to, src),
        Inst::Load(d, addr, t) => format!("{} = load.{} [{}]", d, t, addr),
        Inst::Store(addr, value, t) => format!("store.{} [{}], {}", t, addr, value),
        Inst::MemCopy { dst, src, size } => format!("memcpy [{}], [{}], {}", dst, src, size),
        Inst::SlotAddr(d, slot) => format!("{} = slotaddr {}", d, slot),
        Inst::GlobalAddr(d, index) => format!("{} = globaladdr @global{}", d, index),
        Inst::MemberPtr(d, base, offset) => format!("{} = memberptr {}, +{}", d, base, offset),
        Inst::IndexPtr(d, base, index, size) => {
            format!("{} = indexptr {}, {}, elem={}", d, base, index, size)
        }
        Inst::Call { dst, func, args } => match dst {
            Some((d, t)) => format!("{} = call.{} {}({})", d, t, func, format_args(args)),
            None => format!("call {}({})", func, format_args(args)),
        },
        Inst::CallIndirect { dst, callee, args } => match dst {
            Some((d, t)) => format!("{} = calli.{} {}({})", d, t, callee, format_args(args)),
            None => format!("calli {}({})", callee, format_args(args)),
        },
        Inst::Mov(d, src) => format!("{} = mov {}", d, src),
        Inst::FuncAddr(d, name) => format!("{} = funcaddr @{}", d, name),
    }
}

fn format_term(term: &Term) -> String {
    match term {
        Term::Ret(None) => "ret".into(),
        Term::Ret(Some((value, ty))) => format!("ret.{} {}", ty, value),
        Term::Jump(target) => format!("jmp {}", target),
        Term::CondBr {
            cond,
            then_bb,
            else_bb,
        } => format!("br {}, {}, {}", cond, then_bb, else_bb),
    }
}
