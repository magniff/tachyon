// Backends turn the lowered IR into something the system toolchain can link.
//
// This module is the seam between the middle end and code generation: a
// backend only ever sees an `IrProgram`, so the IR can later be swapped for a
// proper SSA IR without touching the driver.
//
//   cranelift  a native object file, built with Cranelift (cranelift.rs).

pub mod cranelift;

use crate::lowering::IrProgram;

#[derive(Debug)]
pub struct GeneratorError {
    pub message: String,
}

impl From<std::fmt::Error> for GeneratorError {
    fn from(value: std::fmt::Error) -> Self {
        Self {
            message: value.to_string(),
        }
    }
}

// The platform code is generated for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Target {
    // x86-64 System V, ELF. Linked with gcc/cc.
    LinuxX86_64,
    // x86-64 System V, Mach-O. Linked with `clang -arch x86_64`; Apple
    // Silicon runs it under Rosetta 2.
    MacosX86_64,
    // Apple arm64 (AAPCS64 with Apple's variadic convention), Mach-O.
    MacosAarch64,
}

impl Target {
    // The machine this compiler is running on, if it can be targeted.
    pub fn native() -> Option<Target> {
        if cfg!(all(target_os = "macos", target_arch = "aarch64")) {
            Some(Target::MacosAarch64)
        } else if cfg!(all(target_os = "macos", target_arch = "x86_64")) {
            Some(Target::MacosX86_64)
        } else if cfg!(all(target_os = "linux", target_arch = "x86_64")) {
            Some(Target::LinuxX86_64)
        } else {
            None
        }
    }

    // The default target on this host: native where supported, otherwise
    // the x86-64 flavour of the host OS.
    pub fn host() -> Target {
        Target::native().unwrap_or(if cfg!(target_os = "macos") {
            Target::MacosX86_64
        } else {
            Target::LinuxX86_64
        })
    }

    pub fn name(self) -> &'static str {
        match self {
            Target::LinuxX86_64 => "linux-x86_64",
            Target::MacosX86_64 => "macos-x86_64",
            Target::MacosAarch64 => "macos-aarch64",
        }
    }

    pub fn triple(self) -> &'static str {
        match self {
            Target::LinuxX86_64 => "x86_64-unknown-linux-gnu",
            Target::MacosX86_64 => "x86_64-apple-darwin",
            Target::MacosAarch64 => "aarch64-apple-darwin",
        }
    }

    pub fn is_macos(self) -> bool {
        matches!(self, Target::MacosX86_64 | Target::MacosAarch64)
    }

    pub fn is_x86_64(self) -> bool {
        matches!(self, Target::LinuxX86_64 | Target::MacosX86_64)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum OptLevel {
    #[default]
    None,
    Speed,
}

#[derive(Debug, Clone, Copy)]
pub struct Options {
    pub target: Target,
    pub opt_level: OptLevel,
}

impl Default for Options {
    fn default() -> Options {
        Options {
            target: Target::host(),
            opt_level: OptLevel::None,
        }
    }
}

// What a backend produces: a relocatable object file, ready for the linker.
pub struct Artifact(pub Vec<u8>);

pub trait Backend {
    fn compile(&self, program: &IrProgram, options: &Options) -> Result<Artifact, GeneratorError>;
}

pub fn backend() -> Box<dyn Backend> {
    Box::new(cranelift::CraneliftBackend)
}
