// Pass 1: collect every declaration and resolve the types they mention.

use std::collections::HashSet;

use super::types::primitive_type;
use super::{
    FnSig, StaticInfo, StructInfo, TypeInternal, Typechecker, TypecheckerError, TypecheckerResult,
    typechecker_error,
};
use crate::lexer::span::Span;
use crate::parser::{Item, Parameter, Program, StructDecl, Type, TypeKind};

// What kind of declaration an item is, for "duplicate ..." messages, and
// whether its name lives in the type namespace.
fn item_kind(item: &Item) -> (&'static str, bool) {
    match item {
        Item::Struct(_) => ("struct", true),
        Item::TypeAlias(_) => ("type", true),
        Item::Function(_) | Item::Extern(_) => ("function", false),
        Item::Const(_) => ("constant", false),
        Item::Static(_) => ("static", false),
    }
}

fn item_name(item: &Item) -> (&String, Span) {
    match item {
        Item::Struct(decl) => (&decl.name.0, decl.span),
        Item::TypeAlias(decl) => (&decl.name.0, decl.span),
        Item::Function(decl) => (&decl.name.0, decl.span),
        Item::Extern(decl) => (&decl.name.0, decl.span),
        Item::Const(decl) => (&decl.name.0, decl.span),
        Item::Static(decl) => (&decl.name.0, decl.span),
    }
}

impl<'p> Typechecker<'p> {
    pub(super) fn collect_declarations(
        &mut self,
        program: &'p Program,
    ) -> Result<(), Vec<TypecheckerError>> {
        self.collect_names(program);
        self.stop_on_errors()?;
        self.collect_const_types(program);
        self.collect_structs(program);
        self.collect_aliases(program);
        self.stop_on_errors()?;
        self.check_struct_cycles(program);
        self.stop_on_errors()?;
        self.collect_functions(program);
        self.collect_statics(program);
        self.evaluate_consts(program);
        self.stop_on_errors()
    }

    // Registers every global name, so declarations can refer to each other
    // in any order. Types (structs, aliases) and values (functions,
    // constants, statics) have separate namespaces.
    fn collect_names(&mut self, program: &'p Program) {
        let mut type_names: HashSet<&str> = HashSet::new();
        let mut value_names: HashSet<&str> = HashSet::new();
        for item in &program.items {
            let (name, span) = item_name(item);
            let (kind, is_type) = item_kind(item);
            let fresh = if is_type {
                type_names.insert(name) && primitive_type(name).is_none()
            } else {
                value_names.insert(name)
            };
            if !fresh {
                self.errors.push(typechecker_error(
                    span,
                    format!("duplicate {} '{}'", kind, name),
                ));
                continue;
            }
            match item {
                Item::Struct(_) => {
                    let info = StructInfo {
                        name: name.clone(),
                        fields: Vec::new(),
                    };
                    self.structs.insert(name.clone(), info);
                }
                Item::TypeAlias(alias) => {
                    self.aliases.insert(name.clone(), &alias.ty);
                }
                Item::Const(decl) => {
                    self.const_decls.insert(name.clone(), decl);
                }
                _ => {}
            }
        }
    }

    // Constants have scalar types, resolved before anything that may use
    // them (array sizes in struct fields, signatures, ...).
    fn collect_const_types(&mut self, program: &Program) {
        for item in &program.items {
            let Item::Const(decl) = item else {
                continue;
            };
            match self.resolve_type(&decl.ty) {
                Ok(ty) if ty.is_numeric() || ty == TypeInternal::Bool => {
                    self.const_types.insert(decl.name.0.clone(), ty);
                }
                Ok(ty) => self.errors.push(typechecker_error(
                    decl.ty.span,
                    format!(
                        "constant '{}' has type '{}'; constants must be integers, floats or bool",
                        decl.name.0, ty
                    ),
                )),
                Err(e) => self.errors.push(e),
            }
        }
    }

    // Resolves struct field types now that all names are known.
    fn collect_structs(&mut self, program: &Program) {
        for item in &program.items {
            if let Item::Struct(decl) = item {
                let fields = self.resolve_struct_fields(decl);
                if let Some(info) = self.structs.get_mut(&decl.name.0) {
                    info.fields = fields;
                }
            }
        }
    }

    fn resolve_struct_fields(&mut self, decl: &StructDecl) -> Vec<(String, TypeInternal)> {
        let mut fields = Vec::new();
        let mut seen = HashSet::new();
        for field in &decl.fields {
            if !seen.insert(&field.name.0) {
                self.errors.push(typechecker_error(
                    field.span,
                    format!(
                        "duplicate field '{}' in struct '{}'",
                        field.name.0, decl.name.0
                    ),
                ));
                continue;
            }
            match self.resolve_type(&field.ty) {
                Ok(ty) => fields.push((field.name.0.clone(), ty)),
                Err(e) => self.errors.push(e),
            }
        }
        fields
    }

    // Resolves every type alias, so errors in unused ones are reported too.
    fn collect_aliases(&mut self, program: &Program) {
        for item in &program.items {
            if let Item::TypeAlias(alias) = item
                && let Err(e) = self.resolve_named(&alias.name.0, alias.name.1)
            {
                self.errors.push(e);
            }
        }
    }

    // Detects structs that contain themselves (directly or transitively) by
    // value. Pointers break the cycle (they have a fixed size).
    fn check_struct_cycles(&mut self, program: &Program) {
        for item in &program.items {
            let Item::Struct(decl) = item else {
                continue;
            };
            let mut visiting = HashSet::new();
            if self.struct_has_cycle(&decl.name.0, &mut visiting) {
                self.errors.push(typechecker_error(
                    decl.name.1,
                    format!(
                        "struct '{}' has infinite size due to recursive field (use a pointer to break the cycle)",
                        decl.name.0
                    ),
                ));
            }
        }
    }

