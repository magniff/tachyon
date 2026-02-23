use crate::lexer::{
    span::Span,
    token::{Token, TokenKind},
};

mod ast;
pub use ast::*;

use std::fmt;

#[derive(Debug, Clone, PartialEq)]
pub struct ParserError {
    pub message: String,
    pub span: Span,
}

impl fmt::Display for ParserError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "parse error at {}..{}: {}",
            self.span.start, self.span.end, self.message
        )
    }
}

pub struct Parser {
    tokens: Vec<Token>,
    pos: usize,
    no_struct: bool,
}

impl Parser {
    pub fn new(tokens: Vec<Token>) -> Self {
        Self {
            tokens,
            pos: 0,
            no_struct: false,
        }
    }

    fn current_token(&self) -> &TokenKind {
        &self.tokens[self.pos].kind
    }
    fn current_token_span(&self) -> Span {
        self.tokens[self.pos].span
    }
    fn is_at_eof(&self) -> bool {
        matches!(self.current_token(), TokenKind::EOF)
    }

    fn at(&self, kind: &TokenKind) -> bool {
        self.current_token() == kind
    }

    fn advance(&mut self) -> &Token {
        let tok = &self.tokens[self.pos];
        if !self.is_at_eof() {
            self.pos += 1;
        }
        tok
    }

    fn expect(&mut self, kind: &TokenKind) -> Result<Span, ParserError> {
        if self.at(kind) {
            let s = self.current_token_span();
            self.advance();
            Ok(s)
        } else {
            Err(self.error(format!(
                "expected '{}', got '{}'",
                kind,
                self.current_token()
            )))
        }
    }

    fn expect_ident(&mut self) -> Result<Spanned<String>, ParserError> {
        if let TokenKind::Ident(name) = self.current_token().clone() {
            let span = self.current_token_span();
            self.advance();
            Ok((name, span))
        } else {
            Err(self.error(format!(
                "expected identifier, got '{}'",
                self.current_token()
            )))
        }
    }

    fn expect_int(&mut self) -> Result<Spanned<u64>, ParserError> {
        if let TokenKind::IntLiteral(v) = self.current_token().clone() {
            let span = self.current_token_span();
            self.advance();
            Ok((v, span))
        } else {
            Err(self.error(format!("expected integer, got '{}'", self.current_token())))
        }
    }

    fn error(&self, msg: impl Into<String>) -> ParserError {
        ParserError {
            message: msg.into(),
            span: self.current_token_span(),
        }
    }

    fn prev_span(&self) -> Span {
        if self.pos > 0 {
            self.tokens[self.pos - 1].span
        } else {
            Span::new(0, 0)
        }
    }

    #[tracing::instrument(skip(self))]
    pub fn parse_program(&mut self) -> Result<Program, ParserError> {
        let mut items = Vec::new();
        while !self.is_at_eof() {
            items.push(self.parse_item()?);
        }
        Ok(Program { items })
    }

    #[tracing::instrument(skip(self))]
    fn parse_item(&mut self) -> Result<Item, ParserError> {
        match self.current_token() {
            TokenKind::Fn => Ok(Item::Function(self.parse_function_decl()?)),
            TokenKind::Extern => Ok(Item::Extern(self.parse_extern_decl()?)),
            TokenKind::Struct => Ok(Item::Struct(self.parse_struct_decl()?)),
            _ => Err(self.error(format!(
                "expected 'fn', 'extern', or 'struct', got '{}'",
                self.current_token()
            ))),
        }
    }

    #[tracing::instrument(skip(self), level = "trace", ret)]
    fn parse_struct_decl(&mut self) -> Result<StructDecl, ParserError> {
        let start = self.current_token_span();
        self.expect(&TokenKind::Struct)?;
        let name = self.expect_ident()?;
        self.expect(&TokenKind::LBrace)?;
        let mut fields = Vec::new();
        while !self.at(&TokenKind::RBrace) && !self.is_at_eof() {
            let fs = self.current_token_span();
            let fname = self.expect_ident()?;
            self.expect(&TokenKind::Colon)?;
            let ty = self.parse_type()?;
            fields.push(StructField {
                name: fname,
                ty,
                span: fs.merge(self.prev_span()),
            });
            if !self.at(&TokenKind::Comma) {
                break;
            }
            self.advance();
        }
        self.expect(&TokenKind::RBrace)?;
        Ok(StructDecl {
            name,
            fields,
            span: start.merge(self.prev_span()),
        })
    }

    #[tracing::instrument(skip(self), level = "trace", ret)]
    fn parse_function_decl(&mut self) -> Result<FunctionDecl, ParserError> {
        let start = self.current_token_span();
        self.expect(&TokenKind::Fn)?;
        let name = self.expect_ident()?;
        self.expect(&TokenKind::LParen)?;
        let (params, _) = self.parse_params(false)?;
        self.expect(&TokenKind::RParen)?;
        let return_type = if self.at(&TokenKind::Arrow) {
            self.advance();
            Some(self.parse_type()?)
        } else {
            None
        };
        let body = self.parse_block()?;
        Ok(FunctionDecl {
            name,
            params,
            return_type,
            body,
            span: start.merge(self.prev_span()),
        })
    }

