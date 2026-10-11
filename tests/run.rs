// Golden execution tests: compile each program, assemble and link it with
// nasm + gcc, run it, and compare stdout and the exit code.
//
// Programs live in tests/run/*.tach and describe their expectations in
// comments:
//
//   // ARGS: a b c         command-line arguments (whitespace separated)
//   // STDIN: text         stdin, one directive per line, joined with '\n'
//   // EXPECT: text        expected stdout, one directive per line
//   // EXIT: 3             expected exit code (default 0)
//   // ERROR: substring    compilation must fail with this message
//   // XFAIL: reason       known bug: the case is expected to fail; it is
//                          reported as XPASS (a failure) once it passes
//
// Stdout is compared after trimming trailing whitespace.
//
// The generated code is x86-64. On x86-64 Linux (nasm + gcc) and on macOS
// (nasm + clang -arch x86_64, run under Rosetta 2 on Apple Silicon) the tests
// run natively. Elsewhere set TACHYON_DOCKER=1 to run them in a linux/amd64
// container (built from tests/docker/Dockerfile). Without any of these, only
// the ERROR cases run and the rest are skipped; set TACHYON_REQUIRE_RUN=1 to
// turn the skip into a failure.

use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const DOCKER_IMAGE: &str = "tachyon-run-tests";
const RUN_TIMEOUT: Duration = Duration::from_secs(20);

#[derive(Debug, Default, Clone)]
struct Case {
    name: String,
    source: PathBuf,
    args: Vec<String>,
    stdin: Option<String>,
    expect: Vec<String>,
    exit: i32,
    error: Option<String>,
    xfail: Option<String>,
    // Only compile, assemble and link (programs that serve or animate).
    build_only: bool,
}

impl Case {
    fn from_file(path: &Path) -> Case {
        let text = std::fs::read_to_string(path).unwrap();
        let mut case = Case {
            name: path.file_stem().unwrap().to_string_lossy().into_owned(),
            source: path.to_path_buf(),
            ..Default::default()
        };
        let mut stdin: Vec<String> = Vec::new();
        for line in text.lines() {
            let Some(comment) = line.trim_start().strip_prefix("//") else {
                continue;
            };
            let comment = comment.strip_prefix(' ').unwrap_or(comment);
            let Some((key, value)) = comment.split_once(':') else {
                continue;
            };
            let value = value.strip_prefix(' ').unwrap_or(value).to_string();
            match key {
                "ARGS" => case.args = value.split_whitespace().map(String::from).collect(),
                "STDIN" => stdin.push(value),
                "EXPECT" => case.expect.push(value),
                "EXIT" => case.exit = value.trim().parse().expect("EXIT must be an integer"),
                "ERROR" => case.error = Some(value),
                "XFAIL" => case.xfail = Some(value),
                _ => {}
            }
        }
        if !stdin.is_empty() {
            case.stdin = Some(stdin.join("\n"));
        }
        case
    }
}

// Examples whose output is deterministic. They keep no test directives of
// their own, so their expectations live here.
fn example_cases(root: &Path) -> Vec<Case> {
    let example = |name: &str, file: &str, expect: &[&str]| Case {
        name: format!("example_{}", name),
        source: root.join("examples").join(file),
        expect: expect.iter().map(|s| s.to_string()).collect(),
        ..Default::default()
    };
    vec![
        example("helloworld", "helloworld.tach", &["Hello from tachyon!"]),
        example(
            "factorial",
            "factorial.tach",
            &[
                "Factorial of 1 == 1",
                "Factorial of 2 == 2",
                "Factorial of 3 == 6",
                "Factorial of 4 == 24",
                "Factorial of 5 == 120",
                "Factorial of 6 == 720",
                "Factorial of 7 == 5040",
                "Factorial of 8 == 40320",
                "Factorial of 9 == 362880",
                "Factorial of 10 == 3628800",
            ],
        ),
        example("floats", "floats.tach", &["1.732051"]),
        example(
            "variadic",
            "variadic.tach",
            &[
                "Just a humble int 1",
                "A fancy float 2.000000",
                "These two together, friendship, hey! 1 and 2.000000",
            ],
        ),
        Case {
            args: vec!["foo".into(), "bar".into()],
            ..example(
                "args",
                "args.tach",
                &["argc: 3", "-- ./prog", "-- foo", "-- bar"],
            )
        },
        Case {
            build_only: true,
            ..example("life", "life.tach", &[])
        },
        Case {
            build_only: true,
            ..example("httpd", "httpd.tach", &[])
        },
        Case {
            stdin: Some(String::new()),
            ..example(
                "md5_empty",
                "md5.tach",
                &["d41d8cd98f00b204e9800998ecf8427e"],
            )
        },
        Case {
            stdin: Some("abc".into()),
            ..example("md5_abc", "md5.tach", &["900150983cd24fb0d6963f7d28e17f72"])
        },
        Case {
            stdin: Some("The quick brown fox jumps over the lazy dog".into()),
            ..example("md5_fox", "md5.tach", &["9e107d9d372bb6826bd81d3542a419d6"])
        },
    ]
}

