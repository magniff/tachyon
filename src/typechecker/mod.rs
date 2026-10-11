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

use std::collections::{HashMap, HashSet};
use std::fmt;

use crate::lexer::{span::Span, token::NumSuffix};
use crate::parser::{
    AssignOp, BinOp, Block, ConstDecl, Expr, ExprKind, FieldInit, Item, LitValue, Pattern,
    PatternKind, Program, Stmt, Type, TypeKind, UnaryOp,
};

// Internal type representation (resolved, no spans)
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum TypeInternal {
    I8,
    I16,
    I32,
    I64,
    U8,
    U16,
    U32,
    U64,
    F32,
    F64,
    Bool,
    Unit,
    // `!`: the expression never produces a value.
    Never,
    Tuple(Vec<TypeInternal>),
    Array(Box<TypeInternal>, u64),
    Pointer(Box<TypeInternal>),
    Fn {
        params: Vec<TypeInternal>,
        result: Box<TypeInternal>,
    },
    Struct(String), // resolved by name
}

impl fmt::Display for TypeInternal {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TypeInternal::I8 => write!(f, "i8"),
            TypeInternal::I16 => write!(f, "i16"),
            TypeInternal::I32 => write!(f, "i32"),
            TypeInternal::I64 => write!(f, "i64"),
            TypeInternal::U8 => write!(f, "u8"),
            TypeInternal::U16 => write!(f, "u16"),
            TypeInternal::U32 => write!(f, "u32"),
            TypeInternal::U64 => write!(f, "u64"),
            TypeInternal::F32 => write!(f, "f32"),
            TypeInternal::F64 => write!(f, "f64"),
            TypeInternal::Bool => write!(f, "bool"),
            TypeInternal::Unit => write!(f, "()"),
            TypeInternal::Never => write!(f, "!"),
            TypeInternal::Tuple(ts) => {
                write!(f, "(")?;
                for (i, t) in ts.iter().enumerate() {
                    if i > 0 {
                        write!(f, ", ")?;
                    }
                    write!(f, "{}", t)?;
                }
                if ts.len() == 1 {
                    write!(f, ",")?;
                }
                write!(f, ")")
            }
            TypeInternal::Array(elem, n) => write!(f, "[{}; {}]", elem, n),
            TypeInternal::Pointer(inner) => write!(f, "*{}", inner),
            TypeInternal::Fn { params, result, .. } => {
                write!(f, "fn(")?;
                for (i, p) in params.iter().enumerate() {
                    if i > 0 {
                        write!(f, ", ")?;
                    }
                    write!(f, "{}", p)?;
                }
                write!(f, ")")?;
                if **result != TypeInternal::Unit {
                    write!(f, " -> {}", result)?;
                }
                Ok(())
            }
            TypeInternal::Struct(name) => write!(f, "{}", name),
        }
    }
}

impl TypeInternal {
    pub fn is_integer(&self) -> bool {
        matches!(
            self,
            TypeInternal::I8
                | TypeInternal::I16
                | TypeInternal::I32
                | TypeInternal::I64
                | TypeInternal::U8
                | TypeInternal::U16
                | TypeInternal::U32
                | TypeInternal::U64
        )
    }
    pub fn is_signed(&self) -> bool {
        matches!(
            self,
            TypeInternal::I8 | TypeInternal::I16 | TypeInternal::I32 | TypeInternal::I64
        )
    }
    pub fn is_float(&self) -> bool {
        matches!(self, TypeInternal::F32 | TypeInternal::F64)
    }
    pub fn is_numeric(&self) -> bool {
        self.is_integer() || self.is_float()
    }
    pub fn is_pointer(&self) -> bool {
        matches!(self, TypeInternal::Pointer(_))
    }
    // Width in bits of an integer, pointer or bool.
    fn int_bits(&self) -> u32 {
        match self {
            TypeInternal::I8 | TypeInternal::U8 | TypeInternal::Bool => 8,
            TypeInternal::I16 | TypeInternal::U16 => 16,
            TypeInternal::I32 | TypeInternal::U32 => 32,
            _ => 64,
        }
    }
}

fn suffix_type(s: NumSuffix) -> TypeInternal {
    match s {
        NumSuffix::I8 => TypeInternal::I8,
        NumSuffix::I16 => TypeInternal::I16,
        NumSuffix::I32 => TypeInternal::I32,
        NumSuffix::I64 | NumSuffix::Isize => TypeInternal::I64,
        NumSuffix::U8 => TypeInternal::U8,
        NumSuffix::U16 => TypeInternal::U16,
        NumSuffix::U32 => TypeInternal::U32,
        NumSuffix::U64 | NumSuffix::Usize => TypeInternal::U64,
        NumSuffix::F32 => TypeInternal::F32,
        NumSuffix::F64 => TypeInternal::F64,
    }
}

// Type error
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

fn typechecker_error(span: Span, msg: String) -> TypecheckerError {
    TypecheckerError {
        message: msg,
        span,
        help: None,
    }
}

// Struct info
#[derive(Debug, Clone)]
pub struct StructInfo {
    pub name: String,
    pub fields: Vec<(String, TypeInternal)>, // ordered
}

impl StructInfo {
    fn field_ty(&self, name: &str) -> Option<&TypeInternal> {
        self.fields
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, ty)| ty)
    }
}

// Function signature
#[derive(Debug, Clone)]
pub struct FnSig {
    pub name: String,
    pub params: Vec<(String, TypeInternal)>,
    pub return_ty: TypeInternal,
    pub is_variadic: bool,
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

#[derive(Debug, Clone)]
struct VarInfo {
    ty: TypeInternal,
    mutable: bool,
    is_param: bool,
}

// Scope / variable environment
struct Scope {
    vars: HashMap<String, VarInfo>,
}

struct TypingEnvironment {
    scopes: Vec<Scope>,
}

impl TypingEnvironment {
    fn new() -> Self {
        Self {
            scopes: vec![Scope {
                vars: HashMap::new(),
            }],
        }
    }

    fn push_scope(&mut self) {
        self.scopes.push(Scope {
            vars: HashMap::new(),
        });
    }

    fn pop_scope(&mut self) {
        if self.scopes.len() > 1 {
            self.scopes.pop();
        }
    }

    fn define(&mut self, name: String, info: VarInfo) {
        self.scopes.last_mut().unwrap().vars.insert(name, info);
    }

    fn lookup(&self, name: &str) -> Option<&VarInfo> {
        self.scopes.iter().rev().find_map(|s| s.vars.get(name))
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum LoopKind {
    Loop,
    While,
    For,
}

struct LoopCtx {
    label: Option<String>,
    kind: LoopKind,
    // Type of the `loop`'s value: set by the context (check mode) or by the
    // first `break`.
    break_ty: Option<TypeInternal>,
    has_break: bool,
}

pub struct Typechecker<'p> {
    structs: HashMap<String, StructInfo>,
    signatures: HashMap<String, FnSig>,
    aliases: HashMap<String, &'p Type>,
    resolved_aliases: HashMap<String, TypeInternal>,
    resolving_aliases: HashSet<String>,
    const_decls: HashMap<String, &'p ConstDecl>,
    const_types: HashMap<String, TypeInternal>,
    consts: HashMap<String, ConstInfo>,
    evaluating_consts: HashSet<String>,
    statics: HashMap<String, StaticInfo>,
    env: TypingEnvironment,
    return_ty: TypeInternal, // current function's return type
    loops: Vec<LoopCtx>,
    errors: Vec<TypecheckerError>,
    // Type of every expression, indexed by ExprId.
    types: Vec<Option<TypeInternal>>,
    // Expressions of type `!`, indexed by ExprId.
    diverges: Vec<bool>,
}

impl<'p> Typechecker<'p> {
    pub fn check_program(program: &'p Program) -> Result<CheckedProgram, Vec<TypecheckerError>> {
        let n = program.expr_count as usize;
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
            types: vec![None; n],
            diverges: vec![false; n],
        };

        // Pass 1: collect declarations
        checker.collect_names(program);
        if !checker.errors.is_empty() {
            return Err(checker.errors);
        }
        checker.collect_const_types(program);
        checker.collect_structs(program);
        checker.collect_aliases(program);
        if !checker.errors.is_empty() {
            return Err(checker.errors);
        }

        checker.check_struct_cycles(program);
        if !checker.errors.is_empty() {
            return Err(checker.errors);
        }

        checker.collect_functions(program);
        checker.collect_statics(program);
        checker.evaluate_consts(program);
        if !checker.errors.is_empty() {
            return Err(checker.errors);
        }

        // Pass 2: check function bodies
        checker.check_function_bodies(program);
        if checker.errors.is_empty() {
            Ok(CheckedProgram {
                structs: checker.structs,
                functions: checker.signatures,
                consts: checker.consts,
                statics: checker.statics,
                types: checker.types,
                diverges: checker.diverges,
            })
        } else {
            Err(checker.errors)
        }
    }

    // Pass 1: Collect declarations

    // Registers every global name, so declarations can refer to each other
    // in any order. Types (structs, aliases) and values (functions,
    // constants, statics) have separate namespaces.
    fn collect_names(&mut self, program: &'p Program) {
        let mut types: HashSet<&str> = HashSet::new();
        let mut values: HashSet<&str> = HashSet::new();
        for item in &program.items {
            let (name, span, is_type) = match item {
                Item::Struct(sd) => (&sd.name.0, sd.span, true),
                Item::TypeAlias(ta) => (&ta.name.0, ta.span, true),
                Item::Function(fd) => (&fd.name.0, fd.span, false),
                Item::Extern(ed) => (&ed.name.0, ed.span, false),
                Item::Const(cd) => (&cd.name.0, cd.span, false),
                Item::Static(sd) => (&sd.name.0, sd.span, false),
            };
            let fresh = if is_type {
                types.insert(name) && !is_primitive_type(name)
            } else {
                values.insert(name)
            };
            if !fresh {
                let what = match item {
                    Item::Struct(_) => "struct",
                    Item::TypeAlias(_) => "type",
                    Item::Function(_) | Item::Extern(_) => "function",
                    Item::Const(_) => "constant",
                    Item::Static(_) => "static",
                };
                self.errors.push(typechecker_error(
                    span,
                    format!("duplicate {} '{}'", what, name),
                ));
                continue;
            }
            match item {
                Item::Struct(sd) => {
                    self.structs.insert(
                        name.clone(),
                        StructInfo {
                            name: name.clone(),
                            fields: Vec::new(),
                        },
                    );
                    let _ = sd;
                }
                Item::TypeAlias(ta) => {
                    self.aliases.insert(name.clone(), &ta.ty);
                }
                Item::Const(cd) => {
                    self.const_decls.insert(name.clone(), cd);
                }
                _ => {}
            }
        }
    }

    // Constants have scalar types, resolved before anything that may use
    // them (array sizes in struct fields, signatures, ...).
    fn collect_const_types(&mut self, program: &Program) {
        for item in &program.items {
            if let Item::Const(cd) = item {
                match self.resolve_type(&cd.ty) {
                    Ok(ty) if ty.is_numeric() || ty == TypeInternal::Bool => {
                        self.const_types.insert(cd.name.0.clone(), ty);
                    }
                    Ok(ty) => self.errors.push(typechecker_error(
                        cd.ty.span,
                        format!(
                            "constant '{}' has type '{}'; constants must be integers, floats or bool",
                            cd.name.0, ty
                        ),
                    )),
                    Err(e) => self.errors.push(e),
                }
            }
        }
    }

    // Resolves struct field types now that all names are known.
    fn collect_structs(&mut self, program: &Program) {
        for item in &program.items {
            if let Item::Struct(sd) = item {
                let name = &sd.name.0;
                let mut fields = Vec::new();
                let mut seen = HashSet::new();
                for f in &sd.fields {
                    if !seen.insert(&f.name.0) {
                        self.errors.push(typechecker_error(
                            f.span,
                            format!("duplicate field '{}' in struct '{}'", f.name.0, name),
                        ));
                        continue;
                    }
                    match self.resolve_type(&f.ty) {
                        Ok(ty) => fields.push((f.name.0.clone(), ty)),
                        Err(e) => self.errors.push(e),
                    }
                }
                if let Some(info) = self.structs.get_mut(name) {
                    info.fields = fields;
                }
            }
        }
    }

    // Resolves every type alias, so errors in unused ones are reported too.
    fn collect_aliases(&mut self, program: &Program) {
        for item in &program.items {
            if let Item::TypeAlias(ta) = item
                && let Err(e) = self.resolve_named(&ta.name.0, ta.name.1)
            {
                self.errors.push(e);
            }
        }
    }

