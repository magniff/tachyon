// Check mode: an expression against the type its context expects. The
// expected type flows into literals, aggregates, branches and arithmetic
// operands; everything else falls back to synth + compare.

use super::{TypeInternal, Typechecker, TypecheckerResult, typechecker_error};
use crate::lexer::span::Span;
use crate::parser::{BinOp, Block, Expr, ExprKind, FieldInit, Spanned, UnaryOp};

// Operators whose operands have the result's type when it is numeric
// (arithmetic) or an integer (bitwise).
fn passes_expected_to_operands(op: BinOp, expected: &TypeInternal) -> bool {
    match op {
        BinOp::Add | BinOp::Sub | BinOp::Mul | BinOp::Div | BinOp::Mod => expected.is_numeric(),
        BinOp::BitAnd | BinOp::BitOr | BinOp::BitXor => expected.is_integer(),
        _ => false,
    }
}

impl Typechecker<'_> {
    // On success the expression's type is recorded as `expected`, the type
    // it has in its context; the result is `expected`, or `!` when the
    // expression diverges.
    pub(super) fn check_expr(
        &mut self,
        expr: &Expr,
        expected: &TypeInternal,
    ) -> TypecheckerResult<TypeInternal> {
        let actual = self.check_expr_inner(expr, expected)?;
        self.record(expr, expected.clone(), &actual);
        Ok(actual)
    }

    fn check_expr_inner(
        &mut self,
        expr: &Expr,
        expected: &TypeInternal,
    ) -> TypecheckerResult<TypeInternal> {
        match (&expr.kind, expected) {
            (ExprKind::IntLiteral(value), _) if expected.is_integer() => {
                self.check_int_fits(*value, expected, expr.span)?;
            }
            (ExprKind::CharLiteral(value), _) if expected.is_integer() => {
                self.check_int_fits(*value as u64, expected, expr.span)?;
            }
            (ExprKind::FloatLiteral(_), _) if expected.is_float() => {}
            (ExprKind::Tuple(elems), TypeInternal::Tuple(expected_elems)) => {
                self.check_tuple(elems, expected_elems, expr.span)?;
            }
            (ExprKind::Array(elems), TypeInternal::Array(elem_ty, len)) => {
                self.check_array(elems, elem_ty, *len, expr.span)?;
            }
            (ExprKind::ArrayRepeat(value, count), TypeInternal::Array(elem_ty, len)) => {
                self.check_array_repeat(value, count, elem_ty, *len)?;
            }
            (ExprKind::StructConstructor { name, fields }, _) => {
                self.check_struct_literal(name, fields, expected, expr.span)?;
            }
            (
                ExprKind::If {
                    cond,
                    then_block,
                    else_block,
                },
                _,
            ) => return self.check_if(cond, then_block, else_block.as_ref(), expected, expr.span),
            (ExprKind::Block(block), _) => return self.check_branch(block, expected),
            // A `loop`'s breaks take the expected type.
            (ExprKind::Loop { label, body }, _) => {
                return self.check_loop(label, body, Some(expected));
            }
            // Literals among the operands take the expected type
            // (`let x: u8 = 1 + 2`).
            (ExprKind::BinOp { op, lhs, rhs }, _) if passes_expected_to_operands(*op, expected) => {
                self.check_expr(lhs, expected)?;
                self.check_expr(rhs, expected)?;
            }
            (
                ExprKind::BinOp {
                    op: BinOp::Shl | BinOp::Shr,
                    lhs,
                    rhs,
                },
                _,
            ) if expected.is_integer() => {
                self.check_expr(lhs, expected)?;
                self.check_shift_amount(rhs)?;
            }
            (
                ExprKind::UnaryOp {
                    op: UnaryOp::Neg,
                    expr: operand,
                },
                _,
            ) if expected.is_numeric() => self.check_negation(operand, expected, expr.span)?,
            (
                ExprKind::UnaryOp {
                    op: UnaryOp::BitNot,
                    expr: operand,
                },
                _,
            ) if expected.is_integer() => {
                self.check_expr(operand, expected)?;
            }
            _ => return self.synth_and_compare(expr, expected),
        }
        Ok(expected.clone())
    }

    // Falls back to synthesizing the type and comparing it with the
    // expected one; `!` is accepted anywhere.
    fn synth_and_compare(
        &mut self,
        expr: &Expr,
        expected: &TypeInternal,
    ) -> TypecheckerResult<TypeInternal> {
        let actual = self.synth_expr(expr)?;
        if actual == TypeInternal::Never {
            return Ok(actual);
        }
        if actual != *expected {
            return Err(typechecker_error(
                expr.span,
                format!("expected '{}', got '{}'", expected, actual),
            ));
        }
        Ok(expected.clone())
    }

    fn check_tuple(
        &mut self,
        elems: &[Expr],
        expected_elems: &[TypeInternal],
        span: Span,
    ) -> TypecheckerResult<()> {
        if elems.len() != expected_elems.len() {
            return Err(typechecker_error(
                span,
                format!(
                    "tuple has {} elements, expected {}",
                    elems.len(),
                    expected_elems.len()
                ),
            ));
        }
        for (elem, expected) in elems.iter().zip(expected_elems) {
            self.check_expr(elem, expected)?;
        }
        Ok(())
    }

    fn check_array(
        &mut self,
        elems: &[Expr],
        elem_ty: &TypeInternal,
        len: u64,
        span: Span,
    ) -> TypecheckerResult<()> {
        if elems.len() as u64 != len {
            return Err(typechecker_error(
                span,
                format!("array has {} elements, expected {}", elems.len(), len),
            ));
        }
        for elem in elems {
            self.check_expr(elem, elem_ty)?;
        }
        Ok(())
    }

    // `[value; count]`
    fn check_array_repeat(
        &mut self,
        value: &Expr,
        count: &Expr,
        elem_ty: &TypeInternal,
        len: u64,
    ) -> TypecheckerResult<()> {
        self.check_expr(value, elem_ty)?;
        let count_value = self.eval_array_len(count)?;
        if count_value != len {
            return Err(typechecker_error(
                count.span,
                format!("array repeat count is {}, expected {}", count_value, len),
            ));
        }
        Ok(())
    }

    fn check_struct_literal(
        &mut self,
        name: &Spanned<String>,
        fields: &[FieldInit],
        expected: &TypeInternal,
        span: Span,
    ) -> TypecheckerResult<()> {
        if let TypeInternal::Struct(expected_name) = expected
            && *expected_name != name.0
        {
            return Err(typechecker_error(
                span,
                format!(
                    "expected struct '{}', got constructor for '{}'",
                    expected_name, name.0
                ),
            ));
        }
        self.check_struct_fields(&name.0, name.1, fields, span)?;
        let actual = TypeInternal::Struct(name.0.clone());
        if actual != *expected {
            return Err(typechecker_error(
                span,
                format!("expected '{}', got '{}'", expected, actual),
            ));
        }
        Ok(())
    }

    // Both branches take the expected type; without `else` it must be ().
    fn check_if(
        &mut self,
        cond: &Expr,
        then_block: &Block,
        else_block: Option<&Block>,
        expected: &TypeInternal,
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        self.check_expr(cond, &TypeInternal::Bool)?;
        let Some(else_block) = else_block else {
            if *expected != TypeInternal::Unit {
                return Err(typechecker_error(
                    span,
                    format!(
                        "if without else must have type '()', expected '{}'",
                        expected
                    ),
                ));
            }
            self.check_branch(then_block, &TypeInternal::Unit)?;
            return Ok(expected.clone());
        };
        let then_ty = self.check_branch(then_block, expected)?;
        let else_ty = self.check_branch(else_block, expected)?;
        if then_ty == TypeInternal::Never && else_ty == TypeInternal::Never {
            Ok(TypeInternal::Never)
        } else {
            Ok(expected.clone())
        }
    }

    // `-x` against a numeric type. `-128` fits i8 although `128` does not.
    fn check_negation(
        &mut self,
        operand: &Expr,
        expected: &TypeInternal,
        span: Span,
    ) -> TypecheckerResult<()> {
        if let ExprKind::IntLiteral(value) = &operand.kind
            && expected.is_signed()
        {
            self.check_int_fits(value.saturating_sub(1), expected, span)
                .map_err(|_| {
                    typechecker_error(
                        span,
                        format!(
                            "integer literal -{} does not fit in type '{}'",
                            value, expected
                        ),
                    )
                })?;
            self.record_type(operand, expected.clone());
            return Ok(());
        }
        self.check_expr(operand, expected)?;
        Ok(())
    }

    // The amount of a shift may be an integer of any width.
    pub(super) fn check_shift_amount(&mut self, amount: &Expr) -> TypecheckerResult<()> {
        let amount_ty = self.synth_expr(amount)?;
        if !amount_ty.is_integer() {
            return Err(typechecker_error(
                amount.span,
                format!("shift amount must be integer, got '{}'", amount_ty),
            ));
        }
        Ok(())
    }

    // An integer literal's value must fit its type.
    pub(super) fn check_int_fits(
        &self,
        value: u64,
        ty: &TypeInternal,
        span: Span,
    ) -> TypecheckerResult<()> {
        if ty.int_max().is_some_and(|max| value <= max) {
            Ok(())
        } else {
            Err(typechecker_error(
                span,
                format!("integer literal {} does not fit in type '{}'", value, ty),
            ))
        }
    }
}
