// Expressions: a Pratt parser driven by the binding powers in `infix_op`
// (see the precedence table in docs/grammar.md).

use super::{
    AssignOp, BinOp, Block, Expr, ExprKind, FieldInit, LitValue, PResult, Parser, ParserError,
    Spanned, UnaryOp,
};
use crate::lexer::{span::Span, token::TokenKind};

// Binding powers (higher binds tighter) of the operators outside the infix
// table.
const AS_BP: u8 = 24;
const PREFIX_BP: u8 = 25;
const POSTFIX_BP: u8 = 27;

#[derive(Clone, Copy)]
enum Infix {
    Bin(BinOp),
    Assign(AssignOp),
    Range { inclusive: bool },
}

// Non-associative operator levels: `a < b < c` is an error.
#[derive(Clone, Copy, PartialEq)]
enum NonAssoc {
    Comparison,
    Range,
}

impl Infix {
    fn non_assoc(self) -> Option<NonAssoc> {
        match self {
            Infix::Bin(op) if op.is_comparison() => Some(NonAssoc::Comparison),
            Infix::Range { .. } => Some(NonAssoc::Range),
            _ => None,
        }
    }
}

// (operator, left binding power, right binding power)
fn infix_op(kind: &TokenKind) -> Option<(Infix, u8, u8)> {
    use TokenKind as T;
    let assign = |op| Some((Infix::Assign(op), 2, 1));
    let bin = |op, left, right| Some((Infix::Bin(op), left, right));
    match kind {
        T::Eq => assign(AssignOp::Assign),
        T::PlusEq => assign(AssignOp::AddAssign),
        T::MinusEq => assign(AssignOp::SubAssign),
        T::StarEq => assign(AssignOp::MulAssign),
        T::SlashEq => assign(AssignOp::DivAssign),
        T::PercentEq => assign(AssignOp::ModAssign),
        T::AmpEq => assign(AssignOp::BitAndAssign),
        T::PipeEq => assign(AssignOp::BitOrAssign),
        T::CaretEq => assign(AssignOp::BitXorAssign),
        T::ShlEq => assign(AssignOp::ShlAssign),
        T::ShrEq => assign(AssignOp::ShrAssign),
        T::DotDot => Some((Infix::Range { inclusive: false }, 4, 5)),
        T::DotDotEq => Some((Infix::Range { inclusive: true }, 4, 5)),
        T::PipePipe => bin(BinOp::Or, 6, 7),
        T::AmpAmp => bin(BinOp::And, 8, 9),
        T::EqEq => bin(BinOp::Eq, 10, 11),
        T::BangEq => bin(BinOp::Neq, 10, 11),
        T::Lt => bin(BinOp::Lt, 10, 11),
        T::Gt => bin(BinOp::Gt, 10, 11),
        T::LtEq => bin(BinOp::LtEq, 10, 11),
        T::GtEq => bin(BinOp::GtEq, 10, 11),
        T::Pipe => bin(BinOp::BitOr, 12, 13),
        T::Caret => bin(BinOp::BitXor, 14, 15),
        T::Amp => bin(BinOp::BitAnd, 16, 17),
        T::Shl => bin(BinOp::Shl, 18, 19),
        T::Shr => bin(BinOp::Shr, 18, 19),
        T::Plus => bin(BinOp::Add, 20, 21),
        T::Minus => bin(BinOp::Sub, 20, 21),
        T::Star => bin(BinOp::Mul, 22, 23),
        T::Slash => bin(BinOp::Div, 22, 23),
        T::Percent => bin(BinOp::Mod, 22, 23),
        _ => None,
    }
}

// Tokens that are reserved for future syntax.
fn is_reserved_punct(kind: &TokenKind) -> bool {
    matches!(
        kind,
        TokenKind::ColonColon
            | TokenKind::FatArrow
            | TokenKind::Hash
            | TokenKind::Question
            | TokenKind::At
    )
}

