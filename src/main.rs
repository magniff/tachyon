use clap::Parser;
use tracing_subscriber::EnvFilter;

#[derive(Clone, Copy, clap::ValueEnum)]
enum TargetArg {
    #[value(name = "linux-x86_64")]
    LinuxX86_64,
    #[value(name = "macos-x86_64")]
    MacosX86_64,
}

impl From<TargetArg> for tachyon::Target {
    fn from(value: TargetArg) -> Self {
        match value {
            TargetArg::LinuxX86_64 => tachyon::Target::LinuxX86_64,
            TargetArg::MacosX86_64 => tachyon::Target::MacosX86_64,
        }
    }
}

#[derive(clap::Parser)]
struct Arguments {
    #[arg(long, short)]
    input: std::path::PathBuf,

    #[arg(long, short)]
    output: std::path::PathBuf,

    /// Defaults to the host OS (always x86-64; Apple Silicon runs it under Rosetta).
    #[arg(long, value_enum)]
    target: Option<TargetArg>,
}

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .with_target(true)
        .with_file(true)
        .compact()
        .init();

    let arguments = Arguments::parse();
    let program_text = std::fs::read_to_string(&arguments.input).expect("read input");
    let target = arguments
        .target
        .map(Into::into)
        .unwrap_or_else(tachyon::Target::host);

    match tachyon::compile_program_for(&program_text, target) {
        Err(errors) => {
            tracing::error!(
                "{errors}",
                errors = tachyon::format_errors(&errors, &program_text)
            );
            std::process::exit(1);
        }
        Ok(assembly) => {
            std::fs::write(&arguments.output, assembly).expect("write output");
        }
    }
}
