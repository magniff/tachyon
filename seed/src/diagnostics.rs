// Compiler errors from every stage, and their rendering for people:
//
// error[type error]: expected 'i32', got 'bool'
//  --> line 3, column 18
//   |
//   3 |     let x: i32 = true;
//   |                  ~~~~

use crate::{backend, lexer, parser, typechecker};

#[derive(Debug)]
pub enum ErrorKind {
    TokenizerError,
    ParserError,
    TypecheckerError,
    GeneratorError,
}

impl ErrorKind {
    fn label(&self) -> &'static str {
        match self {
            ErrorKind::TokenizerError => "tokenizer error",
            ErrorKind::ParserError => "parser error",
            ErrorKind::TypecheckerError => "type error",
            ErrorKind::GeneratorError => "codegen error",
        }
    }
}

#[derive(Debug)]
pub struct CompilerError {
    message: String,
    // Start and (if known) end byte offsets in the source.
    span: (usize, Option<usize>),
    kind: ErrorKind,
    help: Option<String>,
}

impl From<lexer::LexError> for CompilerError {
    fn from(error: lexer::LexError) -> Self {
        Self {
            message: error.message,
            span: (error.position, None),
            kind: ErrorKind::TokenizerError,
            help: None,
        }
    }
}

impl From<parser::ParserError> for CompilerError {
    fn from(error: parser::ParserError) -> Self {
        Self {
            message: error.message,
            span: (error.span.start, Some(error.span.end)),
            kind: ErrorKind::ParserError,
            help: None,
        }
    }
}

impl From<typechecker::TypecheckerError> for CompilerError {
    fn from(error: typechecker::TypecheckerError) -> Self {
        Self {
            message: error.message,
            span: (error.span.start, Some(error.span.end)),
            kind: ErrorKind::TypecheckerError,
            help: error.help,
        }
    }
}

impl From<backend::GeneratorError> for CompilerError {
    fn from(error: backend::GeneratorError) -> Self {
        Self {
            message: error.message,
            span: (0, None),
            kind: ErrorKind::GeneratorError,
            help: None,
        }
    }
}

impl From<CompilerError> for Vec<CompilerError> {
    fn from(value: CompilerError) -> Self {
        vec![value]
    }
}

// Renders every error with its location and the source line(s) it is on.
pub fn format_errors(errors: &[CompilerError], source: &str) -> String {
    errors
        .iter()
        .map(|error| format_error(error, source))
        .collect()
}

fn format_error(error: &CompilerError, source: &str) -> String {
    let (start, end) = error.span;
    let end = end.unwrap_or(start);
    let (start_line, start_col) = line_and_column(source, start);
    let (end_line, end_col) = line_and_column(source, end);

    let mut out = format!("error[{}]: {}\n", error.kind.label(), error.message);
    out += &format!(" --> line {}, column {}\n", start_line, start_col);
    if start_line == end_line {
        if let Some(line_text) = nth_line(source, start_line) {
            out += "  |\n";
            out += &format!("{:>3} | {}\n", start_line, line_text);
            let underline = underline(line_text, start_col, end_col.max(start_col + 1));
            out += &format!("  | {}\n", underline);
        }
    } else {
        out += "  |\n";
        for line in start_line..=end_line {
            if let Some(line_text) = nth_line(source, line) {
                out += &format!("{:>3} | {}\n", line, line_text);
            }
        }
        out += "  | ^--- spans multiple lines\n";
    }
    if let Some(help) = &error.help {
        out += &format!("  = help: {}\n", help);
    }
    out.push('\n');
    out
}

// The 1-based line and column (in characters) of a byte offset.
fn line_and_column(source: &str, offset: usize) -> (usize, usize) {
    let mut line = 1;
    let mut column = 1;
    for (index, ch) in source.char_indices() {
        if index >= offset {
            break;
        }
        if ch == '\n' {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    (line, column)
}

// The text of a 1-based line.
fn nth_line(source: &str, line: usize) -> Option<&str> {
    source.lines().nth(line - 1)
}

// Marks columns `start..end` of `line_text` with `~` (a single column with
// `^`), keeping tabs before them so the marks line up.
fn underline(line_text: &str, start: usize, end: usize) -> String {
    let mut result = String::new();
    for (index, ch) in line_text.chars().enumerate() {
        let column = index + 1;
        if column < start {
            result.push(if ch == '\t' { '\t' } else { ' ' });
        } else if column == start && start == end {
            result.push('^');
        } else if column >= start && column < end {
            result.push('~');
        }
    }
    if start == end {
        result.push('^');
    }
    result
}
