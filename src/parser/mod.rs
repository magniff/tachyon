// Parser: recursive descent for items and statements, a Pratt (binding
// power) parser for expressions. The grammar is documented in
// docs/grammar.md.
//
// Errors do not stop the parse: a failed statement or item is reported,
// replaced by an `Error` node, and the parser resynchronizes at the next
// `;`, `}` or item/statement keyword, so one run reports every independent
// syntax error.

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

type PResult<T> = Result<T, ParserError>;

// Binding powers (higher binds tighter); see the table in docs/grammar.md.
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
    let bin = |op, l, r| Some((Infix::Bin(op), l, r));
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

fn is_item_start(kind: &TokenKind) -> bool {
    matches!(
        kind,
        TokenKind::Fn
            | TokenKind::Extern
            | TokenKind::Struct
            | TokenKind::Const
            | TokenKind::Static
            | TokenKind::Type
    )
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

enum StmtOrTail {
    Stmt(Stmt),
    Tail(Expr),
}

pub struct Parser {
    tokens: Vec<Token>,
    pos: usize,
    // In `if`/`while` conditions and `for` iterables, `Name {` starts the
    // body, not a struct literal. Cleared inside (), [], {} and arguments.
    no_struct: bool,
    next_expr_id: u32,
    errors: Vec<ParserError>,
}

impl Parser {
    pub fn new(tokens: Vec<Token>) -> Self {
        Self {
            tokens,
            pos: 0,
            no_struct: false,
            next_expr_id: 0,
            errors: Vec::new(),
        }
    }

    // ---- Token access ----

    fn current(&self) -> &TokenKind {
        &self.tokens[self.pos].kind
    }

    fn peek_kind(&self, offset: usize) -> &TokenKind {
        let i = (self.pos + offset).min(self.tokens.len() - 1);
        &self.tokens[i].kind
    }

    fn span(&self) -> Span {
        self.tokens[self.pos].span
    }

    fn prev_span(&self) -> Span {
        if self.pos > 0 {
            self.tokens[self.pos - 1].span
        } else {
            Span::new(0, 0)
        }
    }

    fn is_at_eof(&self) -> bool {
        matches!(self.current(), TokenKind::EOF)
    }

    fn at(&self, kind: &TokenKind) -> bool {
        self.current() == kind
    }

    fn advance(&mut self) {
        if !self.is_at_eof() {
            self.pos += 1;
        }
    }

    fn eat(&mut self, kind: &TokenKind) -> bool {
        if self.at(kind) {
            self.advance();
            true
        } else {
            false
        }
    }

    fn expect(&mut self, kind: &TokenKind) -> PResult<Span> {
        if self.at(kind) {
            let s = self.span();
            self.advance();
            Ok(s)
        } else {
            Err(self.error(format!("expected '{}', got '{}'", kind, self.current())))
        }
    }

    // Splits the current joint token (e.g. `&&`) and consumes its first part
    // (`&`), leaving the rest as the current token.
    fn split_token(&mut self, first: TokenKind, rest: TokenKind) -> Span {
        let len = first.to_string().len();
        let token = &mut self.tokens[self.pos];
        let first_span = Span::new(token.span.start, token.span.start + len);
        token.kind = rest;
        token.span = Span::new(token.span.start + len, token.span.end);
        first_span
    }

    fn reserved_error(&self) -> ParserError {
        match self.current() {
            TokenKind::Reserved(kw) => self.error(format!(
                "'{}' is a reserved keyword (reserved for future use)",
                kw
            )),
            other => self.error(format!("'{}' is reserved for future use", other)),
        }
    }

    // An identifier, taken out of the token (the parser never looks back).
    fn expect_ident(&mut self) -> PResult<Spanned<String>> {
        let span = self.span();
        match &mut self.tokens[self.pos].kind {
            TokenKind::Ident(name) => {
                let name = std::mem::take(name);
                self.advance();
                Ok((name, span))
            }
            TokenKind::Reserved(_) => Err(self.reserved_error()),
            _ => Err(self.error(format!("expected identifier, got '{}'", self.current()))),
        }
    }

    // A name that can be bound: an identifier other than `_`.
    fn expect_binding_name(&mut self) -> PResult<Spanned<String>> {
        if matches!(self.current(), TokenKind::Ident(n) if n == "_") {
            return Err(self.error("expected a name, got '_'"));
        }
        self.expect_ident()
    }

    fn error(&self, msg: impl Into<String>) -> ParserError {
        ParserError {
            message: msg.into(),
            span: self.span(),
        }
    }

    fn mk_expr(&mut self, kind: ExprKind, span: Span) -> Expr {
        let id = ExprId(self.next_expr_id);
        self.next_expr_id += 1;
        Expr { id, kind, span }
    }

    // Runs `f` with the struct-literal restriction set to `no_struct`.
    fn with_no_struct<T>(&mut self, no_struct: bool, f: impl FnOnce(&mut Self) -> T) -> T {
        let saved = std::mem::replace(&mut self.no_struct, no_struct);
        let result = f(self);
        self.no_struct = saved;
        result
    }

    // ---- Error recovery ----

    // Skips the rest of a broken statement: up to and including the next
    // `;`, or up to the `}` that closes the enclosing block, or a keyword
    // that starts the next statement or item. Braces are skipped as units.
    fn recover_stmt(&mut self, start: usize) {
        let mut depth = 0usize;
        loop {
            match self.current() {
                TokenKind::EOF => break,
                TokenKind::LBrace => depth += 1,
                TokenKind::RBrace if depth == 0 => break,
                TokenKind::RBrace => depth -= 1,
                TokenKind::Semi if depth == 0 => {
                    self.advance();
                    break;
                }
                k if depth == 0
                    && self.pos != start
                    && (*k == TokenKind::Let || is_item_start(k)) =>
                {
                    break;
                }
                _ => {}
            }
            self.advance();
        }
        if self.pos == start && !matches!(self.current(), TokenKind::RBrace | TokenKind::EOF) {
            self.advance();
        }
    }

    // Skips to the next item keyword at the top level.
    fn recover_item(&mut self, start: usize) {
        let mut depth = 0usize;
        loop {
            match self.current() {
                TokenKind::EOF => break,
                TokenKind::LBrace => depth += 1,
                TokenKind::RBrace => depth = depth.saturating_sub(1),
                k if depth == 0 && self.pos != start && is_item_start(k) => break,
                _ => {}
            }
            self.advance();
        }
    }

    // ---- Items ----

    pub fn parse_program(&mut self) -> Program {
        let mut items = Vec::new();
        while !self.is_at_eof() {
            let start = self.pos;
            match self.parse_item() {
                Ok(item) => items.push(item),
                Err(e) => {
                    self.errors.push(e);
                    self.recover_item(start);
                }
            }
        }
        Program {
            items,
            expr_count: self.next_expr_id,
        }
    }

    fn parse_item(&mut self) -> PResult<Item> {
        match self.current() {
            TokenKind::Fn => Ok(Item::Function(self.parse_function_decl()?)),
            TokenKind::Extern => Ok(Item::Extern(self.parse_extern_decl()?)),
            TokenKind::Struct => Ok(Item::Struct(self.parse_struct_decl()?)),
            TokenKind::Const => Ok(Item::Const(self.parse_const_decl()?)),
            TokenKind::Static => Ok(Item::Static(self.parse_static_decl()?)),
            TokenKind::Type => Ok(Item::TypeAlias(self.parse_type_alias()?)),
            TokenKind::Reserved(_) | TokenKind::Hash => Err(self.reserved_error()),
            _ => Err(self.error(format!(
                "expected an item ('fn', 'extern', 'struct', 'const', 'static' or 'type'), got '{}'",
                self.current()
            ))),
        }
    }

    fn parse_struct_decl(&mut self) -> PResult<StructDecl> {
        let start = self.span();
        self.expect(&TokenKind::Struct)?;
        let name = self.expect_binding_name()?;
        self.expect(&TokenKind::LBrace)?;
        let mut fields = Vec::new();
        while !self.at(&TokenKind::RBrace) && !self.is_at_eof() {
            let fs = self.span();
            let fname = self.expect_binding_name()?;
            self.expect(&TokenKind::Colon)?;
            let ty = self.parse_type()?;
            fields.push(StructField {
                name: fname,
                ty,
                span: fs.merge(self.prev_span()),
            });
            if !self.eat(&TokenKind::Comma) {
                break;
            }
        }
        self.expect(&TokenKind::RBrace)?;
        Ok(StructDecl {
            name,
            fields,
            span: start.merge(self.prev_span()),
        })
    }

    fn parse_return_type(&mut self) -> PResult<Option<Type>> {
        if self.eat(&TokenKind::Arrow) {
            Ok(Some(self.parse_type()?))
        } else {
            Ok(None)
        }
    }

    fn parse_function_decl(&mut self) -> PResult<FunctionDecl> {
        let start = self.span();
        self.expect(&TokenKind::Fn)?;
        let name = self.expect_binding_name()?;
        self.expect(&TokenKind::LParen)?;
        let (params, _) = self.parse_params(false)?;
        self.expect(&TokenKind::RParen)?;
        let return_type = self.parse_return_type()?;
        let body = self.parse_block()?;
        Ok(FunctionDecl {
            name,
            params,
            return_type,
            body,
            span: start.merge(self.prev_span()),
        })
    }

    fn parse_extern_decl(&mut self) -> PResult<ExternDecl> {
        let start = self.span();
        self.expect(&TokenKind::Extern)?;
        if let TokenKind::StringLiteral(abi) = self.current() {
            if abi.as_slice() != b"C" {
                return Err(self.error(format!(
                    "unsupported ABI {}; only \"C\" is supported",
                    self.current()
                )));
            }
            self.advance();
        }
        if self.at(&TokenKind::Static) {
            return Err(self.error("extern statics are not supported yet"));
        }
        self.expect(&TokenKind::Fn)?;
        let name = self.expect_binding_name()?;
        self.expect(&TokenKind::LParen)?;
        let (params, is_variadic) = self.parse_params(true)?;
        self.expect(&TokenKind::RParen)?;
        let return_type = self.parse_return_type()?;
        self.expect(&TokenKind::Semi)?;
        Ok(ExternDecl {
            name,
            params,
            is_variadic,
            return_type,
            span: start.merge(self.prev_span()),
        })
    }

    // `[mut] name: T, ...` and, for externs, a final `...`.
    fn parse_params(&mut self, allow_ellipsis: bool) -> PResult<(Vec<Parameter>, bool)> {
        let mut params = Vec::new();
        let mut is_variadic = false;
        while !self.at(&TokenKind::RParen) && !self.is_at_eof() {
            if self.at(&TokenKind::Ellipsis) {
                if !allow_ellipsis {
                    return Err(self.error("only extern functions can be variadic"));
                }
                self.advance();
                is_variadic = true;
                self.eat(&TokenKind::Comma);
                break;
            }
            let ps = self.span();
            let mutable = self.eat(&TokenKind::Mut);
            let name = if mutable {
                self.expect_binding_name()?
            } else {
                self.expect_ident()?
            };
            self.expect(&TokenKind::Colon)?;
            let ty = self.parse_type()?;
            params.push(Parameter {
                name,
                mutable,
                ty,
                span: ps.merge(self.prev_span()),
            });
            if !self.eat(&TokenKind::Comma) {
                break;
            }
        }
        Ok((params, is_variadic))
    }

    fn parse_const_decl(&mut self) -> PResult<ConstDecl> {
        let start = self.span();
        self.expect(&TokenKind::Const)?;
        let name = self.expect_binding_name()?;
        self.expect(&TokenKind::Colon)?;
        let ty = self.parse_type()?;
        self.expect(&TokenKind::Eq)?;
        let value = self.parse_expr()?;
        self.expect(&TokenKind::Semi)?;
        Ok(ConstDecl {
            name,
            ty,
            value,
            span: start.merge(self.prev_span()),
        })
    }

    fn parse_static_decl(&mut self) -> PResult<StaticDecl> {
        let start = self.span();
        self.expect(&TokenKind::Static)?;
        let mutable = self.eat(&TokenKind::Mut);
        let name = self.expect_binding_name()?;
        self.expect(&TokenKind::Colon)?;
        let ty = self.parse_type()?;
        self.expect(&TokenKind::Eq)?;
        let value = self.parse_expr()?;
        self.expect(&TokenKind::Semi)?;
        Ok(StaticDecl {
            name,
            mutable,
            ty,
            value,
            span: start.merge(self.prev_span()),
        })
    }

    fn parse_type_alias(&mut self) -> PResult<TypeAliasDecl> {
        let start = self.span();
        self.expect(&TokenKind::Type)?;
        let name = self.expect_binding_name()?;
        if self.at(&TokenKind::Lt) {
            return Err(self.error("generic type aliases are not supported yet"));
        }
        self.expect(&TokenKind::Eq)?;
        let ty = self.parse_type()?;
        self.expect(&TokenKind::Semi)?;
        Ok(TypeAliasDecl {
            name,
            ty,
            span: start.merge(self.prev_span()),
        })
    }

    // ---- Blocks and statements ----

    fn parse_block(&mut self) -> PResult<Block> {
        let start = self.span();
        self.expect(&TokenKind::LBrace)?;
        self.with_no_struct(false, |p| p.parse_block_rest(start))
    }

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
                k if is_item_start(k) => {
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
            if let Some(t) = tail.take() {
                // A tail expression was followed by more statements; only
                // possible after a recovered error.
                let span = t.span;
                stmts.push(Stmt::Expr(ExprStmt {
                    expr: *t,
                    has_semi: false,
                    span,
                }));
            }
            let stmt_start = self.pos;
            match self.parse_stmt() {
                Ok(StmtOrTail::Stmt(s)) => stmts.push(s),
                Ok(StmtOrTail::Tail(e)) => tail = Some(Box::new(e)),
                Err(e) => {
                    let span = e.span;
                    self.errors.push(e);
                    self.recover_stmt(stmt_start);
                    let expr = self.mk_expr(ExprKind::Error, span);
                    stmts.push(Stmt::Expr(ExprStmt {
                        expr,
                        has_semi: true,
                        span,
                    }));
                }
            }
        }
        self.expect(&TokenKind::RBrace)?;
        Ok(Block {
            stmts,
            expr: tail,
            span: start.merge(self.prev_span()),
        })
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
    fn at_label(&self) -> bool {
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
        // A statement that starts with a block-like expression ends at its
        // closing brace: it is not continued by an operator, and needs no
        // `;` (a following `;` belongs to it).
        if self.at_block_like() {
            let expr = self.parse_primary()?;
            if self.at(&TokenKind::RBrace) {
                return Ok(StmtOrTail::Tail(expr));
            }
            let has_semi = self.eat(&TokenKind::Semi);
            let span = expr.span.merge(self.prev_span());
            return Ok(StmtOrTail::Stmt(Stmt::Expr(ExprStmt {
                expr,
                has_semi,
                span,
            })));
        }
        let expr = self.parse_expr()?;
        match self.current() {
            TokenKind::Semi => {
                let span = expr.span.merge(self.span());
                self.advance();
                Ok(StmtOrTail::Stmt(Stmt::Expr(ExprStmt {
                    expr,
                    has_semi: true,
                    span,
                })))
            }
            TokenKind::RBrace => Ok(StmtOrTail::Tail(expr)),
            _ => Err(self.error(format!(
                "expected ';' or '}}' after expression, got '{}'",
                self.current()
            ))),
        }
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
    fn parse_pattern(&mut self) -> PResult<Pattern> {
        let start = self.span();
        let kind = match self.current() {
            TokenKind::Ident(n) if n == "_" => {
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
            TokenKind::LParen => {
                self.advance();
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
                    // A parenthesized pattern.
                    return Ok(elems.pop().unwrap());
                }
                PatternKind::Tuple(elems)
            }
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

    // ---- Expressions ----

    fn parse_expr(&mut self) -> PResult<Expr> {
        self.parse_expr_bp(0)
    }

    fn parse_expr_no_struct(&mut self) -> PResult<Expr> {
        self.with_no_struct(true, |p| p.parse_expr_bp(0))
    }

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
                    self.advance();
                    let ty = self.parse_type()?;
                    let span = lhs.span.merge(ty.span);
                    lhs = self.mk_expr(
                        ExprKind::Cast {
                            expr: Box::new(lhs),
                            ty,
                        },
                        span,
                    );
                    built_by = None;
                    continue;
                }
                k if is_reserved_punct(k) => return Err(self.reserved_error()),
                _ => {}
            }
            let Some((op, lbp, rbp)) = infix_op(self.current()) else {
                break;
            };
            if lbp < min_bp {
                break;
            }
            if let Some(level) = op.non_assoc()
                && built_by == Some(level)
            {
                return Err(self.error(match level {
                    NonAssoc::Comparison => {
                        "comparison operators cannot be chained; use parentheses"
                    }
                    NonAssoc::Range => "range operators cannot be chained; use parentheses",
                }));
            }
            self.advance();
            let rhs = self.parse_expr_bp(rbp)?;
            let span = lhs.span.merge(rhs.span);
            let (lhs_box, rhs_box) = (Box::new(lhs), Box::new(rhs));
            let kind = match op {
                Infix::Bin(op) => ExprKind::BinOp {
                    op,
                    lhs: lhs_box,
                    rhs: rhs_box,
                },
                Infix::Assign(op) => ExprKind::Assign {
                    op,
                    target: lhs_box,
                    value: rhs_box,
                },
                Infix::Range { inclusive } => ExprKind::Range {
                    start: lhs_box,
                    end: rhs_box,
                    inclusive,
                },
            };
            lhs = self.mk_expr(kind, span);
            built_by = op.non_assoc();
        }
        Ok(lhs)
    }

    // Whether the current token can begin an expression (an operand of
    // `return` or `break`).
    fn starts_expr(&self) -> bool {
        matches!(
            self.current(),
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

    // `:label` after `break`/`continue`.
    fn parse_jump_label(&mut self) -> PResult<Option<Spanned<String>>> {
        if self.at(&TokenKind::Colon) && matches!(self.peek_kind(1), TokenKind::Ident(_)) {
            self.advance();
            Ok(Some(self.expect_ident()?))
        } else {
            Ok(None)
        }
    }

    fn parse_prefix(&mut self) -> PResult<Expr> {
        let start = self.span();
        let op = match self.current() {
            TokenKind::Minus => UnaryOp::Neg,
            TokenKind::Bang => UnaryOp::Not,
            TokenKind::Tilde => UnaryOp::BitNot,
            TokenKind::Star => UnaryOp::Deref,
            TokenKind::Amp => UnaryOp::AddrOf,
            TokenKind::AmpAmp => {
                // `&&x` is `& &x`
                let first = self.split_token(TokenKind::Amp, TokenKind::Amp);
                let operand = self.parse_expr_bp(PREFIX_BP)?;
                let span = first.merge(operand.span);
                return Ok(self.mk_expr(
                    ExprKind::UnaryOp {
                        op: UnaryOp::AddrOf,
                        expr: Box::new(operand),
                    },
                    span,
                ));
            }
            TokenKind::Plus => return Err(self.error("unary '+' is not supported")),
            TokenKind::Return => {
                self.advance();
                let value = if self.starts_expr() {
                    Some(Box::new(self.parse_expr_bp(0)?))
                } else {
                    None
                };
                let span = start.merge(self.prev_span());
                return Ok(self.mk_expr(ExprKind::Return(value), span));
            }
            TokenKind::Break => {
                self.advance();
                let label = self.parse_jump_label()?;
                let value = if self.starts_expr() {
                    Some(Box::new(self.parse_expr_bp(0)?))
                } else {
                    None
                };
                let span = start.merge(self.prev_span());
                return Ok(self.mk_expr(ExprKind::Break { label, value }, span));
            }
            TokenKind::Continue => {
                self.advance();
                let label = self.parse_jump_label()?;
                let span = start.merge(self.prev_span());
                return Ok(self.mk_expr(ExprKind::Continue { label }, span));
            }
            TokenKind::DotDot | TokenKind::DotDotEq => {
                return Err(self.error("a range needs a start: write 'a..b'"));
            }
            _ => return self.parse_primary(),
        };
        self.advance();
        let operand = self.parse_expr_bp(PREFIX_BP)?;
        let span = start.merge(operand.span);
        Ok(self.mk_expr(
            ExprKind::UnaryOp {
                op,
                expr: Box::new(operand),
            },
            span,
        ))
    }

    fn parse_postfix(&mut self, lhs: Expr) -> PResult<Expr> {
        match self.current() {
            TokenKind::LParen => {
                self.advance();
                let args =
                    self.with_no_struct(false, |p| p.parse_comma_list(&TokenKind::RParen))?;
                self.expect(&TokenKind::RParen)?;
                let span = lhs.span.merge(self.prev_span());
                Ok(self.mk_expr(
                    ExprKind::Call {
                        callee: Box::new(lhs),
                        args,
                    },
                    span,
                ))
            }
            TokenKind::LBracket => {
                self.advance();
                let index = self.with_no_struct(false, |p| p.parse_expr())?;
                self.expect(&TokenKind::RBracket)?;
                let span = lhs.span.merge(self.prev_span());
                Ok(self.mk_expr(
                    ExprKind::Index {
                        expr: Box::new(lhs),
                        index: Box::new(index),
                    },
                    span,
                ))
            }
            _ => {
                self.expect(&TokenKind::Dot)?;
                match *self.current() {
                    TokenKind::Ident(_) => {
                        if *self.peek_kind(1) == TokenKind::LParen {
                            return Err(self.error(
                                "methods are not supported yet; to call a function stored in a field, write (s.f)(x)",
                            ));
                        }
                        let name = self.expect_ident()?;
                        let span = lhs.span.merge(name.1);
                        Ok(self.mk_expr(
                            ExprKind::Field {
                                expr: Box::new(lhs),
                                name,
                            },
                            span,
                        ))
                    }
                    TokenKind::IntLiteral(index) => {
                        let is = self.span();
                        self.advance();
                        let span = lhs.span.merge(is);
                        Ok(self.mk_expr(
                            ExprKind::TupleField {
                                expr: Box::new(lhs),
                                index: (index, is),
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
        }
    }

    // `e, e, ...` up to (not including) `close`; a trailing comma is allowed.
    fn parse_comma_list(&mut self, close: &TokenKind) -> PResult<Vec<Expr>> {
        let mut items = Vec::new();
        while !self.at(close) && !self.is_at_eof() {
            items.push(self.parse_expr()?);
            if !self.eat(&TokenKind::Comma) {
                break;
            }
        }
        Ok(items)
    }

    fn literal(&mut self, kind: ExprKind) -> PResult<Expr> {
        let span = self.span();
        self.advance();
        Ok(self.mk_expr(kind, span))
    }

    fn parse_primary(&mut self) -> PResult<Expr> {
        let start = self.span();
        let at_label = self.at_label();
        match &mut self.tokens[self.pos].kind {
            TokenKind::IntLiteral(v) => {
                let v = *v;
                self.literal(ExprKind::IntLiteral(v))
            }
            TokenKind::FloatLiteral(v) => {
                let v = *v;
                self.literal(ExprKind::FloatLiteral(v))
            }
            TokenKind::SuffixedInt(v, s) => {
                let (v, s) = (*v, *s);
                self.literal(ExprKind::SuffixedLiteral(LitValue::Int(v), s))
            }
            TokenKind::SuffixedFloat(v, s) => {
                let (v, s) = (*v, *s);
                self.literal(ExprKind::SuffixedLiteral(LitValue::Float(v), s))
            }
            TokenKind::CharLiteral(v) => {
                let v = *v;
                self.literal(ExprKind::CharLiteral(v))
            }
            TokenKind::StringLiteral(s) => {
                let s = std::mem::take(s);
                self.literal(ExprKind::StringLiteral(s))
            }
            TokenKind::CStringLiteral(s) => {
                let s = std::mem::take(s);
                self.literal(ExprKind::CStringLiteral(s))
            }
            TokenKind::True => self.literal(ExprKind::BoolLiteral(true)),
            TokenKind::False => self.literal(ExprKind::BoolLiteral(false)),
            TokenKind::LParen => self.with_no_struct(false, |p| p.parse_paren_expr()),
            TokenKind::LBracket => self.with_no_struct(false, |p| p.parse_array_literal()),
            TokenKind::LBrace => {
                let block = self.parse_block()?;
                let span = block.span;
                Ok(self.mk_expr(ExprKind::Block(block), span))
            }
            TokenKind::If => self.parse_if(),
            TokenKind::Loop | TokenKind::While | TokenKind::For => self.parse_loop(None, start),
            TokenKind::Ident(_) if at_label => {
                let label = self.expect_ident()?;
                self.expect(&TokenKind::Colon)?;
                self.parse_loop(Some(label), start)
            }
            TokenKind::Ident(name) if name == "_" => {
                Err(self.error("'_' can only be used in patterns"))
            }
            TokenKind::Ident(_) => {
                let (name, name_span) = self.expect_ident()?;
                if !self.no_struct && self.at(&TokenKind::LBrace) {
                    self.parse_struct_constructor_rest(name, name_span)
                } else {
                    Ok(self.mk_expr(ExprKind::Ident(name), name_span))
                }
            }
            k if is_reserved_punct(k) || matches!(k, TokenKind::Reserved(_)) => {
                Err(self.reserved_error())
            }
            _ => Err(self.error(format!("expected expression, got '{}'", self.current()))),
        }
    }

    fn parse_paren_expr(&mut self) -> PResult<Expr> {
        let start = self.span();
        self.expect(&TokenKind::LParen)?;

        // Unit: ()
        if self.eat(&TokenKind::RParen) {
            return Ok(self.mk_expr(ExprKind::UnitLiteral, start.merge(self.prev_span())));
        }

        let first = self.parse_expr()?;

        // Tuple: (expr,) or (expr, expr, ...)
        if self.eat(&TokenKind::Comma) {
            let mut elems = vec![first];
            elems.extend(self.parse_comma_list(&TokenKind::RParen)?);
            self.expect(&TokenKind::RParen)?;
            let span = start.merge(self.prev_span());
            return Ok(self.mk_expr(ExprKind::Tuple(elems), span));
        }

        // Parenthesized: (expr)
        self.expect(&TokenKind::RParen)?;
        let span = start.merge(self.prev_span());
        Ok(Expr { span, ..first })
    }

    fn parse_array_literal(&mut self) -> PResult<Expr> {
        let start = self.span();
        self.expect(&TokenKind::LBracket)?;

        // Empty: [] (its type comes from context)
        if self.eat(&TokenKind::RBracket) {
            let span = start.merge(self.prev_span());
            return Ok(self.mk_expr(ExprKind::Array(Vec::new()), span));
        }

        let first = self.parse_expr()?;

        // Repeat: [expr; count]
        if self.eat(&TokenKind::Semi) {
            let count = self.parse_expr()?;
            self.expect(&TokenKind::RBracket)?;
            let span = start.merge(self.prev_span());
            return Ok(self.mk_expr(
                ExprKind::ArrayRepeat(Box::new(first), Box::new(count)),
                span,
            ));
        }

        // List: [expr, expr, ...]
        let mut elems = vec![first];
        if self.eat(&TokenKind::Comma) {
            elems.extend(self.parse_comma_list(&TokenKind::RBracket)?);
        }
        self.expect(&TokenKind::RBracket)?;
        let span = start.merge(self.prev_span());
        Ok(self.mk_expr(ExprKind::Array(elems), span))
    }

    fn parse_struct_constructor_rest(&mut self, name: String, name_span: Span) -> PResult<Expr> {
        self.expect(&TokenKind::LBrace)?;
        let fields = self.with_no_struct(false, |p| {
            let mut fields = Vec::new();
            while !p.at(&TokenKind::RBrace) && !p.is_at_eof() {
                let fs = p.span();
                let fname = p.expect_binding_name()?;
                p.expect(&TokenKind::Colon)?;
                let value = p.parse_expr()?;
                fields.push(FieldInit {
                    name: fname,
                    value,
                    span: fs.merge(p.prev_span()),
                });
                if !p.eat(&TokenKind::Comma) {
                    break;
                }
            }
            Ok(fields)
        })?;
        self.expect(&TokenKind::RBrace)?;
        let span = name_span.merge(self.prev_span());
        Ok(self.mk_expr(
            ExprKind::StructConstructor {
                name: (name, name_span),
                fields,
            },
            span,
        ))
    }

    fn parse_if(&mut self) -> PResult<Expr> {
        let start = self.span();
        self.expect(&TokenKind::If)?;
        let cond = self.parse_expr_no_struct()?;
        let then_block = self.parse_block()?;
        let else_block = if self.eat(&TokenKind::Else) {
            if self.at(&TokenKind::If) {
                // `else if`: an else block holding just the inner `if`.
                let inner = self.parse_if()?;
                let span = inner.span;
                Some(Block {
                    stmts: Vec::new(),
                    expr: Some(Box::new(inner)),
                    span,
                })
            } else {
                Some(self.parse_block()?)
            }
        } else {
            None
        };
        let span = start.merge(self.prev_span());
        Ok(self.mk_expr(
            ExprKind::If {
                cond: Box::new(cond),
                then_block,
                else_block,
            },
            span,
        ))
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
        Ok(self.mk_expr(kind, span))
    }

    // ---- Types ----

    fn parse_type(&mut self) -> PResult<Type> {
        let start = self.span();
        let kind = match self.current() {
            TokenKind::Ident(_) => {
                let (name, _) = self.expect_ident()?;
                if self.at(&TokenKind::ColonColon) {
                    return Err(self.error("paths are not supported yet"));
                }
                TypeKind::Named(name)
            }
            TokenKind::Star => {
                self.advance();
                TypeKind::Pointer(Box::new(self.parse_type()?))
            }
            TokenKind::Bang => {
                self.advance();
                TypeKind::Never
            }
            TokenKind::LParen => {
                self.advance();
                if self.eat(&TokenKind::RParen) {
                    TypeKind::Unit
                } else {
                    let first = self.parse_type()?;
                    if !self.eat(&TokenKind::Comma) {
                        // Parenthesized type
                        self.expect(&TokenKind::RParen)?;
                        return Ok(first);
                    }
                    let mut types = vec![first];
                    while !self.at(&TokenKind::RParen) && !self.is_at_eof() {
                        types.push(self.parse_type()?);
                        if !self.eat(&TokenKind::Comma) {
                            break;
                        }
                    }
                    self.expect(&TokenKind::RParen)?;
                    TypeKind::Tuple(types)
                }
            }
            TokenKind::LBracket => {
                self.advance();
                let elem = self.parse_type()?;
                if self.at(&TokenKind::RBracket) {
                    return Err(self.error("slice types are not supported yet"));
                }
                self.expect(&TokenKind::Semi)?;
                let size = self.with_no_struct(false, |p| p.parse_expr())?;
                self.expect(&TokenKind::RBracket)?;
                TypeKind::Array(Box::new(elem), Box::new(size))
            }
            TokenKind::Fn => {
                self.advance();
                self.expect(&TokenKind::LParen)?;
                let mut params = Vec::new();
                while !self.at(&TokenKind::RParen) && !self.is_at_eof() {
                    if self.at(&TokenKind::Ellipsis) {
                        return Err(self.error(
                            "function pointer types cannot be variadic; call variadic functions directly",
                        ));
                    }
                    params.push(self.parse_type()?);
                    if !self.eat(&TokenKind::Comma) {
                        break;
                    }
                }
                self.expect(&TokenKind::RParen)?;
                let result = if self.eat(&TokenKind::Arrow) {
                    self.parse_type()?
                } else {
                    Type {
                        kind: TypeKind::Unit,
                        span: self.prev_span(),
                    }
                };
                TypeKind::Fn {
                    params,
                    result: Box::new(result),
                }
            }
            TokenKind::Reserved(_) => return Err(self.reserved_error()),
            _ => return Err(self.error(format!("expected type, got '{}'", self.current()))),
        };
        Ok(Type {
            kind,
            span: start.merge(self.prev_span()),
        })
    }
}

// Parses a whole program; on failure returns every syntax error found.
pub fn parse(tokens: Vec<Token>) -> Result<Program, Vec<ParserError>> {
    let mut parser = Parser::new(tokens);
    let program = parser.parse_program();
    if parser.errors.is_empty() {
        Ok(program)
    } else {
        Err(parser.errors)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    pub fn parse_source(src: &str) -> Result<Program, Vec<ParserError>> {
        parse(crate::lexer::Lexer::new(src).tokenize().unwrap())
    }

    fn parse_ok(src: &str) -> Program {
        parse_source(src).unwrap_or_else(|e| panic!("parse failed: {:?}\nsource: {}", e, src))
    }

    fn parse_errs(src: &str) -> Vec<String> {
        match parse_source(src) {
            Ok(_) => panic!("expected parse error for: {}", src),
            Err(errors) => errors.into_iter().map(|e| e.message).collect(),
        }
    }

    fn parse_err(src: &str) {
        parse_errs(src);
    }

    fn parse_err_contains(src: &str, needle: &str) {
        let errors = parse_errs(src);
        assert!(
            errors.iter().any(|e| e.contains(needle)),
            "expected an error containing {:?}, got {:?}\nsource: {}",
            needle,
            errors,
            src
        );
    }

    // ---- S-expression printer, to check tree shapes compactly ----

    fn binop(op: BinOp) -> &'static str {
        match op {
            BinOp::Add => "+",
            BinOp::Sub => "-",
            BinOp::Mul => "*",
            BinOp::Div => "/",
            BinOp::Mod => "%",
            BinOp::Eq => "==",
            BinOp::Neq => "!=",
            BinOp::Lt => "<",
            BinOp::Gt => ">",
            BinOp::LtEq => "<=",
            BinOp::GtEq => ">=",
            BinOp::And => "&&",
            BinOp::Or => "||",
            BinOp::BitAnd => "&",
            BinOp::BitOr => "|",
            BinOp::BitXor => "^",
            BinOp::Shl => "<<",
            BinOp::Shr => ">>",
        }
    }

    fn ty(t: &Type) -> String {
        match &t.kind {
            TypeKind::Named(n) => n.clone(),
            TypeKind::Unit => "()".into(),
            TypeKind::Never => "!".into(),
            TypeKind::Tuple(ts) => {
                format!("({})", ts.iter().map(ty).collect::<Vec<_>>().join(", "))
            }
            TypeKind::Array(e, n) => format!("[{}; {}]", ty(e), sx(n)),
            TypeKind::Pointer(p) => format!("*{}", ty(p)),
            TypeKind::Fn { params, result } => format!(
                "fn({}) -> {}",
                params.iter().map(ty).collect::<Vec<_>>().join(", "),
                ty(result)
            ),
        }
    }

    fn pat(p: &Pattern) -> String {
        match &p.kind {
            PatternKind::Wildcard => "_".into(),
            PatternKind::Binding { name, mutable } => {
                format!("{}{}", if *mutable { "mut " } else { "" }, name)
            }
            PatternKind::Tuple(ps) => {
                format!("({})", ps.iter().map(pat).collect::<Vec<_>>().join(", "))
            }
        }
    }

    fn label(l: &Option<Spanned<String>>) -> String {
        l.as_ref().map(|l| format!(" :{}", l.0)).unwrap_or_default()
    }

    fn block(b: &Block) -> String {
        let mut parts: Vec<String> = b
            .stmts
            .iter()
            .map(|s| match s {
                Stmt::Let(l) => format!(
                    "(let {}{} {});",
                    pat(&l.pattern),
                    l.ty.as_ref()
                        .map(|t| format!(": {}", ty(t)))
                        .unwrap_or_default(),
                    sx(&l.init)
                ),
                Stmt::Expr(e) => format!("{}{}", sx(&e.expr), if e.has_semi { ";" } else { "" }),
            })
            .collect();
        if let Some(t) = &b.expr {
            parts.push(sx(t));
        }
        format!("{{{}}}", parts.join(" "))
    }

    fn list(es: &[Expr]) -> String {
        es.iter().map(sx).collect::<Vec<_>>().join(" ")
    }

    fn sx(e: &Expr) -> String {
        match &e.kind {
            ExprKind::Error => "<error>".into(),
            ExprKind::IntLiteral(v) => v.to_string(),
            ExprKind::FloatLiteral(f) => format!("{:?}", **f),
            ExprKind::CharLiteral(c) => format!("{:?}", *c as char),
            ExprKind::SuffixedLiteral(LitValue::Int(v), s) => format!("{}{}", v, s.name()),
            ExprKind::SuffixedLiteral(LitValue::Float(f), s) => format!("{:?}{}", **f, s.name()),
            ExprKind::StringLiteral(s) => format!("{:?}", String::from_utf8_lossy(s)),
            ExprKind::CStringLiteral(s) => format!("c{:?}", String::from_utf8_lossy(s)),
            ExprKind::BoolLiteral(b) => b.to_string(),
            ExprKind::UnitLiteral => "()".into(),
            ExprKind::Ident(n) => n.clone(),
            ExprKind::Tuple(es) => format!("(tuple {})", list(es)),
            ExprKind::Array(es) => format!("[{}]", list(es)),
            ExprKind::ArrayRepeat(v, n) => format!("[{}; {}]", sx(v), sx(n)),
            ExprKind::StructConstructor { name, fields } => format!(
                "({} {})",
                name.0,
                fields
                    .iter()
                    .map(|f| format!("{}: {}", f.name.0, sx(&f.value)))
                    .collect::<Vec<_>>()
                    .join(" ")
            ),
            ExprKind::BinOp { op, lhs, rhs } => format!("({} {} {})", binop(*op), sx(lhs), sx(rhs)),
            ExprKind::UnaryOp { op, expr } => {
                let o = match op {
                    UnaryOp::Neg => "-",
                    UnaryOp::Not => "!",
                    UnaryOp::BitNot => "~",
                    UnaryOp::Deref => "*",
                    UnaryOp::AddrOf => "&",
                };
                format!("({} {})", o, sx(expr))
            }
            ExprKind::Cast { expr, ty: t } => format!("(as {} {})", sx(expr), ty(t)),
            ExprKind::Call { callee, args } => {
                format!(
                    "(call {}{}{})",
                    sx(callee),
                    if args.is_empty() { "" } else { " " },
                    list(args)
                )
            }
            ExprKind::Index { expr, index } => format!("(index {} {})", sx(expr), sx(index)),
            ExprKind::Field { expr, name } => format!("(. {} {})", sx(expr), name.0),
            ExprKind::TupleField { expr, index } => format!("(. {} {})", sx(expr), index.0),
            ExprKind::Range {
                start,
                end,
                inclusive,
            } => format!(
                "({} {} {})",
                if *inclusive { "..=" } else { ".." },
                sx(start),
                sx(end)
            ),
            ExprKind::Assign { op, target, value } => {
                let o = match op {
                    AssignOp::Assign => "=".to_string(),
                    other => format!("{}=", binop(other.binop().unwrap())),
                };
                format!("({} {} {})", o, sx(target), sx(value))
            }
            ExprKind::Block(b) => block(b),
            ExprKind::If {
                cond,
                then_block,
                else_block,
            } => match else_block {
                Some(eb) => format!("(if {} {} {})", sx(cond), block(then_block), block(eb)),
                None => format!("(if {} {})", sx(cond), block(then_block)),
            },
            ExprKind::Loop { label: l, body } => format!("(loop{} {})", label(l), block(body)),
            ExprKind::While {
                label: l,
                cond,
                body,
            } => format!("(while{} {} {})", label(l), sx(cond), block(body)),
            ExprKind::For {
                label: l,
                pattern,
                iter,
                body,
            } => format!(
                "(for{} {} {} {})",
                label(l),
                pat(pattern),
                sx(iter),
                block(body)
            ),
            ExprKind::Return(v) => match v {
                Some(v) => format!("(return {})", sx(v)),
                None => "(return)".into(),
            },
            ExprKind::Break { label: l, value } => match value {
                Some(v) => format!("(break{} {})", label(l), sx(v)),
                None => format!("(break{})", label(l)),
            },
            ExprKind::Continue { label: l } => format!("(continue{})", label(l)),
        }
    }

    // The body of `fn f() { <src> }`, printed.
    fn body(src: &str) -> String {
        let program = parse_ok(&format!("fn f() {{ {} }}", src));
        let Item::Function(f) = &program.items[0] else {
            panic!()
        };
        block(&f.body)
    }

    // An expression, printed.
    fn expr(src: &str) -> String {
        let printed = body(src);
        printed[1..printed.len() - 1].to_string()
    }

    // ---- Items ----

    #[test]
    fn test_empty_program() {
        assert!(parse_ok("").items.is_empty());
    }

    #[test]
    fn test_items() {
        let p = parse_ok(
            r#"
            struct Point { x: i32, y: i32, }
            struct Empty {}
            extern fn puts(s: *u8) -> i32;
            extern "C" fn printf(fmt: *u8, ...) -> i32;
            fn add(a: i32, mut b: i32,) -> i32 { a }
            fn ignore(_: i64) {}
            const N: i64 = 4 * 2;
            static mut COUNT: u64 = 0;
            static TABLE: [u8; N] = [0; N];
            type Grid = [[u8; 3]; 3];
            "#,
        );
        assert_eq!(p.items.len(), 10);
        let Item::Function(add) = &p.items[4] else {
            panic!()
        };
        assert!(!add.params[0].mutable && add.params[1].mutable);
        let Item::Extern(printf) = &p.items[3] else {
            panic!()
        };
        assert!(printf.is_variadic);
        let Item::Static(count) = &p.items[7] else {
            panic!()
        };
        assert!(count.mutable);
    }

    #[test]
    fn test_types() {
        let p = parse_ok(
            "fn f(a: (i32, f64), b: (i32,), c: [i32; 2 * N], d: **i32, e: fn(i32) -> *u8, g: fn()) -> ! { loop {} }",
        );
        let Item::Function(f) = &p.items[0] else {
            panic!()
        };
        let printed: Vec<String> = f.params.iter().map(|p| ty(&p.ty)).collect();
        assert_eq!(
            printed,
            vec![
                "(i32, f64)",
                "(i32)",
                "[i32; (* 2 N)]",
                "**i32",
                "fn(i32) -> *u8",
                "fn() -> ()"
            ]
        );
        assert_eq!(ty(f.return_type.as_ref().unwrap()), "!");
    }

    #[test]
    fn test_item_errors() {
        parse_err_contains("fn f() {} pub fn g() {}", "'pub' is a reserved keyword");
        parse_err_contains("extern \"Rust\" fn f();", "unsupported ABI");
        parse_err_contains(
            "fn f(x: i64, ...) {}",
            "only extern functions can be variadic",
        );
        parse_err_contains(
            "fn f(g: fn(i64, ...) -> i64) {}",
            "function pointer types cannot be variadic",
        );
        parse_err_contains("fn f(x: [u8]) {}", "slice types are not supported yet");
        parse_err_contains("fn f(x: a::B) {}", "paths are not supported yet");
        parse_err_contains("type V<T> = T;", "generic type aliases");
        parse_err_contains("fn match() {}", "'match' is a reserved keyword");
    }

    // ---- Statements ----

    #[test]
    fn test_let_and_patterns() {
        assert_eq!(body("let x: i32 = 42;"), "{(let x: i32 42);}");
        assert_eq!(
            body(
                "let mut x = 1; let _ = f(); let (a, mut b, _) = t; let ((p, q), r) = u; let (s) = 1;"
            ),
            "{(let mut x 1); (let _ (call f)); (let (a, mut b, _) t); (let ((p, q), r) u); (let s 1);}"
        );
        assert_eq!(body("let (one,) = t;"), "{(let (one) t);}");
        parse_err_contains("fn f() { let x: i64; }", "without an initializer");
        parse_err_contains("fn f() { let mut _ = 1; }", "expected a name, got '_'");
    }

    #[test]
    fn test_statement_rule() {
        // Block-like statements need no `;`, and a following `;` is theirs.
        assert_eq!(
            body("if c { a(); } let x = 1; loop { break; }; while c {} b()"),
            "{(if c {(call a);}) (let x 1); (loop {(break);}); (while c {}) (call b)}"
        );
        // ... and are never continued by an operator: `- 1` is a new statement.
        assert_eq!(body("{ 1 } - 1"), "{{1} (- 1)}");
        // A trailing block-like expression is the block's value.
        assert_eq!(
            body("let y = 0; if c { 1 } else { 2 }"),
            "{(let y 0); (if c {1} {2})}"
        );
        // Empty statements are allowed anywhere.
        assert_eq!(body(";; let x = 1;;"), "{(let x 1);}");
        // Other expressions need a `;` unless they are the tail.
        parse_err_contains("fn f() { a() b() }", "expected ';' or '}' after expression");
        parse_err("fn main() { let x = 42 }");
    }

    #[test]
    fn test_assignment_is_an_expression() {
        assert_eq!(expr("x = 42"), "(= x 42)");
        assert_eq!(
            body(
                "x += 1; x -= 2; x *= 3; x /= 4; x %= 5; x &= 6; x |= 7; x ^= 8; x <<= 9; x >>= 10;"
            ),
            "{(+= x 1); (-= x 2); (*= x 3); (/= x 4); (%= x 5); (&= x 6); (|= x 7); (^= x 8); (<<= x 9); (>>= x 10);}"
        );
        // right-associative, lowest precedence
        assert_eq!(expr("a = b = c + 1"), "(= a (= b (+ c 1)))");
        assert_eq!(expr("*p.x = a[i] = 0"), "(= (* (. p x)) (= (index a i) 0))");
        // targets are checked by the type checker, not the parser
        assert_eq!(expr("f().x = 3"), "(= (. (call f) x) 3)");
    }

    // ---- Expressions: precedence and associativity ----

    #[test]
    fn test_arithmetic_precedence() {
        assert_eq!(expr("1 + 2 * 3"), "(+ 1 (* 2 3))");
        assert_eq!(expr("1 - 2 - 3"), "(- (- 1 2) 3)");
        assert_eq!(expr("a / b % c * d"), "(* (% (/ a b) c) d)");
        assert_eq!(expr("(1 + 2) * 3"), "(* (+ 1 2) 3)");
        assert_eq!(expr("a << 1 + 2"), "(<< a (+ 1 2))");
        assert_eq!(expr("a & b ^ c | d"), "(| (^ (& a b) c) d)");
        assert_eq!(expr("a | b == c"), "(== (| a b) c)");
        assert_eq!(expr("a < b && c || d"), "(|| (&& (< a b) c) d)");
    }

    #[test]
    fn test_unary_and_cast_precedence() {
        assert_eq!(expr("-x as i64"), "(as (- x) i64)");
        assert_eq!(expr("a * b as f64"), "(* a (as b f64))");
        assert_eq!(expr("x as u8 as i32"), "(as (as x u8) i32)");
        assert_eq!(expr("*p.x"), "(* (. p x))");
        assert_eq!(expr("-a[0]"), "(- (index a 0))");
        assert_eq!(expr("!f()"), "(! (call f))");
        assert_eq!(expr("~0xFF"), "(~ 255)");
        assert_eq!(expr("&a.b"), "(& (. a b))");
        assert_eq!(expr("(p as u64 + i) as *u8"), "(as (+ (as p u64) i) *u8)");
        assert_eq!(expr("x as u64 < n"), "(< (as x u64) n)");
    }

    #[test]
    fn test_double_star_and_double_amp() {
        // `**` is two derefs, `&&` in prefix position two address-ofs.
        assert_eq!(expr("**pp"), "(* (* pp))");
        assert_eq!(expr("a * *p"), "(* a (* p))");
        assert_eq!(expr("a**p"), "(* a (* p))");
        assert_eq!(expr("&&x"), "(& (& x))");
        assert_eq!(expr("a && &x == b"), "(&& a (== (& x) b))");
        parse_err_contains("fn f() { +x; }", "unary '+' is not supported");
    }

    #[test]
    fn test_comparisons_do_not_chain() {
        parse_err_contains(
            "fn f() { a < b < c; }",
            "comparison operators cannot be chained",
        );
        parse_err_contains(
            "fn f() { a == b == c; }",
            "comparison operators cannot be chained",
        );
        parse_err_contains(
            "fn f() { a < b == true; }",
            "comparison operators cannot be chained",
        );
        assert_eq!(expr("(a < b) == c"), "(== (< a b) c)");
        assert_eq!(expr("a < b && b < c"), "(&& (< a b) (< b c))");
    }

    #[test]
    fn test_postfix() {
        assert_eq!(
            expr("foo().bar[0].baz"),
            "(. (index (. (call foo) bar) 0) baz)"
        );
        assert_eq!(expr("foo(1, 2,)"), "(call foo 1 2)");
        assert_eq!(expr("t.0.1"), "(. (. t 0) 1)");
        assert_eq!(expr("(s.f)(x)"), "(call (. s f) x)");
        parse_err_contains("fn f() { s.f(x); }", "methods are not supported yet");
        parse_err_contains("fn f() { x?; }", "'?' is reserved for future use");
    }

    #[test]
    fn test_literals() {
        assert_eq!(
            expr("(1, 2.5, 'a', 1u8, 2f32, 3.5f64, true, (), \"hi\", c\"cs\")"),
            "(tuple 1 2.5 'a' 1u8 2.0f32 3.5f64 true () \"hi\" c\"cs\")"
        );
        assert_eq!(expr("(1,)"), "(tuple 1)");
        assert_eq!(expr("[1, 2, 3,]"), "[1 2 3]");
        assert_eq!(expr("[]"), "[]");
        assert_eq!(expr("[0; N + 1]"), "[0; (+ N 1)]");
        assert_eq!(expr("P { x: 1, y: Q { z: 2 } }"), "(P x: 1 y: (Q z: 2))");
        parse_err_contains("fn f() { _; }", "'_' can only be used in patterns");
    }

    // ---- Control flow ----

    #[test]
    fn test_if_else_if() {
        assert_eq!(
            expr("if a { 1 } else if b { 2 } else { 3 }"),
            "(if a {1} {(if b {2} {3})})"
        );
        assert_eq!(
            expr("if a { 1 } else if b { 2 }"),
            "(if a {1} {(if b {2})})"
        );
    }

    #[test]
    fn test_struct_literal_restriction() {
        // In a condition `Name {` starts the body ...
        assert_eq!(expr("if a { 1; }"), "(if a {1;})");
        assert_eq!(expr("while x { }"), "(while x {})");
        // ... but not inside parentheses, brackets, braces or arguments.
        assert_eq!(expr("if f(P { x: 1 }) { }"), "(if (call f (P x: 1)) {})");
        assert_eq!(
            expr("if (P { x: 1 }).x == 1 { }"),
            "(if (== (. (P x: 1) x) 1) {})"
        );
        assert_eq!(
            expr("if a[P { x: 1 }.x] { }"),
            "(if (index a (. (P x: 1) x)) {})"
        );
        assert_eq!(
            expr("if { P { x: 1 } }.x == 1 { }"),
            "(if (== (. {(P x: 1)} x) 1) {})"
        );
    }

    #[test]
    fn test_loops() {
        assert_eq!(expr("loop { break; }"), "(loop {(break);})");
        assert_eq!(
            expr("while i < 10 { i += 1; }"),
            "(while (< i 10) {(+= i 1);})"
        );
        assert_eq!(expr("for i in 0..n { }"), "(for i (.. 0 n) {})");
        assert_eq!(
            expr("for mut i in a..=b + 1 { }"),
            "(for mut i (..= a (+ b 1)) {})"
        );
        assert_eq!(expr("for _ in 0..3 { }"), "(for _ (.. 0 3) {})");
        assert_eq!(
            expr("outer: loop { inner: while c { continue :outer; break :inner; } }"),
            "(loop :outer {(while :inner c {(continue :outer); (break :inner);})})"
        );
        assert_eq!(
            expr("let x = loop { break 5; };"),
            "(let x (loop {(break 5);}));"
        );
        assert_eq!(expr("break :outer x + 1"), "(break :outer (+ x 1))");
        parse_err_contains("fn f() { a..b..c; }", "range operators cannot be chained");
    }

    #[test]
    fn test_return_break_continue_are_expressions() {
        assert_eq!(expr("return"), "(return)");
        assert_eq!(expr("return 1 + 2"), "(return (+ 1 2))");
        assert_eq!(
            body("let v = if c { 1 } else { return 0; }; v"),
            "{(let v (if c {1} {(return 0);})); v}"
        );
        assert_eq!(
            expr("if c { return } else { continue }"),
            "(if c {(return)} {(continue)})"
        );
        assert_eq!(expr("x || return"), "(|| x (return))");
    }

    #[test]
    fn test_reserved_keywords() {
        for kw in [
            "enum", "match", "impl", "trait", "pub", "mod", "use", "self", "Self", "super",
            "where", "unsafe", "defer", "union", "dyn", "move",
        ] {
            parse_err_contains(
                &format!("fn f() {{ let {} = 1; }}", kw),
                "is a reserved keyword",
            );
        }
        parse_err_contains("fn f() { a => b; }", "'=>' is reserved for future use");
        parse_err_contains("fn f() { #x; }", "'#' is reserved for future use");
        parse_err_contains("fn f() { a::b; }", "'::' is reserved for future use");
        parse_err_contains("fn f() { @x; }", "'@' is reserved for future use");
    }

    // ---- Error recovery ----

    #[test]
    fn test_reports_independent_errors() {
        let src = r#"
            fn a() { let x = ; }
            fn b() { foo(1, 2; let ok = 1; }
            struct S { x i64 }
            fn c() -> { 1 }
            fn d() {
                let y = 1 +;
                let z = (2;
                if y < 1 { } else { let w = ) ; }
            }
            fn e() -> i64 { 1 }
        "#;
        let errors = parse_errs(src);
        assert_eq!(errors.len(), 7, "{:#?}", errors);
        assert!(errors[0].contains("expected expression, got ';'"));
        assert!(errors[1].contains("expected ')', got ';'"));
        assert!(errors[2].contains("expected ':', got 'i64'"));
        assert!(errors[3].contains("expected type, got '{'"));
        assert!(errors[4].contains("expected expression, got ';'"));
        assert!(errors[5].contains("expected ')', got ';'"));
        assert!(errors[6].contains("expected expression, got ')'"));
    }

    #[test]
    fn test_recovery_keeps_parsing_after_missing_brace() {
        let errors = parse_errs("fn a() { let x = 1;\nfn b() { let y = ; }");
        assert_eq!(errors.len(), 2, "{:#?}", errors);
        assert!(errors[0].contains("expected '}' before 'fn'"));
        assert!(errors[1].contains("expected expression, got ';'"));
    }

    #[test]
    fn test_error_statements_are_kept() {
        let mut parser = Parser::new(
            crate::lexer::Lexer::new("fn f() { let = 1; g(); }")
                .tokenize()
                .unwrap(),
        );
        let program = parser.parse_program();
        assert_eq!(parser.errors.len(), 1);
        let Item::Function(f) = &program.items[0] else {
            panic!()
        };
        assert_eq!(block(&f.body), "{<error>; (call g);}");
    }

    #[test]
    fn test_expression_ids_are_dense() {
        let p = parse_ok("fn f() -> i64 { let x = 1 + 2; x * (3 - 4) }");
        assert_eq!(p.expr_count, 8);
    }

    #[test]
    fn test_comprehensive_program_parses() {
        parse_ok(
            r#"
            struct Vec2 { x: f64, y: f64 }
            extern fn sqrt(x: f64) -> f64;
            extern fn printf(fmt: *u8, ...) -> i32;
            const SCALE: f64 = 2.0;

            fn length(v: Vec2) -> f64 {
                let sq = v.x * v.x + v.y * v.y;
                sqrt(sq)
            }

            fn abs(x: i32) -> i32 {
                if x < 0 { -x } else { x }
            }

            fn fib(n: i32) -> i32 {
                if n <= 1 { return n; }
                fib(n - 1) + fib(n - 2)
            }

            fn main() -> i32 {
                let mut sum = 0;
                for i in 0..10 {
                    if i % 2 == 0 { continue; }
                    sum += i;
                }
                let mut i = 10;
                while i > 0 { i -= 1; }
                let found = outer: loop {
                    loop { break :outer 42; }
                };
                let p = Vec2 { x: 3.0, y: 4.0 };
                let (a, mut b) = (1, 2);
                b = a;
                let arr: [i32; 3] = [1, 2, 3];
                let c = 'a' as i32 + arr[0] + b;
                printf(c"%f %d %d\n", length(p) * SCALE, fib(10), c + found + sum);
                0
            }
            "#,
        );
    }
}
