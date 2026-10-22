// The reference for vole's Unicode tables (tests/std/unicode/reference-rust.txt):
// per-code-point widths from unicode-width and Rust std's char properties
// and case mappings, over every scalar value. Format: see README.
use std::fmt::Write as _;
use unicode_width::UnicodeWidthChar;

fn w(x: Option<usize>) -> i64 {
    x.map(|v| v as i64).unwrap_or(-1)
}

fn flags(c: char) -> u32 {
    (c.is_alphabetic() as u32)
        | (c.is_numeric() as u32) << 1
        | (c.is_whitespace() as u32) << 2
        | (c.is_lowercase() as u32) << 3
        | (c.is_uppercase() as u32) << 4
        | (c.is_control() as u32) << 5
}

fn main() {
    let mut out = String::new();
    let (a, b, c) = unicode_width::UNICODE_VERSION;
    let (x, y, z) = std::char::UNICODE_VERSION;
    let rustc = option_env!("RUSTC_VERSION").unwrap_or("unknown");
    writeln!(out, "# unicode-width 0.2.2 (Unicode {a}.{b}.{c}), rustc {rustc} (char tables Unicode {x}.{y}.{z})").unwrap();
    let ranges = [(0u32, 0xD7FFu32), (0xE000, 0x10FFFF)];
    // widths
    for &(lo, hi) in &ranges {
        let mut start = lo;
        let mut cur = (-2i64, -2i64);
        for cp in lo..=hi {
            let ch = char::from_u32(cp).unwrap();
            let v = (w(ch.width()), w(ch.width_cjk()));
            if cp == lo { cur = v; continue; }
            if v != cur {
                writeln!(out, "w {:X} {:X} {} {}", start, cp - 1, cur.0, cur.1).unwrap();
                start = cp;
                cur = v;
            }
        }
        writeln!(out, "w {:X} {:X} {} {}", start, hi, cur.0, cur.1).unwrap();
    }
    // properties
    for &(lo, hi) in &ranges {
        let mut start = lo;
        let mut cur = 0;
        for cp in lo..=hi {
            let f = flags(char::from_u32(cp).unwrap());
            if cp == lo { cur = f; continue; }
            if f != cur {
                writeln!(out, "p {:X} {:X} {:X}", start, cp - 1, cur).unwrap();
                start = cp;
                cur = f;
            }
        }
        writeln!(out, "p {:X} {:X} {:X}", start, hi, cur).unwrap();
    }
    // case mappings
    for (tag, upper) in [("l", false), ("u", true)] {
        for &(lo, hi) in &ranges {
            for cp in lo..=hi {
                let ch = char::from_u32(cp).unwrap();
                let m: Vec<char> = if upper { ch.to_uppercase().collect() } else { ch.to_lowercase().collect() };
                if m.len() == 1 && m[0] == ch { continue; }
                write!(out, "{} {:X}", tag, cp).unwrap();
                for d in m { write!(out, " {:X}", d as u32).unwrap(); }
                out.push('\n');
            }
        }
    }
    print!("{out}");
}
