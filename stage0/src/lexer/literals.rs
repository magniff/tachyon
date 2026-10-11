// String, character and number literals.

use super::token::{NumSuffix, TokenKind};
use super::{LexError, Lexer, is_ident_byte};

// The largest number of hex digits in a `\u{...}` escape.
const MAX_UNICODE_ESCAPE_DIGITS: u32 = 6;

impl<'a> Lexer<'a> {
    // ---- Strings and characters ----

    // The bytes of a string literal; the opening quote is already consumed.
    pub(super) fn lex_string_body(&mut self, start: usize) -> Result<Vec<u8>, LexError> {
        let mut bytes = Vec::new();
        loop {
            if self.at_end() {
                return Err(self.error_at(start, "unterminated string literal"));
            }
            match self.advance() {
                b'"' => return Ok(bytes),
                b'\n' => return Err(self.error_at(self.pos - 1, "newline in string literal")),
                b'\\' => self.lex_escape(&mut bytes, false)?,
                // The source is a &str, so non-ASCII bytes are already
                // valid UTF-8 and are copied through unchanged.
                byte => bytes.push(byte),
            }
        }
    }

    // c"...": a string for C, which must not contain NUL.
    pub(super) fn lex_c_string(&mut self) -> Result<TokenKind, LexError> {
        let start = self.pos;
        self.pos += 2;
        let bytes = self.lex_string_body(start)?;
        if bytes.contains(&0) {
            return Err(self.error_at(start, "C string literal contains a NUL byte"));
        }
        Ok(TokenKind::CStringLiteral(bytes))
    }

    // An escape sequence after '\'. In a character literal only escapes that
    // produce a single byte are allowed.
    fn lex_escape(&mut self, out: &mut Vec<u8>, in_char: bool) -> Result<(), LexError> {
        if self.at_end() {
            return Err(self.error_here("unterminated escape"));
        }
        let escape_at = self.pos;
        match self.advance() {
            b'n' => out.push(b'\n'),
            b't' => out.push(b'\t'),
            b'r' => out.push(b'\r'),
            b'0' => out.push(0),
            b'"' => out.push(b'"'),
            b'\'' => out.push(b'\''),
            b'\\' => out.push(b'\\'),
            b'x' => {
                let high = self.hex_digit()?;
                let low = self.hex_digit()?;
                out.push((high << 4) | low);
            }
            b'u' => {
                let ch = self.lex_unicode_escape(escape_at - 1, in_char)?;
                let mut buf = [0u8; 4];
                out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
            }
            _ => {
                return Err(self.error_at(
                    escape_at,
                    format!("unknown escape '\\{}'", self.char_at(escape_at)),
                ));
            }
        }
        Ok(())
    }

    // `\u{XXXX}` after the `u`; `backslash_at` is where the escape starts.
    fn lex_unicode_escape(&mut self, backslash_at: usize, in_char: bool) -> Result<char, LexError> {
        if self.peek() != Some(b'{') {
            return Err(self.error_here("expected '{' after '\\u'"));
        }
        self.advance();
        let mut value: u32 = 0;
        let mut digits = 0;
        while self.peek() != Some(b'}') {
            if digits == MAX_UNICODE_ESCAPE_DIGITS {
                return Err(self.error_here("too many digits in '\\u{...}' escape"));
            }
            value = value * 16 + self.hex_digit()? as u32;
            digits += 1;
        }
        self.advance();
        if digits == 0 {
            return Err(self.error_here("empty '\\u{}' escape"));
        }
        let ch = char::from_u32(value).ok_or_else(|| {
            self.error_at(
                backslash_at,
                format!("invalid unicode escape '\\u{{{:x}}}'", value),
            )
        })?;
        if in_char && !ch.is_ascii() {
            return Err(self.error_at(
                backslash_at,
                format!(
                    "character literal '\\u{{{:x}}}' is not ASCII (a character is one byte, u8)",
                    value
                ),
            ));
        }
        Ok(ch)
    }

    // 'a', '\n', '\x41': a single byte.
    pub(super) fn lex_char(&mut self) -> Result<TokenKind, LexError> {
        let start = self.pos;
        self.advance(); // the opening '
        let mut bytes = Vec::new();
        match self.peek() {
            None | Some(b'\n') => {
                return Err(self.error_at(start, "unterminated character literal"));
            }
            Some(b'\'') => return Err(self.error_at(start, "empty character literal")),
            Some(b'\\') => {
                self.advance();
                self.lex_escape(&mut bytes, true)?;
            }
            Some(byte) if byte.is_ascii() => {
                self.advance();
                bytes.push(byte);
            }
            Some(_) => {
                return Err(self.error_at(
                    start,
                    format!(
                        "character literal '{}' is not ASCII (a character is one byte, u8)",
                        self.char_at(self.pos)
                    ),
                ));
            }
        }
        if self.peek() != Some(b'\'') {
            return Err(self.error_at(start, "unterminated character literal (expected ')"));
        }
        self.advance();
        Ok(TokenKind::CharLiteral(bytes[0]))
    }

    fn hex_digit(&mut self) -> Result<u8, LexError> {
        if self.at_end() {
            return Err(self.error_here("expected hex digit"));
        }
        let byte = self.advance();
        match byte {
            b'0'..=b'9' => Ok(byte - b'0'),
            b'a'..=b'f' => Ok(byte - b'a' + 10),
            b'A'..=b'F' => Ok(byte - b'A' + 10),
            _ => Err(self.error_at(
                self.pos - 1,
                format!("expected hex digit, got '{}'", self.char_at(self.pos - 1)),
            )),
        }
    }

    // ---- Numbers ----

