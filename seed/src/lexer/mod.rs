// Lexer: turns source text into tokens. Works on bytes; non-ASCII text is
// only allowed inside string literals and comments.

use std::fmt;

use span::Span;
use token::{RESERVED_KEYWORDS, Token, TokenKind};

pub mod float;
mod literals;
pub mod span;
pub mod token;

#[derive(Debug, Clone, PartialEq)]
pub struct LexError {
    pub message: String,
    pub position: usize,
}

impl fmt::Display for LexError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "lex error at byte {}: {}", self.position, self.message)
    }
}

pub struct Lexer<'a> {
    src: &'a [u8],
    pos: usize,
    // The previous token was '.', so a number is a tuple index: `t.0.1` is
    // `t . 0 . 1`, not `t . 0.1`.
    after_dot: bool,
}

fn is_ident_byte(byte: u8) -> bool {
    byte == b'_' || byte.is_ascii_alphanumeric()
}

fn is_whitespace(byte: u8) -> bool {
    matches!(byte, b' ' | b'\t' | b'\r' | b'\n')
}

impl<'a> Lexer<'a> {
    pub fn new(src: &'a str) -> Self {
        Self {
            src: src.as_bytes(),
            pos: 0,
            after_dot: false,
        }
    }

    pub fn tokenize(&mut self) -> Result<Vec<Token>, LexError> {
        let mut tokens = Vec::new();
        loop {
            self.skip_whitespace_and_comments()?;
            if self.at_end() {
                tokens.push(Token {
                    kind: TokenKind::EOF,
                    span: Span::new(self.pos, self.pos),
                    joint: false,
                });
                return Ok(tokens);
            }
            let start = self.pos;
            let kind = self.next_token()?;
            self.after_dot = kind == TokenKind::Dot;
            tokens.push(Token {
                kind,
                span: Span::new(start, self.pos),
                joint: self.at_joint(),
            });
        }
    }

    // ---- Reading bytes ----

    fn at_end(&self) -> bool {
        self.pos >= self.src.len()
    }

    fn peek(&self) -> Option<u8> {
        self.src.get(self.pos).copied()
    }

    fn peek_at(&self, offset: usize) -> Option<u8> {
        self.src.get(self.pos + offset).copied()
    }

    fn advance(&mut self) -> u8 {
        let byte = self.src[self.pos];
        self.pos += 1;
        byte
    }

    // The source text from `start` up to the current position.
    fn text_from(&self, start: usize) -> &'a str {
        std::str::from_utf8(&self.src[start..self.pos]).expect("token text is ASCII")
    }

    // Nothing separates the token just lexed from the next one.
    fn at_joint(&self) -> bool {
        match self.peek() {
            None => false,
            Some(byte) if is_whitespace(byte) => false,
            Some(b'/') => !matches!(self.peek_at(1), Some(b'/' | b'*')),
            Some(_) => true,
        }
    }

    // ---- Errors ----

    fn error_at(&self, position: usize, message: impl Into<String>) -> LexError {
        LexError {
            message: message.into(),
            position,
        }
    }

    fn error_here(&self, message: impl Into<String>) -> LexError {
        self.error_at(self.pos, message)
    }

    // The character starting at byte `at`, for messages.
    fn char_at(&self, at: usize) -> char {
        std::str::from_utf8(&self.src[at..])
            .ok()
            .and_then(|s| s.chars().next())
            .unwrap_or(char::REPLACEMENT_CHARACTER)
    }

    // ---- Whitespace and comments ----

    fn skip_whitespace_and_comments(&mut self) -> Result<(), LexError> {
        loop {
            while self.peek().is_some_and(is_whitespace) {
                self.pos += 1;
            }
            match (self.peek(), self.peek_at(1)) {
                (Some(b'/'), Some(b'/')) => self.skip_line_comment(),
                (Some(b'/'), Some(b'*')) => self.skip_block_comment()?,
                _ => return Ok(()),
            }
        }
    }

    fn skip_line_comment(&mut self) {
        while self.peek().is_some_and(|byte| byte != b'\n') {
            self.pos += 1;
        }
    }

    // Block comments nest: `/* a /* b */ c */` is one comment.
    fn skip_block_comment(&mut self) -> Result<(), LexError> {
        let start = self.pos;
        let mut depth = 0usize;
        while !self.at_end() {
            match (self.peek(), self.peek_at(1)) {
                (Some(b'/'), Some(b'*')) => {
                    depth += 1;
                    self.pos += 2;
                }
                (Some(b'*'), Some(b'/')) => {
                    depth -= 1;
                    self.pos += 2;
                    if depth == 0 {
                        return Ok(());
                    }
                }
                _ => self.pos += 1,
            }
        }
        Err(self.error_at(start, "unterminated block comment"))
    }

    // ---- Tokens ----

    fn next_token(&mut self) -> Result<TokenKind, LexError> {
        let first = self.peek().expect("called before the end of the input");
        match first {
            b'"' => {
                let start = self.pos;
                self.advance();
                Ok(TokenKind::StringLiteral(self.lex_string_body(start)?))
            }
            b'c' if self.peek_at(1) == Some(b'"') => self.lex_c_string(),
            b'\'' => self.lex_char(),
            b'0'..=b'9' => self.lex_number(),
            b'_' | b'a'..=b'z' | b'A'..=b'Z' => Ok(self.lex_ident_or_keyword()),
            _ => self.lex_operator(),
        }
    }

    // The longest operator or punctuation token at the current position.
    fn lex_operator(&mut self) -> Result<TokenKind, LexError> {
        let first = self.peek().expect("called before the end of the input");
        let second = self.peek_at(1);
        let third = self.peek_at(2);
        if let (Some(second), Some(third)) = (second, third)
            && let Some(kind) = three_char_operator(first, second, third)
        {
            self.pos += 3;
            return Ok(kind);
        }
        if let Some(second) = second
            && let Some(kind) = two_char_operator(first, second)
        {
            self.pos += 2;
            return Ok(kind);
        }
        match one_char_operator(first) {
            Some(kind) => {
                self.pos += 1;
                Ok(kind)
            }
            None => {
                Err(self.error_here(format!("unexpected character '{}'", self.char_at(self.pos))))
            }
        }
    }

    fn lex_ident_or_keyword(&mut self) -> TokenKind {
        let start = self.pos;
        while self.peek().is_some_and(is_ident_byte) {
            self.pos += 1;
        }
        let text = self.text_from(start);
        keyword(text).unwrap_or_else(|| match RESERVED_KEYWORDS.iter().find(|k| **k == text) {
            Some(reserved) => TokenKind::Reserved(reserved),
            None => TokenKind::Ident(text.to_string()),
        })
    }
}

