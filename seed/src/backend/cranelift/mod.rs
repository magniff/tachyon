// Cranelift backend: lowers the IR to CLIF and emits a native object file.
//
// Every vreg becomes a cranelift-frontend `Variable`, so the frontend builds
// SSA on the fly (Braun et al.) and the register allocator sees real values.
// Stack slots whose address never escapes and that are only read and written
// whole, with one scalar type, are promoted to variables as well (mem2reg);
// everything else stays an explicit stack slot.
//
// Calling convention:
// - tachyon functions use the platform C convention, with tachyon's own
//   rules for compound values on top (sret pointer first, structs by pointer).
// - C variadic calls need care, as Cranelift has no variadic signatures:
//   * x86-64 System V: the caller must put an upper bound on the number of
//     vector registers used in `al`. Calls go through a 7-byte thunk,
//     `mov al, 8; jmp callee`, which leaves arguments and stack untouched.
//   * Apple arm64: variadic arguments are passed on the stack, never in
//     registers. The call signature is padded with dummy arguments until all
//     eight integer and eight vector argument registers are taken, so the
//     variadic ones land on the stack, each in its own 8-byte slot.
//   Variadic arguments are widened to 64 bits so that every one fills a
//   full stack slot.
// - Local tachyon functions get the symbol `tachyon.<name>` so they cannot
//   clash with C symbols (a tachyon `pow` next to libc's `pow`); `main` keeps
//   its name.
//
//   codegen.rs    the module: declarations, definitions, variadic thunks
//   analysis.rs   vreg definitions, uses and types
//   mem2reg.rs    which slots can live in variables
//   translate.rs  one IR function to CLIF
//   inst.rs       IR instructions to CLIF
//   call.rs       calls

use cranelift_codegen::isa::{self, OwnedTargetIsa};
use cranelift_codegen::settings::{self, Configurable};

use super::{Artifact, Backend, GeneratorError, OptLevel, Options, Target};
use crate::lowering::IrProgram;

mod analysis;
mod call;
mod codegen;
mod inst;
mod mem2reg;
mod translate;

use codegen::Codegen;

pub struct CraneliftBackend;

impl Backend for CraneliftBackend {
    fn compile(&self, program: &IrProgram, options: &Options) -> Result<Artifact, GeneratorError> {
        let mut codegen = Codegen::new(program, options)?;
        codegen.define_all(program, None)?;
        codegen.finish().map(Artifact)
    }
}

// The CLIF of every function after Cranelift's mid-end, followed by the
// machine code it was lowered to.
pub fn clif_text(program: &IrProgram, options: &Options) -> Result<String, GeneratorError> {
    let mut codegen = Codegen::new(program, options)?;
    let mut text = String::new();
    codegen.define_all(program, Some(&mut text))?;
    Ok(text)
}

fn error(message: impl Into<String>) -> GeneratorError {
    GeneratorError {
        message: message.into(),
    }
}

fn make_isa(options: &Options) -> Result<OwnedTargetIsa, GeneratorError> {
    let mut flags = settings::builder();
    let opt_level = match options.opt_level {
        OptLevel::None => "none",
        OptLevel::Speed => "speed",
    };
    let mut set = |name: &str, value: &str| {
        flags
            .set(name, value)
            .map_err(|e| error(format!("cranelift setting {}={}: {}", name, value, e)))
    };
    set("opt_level", opt_level)?;
    set("is_pic", "true")?;
    // Apple arm64 requires frame records; they also keep backtraces usable.
    set("preserve_frame_pointers", "true")?;
    set("enable_verifier", "true")?;
    let flags = settings::Flags::new(flags);

    let builder = if Some(options.target) == Target::native() {
        cranelift_native::builder_with_options(true).map_err(error)?
    } else {
        let triple: target_lexicon::Triple = options
            .target
            .triple()
            .parse()
            .map_err(|e| error(format!("bad target triple: {}", e)))?;
        isa::lookup(triple).map_err(|e| error(format!("cranelift: {}", e)))?
    };
    builder
        .finish(flags)
        .map_err(|e| error(format!("cranelift: {}", e)))
}