    fn check_struct_cycles(&mut self, program: &Program) {
        // Detect structs that contain themselves (directly or transitively) by value.
        // Pointers break the cycle (they have a fixed size).
        for item in &program.items {
            if let Item::Struct(sd) = item {
                let mut visited = HashSet::new();
                if self.has_cycle(&sd.name.0, &mut visited) {
                    self.errors.push(typechecker_error(sd.name.1, format!(
                        "struct '{}' has infinite size due to recursive field (use a pointer to break the cycle)", sd.name.0
                    )));
                }
            }
        }
    }

    fn has_cycle(&self, name: &str, visited: &mut HashSet<String>) -> bool {
        if !visited.insert(name.to_string()) {
            return true;
        }
        if let Some(info) = self.structs.get(name) {
            for (_, ty) in &info.fields {
                if self.embeds_cycle(ty, visited) {
                    return true;
                }
            }
        }
        visited.remove(name);
        false
    }

    // Structs embedded by value in `ty` (through arrays and tuples).
    fn embeds_cycle(&self, ty: &TypeInternal, visited: &mut HashSet<String>) -> bool {
        match ty {
            TypeInternal::Struct(inner) => self.has_cycle(inner, visited),
            TypeInternal::Array(elem, _) => self.embeds_cycle(elem, visited),
            TypeInternal::Tuple(elems) => elems.iter().any(|e| self.embeds_cycle(e, visited)),
            _ => false,
        }
    }

    fn collect_functions(&mut self, program: &Program) {
        for item in &program.items {
            let (name, params_ast, ret_ast, is_variadic) = match item {
                Item::Function(fd) => (&fd.name, &fd.params, &fd.return_type, false),
                Item::Extern(ed) => (&ed.name, &ed.params, &ed.return_type, ed.is_variadic),
                _ => continue,
            };
            let mut params = Vec::new();
            let mut seen = HashSet::new();
            for p in params_ast {
                if p.name.0 != "_" && !seen.insert(&p.name.0) {
                    self.errors.push(typechecker_error(
                        p.name.1,
                        format!("duplicate parameter '{}'", p.name.0),
                    ));
                }
                match self.resolve_type(&p.ty) {
                    Ok(ty) => params.push((p.name.0.clone(), ty)),
                    Err(e) => self.errors.push(e),
                }
            }
            let return_ty = match ret_ast {
                Some(t) => match self.resolve_type(t) {
                    Ok(ty) => ty,
                    Err(e) => {
                        self.errors.push(e);
                        TypeInternal::Unit
                    }
                },
                None => TypeInternal::Unit,
            };
            self.signatures.insert(
                name.0.clone(),
                FnSig {
                    name: name.0.clone(),
                    params,
                    return_ty,
                    is_variadic,
                },
            );
        }
    }

    fn collect_statics(&mut self, program: &Program) {
        for item in &program.items {
            if let Item::Static(sd) = item {
                let ty = match self.resolve_type(&sd.ty) {
                    Ok(ty) => ty,
                    Err(e) => {
                        self.errors.push(e);
                        continue;
                    }
                };
                match self.eval_const_expr(&sd.value, &ty) {
                    Ok(value) => {
                        self.statics.insert(
                            sd.name.0.clone(),
                            StaticInfo {
                                ty,
                                mutable: sd.mutable,
                                value,
                            },
                        );
                    }
                    Err(e) => self.errors.push(e),
                }
            }
        }
    }

    fn evaluate_consts(&mut self, program: &Program) {
        for item in &program.items {
            if let Item::Const(cd) = item
                && self.const_types.contains_key(&cd.name.0)
                && let Err(e) = self.const_value(&cd.name.0)
            {
                self.errors.push(e);
            }
        }
    }

    // ---- Constants ----

    // The value of a named constant, evaluated on first use.
    fn const_value(&mut self, name: &str) -> TypecheckerResult<ConstValue> {
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
        self.consts.insert(
            name.to_string(),
            ConstInfo {
                ty,
                value: value.clone(),
            },
        );
        Ok(value)
    }

    // Type checks `expr` against `ty` outside of any function, then
    // evaluates it.
    fn eval_const_expr(&mut self, expr: &Expr, ty: &TypeInternal) -> TypecheckerResult<ConstValue> {
        self.in_const_context(|tc| {
            tc.check_expr(expr, ty)?;
            tc.const_eval(expr)
        })
    }

    // An array length: a constant, non-negative integer expression.
    fn eval_array_len(&mut self, expr: &Expr) -> TypecheckerResult<u64> {
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
            ConstValue::Int(n) if n >= 0 => Ok(n as u64),
            _ => Err(typechecker_error(
                expr.span,
                "array length must not be negative".to_string(),
            )),
        }
    }

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

    fn not_const(expr: &Expr) -> TypecheckerError {
        typechecker_error(
            expr.span,
            "expression is not a compile-time constant".to_string(),
        )
    }

    // Evaluates a type-checked constant expression.
    fn const_eval(&mut self, expr: &Expr) -> TypecheckerResult<ConstValue> {
        let ty = self.types[expr.id.0 as usize]
            .clone()
            .unwrap_or(TypeInternal::Unit);
        let int = |v: i128| ConstValue::Int(wrap_int(v, &ty));
        Ok(match &expr.kind {
            ExprKind::IntLiteral(v) => int(*v as i128),
            ExprKind::CharLiteral(v) => int(*v as i128),
            ExprKind::SuffixedLiteral(LitValue::Int(v), s) if !s.is_float() => int(*v as i128),
            ExprKind::SuffixedLiteral(LitValue::Int(v), _) => float_const(*v as f64, &ty),
            ExprKind::FloatLiteral(f) | ExprKind::SuffixedLiteral(LitValue::Float(f), _) => {
                float_const(**f, &ty)
            }
            ExprKind::BoolLiteral(b) => ConstValue::Bool(*b),
            ExprKind::UnitLiteral => ConstValue::Aggregate(Vec::new()),
            ExprKind::Ident(name) => {
                if self.env.lookup(name).is_none() && self.const_decls.contains_key(name) {
                    self.const_value(name)?
                } else {
                    return Err(typechecker_error(
                        expr.span,
                        format!("'{}' is not a constant", name),
                    ));
                }
            }
            ExprKind::UnaryOp { op, expr: inner } => {
                let v = self.const_eval(inner)?;
                match (op, v) {
                    (UnaryOp::Neg, ConstValue::Int(v)) => int(v.wrapping_neg()),
                    (UnaryOp::Neg, ConstValue::Float(f)) => float_const(-f, &ty),
                    (UnaryOp::Not, ConstValue::Bool(b)) => ConstValue::Bool(!b),
                    (UnaryOp::BitNot, ConstValue::Int(v)) => int(!v),
                    _ => return Err(Self::not_const(expr)),
                }
            }
            ExprKind::BinOp { op, lhs, rhs } => {
                let operand_ty = self.types[lhs.id.0 as usize].clone().unwrap();
                let a = self.const_eval(lhs)?;
                // && and || short-circuit
                match (op, &a) {
                    (BinOp::And, ConstValue::Bool(false)) => return Ok(ConstValue::Bool(false)),
                    (BinOp::Or, ConstValue::Bool(true)) => return Ok(ConstValue::Bool(true)),
                    _ => {}
                }
                let b = self.const_eval(rhs)?;
                const_binop(*op, a, b, &operand_ty, &ty)
                    .map_err(|msg| typechecker_error(expr.span, msg))?
            }
            ExprKind::Cast { expr: inner, .. } => {
                let from = self.types[inner.id.0 as usize].clone().unwrap();
                let v = self.const_eval(inner)?;
                const_cast(v, &from, &ty).ok_or_else(|| Self::not_const(expr))?
            }
            ExprKind::Tuple(elems) | ExprKind::Array(elems) => ConstValue::Aggregate(
                elems
                    .iter()
                    .map(|e| self.const_eval(e))
                    .collect::<TypecheckerResult<_>>()?,
            ),
            ExprKind::ArrayRepeat(value, _) => {
                let TypeInternal::Array(_, n) = ty else {
                    return Err(Self::not_const(expr));
                };
                let v = self.const_eval(value)?;
                ConstValue::Aggregate(vec![v; n as usize])
            }
            ExprKind::StructConstructor { name, fields } => {
                let info = self.structs[&name.0].clone();
                let mut values = Vec::new();
                for (fname, _) in &info.fields {
                    let field = fields.iter().find(|f| &f.name.0 == fname).unwrap();
                    values.push(self.const_eval(&field.value)?);
                }
                ConstValue::Aggregate(values)
            }
            _ => return Err(Self::not_const(expr)),
        })
    }

    // Type resolution: AST Type -> TypeInternal
    fn resolve_type(&mut self, ast_ty: &Type) -> TypecheckerResult<TypeInternal> {
        match &ast_ty.kind {
            TypeKind::Named(name) => self.resolve_named(name, ast_ty.span),
            TypeKind::Unit => Ok(TypeInternal::Unit),
            TypeKind::Never => Ok(TypeInternal::Never),
            TypeKind::Tuple(ts) => {
                let mut resolved = Vec::new();
                for t in ts {
                    resolved.push(self.resolve_type(t)?);
                }
                Ok(TypeInternal::Tuple(resolved))
            }
            TypeKind::Array(elem, size) => {
                let elem_ty = self.resolve_type(elem)?;
                let n = self.eval_array_len(size)?;
                Ok(TypeInternal::Array(Box::new(elem_ty), n))
            }
            TypeKind::Pointer(inner) => {
                let inner_ty = self.resolve_type(inner)?;
                Ok(TypeInternal::Pointer(Box::new(inner_ty)))
            }
            TypeKind::Fn { params, result } => {
                let mut p = Vec::new();
                for t in params {
                    p.push(self.resolve_type(t)?);
                }
                Ok(TypeInternal::Fn {
                    params: p,
                    result: Box::new(self.resolve_type(result)?),
                })
            }
        }
    }

    fn resolve_named(&mut self, name: &str, span: Span) -> TypecheckerResult<TypeInternal> {
        if let Some(ty) = primitive_type(name) {
            return Ok(ty);
        }
        if self.structs.contains_key(name) {
            return Ok(TypeInternal::Struct(name.to_string()));
        }
        if let Some(ty) = self.resolved_aliases.get(name) {
            return Ok(ty.clone());
        }
        if let Some(target) = self.aliases.get(name).copied() {
            if !self.resolving_aliases.insert(name.to_string()) {
                return Err(typechecker_error(
                    span,
                    format!("type alias '{}' is defined in terms of itself", name),
                ));
            }
            let resolved = self.resolve_type(target);
            self.resolving_aliases.remove(name);
            let resolved = resolved?;
            self.resolved_aliases
                .insert(name.to_string(), resolved.clone());
            return Ok(resolved);
        }
        Err(typechecker_error(span, format!("unknown type '{}'", name)))
    }

    // Pass 2: Check function bodies
    fn check_function_bodies(&mut self, program: &Program) {
        for item in &program.items {
            if let Item::Function(fd) = item {
                let sig = self.signatures.get(&fd.name.0).unwrap().clone();
                self.return_ty = sig.return_ty.clone();
                self.loops.clear();
                self.env = TypingEnvironment::new();

                // Bind parameters
                for (p, (name, ty)) in fd.params.iter().zip(&sig.params) {
                    if name != "_" {
                        self.env.define(
                            name.clone(),
                            VarInfo {
                                ty: ty.clone(),
                                mutable: p.mutable,
                                is_param: true,
                            },
                        );
                    }
                }

                // The body's tail is checked against the return type; a body
                // without a tail has type () unless it never reaches its end.
                match self.check_block(&fd.body, Some(&sig.return_ty)) {
                    Ok(bt) => {
                        if bt != sig.return_ty && bt != TypeInternal::Never {
                            self.errors.push(typechecker_error(
                                fd.body.span,
                                format!(
                                    "function '{}' body has type '{}', expected '{}'",
                                    fd.name.0, bt, sig.return_ty
                                ),
                            ));
                        }
                    }
                    Err(e) => self.errors.push(e),
                }
            }
        }
    }