// Whether `kind` can begin an expression (an operand of `return` or
// `break`).
fn starts_expr(kind: &TokenKind) -> bool {
    matches!(
        kind,
        TokenKind::IntLiteral(_)
            | TokenKind::FloatLiteral(_)
            | TokenKind::SuffixedInt(..)
            | TokenKind::SuffixedFloat(..)
            | TokenKind::CharLiteral(_)
            | TokenKind::StringLiteral(_)
            | TokenKind::CStringLiteral(_)
            | TokenKind::Ident(_)
            | TokenKind::True
            | TokenKind::False
            | TokenKind::LParen
            | TokenKind::LBracket
            | TokenKind::LBrace
            | TokenKind::Minus
            | TokenKind::Bang
            | TokenKind::Tilde
            | TokenKind::Star
            | TokenKind::Amp
            | TokenKind::AmpAmp
            | TokenKind::If
            | TokenKind::Loop
            | TokenKind::While
            | TokenKind::For
            | TokenKind::Return
            | TokenKind::Break
            | TokenKind::Continue
    )
}

fn infix_expr_kind(op: Infix, lhs: Expr, rhs: Expr) -> ExprKind {
    let (lhs, rhs) = (Box::new(lhs), Box::new(rhs));
    match op {
        Infix::Bin(op) => ExprKind::BinOp { op, lhs, rhs },
        Infix::Assign(op) => ExprKind::Assign {
            op,
            target: lhs,
            value: rhs,
        },
        Infix::Range { inclusive } => ExprKind::Range {
            start: lhs,
            end: rhs,
            inclusive,
        },
    }
}

impl Parser {
    pub(super) fn parse_expr(&mut self) -> PResult<Expr> {
        self.parse_expr_bp(0)
    }

    fn parse_expr_no_struct(&mut self) -> PResult<Expr> {
        self.with_no_struct(true, |p| p.parse_expr_bp(0))
    }

    // An expression whose operators all bind at least as tightly as
    // `min_bp`.
    fn parse_expr_bp(&mut self, min_bp: u8) -> PResult<Expr> {
        let mut lhs = self.parse_prefix()?;
        // The non-associative level of the operator that built `lhs`.
        let mut built_by: Option<NonAssoc> = None;
        loop {
            match self.current() {
                TokenKind::LParen | TokenKind::LBracket | TokenKind::Dot
                    if POSTFIX_BP >= min_bp =>
                {
                    lhs = self.parse_postfix(lhs)?;
                    built_by = None;
                    continue;
                }
                TokenKind::As if AS_BP >= min_bp => {
                    lhs = self.parse_cast(lhs)?;
                    built_by = None;
                    continue;
                }
                kind if is_reserved_punct(kind) => return Err(self.reserved_error()),
                _ => {}
            }
            let Some((op, left_bp, right_bp)) = infix_op(self.current()) else {
                break;
            };
            if left_bp < min_bp {
                break;
            }
            if let Some(level) = op.non_assoc()
                && built_by == Some(level)
            {
                return Err(self.chained_operator_error(level));
            }
            self.advance();
            let rhs = self.parse_expr_bp(right_bp)?;
            let span = lhs.span.merge(rhs.span);
            lhs = self.make_expr(infix_expr_kind(op, lhs, rhs), span);
            built_by = op.non_assoc();
        }
        Ok(lhs)
    }

    fn chained_operator_error(&self, level: NonAssoc) -> ParserError {
        self.error(match level {
            NonAssoc::Comparison => "comparison operators cannot be chained; use parentheses",
            NonAssoc::Range => "range operators cannot be chained; use parentheses",
        })
    }

    // `expr as T`
    fn parse_cast(&mut self, expr: Expr) -> PResult<Expr> {
        self.expect(&TokenKind::As)?;
        let ty = self.parse_type()?;
        let span = expr.span.merge(ty.span);
        Ok(self.make_expr(
            ExprKind::Cast {
                expr: Box::new(expr),
                ty,
            },
            span,
        ))
    }

    // ---- Prefix operators and jumps ----

    fn parse_prefix(&mut self) -> PResult<Expr> {
        let op = match self.current() {
            TokenKind::Minus => UnaryOp::Neg,
            TokenKind::Bang => UnaryOp::Not,
            TokenKind::Tilde => UnaryOp::BitNot,
            TokenKind::Star => UnaryOp::Deref,
            TokenKind::Amp => UnaryOp::AddrOf,
            TokenKind::AmpAmp => return self.parse_double_addr_of(),
            TokenKind::Plus => return Err(self.error("unary '+' is not supported")),
            TokenKind::Return => return self.parse_return(),
            TokenKind::Break => return self.parse_break(),
            TokenKind::Continue => return self.parse_continue(),
            TokenKind::DotDot | TokenKind::DotDotEq => {
                return Err(self.error("a range needs a start: write 'a..b'"));
            }
            _ => return self.parse_primary(),
        };
        let start = self.span();
        self.advance();
        let operand = self.parse_expr_bp(PREFIX_BP)?;
        Ok(self.make_unary(op, operand, start))
    }

