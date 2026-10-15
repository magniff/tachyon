// The syntax tree, and its dump. Nodes live in vectors and refer to each
// other by index; a list of children (a block's statements, a print's
// expressions) is a run of `count` indices in `lists` from `first`.

#[derive(Clone, Copy, PartialEq)]
pub enum UnOp {
    Neg,
    Not,
}

#[derive(Clone, Copy, PartialEq)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Lt,
    Le,
    Gt,
    Ge,
    Eq,
    Ne,
    And,
    Or,
}

#[derive(Clone, Copy)]
pub enum Expr {
    Num(i64),
    // The name's index, the line of the name.
    Var(i64, i64),
    // The operator, the operand, the line of the operator.
    Unary(UnOp, i64, i64),
    // The operator, the left and right operands, the line of the operator.
    Binary(BinOp, i64, i64, i64),
}

#[derive(Clone, Copy)]
pub enum Stmt {
    // `let name = expr;`: the name, the expression.
    Let(i64, i64),
    // `name = expr;`: the name, the expression, the line of the name.
    Set(i64, i64, i64),
    // `print e, e;`: the list of expressions (first, count).
    Print(i64, i64),
    // The condition, the then-block's list (first, count), and the else
    // part: -1 for none, or a statement (a Block or an If).
    If(i64, i64, i64, i64),
    // The condition, the body's list (first, count).
    While(i64, i64, i64),
    // `{ ... }`: the list of statements (first, count).
    Block(i64, i64),
}

pub struct Ast {
    pub exprs: Vec<Expr>,
    pub stmts: Vec<Stmt>,
    pub lists: Vec<i64>,
    pub names: Vec<Vec<u8>>,
    // The program's statements: a list (first, count).
    pub top_first: i64,
    pub top_count: i64,
}

impl Ast {
    pub fn expr(&self, i: i64) -> Expr {
        self.exprs[i as usize]
    }

    pub fn stmt(&self, i: i64) -> Stmt {
        self.stmts[i as usize]
    }

    pub fn list(&self, i: i64) -> i64 {
        self.lists[i as usize]
    }

    pub fn add_expr(&mut self, e: Expr) -> i64 {
        self.exprs.push(e);
        self.exprs.len() as i64 - 1
    }

    pub fn add_stmt(&mut self, s: Stmt) -> i64 {
        self.stmts.push(s);
        self.stmts.len() as i64 - 1
    }

    // Copies `items` to the end of `lists`; returns where they start.
    pub fn add_list(&mut self, items: &[i64]) -> i64 {
        let first = self.lists.len() as i64;
        for x in items {
            self.lists.push(*x);
        }
        first
    }
}

pub fn unop_text(op: UnOp) -> &'static [u8] {
    match op {
        UnOp::Neg => b"neg",
        UnOp::Not => b"not",
    }
}

pub fn binop_text(op: BinOp) -> &'static [u8] {
    match op {
        BinOp::Add => b"+",
        BinOp::Sub => b"-",
        BinOp::Mul => b"*",
        BinOp::Div => b"/",
        BinOp::Rem => b"%",
        BinOp::Lt => b"<",
        BinOp::Le => b"<=",
        BinOp::Gt => b">",
        BinOp::Ge => b">=",
        BinOp::Eq => b"==",
        BinOp::Ne => b"!=",
        BinOp::And => b"&&",
        BinOp::Or => b"||",
    }
}

pub fn push_int(out: &mut Vec<u8>, v: i64) {
    out.extend_from_slice(v.to_string().as_bytes());
}

fn indent(out: &mut Vec<u8>, depth: i64) {
    for _ in 0..depth {
        out.extend_from_slice(b"  ");
    }
}

// An expression on one line: a number, a name, `(op a)` or `(op a b)`.
pub fn dump_expr(ast: &Ast, e: i64, out: &mut Vec<u8>) {
    match ast.expr(e) {
        Expr::Num(v) => push_int(out, v),
        Expr::Var(name, _) => out.extend_from_slice(&ast.names[name as usize]),
        Expr::Unary(op, a, _) => {
            out.push(b'(');
            out.extend_from_slice(unop_text(op));
            out.push(b' ');
            dump_expr(ast, a, out);
            out.push(b')');
        }
        Expr::Binary(op, a, b, _) => {
            out.push(b'(');
            out.extend_from_slice(binop_text(op));
            out.push(b' ');
            dump_expr(ast, a, out);
            out.push(b' ');
            dump_expr(ast, b, out);
            out.push(b')');
        }
    }
}

// The statements of a list, each at `depth`.
pub fn dump_list(ast: &Ast, first: i64, count: i64, depth: i64, out: &mut Vec<u8>) {
    for k in 0..count {
        dump_stmt(ast, ast.list(first + k), depth, out);
    }
}

// A statement on its own line, indented two spaces per level; the
// statements inside it one level deeper.
pub fn dump_stmt(ast: &Ast, s: i64, depth: i64, out: &mut Vec<u8>) {
    indent(out, depth);
    match ast.stmt(s) {
        Stmt::Let(name, e) => {
            out.extend_from_slice(b"let ");
            out.extend_from_slice(&ast.names[name as usize]);
            out.push(b' ');
            dump_expr(ast, e, out);
            out.push(b'\n');
        }
        Stmt::Set(name, e, _) => {
            out.extend_from_slice(b"set ");
            out.extend_from_slice(&ast.names[name as usize]);
            out.push(b' ');
            dump_expr(ast, e, out);
            out.push(b'\n');
        }
        Stmt::Print(first, count) => {
            out.extend_from_slice(b"print");
            for k in 0..count {
                out.push(b' ');
                dump_expr(ast, ast.list(first + k), out);
            }
            out.push(b'\n');
        }
        Stmt::If(cond, first, count, els) => {
            out.extend_from_slice(b"if ");
            dump_expr(ast, cond, out);
            out.push(b'\n');
            dump_list(ast, first, count, depth + 1, out);
            if els >= 0 {
                indent(out, depth);
                out.extend_from_slice(b"else\n");
                match ast.stmt(els) {
                    Stmt::Block(f, c) => dump_list(ast, f, c, depth + 1, out),
                    _ => dump_stmt(ast, els, depth + 1, out),
                }
            }
        }
        Stmt::While(cond, first, count) => {
            out.extend_from_slice(b"while ");
            dump_expr(ast, cond, out);
            out.push(b'\n');
            dump_list(ast, first, count, depth + 1, out);
        }
        Stmt::Block(first, count) => {
            out.extend_from_slice(b"block\n");
            dump_list(ast, first, count, depth + 1, out);
        }
    }
}

// The whole program: `program`, then its statements one level deeper.
pub fn dump(ast: &Ast, out: &mut Vec<u8>) {
    out.extend_from_slice(b"program\n");
    dump_list(ast, ast.top_first, ast.top_count, 1, out);
}
