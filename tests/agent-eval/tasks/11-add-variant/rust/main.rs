// A stack machine: reads a program from stdin, checks it, lists it if
// asked, runs it, and reports how it stopped.

mod op;
mod parse;
mod verify;
mod vm;

use op::{kind_name, mnemonic, Op};
use std::io::Read;
use vm::{DIVIDE_BY_ZERO, HALTED, OUT_OF_STEPS};

// The instruction as a listing shows it: its name and operand.
fn write_op(out: &mut String, op: Op) {
    out.push_str(mnemonic(op));
    match op {
        Op::Push(n) | Op::Jmp(n) | Op::Jz(n) => {
            out.push(' ');
            out.push_str(&n.to_string());
        }
        Op::Pop | Op::Dup | Op::Swap | Op::Over => {}
        Op::Add | Op::Sub | Op::Mul | Op::Div | Op::Mod | Op::Lt | Op::Eq => {}
        Op::Print | Op::Halt => {}
    }
}

fn main() {
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input).unwrap();
    let mut out = String::new();
    run_program(&input, &mut out);
    print!("{}", out);
}

fn run_program(input: &str, out: &mut String) {
    let prog = match parse::parse(input) {
        Ok(p) => p,
        Err(e) => {
            out.push_str("parse error on line ");
            out.push_str(&e.line.to_string());
            out.push_str(": ");
            out.push_str(&e.message);
            out.push('\n');
            return;
        }
    };
    if let Err(e) = verify::verify(&prog.ops) {
        out.push_str("verify error at ");
        out.push_str(&e.pc.to_string());
        out.push_str(": ");
        out.push_str(e.message);
        out.push('\n');
        return;
    }
    if prog.list {
        for (pc, &op) in prog.ops.iter().enumerate() {
            out.push_str(&pc.to_string());
            out.push_str(": ");
            write_op(out, op);
            out.push('\n');
        }
    }
    let m = vm::run(&prog.ops, out);
    if m.status == HALTED {
        out.push_str("halted");
    } else if m.status == DIVIDE_BY_ZERO {
        out.push_str("division by zero");
    } else if m.status == OUT_OF_STEPS {
        out.push_str("out of steps");
    }
    out.push_str(" at ");
    out.push_str(&m.pc.to_string());
    out.push_str(" after ");
    out.push_str(&m.steps.to_string());
    out.push_str(" steps, cost ");
    out.push_str(&m.cost.to_string());
    out.push('\n');
    out.push_str("stack:");
    if m.stack.is_empty() {
        out.push_str(" empty");
    }
    for v in &m.stack {
        out.push(' ');
        out.push_str(&v.to_string());
    }
    out.push('\n');
    for k in 0..4 {
        out.push_str(if k == 0 { "steps: " } else { ", " });
        out.push_str(kind_name(k));
        out.push(' ');
        out.push_str(&m.counts[k].to_string());
    }
    out.push('\n');
}
