// Text helpers: splitting lines into words, reading integers, writing
// numbers, and wrapping a list of words to a width.

// The words of a line: maximal runs of bytes other than space and tab.
pub fn split_words(line: &[u8]) -> Vec<&[u8]> {
    let mut words: Vec<&[u8]> = Vec::new();
    let mut i = 0;
    while i < line.len() {
        while i < line.len() && is_blank(line[i]) {
            i += 1;
        }
        let start = i;
        while i < line.len() && !is_blank(line[i]) {
            i += 1;
        }
        if i > start {
            words.push(&line[start..i]);
        }
    }
    words
}

fn is_blank(b: u8) -> bool {
    b == b' ' || b == b'\t'
}

// An integer: an optional '-', then 1 to 18 decimal digits, nothing else.
pub fn parse_int(s: &[u8]) -> Option<i64> {
    let mut i = 0;
    let mut negative = false;
    if !s.is_empty() && s[0] == b'-' {
        negative = true;
        i = 1;
    }
    let digits = s.len() as i64 - i as i64;
    if digits < 1 || digits > 18 {
        return None;
    }
    let mut v: i64 = 0;
    while i < s.len() {
        let b = s[i];
        if b < b'0' || b > b'9' {
            return None;
        }
        v = v * 10 + (b - b'0') as i64;
        i += 1;
    }
    if negative {
        v = -v;
    }
    Some(v)
}

// The decimal digits of v.
pub fn push_int(out: &mut Vec<u8>, v: i64) {
    out.extend_from_slice(v.to_string().as_bytes());
}

// v with its digits in groups of three: 1234567 is "1,234,567",
// -1234 is "-1,234".
pub fn push_grouped(out: &mut Vec<u8>, v: i64) {
    let mut digits: Vec<u8> = Vec::new();
    push_int(&mut digits, v);
    let mut start = 0;
    if !digits.is_empty() && digits[0] == b'-' {
        out.push(b'-');
        start = 1;
    }
    let n = digits.len() - start;
    for k in 0..n {
        if k > 0 && (n - k) % 3 == 0 {
            out.push(b',');
        }
        out.push(digits[start + k]);
    }
}

// Writes `words` as lines of at most `width` bytes (words joined by one
// space), each line indented by two spaces. A line takes as many words
// as fit; a word longer than the width gets a line of its own.
pub fn wrap(words: &[&[u8]], width: i64, out: &mut Vec<u8>) {
    let mut i = 0;
    while i < words.len() {
        let mut j = i;
        let mut len: i64 = 0;
        while j < words.len() {
            let need = if j == i {
                words[j].len() as i64
            } else {
                len + 1 + words[j].len() as i64
            };
            if need > width {
                break;
            }
            len = need;
            j += 1;
        }
        if j == i {
            // a word longer than the width: on a line of its own
            j = i + 1;
        }
        out.extend_from_slice(b"  ");
        for k in i..j {
            if k > i {
                out.push(b' ');
            }
            out.extend_from_slice(words[k]);
        }
        out.push(b'\n');
        i = j;
    }
}
