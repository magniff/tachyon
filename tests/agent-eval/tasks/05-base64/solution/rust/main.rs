// Base64: `enc TEXT` and `dec DATA` requests, one per line.
use std::io::{self, Read, Write};

static ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// The value of an alphabet character, or -1.
fn sextet(ch: u8) -> i64 {
    if ch >= b'A' && ch <= b'Z' {
        (ch - b'A') as i64
    } else if ch >= b'a' && ch <= b'z' {
        (ch - b'a') as i64 + 26
    } else if ch >= b'0' && ch <= b'9' {
        (ch - b'0') as i64 + 52
    } else if ch == b'+' {
        62
    } else if ch == b'/' {
        63
    } else {
        -1
    }
}

fn encode(data: &[u8], out: &mut Vec<u8>) {
    let mut i = 0;
    while i < data.len() {
        let rest = data.len() - i;
        let b0 = data[i] as usize;
        let b1 = if rest > 1 { data[i + 1] as usize } else { 0 };
        let b2 = if rest > 2 { data[i + 2] as usize } else { 0 };
        let group = (b0 << 16) | (b1 << 8) | b2;
        out.push(ALPHABET[(group >> 18) & 63]);
        out.push(ALPHABET[(group >> 12) & 63]);
        out.push(if rest > 1 {
            ALPHABET[(group >> 6) & 63]
        } else {
            b'='
        });
        out.push(if rest > 2 { ALPHABET[group & 63] } else { b'=' });
        i += 3;
    }
}

// Appends the decoded bytes to out; false when the data is not valid base64.
fn decode(data: &[u8], out: &mut Vec<u8>) -> bool {
    if data.len() % 4 != 0 {
        return false;
    }
    let mut pad = 0;
    if data.len() >= 1 && data[data.len() - 1] == b'=' {
        pad = 1;
        if data[data.len() - 2] == b'=' {
            pad = 2;
        }
    }
    let mut i = 0;
    while i < data.len() {
        let last = i + 4 == data.len();
        let mut group: i64 = 0;
        for k in 0..4 {
            let mut v = 0;
            if !(last && k >= 4 - pad) {
                v = sextet(data[i + k]);
                if v < 0 {
                    return false;
                }
            }
            group = (group << 6) | v;
        }
        out.push((group >> 16) as u8);
        if last && pad == 2 {
            if group & 0xffff != 0 {
                return false;
            }
        } else if last && pad == 1 {
            out.push((group >> 8) as u8);
            if group & 0xff != 0 {
                return false;
            }
        } else {
            out.push((group >> 8) as u8);
            out.push(group as u8);
        }
        i += 4;
    }
    true
}

fn push_decoded(bytes: &[u8], out: &mut Vec<u8>) {
    let mut printable = true;
    for &b in bytes {
        if b < 32 || b > 126 {
            printable = false;
        }
    }
    if printable {
        out.extend_from_slice(bytes);
        return;
    }
    let digits = b"0123456789abcdef";
    out.extend_from_slice(b"hex:");
    for &b in bytes {
        out.push(digits[(b >> 4) as usize]);
        out.push(digits[(b & 15) as usize]);
    }
}

fn handle(line: &[u8], out: &mut Vec<u8>, scratch: &mut Vec<u8>) {
    let (cmd, arg): (&[u8], &[u8]) = if line.len() >= 4 && line[3] == b' ' {
        (&line[..3], &line[4..])
    } else {
        (line, b"")
    };
    if cmd == b"enc" {
        encode(arg, out);
    } else if cmd == b"dec" {
        scratch.clear();
        if decode(arg, scratch) {
            push_decoded(scratch, out);
        } else {
            out.extend_from_slice(b"invalid");
        }
    } else {
        out.extend_from_slice(b"invalid");
    }
    out.push(b'\n');
}

fn main() {
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).unwrap();
    let mut out = Vec::new();
    let mut scratch = Vec::new();
    let mut start = 0;
    for i in 0..input.len() + 1 {
        if i == input.len() || input[i] == b'\n' {
            if i == input.len() && start == i {
                break; // after the final newline
            }
            handle(&input[start..i], &mut out, &mut scratch);
            start = i + 1;
        }
    }
    io::stdout().write_all(&out).unwrap();
}
