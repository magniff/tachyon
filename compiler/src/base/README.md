# base: what every phase uses

The C library, growable arrays, byte buffers, the symbol interner and the
source files, with the diagnostics, the target selection and the phase
timer. Every other folder imports from here; base imports from none of
them (but `diag.vl`, for the instantiation chain a message notes).

| module | |
|---|---|
| `mod.vl` | `crate::base`: the C library's declarations, `grow` and `IntVec`, byte buffers (`BUFS`), symbols (`intern`, `SYMS`), the source files (`SRC`, `FILES`), fatal errors, C strings |
| `diag.vl` | errors at a source position, several per run through recovery points (`_setjmp`), warnings, `--diagnostics=short` |
| `target.vl` | the target being compiled for (`--target`, else the host): the machine and the object format, read by every phase |
| `timer.vl` | `--time-passes`: the CPU time of each phase |
