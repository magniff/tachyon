// Compile-time evaluation: constants, static initializers and array
// lengths. Expressions are type checked first, then evaluated with the
// machine's wrapping semantics.

use super::env::TypingEnvironment;
use super::{
    ConstInfo, ConstValue, TypeInternal, Typechecker, TypecheckerError, TypecheckerResult,
    typechecker_error,
};
use crate::parser::{BinOp, Expr, ExprKind, FieldInit, LitValue, UnaryOp};

fn not_constant(expr: &Expr) -> TypecheckerError {
    typechecker_error(
        expr.span,
        "expression is not a compile-time constant".to_string(),
    )
}

impl Typechecker<'_> {
    // The value of a named constant, evaluated on first use.
    pub(super) fn const_value(&mut self, name: &str) -> TypecheckerResult<ConstValue> {
        if let Some(info) = self.consts.get(name) {
            return Ok(info.value.clone());
        }
        let decl = self.const_decls[name];
        let Some(ty) = self.const_types.get(name).cloned() else {
            // Its type failed to resolve; that error is already reported.
            return Ok(ConstValue::Int(0));
        };
        if !self.evaluating_consts.insert(name.to_string()) {
            return Err(typechecker_error(
                decl.name.1,
                format!("constant '{}' is defined in terms of itself", name),
            ));
        }
        let value = self.eval_const_expr(&decl.value, &ty);
        self.evaluating_consts.remove(name);
        let value = value?;
        let info = ConstInfo {
            ty,
            value: value.clone(),
        };
        self.consts.insert(name.to_string(), info);
        Ok(value)
    }

    // Type checks `expr` against `ty` outside of any function, then
    // evaluates it.
    pub(super) fn eval_const_expr(
        &mut self,
        expr: &Expr,
        ty: &TypeInternal,
    ) -> TypecheckerResult<ConstValue> {
        self.in_const_context(|tc| {
            tc.check_expr(expr, ty)?;
            tc.const_eval(expr)
        })
    }

    // An array length: a constant, non-negative integer expression.
    pub(super) fn eval_array_len(&mut self, expr: &Expr) -> TypecheckerResult<u64> {
        let value = self.in_const_context(|tc| {
            let ty = tc.synth_expr(expr)?;
            if !ty.is_integer() {
                return Err(typechecker_error(
                    expr.span,
                    format!("array length must be an integer, got '{}'", ty),
                ));
            }
            tc.const_eval(expr)
        })?;
        match value {
            ConstValue::Int(len) if len >= 0 => Ok(len as u64),
            _ => Err(typechecker_error(
                expr.span,
                "array length must not be negative".to_string(),
            )),
        }
    }

    // Runs `f` outside of the function being checked: no locals, no loops.
    fn in_const_context<T>(&mut self, f: impl FnOnce(&mut Self) -> T) -> T {
        let env = std::mem::replace(&mut self.env, TypingEnvironment::new());
        let return_ty = std::mem::replace(&mut self.return_ty, TypeInternal::Unit);
        let loops = std::mem::take(&mut self.loops);
        let result = f(self);
        self.env = env;
        self.return_ty = return_ty;
        self.loops = loops;
        result
    }

    // The type the checker recorded for a sub-expression of a checked
    // constant expression.
    fn checked_type(&self, expr: &Expr) -> TypeInternal {
        self.recorded_type(expr)
            .cloned()
            .expect("constant sub-expressions are type checked before evaluation")
    }

    // Evaluates a type-checked constant expression.
    fn const_eval(&mut self, expr: &Expr) -> TypecheckerResult<ConstValue> {
        let ty = self
            .recorded_type(expr)
            .cloned()
            .unwrap_or(TypeInternal::Unit);
        let int = |v: i128| ConstValue::Int(wrap_int(v, &ty));
        Ok(match &expr.kind {
            ExprKind::IntLiteral(v) => int(*v as i128),
            ExprKind::CharLiteral(v) => int(*v as i128),
            ExprKind::SuffixedLiteral(LitValue::Int(v), suffix) if !suffix.is_float() => {
                int(*v as i128)
            }
            ExprKind::SuffixedLiteral(LitValue::Int(v), _) => float_const(*v as f64, &ty),
            ExprKind::FloatLiteral(f) | ExprKind::SuffixedLiteral(LitValue::Float(f), _) => {
                float_const(**f, &ty)
            }
            ExprKind::BoolLiteral(b) => ConstValue::Bool(*b),
            ExprKind::UnitLiteral => ConstValue::Aggregate(Vec::new()),
            ExprKind::Ident(name) => self.const_eval_name(name, expr)?,
            ExprKind::UnaryOp { op, expr: operand } => {
                let value = self.const_eval(operand)?;
                const_unary(*op, value, &ty).ok_or_else(|| not_constant(expr))?
            }
            ExprKind::BinOp { op, lhs, rhs } => self.const_eval_binop(*op, lhs, rhs, &ty, expr)?,
            ExprKind::Cast { expr: operand, .. } => {
                let value = self.const_eval(operand)?;
                const_cast(value, &ty).ok_or_else(|| not_constant(expr))?
            }
            ExprKind::Tuple(elems) | ExprKind::Array(elems) => ConstValue::Aggregate(
                elems
                    .iter()
                    .map(|elem| self.const_eval(elem))
                    .collect::<TypecheckerResult<_>>()?,
            ),
            ExprKind::ArrayRepeat(value, _) => {
                let TypeInternal::Array(_, len) = ty else {
                    return Err(not_constant(expr));
                };
                let value = self.const_eval(value)?;
                ConstValue::Aggregate(vec![value; len as usize])
            }
            ExprKind::StructConstructor { name, fields } => {
                self.const_eval_struct(&name.0, fields)?
            }
            _ => return Err(not_constant(expr)),
        })
    }

    // A name in a constant expression must name a constant.
    fn const_eval_name(&mut self, name: &str, expr: &Expr) -> TypecheckerResult<ConstValue> {
        if self.env.lookup(name).is_none() && self.const_decls.contains_key(name) {
            self.const_value(name)
        } else {
            Err(typechecker_error(
                expr.span,
                format!("'{}' is not a constant", name),
            ))
        }
    }

    fn const_eval_binop(
        &mut self,
        op: BinOp,
        lhs: &Expr,
        rhs: &Expr,
        result_ty: &TypeInternal,
        expr: &Expr,
    ) -> TypecheckerResult<ConstValue> {
        let operand_ty = self.checked_type(lhs);
        let lhs_value = self.const_eval(lhs)?;
        // && and || short-circuit
        match (op, &lhs_value) {
            (BinOp::And, ConstValue::Bool(false)) => return Ok(ConstValue::Bool(false)),
            (BinOp::Or, ConstValue::Bool(true)) => return Ok(ConstValue::Bool(true)),
            _ => {}
        }
        let rhs_value = self.const_eval(rhs)?;
        const_binop(op, lhs_value, rhs_value, &operand_ty, result_ty)
            .map_err(|message| typechecker_error(expr.span, message))
    }

    // Field values in declaration order.
    fn const_eval_struct(
        &mut self,
        struct_name: &str,
        fields: &[FieldInit],
    ) -> TypecheckerResult<ConstValue> {
        let info = self.structs[struct_name].clone();
        let mut values = Vec::new();
        for (field_name, _) in &info.fields {
            let field = fields
                .iter()
                .find(|field| &field.name.0 == field_name)
                .expect("the checker rejects struct literals with missing fields");
            values.push(self.const_eval(&field.value)?);
        }
        Ok(ConstValue::Aggregate(values))
    }
}

