use std::fmt;

use crate::lexer;

// The type named by a numeric literal suffix (`1u8`, `2.5f32`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NumSuffix {
    I8,
    I16,
    I32,
    I64,
    Isize,
    U8,
    U16,
    U32,
    U64,
    Usize,
    F32,
    F64,
}

impl NumSuffix {
    pub fn from_name(name: &str) -> Option<NumSuffix> {
        Some(match name {
            "i8" => NumSuffix::I8,
            "i16" => NumSuffix::I16,
            "i32" => NumSuffix::I32,
            "i64" => NumSuffix::I64,
            "isize" => NumSuffix::Isize,
            "u8" => NumSuffix::U8,
            "u16" => NumSuffix::U16,
            "u32" => NumSuffix::U32,
            "u64" => NumSuffix::U64,
            "usize" => NumSuffix::Usize,
            "f32" => NumSuffix::F32,
            "f64" => NumSuffix::F64,
            _ => return None,
        })
    }

    pub fn name(self) -> &'static str {
        match self {
            NumSuffix::I8 => "i8",
            NumSuffix::I16 => "i16",
            NumSuffix::I32 => "i32",
            NumSuffix::I64 => "i64",
            NumSuffix::Isize => "isize",
            NumSuffix::U8 => "u8",
            NumSuffix::U16 => "u16",
            NumSuffix::U32 => "u32",
            NumSuffix::U64 => "u64",
            NumSuffix::Usize => "usize",
            NumSuffix::F32 => "f32",
            NumSuffix::F64 => "f64",
        }
    }

    pub fn is_float(self) -> bool {
        matches!(self, NumSuffix::F32 | NumSuffix::F64)
    }
}

// Keywords that are reserved for planned features. Using one is an error
// ("reserved for future use") rather than an identifier.
pub const RESERVED_KEYWORDS: &[&str] = &[
    "enum", "match", "impl", "trait", "pub", "mod", "use", "self", "Self", "super", "where",
    "unsafe", "defer", "union", "dyn", "move",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TokenKind {
    IntLiteral(u64),
    FloatLiteral(lexer::float::Float),
    // `1u8`, `7i64`, `1f32`: a literal with an explicit type.
    SuffixedInt(u64, NumSuffix),
    SuffixedFloat(lexer::float::Float, NumSuffix),
    // 'a': a byte value.
    CharLiteral(u8),
    // Raw bytes: `\xNN` escapes may produce bytes that are not valid UTF-8.
    StringLiteral(Vec<u8>),
    // c"...": a NUL-terminated C string.
    CStringLiteral(Vec<u8>),
    Ident(String),
    // Keywords
    Fn,
    Let,
    Mut,
    Struct,
    If,
    Else,
    Loop,
    While,
    For,
    In,
    Break,
    Continue,
    True,
    False,
    As,
    Return,
    Extern,
    Const,
    Static,
    Type,
    // A keyword reserved for future use (see RESERVED_KEYWORDS).
    Reserved(&'static str),
    // Multi-char operators
    PlusEq,
    MinusEq,
    StarEq,
    SlashEq,
    PercentEq,
    AmpEq,
    PipeEq,
    CaretEq,
    BangEq,
    EqEq,
    GtEq,
    LtEq,
    AmpAmp,
    PipePipe,
    Arrow,
    FatArrow,
    Shl,
    Shr,
    ShlEq,
    ShrEq,
    DotDot,
    DotDotEq,
    Ellipsis,
    ColonColon,
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
    Hash,
    Question,
    At,
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
        let text = match self {
            TokenKind::IntLiteral(v) => return write!(f, "{v}"),
            TokenKind::FloatLiteral(v) => return write!(f, "{v}"),
            TokenKind::SuffixedInt(v, s) => return write!(f, "{v}{}", s.name()),
            TokenKind::SuffixedFloat(v, s) => return write!(f, "{v}{}", s.name()),
            TokenKind::CharLiteral(v) => return write!(f, "{:?}", *v as char),
            TokenKind::StringLiteral(v) => {
                return write!(f, "{:?}", String::from_utf8_lossy(v));
            }
            TokenKind::CStringLiteral(v) => {
                return write!(f, "c{:?}", String::from_utf8_lossy(v));
            }
            TokenKind::Ident(v) => return write!(f, "{}", v),
            TokenKind::Reserved(v) => v,
            TokenKind::Fn => "fn",
            TokenKind::Let => "let",
            TokenKind::Mut => "mut",
            TokenKind::Struct => "struct",
            TokenKind::If => "if",
            TokenKind::Else => "else",
            TokenKind::Loop => "loop",
            TokenKind::While => "while",
            TokenKind::For => "for",
            TokenKind::In => "in",
            TokenKind::Break => "break",
            TokenKind::Continue => "continue",
            TokenKind::True => "true",
            TokenKind::False => "false",
            TokenKind::As => "as",
            TokenKind::Return => "return",
            TokenKind::Extern => "extern",
            TokenKind::Const => "const",
            TokenKind::Static => "static",
            TokenKind::Type => "type",
            TokenKind::PlusEq => "+=",
            TokenKind::MinusEq => "-=",
            TokenKind::StarEq => "*=",
            TokenKind::SlashEq => "/=",
            TokenKind::PercentEq => "%=",
            TokenKind::AmpEq => "&=",
            TokenKind::PipeEq => "|=",
            TokenKind::CaretEq => "^=",
            TokenKind::BangEq => "!=",
            TokenKind::EqEq => "==",
            TokenKind::GtEq => ">=",
            TokenKind::LtEq => "<=",
            TokenKind::AmpAmp => "&&",
            TokenKind::PipePipe => "||",
            TokenKind::Arrow => "->",
            TokenKind::FatArrow => "=>",
            TokenKind::Shl => "<<",
            TokenKind::Shr => ">>",
            TokenKind::ShlEq => "<<=",
            TokenKind::ShrEq => ">>=",
            TokenKind::DotDot => "..",
            TokenKind::DotDotEq => "..=",
            TokenKind::Ellipsis => "...",
            TokenKind::ColonColon => "::",
            TokenKind::Eq => "=",
            TokenKind::Plus => "+",
            TokenKind::Minus => "-",
            TokenKind::Star => "*",
            TokenKind::Slash => "/",
            TokenKind::Percent => "%",
            TokenKind::Caret => "^",
            TokenKind::Amp => "&",
            TokenKind::Pipe => "|",
            TokenKind::Tilde => "~",
            TokenKind::Bang => "!",
            TokenKind::Lt => "<",
            TokenKind::Gt => ">",
            TokenKind::Dot => ".",
            TokenKind::Comma => ",",
            TokenKind::Semi => ";",
            TokenKind::Colon => ":",
            TokenKind::Hash => "#",
            TokenKind::Question => "?",
            TokenKind::At => "@",
            TokenKind::LParen => "(",
            TokenKind::RParen => ")",
            TokenKind::LBrace => "{",
            TokenKind::RBrace => "}",
            TokenKind::LBracket => "[",
            TokenKind::RBracket => "]",
            TokenKind::EOF => "EOF",
        };
        f.write_str(text)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Token {
    pub kind: TokenKind,
    pub span: lexer::span::Span,
    // No whitespace or comment follows the token (`&&x`, `>>`): the parser
    // may split such a token into its parts.
    pub joint: bool,
}