fn keyword(text: &str) -> Option<TokenKind> {
    Some(match text {
        "fn" => TokenKind::Fn,
        "let" => TokenKind::Let,
        "mut" => TokenKind::Mut,
        "struct" => TokenKind::Struct,
        "if" => TokenKind::If,
        "else" => TokenKind::Else,
        "loop" => TokenKind::Loop,
        "while" => TokenKind::While,
        "for" => TokenKind::For,
        "in" => TokenKind::In,
        "break" => TokenKind::Break,
        "continue" => TokenKind::Continue,
        "true" => TokenKind::True,
        "false" => TokenKind::False,
        "as" => TokenKind::As,
        "return" => TokenKind::Return,
        "extern" => TokenKind::Extern,
        "const" => TokenKind::Const,
        "static" => TokenKind::Static,
        "type" => TokenKind::Type,
        _ => return None,
    })
}

fn three_char_operator(first: u8, second: u8, third: u8) -> Option<TokenKind> {
    Some(match (first, second, third) {
        (b'<', b'<', b'=') => TokenKind::ShlEq,
        (b'>', b'>', b'=') => TokenKind::ShrEq,
        (b'.', b'.', b'.') => TokenKind::Ellipsis,
        (b'.', b'.', b'=') => TokenKind::DotDotEq,
        _ => return None,
    })
}

fn two_char_operator(first: u8, second: u8) -> Option<TokenKind> {
    Some(match (first, second) {
        (b'+', b'=') => TokenKind::PlusEq,
        (b'-', b'=') => TokenKind::MinusEq,
        (b'*', b'=') => TokenKind::StarEq,
        (b'/', b'=') => TokenKind::SlashEq,
        (b'%', b'=') => TokenKind::PercentEq,
        (b'&', b'=') => TokenKind::AmpEq,
        (b'|', b'=') => TokenKind::PipeEq,
        (b'^', b'=') => TokenKind::CaretEq,
        (b'!', b'=') => TokenKind::BangEq,
        (b'=', b'=') => TokenKind::EqEq,
        (b'>', b'=') => TokenKind::GtEq,
        (b'<', b'=') => TokenKind::LtEq,
        (b'<', b'<') => TokenKind::Shl,
        (b'>', b'>') => TokenKind::Shr,
        (b'&', b'&') => TokenKind::AmpAmp,
        (b'|', b'|') => TokenKind::PipePipe,
        (b'-', b'>') => TokenKind::Arrow,
        (b'=', b'>') => TokenKind::FatArrow,
        (b'.', b'.') => TokenKind::DotDot,
        (b':', b':') => TokenKind::ColonColon,
        _ => return None,
    })
}

fn one_char_operator(byte: u8) -> Option<TokenKind> {
    Some(match byte {
        b'=' => TokenKind::Eq,
        b'+' => TokenKind::Plus,
        b'-' => TokenKind::Minus,
        b'*' => TokenKind::Star,
        b'/' => TokenKind::Slash,
        b'%' => TokenKind::Percent,
        b'^' => TokenKind::Caret,
        b'&' => TokenKind::Amp,
        b'|' => TokenKind::Pipe,
        b'~' => TokenKind::Tilde,
        b'!' => TokenKind::Bang,
        b'<' => TokenKind::Lt,
        b'>' => TokenKind::Gt,
        b'.' => TokenKind::Dot,
        b',' => TokenKind::Comma,
        b';' => TokenKind::Semi,
        b':' => TokenKind::Colon,
        b'#' => TokenKind::Hash,
        b'?' => TokenKind::Question,
        b'@' => TokenKind::At,
        b'(' => TokenKind::LParen,
        b')' => TokenKind::RParen,
        b'{' => TokenKind::LBrace,
        b'}' => TokenKind::RBrace,
        b'[' => TokenKind::LBracket,
        b']' => TokenKind::RBracket,
        _ => return None,
    })
}

#[cfg(test)]
mod tests;
