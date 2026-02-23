use crate::lexer::{span::Span, token::Float};

pub type Spanned<T> = (T, Span);

#[derive(Debug, PartialEq)]
pub struct Program {
    pub items: Vec<Item>,
}

#[derive(Debug, PartialEq)]
pub enum Item {
    Function(FunctionDecl),
    Extern(ExternDecl),
    Struct(StructDecl),
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

#[derive(Debug, PartialEq)]
pub struct Parameter {
    pub name: Spanned<String>,
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
    Tuple(Vec<Type>),
    Array(Box<Type>, u64),
    Pointer(Box<Type>),
    FnPtr(Vec<Type>, Option<Box<Type>>),
}

// --- Statements ---
#[derive(PartialEq)]
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

#[derive(Debug, PartialEq)]
pub enum Stmt {
    Let(LetStmt),
    Assign(AssignStmt),
    Return(ReturnStmt),
    Break(BreakStmt),
    Continue(ContinueStmt),
    Loop(LoopStmt),
    Expr(ExprStmt),
}

#[derive(Debug, PartialEq)]
pub struct LetStmt {
    pub name: Spanned<String>,
    pub ty: Option<Type>,
    pub init: Expr,
    pub span: Span,
}

#[derive(Debug, PartialEq)]
pub enum AssignOp {
    Assign,
    AddAssign,
    SubAssign,
    ShlAssign,
    ShrAssign,
}

#[derive(Debug, PartialEq)]
pub struct AssignStmt {
    pub target: LValue,
    pub op: AssignOp,
    pub value: Expr,
    pub span: Span,
}

#[derive(Debug, PartialEq)]
pub struct LValue {
    pub kind: LValueKind,
    pub span: Span,
}

#[derive(Debug, PartialEq)]
pub enum LValueKind {
    Ident(String),
    Deref(Box<Expr>),
    Field(Box<LValue>, Spanned<String>),
    Index(Box<LValue>, Expr),
}

#[derive(Debug, PartialEq)]
pub struct ReturnStmt {
    pub value: Option<Expr>,
    pub span: Span,
}

#[derive(Debug, PartialEq)]
pub struct BreakStmt {
    pub span: Span,
}

#[derive(Debug, PartialEq)]
pub struct ContinueStmt {
    pub span: Span,
}

#[derive(Debug, PartialEq)]
pub struct LoopStmt {
    pub body: Block,
    pub span: Span,
}

#[derive(Debug, PartialEq)]
pub struct ExprStmt {
    pub expr: Expr,
    pub span: Span,
}

// --- Expressions ---
#[derive(Debug, PartialEq)]
pub struct Expr {
    pub kind: ExprKind,
    pub span: Span,
}

#[derive(Debug, PartialEq)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Pow,
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

#[derive(Debug, PartialEq)]
pub enum UnaryOp {
    Neg,
    Pos,
    Not,
    BitNot,
    Deref,
    AddrOf,
}

#[derive(Debug, PartialEq)]
pub struct FieldInit {
    pub name: Spanned<String>,
    pub value: Expr,
    pub span: Span,
}

#[derive(Debug, PartialEq)]
pub enum ExprKind {
    IntLiteral(u64),
    FloatLiteral(Float),
    StringLiteral(String),
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
    Block(Block),
    If {
        cond: Box<Expr>,
        then_block: Block,
        else_block: Option<Block>,
    },
}
