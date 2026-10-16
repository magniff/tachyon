// Runs the tree. Variables live on one stack of (name, value) entries; a
// block's variables are dropped when it ends, and a name means its most
// recent entry. Arithmetic wraps around at 64 bits.

use crate::ast::{push_int, Ast, BinOp, Expr, Stmt, UnOp};

pub enum ErrorKind {
    UndefinedVariable,
    DivisionByZero,
}

pub struct RtError {
    pub kind: ErrorKind,
    pub line: i64,
    // The variable's name index, for UndefinedVariable.
    pub name: i64,
}

struct Machine<'a> {
    ast: &'a Ast,
    names: Vec<i64>,
    values: Vec<i64>,
    // The number of live entries in names/values (the rest are stale).
    top: i64,
    out: Vec<u8>,
}

fn truth(b: bool) -> i64 {
    if b {
        1
    } else {
        0
    }
}

// The value of `op` on two numbers; None for division or remainder by 0.
pub fn apply_binary(op: BinOp, a: i64, b: i64) -> Option<i64> {
    let v = match op {
        BinOp::Add => a.wrapping_add(b),
        BinOp::Sub => a.wrapping_sub(b),
        BinOp::Mul => a.wrapping_mul(b),
        BinOp::Div => {
            if b == 0 {
                return None;
            }
            a.wrapping_div(b)
        }
        BinOp::Rem => {
            if b == 0 {
                return None;
            }
            a.wrapping_rem(b)
        }
        BinOp::Lt => truth(a < b),
        BinOp::Le => truth(a <= b),
        BinOp::Gt => truth(a > b),
        BinOp::Ge => truth(a >= b),
        BinOp::Eq => truth(a == b),
        BinOp::Ne => truth(a != b),
        BinOp::And => truth(a != 0 && b != 0),
        BinOp::Or => truth(a != 0 || b != 0),
    };
    Some(v)
}

pub fn apply_unary(op: UnOp, a: i64) -> i64 {
    match op {
        UnOp::Neg => a.wrapping_neg(),
        UnOp::Not => truth(a == 0),
    }
}

impl<'a> Machine<'a> {
    // The index of the live entry of `name`, or -1.
    fn find(&self, name: i64) -> i64 {
        let mut i = self.top - 1;
        while i >= 0 {
            if self.names[i as usize] == name {
                return i;
            }
            i -= 1;
        }
        -1
    }

    fn declare(&mut self, name: i64, value: i64) {
        if self.top == self.names.len() as i64 {
            self.names.push(name);
            self.values.push(value);
        } else {
            self.names[self.top as usize] = name;
            self.values[self.top as usize] = value;
        }
        self.top += 1;
    }

    fn eval(&mut self, e: i64) -> Result<i64, RtError> {
        match self.ast.expr(e) {
            Expr::Num(v) => Ok(v),
            Expr::Var(name, line) => {
                let i = self.find(name);
                if i < 0 {
                    return Err(RtError {
                        kind: ErrorKind::UndefinedVariable,
                        line: line,
                        name: name,
                    });
                }
                Ok(self.values[i as usize])
            }
            Expr::Unary(op, a, _) => {
                let v = self.eval(a)?;
                Ok(apply_unary(op, v))
            }
            Expr::Binary(op, a, b, line) => {
                let left = self.eval(a)?;
                if op == BinOp::And && left == 0 {
                    return Ok(0);
                }
                if op == BinOp::Or && left != 0 {
                    return Ok(1);
                }
                let right = self.eval(b)?;
                match apply_binary(op, left, right) {
                    Some(v) => Ok(v),
                    None => Err(RtError {
                        kind: ErrorKind::DivisionByZero,
                        line: line,
                        name: 0,
                    }),
                }
            }
        }
    }

    // Runs a list of statements in a new scope.
    fn exec_block(&mut self, first: i64, count: i64) -> Result<(), RtError> {
        let mark = self.top;
        for k in 0..count {
            let r = self.exec(self.ast.list(first + k));
            if r.is_err() {
                self.top = mark;
                return r;
            }
        }
        self.top = mark;
        Ok(())
    }

    fn exec(&mut self, s: i64) -> Result<(), RtError> {
        match self.ast.stmt(s) {
            Stmt::Let(name, e) => {
                let v = self.eval(e)?;
                self.declare(name, v);
            }
            Stmt::Set(name, e, line) => {
                let v = self.eval(e)?;
                let i = self.find(name);
                if i < 0 {
                    return Err(RtError {
                        kind: ErrorKind::UndefinedVariable,
                        line: line,
                        name: name,
                    });
                }
                self.values[i as usize] = v;
            }
            Stmt::Print(first, count) => {
                let mut vals: Vec<i64> = Vec::new();
                for k in 0..count {
                    let v = self.eval(self.ast.list(first + k))?;
                    vals.push(v);
                }
                for k in 0..vals.len() {
                    if k > 0 {
                        self.out.push(b' ');
                    }
                    push_int(&mut self.out, vals[k]);
                }
                self.out.push(b'\n');
            }
            Stmt::If(cond, first, count, els) => {
                let c = self.eval(cond)?;
                if c != 0 {
                    self.exec_block(first, count)?;
                } else if els >= 0 {
                    self.exec(els)?;
                }
            }
            Stmt::While(cond, first, count) => loop {
                let c = self.eval(cond)?;
                if c == 0 {
                    break;
                }
                self.exec_block(first, count)?;
            },
            Stmt::Block(first, count) => self.exec_block(first, count)?,
        }
        Ok(())
    }
}

// Runs the program; appends what it printed to `out`, ending with the
// error line if it stopped on an error.
pub fn run(ast: &Ast, out: &mut Vec<u8>) {
    let mut m = Machine {
        ast: ast,
        names: Vec::new(),
        values: Vec::new(),
        top: 0,
        out: Vec::new(),
    };
    let r = m.exec_block(ast.top_first, ast.top_count);
    out.extend_from_slice(&m.out);
    if let Err(e) = r {
        out.extend_from_slice(b"error at line ");
        push_int(out, e.line);
        match e.kind {
            ErrorKind::UndefinedVariable => {
                out.extend_from_slice(b": undefined variable ");
                out.extend_from_slice(&ast.names[e.name as usize]);
            }
            ErrorKind::DivisionByZero => out.extend_from_slice(b": division by zero"),
        }
        out.push(b'\n');
    }
}