    fn make_unary(&mut self, op: UnaryOp, operand: Expr, op_span: Span) -> Expr {
        let span = op_span.merge(operand.span);
        self.make_expr(
            ExprKind::UnaryOp {
                op,
                expr: Box::new(operand),
            },
            span,
        )
    }

    // `&&x` is `& &x`.
    fn parse_double_addr_of(&mut self) -> PResult<Expr> {
        let first = self.split_token(TokenKind::Amp, TokenKind::Amp);
        let operand = self.parse_expr_bp(PREFIX_BP)?;
        Ok(self.make_unary(UnaryOp::AddrOf, operand, first))
    }

    fn parse_return(&mut self) -> PResult<Expr> {
        let start = self.expect(&TokenKind::Return)?;
        let value = self.parse_jump_value()?;
        let span = start.merge(self.prev_span());
        Ok(self.make_expr(ExprKind::Return(value), span))
    }

    fn parse_break(&mut self) -> PResult<Expr> {
        let start = self.expect(&TokenKind::Break)?;
        let label = self.parse_jump_label()?;
        let value = self.parse_jump_value()?;
        let span = start.merge(self.prev_span());
        Ok(self.make_expr(ExprKind::Break { label, value }, span))
    }

    fn parse_continue(&mut self) -> PResult<Expr> {
        let start = self.expect(&TokenKind::Continue)?;
        let label = self.parse_jump_label()?;
        let span = start.merge(self.prev_span());
        Ok(self.make_expr(ExprKind::Continue { label }, span))
    }

    // The optional operand of `return` or `break`.
    fn parse_jump_value(&mut self) -> PResult<Option<Box<Expr>>> {
        if starts_expr(self.current()) {
            Ok(Some(Box::new(self.parse_expr_bp(0)?)))
        } else {
            Ok(None)
        }
    }

    // `:label` after `break`/`continue`.
    fn parse_jump_label(&mut self) -> PResult<Option<Spanned<String>>> {
        if self.at(&TokenKind::Colon) && matches!(self.peek_kind(1), TokenKind::Ident(_)) {
            self.advance();
            Ok(Some(self.expect_ident()?))
        } else {
            Ok(None)
        }
    }

    // ---- Postfix operators ----

    fn parse_postfix(&mut self, lhs: Expr) -> PResult<Expr> {
        match self.current() {
            TokenKind::LParen => self.parse_call(lhs),
            TokenKind::LBracket => self.parse_index(lhs),
            _ => self.parse_field_access(lhs),
        }
    }

    fn parse_call(&mut self, callee: Expr) -> PResult<Expr> {
        self.expect(&TokenKind::LParen)?;
        let args = self.with_no_struct(false, |p| p.parse_comma_list(&TokenKind::RParen))?;
        self.expect(&TokenKind::RParen)?;
        let span = callee.span.merge(self.prev_span());
        Ok(self.make_expr(
            ExprKind::Call {
                callee: Box::new(callee),
                args,
            },
            span,
        ))
    }

    fn parse_index(&mut self, base: Expr) -> PResult<Expr> {
        self.expect(&TokenKind::LBracket)?;
        let index = self.with_no_struct(false, |p| p.parse_expr())?;
        self.expect(&TokenKind::RBracket)?;
        let span = base.span.merge(self.prev_span());
        Ok(self.make_expr(
            ExprKind::Index {
                expr: Box::new(base),
                index: Box::new(index),
            },
            span,
        ))
    }

    // `.name` or `.0`
    fn parse_field_access(&mut self, base: Expr) -> PResult<Expr> {
        self.expect(&TokenKind::Dot)?;
        match *self.current() {
            TokenKind::Ident(_) => {
                if *self.peek_kind(1) == TokenKind::LParen {
                    return Err(self.error(
                        "methods are not supported yet; to call a function stored in a field, write (s.f)(x)",
                    ));
                }
                let name = self.expect_ident()?;
                let span = base.span.merge(name.1);
                Ok(self.make_expr(
                    ExprKind::Field {
                        expr: Box::new(base),
                        name,
                    },
                    span,
                ))
            }
            TokenKind::IntLiteral(index) => {
                let index_span = self.span();
                self.advance();
                let span = base.span.merge(index_span);
                Ok(self.make_expr(
                    ExprKind::TupleField {
                        expr: Box::new(base),
                        index: (index, index_span),
                    },
                    span,
                ))
            }
            _ => Err(self.error(format!(
                "expected field name or index after '.', got '{}'",
                self.current()
            ))),
        }
    }

