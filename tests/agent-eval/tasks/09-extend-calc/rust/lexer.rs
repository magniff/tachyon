// Splits a line into tokens.

#[derive(Clone, Copy, PartialEq)]
pub enum TokenKind {
    Num,
    Plus,
    Minus,
    Star,
    Slash,
    LParen,
    RParen,
    // After the last token of every line.
    End,
}

#[derive(Clone, Copy)]
pub struct Token {
    pub kind: TokenKind,
    // The number's value, for Num; 0 for the others.
    pub value: i64,
}

fn is_digit(c: u8) -> bool {
    c >= b'0' && c <= b'9'
}

fn is_space(c: u8) -> bool {
    c == b' ' || c == b'\t' || c == b'\r'
}

// One token of a single character, if `c` starts one.
fn single(c: u8) -> Option<TokenKind> {
    match c {
        b'+' => Some(TokenKind::Plus),
        b'-' => Some(TokenKind::Minus),
        b'*' => Some(TokenKind::Star),
        b'/' => Some(TokenKind::Slash),
        b'(' => Some(TokenKind::LParen),
        b')' => Some(TokenKind::RParen),
        _ => None,
    }
}

// The tokens of `line`, ending with End; None when a character starts no
// token. `#` starts a comment that runs to the end of the line.
pub fn tokenize(line: &[u8]) -> Option<Vec<Token>> {
    let mut tokens = Vec::new();
    let mut i = 0;
    while i < line.len() {
        let c = line[i];
        if is_space(c) {
            i += 1;
        } else if c == b'#' {
            break;
        } else if is_digit(c) {
            let mut value: i64 = 0;
            while i < line.len() && is_digit(line[i]) {
                value = value * 10 + (line[i] - b'0') as i64;
                i += 1;
            }
            tokens.push(Token { kind: TokenKind::Num, value: value });
        } else {
            match single(c) {
                Some(kind) => tokens.push(Token { kind: kind, value: 0 }),
                None => return None,
            }
            i += 1;
        }
    }
    tokens.push(Token { kind: TokenKind::End, value: 0 });
    Some(tokens)
}
