// Blocks, statements and patterns.

use super::recovery::is_item_start;
use super::{
    Block, Expr, ExprKind, ExprStmt, LetStmt, PResult, Parser, Pattern, PatternKind, Stmt,
};
use crate::lexer::{span::Span, token::TokenKind};

// What `parse_stmt` found: a statement, or the block's tail expression.
enum StmtOrTail {
    Stmt(Stmt),
    Tail(Expr),
}

fn expr_stmt(expr: Expr, has_semi: bool, span: Span) -> Stmt {
    Stmt::Expr(ExprStmt {
        expr,
        has_semi,
        span,
    })
}

impl Parser {
    pub(super) fn parse_block(&mut self) -> PResult<Block> {
        let start = self.span();
        self.expect(&TokenKind::LBrace)?;
        self.with_no_struct(false, |p| p.parse_block_rest(start))
    }

    // The statements of a block after its `{`, and the closing `}`.
    fn parse_block_rest(&mut self, start: Span) -> PResult<Block> {
        let mut stmts = Vec::new();
        let mut tail: Option<Box<Expr>> = None;
        loop {
            match self.current() {
                TokenKind::RBrace | TokenKind::EOF => break,
                // An empty statement.
                TokenKind::Semi => {
                    self.advance();
                    continue;
                }
                kind if is_item_start(kind) => {
                    // Most likely a missing `}`: end the block here and let
                    // the item be parsed at the top level.
                    self.errors.push(self.error(format!(
                        "expected '}}' before '{}' (items cannot be nested in blocks)",
                        self.current()
                    )));
                    return Ok(Block {
                        stmts,
                        expr: tail,
                        span: start.merge(self.prev_span()),
                    });
                }
                _ => {}
            }
            if let Some(previous_tail) = tail.take() {
                // A tail expression was followed by more statements; only
                // possible after a recovered error.
                let span = previous_tail.span;
                stmts.push(expr_stmt(*previous_tail, false, span));
            }
            match self.parse_stmt_or_recover() {
                StmtOrTail::Stmt(stmt) => stmts.push(stmt),
                StmtOrTail::Tail(expr) => tail = Some(Box::new(expr)),
            }
        }
        self.expect(&TokenKind::RBrace)?;
        Ok(Block {
            stmts,
            expr: tail,
            span: start.merge(self.prev_span()),
        })
    }

    // A statement; on a syntax error, the error is recorded, the rest of the
    // statement skipped, and an `Error` statement stands in for it.
    fn parse_stmt_or_recover(&mut self) -> StmtOrTail {
        let stmt_start = self.pos;
        match self.parse_stmt() {
            Ok(parsed) => parsed,
            Err(e) => {
                let span = e.span;
                self.errors.push(e);
                self.recover_stmt(stmt_start);
                let expr = self.make_expr(ExprKind::Error, span);
                StmtOrTail::Stmt(expr_stmt(expr, true, span))
            }
        }
    }

    // `{`, `if`, `loop`, `while`, `for`, or a label before a loop.
    fn at_block_like(&self) -> bool {
        match self.current() {
            TokenKind::LBrace
            | TokenKind::If
            | TokenKind::Loop
            | TokenKind::While
            | TokenKind::For => true,
            TokenKind::Ident(_) => self.at_label(),
            _ => false,
        }
    }

    // `name:` before `loop`, `while` or `for`.
    pub(super) fn at_label(&self) -> bool {
        matches!(self.current(), TokenKind::Ident(_))
            && *self.peek_kind(1) == TokenKind::Colon
            && matches!(
                self.peek_kind(2),
                TokenKind::Loop | TokenKind::While | TokenKind::For
            )
    }

    fn parse_stmt(&mut self) -> PResult<StmtOrTail> {
        if self.at(&TokenKind::Let) {
            return Ok(StmtOrTail::Stmt(Stmt::Let(self.parse_let_stmt()?)));
        }
        if self.at_block_like() {
            return self.parse_block_like_stmt();
        }
        let expr = self.parse_expr()?;
        match self.current() {
            TokenKind::Semi => {
                let span = expr.span.merge(self.span());
                self.advance();
                Ok(StmtOrTail::Stmt(expr_stmt(expr, true, span)))
            }
            TokenKind::RBrace => Ok(StmtOrTail::Tail(expr)),
            _ => Err(self.error(format!(
                "expected ';' or '}}' after expression, got '{}'",
                self.current()
            ))),
        }
    }

    // A statement that starts with a block-like expression ends at its
    // closing brace: it is not continued by an operator, and needs no `;`
    // (a following `;` belongs to it).
    fn parse_block_like_stmt(&mut self) -> PResult<StmtOrTail> {
        let expr = self.parse_primary()?;
        if self.at(&TokenKind::RBrace) {
            return Ok(StmtOrTail::Tail(expr));
        }
        let has_semi = self.eat(&TokenKind::Semi);
        let span = expr.span.merge(self.prev_span());
        Ok(StmtOrTail::Stmt(expr_stmt(expr, has_semi, span)))
    }

    fn parse_let_stmt(&mut self) -> PResult<LetStmt> {
        let start = self.span();
        self.expect(&TokenKind::Let)?;
        let pattern = self.parse_pattern()?;
        let ty = if self.eat(&TokenKind::Colon) {
            Some(self.parse_type()?)
        } else {
            None
        };
        if self.at(&TokenKind::Semi) {
            return Err(self
                .error("'let' without an initializer is not supported; give the binding a value"));
        }
        self.expect(&TokenKind::Eq)?;
        let init = self.parse_expr()?;
        self.expect(&TokenKind::Semi)?;
        Ok(LetStmt {
            pattern,
            ty,
            init,
            span: start.merge(self.prev_span()),
        })
    }

    // `_`, `x`, `mut x`, `(p, ...)`
    pub(super) fn parse_pattern(&mut self) -> PResult<Pattern> {
        let start = self.span();
        let kind = match self.current() {
            TokenKind::Ident(name) if name == "_" => {
                self.advance();
                PatternKind::Wildcard
            }
            TokenKind::Mut => {
                self.advance();
                let (name, _) = self.expect_binding_name()?;
                PatternKind::Binding {
                    name,
                    mutable: true,
                }
            }
            TokenKind::Ident(_) => {
                let (name, _) = self.expect_ident()?;
                PatternKind::Binding {
                    name,
                    mutable: false,
                }
            }
            TokenKind::LParen => return self.parse_tuple_pattern(start),
            TokenKind::Reserved(_) => return Err(self.reserved_error()),
            _ => {
                return Err(self.error(format!("expected a pattern, got '{}'", self.current())));
            }
        };
        Ok(Pattern {
            kind,
            span: start.merge(self.prev_span()),
        })
    }

    // `(p, ...)`; `(p)` is just a parenthesized `p`.
    fn parse_tuple_pattern(&mut self, start: Span) -> PResult<Pattern> {
        self.expect(&TokenKind::LParen)?;
        let mut elems = Vec::new();
        let mut trailing_comma = false;
        while !self.at(&TokenKind::RParen) && !self.is_at_eof() {
            elems.push(self.parse_pattern()?);
            trailing_comma = self.eat(&TokenKind::Comma);
            if !trailing_comma {
                break;
            }
        }
        self.expect(&TokenKind::RParen)?;
        if elems.len() == 1 && !trailing_comma {
            return Ok(elems.pop().expect("one element"));
        }
        Ok(Pattern {
            kind: PatternKind::Tuple(elems),
            span: start.merge(self.prev_span()),
        })
    }
}