enum Toolchain {
    Native(tachyon::Target),
    Docker,
}

impl Toolchain {
    fn detect() -> Result<Toolchain, String> {
        if std::env::var("TACHYON_DOCKER").is_ok_and(|v| v == "1") {
            let status = Command::new("docker")
                .args([
                    "build",
                    "-q",
                    "--platform",
                    "linux/amd64",
                    "-t",
                    DOCKER_IMAGE,
                ])
                .arg(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/docker"))
                .stdout(Stdio::null())
                .status()
                .map_err(|e| format!("cannot run docker: {}", e))?;
            if !status.success() {
                return Err("docker build of tests/docker failed".into());
            }
            return Ok(Toolchain::Docker);
        }
        let (target, linker) = if cfg!(target_os = "macos") {
            (tachyon::Target::MacosX86_64, "clang")
        } else if cfg!(all(target_os = "linux", target_arch = "x86_64")) {
            (tachyon::Target::LinuxX86_64, "gcc")
        } else {
            return Err(
                "host is neither x86-64 Linux nor macOS (set TACHYON_DOCKER=1 to use docker)"
                    .into(),
            );
        };
        for tool in ["nasm", linker] {
            let found = Command::new(tool)
                .arg("--version")
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .is_ok_and(|s| s.success());
            if !found {
                return Err(format!("'{}' not found", tool));
            }
        }
        Ok(Toolchain::Native(target))
    }

    fn target(&self) -> tachyon::Target {
        match self {
            Toolchain::Native(target) => *target,
            Toolchain::Docker => tachyon::Target::LinuxX86_64,
        }
    }

    // Assemble prog.asm and link it into ./prog.
    fn build_steps(&self) -> [(&'static str, &'static [&'static str]); 2] {
        match self.target() {
            tachyon::Target::LinuxX86_64 => [
                ("nasm", &["-f", "elf64", "-o", "prog.o", "prog.asm"]),
                ("gcc", &["-no-pie", "-o", "prog", "prog.o", "-lc", "-lm"]),
            ],
            tachyon::Target::MacosX86_64 => [
                ("nasm", &["-f", "macho64", "-o", "prog.o", "prog.asm"]),
                (
                    "clang",
                    &["-arch", "x86_64", "-Wl,-w", "-o", "prog", "prog.o", "-lm"],
                ),
            ],
        }
    }

    // A command running `program` inside `dir`, either directly or in the
    // container with `dir` mounted as the working directory.
    fn command(&self, dir: &Path, program: &str, args: &[&str]) -> Command {
        match self {
            Toolchain::Native(_) => {
                // Resolve ./prog against `dir` ourselves (relative paths with
                // current_dir are platform-specific) but keep argv[0] as given.
                let mut c = match program.strip_prefix("./") {
                    Some(local) => {
                        let mut c = Command::new(dir.join(local));
                        std::os::unix::process::CommandExt::arg0(&mut c, program);
                        c
                    }
                    None => Command::new(program),
                };
                c.args(args).current_dir(dir);
                c
            }
            Toolchain::Docker => {
                let mut c = Command::new("docker");
                c.args(["run", "--rm", "-i", "--platform", "linux/amd64", "-v"])
                    .arg(format!("{}:/work", dir.display()))
                    .args(["-w", "/work", DOCKER_IMAGE, "timeout", "20", program])
                    .args(args);
                c
            }
        }
    }
}

struct Output {
    stdout: String,
    stderr: String,
    code: Option<i32>,
}

fn run_with_timeout(mut command: Command, stdin: Option<&str>) -> Result<Output, String> {
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("spawn failed: {}", e))?;
    let input = stdin.unwrap_or("").to_string();
    let mut child_stdin = child.stdin.take().unwrap();
    let writer = std::thread::spawn(move || {
        let _ = child_stdin.write_all(input.as_bytes());
    });
    let mut out = child.stdout.take().unwrap();
    let mut err = child.stderr.take().unwrap();
    let out_reader = std::thread::spawn(move || {
        let mut buffer = Vec::new();
        let _ = out.read_to_end(&mut buffer);
        buffer
    });
    let err_reader = std::thread::spawn(move || {
        let mut buffer = Vec::new();
        let _ = err.read_to_end(&mut buffer);
        buffer
    });
    let start = Instant::now();
    let status = loop {
        if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
            break status;
        }
        if start.elapsed() > RUN_TIMEOUT {
            let _ = child.kill();
            let _ = child.wait();
            return Err(format!("timed out after {:?}", RUN_TIMEOUT));
        }
        std::thread::sleep(Duration::from_millis(5));
    };
    let _ = writer.join();
    Ok(Output {
        stdout: String::from_utf8_lossy(&out_reader.join().unwrap()).into_owned(),
        stderr: String::from_utf8_lossy(&err_reader.join().unwrap()).into_owned(),
        code: status.code(),
    })
}

// Compile, turning a compiler panic (an internal compiler error) into an
// error report so one crashing case does not take down the whole suite.
fn compile(source: &str, target: tachyon::Target) -> Result<String, String> {
    let source_owned = source.to_string();
    let result =
        std::panic::catch_unwind(move || tachyon::compile_program_for(&source_owned, target));
    match result {
        Ok(Ok(assembly)) => Ok(assembly),
        Ok(Err(errors)) => Err(tachyon::format_errors(&errors, source)),
        Err(panic) => {
            let message = panic
                .downcast_ref::<String>()
                .cloned()
                .or_else(|| panic.downcast_ref::<&str>().map(|s| s.to_string()))
                .unwrap_or_default();
            Err(format!("compiler panicked: {}", message))
        }
    }
}

fn check_compile_error(case: &Case, expected: &str) -> Result<(), String> {
    let source = std::fs::read_to_string(&case.source).unwrap();
    match compile(&source, tachyon::Target::LinuxX86_64) {
        Ok(_) => Err(format!("expected compile error containing '{}'", expected)),
        Err(report) => {
            if report.contains(expected) {
                Ok(())
            } else {
                Err(format!(
                    "expected compile error containing '{}', got:\n{}",
                    expected, report
                ))
            }
        }
    }
}

fn run_case(case: &Case, toolchain: &Toolchain, work: &Path) -> Result<(), String> {
    let source = std::fs::read_to_string(&case.source).unwrap();
    let assembly = compile(&source, toolchain.target())
        .map_err(|report| format!("compile failed:\n{}", report))?;

    let dir = work.join(&case.name);
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("prog.asm"), assembly).unwrap();

