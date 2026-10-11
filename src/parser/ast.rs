use crate::lexer::{float::Float, span::Span, token::NumSuffix};

pub type Spanned<T> = (T, Span);

#[derive(Debug, PartialEq)]
pub struct Program {
    pub items: Vec<Item>,
    // Number of expression ids handed out (ids are 0..expr_count).
    pub expr_count: u32,
}

#[derive(Debug, PartialEq)]
pub enum Item {
    Function(FunctionDecl),
    Extern(ExternDecl),
    Struct(StructDecl),
    Const(ConstDecl),
    Static(StaticDecl),
    TypeAlias(TypeAliasDecl),
}

#[derive(Debug, PartialEq)]
pub struct StructDecl {
    pub name: Spanned<String>,
    pub fields: Vec<StructField>,
    pub span: Span,
}

#[derive(Debug, PartialEq)]
pub struct StructField {
    pub name: Spanned<String>,
    pub ty: Type,
    pub span: Span,
}

#[derive(PartialEq)]
pub struct FunctionDecl {
    pub name: Spanned<String>,
    pub params: Vec<Parameter>,
    pub return_type: Option<Type>,
    pub body: Block,
    pub span: Span,
}

impl std::fmt::Debug for FunctionDecl {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("FunctionDecl")
            .field("name", &self.name)
            .field("span", &self.span)
            .finish()
    }
}

#[derive(PartialEq)]
pub struct ExternDecl {
    pub name: Spanned<String>,
    pub params: Vec<Parameter>,
    pub is_variadic: bool,
    pub return_type: Option<Type>,
    pub span: Span,
}

impl std::fmt::Debug for ExternDecl {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ExternDecl")
            .field("name", &self.name)
            .field("span", &self.span)
            .finish()
    }
}

// `const NAME: T = expr;` — a compile-time constant.
#[derive(Debug, PartialEq)]
pub struct ConstDecl {
    pub name: Spanned<String>,
    pub ty: Type,
    pub value: Expr,
    pub span: Span,
}

// `static [mut] NAME: T = expr;` — a global variable with a constant
// initializer.
#[derive(Debug, PartialEq)]
pub struct StaticDecl {
    pub name: Spanned<String>,
    pub mutable: bool,
    pub ty: Type,
    pub value: Expr,
    pub span: Span,
}

// `type Name = T;`
#[derive(Debug, PartialEq)]
pub struct TypeAliasDecl {
    pub name: Spanned<String>,
    pub ty: Type,
    pub span: Span,
}

// `[mut] name: T`; the name is "_" for an ignored parameter.
#[derive(Debug, PartialEq)]
pub struct Parameter {
    pub name: Spanned<String>,
    pub mutable: bool,
    pub ty: Type,
    pub span: Span,
}

// --- Types ---
#[derive(Debug, Clone, PartialEq)]
pub struct Type {
    pub kind: TypeKind,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq)]
pub enum TypeKind {
    Named(String),
    Unit,
    // `!`, the type of expressions that never produce a value.
    Never,
    Tuple(Vec<Type>),
    // The size is a constant expression.
    Array(Box<Type>, Box<Expr>),
    Pointer(Box<Type>),
    Fn {
        params: Vec<Type>,
        result: Box<Type>,
    },
}

// --- Patterns ---
#[derive(Debug, Clone, PartialEq)]
pub struct Pattern {
    pub kind: PatternKind,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq)]
pub enum PatternKind {
    // `_`
    Wildcard,
    // `x`, `mut x`
    Binding { name: String, mutable: bool },
    // `(a, mut b, _)`
    Tuple(Vec<Pattern>),
}

// --- Statements ---
#[derive(Clone, PartialEq)]
pub struct Block {
    pub stmts: Vec<Stmt>,
    pub expr: Option<Box<Expr>>,
    pub span: Span,
}