    // `e, e, ...` up to (not including) `close`; a trailing comma is allowed.
    fn parse_comma_list(&mut self, close: &TokenKind) -> PResult<Vec<Expr>> {
        self.parse_comma_separated(close, Self::parse_expr)
    }

    // ---- Primary expressions ----

    pub(super) fn parse_primary(&mut self) -> PResult<Expr> {
        if let Some(kind) = self.take_literal() {
            let span = self.span();
            self.advance();
            return Ok(self.make_expr(kind, span));
        }
        let start = self.span();
        match self.current() {
            TokenKind::LParen => self.with_no_struct(false, |p| p.parse_paren_expr()),
            TokenKind::LBracket => self.with_no_struct(false, |p| p.parse_array_literal()),
            TokenKind::LBrace => {
                let block = self.parse_block()?;
                let span = block.span;
                Ok(self.make_expr(ExprKind::Block(block), span))
            }
            TokenKind::If => self.parse_if(),
            TokenKind::Loop | TokenKind::While | TokenKind::For => self.parse_loop(None, start),
            TokenKind::Ident(_) if self.at_label() => {
                let label = self.expect_ident()?;
                self.expect(&TokenKind::Colon)?;
                self.parse_loop(Some(label), start)
            }
            TokenKind::Ident(name) if name == "_" => {
                Err(self.error("'_' can only be used in patterns"))
            }
            TokenKind::Ident(_) => self.parse_name_or_struct_literal(),
            kind if is_reserved_punct(kind) || matches!(kind, TokenKind::Reserved(_)) => {
                Err(self.reserved_error())
            }
            _ => Err(self.error(format!("expected expression, got '{}'", self.current()))),
        }
    }

    // The expression of a literal token, taking strings out of the token
    // (the parser never looks back). The token is not consumed.
    fn take_literal(&mut self) -> Option<ExprKind> {
        Some(match &mut self.tokens[self.pos].kind {
            TokenKind::IntLiteral(v) => ExprKind::IntLiteral(*v),
            TokenKind::FloatLiteral(v) => ExprKind::FloatLiteral(*v),
            TokenKind::SuffixedInt(v, suffix) => {
                ExprKind::SuffixedLiteral(LitValue::Int(*v), *suffix)
            }
            TokenKind::SuffixedFloat(v, suffix) => {
                ExprKind::SuffixedLiteral(LitValue::Float(*v), *suffix)
            }
            TokenKind::CharLiteral(v) => ExprKind::CharLiteral(*v),
            TokenKind::StringLiteral(s) => ExprKind::StringLiteral(std::mem::take(s)),
            TokenKind::CStringLiteral(s) => ExprKind::CStringLiteral(std::mem::take(s)),
            TokenKind::True => ExprKind::BoolLiteral(true),
            TokenKind::False => ExprKind::BoolLiteral(false),
            _ => return None,
        })
    }

    // `name`, or `Name { field: value, ... }` where struct literals are
    // allowed.
    fn parse_name_or_struct_literal(&mut self) -> PResult<Expr> {
        let (name, name_span) = self.expect_ident()?;
        if !self.no_struct && self.at(&TokenKind::LBrace) {
            self.parse_struct_literal_rest(name, name_span)
        } else {
            Ok(self.make_expr(ExprKind::Ident(name), name_span))
        }
    }

    // `()`, `(e)`, `(e,)` or `(e, e, ...)`
    fn parse_paren_expr(&mut self) -> PResult<Expr> {
        let start = self.span();
        self.expect(&TokenKind::LParen)?;
        if self.eat(&TokenKind::RParen) {
            return Ok(self.make_expr(ExprKind::UnitLiteral, start.merge(self.prev_span())));
        }
        let first = self.parse_expr()?;
        if self.eat(&TokenKind::Comma) {
            let mut elems = vec![first];
            elems.extend(self.parse_comma_list(&TokenKind::RParen)?);
            self.expect(&TokenKind::RParen)?;
            let span = start.merge(self.prev_span());
            return Ok(self.make_expr(ExprKind::Tuple(elems), span));
        }
        self.expect(&TokenKind::RParen)?;
        let span = start.merge(self.prev_span());
        Ok(Expr { span, ..first })
    }

