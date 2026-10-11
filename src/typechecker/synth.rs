// Synth mode: the type of an expression from the expression alone.

use std::collections::HashMap;

use super::types::{string_type, suffix_type};
use super::{
    FnSig, TypeInternal, Typechecker, TypecheckerResult, literal_takes_rhs_type, typechecker_error,
};
use crate::lexer::{span::Span, token::NumSuffix};
use crate::parser::{BinOp, Block, Expr, ExprKind, FieldInit, LitValue, Type, UnaryOp};

// Values C can receive as variadic arguments.
fn is_variadic_arg_type(ty: &TypeInternal) -> bool {
    ty.is_numeric()
        || matches!(
            ty,
            TypeInternal::Bool | TypeInternal::Pointer(_) | TypeInternal::Fn { .. }
        )
}

fn is_valid_cast(from: &TypeInternal, to: &TypeInternal) -> bool {
    match (from, to) {
        // Between numbers of any kind.
        (from, to) if from.is_numeric() && to.is_numeric() => true,
        // Between pointers, and between pointers and integers.
        (TypeInternal::Pointer(_), TypeInternal::Pointer(_)) => true,
        (from, TypeInternal::Pointer(_)) if from.is_integer() => true,
        (TypeInternal::Pointer(_), to) if to.is_integer() => true,
        (TypeInternal::Bool, to) if to.is_integer() => true,
        (TypeInternal::Never, _) => true,
        _ => false,
    }
}