impl std::fmt::Debug for Block {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Block")
            .field("statements", &self.stmts)
            .field("span", &self.span)
            .finish()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Stmt {
    Let(LetStmt),
    Expr(ExprStmt),
}

#[derive(Debug, Clone, PartialEq)]
pub struct LetStmt {
    pub pattern: Pattern,
    pub ty: Option<Type>,
    pub init: Expr,
    pub span: Span,
}

// An expression statement. Only block-like expressions (`if`, `loop`, `{}`,
// ...) may omit the `;`; they then must have type `()`.
#[derive(Debug, Clone, PartialEq)]
pub struct ExprStmt {
    pub expr: Expr,
    pub has_semi: bool,
    pub span: Span,
}

// --- Expressions ---

// Identifies an expression node; the parser numbers them densely from 0, so
// later passes can keep per-expression facts (e.g. types) in side tables.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ExprId(pub u32);

#[derive(Debug, Clone)]
pub struct Expr {
    pub id: ExprId,
    pub kind: ExprKind,
    pub span: Span,
}

// Structural equality: the id is an identity, not part of the shape.
impl PartialEq for Expr {
    fn eq(&self, other: &Self) -> bool {
        self.kind == other.kind && self.span == other.span
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Eq,
    Neq,
    Lt,
    Gt,
    LtEq,
    GtEq,
    And,
    Or,
    BitAnd,
    BitOr,
    BitXor,
    Shl,
    Shr,
}

impl BinOp {
    pub fn is_comparison(self) -> bool {
        matches!(
            self,
            BinOp::Eq | BinOp::Neq | BinOp::Lt | BinOp::Gt | BinOp::LtEq | BinOp::GtEq
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum UnaryOp {
    Neg,
    Not,
    BitNot,
    Deref,
    AddrOf,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum AssignOp {
    Assign,
    AddAssign,
    SubAssign,
    MulAssign,
    DivAssign,
    ModAssign,
    BitAndAssign,
    BitOrAssign,
    BitXorAssign,
    ShlAssign,
    ShrAssign,
}

impl AssignOp {
    // The operator a compound assignment applies (`a += b` is `a = a + b`).
    pub fn binop(self) -> Option<BinOp> {
        Some(match self {
            AssignOp::Assign => return None,
            AssignOp::AddAssign => BinOp::Add,
            AssignOp::SubAssign => BinOp::Sub,
            AssignOp::MulAssign => BinOp::Mul,
            AssignOp::DivAssign => BinOp::Div,
            AssignOp::ModAssign => BinOp::Mod,
            AssignOp::BitAndAssign => BinOp::BitAnd,
            AssignOp::BitOrAssign => BinOp::BitOr,
            AssignOp::BitXorAssign => BinOp::BitXor,
            AssignOp::ShlAssign => BinOp::Shl,
            AssignOp::ShrAssign => BinOp::Shr,
        })
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct FieldInit {
    pub name: Spanned<String>,
    pub value: Expr,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LitValue {
    Int(u64),
    Float(Float),
}

#[derive(Debug, Clone, PartialEq)]
pub enum ExprKind {
    // Stands in for an expression or statement that failed to parse.
    Error,
    // Untyped literals: the type comes from context (default i64/f64).
    IntLiteral(u64),
    FloatLiteral(Float),
    // 'a': an untyped integer literal whose default type is u8.
    CharLiteral(u8),
    // `1u8`, `2.0f32`: a literal with an explicit type.
    SuffixedLiteral(LitValue, NumSuffix),
    // "...": a (*u8, u64) pair.
    StringLiteral(Vec<u8>),
    // c"...": a NUL-terminated *u8.
    CStringLiteral(Vec<u8>),
    BoolLiteral(bool),
    UnitLiteral,
    Ident(String),
    Tuple(Vec<Expr>),
    Array(Vec<Expr>),
    ArrayRepeat(Box<Expr>, Box<Expr>),
    StructConstructor {
        name: Spanned<String>,
        fields: Vec<FieldInit>,
    },
    BinOp {
        op: BinOp,
        lhs: Box<Expr>,
        rhs: Box<Expr>,
    },
    UnaryOp {
        op: UnaryOp,
        expr: Box<Expr>,
    },
    Cast {
        expr: Box<Expr>,
        ty: Type,
    },
    Call {
        callee: Box<Expr>,
        args: Vec<Expr>,
    },
    Index {
        expr: Box<Expr>,
        index: Box<Expr>,
    },
    Field {
        expr: Box<Expr>,
        name: Spanned<String>,
    },
    TupleField {
        expr: Box<Expr>,
        index: Spanned<u64>,
    },
    // `a..b`, `a..=b`; only valid as the iterable of a `for` loop.
    Range {
        start: Box<Expr>,
        end: Box<Expr>,
        inclusive: bool,
    },
    // `target op= value`; has type ().
    Assign {
        op: AssignOp,
        target: Box<Expr>,
        value: Box<Expr>,
    },
    Block(Block),
    // `else if` is an else block whose tail is the inner `if`.
    If {
        cond: Box<Expr>,
        then_block: Block,
        else_block: Option<Block>,
    },
    Loop {
        label: Option<Spanned<String>>,
        body: Block,
    },
    While {
        label: Option<Spanned<String>>,
        cond: Box<Expr>,
        body: Block,
    },
    For {
        label: Option<Spanned<String>>,
        pattern: Pattern,
        iter: Box<Expr>,
        body: Block,
    },
    // `return`, `break` and `continue` have type `!`.
    Return(Option<Box<Expr>>),
    Break {
        label: Option<Spanned<String>>,
        value: Option<Box<Expr>>,
    },
    Continue {
        label: Option<Spanned<String>>,
    },
}
