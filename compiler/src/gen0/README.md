# gen0: -O0, and the driver of every level

`gen/mod.vl`'s `compile_program` drives code generation at every level:
at -O1 and -O2 it lowers, optimizes and emits through `middle` and
`back`; at -O0 it runs the 0.1 code generator, which walks the checked
AST and writes assembly through the target interface. -O0 shares only
the front end with the other levels, so it is the oracle they are tested
against.

| module | |
|---|---|
| `gen/` | the driver, and -O0's generator: functions and statements (`mod`), expressions (`expr`), control flow and `match` (`control`), calls (`call`), vectors (`vector`) |
| `target.vl` | the target interface: the machine model's virtual registers, output helpers, data, run-time checks, dispatch to the instruction set |
| `arm64.vl` | AArch64 for -O0 (Apple's arm64 ABI, AAPCS64; Mach-O, ELF) |
| `x86_64.vl` | x86-64 for -O0 (System V; AT&T syntax) |