    // The block's type: its tail's (checked against `expected` if given),
    // `!` if a statement diverges, otherwise ().
    fn check_block(
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
            (Some(tail), Some(exp)) => self.check_expr(tail, exp)?,
            (Some(tail), None) => self.synth_expr(tail)?,
            (None, _) => TypeInternal::Unit,
        };
        Ok(if diverges { TypeInternal::Never } else { ty })
    }

    // A block in check mode (an if/else branch or a block expression): its
    // tail must have the expected type, and a block without a tail has type
    // () unless control never reaches its end. Returns `!` or `expected`.
    fn check_branch(
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

    // Checks a statement; returns whether it diverges.
    fn check_stmt(&mut self, stmt: &Stmt) -> bool {
        match stmt {
            Stmt::Let(ls) => {
                let (ty, actual) = match &ls.ty {
                    Some(ann) => match self.resolve_type(ann) {
                        Ok(expected) => match self.check_expr(&ls.init, &expected) {
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
                    None => match self.synth_expr(&ls.init) {
                        Ok(ty) => (ty.clone(), ty),
                        // `!` binds silently, avoiding follow-up errors.
                        Err(e) => {
                            self.errors.push(e);
                            (TypeInternal::Never, TypeInternal::Unit)
                        }
                    },
                };
                self.bind_pattern(&ls.pattern, &ty);
                actual == TypeInternal::Never
            }
            Stmt::Expr(es) => {
                // A block-like statement without `;` must have type ().
                let result = if es.has_semi {
                    self.synth_expr(&es.expr)
                } else {
                    self.check_expr(&es.expr, &TypeInternal::Unit)
                };
                match result {
                    Ok(ty) => ty == TypeInternal::Never,
                    Err(e) => {
                        self.errors.push(e);
                        false
                    }
                }
            }
        }
    }

    fn bind_pattern(&mut self, pattern: &Pattern, ty: &TypeInternal) {
        match &pattern.kind {
            PatternKind::Wildcard => {}
            PatternKind::Binding { name, mutable } => self.env.define(
                name.clone(),
                VarInfo {
                    ty: ty.clone(),
                    mutable: *mutable,
                    is_param: false,
                },
            ),
            PatternKind::Tuple(pats) => match ty {
                TypeInternal::Tuple(elems) if elems.len() == pats.len() => {
                    for (p, t) in pats.iter().zip(elems) {
                        self.bind_pattern(p, t);
                    }
                }
                TypeInternal::Never => {
                    for p in pats {
                        self.bind_pattern(p, &TypeInternal::Never);
                    }
                }
                _ => self.errors.push(typechecker_error(
                    pattern.span,
                    format!(
                        "a tuple pattern with {} elements cannot bind a value of type '{}'",
                        pats.len(),
                        ty
                    ),
                )),
            },
        }
    }

    // Expression checking (check mode). On success the expression's type is
    // recorded as `expected`, the type it has in its context; the result is
    // `expected`, or `!` when the expression diverges.
    fn check_expr(
        &mut self,
        expr: &Expr,
        expected: &TypeInternal,
    ) -> TypecheckerResult<TypeInternal> {
        let actual = self.check_expr_inner(expr, expected)?;
        let id = expr.id.0 as usize;
        self.types[id] = Some(expected.clone());
        if actual == TypeInternal::Never {
            self.diverges[id] = true;
        }
        Ok(actual)
    }

    fn mismatch(
        &mut self,
        expr: &Expr,
        expected: &TypeInternal,
    ) -> TypecheckerResult<TypeInternal> {
        let got = self.synth_expr(expr)?;
        if got == TypeInternal::Never {
            return Ok(got);
        }
        if got != *expected {
            return Err(typechecker_error(
                expr.span,
                format!("expected '{}', got '{}'", expected, got),
            ));
        }
        Ok(got)
    }

    fn check_expr_inner(
        &mut self,
        expr: &Expr,
        expected: &TypeInternal,
    ) -> TypecheckerResult<TypeInternal> {
        let ok = Ok(expected.clone());
        match &expr.kind {
            // Literals benefit from check mode
            ExprKind::IntLiteral(_) | ExprKind::CharLiteral(_) if expected.is_integer() => {
                let v = match expr.kind {
                    ExprKind::IntLiteral(v) => v,
                    ExprKind::CharLiteral(c) => c as u64,
                    _ => unreachable!(),
                };
                self.check_int_fits(v, expected, expr.span)?;
                ok
            }
            ExprKind::FloatLiteral(_) if expected.is_float() => ok,

            // Tuple: push expected element types down
            ExprKind::Tuple(elems) if matches!(expected, TypeInternal::Tuple(_)) => {
                let TypeInternal::Tuple(exp_elems) = expected else {
                    unreachable!()
                };
                if elems.len() != exp_elems.len() {
                    return Err(typechecker_error(
                        expr.span,
                        format!(
                            "tuple has {} elements, expected {}",
                            elems.len(),
                            exp_elems.len()
                        ),
                    ));
                }
                for (elem, exp) in elems.iter().zip(exp_elems.iter()) {
                    self.check_expr(elem, exp)?;
                }
                ok
            }

            // Array: push expected element type down
            ExprKind::Array(elems) if matches!(expected, TypeInternal::Array(..)) => {
                let TypeInternal::Array(exp_elem, exp_size) = expected else {
                    unreachable!()
                };
                if elems.len() as u64 != *exp_size {
                    return Err(typechecker_error(
                        expr.span,
                        format!("array has {} elements, expected {}", elems.len(), exp_size),
                    ));
                }
                for elem in elems {
                    self.check_expr(elem, exp_elem)?;
                }
                ok
            }

            // ArrayRepeat: push expected element type down
            ExprKind::ArrayRepeat(val, count) if matches!(expected, TypeInternal::Array(..)) => {
                let TypeInternal::Array(exp_elem, exp_size) = expected else {
                    unreachable!()
                };
                self.check_expr(val, exp_elem)?;
                let n = self.eval_array_len(count)?;
                if n != *exp_size {
                    return Err(typechecker_error(
                        count.span,
                        format!("array repeat count is {}, expected {}", n, exp_size),
                    ));
                }
                ok
            }

            // Struct constructor: push field types down
            ExprKind::StructConstructor { name, fields } => {
                if let TypeInternal::Struct(exp_name) = expected
                    && *exp_name != name.0
                {
                    return Err(typechecker_error(
                        expr.span,
                        format!(
                            "expected struct '{}', got constructor for '{}'",
                            exp_name, name.0
                        ),
                    ));
                }
                self.check_struct_constructor(&name.0, name.1, fields, expr.span)?;
                let got = TypeInternal::Struct(name.0.clone());
                if got != *expected {
                    return Err(typechecker_error(
                        expr.span,
                        format!("expected '{}', got '{}'", expected, got),
                    ));
                }
                ok
            }

            // If: push expected into both branches
            ExprKind::If {
                cond,
                then_block,
                else_block,
            } => {
                self.check_expr(cond, &TypeInternal::Bool)?;
                match else_block {
                    Some(eb) => {
                        let t = self.check_branch(then_block, expected)?;
                        let e = self.check_branch(eb, expected)?;
                        if t == TypeInternal::Never && e == TypeInternal::Never {
                            Ok(TypeInternal::Never)
                        } else {
                            ok
                        }
                    }
                    None => {
                        if *expected != TypeInternal::Unit {
                            return Err(typechecker_error(
                                expr.span,
                                format!(
                                    "if without else must have type '()', expected '{}'",
                                    expected
                                ),
                            ));
                        }
                        self.check_branch(then_block, &TypeInternal::Unit)?;
                        ok
                    }
                }
            }

            // Block: push expected into tail
            ExprKind::Block(block) => self.check_branch(block, expected),

            // A `loop`'s breaks take the expected type.
            ExprKind::Loop { label, body } => self.check_loop(label, body, Some(expected)),

            // Arithmetic and bitwise operators: push a numeric expected type
            // into both operands so literals take it (`let x: u8 = 1 + 2`).
            ExprKind::BinOp { op, lhs, rhs }
                if (matches!(
                    op,
                    BinOp::Add | BinOp::Sub | BinOp::Mul | BinOp::Div | BinOp::Mod
                ) && expected.is_numeric())
                    || (matches!(op, BinOp::BitAnd | BinOp::BitOr | BinOp::BitXor)
                        && expected.is_integer()) =>
            {
                self.check_expr(lhs, expected)?;
                self.check_expr(rhs, expected)?;
                ok
            }
            ExprKind::BinOp {
                op: BinOp::Shl | BinOp::Shr,
                lhs,
                rhs,
            } if expected.is_integer() => {
                self.check_expr(lhs, expected)?;
                let rty = self.synth_expr(rhs)?;
                if !rty.is_integer() {
                    return Err(typechecker_error(
                        rhs.span,
                        format!("shift amount must be integer, got '{}'", rty),
                    ));
                }
                ok
            }
            ExprKind::UnaryOp {
                op: UnaryOp::Neg,
                expr: inner,
            } if expected.is_numeric() => {
                // `-128` fits i8 although `128` does not
                if let ExprKind::IntLiteral(v) = &inner.kind
                    && expected.is_signed()
                {
                    self.check_int_fits(v.saturating_sub(1), expected, expr.span)
                        .map_err(|_| {
                            typechecker_error(
                                expr.span,
                                format!(
                                    "integer literal -{} does not fit in type '{}'",
                                    v, expected
                                ),
                            )
                        })?;
                    self.types[inner.id.0 as usize] = Some(expected.clone());
                    return ok;
                }
                self.check_expr(inner, expected)?;
                ok
            }
            ExprKind::UnaryOp {
                op: UnaryOp::BitNot,
                expr: inner,
            } if expected.is_integer() => {
                self.check_expr(inner, expected)?;
                ok
            }

            // For everything else, fall back to synth + compare
            _ => self.mismatch(expr, expected).map(|got| {
                if got == TypeInternal::Never {
                    got
                } else {
                    expected.clone()
                }
            }),
        }
    }

    // Expression synthesis (synth mode)
    fn synth_expr(&mut self, expr: &Expr) -> TypecheckerResult<TypeInternal> {
        let ty = self.synth_expr_inner(expr)?;
        let id = expr.id.0 as usize;
        self.types[id] = Some(ty.clone());
        if ty == TypeInternal::Never {
            self.diverges[id] = true;
        }
        Ok(ty)
    }

    fn synth_expr_inner(&mut self, expr: &Expr) -> TypecheckerResult<TypeInternal> {
        match &expr.kind {
            // Already reported by the parser.
            ExprKind::Error => Ok(TypeInternal::Never),
            ExprKind::IntLiteral(_) => Ok(TypeInternal::I64), // default
            ExprKind::CharLiteral(_) => Ok(TypeInternal::U8),
            ExprKind::FloatLiteral(_) => Ok(TypeInternal::F64), // default
            ExprKind::SuffixedLiteral(v, s) => self.suffixed_literal(*v, *s, false, expr.span),
            ExprKind::BoolLiteral(_) => Ok(TypeInternal::Bool),
            ExprKind::UnitLiteral => Ok(TypeInternal::Unit),
            ExprKind::StringLiteral(_) => {
                // String literals are (*u8, usize) aka (*u8, u64)
                Ok(TypeInternal::Tuple(vec![
                    TypeInternal::Pointer(Box::new(TypeInternal::U8)),
                    TypeInternal::U64,
                ]))
            }
            ExprKind::CStringLiteral(_) => Ok(TypeInternal::Pointer(Box::new(TypeInternal::U8))),

            ExprKind::Ident(name) => {
                if let Some(var) = self.env.lookup(name) {
                    return Ok(var.ty.clone());
                }
                if let Some(ty) = self.const_types.get(name) {
                    return Ok(ty.clone());
                }
                if let Some(info) = self.statics.get(name) {
                    return Ok(info.ty.clone());
                }
                // A function used as a value has a function pointer type
                match self.signatures.get(name) {
                    Some(sig) if !sig.is_variadic => Ok(TypeInternal::Fn {
                        params: sig.params.iter().map(|(_, t)| t.clone()).collect(),
                        result: Box::new(sig.return_ty.clone()),
                    }),
                    Some(_) => Err(typechecker_error(
                        expr.span,
                        format!("variadic function '{}' cannot be used as a value", name),
                    )),
                    None => Err(typechecker_error(
                        expr.span,
                        format!("undefined variable '{}'", name),
                    )),
                }
            }

            ExprKind::BinOp { op, lhs, rhs } => self.synth_binop(op, lhs, rhs, expr.span),
            ExprKind::UnaryOp { op, expr: inner } => self.synth_unaryop(op, inner, expr.span),

            ExprKind::Cast { expr: inner, ty } => {
                let from = self.synth_expr(inner)?;
                let to = self.resolve_type(ty)?;
                self.check_cast(&from, &to, inner.span)?;
                Ok(to)
            }

            ExprKind::Call { callee, args } => self.synth_call(callee, args, expr.span),

            ExprKind::Index { expr: base, index } => {
                let base_ty = self.synth_expr(base)?;
                let elem = match &base_ty {
                    TypeInternal::Array(elem, _) | TypeInternal::Pointer(elem) => (**elem).clone(),
                    _ => {
                        return Err(typechecker_error(
                            base.span,
                            format!("cannot index type '{}'", base_ty),
                        ));
                    }
                };
                let idx_ty = self.synth_expr(index)?;
                if !idx_ty.is_integer() {
                    return Err(typechecker_error(
                        index.span,
                        format!("index must be integer, got '{}'", idx_ty),
                    ));
                }
                Ok(elem)
            }

            ExprKind::Field { expr: inner, name } => {
                let inner_ty = self.synth_expr(inner)?;
                self.resolve_field_access(&inner_ty, &name.0, expr.span)
            }

            ExprKind::TupleField { expr: inner, index } => {
                let inner_ty = self.synth_expr(inner)?;
                match &inner_ty {
                    TypeInternal::Tuple(elems) => {
                        let idx = index.0 as usize;
                        if idx >= elems.len() {
                            Err(typechecker_error(
                                expr.span,
                                format!(
                                    "tuple index {} out of range for tuple with {} elements",
                                    idx,
                                    elems.len()
                                ),
                            ))
                        } else {
                            Ok(elems[idx].clone())
                        }
                    }
                    _ => Err(typechecker_error(
                        expr.span,
                        format!("cannot use tuple index on type '{}'", inner_ty),
                    )),
                }
            }

            ExprKind::Tuple(elems) => {
                let mut types = Vec::new();
                for elem in elems {
                    types.push(self.synth_expr(elem)?);
                }
                Ok(TypeInternal::Tuple(types))
            }

            ExprKind::Array(elems) => {
                if elems.is_empty() {
                    return Err(typechecker_error(
                        expr.span,
                        "cannot infer the type of an empty array; annotate it".to_string(),
                    ));
                }
                let first_ty = self.synth_expr(&elems[0])?;
                for elem in &elems[1..] {
                    self.check_expr(elem, &first_ty)?;
                }
                Ok(TypeInternal::Array(Box::new(first_ty), elems.len() as u64))
            }

            ExprKind::ArrayRepeat(val, count) => {
                let elem_ty = self.synth_expr(val)?;
                let n = self.eval_array_len(count)?;
                Ok(TypeInternal::Array(Box::new(elem_ty), n))
            }

            ExprKind::StructConstructor { name, fields } => {
                self.check_struct_constructor(&name.0, name.1, fields, expr.span)?;
                Ok(TypeInternal::Struct(name.0.clone()))
            }

            ExprKind::Block(block) => self.check_block(block, None),

            ExprKind::If {
                cond,
                then_block,
                else_block,
            } => {
                self.check_expr(cond, &TypeInternal::Bool)?;
                match else_block {
                    Some(eb) => {
                        let then_ty = self.check_block(then_block, None)?;
                        let else_ty = self.check_block(eb, None)?;
                        if then_ty == TypeInternal::Never {
                            Ok(else_ty)
                        } else if else_ty == TypeInternal::Never || then_ty == else_ty {
                            Ok(then_ty)
                        } else {
                            Err(typechecker_error(
                                expr.span,
                                format!(
                                    "if/else branches have different types: '{}' vs '{}'",
                                    then_ty, else_ty
                                ),
                            ))
                        }
                    }
                    None => {
                        let then_ty = self.check_block(then_block, None)?;
                        if then_ty != TypeInternal::Unit && then_ty != TypeInternal::Never {
                            Err(typechecker_error(
                                expr.span,
                                format!("if without else must have type '()', got '{}'", then_ty),
                            ))
                        } else {
                            Ok(TypeInternal::Unit)
                        }
                    }
                }
            }

            ExprKind::Loop { label, body } => self.check_loop(label, body, None),

            ExprKind::While { label, cond, body } => {
                self.check_expr(cond, &TypeInternal::Bool)?;
                self.loops.push(LoopCtx {
                    label: label.as_ref().map(|l| l.0.clone()),
                    kind: LoopKind::While,
                    break_ty: None,
                    has_break: false,
                });
                let result = self.check_branch(body, &TypeInternal::Unit);
                self.loops.pop();
                result?;
                Ok(TypeInternal::Unit)
            }

            ExprKind::For {
                label,
                pattern,
                iter,
                body,
            } => self.check_for(label, pattern, iter, body),

            ExprKind::Range { .. } => Err(typechecker_error(
                expr.span,
                "ranges can only be used as the bounds of a 'for' loop".to_string(),
            )),

            ExprKind::Assign { op, target, value } => {
                self.check_assign(*op, target, value, expr.span)?;
                Ok(TypeInternal::Unit)
            }

            ExprKind::Return(value) => {
                let expected = self.return_ty.clone();
                match value {
                    Some(v) => {
                        self.check_expr(v, &expected)?;
                    }
                    None => {
                        if expected != TypeInternal::Unit && expected != TypeInternal::Never {
                            return Err(typechecker_error(
                                expr.span,
                                format!("empty return in function returning '{}'", expected),
                            ));
                        }
                    }
                }
                Ok(TypeInternal::Never)
            }

            ExprKind::Break { label, value } => {
                self.check_break(label, value.as_deref(), expr.span)?;
                Ok(TypeInternal::Never)
            }

            ExprKind::Continue { label } => {
                self.find_loop(label, "continue", expr.span)?;
                Ok(TypeInternal::Never)
            }
        }
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
        if let LitValue::Int(v) = value
            && ty.is_integer()
        {
            let limit = if negated && ty.is_signed() {
                v.saturating_sub(1)
            } else {
                v
            };
            self.check_int_fits(limit, &ty, span).map_err(|_| {
                typechecker_error(
                    span,
                    format!(
                        "integer literal {}{} does not fit in type '{}'",
                        if negated { "-" } else { "" },
                        v,
                        ty
                    ),
                )
            })?;
        }
        Ok(ty)
    }

    // A `loop`: its type is its breaks' type, or `!` without a break.
    fn check_loop(
        &mut self,
        label: &Option<(String, Span)>,
        body: &Block,
        expected: Option<&TypeInternal>,
    ) -> TypecheckerResult<TypeInternal> {
        self.loops.push(LoopCtx {
            label: label.as_ref().map(|l| l.0.clone()),
            kind: LoopKind::Loop,
            break_ty: expected.cloned(),
            has_break: false,
        });
        let result = self.check_branch(body, &TypeInternal::Unit);
        let ctx = self.loops.pop().unwrap();
        result?;
        Ok(if ctx.has_break {
            ctx.break_ty.unwrap_or(TypeInternal::Unit)
        } else {
            TypeInternal::Never
        })
    }

    // The loop a `break`/`continue` refers to: the innermost, or the one
    // with the given label.
    fn find_loop(
        &self,
        label: &Option<(String, Span)>,
        what: &str,
        span: Span,
    ) -> TypecheckerResult<usize> {
        match label {
            None => self
                .loops
                .len()
                .checked_sub(1)
                .ok_or_else(|| typechecker_error(span, format!("{} outside of loop", what))),
            Some((name, label_span)) => self
                .loops
                .iter()
                .rposition(|l| l.label.as_deref() == Some(name.as_str()))
                .ok_or_else(|| {
                    typechecker_error(*label_span, format!("unknown loop label ':{}'", name))
                }),
        }
    }

    fn check_break(
        &mut self,
        label: &Option<(String, Span)>,
        value: Option<&Expr>,
        span: Span,
    ) -> TypecheckerResult<()> {
        let idx = self.find_loop(label, "break", span)?;
        let kind = self.loops[idx].kind;
        match value {
            Some(v) if kind != LoopKind::Loop => {
                return Err(typechecker_error(
                    v.span,
                    format!(
                        "'break' with a value is only allowed in 'loop', not in '{}'",
                        if kind == LoopKind::While {
                            "while"
                        } else {
                            "for"
                        }
                    ),
                ));
            }
            Some(v) => match self.loops[idx].break_ty.clone() {
                Some(t) => {
                    self.check_expr(v, &t)?;
                }
                None => {
                    let t = self.synth_expr(v)?;
                    if t != TypeInternal::Never {
                        self.loops[idx].break_ty = Some(t);
                    }
                }
            },
            None => match &self.loops[idx].break_ty {
                Some(t) if *t != TypeInternal::Unit && *t != TypeInternal::Never => {
                    return Err(typechecker_error(
                        span,
                        format!("expected '{}', got '()' (break without a value)", t),
                    ));
                }
                Some(_) => {}
                None => self.loops[idx].break_ty = Some(TypeInternal::Unit),
            },
        }
        self.loops[idx].has_break = true;
        Ok(())
    }

    // `for pattern in a..b { body }`
    fn check_for(
        &mut self,
        label: &Option<(String, Span)>,
        pattern: &Pattern,
        iter: &Expr,
        body: &Block,
    ) -> TypecheckerResult<TypeInternal> {
        let ExprKind::Range { start, end, .. } = &iter.kind else {
            return Err(typechecker_error(
                iter.span,
                "'for' loops can only iterate over integer ranges ('a..b' or 'a..=b')".to_string(),
            ));
        };
        let elem = if literal_takes_rhs_type(start, end) {
            let t = self.synth_expr(end)?;
            self.check_expr(start, &t)?;
            t
        } else {
            let t = self.synth_expr(start)?;
            self.check_expr(end, &t)?;
            t
        };
        if !elem.is_integer() {
            return Err(typechecker_error(
                iter.span,
                format!("range bounds must be integers, got '{}'", elem),
            ));
        }
        // The range node records its element type.
        self.types[iter.id.0 as usize] = Some(elem.clone());
        if let PatternKind::Tuple(_) = pattern.kind {
            return Err(typechecker_error(
                pattern.span,
                "a 'for' loop over a range binds one integer, not a tuple".to_string(),
            ));
        }
        self.env.push_scope();
        self.bind_pattern(pattern, &elem);
        self.loops.push(LoopCtx {
            label: label.as_ref().map(|l| l.0.clone()),
            kind: LoopKind::For,
            break_ty: None,
            has_break: false,
        });
        let result = self.check_branch(body, &TypeInternal::Unit);
        self.loops.pop();
        self.env.pop_scope();
        result?;
        Ok(TypeInternal::Unit)
    }

    fn check_assign(
        &mut self,
        op: AssignOp,
        target: &Expr,
        value: &Expr,
        span: Span,
    ) -> TypecheckerResult<()> {
        let target_ty = self.synth_expr(target)?;
        if !self.is_place(target) {
            let message = match &target.kind {
                ExprKind::Ident(name) if self.const_types.contains_key(name) => {
                    format!("cannot assign to constant '{}'", name)
                }
                ExprKind::Ident(name) if self.signatures.contains_key(name) => {
                    format!("cannot assign to function '{}'", name)
                }
                _ => "invalid assignment target".to_string(),
            };
            return Err(typechecker_error(target.span, message));
        }
        self.check_mutable_place(target)?;
        match op.binop() {
            None => {
                self.check_expr(value, &target_ty)?;
            }
            Some(BinOp::Shl | BinOp::Shr) => {
                if !target_ty.is_integer() {
                    return Err(typechecker_error(
                        span,
                        format!(
                            "shift assignment requires integer type, got '{}'",
                            target_ty
                        ),
                    ));
                }
                // The amount just needs to be an integer of any width.
                let rty = self.synth_expr(value)?;
                if !rty.is_integer() {
                    return Err(typechecker_error(
                        value.span,
                        format!("shift amount must be integer, got '{}'", rty),
                    ));
                }
            }
            Some(BinOp::BitAnd | BinOp::BitOr | BinOp::BitXor) => {
                if !target_ty.is_integer() {
                    return Err(typechecker_error(
                        span,
                        format!(
                            "bitwise assignment requires integer type, got '{}'",
                            target_ty
                        ),
                    ));
                }
                self.check_expr(value, &target_ty)?;
            }
            Some(_) => {
                if !target_ty.is_numeric() {
                    return Err(typechecker_error(
                        span,
                        format!(
                            "compound assignment requires numeric type, got '{}'",
                            target_ty
                        ),
                    ));
                }
                self.check_expr(value, &target_ty)?;
            }
        }
        Ok(())
    }

    // A location that can be assigned to or have its address taken:
    // variables, statics, `*p`, `p[i]`, and fields/elements of places.
    fn is_place(&self, expr: &Expr) -> bool {
        match &expr.kind {
            ExprKind::Ident(name) => {
                self.env.lookup(name).is_some() || self.statics.contains_key(name)
            }
            ExprKind::UnaryOp {
                op: UnaryOp::Deref, ..
            } => true,
            ExprKind::Field { expr: inner, .. } | ExprKind::TupleField { expr: inner, .. } => {
                self.is_place(inner)
            }
            ExprKind::Index { expr: inner, .. } => {
                self.types[inner.id.0 as usize]
                    .as_ref()
                    .is_some_and(|t| t.is_pointer())
                    || self.is_place(inner)
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
                ExprKind::Field { expr, .. } | ExprKind::TupleField { expr, .. } => root = expr,
                ExprKind::Index { expr, .. }
                    if !self.types[expr.id.0 as usize]
                        .as_ref()
                        .is_some_and(|t| t.is_pointer()) =>
                {
                    root = expr
                }
                ExprKind::Ident(name) => {
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
                            span: target.span,
                            help: Some(help),
                        });
                    }
                    if let Some(info) = self.statics.get(name)
                        && !info.mutable
                    {
                        return Err(TypecheckerError {
                            message: format!("cannot assign to immutable static '{}'", name),
                            span: target.span,
                            help: Some(format!("declare it `static mut {}`", name)),
                        });
                    }
                    return Ok(());
                }
                _ => return Ok(()),
            }
        }
    }

    // Binary operators
    fn synth_binop(
        &mut self,
        op: &BinOp,
        lhs: &Expr,
        rhs: &Expr,
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        // Shifts are special: RHS type is independent of LHS (e.g. u64 << u8).
        if matches!(op, BinOp::Shl | BinOp::Shr) {
            let lty = self.synth_expr(lhs)?;
            let rty = self.synth_expr(rhs)?;
            if !lty.is_integer() {
                return Err(typechecker_error(
                    span,
                    format!("shift operator requires integer type, got '{}'", lty),
                ));
            }
            if !rty.is_integer() {
                return Err(typechecker_error(
                    span,
                    format!("shift amount must be integer, got '{}'", rty),
                ));
            }
            return Ok(lty);
        }

        // Check one operand against the other's type so literals pick up the
        // right type, whichever side they are on.
        let lty = if literal_takes_rhs_type(lhs, rhs) {
            let rty = self.synth_expr(rhs)?;
            self.check_expr(lhs, &rty)?;
            rty
        } else {
            let lty = self.synth_expr(lhs)?;
            self.check_expr(rhs, &lty)?;
            lty
        };

        match op {
            BinOp::Add | BinOp::Sub | BinOp::Mul | BinOp::Div | BinOp::Mod => {
                if !lty.is_numeric() {
                    return Err(typechecker_error(
                        span,
                        format!("arithmetic operator requires numeric type, got '{}'", lty),
                    ));
                }
                Ok(lty)
            }
            BinOp::Lt | BinOp::Gt | BinOp::LtEq | BinOp::GtEq => {
                if !lty.is_numeric() && !lty.is_pointer() {
                    return Err(typechecker_error(
                        span,
                        format!("comparison requires numeric type, got '{}'", lty),
                    ));
                }
                Ok(TypeInternal::Bool)
            }
            BinOp::Eq | BinOp::Neq => {
                if !lty.is_numeric()
                    && lty != TypeInternal::Bool
                    && !lty.is_pointer()
                    && !matches!(lty, TypeInternal::Fn { .. })
                {
                    return Err(typechecker_error(
                        span,
                        format!(
                            "equality requires numeric, bool, or pointer type, got '{}'",
                            lty
                        ),
                    ));
                }
                Ok(TypeInternal::Bool)
            }
            BinOp::And | BinOp::Or => {
                if lty != TypeInternal::Bool {
                    return Err(typechecker_error(
                        span,
                        format!("logical operator requires bool, got '{}'", lty),
                    ));
                }
                Ok(TypeInternal::Bool)
            }
            BinOp::BitAnd | BinOp::BitOr | BinOp::BitXor => {
                if !lty.is_integer() {
                    return Err(typechecker_error(
                        span,
                        format!("bitwise operator requires integer type, got '{}'", lty),
                    ));
                }
                Ok(lty)
            }
            // Shifts are handled at the top of synth_binop; this is unreachable
            BinOp::Shl | BinOp::Shr => unreachable!(),
        }
    }

    // Unary operators
    fn synth_unaryop(
        &mut self,
        op: &UnaryOp,
        inner: &Expr,
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        match op {
            UnaryOp::Neg => {
                // `-128i8` fits although `128i8` does not
                let ty = match &inner.kind {
                    ExprKind::SuffixedLiteral(v, s) => {
                        let ty = self.suffixed_literal(*v, *s, true, span)?;
                        self.types[inner.id.0 as usize] = Some(ty.clone());
                        ty
                    }
                    _ => self.synth_expr(inner)?,
                };
                if !ty.is_numeric() {
                    return Err(typechecker_error(
                        span,
                        format!("unary '-' requires numeric type, got '{}'", ty),
                    ));
                }
                Ok(ty)
            }
            UnaryOp::Not => {
                self.check_expr(inner, &TypeInternal::Bool)?;
                Ok(TypeInternal::Bool)
            }
            UnaryOp::BitNot => {
                let ty = self.synth_expr(inner)?;
                if !ty.is_integer() {
                    return Err(typechecker_error(
                        span,
                        format!("bitwise NOT requires integer type, got '{}'", ty),
                    ));
                }
                Ok(ty)
            }
            UnaryOp::Deref => {
                let ty = self.synth_expr(inner)?;
                match ty {
                    TypeInternal::Pointer(pointee) => Ok(*pointee),
                    _ => Err(typechecker_error(
                        span,
                        format!("cannot deref non-pointer type '{}'", ty),
                    )),
                }
            }
            UnaryOp::AddrOf => {
                let ty = self.synth_expr(inner)?;
                // Must be an lvalue
                if !self.is_place(inner) {
                    return Err(typechecker_error(
                        span,
                        "cannot take address of non-lvalue expression".to_string(),
                    ));
                }
                Ok(TypeInternal::Pointer(Box::new(ty)))
            }
        }
    }

    // Function calls
    fn synth_call(
        &mut self,
        callee: &Expr,
        args: &[Expr],
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        // Direct function call by name (unless a local shadows the function)
        if let ExprKind::Ident(name) = &callee.kind
            && self.env.lookup(name).is_none()
            && let Some(sig) = self.signatures.get(name).cloned()
        {
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
                        name,
                        if sig.is_variadic { "at least " } else { "" },
                        sig.params.len(),
                        args.len()
                    ),
                ));
            }
            for (arg, (_pname, pty)) in args.iter().zip(sig.params.iter()) {
                self.check_expr(arg, pty)?;
            }
            // Variadic tail: C only receives scalars here
            for arg in &args[sig.params.len()..] {
                let ty = self.synth_expr(arg)?;
                if !(ty.is_numeric()
                    || matches!(
                        ty,
                        TypeInternal::Bool | TypeInternal::Pointer(_) | TypeInternal::Fn { .. }
                    ))
                {
                    return Err(typechecker_error(
                        arg.span,
                        format!("cannot pass value of type '{}' as a variadic argument", ty),
                    ));
                }
            }
            return Ok(sig.return_ty);
        }

        // Indirect call via fn pointer
        let callee_ty = self.synth_expr(callee)?;
        match &callee_ty {
            TypeInternal::Fn { params, result } => {
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
                for (arg, pty) in args.iter().zip(params.iter()) {
                    self.check_expr(arg, pty)?;
                }
                Ok(*result.clone())
            }
            _ => Err(typechecker_error(
                callee.span,
                format!("cannot call non-function type '{}'", callee_ty),
            )),
        }
    }

    // Struct constructor
    fn check_struct_constructor(
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

        // Check for missing and extra fields
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

        for (fname, fty) in &info.fields {
            match provided.remove(fname.as_str()) {
                Some(fi) => {
                    if let Err(e) = self.check_expr(&fi.value, fty) {
                        self.errors.push(e);
                    }
                }
                None => {
                    self.errors.push(typechecker_error(
                        span,
                        format!("missing field '{}' in struct '{}' constructor", fname, name),
                    ));
                }
            }
        }
        for (extra_name, fi) in &provided {
            self.errors.push(typechecker_error(
                fi.span,
                format!("unknown field '{}' in struct '{}'", extra_name, name),
            ));
        }

        Ok(())
    }

    // Field access
    fn resolve_field_access(
        &self,
        ty: &TypeInternal,
        field: &str,
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        match ty {
            TypeInternal::Struct(name) => {
                let info = self
                    .structs
                    .get(name)
                    .ok_or_else(|| typechecker_error(span, format!("unknown struct '{}'", name)))?;
                info.field_ty(field).cloned().ok_or_else(|| {
                    typechecker_error(span, format!("struct '{}' has no field '{}'", name, field))
                })
            }
            _ => Err(typechecker_error(
                span,
                format!("cannot access field '{}' on type '{}'", field, ty),
            )),
        }
    }

    // Cast validation
    fn check_cast(
        &self,
        from: &TypeInternal,
        to: &TypeInternal,
        span: Span,
    ) -> TypecheckerResult<()> {
        let ok = match (from, to) {
            // int <-> int
            (f, t) if f.is_integer() && t.is_integer() => true,
            // float <-> float
            (f, t) if f.is_float() && t.is_float() => true,
            // int <-> float
            (f, t) if f.is_integer() && t.is_float() => true,
            (f, t) if f.is_float() && t.is_integer() => true,
            // int <-> pointer
            (f, TypeInternal::Pointer(_)) if f.is_integer() => true,
            (TypeInternal::Pointer(_), t) if t.is_integer() => true,
            // pointer <-> pointer
            (TypeInternal::Pointer(_), TypeInternal::Pointer(_)) => true,
            // bool -> int
            (TypeInternal::Bool, t) if t.is_integer() => true,
            (TypeInternal::Never, _) => true,
            _ => false,
        };
        if ok {
            Ok(())
        } else {
            Err(typechecker_error(
                span,
                format!("cannot cast '{}' to '{}'", from, to),
            ))
        }
    }

    // Integer range checking
    fn check_int_fits(&self, value: u64, ty: &TypeInternal, span: Span) -> TypecheckerResult<()> {
        let fits = match ty {
            TypeInternal::U8 => value <= u8::MAX as u64,
            TypeInternal::U16 => value <= u16::MAX as u64,
            TypeInternal::U32 => value <= u32::MAX as u64,
            TypeInternal::U64 => true,
            TypeInternal::I8 => value <= i8::MAX as u64,
            TypeInternal::I16 => value <= i16::MAX as u64,
            TypeInternal::I32 => value <= i32::MAX as u64,
            TypeInternal::I64 => value <= i64::MAX as u64,
            _ => false,
        };
        if fits {
            Ok(())
        } else {
            Err(typechecker_error(
                span,
                format!("integer literal {} does not fit in type '{}'", value, ty),
            ))
        }
    }
}

