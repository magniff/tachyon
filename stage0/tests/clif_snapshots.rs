// Snapshot the Cranelift IR (or the error report) for the programs in
// tests/run marked `// SNAPSHOT`, so code generation changes show up as
// reviewable diffs. The target is fixed and machine code is left out, so the
// snapshots are the same on every host.
//
// After an intended codegen change: `cargo insta review` (or
// `INSTA_UPDATE=always cargo test --test clif_snapshots`).

use tachyon::{OptLevel, Options, Target};

// The CLIF of every function, without the machine code that follows each.
fn clif_only(text: &str) -> String {
    let mut out = String::new();
    let mut in_machine_code = false;
    for line in text.lines() {
        if line == "; machine code" {
            in_machine_code = true;
        } else if line.starts_with("function ") {
            in_machine_code = false;
        }
        if !in_machine_code {
            out.push_str(line);
            out.push('\n');
        }
    }
    out
}

#[test]
fn clif_snapshots() {
    let options = Options {
        target: Target::LinuxX86_64,
        opt_level: OptLevel::None,
    };
    insta::glob!("run/*.tach", |path| {
        let source = std::fs::read_to_string(path).unwrap();
        // Opt-in: only programs carrying a `// SNAPSHOT` line.
        if !source.lines().any(|l| l.trim() == "// SNAPSHOT") {
            return;
        }
        let output = match tachyon::compile_to_clif(&source, &options) {
            Ok(text) => clif_only(&text),
            Err(errors) => tachyon::format_errors(&errors, &source),
        };
        insta::assert_snapshot!(output);
    });
}
