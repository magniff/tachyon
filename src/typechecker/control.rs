// Loops, `break`, `continue` and `return`.

use super::env::{LoopContext, LoopKind};
use super::{
    TypeInternal, Typechecker, TypecheckerResult, literal_takes_rhs_type, typechecker_error,
};
use crate::lexer::span::Span;
use crate::parser::{Block, Expr, ExprKind, Pattern, PatternKind, Spanned};

type Label = Option<Spanned<String>>;

fn label_name(label: &Label) -> Option<String> {
    label.as_ref().map(|(name, _)| name.clone())
}

impl Typechecker<'_> {
    // Checks `body` as the body of the innermost loop `context`; returns the
    // context, updated by the body's `break`s.
    fn check_loop_body(
        &mut self,
        context: LoopContext,
        body: &Block,
    ) -> TypecheckerResult<LoopContext> {
        self.loops.push(context);
        let result = self.check_branch(body, &TypeInternal::Unit);
        let context = self.loops.pop().expect("pushed above");
        result.map(|_| context)
    }

    // A `loop`: its type is its breaks' type, or `!` without a break.
    pub(super) fn check_loop(
        &mut self,
        label: &Label,
        body: &Block,
        expected: Option<&TypeInternal>,
    ) -> TypecheckerResult<TypeInternal> {
        let context = LoopContext::new(label_name(label), LoopKind::Loop, expected.cloned());
        let context = self.check_loop_body(context, body)?;
        Ok(if context.has_break {
            context.break_ty.unwrap_or(TypeInternal::Unit)
        } else {
            TypeInternal::Never
        })
    }

    pub(super) fn check_while(
        &mut self,
        label: &Label,
        cond: &Expr,
        body: &Block,
    ) -> TypecheckerResult<TypeInternal> {
        self.check_expr(cond, &TypeInternal::Bool)?;
        let context = LoopContext::new(label_name(label), LoopKind::While, None);
        self.check_loop_body(context, body)?;
        Ok(TypeInternal::Unit)
    }

    // `for pattern in a..b { body }`
    pub(super) fn check_for(
        &mut self,
        label: &Label,
        pattern: &Pattern,
        iter: &Expr,
        body: &Block,
    ) -> TypecheckerResult<TypeInternal> {
        let elem_ty = self.check_range(iter)?;
        if let PatternKind::Tuple(_) = pattern.kind {
            return Err(typechecker_error(
                pattern.span,
                "a 'for' loop over a range binds one integer, not a tuple".to_string(),
            ));
        }
        self.env.push_scope();
        self.bind_pattern(pattern, &elem_ty);
        let context = LoopContext::new(label_name(label), LoopKind::For, None);
        let result = self.check_loop_body(context, body);
        self.env.pop_scope();
        result?;
        Ok(TypeInternal::Unit)
    }

    // The bounds of a `for` loop, `a..b` or `a..=b`: integers of one type,
    // which is recorded as the range's type and returned.
    fn check_range(&mut self, iter: &Expr) -> TypecheckerResult<TypeInternal> {
        let ExprKind::Range { start, end, .. } = &iter.kind else {
            return Err(typechecker_error(
                iter.span,
                "'for' loops can only iterate over integer ranges ('a..b' or 'a..=b')".to_string(),
            ));
        };
        let elem_ty = if literal_takes_rhs_type(start, end) {
            let ty = self.synth_expr(end)?;
            self.check_expr(start, &ty)?;
            ty
        } else {
            let ty = self.synth_expr(start)?;
            self.check_expr(end, &ty)?;
            ty
        };
        if !elem_ty.is_integer() {
            return Err(typechecker_error(
                iter.span,
                format!("range bounds must be integers, got '{}'", elem_ty),
            ));
        }
        self.record_type(iter, elem_ty.clone());
        Ok(elem_ty)
    }

    // The loop a `break`/`continue` refers to: the innermost, or the one
    // with the given label. Returns its index in `self.loops`.
    pub(super) fn find_loop(
        &self,
        label: &Label,
        keyword: &str,
        span: Span,
    ) -> TypecheckerResult<usize> {
        match label {
            None => self
                .loops
                .len()
                .checked_sub(1)
                .ok_or_else(|| typechecker_error(span, format!("{} outside of loop", keyword))),
            Some((name, label_span)) => self
                .loops
                .iter()
                .rposition(|context| context.label.as_deref() == Some(name.as_str()))
                .ok_or_else(|| {
                    typechecker_error(*label_span, format!("unknown loop label ':{}'", name))
                }),
        }
    }

    pub(super) fn check_break(
        &mut self,
        label: &Label,
        value: Option<&Expr>,
        span: Span,
    ) -> TypecheckerResult<()> {
        let index = self.find_loop(label, "break", span)?;
        match value {
            Some(value) => self.check_break_value(index, value)?,
            None => self.check_break_without_value(index, span)?,
        }
        self.loops[index].has_break = true;
        Ok(())
    }

    // `break value`: only a `loop` has a value; every break agrees on its
    // type.
    fn check_break_value(&mut self, loop_index: usize, value: &Expr) -> TypecheckerResult<()> {
        let kind = self.loops[loop_index].kind;
        if kind != LoopKind::Loop {
            return Err(typechecker_error(
                value.span,
                format!(
                    "'break' with a value is only allowed in 'loop', not in '{}'",
                    kind.keyword()
                ),
            ));
        }
        match self.loops[loop_index].break_ty.clone() {
            Some(break_ty) => {
                self.check_expr(value, &break_ty)?;
            }
            None => {
                let ty = self.synth_expr(value)?;
                if ty != TypeInternal::Never {
                    self.loops[loop_index].break_ty = Some(ty);
                }
            }
        }
        Ok(())
    }

    // A plain `break` gives the loop the value ().
    fn check_break_without_value(
        &mut self,
        loop_index: usize,
        span: Span,
    ) -> TypecheckerResult<()> {
        match &self.loops[loop_index].break_ty {
            Some(ty) if *ty != TypeInternal::Unit && *ty != TypeInternal::Never => {
                Err(typechecker_error(
                    span,
                    format!("expected '{}', got '()' (break without a value)", ty),
                ))
            }
            Some(_) => Ok(()),
            None => {
                self.loops[loop_index].break_ty = Some(TypeInternal::Unit);
                Ok(())
            }
        }
    }

    // `return [value]` has type `!`.
    pub(super) fn check_return(
        &mut self,
        value: Option<&Expr>,
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        let expected = self.return_ty.clone();
        match value {
            Some(value) => {
                self.check_expr(value, &expected)?;
            }
            None if expected != TypeInternal::Unit && expected != TypeInternal::Never => {
                return Err(typechecker_error(
                    span,
                    format!("empty return in function returning '{}'", expected),
                ));
            }
            None => {}
        }
        Ok(TypeInternal::Never)
    }
}
