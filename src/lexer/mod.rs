use std::fmt;

use span::Span;
use token::{Token, TokenKind};

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
}

impl<'a> Lexer<'a> {
    pub fn new(src: &'a str) -> Self {
        Self {
            src: src.as_bytes(),
            pos: 0,
        }
    }

    #[tracing::instrument(skip(self))]
    pub fn tokenize(&mut self) -> Result<Vec<Token>, LexError> {
        let mut tokens = Vec::new();
        loop {
            self.skip_ws_and_comments();
            if self.pos >= self.src.len() {
                tokens.push(Token {
                    kind: TokenKind::EOF,
                    span: Span::new(self.pos, self.pos),
                });
                break;
            }
            tokens.push(self.next_token()?);
        }
        Ok(tokens)
    }

    fn peek(&self) -> Option<u8> {
        self.src.get(self.pos).copied()
    }

    fn peek_at(&self, off: usize) -> Option<u8> {
        self.src.get(self.pos + off).copied()
    }

    fn advance(&mut self) -> u8 {
        let b = self.src[self.pos];
        self.pos += 1;
        b
    }

    #[tracing::instrument(skip(self))]
    fn skip_ws_and_comments(&mut self) {
        loop {
            while self.pos < self.src.len()
                && matches!(self.src[self.pos], b' ' | b'\t' | b'\r' | b'\n')
            {
                self.pos += 1;
            }
            if self.pos + 1 < self.src.len()
                && self.src[self.pos] == b'/'
                && self.src[self.pos + 1] == b'/'
            {
                self.pos += 2;
                while self.pos < self.src.len() && self.src[self.pos] != b'\n' {
                    self.pos += 1;
                }
                continue;
            }
            break;
        }
    }

    fn err(&self, msg: impl Into<String>) -> LexError {
        LexError {
            message: msg.into(),
            position: self.pos,
        }
    }

    #[tracing::instrument(skip(self), level = "trace", ret)]
    fn next_token(&mut self) -> Result<Token, LexError> {
        let start = self.pos;
        let b = self.peek().unwrap();

        if b == b'"' {
            return self.lex_string();
        }
        if b.is_ascii_digit() {
            return self.lex_number();
        }
        if b == b'_' || b.is_ascii_alphabetic() {
            return self.lex_ident_or_keyword();
        }

        // Three-char operators (must be checked before two-char)
        if let (Some(c1), Some(c2)) = (self.peek_at(1), self.peek_at(2)) {
            let kind = match (b, c1, c2) {
                (b'<', b'<', b'=') => Some(TokenKind::ShlEq),
                (b'>', b'>', b'=') => Some(TokenKind::ShrEq),
                _ => None,
            };
            if let Some(kind) = kind {
                self.pos += 3;
                return Ok(Token {
                    kind,
                    span: Span::new(start, self.pos),
                });
            }
        }

        // Two-char operators
        if let Some(next) = self.peek_at(1) {
            let kind = match (b, next) {
                (b'+', b'=') => Some(TokenKind::PlusEq),
                (b'-', b'=') => Some(TokenKind::MinusEq),
                (b'!', b'=') => Some(TokenKind::BangEq),
                (b'=', b'=') => Some(TokenKind::EqEq),
                (b'>', b'=') => Some(TokenKind::GtEq),
                (b'<', b'=') => Some(TokenKind::LtEq),
                (b'<', b'<') => Some(TokenKind::Shl),
                (b'>', b'>') => Some(TokenKind::Shr),
                (b'&', b'&') => Some(TokenKind::AmpAmp),
                (b'|', b'|') => Some(TokenKind::PipePipe),
                (b'*', b'*') => Some(TokenKind::StarStar),
                (b'-', b'>') => Some(TokenKind::Arrow),
                _ => None,
            };
            if let Some(kind) = kind {
                self.pos += 2;
                return Ok(Token {
                    kind,
                    span: Span::new(start, self.pos),
                });
            }
        }

        // Single-char
        self.pos += 1;
        let kind = match b {
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
            b'(' => TokenKind::LParen,
            b')' => TokenKind::RParen,
            b'{' => TokenKind::LBrace,
            b'}' => TokenKind::RBrace,
            b'[' => TokenKind::LBracket,
            b']' => TokenKind::RBracket,
            _ => {
                return Err(LexError {
                    message: format!("unexpected character '{}'", b as char),
                    position: start,
                });
            }
        };
        Ok(Token {
            kind,
            span: Span::new(start, self.pos),
        })
    }

