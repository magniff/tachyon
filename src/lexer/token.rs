use std::fmt;

use crate::lexer;

#[derive(Debug, Clone, Copy)]
pub struct Float(pub f64);

impl std::fmt::Display for Float {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl PartialEq for Float {
    fn eq(&self, other: &Self) -> bool {
        self.0.to_bits() == other.0.to_bits()
    }
}
impl Eq for Float {}
impl From<f64> for Float {
    fn from(value: f64) -> Self {
        Self(value)
    }
}

impl std::ops::Deref for Float {
    type Target = f64;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TokenKind {
    IntLiteral(u64),
    FloatLiteral(Float),
    StringLiteral(String),
    Ident(String),
    // Keywords
    Fn,
    Let,
    Struct,
    If,
    Else,
    Loop,
    Break,
    Continue,
    True,
    False,
    As,
    Return,
    Extern,
    // Multi-char operators
    PlusEq,
    MinusEq,
    BangEq,
    EqEq,
    GtEq,
    LtEq,
    AmpAmp,
    PipePipe,
    StarStar,
    Arrow,
    Shl,
    Shr,
    ShlEq,
    ShrEq,
    Ellipsis,
    // Single-char
    Eq,
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    Caret,
    Amp,
    Pipe,
    Tilde,
    Bang,
    Lt,
    Gt,
    Dot,
    Comma,
    Semi,
    Colon,
    LParen,
    RParen,
    LBrace,
    RBrace,
    LBracket,
    RBracket,
    EOF,
}

impl fmt::Display for TokenKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TokenKind::IntLiteral(v) => write!(f, "{v}"),
            TokenKind::FloatLiteral(v) => write!(f, "{v}"),
            TokenKind::StringLiteral(v) => write!(f, "{v:?}"),
            TokenKind::Ident(v) => write!(f, "{}", v),
            TokenKind::Fn => write!(f, "fn"),
            TokenKind::Let => write!(f, "let"),
            TokenKind::Struct => write!(f, "struct"),
            TokenKind::If => write!(f, "if"),
            TokenKind::Else => write!(f, "else"),
            TokenKind::Loop => write!(f, "loop"),
            TokenKind::Break => write!(f, "break"),
            TokenKind::Continue => write!(f, "continue"),
            TokenKind::True => write!(f, "true"),
            TokenKind::False => write!(f, "false"),
            TokenKind::As => write!(f, "as"),
            TokenKind::Return => write!(f, "return"),
            TokenKind::Extern => write!(f, "extern"),
            TokenKind::PlusEq => write!(f, "+="),
            TokenKind::MinusEq => write!(f, "-="),
            TokenKind::BangEq => write!(f, "!="),
            TokenKind::EqEq => write!(f, "=="),
            TokenKind::GtEq => write!(f, ">="),
            TokenKind::LtEq => write!(f, "<="),
            TokenKind::AmpAmp => write!(f, "&&"),
            TokenKind::PipePipe => write!(f, "||"),
            TokenKind::StarStar => write!(f, "**"),
            TokenKind::Arrow => write!(f, "->"),
            TokenKind::Shl => write!(f, "<<"),
            TokenKind::Shr => write!(f, ">>"),
            TokenKind::ShlEq => write!(f, "<<="),
            TokenKind::ShrEq => write!(f, ">>="),
            TokenKind::Ellipsis => write!(f, "..."),
            TokenKind::Eq => write!(f, "="),
            TokenKind::Plus => write!(f, "+"),
            TokenKind::Minus => write!(f, "-"),
            TokenKind::Star => write!(f, "*"),
            TokenKind::Slash => write!(f, "/"),
            TokenKind::Percent => write!(f, "%"),
            TokenKind::Caret => write!(f, "^"),
            TokenKind::Amp => write!(f, "&"),
            TokenKind::Pipe => write!(f, "|"),
            TokenKind::Tilde => write!(f, "~"),
            TokenKind::Bang => write!(f, "!"),
            TokenKind::Lt => write!(f, "<"),
            TokenKind::Gt => write!(f, ">"),
            TokenKind::Dot => write!(f, "."),
            TokenKind::Comma => write!(f, ","),
            TokenKind::Semi => write!(f, ";"),
            TokenKind::Colon => write!(f, ":"),
            TokenKind::LParen => write!(f, "("),
            TokenKind::RParen => write!(f, ")"),
            TokenKind::LBrace => write!(f, "{{"),
            TokenKind::RBrace => write!(f, "}}"),
            TokenKind::LBracket => write!(f, "["),
            TokenKind::RBracket => write!(f, "]"),
            TokenKind::EOF => write!(f, "EOF"),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Token {
    pub kind: TokenKind,
    pub span: lexer::span::Span,
}
