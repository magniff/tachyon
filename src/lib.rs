pub mod backend;
pub mod driver;
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

pub use backend::{Artifact, OptLevel, Options, Target};

// Lexes, parses and type checks a program.
fn analyze(
    program_text: &str,
) -> Result<(parser::Program, typechecker::CheckedProgram), Vec<CompilerError>> {
    let tokens = lexer::Lexer::new(program_text)
        .tokenize()
        .map_err(|error| vec![error.into()])?;
    let ast = parser::parse(tokens)
        .map_err(|errors| errors.into_iter().map(Into::into).collect::<Vec<_>>())?;
    let checked = typechecker::typecheck(&ast).map_err(|typechecker_errors| {
        typechecker_errors
            .into_iter()
            .map(|error| error.into())
            .collect::<Vec<_>>()
    })?;
    Ok((ast, checked))
}

// Reports the program's errors without generating code.
pub fn check(program_text: &str) -> Result<(), Vec<CompilerError>> {
    analyze(program_text).map(|_| ())
}

fn front_end(program_text: &str) -> Result<lowering::IrProgram, Vec<CompilerError>> {
    let (ast, checked) = analyze(program_text)?;
    Ok(lowering::lower(&ast, &checked))
}

pub fn compile(program_text: &str, options: &Options) -> Result<Artifact, Vec<CompilerError>> {
    let program = front_end(program_text)?;
    Ok(backend::backend()
        .compile(&program, options)
        .map_err(Into::<CompilerError>::into)?)
}

// Cranelift IR and machine code of every function, for inspection.
pub fn compile_to_clif(
    program_text: &str,
    options: &Options,
) -> Result<String, Vec<CompilerError>> {
    let program = front_end(program_text)?;
    Ok(backend::cranelift::clif_text(&program, options).map_err(Into::<CompilerError>::into)?)
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
        if let Some(help) = &error.help {
            out.push_str(&format!("  = help: {}\n", help));
        }
        out.push('\n');
    }
    out
}
