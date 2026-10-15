// A small query engine: a CSV table on stdin, then queries in a subset of
// SQL, one per line; prints each query's result or one error line.

mod check;
mod exec;
mod lexer;
mod parser;
mod sort;
mod table;

use std::io::{Read, Write};

use check::plan;
use exec::run;
use lexer::tokenize;
use parser::parse;
use table::{read_table, Table};

// The input's lines, without their `\n` and one trailing `\r`.
fn split_lines(text: &[u8]) -> Vec<&[u8]> {
    let mut lines = Vec::new();
    let mut start = 0;
    for i in 0..text.len() + 1 {
        if i == text.len() || text[i] == b'\n' {
            if i == text.len() && start == i {
                break;
            }
            let mut end = i;
            if end > start && text[end - 1] == b'\r' {
                end -= 1;
            }
            lines.push(&text[start..end]);
            start = i + 1;
        }
    }
    lines
}

fn is_blank(line: &[u8]) -> bool {
    for &b in line {
        if b != b' ' && b != b'\t' {
            return false;
        }
    }
    true
}

fn run_query(line: &[u8], t: &Table, out: &mut Vec<u8>) {
    let result = match tokenize(line) {
        Err(e) => Err(e),
        Ok(toks) => match parse(&toks) {
            Err(e) => Err(e),
            Ok(q) => match plan(&q, t) {
                Err(e) => Err(e),
                Ok(p) => {
                    run(&p, t, out);
                    Ok(())
                }
            },
        },
    };
    if let Err(e) = result {
        out.extend_from_slice(b"error: ");
        out.extend_from_slice(&e);
        out.push(b'\n');
    }
}

fn main() {
    let mut input = Vec::new();
    std::io::stdin().read_to_end(&mut input).unwrap();
    let lines = split_lines(&input);
    let (t, first) = read_table(&lines);
    let mut out = Vec::new();
    for k in first..lines.len() {
        let line = lines[k];
        if is_blank(line) || line.starts_with(b"--") {
            continue;
        }
        run_query(line, &t, &mut out);
    }
    std::io::stdout().write_all(&out).unwrap();
}
