use std::fmt;

use span::Span;
use token::{NumSuffix, RESERVED_KEYWORDS, Token, TokenKind};

pub mod float;
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

fn is_ident_byte(b: u8) -> bool {
    b == b'_' || b.is_ascii_alphanumeric()
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
            self.skip_ws_and_comments()?;
            if self.pos >= self.src.len() {
                tokens.push(Token {
                    kind: TokenKind::EOF,
                    span: Span::new(self.pos, self.pos),
                    joint: false,
                });
                break;
            }
            let (kind, start) = self.next_token()?;
            self.after_dot = kind == TokenKind::Dot;
            tokens.push(Token {
                kind,
                span: Span::new(start, self.pos),
                joint: self.at_joint(),
            });
        }
        Ok(tokens)
    }

    // Nothing separates the token just lexed from the next one.
    fn at_joint(&self) -> bool {
        match self.peek() {
            None => false,
            Some(b' ' | b'\t' | b'\r' | b'\n') => false,
            Some(b'/') => !matches!(self.peek_at(1), Some(b'/' | b'*')),
            Some(_) => true,
        }
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

    fn skip_ws_and_comments(&mut self) -> Result<(), LexError> {
        loop {
            while self.pos < self.src.len()
                && matches!(self.src[self.pos], b' ' | b'\t' | b'\r' | b'\n')
            {
                self.pos += 1;
            }
            match (self.peek(), self.peek_at(1)) {
                (Some(b'/'), Some(b'/')) => {
                    self.pos += 2;
                    while self.pos < self.src.len() && self.src[self.pos] != b'\n' {
                        self.pos += 1;
                    }
                }
                (Some(b'/'), Some(b'*')) => self.skip_block_comment()?,
                _ => return Ok(()),
            }
        }
    }

    // Block comments nest: `/* a /* b */ c */` is one comment.
    fn skip_block_comment(&mut self) -> Result<(), LexError> {
        let start = self.pos;
        let mut depth = 0usize;
        while self.pos < self.src.len() {
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
        Err(LexError {
            message: "unterminated block comment".into(),
            position: start,
        })
    }

    fn err(&self, msg: impl Into<String>) -> LexError {
        LexError {
            message: msg.into(),
            position: self.pos,
        }
    }

    // The character starting at byte `at`, for messages.
    fn char_at(&self, at: usize) -> char {
        std::str::from_utf8(&self.src[at..])
            .ok()
            .and_then(|s| s.chars().next())
            .unwrap_or(char::REPLACEMENT_CHARACTER)
    }

    fn next_token(&mut self) -> Result<(TokenKind, usize), LexError> {
        let start = self.pos;
        let b = self.peek().unwrap();

        if b == b'"' {
            self.advance();
            return Ok((
                TokenKind::StringLiteral(self.lex_string_body(start)?),
                start,
            ));
        }
        if b == b'c' && self.peek_at(1) == Some(b'"') {
            self.pos += 2;
            let bytes = self.lex_string_body(start)?;
            if bytes.contains(&0) {
                return Err(LexError {
                    message: "C string literal contains a NUL byte".into(),
                    position: start,
                });
            }
            return Ok((TokenKind::CStringLiteral(bytes), start));
        }
        if b == b'\'' {
            return Ok((self.lex_char()?, start));
        }
        if b.is_ascii_digit() {
            return Ok((self.lex_number()?, start));
        }
        if b == b'_' || b.is_ascii_alphabetic() {
            return Ok((self.lex_ident_or_keyword(), start));
        }

        // Three-char operators (must be checked before two-char)
        if let (Some(c1), Some(c2)) = (self.peek_at(1), self.peek_at(2)) {
            let kind = match (b, c1, c2) {
                (b'<', b'<', b'=') => Some(TokenKind::ShlEq),
                (b'>', b'>', b'=') => Some(TokenKind::ShrEq),
                (b'.', b'.', b'.') => Some(TokenKind::Ellipsis),
                (b'.', b'.', b'=') => Some(TokenKind::DotDotEq),
                _ => None,
            };
            if let Some(kind) = kind {
                self.pos += 3;
                return Ok((kind, start));
            }
        }

        // Two-char operators
        if let Some(next) = self.peek_at(1) {
            let kind = match (b, next) {
                (b'+', b'=') => Some(TokenKind::PlusEq),
                (b'-', b'=') => Some(TokenKind::MinusEq),
                (b'*', b'=') => Some(TokenKind::StarEq),
                (b'/', b'=') => Some(TokenKind::SlashEq),
                (b'%', b'=') => Some(TokenKind::PercentEq),
                (b'&', b'=') => Some(TokenKind::AmpEq),
                (b'|', b'=') => Some(TokenKind::PipeEq),
                (b'^', b'=') => Some(TokenKind::CaretEq),
                (b'!', b'=') => Some(TokenKind::BangEq),
                (b'=', b'=') => Some(TokenKind::EqEq),
                (b'>', b'=') => Some(TokenKind::GtEq),
                (b'<', b'=') => Some(TokenKind::LtEq),
                (b'<', b'<') => Some(TokenKind::Shl),
                (b'>', b'>') => Some(TokenKind::Shr),
                (b'&', b'&') => Some(TokenKind::AmpAmp),
                (b'|', b'|') => Some(TokenKind::PipePipe),
                (b'-', b'>') => Some(TokenKind::Arrow),
                (b'=', b'>') => Some(TokenKind::FatArrow),
                (b'.', b'.') => Some(TokenKind::DotDot),
                (b':', b':') => Some(TokenKind::ColonColon),
                _ => None,
            };
            if let Some(kind) = kind {
                self.pos += 2;
                return Ok((kind, start));
            }
        }

        // Single-char
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
            b'#' => TokenKind::Hash,
            b'?' => TokenKind::Question,
            b'@' => TokenKind::At,
            b'(' => TokenKind::LParen,
            b')' => TokenKind::RParen,
            b'{' => TokenKind::LBrace,
            b'}' => TokenKind::RBrace,
            b'[' => TokenKind::LBracket,
            b']' => TokenKind::RBracket,
            _ => {
                return Err(LexError {
                    message: format!("unexpected character '{}'", self.char_at(start)),
                    position: start,
                });
            }
        };
        self.pos += 1;
        Ok((kind, start))
    }

    // The bytes of a string literal; the opening quote is already consumed.
    fn lex_string_body(&mut self, start: usize) -> Result<Vec<u8>, LexError> {
        let mut val: Vec<u8> = Vec::new();
        loop {
            if self.pos >= self.src.len() {
                return Err(LexError {
                    message: "unterminated string literal".into(),
                    position: start,
                });
            }
            let b = self.advance();
            match b {
                b'"' => return Ok(val),
                b'\n' => {
                    return Err(LexError {
                        message: "newline in string literal".into(),
                        position: self.pos - 1,
                    });
                }
                b'\\' => self.lex_escape(&mut val, false)?,
                // The source is a &str, so non-ASCII bytes are already
                // valid UTF-8 and are copied through unchanged.
                _ => val.push(b),
            }
        }
    }

    // An escape sequence after '\'. In a character literal only escapes that
    // produce a single byte are allowed.
    fn lex_escape(&mut self, out: &mut Vec<u8>, in_char: bool) -> Result<(), LexError> {
        if self.pos >= self.src.len() {
            return Err(self.err("unterminated escape"));
        }
        let esc_at = self.pos;
        let esc = self.advance();
        match esc {
            b'n' => out.push(b'\n'),
            b't' => out.push(b'\t'),
            b'r' => out.push(b'\r'),
            b'0' => out.push(0),
            b'"' => out.push(b'"'),
            b'\'' => out.push(b'\''),
            b'\\' => out.push(b'\\'),
            b'x' => {
                let hi = self.hex_digit()?;
                let lo = self.hex_digit()?;
                out.push((hi << 4) | lo);
            }
            b'u' => {
                if self.peek() != Some(b'{') {
                    return Err(self.err("expected '{' after '\\u'"));
                }
                self.advance();
                let mut value: u32 = 0;
                let mut digits = 0;
                while self.peek() != Some(b'}') {
                    if digits == 6 {
                        return Err(self.err("too many digits in '\\u{...}' escape"));
                    }
                    value = value * 16 + self.hex_digit()? as u32;
                    digits += 1;
                }
                self.advance();
                if digits == 0 {
                    return Err(self.err("empty '\\u{}' escape"));
                }
                let ch = char::from_u32(value).ok_or_else(|| LexError {
                    message: format!("invalid unicode escape '\\u{{{:x}}}'", value),
                    position: esc_at - 1,
                })?;
                if in_char && !ch.is_ascii() {
                    return Err(LexError {
                        message: format!(
                            "character literal '\\u{{{:x}}}' is not ASCII (a character is one byte, u8)",
                            value
                        ),
                        position: esc_at - 1,
                    });
                }
                let mut buf = [0u8; 4];
                out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
            }
            _ => {
                return Err(LexError {
                    message: format!("unknown escape '\\{}'", self.char_at(esc_at)),
                    position: esc_at,
                });
            }
        }
        Ok(())
    }

    // 'a', '\n', '\x41': a single byte.
    fn lex_char(&mut self) -> Result<TokenKind, LexError> {
        let start = self.pos;
        self.advance(); // skip '
        let mut bytes = Vec::new();
        match self.peek() {
            None | Some(b'\n') => {
                return Err(LexError {
                    message: "unterminated character literal".into(),
                    position: start,
                });
            }
            Some(b'\'') => {
                return Err(LexError {
                    message: "empty character literal".into(),
                    position: start,
                });
            }
            Some(b'\\') => {
                self.advance();
                self.lex_escape(&mut bytes, true)?;
            }
            Some(b) if b.is_ascii() => {
                self.advance();
                bytes.push(b);
            }
            Some(_) => {
                return Err(LexError {
                    message: format!(
                        "character literal '{}' is not ASCII (a character is one byte, u8)",
                        self.char_at(self.pos)
                    ),
                    position: start,
                });
            }
        }
        if self.peek() != Some(b'\'') {
            return Err(LexError {
                message: "unterminated character literal (expected ')".into(),
                position: start,
            });
        }
        self.advance();
        Ok(TokenKind::CharLiteral(bytes[0]))
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
                message: format!("expected hex digit, got '{}'", self.char_at(self.pos - 1)),
                position: self.pos - 1,
            }),
        }
    }

    fn lex_number(&mut self) -> Result<TokenKind, LexError> {
        let start = self.pos;
        if self.src[self.pos] == b'0' {
            let radix = match self.peek_at(1) {
                Some(b'x' | b'X') => Some((16, "hex")),
                Some(b'b' | b'B') => Some((2, "binary")),
                _ => None,
            };
            if let Some((radix, name)) = radix {
                self.pos += 2;
                let value = self.lex_radix_digits(radix, name)?;
                return self.int_suffix(value, start, false);
            }
        }
        self.lex_decimal_or_float(start)
    }

    // Digits of a 0x/0b literal; '_' separators are allowed.
    fn lex_radix_digits(&mut self, radix: u32, name: &str) -> Result<u64, LexError> {
        if !self.peek().is_some_and(|b| (b as char).is_digit(radix)) {
            return Err(self.err(format!(
                "expected {} digit after '{}'",
                name,
                std::str::from_utf8(&self.src[self.pos - 2..self.pos]).unwrap()
            )));
        }
        let mut value: u64 = 0;
        let mut last_underscore = false;
        while let Some(b) = self.peek() {
            if b == b'_' {
                last_underscore = true;
                self.pos += 1;
                continue;
            }
            let Some(d) = (b as char).to_digit(radix) else {
                break;
            };
            last_underscore = false;
            value = value
                .checked_mul(radix as u64)
                .and_then(|v| v.checked_add(d as u64))
                .ok_or_else(|| self.err(format!("{} literal overflow", name)))?;
            self.pos += 1;
        }
        self.check_trailing_underscore(last_underscore)?;
        Ok(value)
    }

    // A '_' may end the digits only when a suffix follows (`1_u8`).
    fn check_trailing_underscore(&self, last_underscore: bool) -> Result<(), LexError> {
        if last_underscore && !self.peek().is_some_and(|b| b.is_ascii_alphabetic()) {
            return Err(LexError {
                message: "trailing underscore in literal".into(),
                position: self.pos - 1,
            });
        }
        Ok(())
    }

    // An identifier glued to a literal: its type suffix.
    fn read_suffix(&mut self) -> Option<(String, usize)> {
        if !self.peek().is_some_and(is_ident_byte) {
            return None;
        }
        let start = self.pos;
        while self.peek().is_some_and(is_ident_byte) {
            self.pos += 1;
        }
        let text = std::str::from_utf8(&self.src[start..self.pos]).unwrap();
        Some((text.to_string(), start))
    }

    fn int_suffix(
        &mut self,
        value: u64,
        start: usize,
        decimal: bool,
    ) -> Result<TokenKind, LexError> {
        let Some((suffix, at)) = self.read_suffix() else {
            return Ok(TokenKind::IntLiteral(value));
        };
        match NumSuffix::from_name(&suffix) {
            Some(s) if s.is_float() && decimal => {
                Ok(TokenKind::SuffixedFloat((value as f64).into(), s))
            }
            Some(s) if !s.is_float() => Ok(TokenKind::SuffixedInt(value, s)),
            _ => Err(LexError {
                message: format!(
                    "invalid suffix '{}' on integer literal {}",
                    suffix,
                    std::str::from_utf8(&self.src[start..at]).unwrap()
                ),
                position: at,
            }),
        }
    }

    fn lex_decimal_or_float(&mut self, start: usize) -> Result<TokenKind, LexError> {
        let int_str = self.read_dec_digits()?;
        // '.' followed by a digit, or an exponent, makes a float
        let has_fraction =
            self.peek() == Some(b'.') && self.peek_at(1).is_some_and(|b| b.is_ascii_digit());
        let has_exponent = matches!(self.peek(), Some(b'e' | b'E'))
            && match self.peek_at(1) {
                Some(b'+' | b'-') => self.peek_at(2).is_some_and(|b| b.is_ascii_digit()),
                Some(b) => b.is_ascii_digit(),
                None => false,
            };
        if self.after_dot || !(has_fraction || has_exponent) {
            let value: u64 = int_str.parse().map_err(|_| self.err("integer overflow"))?;
            return self.int_suffix(value, start, !self.after_dot);
        }
        let mut fs = int_str;
        if has_fraction {
            self.pos += 1; // skip '.'
            fs.push('.');
            fs.push_str(&self.read_dec_digits()?);
        }
        if matches!(self.peek(), Some(b'e' | b'E')) {
            self.pos += 1;
            fs.push('e');
            if matches!(self.peek(), Some(b'+' | b'-')) {
                fs.push(self.advance() as char);
            }
            if !self.peek().is_some_and(|b| b.is_ascii_digit()) {
                return Err(self.err("expected digit in exponent"));
            }
            fs.push_str(&self.read_dec_digits()?);
        }
        let value: f64 = fs.parse().map_err(|_| self.err("invalid float"))?;
        match self.read_suffix() {
            None => Ok(TokenKind::FloatLiteral(value.into())),
            Some((suffix, at)) => match NumSuffix::from_name(&suffix) {
                Some(s) if s.is_float() => Ok(TokenKind::SuffixedFloat(value.into(), s)),
                _ => Err(LexError {
                    message: format!("invalid suffix '{}' on float literal {}", suffix, fs),
                    position: at,
                }),
            },
        }
    }

    fn read_dec_digits(&mut self) -> Result<String, LexError> {
        if !self.peek().is_some_and(|b| b.is_ascii_digit()) {
            return Err(self.err("expected digit"));
        }
        let mut s = String::new();
        let mut last_underscore = false;
        while let Some(b) = self.peek() {
            if b == b'_' {
                last_underscore = true;
                self.pos += 1;
                continue;
            }
            if !b.is_ascii_digit() {
                break;
            }
            last_underscore = false;
            s.push(b as char);
            self.pos += 1;
        }
        self.check_trailing_underscore(last_underscore)?;
        Ok(s)
    }

    fn lex_ident_or_keyword(&mut self) -> TokenKind {
        let start = self.pos;
        while self.peek().is_some_and(is_ident_byte) {
            self.pos += 1;
        }
        let text = std::str::from_utf8(&self.src[start..self.pos]).unwrap();
        match text {
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
            _ => match RESERVED_KEYWORDS.iter().find(|k| **k == text) {
                Some(k) => TokenKind::Reserved(k),
                None => TokenKind::Ident(text.to_string()),
            },
        }
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
        let mut l = Lexer::new("3.25 1.0 2.0e10 1.5e-3");
        let t = l.tokenize().unwrap();
        assert!(matches!(t[0].kind, TokenKind::FloatLiteral(v) if (*v - 3.25).abs() < 1e-10));
        assert!(matches!(t[1].kind, TokenKind::FloatLiteral(v) if (*v - 1.0).abs() < 1e-10));
        assert!(matches!(t[2].kind, TokenKind::FloatLiteral(v) if (*v - 2.0e10).abs() < 1.0));
        assert!(matches!(t[3].kind, TokenKind::FloatLiteral(v) if (*v - 1.5e-3).abs() < 1e-10));
    }

    #[test]
    fn test_lex_strings() {
        let mut l = Lexer::new(r#""hello" "world\n" "\x41""#);
        let t = l.tokenize().unwrap();
        assert!(matches!(&t[0].kind, TokenKind::StringLiteral(s) if s == b"hello"));
        assert!(matches!(&t[1].kind, TokenKind::StringLiteral(s) if s == b"world\n"));
        assert!(matches!(&t[2].kind, TokenKind::StringLiteral(s) if s == b"A"));
    }

    #[test]
    fn test_lex_trailing_underscore_err() {
        let mut l = Lexer::new("100_");
        assert!(l.tokenize().is_err());
    }

    fn kinds(src: &str) -> Vec<TokenKind> {
        Lexer::new(src)
            .tokenize()
            .unwrap_or_else(|e| panic!("{}: {}", src, e))
            .into_iter()
            .map(|t| t.kind)
            .collect()
    }

    fn lex_err(src: &str) -> String {
        Lexer::new(src).tokenize().unwrap_err().message
    }

    #[test]
    fn test_lex_new_keywords_and_reserved() {
        assert_eq!(
            kinds("while for in mut const static type match Self moved"),
            vec![
                TokenKind::While,
                TokenKind::For,
                TokenKind::In,
                TokenKind::Mut,
                TokenKind::Const,
                TokenKind::Static,
                TokenKind::Type,
                TokenKind::Reserved("match"),
                TokenKind::Reserved("Self"),
                TokenKind::Ident("moved".into()),
                TokenKind::EOF,
            ]
        );
    }

    #[test]
    fn test_lex_star_star_is_two_tokens() {
        assert_eq!(
            kinds("**p"),
            vec![
                TokenKind::Star,
                TokenKind::Star,
                TokenKind::Ident("p".into()),
                TokenKind::EOF
            ]
        );
    }

    #[test]
    fn test_lex_joint_flag() {
        let t = Lexer::new("&&x && y // c\n").tokenize().unwrap();
        assert!(t[0].joint);
        assert!(!t[2].joint);
        assert!(!t[3].joint);
    }

    #[test]
    fn test_lex_block_comments_nest() {
        assert_eq!(
            kinds("1 /* a /* b */ c */ 2 /**/ 3"),
            vec![
                TokenKind::IntLiteral(1),
                TokenKind::IntLiteral(2),
                TokenKind::IntLiteral(3),
                TokenKind::EOF
            ]
        );
        assert!(lex_err("1 /* a /* b */").contains("unterminated block comment"));
    }

    #[test]
    fn test_lex_char_literals() {
        assert_eq!(
            kinds(r"'a' '\n' '\'' '\\' '\x41' '\u{7a}' '0'"),
            vec![
                TokenKind::CharLiteral(b'a'),
                TokenKind::CharLiteral(b'\n'),
                TokenKind::CharLiteral(b'\''),
                TokenKind::CharLiteral(b'\\'),
                TokenKind::CharLiteral(0x41),
                TokenKind::CharLiteral(b'z'),
                TokenKind::CharLiteral(b'0'),
                TokenKind::EOF,
            ]
        );
        assert!(lex_err("''").contains("empty character literal"));
        assert!(lex_err("'ab'").contains("unterminated character literal"));
        assert!(lex_err("'é'").contains("not ASCII"));
        assert!(lex_err(r"'\u{e9}'").contains("not ASCII"));
    }

    #[test]
    fn test_lex_unicode_escape_in_string() {
        assert_eq!(
            kinds(r#""\u{e9}\u{1F600}\'""#),
            vec![
                TokenKind::StringLiteral(vec![0xc3, 0xa9, 0xf0, 0x9f, 0x98, 0x80, b'\'']),
                TokenKind::EOF
            ]
        );
        assert!(lex_err(r#""\u{110000}""#).contains("invalid unicode escape"));
    }

    #[test]
    fn test_lex_c_strings() {
        assert_eq!(
            kinds(r#"c"hi\n" cx"#),
            vec![
                TokenKind::CStringLiteral(b"hi\n".to_vec()),
                TokenKind::Ident("cx".into()),
                TokenKind::EOF
            ]
        );
        assert!(lex_err(r#"c"a\0b""#).contains("NUL"));
    }

    #[test]
    fn test_lex_suffixes() {
        assert_eq!(
            kinds("1u8 255_u8 0xffu32 0b1i8 7usize 2f32 1.5f64 1e3f32 7i64"),
            vec![
                TokenKind::SuffixedInt(1, NumSuffix::U8),
                TokenKind::SuffixedInt(255, NumSuffix::U8),
                TokenKind::SuffixedInt(0xff, NumSuffix::U32),
                TokenKind::SuffixedInt(1, NumSuffix::I8),
                TokenKind::SuffixedInt(7, NumSuffix::Usize),
                TokenKind::SuffixedFloat(2.0.into(), NumSuffix::F32),
                TokenKind::SuffixedFloat(1.5.into(), NumSuffix::F64),
                TokenKind::SuffixedFloat(1e3.into(), NumSuffix::F32),
                TokenKind::SuffixedInt(7, NumSuffix::I64),
                TokenKind::EOF,
            ]
        );
        assert!(lex_err("1foo").contains("invalid suffix 'foo'"));
        assert!(lex_err("1.5u8").contains("invalid suffix 'u8' on float literal"));
        assert!(lex_err("0b1f32").contains("invalid suffix 'f32'"));
    }

    #[test]
    fn test_lex_ranges() {
        assert_eq!(
            kinds("0..10 a..=b"),
            vec![
                TokenKind::IntLiteral(0),
                TokenKind::DotDot,
                TokenKind::IntLiteral(10),
                TokenKind::Ident("a".into()),
                TokenKind::DotDotEq,
                TokenKind::Ident("b".into()),
                TokenKind::EOF,
            ]
        );
    }

    #[test]
    fn test_lex_non_ascii_message() {
        assert!(lex_err("é").contains("unexpected character 'é'"));
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
        let mut l = Lexer::new(
            "+= -= != == >= <= && || -> << >> <<= >>= ... *= /= %= &= |= ^= .. ..= :: => # ? @",
        );
        let t = l.tokenize().unwrap();
        let kinds: Vec<TokenKind> = t.into_iter().map(|t| t.kind).collect();
        assert_eq!(
            kinds,
            vec![
                TokenKind::PlusEq,
                TokenKind::MinusEq,
                TokenKind::BangEq,
                TokenKind::EqEq,
                TokenKind::GtEq,
                TokenKind::LtEq,
                TokenKind::AmpAmp,
                TokenKind::PipePipe,
                TokenKind::Arrow,
                TokenKind::Shl,
                TokenKind::Shr,
                TokenKind::ShlEq,
                TokenKind::ShrEq,
                TokenKind::Ellipsis,
                TokenKind::StarEq,
                TokenKind::SlashEq,
                TokenKind::PercentEq,
                TokenKind::AmpEq,
                TokenKind::PipeEq,
                TokenKind::CaretEq,
                TokenKind::DotDot,
                TokenKind::DotDotEq,
                TokenKind::ColonColon,
                TokenKind::FatArrow,
                TokenKind::Hash,
                TokenKind::Question,
                TokenKind::At,
                TokenKind::EOF,
            ]
        );
    }

    #[test]
    fn test_lex_comments() {
        let mut l = Lexer::new("42 // comment\n43");
        let t = l.tokenize().unwrap();
        assert!(matches!(t[0].kind, TokenKind::IntLiteral(42)));
        assert!(matches!(t[1].kind, TokenKind::IntLiteral(43)));
    }

    #[test]
    fn test_lex_exponent_without_fraction() {
        let mut l = Lexer::new("1e3 2E-2 7e+1");
        let t = l.tokenize().unwrap();
        assert!(matches!(&t[0].kind, TokenKind::FloatLiteral(f) if **f == 1e3));
        assert!(matches!(&t[1].kind, TokenKind::FloatLiteral(f) if **f == 2e-2));
        assert!(matches!(&t[2].kind, TokenKind::FloatLiteral(f) if **f == 7e1));
        // `3e` has no exponent digits: `e` is an (invalid) suffix
        let err = Lexer::new("3e").tokenize().unwrap_err();
        assert!(
            err.message.contains("invalid suffix 'e'"),
            "{}",
            err.message
        );
    }

    #[test]
    fn test_lex_nested_tuple_index() {
        let mut l = Lexer::new("t.0.1 x = 0.1");
        let t = l.tokenize().unwrap();
        assert!(matches!(t[2].kind, TokenKind::IntLiteral(0)));
        assert!(matches!(t[3].kind, TokenKind::Dot));
        assert!(matches!(t[4].kind, TokenKind::IntLiteral(1)));
        assert!(matches!(&t[7].kind, TokenKind::FloatLiteral(f) if **f == 0.1));
    }

    #[test]
    fn test_lex_hex_escape_is_one_byte() {
        let mut l = Lexer::new(r#""\xff\x00é""#);
        let t = l.tokenize().unwrap();
        assert!(
            matches!(&t[0].kind, TokenKind::StringLiteral(s) if s == &[0xff, 0x00, 0xc3, 0xa9])
        );
    }
}
