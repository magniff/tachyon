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