    #[tracing::instrument(skip(self), level = "trace", ret)]
    fn parse_extern_decl(&mut self) -> Result<ExternDecl, ParserError> {
        let start = self.current_token_span();
        self.expect(&TokenKind::Extern)?;
        self.expect(&TokenKind::Fn)?;
        let name = self.expect_ident()?;
        self.expect(&TokenKind::LParen)?;
        let (params, is_variadic) = self.parse_params(true)?;
        self.expect(&TokenKind::RParen)?;
        let return_type = if self.at(&TokenKind::Arrow) {
            self.advance();
            Some(self.parse_type()?)
        } else {
            None
        };
        self.expect(&TokenKind::Semi)?;
        Ok(ExternDecl {
            name,
            params,
            is_variadic,
            return_type,
            span: start.merge(self.prev_span()),
        })
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_params(&mut self, allow_elipsis: bool) -> Result<(Vec<Parameter>, bool), ParserError> {
        let mut params = Vec::new();
        let mut is_variadic = false;
        while !self.at(&TokenKind::RParen) && !self.is_at_eof() {
            let ps = self.current_token_span();
            // parsing the vararg elipsis thing
            // extern fn printf(format: *u8, ...);
            if allow_elipsis {
                if let Ok(_) = self.expect(&TokenKind::Ellipsis) {
                    is_variadic = true;
                    break;
                }
            }
            // parsing a normal param_name: param_type pair
            let name = self.expect_ident()?;
            self.expect(&TokenKind::Colon)?;
            let ty = self.parse_type()?;
            params.push(Parameter {
                name,
                ty,
                span: ps.merge(self.prev_span()),
            });
            if !self.at(&TokenKind::Comma) {
                break;
            }
            self.advance();
        }
        Ok((params, is_variadic))
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_block(&mut self) -> Result<Block, ParserError> {
        let start = self.current_token_span();
        self.expect(&TokenKind::LBrace)?;
        let mut stmts = Vec::new();
        let mut tail_expr: Option<Box<Expr>> = None;

        while !self.at(&TokenKind::RBrace) && !self.is_at_eof() {
            match self.current_token() {
                TokenKind::Let => stmts.push(Stmt::Let(self.parse_let_stmt()?)),
                TokenKind::Return => stmts.push(Stmt::Return(self.parse_return_stmt()?)),
                TokenKind::Break => stmts.push(Stmt::Break(self.parse_break_stmt()?)),
                TokenKind::Continue => stmts.push(Stmt::Continue(self.parse_continue_stmt()?)),
                TokenKind::Loop => stmts.push(Stmt::Loop(self.parse_loop_stmt()?)),
                _ => {
                    let expr = self.parse_expression()?;
                    match self.current_token() {
                        TokenKind::Eq
                        | TokenKind::PlusEq
                        | TokenKind::MinusEq
                        | TokenKind::ShlEq
                        | TokenKind::ShrEq => {
                            let op = match self.current_token() {
                                TokenKind::Eq => AssignOp::Assign,
                                TokenKind::PlusEq => AssignOp::AddAssign,
                                TokenKind::MinusEq => AssignOp::SubAssign,
                                TokenKind::ShlEq => AssignOp::ShlAssign,
                                _ => AssignOp::ShrAssign,
                            };
                            self.advance();
                            let value = self.parse_expression()?;
                            self.expect(&TokenKind::Semi)?;
                            let target = Self::expr_to_lvalue(expr)?;
                            let span = target.span.merge(self.prev_span());
                            stmts.push(Stmt::Assign(AssignStmt {
                                target,
                                op,
                                value,
                                span,
                            }));
                        }
                        TokenKind::Semi => {
                            let span = expr.span.merge(self.current_token_span());
                            self.advance();
                            stmts.push(Stmt::Expr(ExprStmt { expr, span }));
                        }
                        TokenKind::RBrace => {
                            tail_expr = Some(Box::new(expr));
                        }
                        _ => {
                            return Err(self.error(format!(
                                "expected ';', '=', '+=', '-=', '<<=', '>>=', or '}}', got '{}'",
                                self.current_token()
                            )));
                        }
                    }
                }
            }
        }
        self.expect(&TokenKind::RBrace)?;
        Ok(Block {
            stmts,
            expr: tail_expr,
            span: start.merge(self.prev_span()),
        })
    }

    #[tracing::instrument(level = "trace")]
    fn expr_to_lvalue(expr: Expr) -> Result<LValue, ParserError> {
        let span = expr.span;
        match expr.kind {
            ExprKind::Ident(name) => Ok(LValue {
                kind: LValueKind::Ident(name),
                span,
            }),
            ExprKind::UnaryOp {
                op: UnaryOp::Deref,
                expr: inner,
            } => Ok(LValue {
                kind: LValueKind::Deref(inner),
                span,
            }),
            ExprKind::Field {
                expr: inner,
                name: field,
            } => {
                let inner_lv = Self::expr_to_lvalue(*inner)?;
                Ok(LValue {
                    kind: LValueKind::Field(Box::new(inner_lv), field),
                    span,
                })
            }
            ExprKind::Index { expr: inner, index } => {
                let inner_lv = Self::expr_to_lvalue(*inner)?;
                Ok(LValue {
                    kind: LValueKind::Index(Box::new(inner_lv), *index),
                    span,
                })
            }
            _ => Err(ParserError {
                message: "invalid assignment target".into(),
                span,
            }),
        }
    }

    #[tracing::instrument(skip(self), level = "trace", ret)]
    fn parse_let_stmt(&mut self) -> Result<LetStmt, ParserError> {
        let start = self.current_token_span();
        self.expect(&TokenKind::Let)?;
        let name = self.expect_ident()?;
        let ty = if self.at(&TokenKind::Colon) {
            self.advance();
            Some(self.parse_type()?)
        } else {
            None
        };
        self.expect(&TokenKind::Eq)?;
        let init = self.parse_expression()?;
        self.expect(&TokenKind::Semi)?;
        Ok(LetStmt {
            name,
            ty,
            init,
            span: start.merge(self.prev_span()),
        })
    }

    #[tracing::instrument(skip(self), level = "trace", ret)]
    fn parse_return_stmt(&mut self) -> Result<ReturnStmt, ParserError> {
        let start = self.current_token_span();
        self.expect(&TokenKind::Return)?;
        let value = if !self.at(&TokenKind::Semi) {
            Some(self.parse_expression()?)
        } else {
            None
        };
        self.expect(&TokenKind::Semi)?;
        Ok(ReturnStmt {
            value,
            span: start.merge(self.prev_span()),
        })
    }

    #[tracing::instrument(skip(self), level = "trace", ret)]
    fn parse_break_stmt(&mut self) -> Result<BreakStmt, ParserError> {
        let start = self.current_token_span();
        self.expect(&TokenKind::Break)?;
        self.expect(&TokenKind::Semi)?;
        Ok(BreakStmt {
            span: start.merge(self.prev_span()),
        })
    }

    #[tracing::instrument(skip(self), level = "trace", ret)]
    fn parse_continue_stmt(&mut self) -> Result<ContinueStmt, ParserError> {
        let start = self.current_token_span();
        self.expect(&TokenKind::Continue)?;
        self.expect(&TokenKind::Semi)?;
        Ok(ContinueStmt {
            span: start.merge(self.prev_span()),
        })
    }

    #[tracing::instrument(skip(self), level = "trace", ret)]
    fn parse_loop_stmt(&mut self) -> Result<LoopStmt, ParserError> {
        let start = self.current_token_span();
        self.expect(&TokenKind::Loop)?;
        let body = self.parse_block()?;
        Ok(LoopStmt {
            body,
            span: start.merge(self.prev_span()),
        })
    }

    #[tracing::instrument(skip(self), level = "trace", ret)]
    fn parse_expression(&mut self) -> Result<Expr, ParserError> {
        self.parse_logical_or()
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_expression_no_struct(&mut self) -> Result<Expr, ParserError> {
        let old = self.no_struct;
        self.no_struct = true;
        let result = self.parse_logical_or();
        self.no_struct = old;
        result
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_logical_or(&mut self) -> Result<Expr, ParserError> {
        let mut lhs = self.parse_logical_and()?;
        while self.at(&TokenKind::PipePipe) {
            self.advance();
            let rhs = self.parse_logical_and()?;
            let span = lhs.span.merge(rhs.span);
            lhs = Expr {
                kind: ExprKind::BinOp {
                    op: BinOp::Or,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
                span,
            };
        }
        Ok(lhs)
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_logical_and(&mut self) -> Result<Expr, ParserError> {
        let mut lhs = self.parse_equality()?;
        while self.at(&TokenKind::AmpAmp) {
            self.advance();
            let rhs = self.parse_equality()?;
            let span = lhs.span.merge(rhs.span);
            lhs = Expr {
                kind: ExprKind::BinOp {
                    op: BinOp::And,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
                span,
            };
        }
        Ok(lhs)
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_equality(&mut self) -> Result<Expr, ParserError> {
        let lhs = self.parse_comparison()?;
        let op = match self.current_token() {
            TokenKind::EqEq => Some(BinOp::Eq),
            TokenKind::BangEq => Some(BinOp::Neq),
            _ => None,
        };
        if let Some(op) = op {
            self.advance();
            let rhs = self.parse_comparison()?;
            let span = lhs.span.merge(rhs.span);
            Ok(Expr {
                kind: ExprKind::BinOp {
                    op,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
                span,
            })
        } else {
            Ok(lhs)
        }
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_comparison(&mut self) -> Result<Expr, ParserError> {
        let lhs = self.parse_bitwise_or()?;
        let op = match self.current_token() {
            TokenKind::Lt => Some(BinOp::Lt),
            TokenKind::Gt => Some(BinOp::Gt),
            TokenKind::LtEq => Some(BinOp::LtEq),
            TokenKind::GtEq => Some(BinOp::GtEq),
            _ => None,
        };
        if let Some(op) = op {
            self.advance();
            let rhs = self.parse_bitwise_or()?;
            let span = lhs.span.merge(rhs.span);
            Ok(Expr {
                kind: ExprKind::BinOp {
                    op,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
                span,
            })
        } else {
            Ok(lhs)
        }
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_bitwise_or(&mut self) -> Result<Expr, ParserError> {
        let mut lhs = self.parse_bitwise_xor()?;
        while self.at(&TokenKind::Pipe) {
            self.advance();
            let rhs = self.parse_bitwise_xor()?;
            let span = lhs.span.merge(rhs.span);
            lhs = Expr {
                kind: ExprKind::BinOp {
                    op: BinOp::BitOr,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
                span,
            };
        }
        Ok(lhs)
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_bitwise_xor(&mut self) -> Result<Expr, ParserError> {
        let mut lhs = self.parse_bitwise_and()?;
        while self.at(&TokenKind::Caret) {
            self.advance();
            let rhs = self.parse_bitwise_and()?;
            let span = lhs.span.merge(rhs.span);
            lhs = Expr {
                kind: ExprKind::BinOp {
                    op: BinOp::BitXor,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
                span,
            };
        }
        Ok(lhs)
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_bitwise_and(&mut self) -> Result<Expr, ParserError> {
        let mut lhs = self.parse_shift()?;
        while self.at(&TokenKind::Amp) {
            self.advance();
            let rhs = self.parse_shift()?;
            let span = lhs.span.merge(rhs.span);
            lhs = Expr {
                kind: ExprKind::BinOp {
                    op: BinOp::BitAnd,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
                span,
            };
        }
        Ok(lhs)
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_shift(&mut self) -> Result<Expr, ParserError> {
        let mut lhs = self.parse_additive()?;
        loop {
            let op = match self.current_token() {
                TokenKind::Shl => BinOp::Shl,
                TokenKind::Shr => BinOp::Shr,
                _ => break,
            };
            self.advance();
            let rhs = self.parse_additive()?;
            let span = lhs.span.merge(rhs.span);
            lhs = Expr {
                kind: ExprKind::BinOp {
                    op,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
                span,
            };
        }
        Ok(lhs)
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_additive(&mut self) -> Result<Expr, ParserError> {
        let mut lhs = self.parse_multiplicative()?;
        loop {
            let op = match self.current_token() {
                TokenKind::Plus => BinOp::Add,
                TokenKind::Minus => BinOp::Sub,
                _ => break,
            };
            self.advance();
            let rhs = self.parse_multiplicative()?;
            let span = lhs.span.merge(rhs.span);
            lhs = Expr {
                kind: ExprKind::BinOp {
                    op,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
                span,
            };
        }
        Ok(lhs)
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_multiplicative(&mut self) -> Result<Expr, ParserError> {
        let mut lhs = self.parse_cast()?;
        loop {
            let op = match self.current_token() {
                TokenKind::Star => BinOp::Mul,
                TokenKind::Slash => BinOp::Div,
                TokenKind::Percent => BinOp::Mod,
                _ => break,
            };
            self.advance();
            let rhs = self.parse_cast()?;
            let span = lhs.span.merge(rhs.span);
            lhs = Expr {
                kind: ExprKind::BinOp {
                    op,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
                span,
            };
        }
        Ok(lhs)
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_cast(&mut self) -> Result<Expr, ParserError> {
        let mut expr = self.parse_unary()?;
        while self.at(&TokenKind::As) {
            self.advance();
            let ty = self.parse_type()?;
            let span = expr.span.merge(ty.span);
            expr = Expr {
                kind: ExprKind::Cast {
                    expr: Box::new(expr),
                    ty,
                },
                span,
            };
        }
        Ok(expr)
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_unary(&mut self) -> Result<Expr, ParserError> {
        let op = match self.current_token() {
            TokenKind::Minus => Some(UnaryOp::Neg),
            TokenKind::Plus => Some(UnaryOp::Pos),
            TokenKind::Bang => Some(UnaryOp::Not),
            TokenKind::Tilde => Some(UnaryOp::BitNot),
            TokenKind::Star => Some(UnaryOp::Deref),
            TokenKind::Amp => Some(UnaryOp::AddrOf),
            _ => None,
        };
        if let Some(op) = op {
            let start = self.current_token_span();
            self.advance();
            let expr = self.parse_unary()?;
            let span = start.merge(expr.span);
            Ok(Expr {
                kind: ExprKind::UnaryOp {
                    op,
                    expr: Box::new(expr),
                },
                span,
            })
        } else if matches!(self.current_token(), TokenKind::StarStar) {
            // Lexer greedily matched ** — treat as two derefs: *(*expr)
            let start = self.current_token_span();
            self.advance();
            let inner = self.parse_unary()?;
            let inner_span = start.merge(inner.span);
            let inner_deref = Expr {
                kind: ExprKind::UnaryOp {
                    op: UnaryOp::Deref,
                    expr: Box::new(inner),
                },
                span: inner_span,
            };
            Ok(Expr {
                kind: ExprKind::UnaryOp {
                    op: UnaryOp::Deref,
                    expr: Box::new(inner_deref),
                },
                span: start.merge(inner_span),
            })
        } else {
            self.parse_exponent()
        }
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_exponent(&mut self) -> Result<Expr, ParserError> {
        let lhs = self.parse_postfix()?;
        if self.at(&TokenKind::StarStar) {
            self.advance();
            let rhs = self.parse_exponent()?;
            let span = lhs.span.merge(rhs.span);
            Ok(Expr {
                kind: ExprKind::BinOp {
                    op: BinOp::Pow,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
                span,
            })
        } else {
            Ok(lhs)
        }
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_postfix(&mut self) -> Result<Expr, ParserError> {
        let mut expr = self.parse_primary()?;
        loop {
            match self.current_token() {
                TokenKind::LParen => {
                    self.advance();
                    let args = self.parse_arg_list()?;
                    self.expect(&TokenKind::RParen)?;
                    let span = expr.span.merge(self.prev_span());
                    expr = Expr {
                        kind: ExprKind::Call {
                            callee: Box::new(expr),
                            args,
                        },
                        span,
                    };
                }
                TokenKind::LBracket => {
                    self.advance();
                    let index = self.parse_expression()?;
                    self.expect(&TokenKind::RBracket)?;
                    let span = expr.span.merge(self.prev_span());
                    expr = Expr {
                        kind: ExprKind::Index {
                            expr: Box::new(expr),
                            index: Box::new(index),
                        },
                        span,
                    };
                }
                TokenKind::Dot => {
                    self.advance();
                    match self.current_token().clone() {
                        TokenKind::Ident(name) => {
                            let fs = self.current_token_span();
                            self.advance();
                            let span = expr.span.merge(fs);
                            expr = Expr {
                                kind: ExprKind::Field {
                                    expr: Box::new(expr),
                                    name: (name, fs),
                                },
                                span,
                            };
                        }
                        TokenKind::IntLiteral(idx) => {
                            let is = self.current_token_span();
                            self.advance();
                            let span = expr.span.merge(is);
                            expr = Expr {
                                kind: ExprKind::TupleField {
                                    expr: Box::new(expr),
                                    index: (idx, is),
                                },
                                span,
                            };
                        }
                        _ => {
                            return Err(self.error(format!(
                                "expected field name or index after '.', got '{}'",
                                self.current_token()
                            )));
                        }
                    }
                }
                _ => break,
            }
        }
        Ok(expr)
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_arg_list(&mut self) -> Result<Vec<Expr>, ParserError> {
        let mut args = Vec::new();
        if self.at(&TokenKind::RParen) {
            return Ok(args);
        }
        loop {
            args.push(self.parse_expression()?);
            if !self.at(&TokenKind::Comma) {
                break;
            }
            self.advance();
            if self.at(&TokenKind::RParen) {
                break;
            } // trailing comma
        }
        Ok(args)
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_primary(&mut self) -> Result<Expr, ParserError> {
        match self.current_token().clone() {
            TokenKind::IntLiteral(v) => {
                let span = self.current_token_span();
                self.advance();
                Ok(Expr {
                    kind: ExprKind::IntLiteral(v),
                    span,
                })
            }
            TokenKind::FloatLiteral(v) => {
                let span = self.current_token_span();
                self.advance();
                Ok(Expr {
                    kind: ExprKind::FloatLiteral(v),
                    span,
                })
            }
            TokenKind::StringLiteral(s) => {
                let span = self.current_token_span();
                self.advance();
                Ok(Expr {
                    kind: ExprKind::StringLiteral(s),
                    span,
                })
            }
            TokenKind::True => {
                let span = self.current_token_span();
                self.advance();
                Ok(Expr {
                    kind: ExprKind::BoolLiteral(true),
                    span,
                })
            }
            TokenKind::False => {
                let span = self.current_token_span();
                self.advance();
                Ok(Expr {
                    kind: ExprKind::BoolLiteral(false),
                    span,
                })
            }
            TokenKind::LParen => self.parse_paren_expr(),
            TokenKind::LBracket => self.parse_array_literal(),
            TokenKind::LBrace => {
                let block = self.parse_block()?;
                let span = block.span;
                Ok(Expr {
                    kind: ExprKind::Block(block),
                    span,
                })
            }
            TokenKind::If => self.parse_if_expression(),
            TokenKind::Ident(name) => {
                let name_span = self.current_token_span();
                self.advance();
                if !self.no_struct && self.at(&TokenKind::LBrace) {
                    self.parse_struct_constructor_rest(name, name_span)
                } else {
                    Ok(Expr {
                        kind: ExprKind::Ident(name),
                        span: name_span,
                    })
                }
            }
            _ => Err(self.error(format!(
                "expected expression, got '{}'",
                self.current_token()
            ))),
        }
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_paren_expr(&mut self) -> Result<Expr, ParserError> {
        let start = self.current_token_span();
        self.expect(&TokenKind::LParen)?;

        // Unit: ()
        if self.at(&TokenKind::RParen) {
            self.advance();
            return Ok(Expr {
                kind: ExprKind::UnitLiteral,
                span: start.merge(self.prev_span()),
            });
        }

        let first = self.parse_expression()?;

        // Tuple: (expr,) or (expr, expr, ...)
        if self.at(&TokenKind::Comma) {
            self.advance();
            let mut elems = vec![first];
            if !self.at(&TokenKind::RParen) {
                loop {
                    elems.push(self.parse_expression()?);
                    if !self.at(&TokenKind::Comma) {
                        break;
                    }
                    self.advance();
                    if self.at(&TokenKind::RParen) {
                        break;
                    }
                }
            }
            self.expect(&TokenKind::RParen)?;
            return Ok(Expr {
                kind: ExprKind::Tuple(elems),
                span: start.merge(self.prev_span()),
            });
        }

        // Parenthesized: (expr)
        self.expect(&TokenKind::RParen)?;
        Ok(Expr {
            kind: first.kind,
            span: start.merge(self.prev_span()),
        })
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_array_literal(&mut self) -> Result<Expr, ParserError> {
        let start = self.current_token_span();
        self.expect(&TokenKind::LBracket)?;
        let first = self.parse_expression()?;

        // Repeat: [expr; expr]
        if self.at(&TokenKind::Semi) {
            self.advance();
            let count = self.parse_expression()?;
            self.expect(&TokenKind::RBracket)?;
            return Ok(Expr {
                kind: ExprKind::ArrayRepeat(Box::new(first), Box::new(count)),
                span: start.merge(self.prev_span()),
            });
        }

        // List: [expr, expr, ...]
        let mut elems = vec![first];
        while self.at(&TokenKind::Comma) {
            self.advance();
            if self.at(&TokenKind::RBracket) {
                break;
            }
            elems.push(self.parse_expression()?);
        }
        self.expect(&TokenKind::RBracket)?;
        Ok(Expr {
            kind: ExprKind::Array(elems),
            span: start.merge(self.prev_span()),
        })
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_struct_constructor_rest(
        &mut self,
        name: String,
        name_span: Span,
    ) -> Result<Expr, ParserError> {
        self.expect(&TokenKind::LBrace)?;
        let mut fields = Vec::new();
        while !self.at(&TokenKind::RBrace) && !self.is_at_eof() {
            let fs = self.current_token_span();
            let fname = self.expect_ident()?;
            self.expect(&TokenKind::Colon)?;
            let value = self.parse_expression()?;
            fields.push(FieldInit {
                name: fname,
                value,
                span: fs.merge(self.prev_span()),
            });
            if !self.at(&TokenKind::Comma) {
                break;
            }
            self.advance();
        }
        self.expect(&TokenKind::RBrace)?;
        Ok(Expr {
            kind: ExprKind::StructConstructor {
                name: (name, name_span),
                fields,
            },
            span: name_span.merge(self.prev_span()),
        })
    }

    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_if_expression(&mut self) -> Result<Expr, ParserError> {
        let start = self.current_token_span();
        self.expect(&TokenKind::If)?;
        let cond = self.parse_expression_no_struct()?;
        let then_block = self.parse_block()?;
        let else_block = if self.at(&TokenKind::Else) {
            self.advance();
            Some(self.parse_block()?)
        } else {
            None
        };
        Ok(Expr {
            kind: ExprKind::If {
                cond: Box::new(cond),
                then_block,
                else_block,
            },
            span: start.merge(self.prev_span()),
        })
    }

    // ---- Types ----
    #[tracing::instrument(skip(self), level = "trace")]
    fn parse_type(&mut self) -> Result<Type, ParserError> {
        let start = self.current_token_span();
        match self.current_token().clone() {
            TokenKind::Ident(name) => {
                self.advance();
                Ok(Type {
                    kind: TypeKind::Named(name),
                    span: start,
                })
            }
            TokenKind::Star => {
                self.advance();
                let inner = self.parse_type()?;
                Ok(Type {
                    kind: TypeKind::Pointer(Box::new(inner)),
                    span: start.merge(self.prev_span()),
                })
            }
            TokenKind::StarStar => {
                // Lexer greedily matched ** — treat as two pointer indirections
                self.advance();
                let inner = self.parse_type()?;
                let inner_span = start.merge(inner.span);
                let inner_ptr = Type {
                    kind: TypeKind::Pointer(Box::new(inner)),
                    span: inner_span,
                };
                Ok(Type {
                    kind: TypeKind::Pointer(Box::new(inner_ptr)),
                    span: start.merge(self.prev_span()),
                })
            }
            TokenKind::LParen => {
                self.advance();
                if self.at(&TokenKind::RParen) {
                    self.advance();
                    return Ok(Type {
                        kind: TypeKind::Unit,
                        span: start.merge(self.prev_span()),
                    });
                }
                let first = self.parse_type()?;
                if self.at(&TokenKind::Comma) {
                    self.advance();
                    let mut types = vec![first];
                    if !self.at(&TokenKind::RParen) {
                        loop {
                            types.push(self.parse_type()?);
                            if !self.at(&TokenKind::Comma) {
                                break;
                            }
                            self.advance();
                            if self.at(&TokenKind::RParen) {
                                break;
                            }
                        }
                    }
                    self.expect(&TokenKind::RParen)?;
                    return Ok(Type {
                        kind: TypeKind::Tuple(types),
                        span: start.merge(self.prev_span()),
                    });
                }
                // Parenthesized type
                self.expect(&TokenKind::RParen)?;
                Ok(first)
            }
            TokenKind::LBracket => {
                self.advance();
                let elem = self.parse_type()?;
                self.expect(&TokenKind::Semi)?;
                let (size, _) = self.expect_int()?;
                self.expect(&TokenKind::RBracket)?;
                Ok(Type {
                    kind: TypeKind::Array(Box::new(elem), size),
                    span: start.merge(self.prev_span()),
                })
            }
            TokenKind::Fn => {
                self.advance();
                self.expect(&TokenKind::LParen)?;
                let mut param_types = Vec::new();
                let mut is_variadic = false;
                if !self.at(&TokenKind::RParen) {
                    loop {
                        if let Ok(_) = self.expect(&TokenKind::Ellipsis) {
                            is_variadic = true;
                            break;
                        }
                        param_types.push(self.parse_type()?);

                        if !self.at(&TokenKind::Comma) {
                            break;
                        }
                        self.advance();
                        if self.at(&TokenKind::RParen) {
                            break;
                        }
                    }
                }
                self.expect(&TokenKind::RParen)?;
                let ret = if self.at(&TokenKind::Arrow) {
                    self.advance();
                    Box::new(self.parse_type()?)
                } else {
                    Box::new(Type {
                        kind: TypeKind::Unit,
                        span: self.current_token_span(),
                    })
                };

                Ok(Type {
                    kind: TypeKind::Fn {
                        params: param_types,
                        result: ret,
                        is_variadic,
                    },
                    span: start.merge(self.prev_span()),
                })
            }
            _ => Err(self.error(format!("expected type, got '{}'", self.current_token()))),
        }
    }
}

#[tracing::instrument(skip(tokens))]
pub fn parse(tokens: &[crate::lexer::token::Token]) -> Result<Program, ParserError> {
    Parser::new(tokens.into()).parse_program()
}

#[cfg(test)]
mod tests {
    use crate::lexer::float::Float;

    use super::*;

    pub fn parse_source(src: &str) -> Result<Program, ParserError> {
        parse(&crate::lexer::Lexer::new(src).tokenize().unwrap())
    }

    fn parse_ok(src: &str) -> Program {
        parse_source(src).unwrap_or_else(|e| panic!("parse failed: {}\nsource: {}", e, src))
    }

    fn parse_err(src: &str) {
        assert!(
            parse_source(src).is_err(),
            "expected parse error for: {}",
            src
        );
    }

    #[test]
    fn test_empty_program() {
        let p = parse_ok("");
        assert!(p.items.is_empty());
    }

    #[test]
    fn test_empty_function() {
        let p = parse_ok("fn main() {}");
        assert_eq!(p.items.len(), 1);
    }

    #[test]
    fn test_fn_params_and_return() {
        parse_ok("fn add(a: i32, b: i32) -> i32 { a }");
    }

    #[test]
    fn test_trailing_comma_params() {
        parse_ok("fn foo(a: i32, b: i32,) {}");
    }

    #[test]
    fn test_extern_decl() {
        parse_ok("extern fn puts(s: *u8) -> i32;");
    }

    #[test]
    fn test_struct_decl() {
        parse_ok("struct Point { x: i32, y: i32 }");
    }

    #[test]
    fn test_struct_trailing_comma() {
        parse_ok("struct Point { x: i32, y: i32, }");
    }

    #[test]
    fn test_empty_struct() {
        parse_ok("struct Empty {}");
    }

    #[test]
    fn test_let_with_type() {
        parse_ok("fn main() { let x: i32 = 42; }");
    }

    #[test]
    fn test_let_without_type() {
        parse_ok("fn main() { let x = 42; }");
    }

    #[test]
    fn test_assignment() {
        parse_ok("fn main() { let x = 0; x = 42; }");
    }

    #[test]
    fn test_compound_assignment() {
        parse_ok("fn main() { let x = 0; x += 1; x -= 2; }");
        parse_ok("fn main() { let x = 0; x <<= 1; x >>= 2; }");
    }

    #[test]
    fn test_return_value() {
        parse_ok("fn main() -> i32 { return 42; }");
    }

    #[test]
    fn test_return_void() {
        parse_ok("fn main() { return; }");
    }

    #[test]
    fn test_break_continue() {
        parse_ok("fn main() { loop { break; } }");
        parse_ok("fn main() { loop { continue; } }");
    }

    #[test]
    fn test_loop_stmt() {
        parse_ok("fn main() { loop { break; } }");
    }

    #[test]
    fn test_tail_expression() {
        let p = parse_ok("fn main() -> i32 { 42 }");
        if let Item::Function(f) = &p.items[0] {
            assert!(f.body.expr.is_some());
        }
    }

    #[test]
    fn test_binary_ops() {
        parse_ok("fn main() { let x = 1 + 2 * 3; }");
        parse_ok("fn main() { let x = 1 == 2; }");
        parse_ok("fn main() { let x = 1 != 2; }");
        parse_ok("fn main() { let x = 1 < 2; }");
        parse_ok("fn main() { let x = true && false || true; }");
        parse_ok("fn main() { let x = 1 | 2 ^ 3 & 4; }");
        parse_ok("fn main() { let x = 2 ** 3 ** 4; }");
        parse_ok("fn main() { let x = 10 % 3; }");
        parse_ok("fn main() { let x = 1 << 2; }");
        parse_ok("fn main() { let x = 8 >> 1; }");
    }

    #[test]
    fn test_unary_ops() {
        parse_ok("fn main() { let x = -1; }");
        parse_ok("fn main() { let x = !true; }");
        parse_ok("fn main() { let x = ~0xFF; }");
        parse_ok("fn main() { let x = *ptr; }");
        parse_ok("fn main() { let x = &y; }");
    }

    #[test]
    fn test_cast() {
        parse_ok("fn main() { let x = 42 as f64; }");
        parse_ok("fn main() { let x = 42 as f64 as i32; }");
    }

    #[test]
    fn test_function_call() {
        parse_ok("fn main() { foo(); }");
        parse_ok("fn main() { foo(1, 2, 3); }");
        parse_ok("fn main() { foo(1, 2,); }");
    }

    #[test]
    fn test_index() {
        parse_ok("fn main() { let x = arr[0]; }");
    }

    #[test]
    fn test_field_access() {
        parse_ok("fn main() { let x = point.x; }");
        parse_ok("fn main() { let x = tuple.0; }");
    }

    #[test]
    fn test_chained_postfix() {
        parse_ok("fn main() { foo().bar[0].baz(1, 2); }");
    }

    #[test]
    fn test_unit_literal() {
        parse_ok("fn main() { let x = (); }");
    }

    #[test]
    fn test_tuple_literal() {
        parse_ok("fn main() { let x = (1,); }");
        parse_ok("fn main() { let x = (1, 2); }");
        parse_ok("fn main() { let x = (1, 2, 3); }");
    }

    #[test]
    fn test_paren_expr() {
        parse_ok("fn main() { let x = (1 + 2) * 3; }");
    }

    #[test]
    fn test_array_literal() {
        parse_ok("fn main() { let x = [1, 2, 3]; }");
        parse_ok("fn main() { let x = [1, 2, 3,]; }");
    }

    #[test]
    fn test_array_repeat() {
        parse_ok("fn main() { let x = [0; 10]; }");
    }

    #[test]
    fn test_struct_constructor() {
        parse_ok("struct Foo { x: i32 } fn main() { let f = Foo { x: 42 }; }");
    }

    #[test]
    fn test_struct_constructor_trailing_comma() {
        parse_ok("struct Foo { x: i32, y: i32 } fn main() { let f = Foo { x: 1, y: 2, }; }");
    }

    #[test]
    fn test_if_expression() {
        parse_ok("fn main() { if true { 1; }; }");
        parse_ok("fn main() { let x = if true { 1 } else { 2 }; }");
    }

    #[test]
    fn test_if_no_struct_ambiguity() {
        parse_ok("fn main() { if a { 1; }; }");
    }

    #[test]
    fn test_block_expression() {
        parse_ok("fn main() { let x = { let y = 1; y + 1 }; }");
    }

    #[test]
    fn test_nested_blocks() {
        parse_ok("fn main() { let x = { { 42 } }; }");
    }

    // -- Types --

    #[test]
    fn test_type_named() {
        parse_ok("fn foo(x: i32) {}");
    }

    #[test]
    fn test_type_unit() {
        parse_ok("fn foo() -> () {}");
    }

    #[test]
    fn test_type_tuple() {
        parse_ok("fn foo(x: (i32, f64)) {}");
    }

    #[test]
    fn test_type_1tuple() {
        parse_ok("fn foo(x: (i32,)) {}");
    }

    #[test]
    fn test_type_array() {
        parse_ok("fn foo(x: [i32; 10]) {}");
    }

    #[test]
    fn test_type_pointer() {
        parse_ok("fn foo(x: *i32) {}");
        parse_ok("fn foo(x: **i32) {}");
    }

    #[test]
    fn test_type_fn_ptr() {
        parse_ok("fn foo(f: fn(i32, i32) -> i32) {}");
        parse_ok("fn foo(f: fn()) {}");
    }

    #[test]
    fn test_type_complex() {
        parse_ok("fn foo(f: fn(*i32, [u8; 4]) -> (i32, f64)) {}");
    }

    // -- Assignment targets --

    #[test]
    fn test_assign_deref() {
        parse_ok("fn main() { *ptr = 42; }");
    }

    #[test]
    fn test_assign_field() {
        parse_ok("fn main() { point.x = 42; }");
    }

    #[test]
    fn test_assign_index() {
        parse_ok("fn main() { arr[0] = 42; }");
    }

    #[test]
    fn test_assign_nested() {
        parse_ok("fn main() { (*ptr).x = 42; }");
    }

    #[test]
    fn test_complex_lvalue() {
        parse_ok("fn main() { a.b.c[0] = 1; }");
    }

    // -- Error cases --

    #[test]
    fn test_err_missing_semi() {
        parse_err("fn main() { let x = 42 }");
    }

    #[test]
    fn test_err_invalid_assign_target() {
        parse_err("fn main() { 42 = 1; }");
    }

    #[test]
    fn test_err_unexpected_token() {
        parse_err("fn main( {}");
    }

    #[test]
    fn test_err_loop_not_expression() {
        // loop is a statement; using it where an expression is expected should fail
        parse_err("fn main() { let x = loop { break; }; }");
    }

    #[test]
    fn test_err_break_with_value() {
        // break no longer accepts a value
        parse_err("fn main() { loop { break 42; } }");
    }

    // -- Extra --
    #[test]
    fn test_string_escapes() {
        parse_ok(r#"fn main() { let s = "hello\nworld\t\r\0\"\\"; }"#);
        parse_ok(r#"fn main() { let s = "\x41\x42"; }"#);
    }

    #[test]
    fn test_multiple_structs_and_fns() {
        parse_ok(
            r#"
            struct A { x: i32 }
            struct B { y: f64 }
            fn foo() -> A { A { x: 1 } }
            fn bar() -> B { B { y: 2.0 } }
        "#,
        );
    }

    #[test]
    fn test_empty_struct_constructor() {
        parse_ok("struct Empty {} fn main() { let e = Empty {}; }");
    }

    #[test]
    fn test_nested_if() {
        parse_ok("fn main() { if true { if false { 1; } else { 2; }; }; }");
    }

    #[test]
    fn test_precedence_and_vs_or() {
        parse_ok("fn main() { let x = a || b && c; }");
    }

    #[test]
    fn test_unary_addr_of_deref() {
        parse_ok("fn main() { let x = &*ptr; }");
    }

    #[test]
    fn test_double_deref() {
        parse_ok("fn main() { let x = **ptr; }");
    }

    // -- Comprehensive: full AST comparison --

    const S: Span = Span { start: 0, end: 0 };
    fn sp(name: &str) -> Spanned<String> {
        (name.to_string(), S)
    }
    fn spu(v: u64) -> Spanned<u64> {
        (v, S)
    }
    fn named(n: &str) -> Type {
        Type {
            kind: TypeKind::Named(n.to_string()),
            span: S,
        }
    }
    fn ptr_ty(inner: Type) -> Type {
        Type {
            kind: TypeKind::Pointer(Box::new(inner)),
            span: S,
        }
    }
    fn tuple_ty(ts: Vec<Type>) -> Type {
        Type {
            kind: TypeKind::Tuple(ts),
            span: S,
        }
    }
    fn int(v: u64) -> Expr {
        Expr {
            kind: ExprKind::IntLiteral(v),
            span: S,
        }
    }
    fn float(v: f64) -> Expr {
        Expr {
            kind: ExprKind::FloatLiteral(Float::from(v)),
            span: S,
        }
    }
    fn bool_(v: bool) -> Expr {
        Expr {
            kind: ExprKind::BoolLiteral(v),
            span: S,
        }
    }
    fn id(n: &str) -> Expr {
        Expr {
            kind: ExprKind::Ident(n.to_string()),
            span: S,
        }
    }
    fn bin(op: BinOp, l: Expr, r: Expr) -> Expr {
        Expr {
            kind: ExprKind::BinOp {
                op,
                lhs: Box::new(l),
                rhs: Box::new(r),
            },
            span: S,
        }
    }
    fn un(op: UnaryOp, e: Expr) -> Expr {
        Expr {
            kind: ExprKind::UnaryOp {
                op,
                expr: Box::new(e),
            },
            span: S,
        }
    }
    fn call(callee: Expr, args: Vec<Expr>) -> Expr {
        Expr {
            kind: ExprKind::Call {
                callee: Box::new(callee),
                args,
            },
            span: S,
        }
    }
    fn fld(e: Expr, name: &str) -> Expr {
        Expr {
            kind: ExprKind::Field {
                expr: Box::new(e),
                name: sp(name),
            },
            span: S,
        }
    }
    fn tfield(e: Expr, idx: u64) -> Expr {
        Expr {
            kind: ExprKind::TupleField {
                expr: Box::new(e),
                index: spu(idx),
            },
            span: S,
        }
    }
    fn idx(e: Expr, i: Expr) -> Expr {
        Expr {
            kind: ExprKind::Index {
                expr: Box::new(e),
                index: Box::new(i),
            },
            span: S,
        }
    }
    fn cast(e: Expr, ty: Type) -> Expr {
        Expr {
            kind: ExprKind::Cast {
                expr: Box::new(e),
                ty,
            },
            span: S,
        }
    }
    fn tuple_expr(es: Vec<Expr>) -> Expr {
        Expr {
            kind: ExprKind::Tuple(es),
            span: S,
        }
    }
    fn array(es: Vec<Expr>) -> Expr {
        Expr {
            kind: ExprKind::Array(es),
            span: S,
        }
    }
    fn struct_init(name: &str, fields: Vec<(&str, Expr)>) -> Expr {
        Expr {
            kind: ExprKind::StructConstructor {
                name: sp(name),
                fields: fields
                    .into_iter()
                    .map(|(n, v)| FieldInit {
                        name: sp(n),
                        value: v,
                        span: S,
                    })
                    .collect(),
            },
            span: S,
        }
    }
    fn if_expr(cond: Expr, then: Block, else_: Option<Block>) -> Expr {
        Expr {
            kind: ExprKind::If {
                cond: Box::new(cond),
                then_block: then,
                else_block: else_,
            },
            span: S,
        }
    }
    fn blk(stmts: Vec<Stmt>, tail: Option<Expr>) -> Block {
        Block {
            stmts,
            expr: tail.map(Box::new),
            span: S,
        }
    }
    fn let_(name: &str, ty: Option<Type>, init: Expr) -> Stmt {
        Stmt::Let(LetStmt {
            name: sp(name),
            ty,
            init,
            span: S,
        })
    }
    fn assign(name: &str, val: Expr) -> Stmt {
        Stmt::Assign(AssignStmt {
            target: LValue {
                kind: LValueKind::Ident(name.to_string()),
                span: S,
            },
            op: AssignOp::Assign,
            value: val,
            span: S,
        })
    }
    fn add_assign(name: &str, val: Expr) -> Stmt {
        Stmt::Assign(AssignStmt {
            target: LValue {
                kind: LValueKind::Ident(name.to_string()),
                span: S,
            },
            op: AssignOp::AddAssign,
            value: val,
            span: S,
        })
    }
    fn expr_stmt(e: Expr) -> Stmt {
        Stmt::Expr(ExprStmt { expr: e, span: S })
    }
    fn break_s() -> Stmt {
        Stmt::Break(BreakStmt { span: S })
    }
    fn loop_s(body: Block) -> Stmt {
        Stmt::Loop(LoopStmt { body, span: S })
    }
    fn param(name: &str, ty: Type) -> Parameter {
        Parameter {
            name: sp(name),
            ty,
            span: S,
        }
    }
    fn sfield(name: &str, ty: Type) -> StructField {
        StructField {
            name: sp(name),
            ty,
            span: S,
        }
    }

    #[test]
    fn test_comprehensive_program() {
        let src = r#"
            struct Vec2 { x: f64, y: f64 }

            extern fn sqrt(x: f64) -> f64;
            extern fn printf(fmt: *u8, ...) -> i32;

            fn length(v: Vec2) -> f64 {
                let sq = v.x * v.x + v.y * v.y;
                sqrt(sq)
            }

            fn dot(a: Vec2, b: Vec2) -> f64 {
                a.x * b.x + a.y * b.y
            }

            fn abs(x: i32) -> i32 {
                if x < 0 { -x } else { x }
            }

            fn fib(n: i32) -> i32 {
                let a = 0;
                let b = 1;
                let i = 0;
                loop {
                    if i == n { break; };
                    let temp = b;
                    b = a + b;
                    a = temp;
                    i += 1;
                }
                a
            }

            fn main() -> i32 {
                let v = Vec2 { x: 3.0, y: 4.0 };
                let len = length(v);

                let arr = [1, 2, 3, 4, 5];
                let sum = 0;
                let i = 0;
                loop {
                    if i == 5 { break; };
                    sum += arr[i];
                    i += 1;
                }

                let pair: (i32, i32) = (10, 20);
                let first = pair.0;
                let answer = fib(10);
                let ptr = &sum;
                let val = *ptr;
                let mask = 0xFF & (0b1010 | 0x0F);
                let big = 2 ** 3 ** 2;
                let cast_val = 42 as f64;
                let flag = true && !false || 1 != 2;
                0
            }
        "#;

        let actual = parse_ok(src);

        let item_struct = Item::Struct(StructDecl {
            name: sp("Vec2"),
            fields: vec![sfield("x", named("f64")), sfield("y", named("f64"))],
            span: S,
        });

        let item_sqrt = Item::Extern(ExternDecl {
            name: sp("sqrt"),
            params: vec![param("x", named("f64"))],
            is_variadic: false,
            return_type: Some(named("f64")),
            span: S,
        });

        let item_printf = Item::Extern(ExternDecl {
            name: sp("printf"),
            params: vec![param("fmt", ptr_ty(named("u8")))],
            is_variadic: true,
            return_type: Some(named("i32")),
            span: S,
        });

        let item_length = Item::Function(FunctionDecl {
            name: sp("length"),
            params: vec![param("v", named("Vec2"))],
            return_type: Some(named("f64")),
            body: blk(
                vec![let_(
                    "sq",
                    None,
                    bin(
                        BinOp::Add,
                        bin(BinOp::Mul, fld(id("v"), "x"), fld(id("v"), "x")),
                        bin(BinOp::Mul, fld(id("v"), "y"), fld(id("v"), "y")),
                    ),
                )],
                Some(call(id("sqrt"), vec![id("sq")])),
            ),
            span: S,
        });

        let item_dot = Item::Function(FunctionDecl {
            name: sp("dot"),
            params: vec![param("a", named("Vec2")), param("b", named("Vec2"))],
            return_type: Some(named("f64")),
            body: blk(
                vec![],
                Some(bin(
                    BinOp::Add,
                    bin(BinOp::Mul, fld(id("a"), "x"), fld(id("b"), "x")),
                    bin(BinOp::Mul, fld(id("a"), "y"), fld(id("b"), "y")),
                )),
            ),
            span: S,
        });

        let item_abs = Item::Function(FunctionDecl {
            name: sp("abs"),
            params: vec![param("x", named("i32"))],
            return_type: Some(named("i32")),
            body: blk(
                vec![],
                Some(if_expr(
                    bin(BinOp::Lt, id("x"), int(0)),
                    blk(vec![], Some(un(UnaryOp::Neg, id("x")))),
                    Some(blk(vec![], Some(id("x")))),
                )),
            ),
            span: S,
        });

        let item_fib = Item::Function(FunctionDecl {
            name: sp("fib"),
            params: vec![param("n", named("i32"))],
            return_type: Some(named("i32")),
            body: blk(
                vec![
                    let_("a", None, int(0)),
                    let_("b", None, int(1)),
                    let_("i", None, int(0)),
                    loop_s(blk(
                        vec![
                            expr_stmt(if_expr(
                                bin(BinOp::Eq, id("i"), id("n")),
                                blk(vec![break_s()], None),
                                None,
                            )),
                            let_("temp", None, id("b")),
                            assign("b", bin(BinOp::Add, id("a"), id("b"))),
                            assign("a", id("temp")),
                            add_assign("i", int(1)),
                        ],
                        None,
                    )),
                ],
                Some(id("a")),
            ),
            span: S,
        });

        let item_main = Item::Function(FunctionDecl {
            name: sp("main"),
            params: vec![],
            return_type: Some(named("i32")),
            body: blk(
                vec![
                    let_(
                        "v",
                        None,
                        struct_init("Vec2", vec![("x", float(3.0)), ("y", float(4.0))]),
                    ),
                    let_("len", None, call(id("length"), vec![id("v")])),
                    let_(
                        "arr",
                        None,
                        array(vec![int(1), int(2), int(3), int(4), int(5)]),
                    ),
                    let_("sum", None, int(0)),
                    let_("i", None, int(0)),
                    loop_s(blk(
                        vec![
                            expr_stmt(if_expr(
                                bin(BinOp::Eq, id("i"), int(5)),
                                blk(vec![break_s()], None),
                                None,
                            )),
                            add_assign("sum", idx(id("arr"), id("i"))),
                            add_assign("i", int(1)),
                        ],
                        None,
                    )),
                    let_(
                        "pair",
                        Some(tuple_ty(vec![named("i32"), named("i32")])),
                        tuple_expr(vec![int(10), int(20)]),
                    ),
                    let_("first", None, tfield(id("pair"), 0)),
                    let_("answer", None, call(id("fib"), vec![int(10)])),
                    let_("ptr", None, un(UnaryOp::AddrOf, id("sum"))),
                    let_("val", None, un(UnaryOp::Deref, id("ptr"))),
                    let_(
                        "mask",
                        None,
                        bin(BinOp::BitAnd, int(255), bin(BinOp::BitOr, int(10), int(15))),
                    ),
                    let_(
                        "big",
                        None,
                        bin(BinOp::Pow, int(2), bin(BinOp::Pow, int(3), int(2))),
                    ),
                    let_("cast_val", None, cast(int(42), named("f64"))),
                    let_(
                        "flag",
                        None,
                        bin(
                            BinOp::Or,
                            bin(BinOp::And, bool_(true), un(UnaryOp::Not, bool_(false))),
                            bin(BinOp::Neq, int(1), int(2)),
                        ),
                    ),
                ],
                Some(int(0)),
            ),
            span: S,
        });

        let expected = Program {
            items: vec![
                item_struct,
                item_sqrt,
                item_printf,
                item_length,
                item_dot,
                item_abs,
                item_fib,
                item_main,
            ],
        };

        assert_eq!(actual, expected);
    }
}