fn primitive_type(name: &str) -> Option<TypeInternal> {
    Some(match name {
        "i8" => TypeInternal::I8,
        "i16" => TypeInternal::I16,
        "i32" => TypeInternal::I32,
        "i64" | "isize" => TypeInternal::I64,
        "u8" => TypeInternal::U8,
        "u16" => TypeInternal::U16,
        "u32" => TypeInternal::U32,
        "u64" | "usize" => TypeInternal::U64,
        "f32" => TypeInternal::F32,
        "f64" => TypeInternal::F64,
        "bool" => TypeInternal::Bool,
        _ => return None,
    })
}

fn is_primitive_type(name: &str) -> bool {
    primitive_type(name).is_some()
}

// Wraps an integer to the width (and signedness) of `ty`.
fn wrap_int(v: i128, ty: &TypeInternal) -> i128 {
    let bits = ty.int_bits();
    let masked = (v as u128) & ((1u128 << bits) - 1);
    if ty.is_signed() && masked >> (bits - 1) == 1 {
        masked as i128 - (1i128 << bits)
    } else {
        masked as i128
    }
}

fn float_const(f: f64, ty: &TypeInternal) -> ConstValue {
    ConstValue::Float(if *ty == TypeInternal::F32 {
        f as f32 as f64
    } else {
        f
    })
}

