// Code generation checks that need no linker or runtime, so they run on
// any host: every program compiles for every target, and the variadic call
// conventions show up in the generated CLIF.

use tachyon::{Artifact, OptLevel, Options, Target};

const TARGETS: [Target; 3] = [
    Target::LinuxX86_64,
    Target::MacosX86_64,
    Target::MacosAarch64,
];

fn options(target: Target, opt_level: OptLevel) -> Options {
    Options { target, opt_level }
}

fn program_sources() -> Vec<(String, String)> {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut sources = Vec::new();
    for dir in ["tests/run", "examples"] {
        let mut paths: Vec<_> = std::fs::read_dir(root.join(dir))
            .unwrap()
            .map(|e| e.unwrap().path())
            .filter(|p| p.extension().is_some_and(|e| e == "tach"))
            .collect();
        paths.sort();
        for path in paths {
            let source = std::fs::read_to_string(&path).unwrap();
            // Front-end error cases and known backend gaps.
            if source
                .lines()
                .any(|l| l.starts_with("// ERROR:") || l.starts_with("// XFAIL"))
            {
                continue;
            }
            sources.push((path.display().to_string(), source));
        }
    }
    sources
}

// Every program becomes an object file of the right format for every target,
// with and without optimization. This is the only coverage the linux-x86_64
// object path gets on a macOS host.
#[test]
fn compiles_for_every_target() {
    let mut failures = Vec::new();
    for (name, source) in program_sources() {
        for target in TARGETS {
            for opt in [OptLevel::None, OptLevel::Speed] {
                match tachyon::compile(&source, &options(target, opt)) {
                    Ok(Artifact(bytes)) => {
                        let elf = bytes.starts_with(b"\x7fELF");
                        let macho = bytes.starts_with(&[0xcf, 0xfa, 0xed, 0xfe]);
                        if (target == Target::LinuxX86_64 && !elf) || (target.is_macos() && !macho)
                        {
                            failures.push(format!("{} {:?}: wrong object format", name, target));
                        }
                    }
                    Err(errors) => failures.push(format!(
                        "{} {:?} {:?}:\n{}",
                        name,
                        target,
                        opt,
                        tachyon::format_errors(&errors, &source)
                    )),
                }
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

const VARIADIC: &str = r#"
extern fn printf(format: *u8, ...) -> i32;
fn main() -> i64 {
    let x: i32 = 7;
    printf("%d %f\n".0, x, 0.5);
    0
}
"#;

fn clif(target: Target) -> String {
    tachyon::compile_to_clif(VARIADIC, &options(target, OptLevel::None))
        .unwrap_or_else(|errors| panic!("{}", tachyon::format_errors(&errors, VARIADIC)))
}

// Apple arm64 passes variadic arguments on the stack: the call signature is
// padded so all eight integer and eight vector registers are taken, and the
// variadic values follow as 64-bit stack arguments.
#[test]
fn apple_arm64_variadic_args_go_on_the_stack() {
    let text = clif(Target::MacosAarch64);
    let padded = format!(
        "({}, {}, i64, f64) -> i32 apple_aarch64",
        ["i64"; 8].join(", "),
        ["f64"; 8].join(", ")
    );
    assert!(text.contains(&padded), "no padded signature in:\n{}", text);
}

// x86-64 System V needs an upper bound of the vector registers used in %al:
// variadic calls go through the `mov al, 8; jmp printf` thunk and pass
// arguments in registers as usual.
#[test]
fn x86_64_variadic_calls_use_the_al_thunk() {
    for target in [Target::LinuxX86_64, Target::MacosX86_64] {
        let text = clif(target);
        assert!(
            text.contains("(i64, i64, f64) -> i32 system_v"),
            "unexpected variadic signature for {:?}:\n{}",
            target,
            text
        );
        let options = options(target, OptLevel::None);
        let Ok(Artifact(bytes)) = tachyon::compile(VARIADIC, &options) else {
            panic!("compile failed");
        };
        // mov al, 8 ; jmp rel32
        assert!(
            bytes.windows(3).any(|w| w == [0xb0, 0x08, 0xe9]),
            "no al thunk in the {:?} object",
            target
        );
    }
}
