// Turning compiled objects into programs: invoking the system linker and
// building executables. Shared by the `tachyon` command and the tests, so
// both link the same way.

use std::fmt;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::{Artifact, CompilerError, Options, Target};

#[derive(Debug)]
pub enum BuildError {
    // The program has errors; report them with `format_errors`.
    Compile(Vec<CompilerError>),
    // The linker is missing or failed.
    Link(String),
    Io(String),
}

impl fmt::Display for BuildError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BuildError::Compile(errors) => write!(f, "{} compile error(s)", errors.len()),
            BuildError::Link(message) | BuildError::Io(message) => f.write_str(message),
        }
    }
}

// The C compiler used as the linker: `$CC`, else `cc`.
pub fn linker_program() -> String {
    std::env::var("CC")
        .ok()
        .filter(|cc| !cc.trim().is_empty())
        .unwrap_or_else(|| "cc".to_string())
}

// The linker invocation that turns `object` into the executable `output`
// for `target`: the program and its arguments. Callers that run the linker
// elsewhere (e.g. in a container) use this directly.
pub fn link_args(target: Target, object: &str, output: &str) -> (String, Vec<String>) {
    let mut args: Vec<String> = match target {
        Target::LinuxX86_64 => vec![],
        // Silences warnings about the x86-64 slice on Apple Silicon hosts.
        Target::MacosX86_64 => vec!["-arch".into(), "x86_64".into(), "-Wl,-w".into()],
        Target::MacosAarch64 => vec!["-arch".into(), "arm64".into()],
    };
    args.extend(["-o", output, object, "-lm"].map(String::from));
    (linker_program(), args)
}

// Links `object` into the executable `output`.
pub fn link(target: Target, object: &Path, output: &Path) -> Result<(), BuildError> {
    let (program, args) = link_args(
        target,
        &object.display().to_string(),
        &output.display().to_string(),
    );
    let result = Command::new(&program).args(&args).output();
    let out = match result {
        Ok(out) => out,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            return Err(BuildError::Link(format!(
                "linker '{}' not found; install a C compiler or set CC",
                program
            )));
        }
        Err(e) => {
            return Err(BuildError::Link(format!(
                "cannot run linker '{}': {}",
                program, e
            )));
        }
    };
    if !out.status.success() {
        return Err(BuildError::Link(format!(
            "linking with '{}' failed ({}):\n{}{}",
            program,
            out.status,
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        )));
    }
    Ok(())
}

// A fresh, empty directory for intermediate files; removed on drop.
pub struct TempDir(PathBuf);

impl TempDir {
    pub fn new(prefix: &str) -> Result<TempDir, BuildError> {
        use std::sync::atomic::{AtomicU32, Ordering};
        static COUNTER: AtomicU32 = AtomicU32::new(0);
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.subsec_nanos())
            .unwrap_or(0);
        let path = std::env::temp_dir().join(format!(
            "{}-{}-{}-{}",
            prefix,
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed),
            nanos
        ));
        std::fs::create_dir_all(&path)
            .map_err(|e| BuildError::Io(format!("cannot create {}: {}", path.display(), e)))?;
        Ok(TempDir(path))
    }

    pub fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

// Compiles `source` and links it into the executable `output`.
pub fn build_executable(source: &str, options: &Options, output: &Path) -> Result<(), BuildError> {
    let Artifact(bytes) = crate::compile(source, options).map_err(BuildError::Compile)?;
    let temp = TempDir::new("tachyon-build")?;
    let object = temp.path().join("program.o");
    std::fs::write(&object, bytes)
        .map_err(|e| BuildError::Io(format!("cannot write {}: {}", object.display(), e)))?;
    link(options.target, &object, output)
}
