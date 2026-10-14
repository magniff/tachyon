// RPN calculator: one expression per line, wrapping i64 arithmetic.
use std::io::{self, Read, Write};

#[derive(Clone, Copy)]
enum Token {
    Num(i64),
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Dup,
    Swap,
    Bad,
}

fn parse_number(tok: &[u8]) -> Token {
    let mut i = 0;
    let negative = tok[0] == b'-';
    if negative {
        i = 1;
    }
    if i == tok.len() {
        return Token::Bad;
    }
    let mut n: i64 = 0;
    while i < tok.len() {
        let ch = tok[i];
        if ch < b'0' || ch > b'9' {
            return Token::Bad;
        }
        n = n.wrapping_mul(10).wrapping_add((ch - b'0') as i64);
        i += 1;
    }
    if negative {
        n = n.wrapping_neg();
    }
    Token::Num(n)
}

fn parse_token(tok: &[u8]) -> Token {
    if tok == b"+" {
        Token::Add
    } else if tok == b"-" {
        Token::Sub
    } else if tok == b"*" {
        Token::Mul
    } else if tok == b"/" {
        Token::Div
    } else if tok == b"%" {
        Token::Rem
    } else if tok == b"dup" {
        Token::Dup
    } else if tok == b"swap" {
        Token::Swap
    } else {
        parse_number(tok)
    }
}

// Applies one token to the stack; false on an error.
fn apply(tok: Token, stack: &mut Vec<i64>) -> bool {
    match tok {
        Token::Num(n) => {
            stack.push(n);
            true
        }
        Token::Dup => {
            if stack.is_empty() {
                return false;
            }
            let top = stack[stack.len() - 1];
            stack.push(top);
            true
        }
        Token::Swap => {
            let n = stack.len();
            if n < 2 {
                return false;
            }
            stack.swap(n - 1, n - 2);
            true
        }
        Token::Bad => false,
        _ => {
            if stack.len() < 2 {
                return false;
            }
            let b = stack.pop().unwrap();
            let a = stack.pop().unwrap();
            let r = match tok {
                Token::Add => a.wrapping_add(b),
                Token::Sub => a.wrapping_sub(b),
                Token::Mul => a.wrapping_mul(b),
                Token::Div => {
                    if b == 0 {
                        return false;
                    }
                    a.wrapping_div(b)
                }
                _ => {
                    if b == 0 {
                        return false;
                    }
                    a.wrapping_rem(b)
                }
            };
            stack.push(r);
            true
        }
    }
}

fn eval_line(line: &[u8], stack: &mut Vec<i64>) -> Option<i64> {
    stack.clear();
    let mut i = 0;
    while i < line.len() {
        if line[i] == b' ' {
            i += 1;
            continue;
        }
        let start = i;
        while i < line.len() && line[i] != b' ' {
            i += 1;
        }
        if !apply(parse_token(&line[start..i]), stack) {
            return None;
        }
    }
    if stack.len() != 1 {
        return None;
    }
    Some(stack[0])
}

fn main() {
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).unwrap();
    let mut stack: Vec<i64> = Vec::new();
    let mut out = Vec::new();
    let mut start = 0;
    for i in 0..input.len() + 1 {
        if i == input.len() || input[i] == b'\n' {
            if i == input.len() && start == i {
                break; // after the final newline
            }
            match eval_line(&input[start..i], &mut stack) {
                Some(v) => out.extend_from_slice(v.to_string().as_bytes()),
                None => out.extend_from_slice(b"error"),
            }
            out.push(b'\n');
            start = i + 1;
        }
    }
    io::stdout().write_all(&out).unwrap();
}
