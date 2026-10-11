// Bidirectional Type Checker
//
// Two-pass design:
//   Pass 1 — Collect all type, constant, struct and function declarations
//            into global environments. Detect duplicate names and
//            infinite-size structs. Resolve all AST types to TypeInternal
//            (array sizes and constants are evaluated at compile time).
//   Pass 2 — Check each function body using bidirectional type checking.
//
// Bidirectional modes:
//   synth(expr) -> Ty         Bottom-up inference
//   check(expr, expected: Ty) Top-down checking (falls back to synth + compare)
//
// Every expression's type (in its context) is recorded in a side table
// indexed by ExprId, which lowering reads instead of re-deriving types.
//
// `return`, `break`, `continue`, a `loop` without `break` and calls to
// functions returning `!` have the never type `!`, which coerces to every
// type; a block diverges when one of its statements does.
//
//   collect.rs   pass 1: declarations and type resolution
//   consts.rs    compile-time evaluation of constants
//   body.rs      pass 2: functions, blocks, statements, patterns
//   check.rs     check mode
//   synth.rs     synth mode
//   control.rs   loops, `break`, `continue`, `return`
//   place.rs     assignment, places and mutability

use std::collections::{HashMap, HashSet};
use std::fmt;

use crate::lexer::span::Span;
use crate::parser::{ConstDecl, Expr, ExprKind, Program, Type, UnaryOp};

mod body;
mod check;
mod collect;
mod consts;
mod control;
mod env;
mod place;
mod synth;
mod types;

use env::{LoopContext, TypingEnvironment};
pub use types::TypeInternal;

#[derive(Debug, Clone)]
pub struct TypecheckerError {
    pub message: String,
    pub span: Span,
    // A suggestion shown under the error.
    pub help: Option<String>,
}

impl fmt::Display for TypecheckerError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "type error at {}..{}: {}",
            self.span.start, self.span.end, self.message
        )?;
        if let Some(help) = &self.help {
            write!(f, " (help: {})", help)?;
        }
        Ok(())
    }
}

type TypecheckerResult<T> = Result<T, TypecheckerError>;

fn typechecker_error(span: Span, message: String) -> TypecheckerError {
    TypecheckerError {
        message,
        span,
        help: None,
    }
}

#[derive(Debug, Clone)]
pub struct StructInfo {
    pub name: String,
    // In declaration order.
    pub fields: Vec<(String, TypeInternal)>,
}

impl StructInfo {
    fn field_ty(&self, name: &str) -> Option<&TypeInternal> {
        self.fields
            .iter()
            .find(|(field_name, _)| field_name == name)
            .map(|(_, ty)| ty)
    }
}

#[derive(Debug, Clone)]
pub struct FnSig {
    pub name: String,
    pub params: Vec<(String, TypeInternal)>,
    pub return_ty: TypeInternal,
    pub is_variadic: bool,
}

impl FnSig {
    pub fn param_types(&self) -> Vec<TypeInternal> {
        self.params.iter().map(|(_, ty)| ty.clone()).collect()
    }
}

// A value computed at compile time. Integers are kept wrapped to their
// type's width (and sign-extended for signed types).
#[derive(Debug, Clone, PartialEq)]
pub enum ConstValue {
    Int(i128),
    Float(f64),
    Bool(bool),
    // Array elements, tuple elements or struct fields in declaration order.
    Aggregate(Vec<ConstValue>),
}

#[derive(Debug, Clone)]
pub struct ConstInfo {
    pub ty: TypeInternal,
    pub value: ConstValue,
}

// A global variable: `static [mut] NAME: T = value;`
#[derive(Debug, Clone)]
pub struct StaticInfo {
    pub ty: TypeInternal,
    pub mutable: bool,
    pub value: ConstValue,
}

pub struct Typechecker<'p> {
    structs: HashMap<String, StructInfo>,
    signatures: HashMap<String, FnSig>,
    aliases: HashMap<String, &'p Type>,
    resolved_aliases: HashMap<String, TypeInternal>,
    // Aliases being resolved, to detect cycles.
    resolving_aliases: HashSet<String>,
    const_decls: HashMap<String, &'p ConstDecl>,
    const_types: HashMap<String, TypeInternal>,
    consts: HashMap<String, ConstInfo>,
    // Constants being evaluated, to detect cycles.
    evaluating_consts: HashSet<String>,
    statics: HashMap<String, StaticInfo>,
    env: TypingEnvironment,
    // The return type of the function being checked.
    return_ty: TypeInternal,
    loops: Vec<LoopContext>,
    errors: Vec<TypecheckerError>,
    // Type of every expression, indexed by ExprId.
    types: Vec<Option<TypeInternal>>,
    // Expressions of type `!`, indexed by ExprId.
    diverges: Vec<bool>,
}

