// Pass 2: function bodies, blocks, statements and patterns.

use super::env::{TypingEnvironment, VarInfo};
use super::{TypeInternal, Typechecker, TypecheckerResult, typechecker_error};
use crate::parser::{
    Block, ExprStmt, FunctionDecl, Item, LetStmt, Pattern, PatternKind, Program, Stmt,
};

impl Typechecker<'_> {
    pub(super) fn check_function_bodies(&mut self, program: &Program) {
        for item in &program.items {
            if let Item::Function(decl) = item {
                self.check_function(decl);
            }
        }
    }

    fn check_function(&mut self, decl: &FunctionDecl) {
        let signature = self.signatures[&decl.name.0].clone();
        self.return_ty = signature.return_ty.clone();
        self.loops.clear();
        self.env = TypingEnvironment::new();
        for (param, (name, ty)) in decl.params.iter().zip(&signature.params) {
            if name != "_" {
                let info = VarInfo {
                    ty: ty.clone(),
                    mutable: param.mutable,
                    is_param: true,
                };
                self.env.define(name.clone(), info);
            }
        }

        // The body's tail is checked against the return type; a body without
        // a tail has type () unless it never reaches its end.
        match self.check_block(&decl.body, Some(&signature.return_ty)) {
            Ok(body_ty) if body_ty != signature.return_ty && body_ty != TypeInternal::Never => {
                self.errors.push(typechecker_error(
                    decl.body.span,
                    format!(
                        "function '{}' body has type '{}', expected '{}'",
                        decl.name.0, body_ty, signature.return_ty
                    ),
                ));
            }
            Ok(_) => {}
            Err(e) => self.errors.push(e),
        }
    }

    // The block's type: its tail's (checked against `expected` if given),
    // `!` if a statement diverges, otherwise ().
    pub(super) fn check_block(
        &mut self,
        block: &Block,
        expected: Option<&TypeInternal>,
    ) -> TypecheckerResult<TypeInternal> {
        self.env.push_scope();
        let result = self.check_block_in_scope(block, expected);
        self.env.pop_scope();
        result
    }

    fn check_block_in_scope(
        &mut self,
        block: &Block,
        expected: Option<&TypeInternal>,
    ) -> TypecheckerResult<TypeInternal> {
        let mut diverges = false;
        for stmt in &block.stmts {
            diverges |= self.check_stmt(stmt);
        }
        let ty = match (&block.expr, expected) {
            (Some(tail), Some(expected)) => self.check_expr(tail, expected)?,
            (Some(tail), None) => self.synth_expr(tail)?,
            (None, _) => TypeInternal::Unit,
        };
        Ok(if diverges { TypeInternal::Never } else { ty })
    }

    // A block in check mode (an if/else branch or a block expression): its
    // tail must have the expected type, and a block without a tail has type
    // () unless control never reaches its end. Returns `!` or `expected`.
    pub(super) fn check_branch(
        &mut self,
        block: &Block,
        expected: &TypeInternal,
    ) -> TypecheckerResult<TypeInternal> {
        let ty = self.check_block(block, Some(expected))?;
        if ty != *expected && ty != TypeInternal::Never {
            return Err(typechecker_error(
                block.span,
                format!("expected '{}', got '{}'", expected, ty),
            ));
        }
        Ok(ty)
    }

    // Checks a statement, reporting its errors; returns whether it diverges.
    fn check_stmt(&mut self, stmt: &Stmt) -> bool {
        match stmt {
            Stmt::Let(let_stmt) => self.check_let(let_stmt),
            Stmt::Expr(expr_stmt) => self.check_expr_stmt(expr_stmt),
        }
    }

    fn check_let(&mut self, let_stmt: &LetStmt) -> bool {
        // The binding's type and the initializer's actual type. After an
        // error the binding gets `!`, which avoids follow-up errors.
        let (binding_ty, actual) = match &let_stmt.ty {
            Some(annotation) => match self.resolve_type(annotation) {
                Ok(expected) => match self.check_expr(&let_stmt.init, &expected) {
                    Ok(actual) => (expected, actual),
                    Err(e) => {
                        self.errors.push(e);
                        (expected, TypeInternal::Unit)
                    }
                },
                Err(e) => {
                    self.errors.push(e);
                    (TypeInternal::Never, TypeInternal::Unit)
                }
            },
            None => match self.synth_expr(&let_stmt.init) {
                Ok(ty) => (ty.clone(), ty),
                Err(e) => {
                    self.errors.push(e);
                    (TypeInternal::Never, TypeInternal::Unit)
                }
            },
        };
        self.bind_pattern(&let_stmt.pattern, &binding_ty);
        actual == TypeInternal::Never
    }

    fn check_expr_stmt(&mut self, expr_stmt: &ExprStmt) -> bool {
        // A block-like statement without `;` must have type ().
        let result = if expr_stmt.has_semi {
            self.synth_expr(&expr_stmt.expr)
        } else {
            self.check_expr(&expr_stmt.expr, &TypeInternal::Unit)
        };
        match result {
            Ok(ty) => ty == TypeInternal::Never,
            Err(e) => {
                self.errors.push(e);
                false
            }
        }
    }

    pub(super) fn bind_pattern(&mut self, pattern: &Pattern, ty: &TypeInternal) {
        match &pattern.kind {
            PatternKind::Wildcard => {}
            PatternKind::Binding { name, mutable } => {
                let info = VarInfo {
                    ty: ty.clone(),
                    mutable: *mutable,
                    is_param: false,
                };
                self.env.define(name.clone(), info);
            }
            PatternKind::Tuple(patterns) => match ty {
                TypeInternal::Tuple(elems) if elems.len() == patterns.len() => {
                    for (pattern, elem_ty) in patterns.iter().zip(elems) {
                        self.bind_pattern(pattern, elem_ty);
                    }
                }
                TypeInternal::Never => {
                    for pattern in patterns {
                        self.bind_pattern(pattern, &TypeInternal::Never);
                    }
                }
                _ => self.errors.push(typechecker_error(
                    pattern.span,
                    format!(
                        "a tuple pattern with {} elements cannot bind a value of type '{}'",
                        patterns.len(),
                        ty
                    ),
                )),
            },
        }
    }
}