    fn lex_string(&mut self) -> Result<Token, LexError> {
        let start = self.pos;
        self.advance(); // skip "
        let mut val = String::new();
        loop {
            if self.pos >= self.src.len() {
                return Err(self.err("unterminated string literal"));
            }
            let b = self.advance();
            match b {
                b'"' => {
                    return Ok(Token {
                        kind: TokenKind::StringLiteral(val),
                        span: Span::new(start, self.pos),
                    });
                }
                b'\n' => {
                    return Err(LexError {
                        message: "newline in string literal".into(),
                        position: self.pos - 1,
                    });
                }
                b'\\' => {
                    if self.pos >= self.src.len() {
                        return Err(self.err("unterminated escape"));
                    }
                    let esc = self.advance();
                    match esc {
                        b'n' => val.push('\n'),
                        b't' => val.push('\t'),
                        b'r' => val.push('\r'),
                        b'0' => val.push('\0'),
                        b'"' => val.push('"'),
                        b'\\' => val.push('\\'),
                        b'x' => {
                            let hi = self.hex_digit()?;
                            let lo = self.hex_digit()?;
                            val.push(((hi << 4) | lo) as char);
                        }
                        _ => {
                            return Err(LexError {
                                message: format!("unknown escape '\\{}'", esc as char),
                                position: self.pos - 1,
                            });
                        }
                    }
                }
                _ => {
                    if b < 0x80 {
                        val.push(b as char);
                    } else {
                        self.pos -= 1;
                        let s = std::str::from_utf8(&self.src[self.pos..])
                            .map_err(|_| self.err("invalid UTF-8"))?;
                        let ch = s.chars().next().unwrap();
                        self.pos += ch.len_utf8();
                        val.push(ch);
                    }
                }
            }
        }
    }

    fn hex_digit(&mut self) -> Result<u8, LexError> {
        if self.pos >= self.src.len() {
            return Err(self.err("expected hex digit"));
        }
        let b = self.advance();
        match b {
            b'0'..=b'9' => Ok(b - b'0'),
            b'a'..=b'f' => Ok(b - b'a' + 10),
            b'A'..=b'F' => Ok(b - b'A' + 10),
            _ => Err(LexError {
                message: format!("expected hex digit, got '{}'", b as char),
                position: self.pos - 1,
            }),
        }
    }

    fn lex_number(&mut self) -> Result<Token, LexError> {
        let start = self.pos;
        if self.src[self.pos] == b'0' {
            if let Some(next) = self.peek_at(1) {
                if next == b'x' || next == b'X' {
                    return self.lex_hex_int(start);
                }
                if next == b'b' || next == b'B' {
                    return self.lex_bin_int(start);
                }
            }
        }
        self.lex_decimal_or_float(start)
    }

    fn lex_hex_int(&mut self, start: usize) -> Result<Token, LexError> {
        self.pos += 2;
        if self.pos >= self.src.len() || !self.src[self.pos].is_ascii_hexdigit() {
            return Err(self.err("expected hex digit after '0x'"));
        }
        let mut value: u64 = 0;
        let mut last_underscore = false;
        while self.pos < self.src.len() {
            let b = self.src[self.pos];
            if b == b'_' {
                last_underscore = true;
                self.pos += 1;
                continue;
            }
            if b.is_ascii_hexdigit() {
                last_underscore = false;
                let d = match b {
                    b'0'..=b'9' => (b - b'0') as u64,
                    b'a'..=b'f' => (b - b'a' + 10) as u64,
                    b'A'..=b'F' => (b - b'A' + 10) as u64,
                    _ => unreachable!(),
                };
                value = value
                    .checked_mul(16)
                    .and_then(|v| v.checked_add(d))
                    .ok_or_else(|| self.err("hex literal overflow"))?;
                self.pos += 1;
            } else {
                break;
            }
        }
        if last_underscore {
            return Err(LexError {
                message: "trailing underscore in literal".into(),
                position: self.pos - 1,
            });
        }
        Ok(Token {
            kind: TokenKind::IntLiteral(value),
            span: Span::new(start, self.pos),
        })
    }

