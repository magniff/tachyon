// Splits a line into tokens.

#[derive(Clone, Copy, PartialEq)]
pub enum TokenKind {
    Num,
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    LParen,
    RParen,
    Lt,
    Le,
    Gt,
    Ge,
    EqEq,
    Ne,
    Assign,
    Name,
    Let,
    // After the last token of every line.
    End,
}

#[derive(Clone)]
pub struct Token {
    pub kind: TokenKind,
    // The number's value, for Num; 0 for the others.
    pub value: i64,
    // The name, for Name; "" for the others.
    pub name: String,
}

fn is_digit(c: u8) -> bool {
    c >= b'0' && c <= b'9'
}

fn is_space(c: u8) -> bool {
    c == b' ' || c == b'\t' || c == b'\r'
}

fn is_name_start(c: u8) -> bool {
    (c >= b'a' && c <= b'z') || (c >= b'A' && c <= b'Z') || c == b'_'
}

// One token of a single character, if `c` starts one.
fn single(c: u8) -> Option<TokenKind> {
    match c {
        b'+' => Some(TokenKind::Plus),
        b'-' => Some(TokenKind::Minus),
        b'*' => Some(TokenKind::Star),
        b'/' => Some(TokenKind::Slash),
        b'%' => Some(TokenKind::Percent),
        b'(' => Some(TokenKind::LParen),
        b')' => Some(TokenKind::RParen),
        _ => None,
    }
}

// A token of one or two characters starting with `c` (`<`, `<=`, `=`,
// `==`, ...), and its length; `next` is the character after `c`, or 0.
fn operator(c: u8, next: u8) -> Option<(TokenKind, usize)> {
    let with_eq = next == b'=';
    match c {
        b'<' => Some(if with_eq { (TokenKind::Le, 2) } else { (TokenKind::Lt, 1) }),
        b'>' => Some(if with_eq { (TokenKind::Ge, 2) } else { (TokenKind::Gt, 1) }),
        b'=' => Some(if with_eq { (TokenKind::EqEq, 2) } else { (TokenKind::Assign, 1) }),
        b'!' => if with_eq { Some((TokenKind::Ne, 2)) } else { None },
        _ => None,
    }
}

fn token(kind: TokenKind) -> Token {
    Token { kind: kind, value: 0, name: String::new() }
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
            tokens.push(Token { kind: TokenKind::Num, value: value, name: String::new() });
        } else if is_name_start(c) {
            let start = i;
            while i < line.len() && (is_name_start(line[i]) || is_digit(line[i])) {
                i += 1;
            }
            let name = String::from_utf8_lossy(&line[start..i]).to_string();
            if name == "let" {
                tokens.push(token(TokenKind::Let));
            } else {
                tokens.push(Token { kind: TokenKind::Name, value: 0, name: name });
            }
        } else {
            let next = if i + 1 < line.len() { line[i + 1] } else { 0 };
            if let Some((kind, len)) = operator(c, next) {
                tokens.push(token(kind));
                i += len;
                continue;
            }
            match single(c) {
                Some(kind) => tokens.push(token(kind)),
                None => return None,
            }
            i += 1;
        }
    }
    tokens.push(token(TokenKind::End));
    Some(tokens)
}
