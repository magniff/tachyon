// Parser: recursive descent for items and statements, a Pratt (binding
// power) parser for expressions. The grammar is documented in
// docs/grammar.md.
//
// Errors do not stop the parse: a failed statement or item is reported,
// replaced by an `Error` node, and the parser resynchronizes at the next
// `;`, `}` or item/statement keyword, so one run reports every independent
// syntax error.
//
//   items.rs     functions, externs, structs, constants, statics, aliases
//   stmt.rs      blocks, statements and patterns
//   expr.rs      expressions (the Pratt parser)
//   types.rs     types
//   recovery.rs  skipping past syntax errors

use std::fmt;

use crate::lexer::{
    span::Span,
    token::{Token, TokenKind},
};

mod ast;
mod expr;
mod items;
mod recovery;
mod stmt;
mod types;

pub use ast::*;

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
        let index = (self.pos + offset).min(self.tokens.len() - 1);
        &self.tokens[index].kind
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
            let span = self.span();
            self.advance();
            Ok(span)
        } else {
            Err(self.error(format!("expected '{}', got '{}'", kind, self.current())))
        }
    }

    // Splits the current joint token (e.g. `&&`) and consumes its first part
    // (`&`), leaving the rest as the current token.
    fn split_token(&mut self, first: TokenKind, rest: TokenKind) -> Span {
        let first_len = first.to_string().len();
        let token = &mut self.tokens[self.pos];
        let first_span = Span::new(token.span.start, token.span.start + first_len);
        token.kind = rest;
        token.span = Span::new(token.span.start + first_len, token.span.end);
        first_span
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
        if matches!(self.current(), TokenKind::Ident(name) if name == "_") {
            return Err(self.error("expected a name, got '_'"));
        }
        self.expect_ident()
    }

    // `, item` repeated up to (not including) `close`; a trailing comma is
    // allowed.
    fn parse_comma_separated<T>(
        &mut self,
        close: &TokenKind,
        mut parse_item: impl FnMut(&mut Self) -> PResult<T>,
    ) -> PResult<Vec<T>> {
        let mut items = Vec::new();
        while !self.at(close) && !self.is_at_eof() {
            items.push(parse_item(self)?);
            if !self.eat(&TokenKind::Comma) {
                break;
            }
        }
        Ok(items)
    }

    // ---- Errors ----

    fn error(&self, message: impl Into<String>) -> ParserError {
        ParserError {
            message: message.into(),
            span: self.span(),
        }
    }

    fn reserved_error(&self) -> ParserError {
        match self.current() {
            TokenKind::Reserved(keyword) => self.error(format!(
                "'{}' is a reserved keyword (reserved for future use)",
                keyword
            )),
            other => self.error(format!("'{}' is reserved for future use", other)),
        }
    }

    // ---- Building nodes ----

    fn make_expr(&mut self, kind: ExprKind, span: Span) -> Expr {
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
mod tests;