    fn lex_bin_int(&mut self, start: usize) -> Result<Token, LexError> {
        self.pos += 2;
        if self.pos >= self.src.len() || !matches!(self.src[self.pos], b'0' | b'1') {
            return Err(self.err("expected binary digit after '0b'"));
        }
        let mut value: u64 = 0;
        let mut last_underscore = false;
        while self.pos < self.src.len() {
            let b = self.src[self.pos];
            if b == b'_' {
                last_underscore = true;
                self.pos += 1;
                continue;
            }
            if matches!(b, b'0' | b'1') {
                last_underscore = false;
                value = value
                    .checked_mul(2)
                    .and_then(|v| v.checked_add((b - b'0') as u64))
                    .ok_or_else(|| self.err("binary literal overflow"))?;
                self.pos += 1;
            } else {
                break;
            }
        }
        if last_underscore {
            return Err(LexError {
                message: "trailing underscore in literal".into(),
                position: self.pos - 1,
            });
        }
        Ok(Token {
            kind: TokenKind::IntLiteral(value),
            span: Span::new(start, self.pos),
        })
    }

    fn lex_decimal_or_float(&mut self, start: usize) -> Result<Token, LexError> {
        let int_str = self.read_dec_digits()?;
        // Check for '.' followed by digit => float
        if self.pos < self.src.len()
            && self.src[self.pos] == b'.'
            && self.peek_at(1).map_or(false, |b| b.is_ascii_digit())
        {
            self.pos += 1; // skip '.'
            let frac_str = self.read_dec_digits()?;
            let mut fs = format!("{}.{}", int_str, frac_str);
            if self.pos < self.src.len() && self.src[self.pos] == b'e' {
                self.pos += 1;
                fs.push('e');
                if self.pos < self.src.len() && matches!(self.src[self.pos], b'+' | b'-') {
                    fs.push(self.advance() as char);
                }
                if self.pos >= self.src.len() || !self.src[self.pos].is_ascii_digit() {
                    return Err(self.err("expected digit in exponent"));
                }
                fs.push_str(&self.read_dec_digits()?);
            }
            let value: f64 = fs.parse().map_err(|_| self.err("invalid float"))?;
            return Ok(Token {
                kind: TokenKind::FloatLiteral(value),
                span: Span::new(start, self.pos),
            });
        }
        let value: u64 = int_str.parse().map_err(|_| self.err("integer overflow"))?;
        Ok(Token {
            kind: TokenKind::IntLiteral(value),
            span: Span::new(start, self.pos),
        })
    }

    fn read_dec_digits(&mut self) -> Result<String, LexError> {
        if self.pos >= self.src.len() || !self.src[self.pos].is_ascii_digit() {
            return Err(self.err("expected digit"));
        }
        let mut s = String::new();
        let mut last_underscore = false;
        while self.pos < self.src.len() {
            let b = self.src[self.pos];
            if b == b'_' {
                last_underscore = true;
                self.pos += 1;
                continue;
            }
            if b.is_ascii_digit() {
                last_underscore = false;
                s.push(b as char);
                self.pos += 1;
            } else {
                break;
            }
        }
        if last_underscore {
            return Err(LexError {
                message: "trailing underscore in literal".into(),
                position: self.pos - 1,
            });
        }
        Ok(s)
    }