impl<'p> Typechecker<'p> {
    pub fn check_program(program: &'p Program) -> Result<CheckedProgram, Vec<TypecheckerError>> {
        let expr_count = program.expr_count as usize;
        let mut checker = Typechecker {
            structs: HashMap::new(),
            signatures: HashMap::new(),
            aliases: HashMap::new(),
            resolved_aliases: HashMap::new(),
            resolving_aliases: HashSet::new(),
            const_decls: HashMap::new(),
            const_types: HashMap::new(),
            consts: HashMap::new(),
            evaluating_consts: HashSet::new(),
            statics: HashMap::new(),
            env: TypingEnvironment::new(),
            return_ty: TypeInternal::Unit,
            loops: Vec::new(),
            errors: Vec::new(),
            types: vec![None; expr_count],
            diverges: vec![false; expr_count],
        };
        checker.collect_declarations(program)?;
        checker.check_function_bodies(program);
        if !checker.errors.is_empty() {
            return Err(checker.errors);
        }
        Ok(CheckedProgram {
            structs: checker.structs,
            functions: checker.signatures,
            consts: checker.consts,
            statics: checker.statics,
            types: checker.types,
            diverges: checker.diverges,
        })
    }

    // Stops checking when errors were found so far: later steps rely on
    // the earlier ones having succeeded.
    fn stop_on_errors(&mut self) -> Result<(), Vec<TypecheckerError>> {
        if self.errors.is_empty() {
            Ok(())
        } else {
            Err(std::mem::take(&mut self.errors))
        }
    }

    // ---- The per-expression side tables ----

    fn record_type(&mut self, expr: &Expr, ty: TypeInternal) {
        self.types[expr.id.0 as usize] = Some(ty);
    }

    fn recorded_type(&self, expr: &Expr) -> Option<&TypeInternal> {
        self.types[expr.id.0 as usize].as_ref()
    }

    // Records `ty` as the expression's type, and whether it diverges
    // (`actual` is `!`).
    fn record(&mut self, expr: &Expr, ty: TypeInternal, actual: &TypeInternal) {
        self.record_type(expr, ty);
        if *actual == TypeInternal::Never {
            self.diverges[expr.id.0 as usize] = true;
        }
    }
}

/// Result of a successful type check: the declarations and per-expression
/// facts that later passes (lowering, codegen) need.
#[derive(Debug, Clone)]
pub struct CheckedProgram {
    pub structs: HashMap<String, StructInfo>,
    pub functions: HashMap<String, FnSig>,
    pub consts: HashMap<String, ConstInfo>,
    pub statics: HashMap<String, StaticInfo>,
    // Type of every expression the checker visited, indexed by ExprId.
    pub types: Vec<Option<TypeInternal>>,
    // Expressions of type `!`, indexed by ExprId.
    pub diverges: Vec<bool>,
}

impl CheckedProgram {
    pub fn type_of(&self, expr: &Expr) -> &TypeInternal {
        self.types[expr.id.0 as usize].as_ref().unwrap_or_else(|| {
            panic!(
                "ICE: the checker gave no type to the expression at {:?}",
                expr.span
            )
        })
    }

    // Control never continues past the expression.
    pub fn diverges(&self, expr: &Expr) -> bool {
        self.diverges[expr.id.0 as usize]
    }
}

// A numeric literal (optionally negated) whose type comes from context.
fn is_untyped_literal(expr: &Expr) -> bool {
    match &expr.kind {
        ExprKind::IntLiteral(_) | ExprKind::FloatLiteral(_) | ExprKind::CharLiteral(_) => true,
        ExprKind::UnaryOp {
            op: UnaryOp::Neg,
            expr: inner,
        } => is_untyped_literal(inner),
        _ => false,
    }
}

// The operand type of a non-shift binary operator is the left operand's,
// unless the left operand is a bare literal and the right one is not
// (`1 + x`, `0 == n`): then the literal adopts the right operand's type.
fn literal_takes_rhs_type(lhs: &Expr, rhs: &Expr) -> bool {
    is_untyped_literal(lhs) && !is_untyped_literal(rhs)
}

pub fn typecheck(program: &Program) -> Result<CheckedProgram, Vec<TypecheckerError>> {
    Typechecker::check_program(program)
}

#[cfg(test)]
mod tests;
