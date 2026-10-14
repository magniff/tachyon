// Evaluates a parsed tree.

use crate::parser::{Node, Op, Tree};

pub enum EvalError {
    DivisionByZero,
}

fn apply(op: Op, a: i64, b: i64) -> Result<i64, EvalError> {
    match op {
        Op::Add => Ok(a + b),
        Op::Sub => Ok(a - b),
        Op::Mul => Ok(a * b),
        Op::Div => {
            if b == 0 {
                return Err(EvalError::DivisionByZero);
            }
            Ok(a / b)
        }
    }
}

// The value of node `index`: the left operand is evaluated before the
// right one, and the first error stops the evaluation.
pub fn evaluate(tree: &Tree, index: usize) -> Result<i64, EvalError> {
    match tree.nodes[index] {
        Node::Num(v) => Ok(v),
        Node::Binary(op, left, right) => {
            let a = evaluate(tree, left)?;
            let b = evaluate(tree, right)?;
            apply(op, a, b)
        }
    }
}
