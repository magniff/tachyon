// Checks a program before it runs: every jump lands on an instruction, and
// every instruction finds the values it pops, however it is reached.

use crate::op::Op;

// The deepest the stack may get.
pub const MAX_DEPTH: i64 = 64;

pub struct VerifyError {
    pub pc: i64,
    pub message: &'static str,
}

// The values the instruction needs on the stack, and the change it makes
// to the stack's depth.
pub fn stack_effect(op: Op) -> (i64, i64) {
    match op {
        Op::Push(_) => (0, 1),
        Op::Pop => (1, -1),
        Op::Dup => (1, 1),
        Op::Swap => (2, 0),
        Op::Over => (2, 1),
        Op::Add | Op::Sub | Op::Mul | Op::Div | Op::Mod | Op::Lt | Op::Eq => (2, -1),
        Op::Jmp(_) => (0, 0),
        Op::Jz(_) => (1, -1),
        Op::Print => (1, -1),
        Op::Halt => (0, 0),
    }
}

// Where the instruction may jump.
pub fn target(op: Op) -> Option<i64> {
    match op {
        Op::Jmp(t) | Op::Jz(t) => Some(t),
        Op::Push(_) | Op::Pop | Op::Dup | Op::Swap | Op::Over => None,
        Op::Add | Op::Sub | Op::Mul | Op::Div | Op::Mod | Op::Lt | Op::Eq => None,
        Op::Print | Op::Halt => None,
    }
}

// Whether the next instruction may run after this one.
pub fn falls_through(op: Op) -> bool {
    match op {
        Op::Jmp(_) | Op::Halt => false,
        Op::Push(_) | Op::Pop | Op::Dup | Op::Swap | Op::Over => true,
        Op::Add | Op::Sub | Op::Mul | Op::Div | Op::Mod | Op::Lt | Op::Eq => true,
        Op::Jz(_) | Op::Print => true,
    }
}

// Walks every path from instruction 0 (a stack of instructions to visit,
// the last one pushed first; after an instruction, the next one is pushed
// before its jump target) and gives the first problem found.
pub fn verify(ops: &[Op]) -> Result<(), VerifyError> {
    let n = ops.len() as i64;
    if n == 0 {
        return Ok(());
    }
    // The stack depth on entry to each instruction; -1 if not reached yet.
    let mut depth: Vec<i64> = vec![-1; ops.len()];
    let mut todo: Vec<i64> = vec![0];
    depth[0] = 0;
    while let Some(pc) = todo.pop() {
        let op = ops[pc as usize];
        if let Some(t) = target(op) {
            if t < 0 || t >= n {
                return Err(VerifyError { pc: pc, message: "bad jump target" });
            }
        }
        let (needs, delta) = stack_effect(op);
        let d = depth[pc as usize];
        if d < needs {
            return Err(VerifyError { pc: pc, message: "stack underflow" });
        }
        let after = d + delta;
        if after > MAX_DEPTH {
            return Err(VerifyError { pc: pc, message: "stack overflow" });
        }
        let mut next: Vec<i64> = Vec::new();
        if falls_through(op) && pc + 1 < n {
            next.push(pc + 1);
        }
        if let Some(t) = target(op) {
            next.push(t);
        }
        for s in next {
            let known = depth[s as usize];
            if known == -1 {
                depth[s as usize] = after;
                todo.push(s);
            } else if known != after {
                return Err(VerifyError { pc: s, message: "inconsistent stack depth" });
            }
        }
    }
    Ok(())
}