// Wraps an integer to the width (and signedness) of `ty`.
fn wrap_int(value: i128, ty: &TypeInternal) -> i128 {
    let bits = ty.int_bits();
    let masked = (value as u128) & ((1u128 << bits) - 1);
    if ty.is_signed() && masked >> (bits - 1) == 1 {
        masked as i128 - (1i128 << bits)
    } else {
        masked as i128
    }
}

// A float constant, rounded to f32 precision for f32.
fn float_const(value: f64, ty: &TypeInternal) -> ConstValue {
    ConstValue::Float(if *ty == TypeInternal::F32 {
        value as f32 as f64
    } else {
        value
    })
}

fn const_unary(op: UnaryOp, value: ConstValue, ty: &TypeInternal) -> Option<ConstValue> {
    Some(match (op, value) {
        (UnaryOp::Neg, ConstValue::Int(v)) => ConstValue::Int(wrap_int(v.wrapping_neg(), ty)),
        (UnaryOp::Neg, ConstValue::Float(f)) => float_const(-f, ty),
        (UnaryOp::Not, ConstValue::Bool(b)) => ConstValue::Bool(!b),
        (UnaryOp::BitNot, ConstValue::Int(v)) => ConstValue::Int(wrap_int(!v, ty)),
        _ => return None,
    })
}