// A binary operator on constants with operands of type `operand` and a
// result of type `result`; Err is a message.
fn const_binop(
    op: BinOp,
    a: ConstValue,
    b: ConstValue,
    operand: &TypeInternal,
    result: &TypeInternal,
) -> Result<ConstValue, String> {
    use ConstValue::*;
    Ok(match (a, b) {
        (Int(a), Int(b)) => {
            let wrap = |v: i128| Int(wrap_int(v, result));
            // Unsigned operands are kept non-negative, so i128 arithmetic
            // matches the machine's after wrapping.
            match op {
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
                // The amount is taken modulo the width, as the machine does.
                BinOp::Shl => wrap(a << (b as u32 % operand.int_bits())),
                BinOp::Shr => wrap(a >> (b as u32 % operand.int_bits())),
                BinOp::Eq => Bool(a == b),
                BinOp::Neq => Bool(a != b),
                BinOp::Lt => Bool(a < b),
                BinOp::Gt => Bool(a > b),
                BinOp::LtEq => Bool(a <= b),
                BinOp::GtEq => Bool(a >= b),
                BinOp::And | BinOp::Or => unreachable!(),
            }
        }
        (Float(a), Float(b)) => {
            let f = |v: f64| float_const(v, result);
            match op {
                BinOp::Add => f(a + b),
                BinOp::Sub => f(a - b),
                BinOp::Mul => f(a * b),
                BinOp::Div => f(a / b),
                BinOp::Mod => f(a % b),
                BinOp::Eq => Bool(a == b),
                BinOp::Neq => Bool(a != b),
                BinOp::Lt => Bool(a < b),
                BinOp::Gt => Bool(a > b),
                BinOp::LtEq => Bool(a <= b),
                BinOp::GtEq => Bool(a >= b),
                _ => return Err("invalid operator on floats".to_string()),
            }
        }
        (Bool(a), Bool(b)) => match op {
            BinOp::And => Bool(a && b),
            BinOp::Or => Bool(a || b),
            BinOp::Eq => Bool(a == b),
            BinOp::Neq => Bool(a != b),
            _ => return Err("invalid operator on bools".to_string()),
        },
        _ => return Err("expression is not a compile-time constant".to_string()),
    })
}

