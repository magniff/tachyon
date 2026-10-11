// The `tachyon` command: build, run, check and clif, exit codes and
// diagnostics. Programs are built for and run on the host, so these tests
// need a C toolchain (`cc`) and a host tachyon can target.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};

fn tachyon() -> Command {
    Command::new(env!("CARGO_BIN_EXE_tachyon"))
}

fn root() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR"))
}

// A scratch directory for this test.
fn scratch(name: &str) -> PathBuf {
    let dir = PathBuf::from(env!("CARGO_TARGET_TMPDIR"))
        .join("cli")
        .join(name);
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn host_supported() -> bool {
    if tachyon::Target::native().is_none() {
        eprintln!("skipping: tachyon cannot target this host");
        return false;
    }
    true
}

fn run_with_stdin(mut command: Command, stdin: &str) -> Output {
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(stdin.as_bytes())
        .unwrap();
    child.wait_with_output().unwrap()
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

#[test]
fn build_then_execute() {
    if !host_supported() {
        return;
    }
    let dir = scratch("build");
    let exe = dir.join("hello");
    let output = tachyon()
        .arg("build")
        .arg(root().join("examples/helloworld.tach"))
        .arg("-o")
        .arg(&exe)
        .output()
        .unwrap();
    assert!(output.status.success(), "{}", stderr(&output));
    let run = Command::new(&exe).output().unwrap();
    assert_eq!(stdout(&run), "Hello from tachyon!\n");
}

#[test]
fn build_object_and_clif() {
    let dir = scratch("emit");
    let object = dir.join("hello.o");
    let output = tachyon()
        .args(["build", "--emit", "obj", "--target", "linux-x86_64"])
        .arg(root().join("examples/helloworld.tach"))
        .arg("-o")
        .arg(&object)
        .output()
        .unwrap();
    assert!(output.status.success(), "{}", stderr(&output));
    let bytes = std::fs::read(&object).unwrap();
    assert_eq!(&bytes[..4], b"\x7fELF");

    let output = tachyon()
        .args(["clif", "-O"])
        .arg(root().join("examples/helloworld.tach"))
        .output()
        .unwrap();
    assert!(output.status.success(), "{}", stderr(&output));
    assert!(stdout(&output).contains("function"));
}

#[test]
fn run_passes_arguments_and_stdin() {
    if !host_supported() {
        return;
    }
    let output = tachyon()
        .arg("run")
        .arg(root().join("examples/args.tach"))
        .args(["--", "one", "two words"])
        .output()
        .unwrap();
    assert!(output.status.success(), "{}", stderr(&output));
    let out = stdout(&output);
    assert!(out.starts_with("argc: 3\n"), "{}", out);
    assert!(out.ends_with("-- one\n-- two words\n"), "{}", out);

    let mut command = tachyon();
    command
        .args(["run", "-O"])
        .arg(root().join("examples/md5.tach"));
    let output = run_with_stdin(command, "abc");
    assert!(output.status.success(), "{}", stderr(&output));
    assert_eq!(stdout(&output).trim(), "900150983cd24fb0d6963f7d28e17f72");
}

#[test]
fn run_forwards_the_exit_code() {
    if !host_supported() {
        return;
    }
    let dir = scratch("exit");
    let source = dir.join("exit.tach");
    std::fs::write(&source, "fn main() -> i64 { 42 }\n").unwrap();
    let output = tachyon().arg("run").arg(&source).output().unwrap();
    assert_eq!(output.status.code(), Some(42));
}

#[test]
fn check_reports_diagnostics() {
    let dir = scratch("check");
    let good = dir.join("good.tach");
    std::fs::write(&good, "fn main() -> i64 { let mut x = 1; x += 1; x }\n").unwrap();
    let output = tachyon().arg("check").arg(&good).output().unwrap();
    assert!(output.status.success(), "{}", stderr(&output));
    assert!(output.stdout.is_empty() && output.stderr.is_empty());

    let bad = dir.join("bad.tach");
    std::fs::write(
        &bad,
        "fn main() -> i64 {\n    let x = 1;\n    x = 2;\n    let y = ;\n    x\n}\n",
    )
    .unwrap();
    let output = tachyon().arg("check").arg(&bad).output().unwrap();
    assert_eq!(output.status.code(), Some(1));
    let err = stderr(&output);
    // Syntax errors stop before type checking.
    assert!(
        err.contains("error[parser error]: expected expression, got ';'"),
        "{}",
        err
    );
    assert!(err.contains(" --> line 4, column 13"), "{}", err);
    // No colour when stderr is not a terminal.
    assert!(!err.contains('\x1b'), "{}", err);

    std::fs::write(
        &bad,
        "fn main() -> i64 {\n    let x = 1;\n    x = 2;\n    x\n}\n",
    )
    .unwrap();
    let output = tachyon().arg("check").arg(&bad).output().unwrap();
    assert_eq!(output.status.code(), Some(1));
    let err = stderr(&output);
    assert!(
        err.contains("cannot assign to immutable variable 'x'"),
        "{}",
        err
    );
    assert!(
        err.contains("= help: make it mutable: `let mut x`"),
        "{}",
        err
    );
}

#[test]
fn compile_errors_fail_build_and_run() {
    let dir = scratch("errors");
    let bad = dir.join("bad.tach");
    std::fs::write(&bad, "fn main() -> i64 { nope }\n").unwrap();
    for subcommand in ["build", "run"] {
        let output = tachyon()
            .arg(subcommand)
            .arg(&bad)
            .current_dir(&dir)
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(1), "{}", subcommand);
        assert!(stderr(&output).contains("undefined variable 'nope'"));
    }
    assert!(!dir.join("bad").exists());
}

#[test]
fn missing_file_and_missing_linker() {
    let output = tachyon()
        .args(["check", "does-not-exist.tach"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(stderr(&output).contains("error: cannot read does-not-exist.tach"));

    let dir = scratch("linker");
    let output = tachyon()
        .arg("build")
        .arg(root().join("examples/helloworld.tach"))
        .arg("-o")
        .arg(dir.join("hello"))
        .env("CC", "tachyon-no-such-linker")
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stderr(&output).contains("linker 'tachyon-no-such-linker' not found"),
        "{}",
        stderr(&output)
    );
}
