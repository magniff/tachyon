use clap::Parser;
use tracing_subscriber::EnvFilter;

#[derive(Clone, Copy, clap::ValueEnum)]
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

#[derive(Clone, Copy, PartialEq, clap::ValueEnum)]
enum EmitArg {
    /// An object file.
    Default,
    /// Cranelift IR and machine code, as text.
    Clif,
}

#[derive(clap::Parser)]
struct Arguments {
    #[arg(long, short)]
    input: std::path::PathBuf,

    #[arg(long, short)]
    output: std::path::PathBuf,

    /// Defaults to the host.
    #[arg(long, value_enum)]
    target: Option<TargetArg>,

    /// Optimize.
    #[arg(short = 'O')]
    optimize: bool,

    #[arg(long, value_enum, default_value = "default")]
    emit: EmitArg,
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
    let options = tachyon::Options {
        target: arguments
            .target
            .map(Into::into)
            .unwrap_or_else(tachyon::Target::host),
        opt_level: if arguments.optimize {
            tachyon::OptLevel::Speed
        } else {
            tachyon::OptLevel::None
        },
    };

    let result = if arguments.emit == EmitArg::Clif {
        tachyon::compile_to_clif(&program_text, &options).map(String::into_bytes)
    } else {
        tachyon::compile(&program_text, &options).map(|tachyon::Artifact(bytes)| bytes)
    };
    match result {
        Err(errors) => {
            tracing::error!(
                "{errors}",
                errors = tachyon::format_errors(&errors, &program_text)
            );
            std::process::exit(1);
        }
        Ok(bytes) => {
            std::fs::write(&arguments.output, bytes).expect("write output");
        }
    }
}
