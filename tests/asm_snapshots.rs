// Snapshot the generated assembly (or the error report) for the programs in
// tests/run marked `// SNAPSHOT`. Runs on any host, so codegen changes show up as reviewable diffs
// even where the golden programs cannot execute.
//
// After an intended codegen change: `cargo insta review` (or
// `INSTA_UPDATE=always cargo test --test asm_snapshots`).

#[test]
fn asm_snapshots() {
    insta::glob!("run/*.tach", |path| {
        let source = std::fs::read_to_string(path).unwrap();
        // Opt-in: only programs carrying a `// SNAPSHOT` line, so the bulk
        // of the execution suite does not drag megabytes of asm along.
        if !source.lines().any(|l| l.trim() == "// SNAPSHOT") {
            return;
        }
        let output = match tachyon::compile_program(&source) {
            Ok(assembly) => assembly,
            Err(errors) => tachyon::format_errors(&errors, &source),
        };
        insta::assert_snapshot!(output);
    });
}

// The macOS target differs only in its header and symbol prefixing.
#[test]
fn asm_snapshot_macos_target() {
    let source = std::fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/examples/helloworld.tach"
    ))
    .unwrap();
    let assembly = match tachyon::compile_program_for(&source, tachyon::Target::MacosX86_64) {
        Ok(assembly) => assembly,
        Err(errors) => tachyon::format_errors(&errors, &source),
    };
    insta::assert_snapshot!(assembly);
}
