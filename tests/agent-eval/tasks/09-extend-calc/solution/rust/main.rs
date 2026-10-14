// A line calculator: each line of stdin is an expression over 64-bit
// integers; its value (or an error) is printed on a line of its own.

mod eval;
mod lexer;
mod parser;

use std::collections::HashMap;
use std::io::Read;

use eval::{evaluate, EvalError};
use lexer::tokenize;
use parser::parse;

// Evaluates one line and appends the result line to `out`. A line with
// no tokens (blank, or only a comment) prints nothing.
fn run_line(line: &[u8], vars: &mut HashMap<String, i64>, out: &mut String) {
    let tokens = match tokenize(line) {
        Some(t) => t,
        None => {
            out.push_str("error: syntax\n");
            return;
        }
    };
    if tokens.len() == 1 {
        return; // only the end marker
    }
    let tree = match parse(tokens) {
        Some(t) => t,
        None => {
            out.push_str("error: syntax\n");
            return;
        }
    };
    match evaluate(&tree, tree.root, vars) {
        Ok(v) => {
            if let Some(name) = &tree.let_name {
                out.push_str(name);
                out.push_str(" = ");
                vars.insert(name.clone(), v);
            }
            out.push_str(&v.to_string());
            out.push('\n');
        }
        Err(EvalError::DivisionByZero) => out.push_str("error: division by zero\n"),
        Err(EvalError::UnknownVariable(name)) => {
            out.push_str("error: unknown variable ");
            out.push_str(&name);
            out.push('\n');
        }
    }
}

fn main() {
    let mut input = Vec::new();
    std::io::stdin().read_to_end(&mut input).unwrap();
    let mut vars = HashMap::new();
    let mut out = String::new();
    let mut start = 0;
    for i in 0..input.len() + 1 {
        if i == input.len() || input[i] == b'\n' {
            run_line(&input[start..i], &mut vars, &mut out);
            start = i + 1;
        }
    }
    print!("{}", out);
}
