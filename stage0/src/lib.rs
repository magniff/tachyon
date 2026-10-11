// The tachyon compiler: source text -> tokens -> AST -> checked AST -> IR ->
// object file.
//
//   lexer        source text to tokens
//   parser       tokens to the AST
//   typechecker  types of every expression; the declarations later passes use
//   lowering     the checked AST to the IR
//   backend      the IR to an object file (Cranelift)
//   driver       linking objects into executables
//   diagnostics  errors and their rendering

pub mod backend;
mod diagnostics;
pub mod driver;
pub mod lexer;
pub mod lowering;
pub mod parser;
pub mod typechecker;

pub use backend::{Artifact, OptLevel, Options, Target};
pub use diagnostics::{CompilerError, ErrorKind, format_errors};

// Lexes, parses and type checks a program.
fn analyze(
    source: &str,
) -> Result<(parser::Program, typechecker::CheckedProgram), Vec<CompilerError>> {
    let tokens = lexer::Lexer::new(source)
        .tokenize()
        .map_err(|error| vec![error.into()])?;
    let ast = parser::parse(tokens).map_err(into_compiler_errors)?;
    let checked = typechecker::typecheck(&ast).map_err(into_compiler_errors)?;
    Ok((ast, checked))
}

fn into_compiler_errors<E: Into<CompilerError>>(errors: Vec<E>) -> Vec<CompilerError> {
    errors.into_iter().map(Into::into).collect()
}

// Reports the program's errors without generating code.
pub fn check(source: &str) -> Result<(), Vec<CompilerError>> {
    analyze(source).map(|_| ())
}

fn front_end(source: &str) -> Result<lowering::IrProgram, Vec<CompilerError>> {
    let (ast, checked) = analyze(source)?;
    Ok(lowering::lower(&ast, &checked))
}

pub fn compile(source: &str, options: &Options) -> Result<Artifact, Vec<CompilerError>> {
    let program = front_end(source)?;
    Ok(backend::backend()
        .compile(&program, options)
        .map_err(CompilerError::from)?)
}

// Cranelift IR and machine code of every function, for inspection.
pub fn compile_to_clif(source: &str, options: &Options) -> Result<String, Vec<CompilerError>> {
    let program = front_end(source)?;
    Ok(backend::cranelift::clif_text(&program, options).map_err(CompilerError::from)?)
}

// One line per token in a stable format, for comparing the lexer with other
// implementations (`tachyon tokens`): `<start> <end> <joint> <token>`, where
// literals print as `int <value> [suffix]`, `float <bits> [suffix]`,
// `char <value>`, `str <hex bytes>`, `cstr <hex bytes>`, identifiers as
// `ident <name>`, and keywords and punctuation as their text. A lex error
// ends the dump with `error <position>`.
pub fn dump_tokens(source: &str) -> String {
    use lexer::token::TokenKind;
    use std::fmt::Write;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|byte| format!("{:02x}", byte)).collect()
    }

    let mut out = String::new();
    let tokens = match lexer::Lexer::new(source).tokenize() {
        Ok(tokens) => tokens,
        Err(error) => {
            let _ = writeln!(out, "error {}", error.position);
            return out;
        }
    };
    for token in tokens {
        let text = match &token.kind {
            TokenKind::IntLiteral(value) => format!("int {}", value),
            TokenKind::SuffixedInt(value, suffix) => format!("int {} {}", value, suffix.name()),
            TokenKind::FloatLiteral(value) => format!("float {:016x}", value.to_bits()),
            TokenKind::SuffixedFloat(value, suffix) => {
                format!("float {:016x} {}", value.to_bits(), suffix.name())
            }
            TokenKind::CharLiteral(value) => format!("char {}", value),
            TokenKind::StringLiteral(bytes) => format!("str {}", hex(bytes)),
            TokenKind::CStringLiteral(bytes) => format!("cstr {}", hex(bytes)),
            TokenKind::Ident(name) => format!("ident {}", name),
            other => other.to_string(),
        };
        let _ = writeln!(
            out,
            "{} {} {} {}",
            token.span.start, token.span.end, token.joint as u8, text
        );
    }
    out
}