// A binary operator on constants with operands of type `operand_ty` and a
// result of type `result_ty`; Err is a message.
fn const_binop(
    op: BinOp,
    lhs: ConstValue,
    rhs: ConstValue,
    operand_ty: &TypeInternal,
    result_ty: &TypeInternal,
) -> Result<ConstValue, String> {
    match (lhs, rhs) {
        (ConstValue::Int(a), ConstValue::Int(b)) => int_binop(op, a, b, operand_ty, result_ty),
        (ConstValue::Float(a), ConstValue::Float(b)) => float_binop(op, a, b, result_ty),
        (ConstValue::Bool(a), ConstValue::Bool(b)) => bool_binop(op, a, b),
        _ => Err("expression is not a compile-time constant".to_string()),
    }
}

fn int_binop(
    op: BinOp,
    a: i128,
    b: i128,
    operand_ty: &TypeInternal,
    result_ty: &TypeInternal,
) -> Result<ConstValue, String> {
    let wrap = |v: i128| ConstValue::Int(wrap_int(v, result_ty));
    // The shift amount is taken modulo the width, as the machine does.
    let shift_amount = || b as u32 % operand_ty.int_bits();
    // Unsigned operands are kept non-negative, so i128 arithmetic matches
    // the machine's after wrapping.
    Ok(match op {
        BinOp::Add => wrap(a + b),
        BinOp::Sub => wrap(a - b),
        BinOp::Mul => wrap(a.wrapping_mul(b)),
        BinOp::Div | BinOp::Mod if b == 0 => {
            return Err("division by zero in constant expression".to_string());
        }
        BinOp::Div => wrap(a / b),
        BinOp::Mod => wrap(a % b),
        BinOp::BitAnd => wrap(a & b),
        BinOp::BitOr => wrap(a | b),
        BinOp::BitXor => wrap(a ^ b),
        BinOp::Shl => wrap(a << shift_amount()),
        BinOp::Shr => wrap(a >> shift_amount()),
        BinOp::Eq => ConstValue::Bool(a == b),
        BinOp::Neq => ConstValue::Bool(a != b),
        BinOp::Lt => ConstValue::Bool(a < b),
        BinOp::Gt => ConstValue::Bool(a > b),
        BinOp::LtEq => ConstValue::Bool(a <= b),
        BinOp::GtEq => ConstValue::Bool(a >= b),
        BinOp::And | BinOp::Or => unreachable!("logical operators take bool operands"),
    })
}

fn float_binop(op: BinOp, a: f64, b: f64, result_ty: &TypeInternal) -> Result<ConstValue, String> {
    let float = |v: f64| float_const(v, result_ty);
    Ok(match op {
        BinOp::Add => float(a + b),
        BinOp::Sub => float(a - b),
        BinOp::Mul => float(a * b),
        BinOp::Div => float(a / b),
        BinOp::Mod => float(a % b),
        BinOp::Eq => ConstValue::Bool(a == b),
        BinOp::Neq => ConstValue::Bool(a != b),
        BinOp::Lt => ConstValue::Bool(a < b),
        BinOp::Gt => ConstValue::Bool(a > b),
        BinOp::LtEq => ConstValue::Bool(a <= b),
        BinOp::GtEq => ConstValue::Bool(a >= b),
        _ => return Err("invalid operator on floats".to_string()),
    })
}

fn bool_binop(op: BinOp, a: bool, b: bool) -> Result<ConstValue, String> {
    Ok(ConstValue::Bool(match op {
        BinOp::And => a && b,
        BinOp::Or => a || b,
        BinOp::Eq => a == b,
        BinOp::Neq => a != b,
        _ => return Err("invalid operator on bools".to_string()),
    }))
}

// `value as to`, or None when the cast is not a constant operation.
fn const_cast(value: ConstValue, to: &TypeInternal) -> Option<ConstValue> {
    let int_like = to.is_integer() || to.is_pointer();
    Some(match value {
        ConstValue::Int(v) if int_like => ConstValue::Int(wrap_int(v, to)),
        ConstValue::Int(v) if to.is_float() => float_const(v as f64, to),
        ConstValue::Float(f) if to.is_float() => float_const(f, to),
        ConstValue::Float(f) if to.is_integer() => ConstValue::Int(float_to_int(f, to)),
        ConstValue::Bool(b) if to.is_integer() => ConstValue::Int(b as i128),
        _ => return None,
    })
}

// Saturating, NaN to 0 (Rust `as` semantics).
fn float_to_int(value: f64, to: &TypeInternal) -> i128 {
    match to {
        TypeInternal::I8 => value as i8 as i128,
        TypeInternal::I16 => value as i16 as i128,
        TypeInternal::I32 => value as i32 as i128,
        TypeInternal::I64 => value as i64 as i128,
        TypeInternal::U8 => value as u8 as i128,
        TypeInternal::U16 => value as u16 as i128,
        TypeInternal::U32 => value as u32 as i128,
        _ => value as u64 as i128,
    }
}
