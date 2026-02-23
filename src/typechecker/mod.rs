// Bidirectional Type Checker
//
// Two-pass design:
//   Pass 1 — Collect all struct definitions and function signatures into global
//            environments. Detect duplicate names. Detect infinite-size structs.
//            Resolve all AST types to Ty.
//   Pass 2 — Check each function body using bidirectional type checking.
//
// Bidirectional modes:
//   synth(expr) -> Ty         Bottom-up inference
//   check(expr, expected: Ty) Top-down checking (falls back to synth + compare)

use std::collections::{HashMap, HashSet};
use std::fmt;

use crate::lexer::span::Span;
use crate::parser::{
    AssignOp, AssignStmt, BinOp, Block, BreakStmt, ContinueStmt, Expr, ExprKind, ExprStmt,
    FieldInit, Item, LValue, LValueKind, LetStmt, LoopStmt, Program, ReturnStmt, Stmt, Type,
    TypeKind, UnaryOp,
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
    Tuple(Vec<TypeInternal>),
    Array(Box<TypeInternal>, u64),
    Pointer(Box<TypeInternal>),
    Fn {
        params: Vec<TypeInternal>,
        result: Box<TypeInternal>,
        is_variadic: bool,
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
}

// Type error
#[derive(Debug, Clone)]
pub struct TypecheckerError {
    pub message: String,
    pub span: Span,
}

impl fmt::Display for TypecheckerError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "type error at {}..{}: {}",
            self.span.start, self.span.end, self.message
        )
    }
}

type TypecheckerResult<T> = Result<T, TypecheckerError>;

