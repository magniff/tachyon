// Evaluates a parsed tree.

use std::collections::HashMap;

use crate::parser::{Node, Op, Tree};

pub enum EvalError {
    DivisionByZero,
    UnknownVariable(String),
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
        Op::Rem => {
            if b == 0 {
                return Err(EvalError::DivisionByZero);
            }
            Ok(a % b)
        }
        Op::Lt => Ok((a < b) as i64),
        Op::Le => Ok((a <= b) as i64),
        Op::Gt => Ok((a > b) as i64),
        Op::Ge => Ok((a >= b) as i64),
        Op::Eq => Ok((a == b) as i64),
        Op::Ne => Ok((a != b) as i64),
    }
}

// The value of node `index`: the left operand is evaluated before the
// right one, and the first error stops the evaluation.
pub fn evaluate(tree: &Tree, index: usize, vars: &HashMap<String, i64>) -> Result<i64, EvalError> {
    match &tree.nodes[index] {
        Node::Num(v) => Ok(*v),
        Node::Var(name) => match vars.get(name) {
            Some(v) => Ok(*v),
            None => Err(EvalError::UnknownVariable(name.clone())),
        },
        Node::Neg(inner) => Ok(-evaluate(tree, *inner, vars)?),
        Node::Binary(op, left, right) => {
            let a = evaluate(tree, *left, vars)?;
            let b = evaluate(tree, *right, vars)?;
            apply(*op, a, b)
        }
    }
}
