// Splits a query line into tokens.

#[derive(Clone, Copy, PartialEq)]
pub enum Kw {
    Select,
    From,
    Where,
    Group,
    By,
    Order,
    Asc,
    Desc,
    Limit,
    And,
    Or,
    Not,
    Is,
    Null,
    Count,
    Sum,
    Min,
    Max,
}

#[derive(Clone, PartialEq)]
pub enum Tok {
    Name,
    Kw(Kw),
    Int(i64),
    Str,
    Comma,
    LParen,
    RParen,
    Star,
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
    End,
}

pub struct Token {
    pub tok: Tok,
    // The token as written in the query.
    pub text: Vec<u8>,
    // A string's value, its quotes removed and '' undoubled.
    pub value: Vec<u8>,
}

const KEYWORDS: [(&[u8], Kw); 18] = [
    (b"select", Kw::Select),
    (b"from", Kw::From),
    (b"where", Kw::Where),
    (b"group", Kw::Group),
    (b"by", Kw::By),
    (b"order", Kw::Order),
    (b"asc", Kw::Asc),
    (b"desc", Kw::Desc),
    (b"limit", Kw::Limit),
    (b"and", Kw::And),
    (b"or", Kw::Or),
    (b"not", Kw::Not),
    (b"is", Kw::Is),
    (b"null", Kw::Null),
    (b"count", Kw::Count),
    (b"sum", Kw::Sum),
    (b"min", Kw::Min),
    (b"max", Kw::Max),
];

fn keyword(word: &[u8]) -> Option<Kw> {
    let mut lower = Vec::with_capacity(word.len());
    for &b in word {
        lower.push(if b >= b'A' && b <= b'Z' { b + 32 } else { b });
    }
    for (k, kw) in KEYWORDS.iter() {
        if lower.as_slice() == *k {
            return Some(*kw);
        }
    }
    None
}

fn is_alpha(b: u8) -> bool {
    (b >= b'a' && b <= b'z') || (b >= b'A' && b <= b'Z') || b == b'_'
}

fn is_digit(b: u8) -> bool {
    b >= b'0' && b <= b'9'
}

fn unexpected(text: &[u8]) -> Vec<u8> {
    let mut m = b"syntax error: unexpected ".to_vec();
    m.extend_from_slice(text);
    m
}

// The tokens of `line`, ending with an End token, or an error message.
pub fn tokenize(line: &[u8]) -> Result<Vec<Token>, Vec<u8>> {
    let mut toks = Vec::new();
    let mut i = 0;
    while i < line.len() {
        let b = line[i];
        let start = i;
        if b == b' ' || b == b'\t' {
            i += 1;
            continue;
        }
        let tok;
        let mut value = Vec::new();
        if is_alpha(b) {
            while i < line.len() && (is_alpha(line[i]) || is_digit(line[i])) {
                i += 1;
            }
            tok = match keyword(&line[start..i]) {
                Some(k) => Tok::Kw(k),
                None => Tok::Name,
            };
        } else if is_digit(b) || (b == b'-' && i + 1 < line.len() && is_digit(line[i + 1])) {
            i += 1;
            while i < line.len() && is_digit(line[i]) {
                i += 1;
            }
            tok = Tok::Int(crate::table::parse_int(&line[start..i]));
        } else if b == b'\'' {
            let mut s = Vec::new();
            i += 1;
            let mut closed = false;
            while i < line.len() {
                if line[i] == b'\'' {
                    if i + 1 < line.len() && line[i + 1] == b'\'' {
                        s.push(b'\'');
                        i += 2;
                    } else {
                        i += 1;
                        closed = true;
                        break;
                    }
                } else {
                    s.push(line[i]);
                    i += 1;
                }
            }
            if !closed {
                return Err(b"syntax error: unterminated string".to_vec());
            }
            tok = Tok::Str;
            value = s;
        } else {
            let next = if i + 1 < line.len() { line[i + 1] } else { 0 };
            i += 1;
            tok = match b {
                b',' => Tok::Comma,
                b'(' => Tok::LParen,
                b')' => Tok::RParen,
                b'*' => Tok::Star,
                b'=' => Tok::Eq,
                b'!' if next == b'=' => {
                    i += 1;
                    Tok::Ne
                }
                b'<' if next == b'=' => {
                    i += 1;
                    Tok::Le
                }
                b'<' => Tok::Lt,
                b'>' if next == b'=' => {
                    i += 1;
                    Tok::Ge
                }
                b'>' => Tok::Gt,
                _ => return Err(unexpected(&line[start..start + 1])),
            };
        }
        toks.push(Token {
            tok,
            text: line[start..i].to_vec(),
            value,
        });
    }
    toks.push(Token {
        tok: Tok::End,
        text: Vec::new(),
        value: Vec::new(),
    });
    Ok(toks)
}
