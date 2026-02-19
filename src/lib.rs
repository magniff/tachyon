pub mod codegen;
pub mod lexer;
pub mod lowering;
pub mod parser;
pub mod typechecker;

#[derive(Debug)]
pub enum ErrorKind {
    TokenizerError,
    ParserError,
    TypecheckerError,
    GeneratorError,
    SystemError,
}

#[derive(Debug)]
pub struct CompilerError {
    message: String,
    span: (usize, Option<usize>),
    kind: ErrorKind,
}

impl From<lexer::LexError> for CompilerError {
    fn from(error: lexer::LexError) -> Self {
        Self {
            message: error.message,
            span: (error.position, None),
            kind: ErrorKind::TokenizerError,
        }
    }
}

impl From<parser::ParserError> for CompilerError {
    fn from(error: parser::ParserError) -> Self {
        Self {
            message: error.message,
            span: (error.span.start, Some(error.span.end)),
            kind: ErrorKind::ParserError,
        }
    }
}

impl From<typechecker::TypecheckerError> for CompilerError {
    fn from(error: typechecker::TypecheckerError) -> Self {
        Self {
            message: error.message,
            span: (error.span.start, Some(error.span.end)),
            kind: ErrorKind::TypecheckerError,
        }
    }
}

impl From<codegen::GeneratorError> for CompilerError {
    fn from(error: codegen::GeneratorError) -> Self {
        Self {
            message: error.message,
            span: (0, None),
            kind: ErrorKind::GeneratorError,
        }
    }
}

impl From<CompilerError> for Vec<CompilerError> {
    fn from(value: CompilerError) -> Self {
        vec![value]
    }
}

pub fn compile_program(program_text: &str) -> Result<String, Vec<CompilerError>> {
    let tokens = lexer::Lexer::new(&program_text)
        .tokenize()
        .map_err(|error| vec![error.into()])?;
    let ast = parser::parse(&tokens).map_err(|error| vec![error.into()])?;
    let checked = typechecker::typecheck(&ast).map_err(|typechecker_errors| {
        typechecker_errors
            .into_iter()
            .map(|error| error.into())
            .collect::<Vec<_>>()
    })?;
    Ok(codegen::generate(&lowering::lower(&ast, &checked)).map_err(Into::<CompilerError>::into)?)
}

pub fn format_errors(errors: &[CompilerError], program_text: &str) -> String {
    fn offset_to_line_col(source: &str, offset: usize) -> (usize, usize) {
        let mut line = 1;
        let mut col = 1;
        let mut idx = 0;
        for ch in source.chars() {
            if idx >= offset {
                break;
            }
            if ch == '\n' {
                line += 1;
                col = 1;
            } else {
                col += 1;
            }
            idx += ch.len_utf8();
        }
        (line, col)
    }

    fn get_line(source: &str, target_line: usize) -> Option<&str> {
        source.lines().nth(target_line - 1)
    }

    fn underline_line(line_text: &str, start_col: usize, end_col: usize) -> String {
        let mut result = String::new();

        for (i, ch) in line_text.chars().enumerate() {
            let col = i + 1;

            if col < start_col {
                // Preserve whitespace alignment
                if ch == '\t' {
                    result.push('\t');
                } else {
                    result.push(' ');
                }
            } else if col == start_col && start_col == end_col {
                result.push('^');
            } else if col >= start_col && col < end_col {
                result.push('~');
            }
        }

        if start_col == end_col {
            result.push('^');
        }

        result
    }

    let mut out = String::new();
    for error in errors {
        let (start_offset, end_offset_opt) = error.span;
        let end_offset = end_offset_opt.unwrap_or(start_offset);
        let (start_line, start_col) = offset_to_line_col(program_text, start_offset);
        let (end_line, end_col) = offset_to_line_col(program_text, end_offset);
        let kind_label = match error.kind {
            ErrorKind::TokenizerError => "tokenizer error",
            ErrorKind::ParserError => "parser error",
            ErrorKind::TypecheckerError => "type error",
            ErrorKind::GeneratorError => "codegen error",
            ErrorKind::SystemError => "system error",
        };
        out.push_str(&format!("error[{}]: {}\n", kind_label, error.message));
        out.push_str(&format!(" --> line {}, column {}\n", start_line, start_col));
        if start_line == end_line {
            if let Some(line_text) = get_line(program_text, start_line) {
                out.push_str("  |\n");
                out.push_str(&format!("{:>3} | {}\n", start_line, line_text));
                let underline = underline_line(line_text, start_col, end_col.max(start_col + 1));
                out.push_str(&format!("  | {}\n", underline));
            }
        } else {
            out.push_str("  |\n");
            for line in start_line..=end_line {
                if let Some(line_text) = get_line(program_text, line) {
                    out.push_str(&format!("{:>3} | {}\n", line, line_text));
                }
            }
            out.push_str("  | ^--- spans multiple lines\n");
        }
        out.push('\n');
    }
    out
}
