// Parses tokens into the tree, by recursive descent:
//
//   program := stmt* END
//   stmt    := 'let' NAME '=' expr ';'
//            | NAME '=' expr ';'
//            | 'print' expr (',' expr)* ';'
//            | 'if' expr block ('else' (if-stmt | block))?
//            | 'while' expr block
//            | block
//   block   := '{' stmt* '}'
//   expr    := and ('||' and)*
//   and     := eq ('&&' eq)*
//   eq      := rel (('==' | '!=') rel)*
//   rel     := add (('<' | '<=' | '>' | '>=') add)*
//   add     := mul (('+' | '-') mul)*
//   mul     := unary (('*' | '/' | '%') unary)*
//   unary   := ('-' | '!') unary | primary
//   primary := NUMBER | NAME | '(' expr ')'
//
// A syntax error is the line of the token where parsing failed.

use crate::ast::{Ast, BinOp, Expr, Stmt, UnOp};
use crate::lexer::{Lexed, Token, TokenKind};

struct Parser {
    tokens: Vec<Token>,
    pos: i64,
    ast: Ast,
}

impl Parser {
    fn peek(&self) -> TokenKind {
        self.tokens[self.pos as usize].kind
    }

    fn advance(&mut self) -> Token {
        let t = self.tokens[self.pos as usize];
        if t.kind != TokenKind::End {
            self.pos += 1;
        }
        t
    }

    // The next token, which must be of `kind`; else the error's line.
    fn expect(&mut self, kind: TokenKind) -> Result<Token, i64> {
        let t = self.advance();
        if t.kind != kind {
            return Err(t.line);
        }
        Ok(t)
    }

    fn binary(&mut self, op: BinOp, left: i64, right: i64, line: i64) -> i64 {
        self.ast.add_expr(Expr::Binary(op, left, right, line))
    }

    fn expr(&mut self) -> Result<i64, i64> {
        let mut left = self.and_expr()?;
        while self.peek() == TokenKind::OrOr {
            let line = self.advance().line;
            let right = self.and_expr()?;
            left = self.binary(BinOp::Or, left, right, line);
        }
        Ok(left)
    }

    fn and_expr(&mut self) -> Result<i64, i64> {
        let mut left = self.eq_expr()?;
        while self.peek() == TokenKind::AndAnd {
            let line = self.advance().line;
            let right = self.eq_expr()?;
            left = self.binary(BinOp::And, left, right, line);
        }
        Ok(left)
    }

    fn eq_expr(&mut self) -> Result<i64, i64> {
        let mut left = self.rel_expr()?;
        loop {
            let op = match self.peek() {
                TokenKind::EqEq => BinOp::Eq,
                TokenKind::Ne => BinOp::Ne,
                _ => return Ok(left),
            };
            let line = self.advance().line;
            let right = self.rel_expr()?;
            left = self.binary(op, left, right, line);
        }
    }

    fn rel_expr(&mut self) -> Result<i64, i64> {
        let mut left = self.add_expr()?;
        loop {
            let op = match self.peek() {
                TokenKind::Lt => BinOp::Lt,
                TokenKind::Le => BinOp::Le,
                TokenKind::Gt => BinOp::Gt,
                TokenKind::Ge => BinOp::Ge,
                _ => return Ok(left),
            };
            let line = self.advance().line;
            let right = self.add_expr()?;
            left = self.binary(op, left, right, line);
        }
    }

    fn add_expr(&mut self) -> Result<i64, i64> {
        let mut left = self.mul_expr()?;
        loop {
            let op = match self.peek() {
                TokenKind::Plus => BinOp::Add,
                TokenKind::Minus => BinOp::Sub,
                _ => return Ok(left),
            };
            let line = self.advance().line;
            let right = self.mul_expr()?;
            left = self.binary(op, left, right, line);
        }
    }

    fn mul_expr(&mut self) -> Result<i64, i64> {
        let mut left = self.unary()?;
        loop {
            let op = match self.peek() {
                TokenKind::Star => BinOp::Mul,
                TokenKind::Slash => BinOp::Div,
                TokenKind::Percent => BinOp::Rem,
                _ => return Ok(left),
            };
            let line = self.advance().line;
            let right = self.unary()?;
            left = self.binary(op, left, right, line);
        }
    }

