// Runs a verified program.

use crate::op::{cost, kind, Op};

// The machine stops after this many steps.
pub const STEP_LIMIT: i64 = 100000;

// Why the machine stopped.
pub const RUNNING: i64 = 0;
pub const HALTED: i64 = 1;
pub const DIVIDE_BY_ZERO: i64 = 2;
pub const OUT_OF_STEPS: i64 = 3;

pub struct Machine {
    pub stack: Vec<i64>,
    pub pc: i64,
    pub steps: i64,
    pub cost: i64,
    // Steps run of each kind of instruction.
    pub counts: [i64; 4],
    pub status: i64,
}

impl Machine {
    pub fn new() -> Machine {
        Machine { stack: Vec::new(), pc: 0, steps: 0, cost: 0, counts: [0; 4], status: RUNNING }
    }

    fn pop(&mut self) -> i64 {
        self.stack.pop().unwrap()
    }

    fn top(&self, below: usize) -> i64 {
        self.stack[self.stack.len() - 1 - below]
    }
}

// Runs one instruction, or sets `m.status` to why it cannot. Printed
// values go to `out`.
pub fn step(ops: &[Op], m: &mut Machine, out: &mut String) {
    if m.pc >= ops.len() as i64 {
        m.status = HALTED;
        return;
    }
    if m.steps == STEP_LIMIT {
        m.status = OUT_OF_STEPS;
        return;
    }
    let op = ops[m.pc as usize];
    let mut next = m.pc + 1;
    match op {
        Op::Push(v) => m.stack.push(v),
        Op::Pop => {
            m.pop();
        }
        Op::Dup => m.stack.push(m.top(0)),
        Op::Swap => {
            let b = m.pop();
            let a = m.pop();
            m.stack.push(b);
            m.stack.push(a);
        }
        Op::Over => m.stack.push(m.top(1)),
        Op::Pick(n) => m.stack.push(m.top(n as usize)),
        Op::Add | Op::Sub | Op::Mul | Op::Div | Op::Mod | Op::Lt | Op::Eq => {
            let b = m.top(0);
            let a = m.top(1);
            if (op == Op::Div || op == Op::Mod) && b == 0 {
                m.status = DIVIDE_BY_ZERO;
                return;
            }
            m.pop();
            m.pop();
            m.stack.push(binary(op, a, b));
        }
        Op::Jmp(t) => next = t,
        Op::Jz(t) => {
            if m.pop() == 0 {
                next = t;
            }
        }
        Op::Print => {
            let v = m.pop();
            out.push_str(&v.to_string());
            out.push('\n');
        }
        Op::Halt => {
            m.status = HALTED;
        }
    }
    m.steps += 1;
    m.cost += cost(op);
    m.counts[kind(op)] += 1;
    if m.status == RUNNING {
        m.pc = next;
    }
}

// a op b for the binary operations; integers wrap.
fn binary(op: Op, a: i64, b: i64) -> i64 {
    match op {
        Op::Add => a.wrapping_add(b),
        Op::Sub => a.wrapping_sub(b),
        Op::Mul => a.wrapping_mul(b),
        Op::Div => a.wrapping_div(b),
        Op::Mod => a.wrapping_rem(b),
        Op::Lt => (a < b) as i64,
        Op::Eq => (a == b) as i64,
        _ => 0,
    }
}

// Runs from instruction 0 until the machine stops.
pub fn run(ops: &[Op], out: &mut String) -> Machine {
    let mut m = Machine::new();
    while m.status == RUNNING {
        step(ops, &mut m, out);
    }
    m
}
