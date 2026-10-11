// Types: `name`, `*T`, `!`, `()`, `(T, ...)`, `[T; n]`, `fn(T, ...) -> R`.

use super::{PResult, Parser, Type, TypeKind};
use crate::lexer::{span::Span, token::TokenKind};

impl Parser {
    pub(super) fn parse_type(&mut self) -> PResult<Type> {
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
            TokenKind::LParen => return self.parse_paren_type(start),
            TokenKind::LBracket => self.parse_array_type()?,
            TokenKind::Fn => self.parse_fn_type()?,
            TokenKind::Reserved(_) => return Err(self.reserved_error()),
            _ => return Err(self.error(format!("expected type, got '{}'", self.current()))),
        };
        Ok(Type {
            kind,
            span: start.merge(self.prev_span()),
        })
    }

    // `-> T` after a parameter list, if present.
    pub(super) fn parse_return_type(&mut self) -> PResult<Option<Type>> {
        if self.eat(&TokenKind::Arrow) {
            Ok(Some(self.parse_type()?))
        } else {
            Ok(None)
        }
    }

    // `()`, `(T)` (just `T`), or a tuple `(T, ...)`.
    fn parse_paren_type(&mut self, start: Span) -> PResult<Type> {
        self.expect(&TokenKind::LParen)?;
        let kind = if self.eat(&TokenKind::RParen) {
            TypeKind::Unit
        } else {
            let first = self.parse_type()?;
            if !self.eat(&TokenKind::Comma) {
                self.expect(&TokenKind::RParen)?;
                return Ok(first);
            }
            let mut elems = vec![first];
            elems.extend(self.parse_comma_separated(&TokenKind::RParen, Self::parse_type)?);
            self.expect(&TokenKind::RParen)?;
            TypeKind::Tuple(elems)
        };
        Ok(Type {
            kind,
            span: start.merge(self.prev_span()),
        })
    }

    // `[T; n]`, where `n` is a constant expression.
    fn parse_array_type(&mut self) -> PResult<TypeKind> {
        self.expect(&TokenKind::LBracket)?;
        let elem = self.parse_type()?;
        if self.at(&TokenKind::RBracket) {
            return Err(self.error("slice types are not supported yet"));
        }
        self.expect(&TokenKind::Semi)?;
        let size = self.with_no_struct(false, |p| p.parse_expr())?;
        self.expect(&TokenKind::RBracket)?;
        Ok(TypeKind::Array(Box::new(elem), Box::new(size)))
    }

    // `fn(T, ...) [-> R]`; without `->` the result is `()`.
    fn parse_fn_type(&mut self) -> PResult<TypeKind> {
        self.expect(&TokenKind::Fn)?;
        self.expect(&TokenKind::LParen)?;
        let params = self.parse_comma_separated(&TokenKind::RParen, |p| {
            if p.at(&TokenKind::Ellipsis) {
                return Err(p.error(
                    "function pointer types cannot be variadic; call variadic functions directly",
                ));
            }
            p.parse_type()
        })?;
        self.expect(&TokenKind::RParen)?;
        let result = if self.eat(&TokenKind::Arrow) {
            self.parse_type()?
        } else {
            Type {
                kind: TypeKind::Unit,
                span: self.prev_span(),
            }
        };
        Ok(TypeKind::Fn {
            params,
            result: Box::new(result),
        })
    }
}
