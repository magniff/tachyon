// An interpreter for a small statement language over 64-bit integers.
// The first line of the program picks the mode: `#!dump` prints the
// syntax tree, anything else runs the program.

mod ast;
mod eval;
mod lexer;
mod parser;

use std::io::{self, Read, Write};

use ast::{dump, push_int};
use eval::run;
use lexer::tokenize;
use parser::parse;

// Whether the first line of `src` is `#!dump` (a `\r` before its end
// allowed).
fn is_dump(src: &[u8]) -> bool {
    let mut end = 0;
    while end < src.len() && src[end] != b'\n' {
        end += 1;
    }
    let mut line = &src[0..end];
    if !line.is_empty() && line[line.len() - 1] == b'\r' {
        line = &line[0..line.len() - 1];
    }
    line == b"#!dump"
}

fn syntax_error(line: i64, out: &mut Vec<u8>) {
    out.extend_from_slice(b"syntax error at line ");
    push_int(out, line);
    out.push(b'\n');
}

fn main() {
    let mut src: Vec<u8> = Vec::new();
    io::stdin().read_to_end(&mut src).unwrap();
    let mut out: Vec<u8> = Vec::new();
    match tokenize(&src) {
        Err(line) => syntax_error(line, &mut out),
        Ok(lexed) => match parse(lexed) {
            Err(line) => syntax_error(line, &mut out),
            Ok(t) => {
                if is_dump(&src) {
                    dump(&t, &mut out);
                } else {
                    run(&t, &mut out);
                }
            }
        },
    }
    io::stdout().write_all(&out).unwrap();
}
