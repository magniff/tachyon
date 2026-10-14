// Command lines as words and numbers; numbers and money as text.

// The words of `line`, separated by runs of spaces.
pub fn words(line: &str) -> Vec<&str> {
    let b = line.as_bytes();
    let mut v = Vec::new();
    let mut i = 0;
    while i < b.len() {
        while i < b.len() && b[i] == b' ' {
            i += 1;
        }
        let start = i;
        while i < b.len() && b[i] != b' ' {
            i += 1;
        }
        if i > start {
            v.push(&line[start..i]);
        }
    }
    v
}

// What follows the first `n` words of `line`, from the next word on.
pub fn rest_after(line: &str, n: usize) -> &str {
    let b = line.as_bytes();
    let mut i = 0;
    for _ in 0..n {
        while i < b.len() && b[i] == b' ' {
            i += 1;
        }
        while i < b.len() && b[i] != b' ' {
            i += 1;
        }
    }
    while i < b.len() && b[i] == b' ' {
        i += 1;
    }
    &line[i..]
}

// A decimal number of at most 12 digits, or None.
pub fn parse_int(word: &str) -> Option<i64> {
    let b = word.as_bytes();
    if b.is_empty() || b.len() > 12 {
        return None;
    }
    let mut n: i64 = 0;
    for &ch in b {
        if ch < b'0' || ch > b'9' {
            return None;
        }
        n = n * 10 + (ch - b'0') as i64;
    }
    Some(n)
}

pub fn push_int(out: &mut String, n: i64) {
    out.push_str(&n.to_string());
}

// Appends an amount in cents as dollars: 1234 is "12.34", 5 is "0.05".
pub fn push_money(out: &mut String, cents: i64) {
    push_int(out, cents / 100);
    out.push('.');
    let rest = cents % 100;
    if rest < 10 {
        out.push('0');
    }
    push_int(out, rest);
}
