// Places (locations that can be assigned to or have their address taken),
// assignments and mutability.

use super::{Typechecker, TypecheckerError, TypecheckerResult, typechecker_error};
use crate::lexer::span::Span;
use crate::parser::{AssignOp, BinOp, Expr, ExprKind, UnaryOp};

impl Typechecker<'_> {
    pub(super) fn check_assign(
        &mut self,
        op: AssignOp,
        target: &Expr,
        value: &Expr,
        span: Span,
    ) -> TypecheckerResult<()> {
        let target_ty = self.synth_expr(target)?;
        if !self.is_place(target) {
            return Err(self.not_assignable_error(target));
        }
        self.check_mutable_place(target)?;
        let Some(op) = op.binop() else {
            self.check_expr(value, &target_ty)?;
            return Ok(());
        };
        let (allowed, kind) = match op {
            BinOp::Shl | BinOp::Shr => (
                target_ty.is_integer(),
                "shift assignment requires integer type",
            ),
            BinOp::BitAnd | BinOp::BitOr | BinOp::BitXor => (
                target_ty.is_integer(),
                "bitwise assignment requires integer type",
            ),
            _ => (
                target_ty.is_numeric(),
                "compound assignment requires numeric type",
            ),
        };
        if !allowed {
            return Err(typechecker_error(
                span,
                format!("{}, got '{}'", kind, target_ty),
            ));
        }
        if matches!(op, BinOp::Shl | BinOp::Shr) {
            self.check_shift_amount(value)
        } else {
            self.check_expr(value, &target_ty).map(|_| ())
        }
    }

    fn not_assignable_error(&self, target: &Expr) -> TypecheckerError {
        let message = match &target.kind {
            ExprKind::Ident(name) if self.const_types.contains_key(name) => {
                format!("cannot assign to constant '{}'", name)
            }
            ExprKind::Ident(name) if self.signatures.contains_key(name) => {
                format!("cannot assign to function '{}'", name)
            }
            _ => "invalid assignment target".to_string(),
        };
        typechecker_error(target.span, message)
    }

    // Whether `expr` has already been given a pointer type.
    fn is_pointer_valued(&self, expr: &Expr) -> bool {
        self.recorded_type(expr).is_some_and(|ty| ty.is_pointer())
    }

    // A location that can be assigned to or have its address taken:
    // variables, statics, `*p`, `p[i]`, and fields/elements of places.
    pub(super) fn is_place(&self, expr: &Expr) -> bool {
        match &expr.kind {
            ExprKind::Ident(name) => {
                self.env.lookup(name).is_some() || self.statics.contains_key(name)
            }
            ExprKind::UnaryOp {
                op: UnaryOp::Deref, ..
            } => true,
            ExprKind::Field { expr: base, .. } | ExprKind::TupleField { expr: base, .. } => {
                self.is_place(base)
            }
            ExprKind::Index { expr: base, .. } => {
                self.is_pointer_valued(base) || self.is_place(base)
            }
            _ => false,
        }
    }

    // Writes through a place must start from a `mut` binding or a `static
    // mut`; writes through pointers (`*p`, `p[i]`) are not checked.
    fn check_mutable_place(&self, target: &Expr) -> TypecheckerResult<()> {
        let mut root = target;
        loop {
            match &root.kind {
                ExprKind::Field { expr: base, .. } | ExprKind::TupleField { expr: base, .. } => {
                    root = base
                }
                ExprKind::Index { expr: base, .. } if !self.is_pointer_valued(base) => root = base,
                ExprKind::Ident(name) => return self.check_mutable_name(name, target.span),
                _ => return Ok(()),
            }
        }
    }

    // `name` is the variable or static a write goes to.
    fn check_mutable_name(&self, name: &str, span: Span) -> TypecheckerResult<()> {
        if let Some(var) = self.env.lookup(name) {
            if var.mutable {
                return Ok(());
            }
            let help = if var.is_param {
                format!("make the parameter mutable: `mut {}: {}`", name, var.ty)
            } else {
                format!("make it mutable: `let mut {}`", name)
            };
            return Err(TypecheckerError {
                message: format!("cannot assign to immutable variable '{}'", name),
                span,
                help: Some(help),
            });
        }
        if let Some(info) = self.statics.get(name)
            && !info.mutable
        {
            return Err(TypecheckerError {
                message: format!("cannot assign to immutable static '{}'", name),
                span,
                help: Some(format!("declare it `static mut {}`", name)),
            });
        }
        Ok(())
    }
}
