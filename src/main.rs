use clap::Parser;
use tracing_subscriber::EnvFilter;

#[derive(clap::Parser)]
struct Arguments {
    #[arg(long, short)]
    input: std::path::PathBuf,

    #[arg(long, short)]
    output: std::path::PathBuf,
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

    match tachyon::compile_program(&program_text) {
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
