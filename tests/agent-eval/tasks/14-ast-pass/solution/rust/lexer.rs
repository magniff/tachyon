// Splits the program text into tokens. Names are interned: an Ident
// token's value is the index of its name in `names`.

use std::collections::HashMap;

#[derive(Clone, Copy, PartialEq)]
pub enum TokenKind {
    Num,
    Ident,
    Let,
    Print,
    If,
    Else,
    While,
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    Bang,
    Lt,
    Le,
    Gt,
    Ge,
    EqEq,
    Ne,
    AndAnd,
    OrOr,
    Assign,
    LParen,
    RParen,
    LBrace,
    RBrace,
    Semi,
    Comma,
    // After the last token; its line is the last token's line.
    End,
}

#[derive(Clone, Copy)]
pub struct Token {
    pub kind: TokenKind,
    // A number's value, a name's index in `names`; 0 for the others.
    pub value: i64,
    pub line: i64,
}

pub struct Lexed {
    pub tokens: Vec<Token>,
    pub names: Vec<Vec<u8>>,
}

fn is_digit(c: u8) -> bool {
    c >= b'0' && c <= b'9'
}

fn is_alpha(c: u8) -> bool {
    (c >= b'a' && c <= b'z') || (c >= b'A' && c <= b'Z') || c == b'_'
}

fn is_space(c: u8) -> bool {
    c == b' ' || c == b'\t' || c == b'\r' || c == b'\n'
}

// The keyword spelled by `word`, if it is one.
fn keyword(word: &[u8]) -> Option<TokenKind> {
    if word == b"let" {
        Some(TokenKind::Let)
    } else if word == b"print" {
        Some(TokenKind::Print)
    } else if word == b"if" {
        Some(TokenKind::If)
    } else if word == b"else" {
        Some(TokenKind::Else)
    } else if word == b"while" {
        Some(TokenKind::While)
    } else {
        None
    }
}

// A token of one character, if `c` starts one that cannot be longer.
fn single(c: u8) -> Option<TokenKind> {
    match c {
        b'+' => Some(TokenKind::Plus),
        b'-' => Some(TokenKind::Minus),
        b'*' => Some(TokenKind::Star),
        b'/' => Some(TokenKind::Slash),
        b'%' => Some(TokenKind::Percent),
        b'(' => Some(TokenKind::LParen),
        b')' => Some(TokenKind::RParen),
        b'{' => Some(TokenKind::LBrace),
        b'}' => Some(TokenKind::RBrace),
        b';' => Some(TokenKind::Semi),
        b',' => Some(TokenKind::Comma),
        _ => None,
    }
}

// A token of one or two characters: `first` alone, or `second` when the
// next character is `next`.
fn one_or_two(src: &[u8], i: i64, next: u8, first: TokenKind, second: TokenKind) -> (TokenKind, i64) {
    if i + 1 < src.len() as i64 && src[(i + 1) as usize] == next {
        (second, 2)
    } else {
        (first, 1)
    }
}

// The index of `word` in `names`, added if it is new; `ids` maps the
// names seen so far to their indices.
fn intern(ids: &mut HashMap<Vec<u8>, i64>, names: &mut Vec<Vec<u8>>, word: &[u8]) -> i64 {
    match ids.get(word) {
        Some(id) => *id,
        None => {
            let id = names.len() as i64;
            ids.insert(word.to_vec(), id);
            names.push(word.to_vec());
            id
        }
    }
}

// The tokens of the program, ending with End, or the line of the first
// character that starts no token. `#` starts a comment to the end of the
// line.
pub fn tokenize(src: &[u8]) -> Result<Lexed, i64> {
    let mut tokens: Vec<Token> = Vec::new();
    let mut ids: HashMap<Vec<u8>, i64> = HashMap::new();
    let mut names: Vec<Vec<u8>> = Vec::new();
    let n = src.len() as i64;
    let mut i: i64 = 0;
    let mut line: i64 = 1;
    while i < n {
        let c = src[i as usize];
        if c == b'\n' {
            line += 1;
            i += 1;
        } else if is_space(c) {
            i += 1;
        } else if c == b'#' {
            while i < n && src[i as usize] != b'\n' {
                i += 1;
            }
        } else if is_digit(c) {
            let mut value: i64 = 0;
            while i < n && is_digit(src[i as usize]) {
                value = value.wrapping_mul(10).wrapping_add((src[i as usize] - b'0') as i64);
                i += 1;
            }
            tokens.push(Token { kind: TokenKind::Num, value: value, line: line });
        } else if is_alpha(c) {
            let start = i;
            while i < n && (is_alpha(src[i as usize]) || is_digit(src[i as usize])) {
                i += 1;
            }
            let word = &src[start as usize..i as usize];
            match keyword(word) {
                Some(kind) => tokens.push(Token { kind: kind, value: 0, line: line }),
                None => {
                    let id = intern(&mut ids, &mut names, word);
                    tokens.push(Token { kind: TokenKind::Ident, value: id, line: line });
                }
            }
        } else {
            let (kind, len) = match c {
                b'<' => one_or_two(src, i, b'=', TokenKind::Lt, TokenKind::Le),
                b'>' => one_or_two(src, i, b'=', TokenKind::Gt, TokenKind::Ge),
                b'=' => one_or_two(src, i, b'=', TokenKind::Assign, TokenKind::EqEq),
                b'!' => one_or_two(src, i, b'=', TokenKind::Bang, TokenKind::Ne),
                b'&' => one_or_two(src, i, b'&', TokenKind::End, TokenKind::AndAnd),
                b'|' => one_or_two(src, i, b'|', TokenKind::End, TokenKind::OrOr),
                _ => match single(c) {
                    Some(kind) => (kind, 1),
                    None => (TokenKind::End, 1),
                },
            };
            if kind == TokenKind::End {
                return Err(line);
            }
            tokens.push(Token { kind: kind, value: 0, line: line });
            i += len;
        }
    }
    let last_line = if tokens.is_empty() { 1 } else { tokens[tokens.len() - 1].line };
    tokens.push(Token { kind: TokenKind::End, value: 0, line: last_line });
    Ok(Lexed { tokens: tokens, names: names })
}