    pub(super) fn lex_number(&mut self) -> Result<TokenKind, LexError> {
        let start = self.pos;
        let radix = match (self.peek(), self.peek_at(1)) {
            (Some(b'0'), Some(b'x' | b'X')) => Some((16, "hex")),
            (Some(b'0'), Some(b'b' | b'B')) => Some((2, "binary")),
            _ => None,
        };
        if let Some((radix, radix_name)) = radix {
            self.pos += 2;
            let value = self.lex_radix_digits(radix, radix_name)?;
            return self.int_suffix(value, start, false);
        }
        self.lex_decimal_or_float(start)
    }

    // Digits of a 0x/0b literal; '_' separators are allowed.
    fn lex_radix_digits(&mut self, radix: u32, radix_name: &str) -> Result<u64, LexError> {
        if !self.peek().is_some_and(|b| (b as char).is_digit(radix)) {
            return Err(self.error_here(format!(
                "expected {} digit after '{}'",
                radix_name,
                self.text_from(self.pos - 2)
            )));
        }
        let mut value: u64 = 0;
        let mut last_underscore = false;
        while let Some(byte) = self.peek() {
            if byte == b'_' {
                last_underscore = true;
                self.pos += 1;
                continue;
            }
            let Some(digit) = (byte as char).to_digit(radix) else {
                break;
            };
            last_underscore = false;
            value = value
                .checked_mul(radix as u64)
                .and_then(|v| v.checked_add(digit as u64))
                .ok_or_else(|| self.error_here(format!("{} literal overflow", radix_name)))?;
            self.pos += 1;
        }
        self.check_trailing_underscore(last_underscore)?;
        Ok(value)
    }

    // A '_' may end the digits only when a suffix follows (`1_u8`).
    fn check_trailing_underscore(&self, last_underscore: bool) -> Result<(), LexError> {
        if last_underscore && !self.peek().is_some_and(|b| b.is_ascii_alphabetic()) {
            return Err(self.error_at(self.pos - 1, "trailing underscore in literal"));
        }
        Ok(())
    }

    // An identifier glued to a literal: its type suffix, and where it starts.
    fn read_suffix(&mut self) -> Option<(&'a str, usize)> {
        if !self.peek().is_some_and(is_ident_byte) {
            return None;
        }
        let start = self.pos;
        while self.peek().is_some_and(is_ident_byte) {
            self.pos += 1;
        }
        Some((self.text_from(start), start))
    }

    // An integer literal and its optional suffix. A decimal literal may take
    // a float suffix (`1f32`).
    fn int_suffix(
        &mut self,
        value: u64,
        start: usize,
        decimal: bool,
    ) -> Result<TokenKind, LexError> {
        let Some((suffix, suffix_at)) = self.read_suffix() else {
            return Ok(TokenKind::IntLiteral(value));
        };
        match NumSuffix::from_name(suffix) {
            Some(s) if s.is_float() && decimal => {
                Ok(TokenKind::SuffixedFloat((value as f64).into(), s))
            }
            Some(s) if !s.is_float() => Ok(TokenKind::SuffixedInt(value, s)),
            _ => Err(self.error_at(
                suffix_at,
                format!(
                    "invalid suffix '{}' on integer literal {}",
                    suffix,
                    std::str::from_utf8(&self.src[start..suffix_at]).expect("digits are ASCII")
                ),
            )),
        }
    }

    fn lex_decimal_or_float(&mut self, start: usize) -> Result<TokenKind, LexError> {
        let int_digits = self.read_decimal_digits()?;
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
            let value: u64 = int_digits
                .parse()
                .map_err(|_| self.error_here("integer overflow"))?;
            return self.int_suffix(value, start, !self.after_dot);
        }
        let float_text = self.read_float_rest(int_digits, has_fraction)?;
        let value: f64 = float_text
            .parse()
            .map_err(|_| self.error_here("invalid float"))?;
        match self.read_suffix() {
            None => Ok(TokenKind::FloatLiteral(value.into())),
            Some((suffix, suffix_at)) => match NumSuffix::from_name(suffix) {
                Some(s) if s.is_float() => Ok(TokenKind::SuffixedFloat(value.into(), s)),
                _ => Err(self.error_at(
                    suffix_at,
                    format!(
                        "invalid suffix '{}' on float literal {}",
                        suffix, float_text
                    ),
                )),
            },
        }
    }

    // The fraction and exponent of a float after its integer digits, as
    // text for `str::parse`.
    fn read_float_rest(
        &mut self,
        int_digits: String,
        has_fraction: bool,
    ) -> Result<String, LexError> {
        let mut text = int_digits;
        if has_fraction {
            self.pos += 1; // the '.'
            text.push('.');
            text.push_str(&self.read_decimal_digits()?);
        }
        if matches!(self.peek(), Some(b'e' | b'E')) {
            self.pos += 1;
            text.push('e');
            if matches!(self.peek(), Some(b'+' | b'-')) {
                text.push(self.advance() as char);
            }
            if !self.peek().is_some_and(|b| b.is_ascii_digit()) {
                return Err(self.error_here("expected digit in exponent"));
            }
            text.push_str(&self.read_decimal_digits()?);
        }
        Ok(text)
    }

    // Decimal digits with '_' separators removed.
    fn read_decimal_digits(&mut self) -> Result<String, LexError> {
        if !self.peek().is_some_and(|b| b.is_ascii_digit()) {
            return Err(self.error_here("expected digit"));
        }
        let mut digits = String::new();
        let mut last_underscore = false;
        while let Some(byte) = self.peek() {
            if byte == b'_' {
                last_underscore = true;
                self.pos += 1;
                continue;
            }
            if !byte.is_ascii_digit() {
                break;
            }
            last_underscore = false;
            digits.push(byte as char);
            self.pos += 1;
        }
        self.check_trailing_underscore(last_underscore)?;
        Ok(digits)
    }
}
