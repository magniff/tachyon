// Reads a program's text: one instruction per line, labels, comments.

use crate::op::Op;

pub struct Program {
    pub ops: Vec<Op>,
    // Whether the program asked for a listing (a `.list` line).
    pub list: bool,
}

pub struct ParseError {
    // Counted from 1.
    pub line: i64,
    pub message: String,
}

// A label and the instruction it names.
struct Label {
    name: String,
    pc: i64,
}

// The line without its comment (from `;`), as words separated by spaces
// or tabs.
fn words(line: &str) -> Vec<&str> {
    let code = match line.find(';') {
        Some(i) => &line[..i],
        None => line,
    };
    let b = code.as_bytes();
    let mut v = Vec::new();
    let mut i = 0;
    while i < b.len() {
        while i < b.len() && (b[i] == b' ' || b[i] == b'\t' || b[i] == b'\r') {
            i += 1;
        }
        let start = i;
        while i < b.len() && b[i] != b' ' && b[i] != b'\t' && b[i] != b'\r' {
            i += 1;
        }
        if i > start {
            v.push(&code[start..i]);
        }
    }
    v
}

// A label is a letter or `_`, then letters, digits and `_`.
fn is_label(name: &str) -> bool {
    let b = name.as_bytes();
    if b.is_empty() || b[0].is_ascii_digit() {
        return false;
    }
    for &ch in b {
        if !(ch.is_ascii_alphanumeric() || ch == b'_') {
            return false;
        }
    }
    true
}

// A decimal integer, `-` allowed, at most 18 digits.
pub fn parse_number(word: &str) -> Option<i64> {
    let b = word.as_bytes();
    let neg = !b.is_empty() && b[0] == b'-';
    let digits = if neg { &b[1..] } else { b };
    if digits.is_empty() || digits.len() > 18 {
        return None;
    }
    let mut n: i64 = 0;
    for &ch in digits {
        if !ch.is_ascii_digit() {
            return None;
        }
        n = n * 10 + (ch - b'0') as i64;
    }
    Some(if neg { -n } else { n })
}

fn quoted(what: &str, word: &str) -> String {
    let mut s = String::from(what);
    s.push_str(" '");
    s.push_str(word);
    s.push('\'');
    s
}

// The operand of a jump: a label or an instruction number.
fn jump_target(word: &str, labels: &[Label]) -> Result<i64, String> {
    if let Some(n) = parse_number(word) {
        return Ok(n);
    }
    for l in labels {
        if l.name == word {
            return Ok(l.pc);
        }
    }
    Err(quoted("unknown label", word))
}

// One instruction from its words.
fn parse_op(w: &[&str], labels: &[Label]) -> Result<Op, String> {
    let name = w[0];
    let with_operand = name == "push" || name == "jmp" || name == "jz";
    if with_operand && w.len() < 2 {
        return Err(String::from("missing operand"));
    }
    if (with_operand && w.len() > 2) || (!with_operand && w.len() > 1) {
        return Err(String::from("extra operand"));
    }
    if name == "push" {
        return match parse_number(w[1]) {
            Some(n) => Ok(Op::Push(n)),
            None => Err(quoted("bad number", w[1])),
        };
    }
    if name == "jmp" {
        return Ok(Op::Jmp(jump_target(w[1], labels)?));
    }
    if name == "jz" {
        return Ok(Op::Jz(jump_target(w[1], labels)?));
    }
    let plain = [
        Op::Pop, Op::Dup, Op::Swap, Op::Over, Op::Add, Op::Sub, Op::Mul, Op::Div,
        Op::Mod, Op::Lt, Op::Eq, Op::Print, Op::Halt,
    ];
    for op in plain {
        if crate::op::mnemonic(op) == name {
            return Ok(op);
        }
    }
    Err(quoted("unknown instruction", name))
}

// The program in `text`, or the first problem in it. Labels are found
// first, so a jump may name a label further down.
pub fn parse(text: &str) -> Result<Program, ParseError> {
    let lines: Vec<&str> = text.split('\n').collect();
    let mut labels: Vec<Label> = Vec::new();
    let mut list = false;
    let mut count = 0;
    for (i, line) in lines.iter().enumerate() {
        let w = words(line);
        if w.is_empty() {
            continue;
        }
        let first = w[0];
        if first == ".list" {
            list = true;
        } else if first.ends_with(':') && w.len() == 1 {
            let name = &first[..first.len() - 1];
            let error = if !is_label(name) {
                Some(quoted("bad label", name))
            } else if labels.iter().any(|l| l.name == name) {
                Some(quoted("duplicate label", name))
            } else {
                None
            };
            if let Some(message) = error {
                return Err(ParseError { line: i as i64 + 1, message: message });
            }
            labels.push(Label { name: name.to_string(), pc: count });
        } else {
            count += 1;
        }
    }
    let mut ops = Vec::new();
    for (i, line) in lines.iter().enumerate() {
        let w = words(line);
        if w.is_empty() || w[0] == ".list" || (w[0].ends_with(':') && w.len() == 1) {
            continue;
        }
        match parse_op(&w, &labels) {
            Ok(op) => ops.push(op),
            Err(message) => return Err(ParseError { line: i as i64 + 1, message: message }),
        }
    }
    Ok(Program { ops: ops, list: list })
}
