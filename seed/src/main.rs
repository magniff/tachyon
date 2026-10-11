// The `tachyon` command: build, run and check tachyon programs.
//
//   tachyon build <file> [-o out] [-O] [--target T] [--emit exe|obj|clif]
//   tachyon run   <file> [-O] [--target T] [-- args...]
//   tachyon check <file>
//   tachyon clif  <file> [-O] [--target T] [-o out]
//
// Exit codes: 0 on success, 1 for errors in the program (or a failed link),
// 101 for an internal compiler error; `run` exits with the program's code.

use std::io::{IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use clap::{Args, Parser, Subcommand, ValueEnum};
use tachyon::driver::{self, BuildError};
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(
    name = "tachyon",
    version = "seed",
    about = "The tachyon compiler (the seed: the Rust implementation)"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Compile a program into an executable (or an object file, or CLIF).
    Build {
        #[command(flatten)]
        compile: CompileArgs,
        /// Output path (default: the file name without extension, plus the
        /// extension of the emitted kind).
        #[arg(short, long)]
        output: Option<PathBuf>,
        /// What to produce.
        #[arg(long, value_enum, default_value = "exe")]
        emit: Emit,
    },
    /// Build a program in a temporary directory and run it.
    Run {
        #[command(flatten)]
        compile: CompileArgs,
        /// Arguments passed to the program (after `--`).
        #[arg(last = true)]
        args: Vec<String>,
    },
    /// Check a program for errors without generating code.
    Check {
        /// The source file.
        file: PathBuf,
    },
    /// Print the Cranelift IR and machine code of a program.
    Clif {
        #[command(flatten)]
        compile: CompileArgs,
        /// Write to this file instead of stdout.
        #[arg(short, long)]
        output: Option<PathBuf>,
    },
    /// Print the tokens of a file, one per line (for testing other lexers).
    #[command(hide = true)]
    Tokens {
        /// The source file.
        file: PathBuf,
    },
}

#[derive(Args)]
struct CompileArgs {
    /// The source file.
    file: PathBuf,
    /// Optimize.
    #[arg(short = 'O')]
    optimize: bool,
    /// The platform to generate code for (default: the host).
    #[arg(long, value_enum)]
    target: Option<TargetArg>,
}

#[derive(Clone, Copy, PartialEq, ValueEnum)]
enum Emit {
    /// An executable.
    Exe,
    /// An object file.
    Obj,
    /// Cranelift IR and machine code, as text.
    Clif,
}

#[derive(Clone, Copy, ValueEnum)]
enum TargetArg {
    #[value(name = "linux-x86_64")]
    LinuxX86_64,
    #[value(name = "macos-x86_64")]
    MacosX86_64,
    #[value(name = "macos-aarch64")]
    MacosAarch64,
}

impl From<TargetArg> for tachyon::Target {
    fn from(value: TargetArg) -> Self {
        match value {
            TargetArg::LinuxX86_64 => tachyon::Target::LinuxX86_64,
            TargetArg::MacosX86_64 => tachyon::Target::MacosX86_64,
            TargetArg::MacosAarch64 => tachyon::Target::MacosAarch64,
        }
    }
}

impl CompileArgs {
    fn options(&self) -> tachyon::Options {
        tachyon::Options {
            target: self
                .target
                .map(Into::into)
                .unwrap_or_else(tachyon::Target::host),
            opt_level: if self.optimize {
                tachyon::OptLevel::Speed
            } else {
                tachyon::OptLevel::None
            },
        }
    }
}

// How the command failed.
enum Failure {
    // Already reported; exit with this code.
    Exit(u8),
    // A message for stderr; exit 1.
    Message(String),
}

impl From<BuildError> for Failure {
    fn from(error: BuildError) -> Self {
        match error {
            BuildError::Compile(_) => unreachable!("compile errors are reported by the caller"),
            BuildError::Link(message) | BuildError::Io(message) => Failure::Message(message),
        }
    }
}

const ICE_EXIT: u8 = 101;

fn colors() -> bool {
    std::io::stderr().is_terminal() && std::env::var_os("NO_COLOR").is_none()
}

// Diagnostics as produced by `format_errors`, coloured for a terminal.
fn print_diagnostics(errors: &[tachyon::CompilerError], source: &str) {
    let report = tachyon::format_errors(errors, source);
    let mut stderr = std::io::stderr().lock();
    if !colors() {
        let _ = stderr.write_all(report.as_bytes());
        return;
    }
    for line in report.lines() {
        let colored = if line.starts_with("error") {
            format!("\x1b[1;31m{}\x1b[0m", line)
        } else if line.starts_with(" -->") || line.starts_with("  |") {
            format!("\x1b[1;34m{}\x1b[0m", line)
        } else if line.starts_with("  = help") {
            format!("\x1b[1;36m{}\x1b[0m", line)
        } else {
            line.to_string()
        };
        let _ = writeln!(stderr, "{}", colored);
    }
}

fn print_error(message: &str) {
    if colors() {
        eprintln!("\x1b[1;31merror\x1b[0m: {}", message);
    } else {
        eprintln!("error: {}", message);
    }
}

fn read_source(path: &Path) -> Result<String, Failure> {
    std::fs::read_to_string(path)
        .map_err(|e| Failure::Message(format!("cannot read {}: {}", path.display(), e)))
}

// Runs a compiler entry point, turning a panic into an internal compiler
// error (exit 101) and compile errors into diagnostics (exit 1).
fn compile_step<T>(
    source: &str,
    step: impl FnOnce() -> Result<T, BuildError> + std::panic::UnwindSafe,
) -> Result<T, Failure> {
    match std::panic::catch_unwind(step) {
        Ok(Ok(value)) => Ok(value),
        Ok(Err(BuildError::Compile(errors))) => {
            print_diagnostics(&errors, source);
            Err(Failure::Exit(1))
        }
        Ok(Err(other)) => Err(other.into()),
        Err(_) => {
            print_error("internal compiler error (this is a bug in tachyon)");
            Err(Failure::Exit(ICE_EXIT))
        }
    }
}

fn default_output(file: &Path, extension: &str) -> PathBuf {
    let stem = file.file_stem().unwrap_or(file.as_os_str());
    PathBuf::from(stem).with_extension(extension)
}

fn build(compile: &CompileArgs, output: Option<PathBuf>, emit: Emit) -> Result<(), Failure> {
    let source = read_source(&compile.file)?;
    let options = compile.options();
    match emit {
        Emit::Exe => {
            let output = output.unwrap_or_else(|| default_output(&compile.file, ""));
            compile_step(&source, || {
                driver::build_executable(&source, &options, &output)
            })
        }
        Emit::Obj => {
            let output = output.unwrap_or_else(|| default_output(&compile.file, "o"));
            let tachyon::Artifact(bytes) = compile_step(&source, || {
                tachyon::compile(&source, &options).map_err(BuildError::Compile)
            })?;
            write_file(&output, &bytes)
        }
        Emit::Clif => {
            let output = output.unwrap_or_else(|| default_output(&compile.file, "clif"));
            let text = clif_text(&source, &options)?;
            write_file(&output, text.as_bytes())
        }
    }
}

fn clif_text(source: &str, options: &tachyon::Options) -> Result<String, Failure> {
    compile_step(source, || {
        tachyon::compile_to_clif(source, options).map_err(BuildError::Compile)
    })
}

fn clif(compile: &CompileArgs, output: Option<&Path>) -> Result<(), Failure> {
    let source = read_source(&compile.file)?;
    let text = clif_text(&source, &compile.options())?;
    match output {
        Some(path) => write_file(path, text.as_bytes()),
        None => {
            print!("{}", text);
            Ok(())
        }
    }
}

fn write_file(path: &Path, bytes: &[u8]) -> Result<(), Failure> {
    std::fs::write(path, bytes)
        .map_err(|e| Failure::Message(format!("cannot write {}: {}", path.display(), e)))
}

fn run(compile: &CompileArgs, args: &[String]) -> Result<(), Failure> {
    let source = read_source(&compile.file)?;
    let options = compile.options();
    let temp = driver::TempDir::new("tachyon-run")?;
    let exe = temp
        .path()
        .join(compile.file.file_stem().unwrap_or(compile.file.as_os_str()));
    compile_step(&source, || {
        driver::build_executable(&source, &options, &exe)
    })?;
    // stdin, stdout and stderr are inherited.
    let status = std::process::Command::new(&exe)
        .args(args)
        .status()
        .map_err(|e| Failure::Message(format!("cannot run {}: {}", exe.display(), e)))?;
    drop(temp);
    let code = match status.code() {
        Some(code) => code,
        // Killed by a signal: the shell convention.
        None => 128 + std::os::unix::process::ExitStatusExt::signal(&status).unwrap_or(0),
    };
    match code & 0xff {
        0 => Ok(()),
        code => Err(Failure::Exit(code as u8)),
    }
}

fn check(file: &Path) -> Result<(), Failure> {
    let source = read_source(file)?;
    compile_step(&source, || {
        tachyon::check(&source).map_err(BuildError::Compile)
    })
}

fn main() -> ExitCode {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .with_writer(std::io::stderr)
        .compact()
        .init();

    let cli = Cli::parse();
    let result = match &cli.command {
        Command::Build {
            compile,
            output,
            emit,
        } => build(compile, output.clone(), *emit),
        Command::Run { compile, args } => run(compile, args),
        Command::Check { file } => check(file),
        Command::Clif { compile, output } => clif(compile, output.as_deref()),
        Command::Tokens { file } => read_source(file).map(|source| {
            print!("{}", tachyon::dump_tokens(&source));
        }),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(Failure::Exit(code)) => ExitCode::from(code),
        Err(Failure::Message(message)) => {
            print_error(&message);
            ExitCode::from(1)
        }
    }
}