    for (tool, args) in toolchain.build_steps() {
        let output = run_with_timeout(toolchain.command(&dir, tool, args), None)?;
        if output.code != Some(0) {
            return Err(format!(
                "{} failed:\n{}{}",
                tool, output.stdout, output.stderr
            ));
        }
    }

    if case.build_only {
        return Ok(());
    }

    let args: Vec<&str> = case.args.iter().map(String::as_str).collect();
    let output = run_with_timeout(
        toolchain.command(&dir, "./prog", &args),
        case.stdin.as_deref(),
    )?;
    let expected = case.expect.join("\n");
    let mut problems = Vec::new();
    if output.stdout.trim_end() != expected.trim_end() {
        problems.push(format!(
            "stdout mismatch\n--- expected\n{}\n--- actual\n{}",
            expected.trim_end(),
            output.stdout.trim_end()
        ));
    }
    if output.code != Some(case.exit) {
        problems.push(format!(
            "exit code: expected {}, got {:?}{}",
            case.exit,
            output.code,
            if output.stderr.is_empty() {
                String::new()
            } else {
                format!("\nstderr:\n{}", output.stderr)
            }
        ));
    }
    if problems.is_empty() {
        Ok(())
    } else {
        Err(problems.join("\n"))
    }
}

#[test]
fn golden_programs() {
    // Compiler panics are reported per case; keep the default hook from
    // printing a backtrace banner for each of them.
    std::panic::set_hook(Box::new(|_| {}));
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let mut files: Vec<PathBuf> = std::fs::read_dir(root.join("tests/run"))
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.extension().is_some_and(|e| e == "tach"))
        .collect();
    files.sort();
    let mut cases: Vec<Case> = files.iter().map(|p| Case::from_file(p)).collect();
    cases.extend(example_cases(&root));

    if let Ok(filter) = std::env::var("TACHYON_RUN_FILTER") {
        cases.retain(|c| c.name.contains(&filter));
    }

    let toolchain = Toolchain::detect();
    if let Err(reason) = &toolchain {
        if std::env::var("TACHYON_REQUIRE_RUN").is_ok_and(|v| v == "1") {
            panic!("cannot run golden programs: {}", reason);
        }
        eprintln!(
            "golden_programs: skipping execution ({}); only compile-error cases run",
            reason
        );
    }

    let work = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("run");
    let mut failures = Vec::new();
    let mut skipped = 0;
    // Per-category (file-name prefix) counts: pass, xfail, fail.
    let mut tally: std::collections::BTreeMap<String, [usize; 3]> = Default::default();
    for case in &cases {
        let category = case.name.split('_').next().unwrap_or("").to_string();
        let counts = tally.entry(category).or_default();
        let result = match (&case.error, &toolchain) {
            (Some(expected), _) => check_compile_error(case, expected),
            (None, Ok(toolchain)) => run_case(case, toolchain, &work),
            (None, Err(_)) => {
                skipped += 1;
                continue;
            }
        };
        match (result, &case.xfail) {
            (Ok(()), None) => {
                counts[0] += 1;
                eprintln!("  ok    {}", case.name);
            }
            (Err(_), Some(reason)) => {
                counts[1] += 1;
                eprintln!("  xfail {} ({})", case.name, reason);
            }
            (Ok(()), Some(reason)) => {
                counts[2] += 1;
                eprintln!("  XPASS {}", case.name);
                failures.push(format!(
                    "[{}] passes but is marked XFAIL ({}); remove the directive",
                    case.name, reason
                ));
            }
            (Err(message), None) => {
                counts[2] += 1;
                eprintln!("  FAIL  {}", case.name);
                failures.push(format!("[{}] {}", case.name, message));
            }
        }
    }
    eprintln!(
        "\n  {:<10} {:>5} {:>6} {:>5}",
        "category", "pass", "xfail", "fail"
    );
    let mut total = [0usize; 3];
    for (category, counts) in &tally {
        eprintln!(
            "  {:<10} {:>5} {:>6} {:>5}",
            category, counts[0], counts[1], counts[2]
        );
        for i in 0..3 {
            total[i] += counts[i];
        }
    }
    eprintln!(
        "  {:<10} {:>5} {:>6} {:>5}\n",
        "total", total[0], total[1], total[2]
    );
    if skipped > 0 {
        eprintln!("golden_programs: {} case(s) skipped", skipped);
    }
    // Restore the default hook so the summary below is printed.
    let _ = std::panic::take_hook();
    assert!(
        failures.is_empty(),
        "{} of {} golden program(s) failed:\n\n{}",
        failures.len(),
        cases.len(),
        failures.join("\n\n")
    );
}
