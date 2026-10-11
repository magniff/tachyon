// The checker's view of the code around an expression: local variables in
// scope and the enclosing loops.

use std::collections::HashMap;

use super::TypeInternal;

#[derive(Debug, Clone)]
pub(super) struct VarInfo {
    pub ty: TypeInternal,
    pub mutable: bool,
    pub is_param: bool,
}

// Local variables, one map per nested scope (innermost last).
pub(super) struct TypingEnvironment {
    scopes: Vec<HashMap<String, VarInfo>>,
}

impl TypingEnvironment {
    pub fn new() -> Self {
        Self {
            scopes: vec![HashMap::new()],
        }
    }

    pub fn push_scope(&mut self) {
        self.scopes.push(HashMap::new());
    }

    pub fn pop_scope(&mut self) {
        if self.scopes.len() > 1 {
            self.scopes.pop();
        }
    }

    pub fn define(&mut self, name: String, info: VarInfo) {
        self.scopes
            .last_mut()
            .expect("the outermost scope is never popped")
            .insert(name, info);
    }

    pub fn lookup(&self, name: &str) -> Option<&VarInfo> {
        self.scopes.iter().rev().find_map(|scope| scope.get(name))
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(super) enum LoopKind {
    Loop,
    While,
    For,
}

impl LoopKind {
    pub fn keyword(self) -> &'static str {
        match self {
            LoopKind::Loop => "loop",
            LoopKind::While => "while",
            LoopKind::For => "for",
        }
    }
}

// A loop being checked, as seen by its `break`s and `continue`s.
pub(super) struct LoopContext {
    pub label: Option<String>,
    pub kind: LoopKind,
    // Type of the `loop`'s value: set by the context (check mode) or by the
    // first `break`.
    pub break_ty: Option<TypeInternal>,
    pub has_break: bool,
}

impl LoopContext {
    pub fn new(label: Option<String>, kind: LoopKind, break_ty: Option<TypeInternal>) -> Self {
        Self {
            label,
            kind,
            break_ty,
            has_break: false,
        }
    }
}