fn const_cast(v: ConstValue, from: &TypeInternal, to: &TypeInternal) -> Option<ConstValue> {
    use ConstValue::*;
    let int_like = |t: &TypeInternal| t.is_integer() || t.is_pointer();
    Some(match v {
        Int(i) if int_like(to) => Int(wrap_int(i, to)),
        Int(i) if to.is_float() => float_const(i as f64, to),
        Float(f) if to.is_float() => float_const(f, to),
        // Saturating, NaN to 0 (Rust `as` semantics)
        Float(f) if to.is_integer() => {
            let i = match to {
                TypeInternal::I8 => f as i8 as i128,
                TypeInternal::I16 => f as i16 as i128,
                TypeInternal::I32 => f as i32 as i128,
                TypeInternal::I64 => f as i64 as i128,
                TypeInternal::U8 => f as u8 as i128,
                TypeInternal::U16 => f as u16 as i128,
                TypeInternal::U32 => f as u32 as i128,
                _ => f as u64 as i128,
            };
            Int(i)
        }
        Bool(b) if to.is_integer() => Int(b as i128),
        _ => {
            let _ = from;
            return None;
        }
    })
}

/// Result of a successful type check — contains resolved struct/function info
/// needed by later passes (lowering, codegen).
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
        self.types[expr.id.0 as usize]
            .as_ref()
            .unwrap_or_else(|| panic!("ICE: expression without a type at {:?}", expr.span))
    }

    // Control never continues past the expression.
    pub fn diverges(&self, expr: &Expr) -> bool {
        self.diverges[expr.id.0 as usize]
    }
}