    // Whether struct `name` reaches a struct in `visiting` by value.
    fn struct_has_cycle(&self, name: &str, visiting: &mut HashSet<String>) -> bool {
        if !visiting.insert(name.to_string()) {
            return true;
        }
        if let Some(info) = self.structs.get(name)
            && info
                .fields
                .iter()
                .any(|(_, ty)| self.embeds_cycle(ty, visiting))
        {
            return true;
        }
        visiting.remove(name);
        false
    }

    // Structs embedded by value in `ty` (through arrays and tuples).
    fn embeds_cycle(&self, ty: &TypeInternal, visiting: &mut HashSet<String>) -> bool {
        match ty {
            TypeInternal::Struct(name) => self.struct_has_cycle(name, visiting),
            TypeInternal::Array(elem, _) => self.embeds_cycle(elem, visiting),
            TypeInternal::Tuple(elems) => {
                elems.iter().any(|elem| self.embeds_cycle(elem, visiting))
            }
            _ => false,
        }
    }

    fn collect_functions(&mut self, program: &Program) {
        for item in &program.items {
            let (name, params, return_type, is_variadic) = match item {
                Item::Function(decl) => (&decl.name.0, &decl.params, &decl.return_type, false),
                Item::Extern(decl) => (
                    &decl.name.0,
                    &decl.params,
                    &decl.return_type,
                    decl.is_variadic,
                ),
                _ => continue,
            };
            let signature = FnSig {
                name: name.clone(),
                params: self.resolve_params(params),
                return_ty: self.resolve_return_type(return_type.as_ref()),
                is_variadic,
            };
            self.signatures.insert(name.clone(), signature);
        }
    }

    fn resolve_params(&mut self, params: &[Parameter]) -> Vec<(String, TypeInternal)> {
        let mut resolved = Vec::new();
        let mut seen = HashSet::new();
        for param in params {
            if param.name.0 != "_" && !seen.insert(&param.name.0) {
                self.errors.push(typechecker_error(
                    param.name.1,
                    format!("duplicate parameter '{}'", param.name.0),
                ));
            }
            match self.resolve_type(&param.ty) {
                Ok(ty) => resolved.push((param.name.0.clone(), ty)),
                Err(e) => self.errors.push(e),
            }
        }
        resolved
    }

    // A missing return type is (); one that fails to resolve is reported.
    fn resolve_return_type(&mut self, return_type: Option<&Type>) -> TypeInternal {
        let Some(ty) = return_type else {
            return TypeInternal::Unit;
        };
        self.resolve_type(ty).unwrap_or_else(|e| {
            self.errors.push(e);
            TypeInternal::Unit
        })
    }

    fn collect_statics(&mut self, program: &Program) {
        for item in &program.items {
            let Item::Static(decl) = item else {
                continue;
            };
            let ty = match self.resolve_type(&decl.ty) {
                Ok(ty) => ty,
                Err(e) => {
                    self.errors.push(e);
                    continue;
                }
            };
            match self.eval_const_expr(&decl.value, &ty) {
                Ok(value) => {
                    let info = StaticInfo {
                        ty,
                        mutable: decl.mutable,
                        value,
                    };
                    self.statics.insert(decl.name.0.clone(), info);
                }
                Err(e) => self.errors.push(e),
            }
        }
    }

    fn evaluate_consts(&mut self, program: &Program) {
        for item in &program.items {
            if let Item::Const(decl) = item
                && self.const_types.contains_key(&decl.name.0)
                && let Err(e) = self.const_value(&decl.name.0)
            {
                self.errors.push(e);
            }
        }
    }

    // ---- Type resolution: AST Type -> TypeInternal ----

    pub(super) fn resolve_type(&mut self, ast_ty: &Type) -> TypecheckerResult<TypeInternal> {
        match &ast_ty.kind {
            TypeKind::Named(name) => self.resolve_named(name, ast_ty.span),
            TypeKind::Unit => Ok(TypeInternal::Unit),
            TypeKind::Never => Ok(TypeInternal::Never),
            TypeKind::Tuple(elems) => Ok(TypeInternal::Tuple(self.resolve_types(elems)?)),
            TypeKind::Array(elem, len) => {
                let elem_ty = self.resolve_type(elem)?;
                let len = self.eval_array_len(len)?;
                Ok(TypeInternal::Array(Box::new(elem_ty), len))
            }
            TypeKind::Pointer(pointee) => Ok(self.resolve_type(pointee)?.pointer_to()),
            TypeKind::Fn { params, result } => {
                let params = self.resolve_types(params)?;
                Ok(TypeInternal::Fn {
                    params,
                    result: Box::new(self.resolve_type(result)?),
                })
            }
        }
    }

    fn resolve_types(&mut self, types: &[Type]) -> TypecheckerResult<Vec<TypeInternal>> {
        types.iter().map(|ty| self.resolve_type(ty)).collect()
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
        match self.aliases.get(name).copied() {
            Some(target) => self.resolve_alias(name, target, span),
            None => Err(typechecker_error(span, format!("unknown type '{}'", name))),
        }
    }

    fn resolve_alias(
        &mut self,
        name: &str,
        target: &Type,
        span: Span,
    ) -> TypecheckerResult<TypeInternal> {
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
        Ok(resolved)
    }
}