    // `[]`, `[e; n]` or `[e, e, ...]`; the type of `[]` comes from context.
    fn parse_array_literal(&mut self) -> PResult<Expr> {
        let start = self.span();
        self.expect(&TokenKind::LBracket)?;
        if self.eat(&TokenKind::RBracket) {
            let span = start.merge(self.prev_span());
            return Ok(self.make_expr(ExprKind::Array(Vec::new()), span));
        }
        let first = self.parse_expr()?;
        if self.eat(&TokenKind::Semi) {
            let count = self.parse_expr()?;
            self.expect(&TokenKind::RBracket)?;
            let span = start.merge(self.prev_span());
            return Ok(self.make_expr(
                ExprKind::ArrayRepeat(Box::new(first), Box::new(count)),
                span,
            ));
        }
        let mut elems = vec![first];
        if self.eat(&TokenKind::Comma) {
            elems.extend(self.parse_comma_list(&TokenKind::RBracket)?);
        }
        self.expect(&TokenKind::RBracket)?;
        let span = start.merge(self.prev_span());
        Ok(self.make_expr(ExprKind::Array(elems), span))
    }

    // `{ field: value, ... }` after the struct's name.
    fn parse_struct_literal_rest(&mut self, name: String, name_span: Span) -> PResult<Expr> {
        self.expect(&TokenKind::LBrace)?;
        let fields = self.with_no_struct(false, |p| {
            p.parse_comma_separated(&TokenKind::RBrace, Self::parse_field_init)
        })?;
        self.expect(&TokenKind::RBrace)?;
        let span = name_span.merge(self.prev_span());
        Ok(self.make_expr(
            ExprKind::StructConstructor {
                name: (name, name_span),
                fields,
            },
            span,
        ))
    }

    // `field: value`
    fn parse_field_init(&mut self) -> PResult<FieldInit> {
        let start = self.span();
        let name = self.expect_binding_name()?;
        self.expect(&TokenKind::Colon)?;
        let value = self.parse_expr()?;
        Ok(FieldInit {
            name,
            value,
            span: start.merge(self.prev_span()),
        })
    }

    // ---- Control flow ----

    fn parse_if(&mut self) -> PResult<Expr> {
        let start = self.span();
        self.expect(&TokenKind::If)?;
        let cond = self.parse_expr_no_struct()?;
        let then_block = self.parse_block()?;
        let else_block = if self.eat(&TokenKind::Else) {
            Some(self.parse_else_block()?)
        } else {
            None
        };
        let span = start.merge(self.prev_span());
        Ok(self.make_expr(
            ExprKind::If {
                cond: Box::new(cond),
                then_block,
                else_block,
            },
            span,
        ))
    }

    // The block after `else`; `else if` is an else block holding just the
    // inner `if`.
    fn parse_else_block(&mut self) -> PResult<Block> {
        if !self.at(&TokenKind::If) {
            return self.parse_block();
        }
        let inner = self.parse_if()?;
        let span = inner.span;
        Ok(Block {
            stmts: Vec::new(),
            expr: Some(Box::new(inner)),
            span,
        })
    }

    // `loop`, `while` or `for`, after an optional label.
    fn parse_loop(&mut self, label: Option<Spanned<String>>, start: Span) -> PResult<Expr> {
        let kind = match self.current() {
            TokenKind::Loop => {
                self.advance();
                let body = self.parse_block()?;
                ExprKind::Loop { label, body }
            }
            TokenKind::While => {
                self.advance();
                let cond = self.parse_expr_no_struct()?;
                let body = self.parse_block()?;
                ExprKind::While {
                    label,
                    cond: Box::new(cond),
                    body,
                }
            }
            _ => {
                self.expect(&TokenKind::For)?;
                let pattern = self.parse_pattern()?;
                self.expect(&TokenKind::In)?;
                let iter = self.parse_expr_no_struct()?;
                let body = self.parse_block()?;
                ExprKind::For {
                    label,
                    pattern,
                    iter: Box::new(iter),
                    body,
                }
            }
        };
        let span = start.merge(self.prev_span());
        Ok(self.make_expr(kind, span))
    }
}