// A numeric literal (optionally negated) whose type comes from context.
// Lowering uses the same predicate to pick operand types, so the two stay
// in agreement.
pub fn is_untyped_literal(expr: &Expr) -> bool {
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
pub fn literal_takes_rhs_type(lhs: &Expr, rhs: &Expr) -> bool {
    is_untyped_literal(lhs) && !is_untyped_literal(rhs)
}

pub fn typecheck(program: &Program) -> Result<CheckedProgram, Vec<TypecheckerError>> {
    Typechecker::check_program(program)
}

#[cfg(test)]
mod tests {
    use crate::parser::ParserError;

    use super::*;

    pub fn parse_source(src: &str) -> Result<Program, ParserError> {
        crate::parser::parse(crate::lexer::Lexer::new(src).tokenize().unwrap())
            .map_err(|mut errors| errors.remove(0))
    }

    fn check_ok(src: &str) {
        let prog = parse_source(src).unwrap_or_else(|e| panic!("parse error: {}", e));
        if let Err(errs) = typecheck(&prog) {
            let msgs: Vec<_> = errs.iter().map(|e| e.to_string()).collect();
            panic!("type errors:\n{}\nsource: {}", msgs.join("\n"), src);
        }
    }

    fn check_err(src: &str) -> Vec<TypecheckerError> {
        let prog = parse_source(src).unwrap_or_else(|e| panic!("parse error: {}", e));
        match typecheck(&prog) {
            Ok(_) => panic!("expected type error for: {}", src),
            Err(errs) => errs,
        }
    }

    fn check_err_contains(src: &str, substr: &str) {
        let errs = check_err(src);
        let all_msgs: Vec<_> = errs.iter().map(|e| e.message.clone()).collect();
        assert!(
            all_msgs.iter().any(|m| m.contains(substr)),
            "expected error containing '{}', got: {:?}\nsource: {}",
            substr,
            all_msgs,
            src
        );
    }

    // Basic valid programs
    #[test]
    fn test_empty_program() {
        check_ok("");
    }

    #[test]
    fn test_simple_function() {
        check_ok("fn main() {}");
    }

    #[test]
    fn test_fn_return_type() {
        check_ok("fn main() -> i32 { 0 }");
    }

    #[test]
    fn test_fn_return_unit_implicit() {
        check_ok("fn main() {}");
    }

    #[test]
    fn test_fn_return_unit_explicit() {
        check_ok("fn main() -> () { () }");
    }

    // Let bindings and type inference
    #[test]
    fn test_let_infer_int() {
        check_ok("fn main() { let x = 42; }");
    }

    #[test]
    fn test_let_annotated() {
        check_ok("fn main() { let x: i32 = 42; }");
    }

    #[test]
    fn test_let_annotated_u8() {
        check_ok("fn main() { let x: u8 = 255; }");
    }

    #[test]
    fn test_let_u8_overflow() {
        check_err_contains("fn main() { let x: u8 = 256; }", "does not fit");
    }

    #[test]
    fn test_let_i8_overflow() {
        check_err_contains("fn main() { let x: i8 = 128; }", "does not fit");
    }

    #[test]
    fn test_let_float_annotated() {
        check_ok("fn main() { let x: f32 = 3.14; }");
    }

    #[test]
    fn test_let_int_in_float_context() {
        check_err("fn main() { let x: f64 = 42; }");
    }

    #[test]
    fn test_let_bool() {
        check_ok("fn main() { let x = true; let y = false; }");
    }

    // String literals
    #[test]
    fn test_string_literal_type() {
        // String is (*u8, u64), so accessing .1 gives u64
        check_ok(
            r#"
            fn main() -> u64 {
                let s = "hello";
                s.1
            }
        "#,
        );
    }

    #[test]
    fn test_string_as_tuple_param() {
        check_ok(
            r#"
            fn get_len(s: (*u8, u64)) -> u64 { s.1 }
            fn main() -> u64 { get_len("Alice") }
        "#,
        );
    }

    // Arithmetic and operators
    #[test]
    fn test_arithmetic() {
        check_ok("fn main() { let x: i32 = 1; let y: i32 = 2; let z = x + y; }");
    }

    #[test]
    fn test_arithmetic_type_mismatch() {
        check_err_contains(
            "fn main() { let x: i32 = 1; let y: i64 = 2; let z = x + y; }",
            "expected 'i32', got 'i64'",
        );
    }

    #[test]
    fn test_comparison() {
        check_ok("fn main() { let x: i32 = 1; let b = x < 2; }");
    }

    #[test]
    fn test_logical() {
        check_ok("fn main() { let b = true && false || true; }");
    }

    #[test]
    fn test_logical_non_bool() {
        check_err_contains(
            "fn main() { let x = 1 && 2; }",
            "logical operator requires bool",
        );
    }

    #[test]
    fn test_bitwise() {
        check_ok("fn main() { let x: u32 = 0xFF; let y = x & 0x0F; }");
    }

    #[test]
    fn test_bitwise_on_float() {
        check_err_contains(
            "fn main() { let x: f64 = 1.0; let y = x & 1.0; }",
            "bitwise operator requires integer",
        );
    }

    #[test]
    fn test_shift() {
        check_ok("fn main() { let x: u32 = 1; let y = x << 4; }");
        check_ok("fn main() { let x: u64 = 256; let y = x >> 2; }");
    }

    #[test]
    fn test_shift_different_rhs_type() {
        // RHS type doesn't need to match LHS — u64 << u8 is fine
        check_ok("fn main() { let x: u64 = 1; let s: u8 = 4; let y = x << s; }");
    }

    #[test]
    fn test_shift_on_float() {
        check_err_contains(
            "fn main() { let x: f64 = 1.0; let y = x << 1; }",
            "shift operator requires integer",
        );
    }

    #[test]
    fn test_shift_assign() {
        check_ok("fn main() { let mut x: u32 = 1; x <<= 4; x >>= 2; }");
    }

    #[test]
    fn test_shift_assign_on_float() {
        check_err_contains(
            "fn main() { let mut x: f64 = 1.0; x <<= 1; }",
            "shift assignment requires integer",
        );
    }

    #[test]
    fn test_double_star_is_two_derefs() {
        // `**` is not an operator: `x ** 3` dereferences `3`.
        check_err_contains(
            "fn main() { let x: i32 = 2; let y = x ** 3; }",
            "cannot deref non-pointer type",
        );
        check_ok("fn f(pp: **i64) -> i64 { **pp }");
    }

    // Unary operators
    #[test]
    fn test_neg() {
        check_ok("fn main() { let x: i32 = 5; let y = -x; }");
    }

    #[test]
    fn test_not() {
        check_ok("fn main() { let x = !true; }");
    }

    #[test]
    fn test_bitnot() {
        check_ok("fn main() { let x: u32 = 0xFF; let y = ~x; }");
    }

    #[test]
    fn test_bitnot_on_bool() {
        check_err_contains(
            "fn main() { let x = ~true; }",
            "bitwise NOT requires integer",
        );
    }

    #[test]
    fn test_deref() {
        check_ok("fn main() { let x: i32 = 42; let p = &x; let y = *p; }");
    }

    #[test]
    fn test_addr_of() {
        check_ok("fn main() { let x: i32 = 42; let p = &x; }");
    }

    #[test]
    fn test_addr_of_non_lvalue() {
        check_err_contains(
            "fn main() { let p = &42; }",
            "cannot take address of non-lvalue",
        );
    }

    // Cast
    #[test]
    fn test_cast_int_to_float() {
        check_ok("fn main() { let x: i32 = 42; let y = x as f64; }");
    }

    #[test]
    fn test_cast_float_to_int() {
        check_ok("fn main() { let x: f64 = 3.14; let y = x as i32; }");
    }

    #[test]
    fn test_cast_int_widening() {
        check_ok("fn main() { let x: i32 = 42; let y = x as i64; }");
    }

    #[test]
    fn test_cast_bool_to_int() {
        check_ok("fn main() { let b = true; let x = b as i32; }");
    }

    #[test]
    fn test_cast_ptr_to_int() {
        check_ok("fn main() { let x: i32 = 0; let p = &x; let n = p as u64; }");
    }

    #[test]
    fn test_cast_invalid() {
        check_err_contains(
            "fn main() { let b = true; let x = b as f64; }",
            "cannot cast",
        );
    }

    // Function calls
    #[test]
    fn test_call_basic() {
        check_ok("fn foo() -> i32 { 42 } fn main() { let x = foo(); }");
    }

    #[test]
    fn test_call_with_args() {
        check_ok("fn add(a: i32, b: i32) -> i32 { a + b } fn main() { let x = add(1, 2); }");
    }

    #[test]
    fn test_call_arg_type_push() {
        // Literal 1 should be checked against i32 parameter type
        check_ok("fn foo(x: i32) {} fn main() { foo(1); }");
    }

    #[test]
    fn test_call_wrong_arg_count() {
        check_err_contains(
            "fn foo(a: i32) {} fn main() { foo(1, 2); }",
            "expects 1 arguments, got 2",
        );
    }

    #[test]
    fn test_call_too_few_args() {
        check_err_contains(
            "fn foo(a: i32, b: i32) {} fn main() { foo(1); }",
            "expects 2 arguments, got 1",
        );
    }

    #[test]
    fn test_call_variadic_too_few_args() {
        check_err_contains(
            "extern fn printf(f: *u8, ...) -> i32; fn main() { printf(); }",
            "expects at least 1 arguments, got 0",
        );
    }

    #[test]
    fn test_call_variadic_extra_args_checked() {
        check_err_contains(
            r#"extern fn printf(f: *u8, ...) -> i32; fn main() { printf("%d".0, nope); }"#,
            "undefined variable",
        );
    }

    #[test]
    fn test_call_variadic_rejects_compound() {
        check_err_contains(
            r#"extern fn printf(f: *u8, ...) -> i32; fn main() { printf("%s".0, "hi"); }"#,
            "variadic argument",
        );
    }

    #[test]
    fn test_call_variadic_scalars_ok() {
        check_ok(
            r#"extern fn printf(f: *u8, ...) -> i32;
            fn main() { let x: u8 = 1; let y: f32 = 2.0; printf("%d %f".0, x, y, &x); }"#,
        );
    }

    #[test]
    fn test_call_wrong_arg_type() {
        check_err_contains(
            "fn foo(a: i32) {} fn main() { let b = true; foo(b); }",
            "expected 'i32', got 'bool'",
        );
    }

    #[test]
    fn test_call_extern() {
        check_ok(
            r#"
            extern fn puts(s: *u8) -> i32;
            fn main() { let x: i32 = 42; let p = &x as *u8; puts(p); }
        "#,
        );
    }

    // Structs
    #[test]
    fn test_struct_basic() {
        check_ok(
            r#"
            struct Point { x: i32, y: i32 }
            fn main() {
                let p = Point { x: 10, y: 20 };
            }
        "#,
        );
    }

    #[test]
    fn test_struct_field_access() {
        check_ok(
            r#"
            struct Point { x: i32, y: i32 }
            fn main() -> i32 {
                let p = Point { x: 10, y: 20 };
                p.x + p.y
            }
        "#,
        );
    }

    #[test]
    fn test_struct_missing_field() {
        check_err_contains(
            "struct Point { x: i32, y: i32 } fn main() { let p = Point { x: 10 }; }",
            "missing field 'y'",
        );
    }

    #[test]
    fn test_struct_extra_field() {
        check_err_contains(
            "struct Point { x: i32 } fn main() { let p = Point { x: 1, y: 2 }; }",
            "unknown field 'y'",
        );
    }

    #[test]
    fn test_struct_field_type_check() {
        // Literal should be checked against field type
        check_ok(
            r#"
            struct Foo { val: u8 }
            fn main() { let f = Foo { val: 255 }; }
        "#,
        );
    }

    #[test]
    fn test_struct_field_type_overflow() {
        check_err_contains(
            "struct Foo { val: u8 } fn main() { let f = Foo { val: 256 }; }",
            "does not fit",
        );
    }

    #[test]
    fn test_struct_nonexistent_field_access() {
        check_err_contains(
            "struct Point { x: i32 } fn main() { let p = Point { x: 1 }; let q = p.y; }",
            "no field 'y'",
        );
    }

    #[test]
    fn test_duplicate_struct() {
        check_err_contains("struct A {} struct A {}", "duplicate struct");
    }

    #[test]
    fn test_recursive_struct_error() {
        check_err_contains("struct Node { next: Node }", "infinite size");
    }

    #[test]
    fn test_recursive_struct_via_pointer_ok() {
        check_ok("struct Node { val: i32, next: *Node }");
    }

    // Arrays
    #[test]
    fn test_array_literal() {
        check_ok("fn main() { let arr = [1, 2, 3]; }");
    }

    #[test]
    fn test_array_annotated() {
        check_ok("fn main() { let arr: [i32; 3] = [1, 2, 3]; }");
    }

    #[test]
    fn test_array_size_mismatch() {
        check_err_contains(
            "fn main() { let arr: [i32; 3] = [1, 2]; }",
            "2 elements, expected 3",
        );
    }

    #[test]
    fn test_array_repeat() {
        check_ok("fn main() { let arr = [0; 10]; }");
    }

    #[test]
    fn test_array_index() {
        check_ok("fn main() { let arr = [1, 2, 3]; let x = arr[0]; }");
    }

    #[test]
    fn test_array_index_non_integer() {
        check_err_contains(
            "fn main() { let arr = [1, 2, 3]; let x = arr[true]; }",
            "index must be integer",
        );
    }

    // Tuples
    #[test]
    fn test_tuple_literal() {
        check_ok("fn main() { let t = (1, true); }");
    }

    #[test]
    fn test_tuple_annotated() {
        check_ok("fn main() { let t: (i32, bool) = (42, true); }");
    }

    #[test]
    fn test_tuple_field() {
        check_ok("fn main() { let t = (1, true); let x = t.0; let b = t.1; }");
    }

    #[test]
    fn test_tuple_field_out_of_range() {
        check_err_contains("fn main() { let t = (1, 2); let x = t.5; }", "out of range");
    }

    #[test]
    fn test_tuple_arity_mismatch() {
        check_err_contains(
            "fn main() { let t: (i32, i32) = (1, 2, 3); }",
            "3 elements, expected 2",
        );
    }

    // If expressions
    #[test]
    fn test_if_else_same_type() {
        check_ok("fn main() -> i32 { if true { 1 } else { 2 } }");
    }

    #[test]
    fn test_if_else_different_types() {
        check_err_contains(
            "fn main() { let x = if true { 1 } else { true }; }",
            "different types",
        );
    }

    #[test]
    fn test_if_no_else_unit() {
        check_ok("fn main() { if true { let x = 1; }; }");
    }

    #[test]
    fn test_if_no_else_non_unit() {
        check_err_contains(
            "fn main() { let x = if true { 1 }; }",
            "if without else must have type '()'",
        );
    }

    #[test]
    fn test_if_condition_non_bool() {
        check_err_contains(
            "fn main() { if 42 { let x = 1; }; }",
            "expected 'bool', got 'i64'",
        );
    }

    // Blocks
    #[test]
    fn test_block_expression() {
        check_ok("fn main() -> i32 { { let x: i32 = 1; x + 1 } }");
    }

    #[test]
    fn test_block_no_tail_is_unit() {
        check_ok("fn main() { { let x = 1; }; }");
    }

    // Loops
    #[test]
    fn test_loop_basic() {
        check_ok("fn main() { loop { break; } }");
    }

    #[test]
    fn test_break_outside_loop() {
        check_err_contains("fn main() { break; }", "break outside of loop");
    }

    #[test]
    fn test_continue_outside_loop() {
        check_err_contains("fn main() { continue; }", "continue outside of loop");
    }

    #[test]
    fn test_nested_loops() {
        check_ok("fn main() { loop { loop { break; } break; } }");
    }

    // Return
    #[test]
    fn test_return_value() {
        check_ok("fn main() -> i32 { return 0; }");
    }

    #[test]
    fn test_return_void() {
        check_ok("fn main() { return; }");
    }

    #[test]
    fn test_return_type_mismatch() {
        check_err_contains(
            "fn main() -> i32 { return true; }",
            "expected 'i32', got 'bool'",
        );
    }

    #[test]
    fn test_empty_return_in_non_void() {
        check_err_contains("fn main() -> i32 { return; }", "empty return");
    }

    // Assignments
    #[test]
    fn test_simple_assign() {
        check_ok("fn main() { let mut x: i32 = 0; x = 42; }");
    }

    #[test]
    fn test_compound_assign() {
        check_ok("fn main() { let mut x: i32 = 0; x += 1; x -= 2; }");
    }

    #[test]
    fn test_compound_assign_non_numeric() {
        check_err_contains(
            "fn main() { let mut x = true; x += true; }",
            "compound assignment requires numeric",
        );
    }

    #[test]
    fn test_assign_type_mismatch() {
        check_err_contains(
            "fn main() { let mut x: i32 = 0; x = true; }",
            "expected 'i32', got 'bool'",
        );
    }

    #[test]
    fn test_assign_through_deref() {
        check_ok(
            r#"
            fn main() {
                let x: i32 = 0;
                let p = &x;
                *p = 42;
            }
        "#,
        );
    }

    #[test]
    fn test_assign_struct_field() {
        check_ok(
            r#"
            struct Point { x: i32, y: i32 }
            fn main() {
                let mut p = Point { x: 0, y: 0 };
                p.x = 10;
            }
        "#,
        );
    }

    #[test]
    fn test_assign_array_index() {
        check_ok(
            r#"
            fn main() {
                let mut arr = [0, 0, 0];
                arr[1] = 42;
            }
        "#,
        );
    }

    // Pointer types
    #[test]
    fn test_pointer_type() {
        check_ok("fn foo(p: *i32) -> i32 { *p }");
    }

    #[test]
    fn test_double_pointer() {
        check_ok(
            r#"
            fn main() {
                let x: i32 = 42;
                let p = &x;
                let pp = &p;
                let val = **pp;
            }
        "#,
        );
    }

    // Function pointers
    #[test]
    fn test_fn_ptr_type() {
        check_ok(
            r#"
            fn add(a: i32, b: i32) -> i32 { a + b }
            fn apply(f: fn(i32, i32) -> i32, x: i32, y: i32) -> i32 {
                f(x, y)
            }
        "#,
        );
    }

    // Duplicate function
    #[test]
    fn test_duplicate_function() {
        check_err_contains("fn foo() {} fn foo() {}", "duplicate function");
    }

    // Unknown type
    #[test]
    fn test_unknown_type() {
        check_err_contains("fn foo(x: Nonexistent) {}", "unknown type");
    }

    // Body type mismatch
    #[test]
    fn test_body_type_mismatch() {
        check_err_contains("fn main() -> i32 { true }", "expected 'i32', got 'bool'");
    }

    // Comprehensive program
    #[test]
    fn test_comprehensive() {
        check_ok(
            r#"
            struct Vec2 { x: f64, y: f64 }

            extern fn sqrt(x: f64) -> f64;

            fn length(v: Vec2) -> f64 {
                let sq = v.x * v.x + v.y * v.y;
                sqrt(sq)
            }

            fn dot(a: Vec2, b: Vec2) -> f64 {
                a.x * b.x + a.y * b.y
            }

            fn abs(x: i32) -> i32 {
                if x < 0 { -x } else { x }
            }

            fn fib(n: i32) -> i32 {
                let mut a: i32 = 0;
                let mut b: i32 = 1;
                let mut i: i32 = 0;
                loop {
                    if i == n { break; };
                    let temp = b;
                    b = a + b;
                    a = temp;
                    i += 1;
                }
                a
            }

            fn main() -> i32 {
                let v = Vec2 { x: 3.0, y: 4.0 };
                let len = length(v);

                let arr: [i32; 5] = [1, 2, 3, 4, 5];
                let mut sum: i32 = 0;
                let mut i: i32 = 0;
                loop {
                    if i == 5 { break; };
                    sum += arr[i];
                    i += 1;
                }

                let pair: (i32, i32) = (10, 20);
                let first = pair.0;
                let answer = fib(10);
                let ptr = &sum;
                let val = *ptr;
                let mask = 0xFF & (0b1010 | 0x0F);
                let big = 2 * 3 * 2;
                let cast_val = 42 as f64;
                let flag = true && !false || 1 != 2;
                0
            }
        "#,
        );
    }

    #[test]
    fn test_string_comprehensive() {
        check_ok(
            r#"
            fn get_len(s: (*u8, u64)) -> u64 {
                s.1
            }
            fn main() -> u64 {
                let name = "Alice";
                get_len(name)
            }
        "#,
        );
    }

    // usize alias
    #[test]
    fn test_usize_alias() {
        check_ok("fn main() { let x: usize = 42; }");
    }

    // Bidirectional literal checking through nested structures
    #[test]
    fn test_literal_push_through_array() {
        // Without annotation, elements default to i64.
        // With annotation, 1/2/3 are checked as u8.
        check_ok("fn main() { let arr: [u8; 3] = [1, 2, 3]; }");
    }

    #[test]
    fn test_literal_push_through_tuple() {
        check_ok("fn main() { let t: (u8, f32) = (42, 3.14); }");
    }

    #[test]
    fn test_literal_push_through_fn_args() {
        // Function param types push into literal arguments
        check_ok("fn foo(a: u16, b: f32) {} fn main() { foo(1000, 2.5); }");
    }

    // Edge cases
    #[test]
    fn test_empty_struct_constructor() {
        check_ok("struct Empty {} fn main() { let e = Empty {}; }");
    }

    #[test]
    fn test_nested_struct() {
        check_ok(
            r#"
                struct Inner { val: i32 }
                struct Outer { inner: Inner }
                fn main() -> i32 {
                    let o = Outer { inner: Inner { val: 42 } };
                    o.inner.val
                }
            "#,
        );
    }

    #[test]
    fn test_mutual_recursive_structs() {
        check_err_contains("struct A { b: B } struct B { a: A }", "infinite size");
    }

    #[test]
    fn test_mutual_recursive_via_pointer_ok() {
        check_ok("struct A { b: *B } struct B { a: *A }");
    }

    #[test]
    fn test_deref_non_pointer() {
        check_err_contains(
            "fn main() { let x: i32 = 42; let y = *x; }",
            "cannot deref non-pointer",
        );
    }

    #[test]
    fn test_call_non_function() {
        check_err_contains(
            "fn main() { let x: i32 = 42; x(1); }",
            "cannot call non-function",
        );
    }

    #[test]
    fn test_index_non_array() {
        check_err_contains(
            "fn main() { let x: i32 = 42; let y = x[0]; }",
            "cannot index type",
        );
    }

    #[test]
    fn test_field_on_non_struct() {
        check_err_contains(
            "fn main() { let x: i32 = 42; let y = x.foo; }",
            "cannot access field",
        );
    }

    #[test]
    fn test_undefined_variable() {
        check_err_contains("fn main() { let x = y; }", "undefined variable 'y'");
    }

    #[test]
    fn test_scope_isolation() {
        check_err_contains(
            "fn main() { { let x: i32 = 1; }; let y = x; }",
            "undefined variable 'x'",
        );
    }

    #[test]
    fn test_shadowing() {
        check_ok(
            r#"
            fn main() -> bool {
                let x: i32 = 42;
                let x = true;
                x
            }
        "#,
        );
    }

    #[test]
    fn test_literal_takes_context_type() {
        check_ok("fn main() { let x: u8 = 1 + 2; let y: i8 = -128; let z: i32 = 0 - 7; }");
        check_ok("fn main() { let x: u8 = 3; let y = 1 + x; let b = 0 == x; let c: u8 = y; }");
        check_ok("fn main() { let x: u32 = (1 << 31) | 5; let f: f32 = -1.5; }");
        check_err_contains("fn main() { let x: i8 = -129; }", "-129 does not fit");
        check_err_contains(
            "fn main() { let a: u32 = 1; let x: u64 = a + 1; }",
            "expected 'u64', got 'u32'",
        );
    }

    #[test]
    fn test_diverging_bodies() {
        check_ok("fn f(c: bool) -> i64 { if c { return 1; } else { return 2; }; }");
        check_ok("fn f() -> i64 { loop { return 1; } }");
        check_ok("fn f(c: bool) -> i64 { let x: i64 = if c { return 0; } else { 5 }; x }");
        check_err_contains(
            "fn f(c: bool) -> i64 { loop { if c { break; }; return 1; } }",
            "expected 'i64', got '()' (break without a value)",
        );
        check_err_contains(
            "fn f(c: bool) -> i64 { if c { return 1; }; }",
            "body has type '()'",
        );
        // a break inside a nested loop does not leave the outer one
        check_ok("fn f() -> i64 { loop { loop { break; } return 1; } }");
    }

    #[test]
    fn test_block_without_tail_has_unit_type() {
        check_err_contains("fn main() { let x: i64 = {}; }", "expected 'i64', got '()'");
        check_err_contains(
            "fn main() { let x: i64 = if true { 1 } else { }; }",
            "expected 'i64', got '()'",
        );
    }

    #[test]
    fn test_function_as_value() {
        check_ok(
            "fn g(x: i64) -> i64 { x } fn main() { let f: fn(i64) -> i64 = g; let y = f(1); let e = f == g; }",
        );
        check_err_contains(
            "extern fn printf(f: *u8, ...) -> i32; fn main() { let p = printf; }",
            "variadic function 'printf' cannot be used as a value",
        );
    }

    // ---- never type, loops, labels ----

    #[test]
    fn test_never_coerces_everywhere() {
        check_ok("fn f(c: bool) -> i64 { let x: i64 = if c { 1 } else { return 2 }; x }");
        check_ok("fn f() -> i64 { loop {} }");
        check_ok("fn f(c: bool) -> i64 { if c { return 1 } else { return 2 } }");
        check_ok("extern fn exit(c: i32) -> !; fn f() -> (i64, bool) { exit(1) }");
        check_ok("fn f() -> i64 { let x = return 3; }");
        check_ok("fn f() { let v: [i64; 2] = [1, loop { break 2; }]; }");
    }

    #[test]
    fn test_loop_values() {
        check_ok("fn f() -> u8 { loop { break 200; } }");
        check_ok("fn f() -> i64 { outer: loop { loop { break :outer 1; } } }");
        check_err_contains(
            "fn f() -> i64 { loop { break true; } }",
            "expected 'i64', got 'bool'",
        );
        check_err_contains(
            "fn f(c: bool) { let x = loop { if c { break 1; } break; }; }",
            "break without a value",
        );
        check_err_contains(
            "fn f() { while true { break 1; } }",
            "only allowed in 'loop'",
        );
        check_err_contains(
            "fn f() { for i in 0..3 { continue :x; } }",
            "unknown loop label ':x'",
        );
        check_err_contains("fn f() { break; }", "break outside of loop");
    }

    #[test]
    fn test_block_like_statement_must_be_unit() {
        check_err_contains(
            "fn f(c: bool) -> i64 { if c { 1 } else { 2 } 3 }",
            "expected '()', got 'i64'",
        );
        check_ok("fn f(c: bool) -> i64 { if c { 1 } else { 2 }; 3 }");
    }

    #[test]
    fn test_for_ranges() {
        check_ok("fn f() { for i in 0u8..=255 { let x: u8 = i; } }");
        check_ok("fn f(n: u32) { for i in 0..n { let x: u32 = i; } }");
        check_err_contains(
            "fn f() { for i in 0.0..1.0 { } }",
            "range bounds must be integers",
        );
        check_err_contains("fn f() { let r = 1..2; }", "ranges can only be used");
    }

    // ---- constants, statics, aliases ----

    fn const_value(src: &str, name: &str) -> ConstValue {
        let prog = parse_source(src).unwrap();
        let checked = typecheck(&prog).unwrap_or_else(|e| panic!("{:?}", e));
        checked.consts[name].value.clone()
    }

    #[test]
    fn test_const_evaluation() {
        assert_eq!(
            const_value("const A: i64 = (1 << 10) - 24 / 3;", "A"),
            ConstValue::Int(1016)
        );
        assert_eq!(
            const_value("const A: u8 = 250 + 10;", "A"),
            ConstValue::Int(4)
        );
        assert_eq!(
            const_value("const A: i8 = 127 + 1;", "A"),
            ConstValue::Int(-128)
        );
        assert_eq!(
            const_value("const A: u32 = ~0u32 >> 4;", "A"),
            ConstValue::Int(0x0FFF_FFFF)
        );
        assert_eq!(
            const_value("const A: i64 = -7 % 3;", "A"),
            ConstValue::Int(-1)
        );
        assert_eq!(
            const_value("const A: f32 = 0.1;", "A"),
            ConstValue::Float(0.1f32 as f64)
        );
        assert_eq!(
            const_value("const A: i32 = 2.9 as i32;", "A"),
            ConstValue::Int(2)
        );
        assert_eq!(
            const_value(
                "const A: bool = B > 2 && B < 5; const B: u8 = 'a' - 94;",
                "A"
            ),
            ConstValue::Bool(true)
        );
        check_err_contains("const A: i64 = 1 / 0;", "division by zero");
        check_err_contains(
            "const A: i64 = B; const B: i64 = A;",
            "defined in terms of itself",
        );
        check_err_contains(
            "fn g() -> i64 { 1 } const A: i64 = g();",
            "not a compile-time constant",
        );
        check_err_contains(
            "const A: (i64, i64) = (1, 2);",
            "constants must be integers, floats or bool",
        );
    }

    #[test]
    fn test_const_array_sizes() {
        check_ok(
            "const N: i64 = 4; fn f() { let a: [u8; N * 2] = [0; 8]; let b = [1; N]; let c: [i64; 4] = b; }",
        );
        check_err_contains(
            "fn f() { let a: [u8; 2 - 3] = []; }",
            "must not be negative",
        );
        check_err_contains(
            "fn f() { let a: [u8; 1.5] = []; }",
            "array length must be an integer",
        );
        check_err_contains(
            "fn f() { let a: [u8; 3] = [0; 4]; }",
            "array repeat count is 4, expected 3",
        );
    }

    #[test]
    fn test_statics() {
        check_ok("static mut C: i64 = 0; fn f() { C += 1; let p = &C; }");
        check_ok(
            "struct P { a: i32, b: (u8, bool) } static S: P = P { b: (1, true), a: -1 }; fn f() -> i32 { S.a }",
        );
        check_err_contains(
            "static S: i64 = 0; fn f() { S = 1; }",
            "cannot assign to immutable static 'S'",
        );
        check_err_contains(
            "fn g() -> i64 { 1 } static S: i64 = g();",
            "not a compile-time constant",
        );
    }

    #[test]
    fn test_type_aliases() {
        check_ok("type B = u8; type P = *B; type Arr = [P; 2]; fn f(a: Arr) -> B { *a[0] }");
        check_err_contains("type A = (A, i64);", "defined in terms of itself");
        check_err_contains("type A = Nope;", "unknown type 'Nope'");
        check_err_contains("type A = i64; struct A { x: i64 }", "duplicate");
    }

    // ---- literals, pointers, patterns ----

    #[test]
    fn test_char_and_suffixed_literals() {
        check_ok(
            "fn f() { let c = 'a'; let d: u8 = c; let e: i32 = 'b'; let s: i16 = -128i8 as i16; }",
        );
        check_ok("fn f() { let x = 1u8 + 2; let y: u8 = x; let z = 2f32 * 1.5; let w: f32 = z; }");
        check_err_contains("fn f() { let x = 300u8; }", "does not fit in type 'u8'");
        check_err_contains(
            "fn f() { let x = -129i8; }",
            "-129 does not fit in type 'i8'",
        );
        check_err_contains("fn f() { let x: f64 = 'a'; }", "expected 'f64', got 'u8'");
        check_ok("fn f() -> *u8 { c\"hi\" }");
    }

    #[test]
    fn test_pointer_indexing() {
        check_ok("fn f(p: *i64, i: u8) -> i64 { p[i] = 1; let q: *i64 = &p[2]; p[0] + q[0] }");
        check_err_contains("fn f(p: *i64) -> i64 { p[1.0] }", "index must be integer");
    }

    #[test]
    fn test_let_patterns() {
        check_ok(
            "fn f() { let (a, (b, mut c), _) = (1, (true, 2.5), 3); c += 1.0; let x: bool = b; }",
        );
        check_err_contains(
            "fn f() { let (a, b) = 1; }",
            "tuple pattern with 2 elements",
        );
        check_err_contains(
            "fn f() { let (a, b) = (1, 2, 3); }",
            "tuple pattern with 2 elements",
        );
        check_err_contains(
            "fn f() { let (a, b) = (1, 2); a = 3; }",
            "immutable variable 'a'",
        );
    }

    // ---- mutability ----

    #[test]
    fn test_mutability() {
        check_ok("fn f(mut n: i64) -> i64 { n -= 1; n }");
        check_ok("fn f() { let x = 1; let p = &x; *p = 2; }");
        check_ok("fn f() { let a = [1, 2]; let p = &a[0]; p[1] = 3; }");
        let errs = check_err("fn f() { let x = 1; x = 2; }");
        assert_eq!(
            errs[0].help.as_deref(),
            Some("make it mutable: `let mut x`")
        );
        let errs = check_err("fn f(n: i64) { n += 1; }");
        assert_eq!(
            errs[0].help.as_deref(),
            Some("make the parameter mutable: `mut n: i64`")
        );
        check_err_contains(
            "struct P { x: i64 } fn f() { let p = P { x: 1 }; p.x = 2; }",
            "immutable variable 'p'",
        );
        check_err_contains(
            "fn f() { let a = [[0; 2]; 2]; a[1][1] = 2; }",
            "immutable variable 'a'",
        );
        check_err_contains(
            "fn f() { for i in 0..3 { i += 1; } }",
            "immutable variable 'i'",
        );
        check_ok("fn f() { for mut i in 0..3 { i += 1; } }");
    }

    #[test]
    fn test_assignment_targets() {
        check_err_contains(
            "struct P { x: i64 } fn mk() -> P { P { x: 1 } } fn f() { mk().x = 2; }",
            "invalid assignment target",
        );
        check_err_contains(
            "const N: i64 = 1; fn f() { N = 2; }",
            "cannot assign to constant 'N'",
        );
        check_err_contains(
            "fn g() {} fn f() { g = g; }",
            "cannot assign to function 'g'",
        );
        check_ok("fn f() { let mut x = 0; let u: () = (x = 1); }");
    }

    #[test]
    fn test_local_shadows_function_in_calls() {
        check_ok(
            "fn g(x: i64) -> i64 { x } fn h(x: i64) -> i64 { x } fn f() -> i64 { let g = h; g(1) }",
        );
    }
}