    fn unary(&mut self) -> Result<i64, i64> {
        let op = match self.peek() {
            TokenKind::Minus => UnOp::Neg,
            TokenKind::Bang => UnOp::Not,
            _ => return self.primary(),
        };
        let line = self.advance().line;
        let operand = self.unary()?;
        Ok(self.ast.add_expr(Expr::Unary(op, operand, line)))
    }

    fn primary(&mut self) -> Result<i64, i64> {
        let t = self.advance();
        match t.kind {
            TokenKind::Num => Ok(self.ast.add_expr(Expr::Num(t.value))),
            TokenKind::Ident => Ok(self.ast.add_expr(Expr::Var(t.value, t.line))),
            TokenKind::LParen => {
                let inner = self.expr()?;
                self.expect(TokenKind::RParen)?;
                Ok(inner)
            }
            _ => Err(t.line),
        }
    }

    // `{ stmt* }`: the list (first, count) of its statements.
    fn block(&mut self) -> Result<(i64, i64), i64> {
        self.expect(TokenKind::LBrace)?;
        let mut items: Vec<i64> = Vec::new();
        while self.peek() != TokenKind::RBrace {
            if self.peek() == TokenKind::End {
                return Err(self.advance().line);
            }
            let s = self.stmt()?;
            items.push(s);
        }
        self.advance();
        let first = self.ast.add_list(&items);
        Ok((first, items.len() as i64))
    }

    // `if` and what follows it, the `if` already read.
    fn if_rest(&mut self) -> Result<i64, i64> {
        let cond = self.expr()?;
        let (first, count) = self.block()?;
        let mut els: i64 = -1;
        if self.peek() == TokenKind::Else {
            self.advance();
            if self.peek() == TokenKind::If {
                self.advance();
                els = self.if_rest()?;
            } else {
                let (f, c) = self.block()?;
                els = self.ast.add_stmt(Stmt::Block(f, c));
            }
        }
        Ok(self.ast.add_stmt(Stmt::If(cond, first, count, els)))
    }

    fn stmt(&mut self) -> Result<i64, i64> {
        let t = self.advance();
        match t.kind {
            TokenKind::Let => {
                let name = self.expect(TokenKind::Ident)?.value;
                self.expect(TokenKind::Assign)?;
                let e = self.expr()?;
                self.expect(TokenKind::Semi)?;
                Ok(self.ast.add_stmt(Stmt::Let(name, e)))
            }
            TokenKind::Ident => {
                self.expect(TokenKind::Assign)?;
                let e = self.expr()?;
                self.expect(TokenKind::Semi)?;
                Ok(self.ast.add_stmt(Stmt::Set(t.value, e, t.line)))
            }
            TokenKind::Print => {
                let mut items: Vec<i64> = Vec::new();
                loop {
                    let e = self.expr()?;
                    items.push(e);
                    if self.peek() != TokenKind::Comma {
                        break;
                    }
                    self.advance();
                }
                self.expect(TokenKind::Semi)?;
                let first = self.ast.add_list(&items);
                Ok(self.ast.add_stmt(Stmt::Print(first, items.len() as i64)))
            }
            TokenKind::If => self.if_rest(),
            TokenKind::While => {
                let cond = self.expr()?;
                let (first, count) = self.block()?;
                Ok(self.ast.add_stmt(Stmt::While(cond, first, count)))
            }
            TokenKind::LBrace => {
                self.pos -= 1;
                let (first, count) = self.block()?;
                Ok(self.ast.add_stmt(Stmt::Block(first, count)))
            }
            _ => Err(t.line),
        }
    }
}

// The tree of the whole program, or the line of its first syntax error.
pub fn parse(lexed: Lexed) -> Result<Ast, i64> {
    let ast = Ast {
        exprs: Vec::new(),
        stmts: Vec::new(),
        lists: Vec::new(),
        names: lexed.names,
        top_first: 0,
        top_count: 0,
    };
    let mut p = Parser {
        tokens: lexed.tokens,
        pos: 0,
        ast: ast,
    };
    let mut items: Vec<i64> = Vec::new();
    while p.peek() != TokenKind::End {
        let s = p.stmt()?;
        items.push(s);
    }
    p.ast.top_first = p.ast.add_list(&items);
    p.ast.top_count = items.len() as i64;
    Ok(p.ast)
}
