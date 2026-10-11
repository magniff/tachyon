// Top-level items: functions, externs, structs, constants, statics and type
// aliases.

use super::{
    ConstDecl, ExternDecl, FunctionDecl, Item, PResult, Parameter, Parser, Program, StaticDecl,
    StructDecl, StructField, TypeAliasDecl,
};
use crate::lexer::token::TokenKind;

impl Parser {
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
        let fields = self.parse_comma_separated(&TokenKind::RBrace, Self::parse_struct_field)?;
        self.expect(&TokenKind::RBrace)?;
        Ok(StructDecl {
            name,
            fields,
            span: start.merge(self.prev_span()),
        })
    }

    // `name: T`
    fn parse_struct_field(&mut self) -> PResult<StructField> {
        let start = self.span();
        let name = self.expect_binding_name()?;
        self.expect(&TokenKind::Colon)?;
        let ty = self.parse_type()?;
        Ok(StructField {
            name,
            ty,
            span: start.merge(self.prev_span()),
        })
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
        self.parse_extern_abi()?;
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

    // The optional ABI string after `extern`; only "C" is supported.
    fn parse_extern_abi(&mut self) -> PResult<()> {
        if let TokenKind::StringLiteral(abi) = self.current() {
            if abi.as_slice() != b"C" {
                return Err(self.error(format!(
                    "unsupported ABI {}; only \"C\" is supported",
                    self.current()
                )));
            }
            self.advance();
        }
        Ok(())
    }

    // `[mut] name: T, ...` and, for externs, a final `...`. Returns the
    // parameters and whether the list ended with `...`.
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
            params.push(self.parse_param()?);
            if !self.eat(&TokenKind::Comma) {
                break;
            }
        }
        Ok((params, is_variadic))
    }

    // `[mut] name: T`; an immutable parameter may be named `_`.
    fn parse_param(&mut self) -> PResult<Parameter> {
        let start = self.span();
        let mutable = self.eat(&TokenKind::Mut);
        let name = if mutable {
            self.expect_binding_name()?
        } else {
            self.expect_ident()?
        };
        self.expect(&TokenKind::Colon)?;
        let ty = self.parse_type()?;
        Ok(Parameter {
            name,
            mutable,
            ty,
            span: start.merge(self.prev_span()),
        })
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
}
