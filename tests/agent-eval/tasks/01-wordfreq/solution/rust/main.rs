// Word frequencies: the N most frequent words of the text on stdin.
use std::cmp::Ordering;
use std::collections::HashMap;
use std::io::{self, Read, Write};

struct Entry<'a> {
    word: &'a [u8],
    count: i64,
}

// Higher count first, then alphabetical.
fn cmp_entries(a: &Entry, b: &Entry) -> Ordering {
    if a.count != b.count {
        return b.count.cmp(&a.count);
    }
    a.word.cmp(b.word)
}

fn is_letter(ch: u8) -> bool {
    (ch >= b'a' && ch <= b'z') || (ch >= b'A' && ch <= b'Z')
}

fn to_lower(ch: u8) -> u8 {
    if ch >= b'A' && ch <= b'Z' {
        ch + 32
    } else {
        ch
    }
}

// The first line's number and the offset where the text starts.
fn parse_header(input: &[u8]) -> (i64, usize) {
    let mut n: i64 = 0;
    let mut i = 0;
    while i < input.len() && input[i] != b'\n' {
        let ch = input[i];
        if ch >= b'0' && ch <= b'9' {
            n = n * 10 + (ch - b'0') as i64;
        }
        i += 1;
    }
    (n, i)
}

fn count_words(text: &[u8]) -> HashMap<&[u8], i64> {
    let mut counts: HashMap<&[u8], i64> = HashMap::new();
    let mut start = 0;
    let mut in_word = false;
    for i in 0..text.len() + 1 {
        let letter = i < text.len() && is_letter(text[i]);
        if letter && !in_word {
            start = i;
            in_word = true;
        } else if !letter && in_word {
            let word = &text[start..i];
            *counts.entry(word).or_insert(0) += 1;
            in_word = false;
        }
    }
    counts
}

fn main() {
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).unwrap();
    let (n, header_end) = parse_header(&input);
    for i in header_end..input.len() {
        input[i] = to_lower(input[i]);
    }
    let text = &input[header_end..];
    let counts = count_words(text);
    let mut entries: Vec<Entry> = Vec::new();
    for (word, count) in &counts {
        entries.push(Entry { word, count: *count });
    }
    entries.sort_by(cmp_entries);
    let mut out = Vec::new();
    let mut i = 0;
    while i < entries.len() && (i as i64) < n {
        out.extend_from_slice(entries[i].word);
        out.push(b' ');
        out.extend_from_slice(entries[i].count.to_string().as_bytes());
        out.push(b'\n');
        i += 1;
    }
    io::stdout().write_all(&out).unwrap();
}