fn typechecker_error(span: Span, msg: String) -> TypecheckerError {
    TypecheckerError { message: msg, span }
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

// Scope / variable environment
struct Scope {
    vars: HashMap<String, TypeInternal>,
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

    fn define(&mut self, name: String, ty: TypeInternal) {
        self.scopes.last_mut().unwrap().vars.insert(name, ty);
    }

    fn lookup(&self, name: &str) -> Option<&TypeInternal> {
        for scope in self.scopes.iter().rev() {
            if let Some(ty) = scope.vars.get(name) {
                return Some(ty);
            }
        }
        None
    }
}

pub struct Typechecker {
    structs: HashMap<String, StructInfo>,
    signatures: HashMap<String, FnSig>,
    env: TypingEnvironment,
    return_ty: TypeInternal, // current function's return type
    loop_depth: u32,         // for break/continue validation
    errors: Vec<TypecheckerError>,
}

impl Typechecker {
    pub fn check_program(program: &Program) -> Result<CheckedProgram, Vec<TypecheckerError>> {
        let mut checker = Typechecker {
            structs: HashMap::new(),
            signatures: HashMap::new(),
            env: TypingEnvironment::new(),
            return_ty: TypeInternal::Unit,
            loop_depth: 0,
            errors: Vec::new(),
        };

        // Pass 1: collect declarations
        checker.collect_structs(program);
        if !checker.errors.is_empty() {
            return Err(checker.errors);
        }

        checker.check_struct_cycles();
        if !checker.errors.is_empty() {
            return Err(checker.errors);
        }

        checker.collect_functions(program);
        if !checker.errors.is_empty() {
            return Err(checker.errors);
        }

        // Pass 2: check function bodies
        checker.check_function_bodies(program);
        if checker.errors.is_empty() {
            Ok(CheckedProgram {
                structs: checker.structs,
                functions: checker.signatures,
            })
        } else {
            Err(checker.errors)
        }
    }

    // Pass 1: Collect declarations
    fn collect_structs(&mut self, program: &Program) {
        // Phase 1: Register all struct names with empty fields so that
        // forward references (and self-references via pointer) resolve.
        for item in &program.items {
            if let Item::Struct(sd) = item {
                let name = &sd.name.0;
                if self.structs.contains_key(name) {
                    self.errors.push(typechecker_error(
                        sd.span,
                        format!("duplicate struct '{}'", name),
                    ));
                    continue;
                }
                self.structs.insert(
                    name.clone(),
                    StructInfo {
                        name: name.clone(),
                        fields: Vec::new(),
                    },
                );
            }
        }

        // Phase 2: Resolve field types now that all struct names are known.
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

    fn check_struct_cycles(&mut self) {
        // Detect structs that contain themselves (directly or transitively) by value.
        // Pointers break the cycle (they have a fixed size).
        for name in self.structs.keys().cloned().collect::<Vec<_>>() {
            let mut visited = HashSet::new();
            if self.has_cycle(&name, &mut visited) {
                // Find the span for the error
                let span = Span::new(0, 0); // We'll use a dummy span
                self.errors.push(typechecker_error(span, format!(
                    "struct '{}' has infinite size due to recursive field (use a pointer to break the cycle)", name
                )));
            }
        }
    }

    fn has_cycle(&self, name: &str, visited: &mut HashSet<String>) -> bool {
        if !visited.insert(name.to_string()) {
            return true;
        }
        if let Some(info) = self.structs.get(name) {
            for (_, ty) in &info.fields {
                if let TypeInternal::Struct(inner) = ty {
                    if self.has_cycle(inner, visited) {
                        return true;
                    }
                }
                // Arrays of structs also embed by value
                if let TypeInternal::Array(elem, _) = ty {
                    if let TypeInternal::Struct(inner) = elem.as_ref() {
                        if self.has_cycle(inner, visited) {
                            return true;
                        }
                    }
                }
                // Tuples containing structs also embed by value
                if let TypeInternal::Tuple(elems) = ty {
                    for elem in elems {
                        if let TypeInternal::Struct(inner) = elem {
                            if self.has_cycle(inner, visited) {
                                return true;
                            }
                        }
                    }
                }
            }
        }
        visited.remove(name);
        false
    }

    fn collect_functions(&mut self, program: &Program) {
        for item in &program.items {
            let (name, params_ast, ret_ast, span, is_variadic) = match item {
                Item::Function(fd) => (&fd.name, &fd.params, &fd.return_type, fd.span, false),
                Item::Extern(ed) => (
                    &ed.name,
                    &ed.params,
                    &ed.return_type,
                    ed.span,
                    ed.is_variadic,
                ),
                Item::Struct(_) => continue,
            };
            if self.signatures.contains_key(&name.0) {
                self.errors.push(typechecker_error(
                    span,
                    format!("duplicate function '{}'", name.0),
                ));
                continue;
            }
            let mut params = Vec::new();
            for p in params_ast {
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

    // Type resolution: AST Type -> TypeInternal
    fn resolve_type(&self, ast_ty: &Type) -> TypecheckerResult<TypeInternal> {
        match &ast_ty.kind {
            TypeKind::Named(name) => self.resolve_named(name, ast_ty.span),
            TypeKind::Unit => Ok(TypeInternal::Unit),
            TypeKind::Tuple(ts) => {
                let mut resolved = Vec::new();
                for t in ts {
                    resolved.push(self.resolve_type(t)?);
                }
                Ok(TypeInternal::Tuple(resolved))
            }
            TypeKind::Array(elem, size) => {
                let elem_ty = self.resolve_type(elem)?;
                Ok(TypeInternal::Array(Box::new(elem_ty), *size))
            }
            TypeKind::Pointer(inner) => {
                let inner_ty = self.resolve_type(inner)?;
                Ok(TypeInternal::Pointer(Box::new(inner_ty)))
            }
            TypeKind::Fn {
                params,
                result,
                is_variadic,
            } => {
                let mut p = Vec::new();
                for t in params {
                    p.push(self.resolve_type(t)?);
                }
                Ok(TypeInternal::Fn {
                    params: p,
                    result: Box::new(self.resolve_type(result)?),
                    is_variadic: *is_variadic,
                })
            }
        }
    }

    fn resolve_named(&self, name: &str, span: Span) -> TypecheckerResult<TypeInternal> {
        match name {
            "i8" => Ok(TypeInternal::I8),
            "i16" => Ok(TypeInternal::I16),
            "i32" => Ok(TypeInternal::I32),
            "i64" => Ok(TypeInternal::I64),
            "u8" => Ok(TypeInternal::U8),
            "u16" => Ok(TypeInternal::U16),
            "u32" => Ok(TypeInternal::U32),
            "u64" => Ok(TypeInternal::U64),
            "f32" => Ok(TypeInternal::F32),
            "f64" => Ok(TypeInternal::F64),
            "bool" => Ok(TypeInternal::Bool),
            "usize" => Ok(TypeInternal::U64), // usize aliases to u64
            _ => {
                if self.structs.contains_key(name) {
                    Ok(TypeInternal::Struct(name.to_string()))
                } else {
                    Err(typechecker_error(span, format!("unknown type '{}'", name)))
                }
            }
        }
    }

    // Pass 2: Check function bodies
    fn check_function_bodies(&mut self, program: &Program) {
        for item in &program.items {
            if let Item::Function(fd) = item {
                let sig = self.signatures.get(&fd.name.0).unwrap().clone();
                self.return_ty = sig.return_ty.clone();
                self.loop_depth = 0;
                self.env = TypingEnvironment::new();

                // Bind parameters
                for (name, ty) in &sig.params {
                    self.env.define(name.clone(), ty.clone());
                }

                // Check body.
                // If the body has a tail expression, check_block verifies it
                // against the return type. If there's no tail, body type is ().
                // We only flag a mismatch when there is no return statement,
                // because `{ return X; }` has body type () but the return
                // statement already checks X against the declared return type.
                let has_return = Self::block_has_return(&fd.body);
                let body_ty = self.check_block(&fd.body, Some(&sig.return_ty));

                match body_ty {
                    Ok(bt) => {
                        if bt != sig.return_ty && !has_return {
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

    fn block_has_return(block: &Block) -> bool {
        for stmt in &block.stmts {
            match stmt {
                Stmt::Return(_) => return true,
                Stmt::Loop(l) => {
                    if Self::block_has_return(&l.body) {
                        return true;
                    }
                }
                _ => {}
            }
        }
        false
    }

    fn check_block(
        &mut self,
        block: &Block,
        expected: Option<&TypeInternal>,
    ) -> TypecheckerResult<TypeInternal> {
        self.env.push_scope();

        for stmt in &block.stmts {
            self.check_stmt(stmt);
        }

        let ty = if let Some(tail) = &block.expr {
            if let Some(exp) = expected {
                self.check_expr(tail, exp)?;
                exp.clone()
            } else {
                self.synth_expr(tail)?
            }
        } else {
            TypeInternal::Unit
        };

        self.env.pop_scope();
        Ok(ty)
    }

    fn check_stmt(&mut self, stmt: &Stmt) {
        match stmt {
            Stmt::Let(ls) => self.check_let_stmt(ls),
            Stmt::Assign(a) => self.check_assign_stmt(a),
            Stmt::Return(r) => self.check_return_stmt(r),
            Stmt::Break(b) => self.check_break_stmt(b),
            Stmt::Continue(c) => self.check_continue_stmt(c),
            Stmt::Loop(l) => self.check_loop_stmt(l),
            Stmt::Expr(e) => self.check_expr_stmt(e),
        }
    }

    fn check_let_stmt(&mut self, ls: &LetStmt) {
        if let Some(ty_ann) = &ls.ty {
            match self.resolve_type(ty_ann) {
                Ok(expected) => {
                    if let Err(e) = self.check_expr(&ls.init, &expected) {
                        self.errors.push(e);
                    }
                    self.env.define(ls.name.0.clone(), expected);
                }
                Err(e) => {
                    self.errors.push(e);
                    // Still try to synth for the binding
                    let ty = self.synth_expr(&ls.init).unwrap_or(TypeInternal::Unit);
                    self.env.define(ls.name.0.clone(), ty);
                }
            }
        } else {
            match self.synth_expr(&ls.init) {
                Ok(ty) => self.env.define(ls.name.0.clone(), ty),
                Err(e) => {
                    self.errors.push(e);
                    self.env.define(ls.name.0.clone(), TypeInternal::Unit);
                }
            }
        }
    }

    fn check_assign_stmt(&mut self, a: &AssignStmt) {
        let target_ty = match self.synth_lvalue(&a.target) {
            Ok(t) => t,
            Err(e) => {
                self.errors.push(e);
                return;
            }
        };

        match a.op {
            AssignOp::Assign => {
                if let Err(e) = self.check_expr(&a.value, &target_ty) {
                    self.errors.push(e);
                }
            }
            AssignOp::AddAssign | AssignOp::SubAssign => {
                if !target_ty.is_numeric() {
                    self.errors.push(typechecker_error(
                        a.span,
                        format!(
                            "compound assignment requires numeric type, got '{}'",
                            target_ty
                        ),
                    ));
                    return;
                }
                if let Err(e) = self.check_expr(&a.value, &target_ty) {
                    self.errors.push(e);
                }
            }
            AssignOp::ShlAssign | AssignOp::ShrAssign => {
                if !target_ty.is_integer() {
                    self.errors.push(typechecker_error(
                        a.span,
                        format!(
                            "shift assignment requires integer type, got '{}'",
                            target_ty
                        ),
                    ));
                    return;
                }
                // RHS just needs to be integer, doesn't need to match LHS type
                match self.synth_expr(&a.value) {
                    Ok(rty) => {
                        if !rty.is_integer() {
                            self.errors.push(typechecker_error(
                                a.value.span,
                                format!("shift amount must be integer, got '{}'", rty),
                            ));
                        }
                    }
                    Err(e) => self.errors.push(e),
                }
            }
        }
    }

    fn check_return_stmt(&mut self, r: &ReturnStmt) {
        let expected = self.return_ty.clone();
        match &r.value {
            Some(expr) => {
                if let Err(e) = self.check_expr(expr, &expected) {
                    self.errors.push(e);
                }
            }
            None => {
                if expected != TypeInternal::Unit {
                    self.errors.push(typechecker_error(
                        r.span,
                        format!("empty return in function returning '{}'", expected),
                    ));
                }
            }
        }
    }

    fn check_break_stmt(&mut self, b: &BreakStmt) {
        if self.loop_depth == 0 {
            self.errors.push(typechecker_error(
                b.span,
                "break outside of loop".to_string(),
            ));
        }
    }

    fn check_continue_stmt(&mut self, c: &ContinueStmt) {
        if self.loop_depth == 0 {
            self.errors.push(typechecker_error(
                c.span,
                "continue outside of loop".to_string(),
            ));
        }
    }

    fn check_loop_stmt(&mut self, l: &LoopStmt) {
        self.loop_depth += 1;
        // Loop body must have type () (no tail expression value escapes)
        match self.check_block(&l.body, Some(&TypeInternal::Unit)) {
            Ok(ty) => {
                if ty != TypeInternal::Unit {
                    self.errors.push(typechecker_error(
                        l.body.span,
                        format!("loop body must have type '()', got '{}'", ty),
                    ));
                }
            }
            Err(e) => self.errors.push(e),
        }
        self.loop_depth -= 1;
    }

    fn check_expr_stmt(&mut self, e: &ExprStmt) {
        if let Err(err) = self.synth_expr(&e.expr) {
            self.errors.push(err);
        }
    }

    // LValue synthesis
    fn synth_lvalue(&mut self, lv: &LValue) -> TypecheckerResult<TypeInternal> {
        match &lv.kind {
            LValueKind::Ident(name) => self.env.lookup(name).cloned().ok_or_else(|| {
                typechecker_error(lv.span, format!("undefined variable '{}'", name))
            }),
            LValueKind::Deref(inner) => {
                let inner_ty = self.synth_expr(inner)?;
                match inner_ty {
                    TypeInternal::Pointer(pointee) => Ok(*pointee),
                    _ => Err(typechecker_error(
                        lv.span,
                        format!("cannot deref non-pointer type '{}'", inner_ty),
                    )),
                }
            }
            LValueKind::Field(inner, field_name) => {
                let inner_ty = self.synth_lvalue(inner)?;
                self.resolve_field_access(&inner_ty, &field_name.0, lv.span)
            }
            LValueKind::Index(inner, index_expr) => {
                let inner_ty = self.synth_lvalue(inner)?;
                match &inner_ty {
                    TypeInternal::Array(elem, _) => {
                        let idx_ty = self.synth_expr(index_expr)?;
                        if !idx_ty.is_integer() {
                            return Err(typechecker_error(
                                lv.span,
                                format!("array index must be integer, got '{}'", idx_ty),
                            ));
                        }
                        Ok(*elem.clone())
                    }
                    _ => Err(typechecker_error(
                        lv.span,
                        format!("cannot index type '{}'", inner_ty),
                    )),
                }
            }
        }
    }

    // Expression checking (check mode)
    fn check_expr(&mut self, expr: &Expr, expected: &TypeInternal) -> TypecheckerResult<()> {
        match &expr.kind {
            // Literals benefit from check mode
            ExprKind::IntLiteral(v) => {
                if expected.is_integer() {
                    self.check_int_fits(*v, expected, expr.span)?;
                    Ok(())
                } else {
                    // Fall through to synth for better error message
                    let got = self.synth_expr(expr)?;
                    Err(typechecker_error(
                        expr.span,
                        format!("expected '{}', got '{}'", expected, got),
                    ))
                }
            }
            ExprKind::FloatLiteral(_) => {
                if expected.is_float() {
                    Ok(())
                } else {
                    let got = self.synth_expr(expr)?;
                    Err(typechecker_error(
                        expr.span,
                        format!("expected '{}', got '{}'", expected, got),
                    ))
                }
            }

            // Tuple: push expected element types down
            ExprKind::Tuple(elems) => {
                if let TypeInternal::Tuple(exp_elems) = expected {
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
                    Ok(())
                } else {
                    // Fall through to synth
                    let got = self.synth_expr(expr)?;
                    if got != *expected {
                        Err(typechecker_error(
                            expr.span,
                            format!("expected '{}', got '{}'", expected, got),
                        ))
                    } else {
                        Ok(())
                    }
                }
            }

            // Array: push expected element type down
            ExprKind::Array(elems) => {
                if let TypeInternal::Array(exp_elem, exp_size) = expected {
                    if elems.len() as u64 != *exp_size {
                        return Err(typechecker_error(
                            expr.span,
                            format!("array has {} elements, expected {}", elems.len(), exp_size),
                        ));
                    }
                    for elem in elems {
                        self.check_expr(elem, exp_elem)?;
                    }
                    Ok(())
                } else {
                    let got = self.synth_expr(expr)?;
                    if got != *expected {
                        Err(typechecker_error(
                            expr.span,
                            format!("expected '{}', got '{}'", expected, got),
                        ))
                    } else {
                        Ok(())
                    }
                }
            }

            // ArrayRepeat: push expected element type down
            ExprKind::ArrayRepeat(val, count) => {
                if let TypeInternal::Array(exp_elem, exp_size) = expected {
                    self.check_expr(val, exp_elem)?;
                    // count must be an int literal matching exp_size
                    if let ExprKind::IntLiteral(n) = count.kind {
                        if n != *exp_size {
                            return Err(typechecker_error(
                                count.span,
                                format!("array repeat count is {}, expected {}", n, exp_size),
                            ));
                        }
                    } else {
                        return Err(typechecker_error(
                            count.span,
                            "array repeat count must be an integer literal".to_string(),
                        ));
                    }
                    Ok(())
                } else {
                    let got = self.synth_expr(expr)?;
                    if got != *expected {
                        Err(typechecker_error(
                            expr.span,
                            format!("expected '{}', got '{}'", expected, got),
                        ))
                    } else {
                        Ok(())
                    }
                }
            }

            // Struct constructor: push field types down
            ExprKind::StructConstructor { name, fields } => {
                if let TypeInternal::Struct(exp_name) = expected {
                    if *exp_name != name.0 {
                        return Err(typechecker_error(
                            expr.span,
                            format!(
                                "expected struct '{}', got constructor for '{}'",
                                exp_name, name.0
                            ),
                        ));
                    }
                }
                // Whether or not we have an expected type, we know the struct name
                self.check_struct_constructor(&name.0, name.1, fields, expr.span)?;
                let got = TypeInternal::Struct(name.0.clone());
                if got != *expected {
                    Err(typechecker_error(
                        expr.span,
                        format!("expected '{}', got '{}'", expected, got),
                    ))
                } else {
                    Ok(())
                }
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
                        self.check_block(then_block, Some(expected))?;
                        self.check_block(eb, Some(expected))?;
                        Ok(())
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
                        self.check_block(then_block, Some(&TypeInternal::Unit))?;
                        Ok(())
                    }
                }
            }

            // Block: push expected into tail
            ExprKind::Block(block) => {
                self.check_block(block, Some(expected))?;
                Ok(())
            }

            // For everything else, fall back to synth + compare
            _ => {
                let got = self.synth_expr(expr)?;
                if got != *expected {
                    Err(typechecker_error(
                        expr.span,
                        format!("expected '{}', got '{}'", expected, got),
                    ))
                } else {
                    Ok(())
                }
            }
        }
    }

    // Expression synthesis (synth mode)
    fn synth_expr(&mut self, expr: &Expr) -> TypecheckerResult<TypeInternal> {
        match &expr.kind {
            ExprKind::IntLiteral(_) => Ok(TypeInternal::I64), // default
            ExprKind::FloatLiteral(_) => Ok(TypeInternal::F64), // default
            ExprKind::BoolLiteral(_) => Ok(TypeInternal::Bool),
            ExprKind::UnitLiteral => Ok(TypeInternal::Unit),
            ExprKind::StringLiteral(_) => {
                // String literals are (*u8, usize) aka (*u8, u64)
                Ok(TypeInternal::Tuple(vec![
                    TypeInternal::Pointer(Box::new(TypeInternal::U8)),
                    TypeInternal::U64,
                ]))
            }

            ExprKind::Ident(name) => self.env.lookup(name).cloned().ok_or_else(|| {
                typechecker_error(expr.span, format!("undefined variable '{}'", name))
            }),

            ExprKind::BinOp { op, lhs, rhs } => self.synth_binop(op, lhs, rhs, expr.span),
            ExprKind::UnaryOp { op, expr: inner } => self.synth_unaryop(op, inner, expr.span),

            ExprKind::Cast { expr: inner, ty } => {
                let from = self.synth_expr(inner)?;
                let to = self.resolve_type(ty)?;
                self.check_cast(&from, &to, inner.span)?;
                Ok(to)
            }

            ExprKind::Call { callee, args } => self.synth_call(callee, args, expr.span),

            ExprKind::Index { expr: arr, index } => {
                let arr_ty = self.synth_expr(arr)?;
                match &arr_ty {
                    TypeInternal::Array(elem, _) => {
                        let idx_ty = self.synth_expr(index)?;
                        if !idx_ty.is_integer() {
                            return Err(typechecker_error(
                                index.span,
                                format!("array index must be integer, got '{}'", idx_ty),
                            ));
                        }
                        Ok(*elem.clone())
                    }
                    _ => Err(typechecker_error(
                        arr.span,
                        format!("cannot index type '{}'", arr_ty),
                    )),
                }
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
                        "cannot infer type of empty array".to_string(),
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
                if let ExprKind::IntLiteral(n) = count.kind {
                    Ok(TypeInternal::Array(Box::new(elem_ty), n))
                } else {
                    Err(typechecker_error(
                        count.span,
                        "array repeat count must be an integer literal".to_string(),
                    ))
                }
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
                        if then_ty != else_ty {
                            Err(typechecker_error(
                                expr.span,
                                format!(
                                    "if/else branches have different types: '{}' vs '{}'",
                                    then_ty, else_ty
                                ),
                            ))
                        } else {
                            Ok(then_ty)
                        }
                    }
                    None => {
                        let then_ty = self.check_block(then_block, None)?;
                        if then_ty != TypeInternal::Unit {
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

        let lty = self.synth_expr(lhs)?;
        // Check rhs against lhs type so literals pick up the right type
        self.check_expr(rhs, &lty)?;

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
            BinOp::Pow => {
                if !lty.is_numeric() {
                    return Err(typechecker_error(
                        span,
                        format!("'**' requires numeric type, got '{}'", lty),
                    ));
                }
                Ok(lty)
            }
            BinOp::Lt | BinOp::Gt | BinOp::LtEq | BinOp::GtEq => {
                if !lty.is_numeric() {
                    return Err(typechecker_error(
                        span,
                        format!("comparison requires numeric type, got '{}'", lty),
                    ));
                }
                Ok(TypeInternal::Bool)
            }
            BinOp::Eq | BinOp::Neq => {
                if !lty.is_numeric() && lty != TypeInternal::Bool && !lty.is_pointer() {
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
            UnaryOp::Neg | UnaryOp::Pos => {
                let ty = self.synth_expr(inner)?;
                if !ty.is_numeric() {
                    return Err(typechecker_error(
                        span,
                        format!("unary +/- requires numeric type, got '{}'", ty),
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
                // Must be an lvalue
                if !self.is_lvalue(inner) {
                    return Err(typechecker_error(
                        span,
                        "cannot take address of non-lvalue expression".to_string(),
                    ));
                }
                let ty = self.synth_expr(inner)?;
                Ok(TypeInternal::Pointer(Box::new(ty)))
            }
        }
    }

    fn is_lvalue(&self, expr: &Expr) -> bool {
        match &expr.kind {
            ExprKind::Ident(_) => true,
            ExprKind::UnaryOp {
                op: UnaryOp::Deref, ..
            } => true,
            ExprKind::Field { expr: inner, .. } => self.is_lvalue(inner),
            ExprKind::TupleField { expr: inner, .. } => self.is_lvalue(inner),
            ExprKind::Index { expr: inner, .. } => self.is_lvalue(inner),
            _ => false,
        }
    }

    // Function calls
    fn synth_call(
        &mut self,
        callee: &Expr,
        args: &[Expr],
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
        // Direct function call by name
        if let ExprKind::Ident(name) = &callee.kind {
            if let Some(sig) = self.signatures.get(name).cloned() {
                if args.len() > sig.params.len() && !sig.is_variadic {
                    return Err(typechecker_error(
                        span,
                        format!(
                            "function '{}' expects {} arguments, got {}",
                            name,
                            sig.params.len(),
                            args.len()
                        ),
                    ));
                }
                for (arg, (_pname, pty)) in args.iter().zip(sig.params.iter()) {
                    self.check_expr(arg, pty)?;
                }
                return Ok(sig.return_ty);
            }
        }

        // Indirect call via fn pointer
        let callee_ty = self.synth_expr(callee)?;
        match &callee_ty {
            TypeInternal::Fn {
                params,
                result,
                is_variadic,
            } => {
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

/// Result of a successful type check — contains resolved struct/function info
/// needed by later passes (lowering, codegen).
#[derive(Debug, Clone)]
pub struct CheckedProgram {
    pub structs: HashMap<String, StructInfo>,
    pub functions: HashMap<String, FnSig>,
}

pub fn typecheck(program: &Program) -> Result<CheckedProgram, Vec<TypecheckerError>> {
    Typechecker::check_program(program)
}

#[cfg(test)]
mod tests {
    use crate::parser::ParserError;

    use super::*;

    pub fn parse_source(src: &str) -> Result<Program, ParserError> {
        crate::parser::parse(&crate::lexer::Lexer::new(src).tokenize().unwrap())
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
        check_ok("fn main() { let x: u32 = 1; x <<= 4; x >>= 2; }");
    }

    #[test]
    fn test_shift_assign_on_float() {
        check_err_contains(
            "fn main() { let x: f64 = 1.0; x <<= 1; }",
            "shift assignment requires integer",
        );
    }

    #[test]
    fn test_power() {
        check_ok("fn main() { let x: i32 = 2; let y = x ** 3; }");
    }

    #[test]
    fn test_power_float() {
        check_ok("fn main() { let x: f64 = 2.0; let y = x ** 3.0; }");
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
            "array index must be integer",
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
        check_ok("fn main() { let x: i32 = 0; x = 42; }");
    }

    #[test]
    fn test_compound_assign() {
        check_ok("fn main() { let x: i32 = 0; x += 1; x -= 2; }");
    }

    #[test]
    fn test_compound_assign_non_numeric() {
        check_err_contains(
            "fn main() { let x = true; x += true; }",
            "compound assignment requires numeric",
        );
    }

    #[test]
    fn test_assign_type_mismatch() {
        check_err_contains(
            "fn main() { let x: i32 = 0; x = true; }",
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
                let p = Point { x: 0, y: 0 };
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
                let arr = [0, 0, 0];
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
                let a: i32 = 0;
                let b: i32 = 1;
                let i: i32 = 0;
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
                let sum: i32 = 0;
                let i: i32 = 0;
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
                let big = 2 ** 3 ** 2;
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
}