    fn lex_ident_or_keyword(&mut self) -> Result<Token, LexError> {
        let start = self.pos;
        while self.pos < self.src.len()
            && (self.src[self.pos] == b'_' || self.src[self.pos].is_ascii_alphanumeric())
        {
            self.pos += 1;
        }
        let text = std::str::from_utf8(&self.src[start..self.pos]).unwrap();
        let kind = match text {
            "fn" => TokenKind::Fn,
            "let" => TokenKind::Let,
            "struct" => TokenKind::Struct,
            "if" => TokenKind::If,
            "else" => TokenKind::Else,
            "loop" => TokenKind::Loop,
            "break" => TokenKind::Break,
            "continue" => TokenKind::Continue,
            "true" => TokenKind::True,
            "false" => TokenKind::False,
            "as" => TokenKind::As,
            "return" => TokenKind::Return,
            "extern" => TokenKind::Extern,
            _ => TokenKind::Ident(text.to_string()),
        };
        Ok(Token {
            kind,
            span: Span::new(start, self.pos),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lex_integers() {
        let mut l = Lexer::new("42 0xFF 0b1010 1_000_000");
        let t = l.tokenize().unwrap();
        assert!(matches!(t[0].kind, TokenKind::IntLiteral(42)));
        assert!(matches!(t[1].kind, TokenKind::IntLiteral(255)));
        assert!(matches!(t[2].kind, TokenKind::IntLiteral(10)));
        assert!(matches!(t[3].kind, TokenKind::IntLiteral(1000000)));
    }

    #[test]
    fn test_lex_floats() {
        let mut l = Lexer::new("3.14 1.0 2.0e10 1.5e-3");
        let t = l.tokenize().unwrap();
        assert!(matches!(t[0].kind, TokenKind::FloatLiteral(v) if (v - 3.14).abs() < 1e-10));
        assert!(matches!(t[1].kind, TokenKind::FloatLiteral(v) if (v - 1.0).abs() < 1e-10));
        assert!(matches!(t[2].kind, TokenKind::FloatLiteral(v) if (v - 2.0e10).abs() < 1.0));
        assert!(matches!(t[3].kind, TokenKind::FloatLiteral(v) if (v - 1.5e-3).abs() < 1e-10));
    }

    #[test]
    fn test_lex_strings() {
        let mut l = Lexer::new(r#""hello" "world\n" "\x41""#);
        let t = l.tokenize().unwrap();
        assert!(matches!(&t[0].kind, TokenKind::StringLiteral(s) if s == "hello"));
        assert!(matches!(&t[1].kind, TokenKind::StringLiteral(s) if s == "world\n"));
        assert!(matches!(&t[2].kind, TokenKind::StringLiteral(s) if s == "A"));
    }

    #[test]
    fn test_lex_trailing_underscore_err() {
        let mut l = Lexer::new("100_");
        assert!(l.tokenize().is_err());
    }

    #[test]
    fn test_lex_keywords_and_idents() {
        let mut l =
            Lexer::new("fn let struct if else loop break continue true false as return extern foo");
        let t = l.tokenize().unwrap();
        assert!(matches!(t[0].kind, TokenKind::Fn));
        assert!(matches!(t[1].kind, TokenKind::Let));
        assert!(matches!(t[2].kind, TokenKind::Struct));
        assert!(matches!(t[3].kind, TokenKind::If));
        assert!(matches!(t[4].kind, TokenKind::Else));
        assert!(matches!(t[5].kind, TokenKind::Loop));
        assert!(matches!(t[6].kind, TokenKind::Break));
        assert!(matches!(t[7].kind, TokenKind::Continue));
        assert!(matches!(t[8].kind, TokenKind::True));
        assert!(matches!(t[9].kind, TokenKind::False));
        assert!(matches!(t[10].kind, TokenKind::As));
        assert!(matches!(t[11].kind, TokenKind::Return));
        assert!(matches!(t[12].kind, TokenKind::Extern));
        assert!(matches!(&t[13].kind, TokenKind::Ident(s) if s == "foo"));
    }

    #[test]
    fn test_lex_operators() {
        let mut l = Lexer::new("+= -= != == >= <= && || ** -> << >> <<= >>=");
        let t = l.tokenize().unwrap();
        assert!(matches!(t[0].kind, TokenKind::PlusEq));
        assert!(matches!(t[1].kind, TokenKind::MinusEq));
        assert!(matches!(t[2].kind, TokenKind::BangEq));
        assert!(matches!(t[3].kind, TokenKind::EqEq));
        assert!(matches!(t[4].kind, TokenKind::GtEq));
        assert!(matches!(t[5].kind, TokenKind::LtEq));
        assert!(matches!(t[6].kind, TokenKind::AmpAmp));
        assert!(matches!(t[7].kind, TokenKind::PipePipe));
        assert!(matches!(t[8].kind, TokenKind::StarStar));
        assert!(matches!(t[9].kind, TokenKind::Arrow));
        assert!(matches!(t[10].kind, TokenKind::Shl));
        assert!(matches!(t[11].kind, TokenKind::Shr));
        assert!(matches!(t[12].kind, TokenKind::ShlEq));
        assert!(matches!(t[13].kind, TokenKind::ShrEq));
    }

    #[test]
    fn test_lex_comments() {
        let mut l = Lexer::new("42 // comment\n43");
        let t = l.tokenize().unwrap();
        assert!(matches!(t[0].kind, TokenKind::IntLiteral(42)));
        assert!(matches!(t[1].kind, TokenKind::IntLiteral(43)));
    }
}