impl Typechecker<'_> {
    pub(super) fn synth_expr(&mut self, expr: &Expr) -> TypecheckerResult<TypeInternal> {
        let ty = self.synth_expr_inner(expr)?;
        self.record(expr, ty.clone(), &ty);
        Ok(ty)
    }

    fn synth_expr_inner(&mut self, expr: &Expr) -> TypecheckerResult<TypeInternal> {
        let span = expr.span;
        match &expr.kind {
            // Already reported by the parser.
            ExprKind::Error => Ok(TypeInternal::Never),
            // Untyped literals default to i64, u8 (characters) and f64.
            ExprKind::IntLiteral(_) => Ok(TypeInternal::I64),
            ExprKind::CharLiteral(_) => Ok(TypeInternal::U8),
            ExprKind::FloatLiteral(_) => Ok(TypeInternal::F64),
            ExprKind::SuffixedLiteral(value, suffix) => {
                self.suffixed_literal(*value, *suffix, false, span)
            }
            ExprKind::BoolLiteral(_) => Ok(TypeInternal::Bool),
            ExprKind::UnitLiteral => Ok(TypeInternal::Unit),
            ExprKind::StringLiteral(_) => Ok(string_type()),
            ExprKind::CStringLiteral(_) => Ok(TypeInternal::U8.pointer_to()),
            ExprKind::Ident(name) => self.synth_name(name, span),
            ExprKind::BinOp { op, lhs, rhs } => self.synth_binop(*op, lhs, rhs, span),
            ExprKind::UnaryOp { op, expr: operand } => self.synth_unaryop(*op, operand, span),
            ExprKind::Cast { expr: operand, ty } => self.synth_cast(operand, ty),
            ExprKind::Call { callee, args } => self.synth_call(callee, args, span),
            ExprKind::Index { expr: base, index } => self.synth_index(base, index),
            ExprKind::Field { expr: base, name } => {
                let base_ty = self.synth_expr(base)?;
                self.field_type(&base_ty, &name.0, span)
            }
            ExprKind::TupleField { expr: base, index } => {
                let base_ty = self.synth_expr(base)?;
                tuple_field_type(&base_ty, index.0 as usize, span)
            }
            ExprKind::Tuple(elems) => {
                let elem_types = elems
                    .iter()
                    .map(|elem| self.synth_expr(elem))
                    .collect::<TypecheckerResult<_>>()?;
                Ok(TypeInternal::Tuple(elem_types))
            }
            ExprKind::Array(elems) => self.synth_array(elems, span),
            ExprKind::ArrayRepeat(value, count) => {
                let elem_ty = self.synth_expr(value)?;
                let len = self.eval_array_len(count)?;
                Ok(TypeInternal::Array(Box::new(elem_ty), len))
            }
            ExprKind::StructConstructor { name, fields } => {
                self.check_struct_fields(&name.0, name.1, fields, span)?;
                Ok(TypeInternal::Struct(name.0.clone()))
            }
            ExprKind::Block(block) => self.check_block(block, None),
            ExprKind::If {
                cond,
                then_block,
                else_block,
            } => self.synth_if(cond, then_block, else_block.as_ref(), span),
            ExprKind::Loop { label, body } => self.check_loop(label, body, None),
            ExprKind::While { label, cond, body } => self.check_while(label, cond, body),
            ExprKind::For {
                label,
                pattern,
                iter,
                body,
            } => self.check_for(label, pattern, iter, body),
            ExprKind::Range { .. } => Err(typechecker_error(
                span,
                "ranges can only be used as the bounds of a 'for' loop".to_string(),
            )),
            ExprKind::Assign { op, target, value } => {
                self.check_assign(*op, target, value, span)?;
                Ok(TypeInternal::Unit)
            }
            ExprKind::Return(value) => self.check_return(value.as_deref(), span),
            ExprKind::Break { label, value } => {
                self.check_break(label, value.as_deref(), span)?;
                Ok(TypeInternal::Never)
            }
            ExprKind::Continue { label } => {
                self.find_loop(label, "continue", span)?;
                Ok(TypeInternal::Never)
            }
        }
    }

    // `operand as ty`
    fn synth_cast(&mut self, operand: &Expr, ty: &Type) -> TypecheckerResult<TypeInternal> {
        let from = self.synth_expr(operand)?;
        let to = self.resolve_type(ty)?;
        if !is_valid_cast(&from, &to) {
            return Err(typechecker_error(
                operand.span,
                format!("cannot cast '{}' to '{}'", from, to),
            ));
        }
        Ok(to)
    }

    // Type of `1u8`, `2.5f32`; `negated` allows `-128i8`.
    fn suffixed_literal(
        &mut self,
        value: LitValue,
        suffix: NumSuffix,
        negated: bool,
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        let ty = suffix_type(suffix);
        if let LitValue::Int(value) = value
            && ty.is_integer()
        {
            let magnitude_limit = if negated && ty.is_signed() {
                value.saturating_sub(1)
            } else {
                value
            };
            self.check_int_fits(magnitude_limit, &ty, span)
                .map_err(|_| {
                    typechecker_error(
                        span,
                        format!(
                            "integer literal {}{} does not fit in type '{}'",
                            if negated { "-" } else { "" },
                            value,
                            ty
                        ),
                    )
                })?;
        }
        Ok(ty)
    }

    // A variable, constant, static or function used as a value.
    fn synth_name(&mut self, name: &str, span: Span) -> TypecheckerResult<TypeInternal> {
        if let Some(var) = self.env.lookup(name) {
            return Ok(var.ty.clone());
        }
        if let Some(ty) = self.const_types.get(name) {
            return Ok(ty.clone());
        }
        if let Some(info) = self.statics.get(name) {
            return Ok(info.ty.clone());
        }
        // A function used as a value has a function pointer type.
        match self.signatures.get(name) {
            Some(sig) if !sig.is_variadic => Ok(TypeInternal::Fn {
                params: sig.param_types(),
                result: Box::new(sig.return_ty.clone()),
            }),
            Some(_) => Err(typechecker_error(
                span,
                format!("variadic function '{}' cannot be used as a value", name),
            )),
            None => Err(typechecker_error(
                span,
                format!("undefined variable '{}'", name),
            )),
        }
    }

    // `base[index]` on an array or a pointer.
    fn synth_index(&mut self, base: &Expr, index: &Expr) -> TypecheckerResult<TypeInternal> {
        let base_ty = self.synth_expr(base)?;
        let elem_ty = match &base_ty {
            TypeInternal::Array(elem, _) | TypeInternal::Pointer(elem) => (**elem).clone(),
            _ => {
                return Err(typechecker_error(
                    base.span,
                    format!("cannot index type '{}'", base_ty),
                ));
            }
        };
        let index_ty = self.synth_expr(index)?;
        if !index_ty.is_integer() {
            return Err(typechecker_error(
                index.span,
                format!("index must be integer, got '{}'", index_ty),
            ));
        }
        Ok(elem_ty)
    }

    // The elements take the first one's type.
    fn synth_array(&mut self, elems: &[Expr], span: Span) -> TypecheckerResult<TypeInternal> {
        let Some((first, rest)) = elems.split_first() else {
            return Err(typechecker_error(
                span,
                "cannot infer the type of an empty array; annotate it".to_string(),
            ));
        };
        let elem_ty = self.synth_expr(first)?;
        for elem in rest {
            self.check_expr(elem, &elem_ty)?;
        }
        Ok(TypeInternal::Array(Box::new(elem_ty), elems.len() as u64))
    }

    // Without `else` the `if` has type (); with it, both branches must
    // agree unless one diverges.
    fn synth_if(
        &mut self,
        cond: &Expr,
        then_block: &Block,
        else_block: Option<&Block>,
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        self.check_expr(cond, &TypeInternal::Bool)?;
        let then_ty = self.check_block(then_block, None)?;
        let Some(else_block) = else_block else {
            if then_ty != TypeInternal::Unit && then_ty != TypeInternal::Never {
                return Err(typechecker_error(
                    span,
                    format!("if without else must have type '()', got '{}'", then_ty),
                ));
            }
            return Ok(TypeInternal::Unit);
        };
        let else_ty = self.check_block(else_block, None)?;
        if then_ty == TypeInternal::Never {
            Ok(else_ty)
        } else if else_ty == TypeInternal::Never || then_ty == else_ty {
            Ok(then_ty)
        } else {
            Err(typechecker_error(
                span,
                format!(
                    "if/else branches have different types: '{}' vs '{}'",
                    then_ty, else_ty
                ),
            ))
        }
    }

    // ---- Operators ----

    fn synth_binop(
        &mut self,
        op: BinOp,
        lhs: &Expr,
        rhs: &Expr,
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        if matches!(op, BinOp::Shl | BinOp::Shr) {
            return self.synth_shift(lhs, rhs, span);
        }
        let operand_ty = self.synth_operands(lhs, rhs)?;
        let (allowed, requirement) = match op {
            BinOp::Add | BinOp::Sub | BinOp::Mul | BinOp::Div | BinOp::Mod => (
                operand_ty.is_numeric(),
                "arithmetic operator requires numeric type",
            ),
            BinOp::Lt | BinOp::Gt | BinOp::LtEq | BinOp::GtEq => (
                operand_ty.is_numeric() || operand_ty.is_pointer(),
                "comparison requires numeric type",
            ),
            BinOp::Eq | BinOp::Neq => (
                operand_ty.is_numeric()
                    || operand_ty == TypeInternal::Bool
                    || operand_ty.is_pointer()
                    || matches!(operand_ty, TypeInternal::Fn { .. }),
                "equality requires numeric, bool, or pointer type",
            ),
            BinOp::And | BinOp::Or => (
                operand_ty == TypeInternal::Bool,
                "logical operator requires bool",
            ),
            BinOp::BitAnd | BinOp::BitOr | BinOp::BitXor => (
                operand_ty.is_integer(),
                "bitwise operator requires integer type",
            ),
            BinOp::Shl | BinOp::Shr => unreachable!("shifts are handled above"),
        };
        if !allowed {
            return Err(typechecker_error(
                span,
                format!("{}, got '{}'", requirement, operand_ty),
            ));
        }
        if op.is_comparison() || matches!(op, BinOp::And | BinOp::Or) {
            Ok(TypeInternal::Bool)
        } else {
            Ok(operand_ty)
        }
    }

    // The common type of a non-shift operator's operands: one operand is
    // checked against the other's type so literals pick up the right type,
    // whichever side they are on.
    fn synth_operands(&mut self, lhs: &Expr, rhs: &Expr) -> TypecheckerResult<TypeInternal> {
        if literal_takes_rhs_type(lhs, rhs) {
            let rhs_ty = self.synth_expr(rhs)?;
            self.check_expr(lhs, &rhs_ty)?;
            Ok(rhs_ty)
        } else {
            let lhs_ty = self.synth_expr(lhs)?;
            self.check_expr(rhs, &lhs_ty)?;
            Ok(lhs_ty)
        }
    }

    // The amount's type is independent of the value's (`u64 << u8`).
    fn synth_shift(
        &mut self,
        lhs: &Expr,
        rhs: &Expr,
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        let value_ty = self.synth_expr(lhs)?;
        let amount_ty = self.synth_expr(rhs)?;
        if !value_ty.is_integer() {
            return Err(typechecker_error(
                span,
                format!("shift operator requires integer type, got '{}'", value_ty),
            ));
        }
        if !amount_ty.is_integer() {
            return Err(typechecker_error(
                span,
                format!("shift amount must be integer, got '{}'", amount_ty),
            ));
        }
        Ok(value_ty)
    }

    fn synth_unaryop(
        &mut self,
        op: UnaryOp,
        operand: &Expr,
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        match op {
            UnaryOp::Neg => {
                let ty = self.synth_negated(operand, span)?;
                if !ty.is_numeric() {
                    return Err(typechecker_error(
                        span,
                        format!("unary '-' requires numeric type, got '{}'", ty),
                    ));
                }
                Ok(ty)
            }
            UnaryOp::Not => {
                self.check_expr(operand, &TypeInternal::Bool)?;
                Ok(TypeInternal::Bool)
            }
            UnaryOp::BitNot => {
                let ty = self.synth_expr(operand)?;
                if !ty.is_integer() {
                    return Err(typechecker_error(
                        span,
                        format!("bitwise NOT requires integer type, got '{}'", ty),
                    ));
                }
                Ok(ty)
            }
            UnaryOp::Deref => match self.synth_expr(operand)? {
                TypeInternal::Pointer(pointee) => Ok(*pointee),
                ty => Err(typechecker_error(
                    span,
                    format!("cannot deref non-pointer type '{}'", ty),
                )),
            },
            UnaryOp::AddrOf => {
                let ty = self.synth_expr(operand)?;
                if !self.is_place(operand) {
                    return Err(typechecker_error(
                        span,
                        "cannot take address of non-lvalue expression".to_string(),
                    ));
                }
                Ok(ty.pointer_to())
            }
        }
    }

    // The type of the operand of `-`; `-128i8` fits although `128i8` does
    // not.
    fn synth_negated(&mut self, operand: &Expr, span: Span) -> TypecheckerResult<TypeInternal> {
        match &operand.kind {
            ExprKind::SuffixedLiteral(value, suffix) => {
                let ty = self.suffixed_literal(*value, *suffix, true, span)?;
                self.record_type(operand, ty.clone());
                Ok(ty)
            }
            _ => self.synth_expr(operand),
        }
    }

    // ---- Calls ----

    fn synth_call(
        &mut self,
        callee: &Expr,
        args: &[Expr],
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        // A direct call by name, unless a local shadows the function.
        if let ExprKind::Ident(name) = &callee.kind
            && self.env.lookup(name).is_none()
            && let Some(sig) = self.signatures.get(name).cloned()
        {
            return self.check_direct_call(&sig, args, span);
        }
        let callee_ty = self.synth_expr(callee)?;
        let TypeInternal::Fn { params, result } = &callee_ty else {
            return Err(typechecker_error(
                callee.span,
                format!("cannot call non-function type '{}'", callee_ty),
            ));
        };
        if args.len() != params.len() {
            return Err(typechecker_error(
                span,
                format!(
                    "function pointer expects {} arguments, got {}",
                    params.len(),
                    args.len()
                ),
            ));
        }
        for (arg, param_ty) in args.iter().zip(params) {
            self.check_expr(arg, param_ty)?;
        }
        Ok((**result).clone())
    }

    fn check_direct_call(
        &mut self,
        sig: &FnSig,
        args: &[Expr],
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        let arity_ok = if sig.is_variadic {
            args.len() >= sig.params.len()
        } else {
            args.len() == sig.params.len()
        };
        if !arity_ok {
            return Err(typechecker_error(
                span,
                format!(
                    "function '{}' expects {}{} arguments, got {}",
                    sig.name,
                    if sig.is_variadic { "at least " } else { "" },
                    sig.params.len(),
                    args.len()
                ),
            ));
        }
        for (arg, (_, param_ty)) in args.iter().zip(&sig.params) {
            self.check_expr(arg, param_ty)?;
        }
        // The variadic tail: C only receives scalars there.
        for arg in &args[sig.params.len()..] {
            let ty = self.synth_expr(arg)?;
            if !is_variadic_arg_type(&ty) {
                return Err(typechecker_error(
                    arg.span,
                    format!("cannot pass value of type '{}' as a variadic argument", ty),
                ));
            }
        }
        Ok(sig.return_ty.clone())
    }

    // ---- Structs ----

    // Checks the fields of `Name { ... }`: each field exactly once, with its
    // declared type. Field errors are reported without stopping.
    pub(super) fn check_struct_fields(
        &mut self,
        name: &str,
        name_span: Span,
        fields: &[FieldInit],
        span: Span,
    ) -> TypecheckerResult<()> {
        let info =
            self.structs.get(name).cloned().ok_or_else(|| {
                typechecker_error(name_span, format!("unknown struct '{}'", name))
            })?;

        let mut provided: HashMap<&str, &FieldInit> = HashMap::new();
        for field in fields {
            if provided.contains_key(field.name.0.as_str()) {
                self.errors.push(typechecker_error(
                    field.span,
                    format!("duplicate field '{}' in constructor", field.name.0),
                ));
                continue;
            }
            provided.insert(&field.name.0, field);
        }

        for (field_name, field_ty) in &info.fields {
            match provided.remove(field_name.as_str()) {
                Some(field) => {
                    if let Err(e) = self.check_expr(&field.value, field_ty) {
                        self.errors.push(e);
                    }
                }
                None => self.errors.push(typechecker_error(
                    span,
                    format!(
                        "missing field '{}' in struct '{}' constructor",
                        field_name, name
                    ),
                )),
            }
        }
        for (extra_name, field) in &provided {
            self.errors.push(typechecker_error(
                field.span,
                format!("unknown field '{}' in struct '{}'", extra_name, name),
            ));
        }
        Ok(())
    }

    fn field_type(
        &self,
        ty: &TypeInternal,
        field: &str,
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        let TypeInternal::Struct(name) = ty else {
            return Err(typechecker_error(
                span,
                format!("cannot access field '{}' on type '{}'", field, ty),
            ));
        };
        let info = self
            .structs
            .get(name)
            .ok_or_else(|| typechecker_error(span, format!("unknown struct '{}'", name)))?;
        info.field_ty(field).cloned().ok_or_else(|| {
            typechecker_error(span, format!("struct '{}' has no field '{}'", name, field))
        })
    }
}

fn tuple_field_type(
    ty: &TypeInternal,
    index: usize,
    span: Span,
) -> TypecheckerResult<TypeInternal> {
    let TypeInternal::Tuple(elems) = ty else {
        return Err(typechecker_error(
            span,
            format!("cannot use tuple index on type '{}'", ty),
        ));
    };
    elems.get(index).cloned().ok_or_else(|| {
        typechecker_error(
            span,
            format!(
                "tuple index {} out of range for tuple with {} elements",
                index,
                elems.len()
            ),
        )
    })
}
