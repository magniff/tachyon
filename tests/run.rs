// Golden execution tests: compile each program for every configured
// target, link it, run it, and compare stdout and the exit code.
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
//   // XFAIL(x): reason    the same, only for configurations whose name
//                          contains x (a target or the opt level, e.g.
//                          `XFAIL(macos-aarch64)` or `XFAIL(/O)`)
//
// Stdout is compared after trimming trailing whitespace.
//
// Configurations (target[/O]):
//   <native target>         object file + cc, at -O0 and -O
//   <x86-64 host target>    at -O0, when the native target is not x86-64
//                           (Rosetta 2 on Apple Silicon)
//
// Environment:
//   TACHYON_TARGET=<target>              run only this target
//   TACHYON_OPT=0|1|all                  optimization levels
//   TACHYON_DOCKER=1                     run linux-x86_64 in a container
//                                        built from tests/docker/Dockerfile
//   TACHYON_RUN_FILTER=substring         only cases whose name matches
//   TACHYON_REQUIRE_RUN=1                fail instead of skipping when a
//                                        configuration cannot run here
//
// ERROR cases exercise the front end only and run once.

use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use tachyon::{Artifact, OptLevel, Options, Target};

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
    // (scope, reason); a scope of None applies to every configuration.
    xfail: Vec<(Option<String>, String)>,
    // Only compile and link (programs that serve or animate).
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
                "XFAIL" => case.xfail.push((None, value)),
                _ => {
                    if let Some(scope) =
                        key.strip_prefix("XFAIL(").and_then(|k| k.strip_suffix(')'))
                    {
                        case.xfail.push((Some(scope.to_string()), value));
                    }
                }
            }
        }
        if !stdin.is_empty() {
            case.stdin = Some(stdin.join("\n"));
        }
        case
    }

    fn xfail_for(&self, config: &Config) -> Option<&str> {
        let name = config.name();
        self.xfail
            .iter()
            .find(|(scope, _)| scope.as_ref().is_none_or(|s| name.contains(s.as_str())))
            .map(|(_, reason)| reason.as_str())
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

#[derive(Debug, Clone, Copy)]
struct Config {
    target: Target,
    opt: OptLevel,
}

impl Config {
    fn name(&self) -> String {
        let opt = match self.opt {
            OptLevel::None => "",
            OptLevel::Speed => "/O",
        };
        format!("{}{}", self.target.name(), opt)
    }

    fn options(&self) -> Options {
        Options {
            target: self.target,
            opt_level: self.opt,
        }
    }

    // The link command, run in the case directory: produces ./prog from
    // prog.o.
    fn link_command(&self) -> (String, Vec<String>) {
        let (linker, flags) = self.target.linker();
        let mut args: Vec<String> = flags.iter().map(|s| s.to_string()).collect();
        args.extend(["-o", "prog", "prog.o", "-lm"].map(String::from));
        (linker.to_string(), args)
    }
}

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

fn parse_target(name: &str) -> Target {
    [
        Target::LinuxX86_64,
        Target::MacosX86_64,
        Target::MacosAarch64,
    ]
    .into_iter()
    .find(|t| t.name() == name)
    .unwrap_or_else(|| panic!("unknown TACHYON_TARGET '{}'", name))
}

fn configs() -> Vec<Config> {
    let opt = env("TACHYON_OPT").unwrap_or_else(|| "all".into());
    let target_override = if env("TACHYON_DOCKER").as_deref() == Some("1") {
        Some(Target::LinuxX86_64)
    } else {
        env("TACHYON_TARGET").map(|t| parse_target(&t))
    };
    let opts: Vec<OptLevel> = match opt.as_str() {
        "0" => vec![OptLevel::None],
        "1" => vec![OptLevel::Speed],
        "all" => vec![OptLevel::None, OptLevel::Speed],
        other => panic!("TACHYON_OPT must be 0, 1 or all, not '{}'", other),
    };

    let targets = match target_override {
        Some(target) => vec![target],
        None => {
            // Apple Silicon also runs x86-64 binaries, under Rosetta 2.
            let native = Target::host();
            if cfg!(target_os = "macos") && !native.is_x86_64() {
                vec![native, Target::MacosX86_64]
            } else {
                vec![native]
            }
        }
    };
    let mut configs = Vec::new();
    for (index, target) in targets.into_iter().enumerate() {
        // -O on the first (native) target only, to keep the suite fast.
        for opt in &opts {
            if index > 0 && *opt == OptLevel::Speed && opts.len() > 1 {
                continue;
            }
            configs.push(Config { target, opt: *opt });
        }
    }
    configs
}

// Where a configuration's programs run.
#[derive(Clone, Copy)]
enum Runner {
    Native,
    Docker,
}

fn tool_exists(tool: &str) -> bool {
    Command::new(tool)
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

fn runner_for(config: &Config) -> Result<Runner, String> {
    if config.target == Target::LinuxX86_64 && env("TACHYON_DOCKER").as_deref() == Some("1") {
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
        return Ok(Runner::Docker);
    }
    // macOS runs x86-64 binaries on Apple Silicon through Rosetta 2.
    let runs_here = Target::native() == Some(config.target)
        || (cfg!(target_os = "macos") && config.target.is_macos());
    if !runs_here {
        return Err(format!(
            "{} binaries do not run on this host (set TACHYON_DOCKER=1 for linux-x86_64)",
            config.target.name()
        ));
    }
    let (linker, _) = config.link_command();
    if !tool_exists(&linker) {
        return Err(format!("'{}' not found", linker));
    }
    Ok(Runner::Native)
}

// A command running `program` inside `dir`, either directly or in the
// container with `dir` mounted as the working directory.
fn command(runner: Runner, dir: &Path, program: &str, args: &[String]) -> Command {
    match runner {
        Runner::Native => {
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
        Runner::Docker => {
            let mut c = Command::new("docker");
            c.args(["run", "--rm", "-i", "--platform", "linux/amd64", "-v"])
                .arg(format!("{}:/work", dir.display()))
                .args(["-w", "/work", DOCKER_IMAGE, "timeout", "20", program])
                .args(args);
            c
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

fn panic_message(panic: Box<dyn std::any::Any + Send>) -> String {
    panic
        .downcast_ref::<String>()
        .cloned()
        .or_else(|| panic.downcast_ref::<&str>().map(|s| s.to_string()))
        .unwrap_or_default()
}

// Compile, turning a compiler panic (an internal compiler error) into an
// error report so one crashing case does not take down the whole suite.
fn compile(source: &str, options: Options) -> Result<Artifact, String> {
    let source_owned = source.to_string();
    let result = std::panic::catch_unwind(move || tachyon::compile(&source_owned, &options));
    match result {
        Ok(Ok(artifact)) => Ok(artifact),
        Ok(Err(errors)) => Err(tachyon::format_errors(&errors, source)),
        Err(panic) => Err(format!("compiler panicked: {}", panic_message(panic))),
    }
}

fn check_compile_error(case: &Case, expected: &str) -> Result<(), String> {
    let source = std::fs::read_to_string(&case.source).unwrap();
    match compile(&source, Options::default()) {
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

fn run_case(case: &Case, config: &Config, runner: Runner, work: &Path) -> Result<(), String> {
    let source = std::fs::read_to_string(&case.source).unwrap();
    let artifact = compile(&source, config.options())
        .map_err(|report| format!("compile failed:\n{}", report))?;

    let dir = work.join(config.name().replace('/', "-")).join(&case.name);
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let Artifact(bytes) = artifact;
    std::fs::write(dir.join("prog.o"), bytes).unwrap();

    let (linker, args) = config.link_command();
    let output = run_with_timeout(command(runner, &dir, &linker, &args), None)?;
    if output.code != Some(0) {
        return Err(format!(
            "{} failed:\n{}{}",
            linker, output.stdout, output.stderr
        ));
    }

    if case.build_only {
        return Ok(());
    }

    let output = run_with_timeout(
        command(runner, &dir, "./prog", &case.args),
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

// Per-category (file-name prefix) counts: pass, xfail, fail.
type Tally = std::collections::BTreeMap<String, [usize; 3]>;

struct Report {
    name: String,
    tally: Tally,
    failures: Vec<String>,
    skipped: Option<String>,
}

fn record(
    tally: &mut Tally,
    failures: &mut Vec<String>,
    label: &str,
    case: &Case,
    xfail: Option<&str>,
    result: Result<(), String>,
) {
    let category = case.name.split('_').next().unwrap_or("").to_string();
    let counts = tally.entry(category).or_default();
    match (result, xfail) {
        (Ok(()), None) => counts[0] += 1,
        (Err(_), Some(_)) => counts[1] += 1,
        (Ok(()), Some(reason)) => {
            counts[2] += 1;
            failures.push(format!(
                "[{}] {}: passes but is marked XFAIL ({}); remove the directive",
                label, case.name, reason
            ));
        }
        (Err(message), None) => {
            counts[2] += 1;
            failures.push(format!("[{}] {}: {}", label, case.name, message));
        }
    }
}

fn run_config(config: Config, cases: &[Case], work: &Path) -> Report {
    let name = config.name();
    let mut report = Report {
        name: name.clone(),
        tally: Tally::new(),
        failures: Vec::new(),
        skipped: None,
    };
    let runner = match runner_for(&config) {
        Ok(runner) => runner,
        Err(reason) => {
            report.skipped = Some(reason);
            return report;
        }
    };
    for case in cases.iter().filter(|c| c.error.is_none()) {
        let result = run_case(case, &config, runner, work);
        record(
            &mut report.tally,
            &mut report.failures,
            &name,
            case,
            case.xfail_for(&config),
            result,
        );
    }
    report
}

fn print_table(title: &str, tally: &Tally) {
    eprintln!("\n  {}", title);
    eprintln!(
        "  {:<10} {:>5} {:>6} {:>5}",
        "category", "pass", "xfail", "fail"
    );
    let mut total = [0usize; 3];
    for (category, counts) in tally {
        eprintln!(
            "  {:<10} {:>5} {:>6} {:>5}",
            category, counts[0], counts[1], counts[2]
        );
        for i in 0..3 {
            total[i] += counts[i];
        }
    }
    eprintln!(
        "  {:<10} {:>5} {:>6} {:>5}",
        "total", total[0], total[1], total[2]
    );
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

    if let Some(filter) = env("TACHYON_RUN_FILTER") {
        cases.retain(|c| c.name.contains(&filter));
    }

    let work = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("run");

    // Front-end error cases, once.
    let mut errors_tally = Tally::new();
    let mut failures = Vec::new();
    for case in cases.iter() {
        if let Some(expected) = &case.error {
            let xfail = case
                .xfail
                .iter()
                .find(|(scope, _)| scope.is_none())
                .map(|(_, r)| r.as_str());
            let result = check_compile_error(case, expected);
            record(
                &mut errors_tally,
                &mut failures,
                "front end",
                case,
                xfail,
                result,
            );
        }
    }

    // Every configuration in parallel; each runs its cases in order.
    let configs = configs();
    let reports: Vec<Report> = std::thread::scope(|scope| {
        let handles: Vec<_> = configs
            .iter()
            .map(|config| {
                let cases = &cases;
                let work = &work;
                scope.spawn(move || run_config(*config, cases, work))
            })
            .collect();
        handles
            .into_iter()
            .map(|h| h.join().unwrap_or_else(|p| panic!("{}", panic_message(p))))
            .collect()
    });

    if !errors_tally.is_empty() {
        print_table("front end (ERROR cases)", &errors_tally);
    }
    let mut skipped = Vec::new();
    for report in reports {
        match &report.skipped {
            Some(reason) => {
                eprintln!("\n  {}: skipped ({})", report.name, reason);
                skipped.push(format!("{}: {}", report.name, reason));
            }
            None => print_table(&report.name, &report.tally),
        }
        failures.extend(report.failures);
    }
    eprintln!();

    // Restore the default hook so the summary below is printed.
    let _ = std::panic::take_hook();
    if !skipped.is_empty() && env("TACHYON_REQUIRE_RUN").as_deref() == Some("1") {
        panic!("cannot run golden programs:\n{}", skipped.join("\n"));
    }
    assert!(
        failures.is_empty(),
        "{} golden program run(s) failed:\n\n{}",
        failures.len(),
        failures.join("\n\n")
    );
}
