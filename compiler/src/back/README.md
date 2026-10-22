# back: optimized IR to machine code (-O1, -O2)

From the optimized IR of `middle` to an object file, in this order:
instruction selection, register allocation, block layout, emission
through the target's machine layer, then the assembler. The assembler,
the encoders, `abi.vl` and `dwarf.vl` serve -O0 (`gen0`) too.

| module | |
|---|---|
| `isel/` | instruction selection: branches reshaped (`branches`), divisions by constants (`divisions`), tiling by maximal munch (`tiling`) |
| `regalloc/` | linear scan on SSA: use counts and liveness (`prepare`), intervals, the scan, locations and moves, `--verify-regalloc` (`check`) |
| `layout.vl` | the order blocks are emitted in |
| `emit/` | the allocated IR emitted: functions and frames, blocks, instructions, calls, operands and parallel moves, the machine layer, `--stats` |
| `mc_arm64/`, `mc_x86_64/` | the machine instructions of each instruction set, on physical registers (`ops`, `vector`) |
| `abi.vl` | C's calling convention for aggregates (AArch64, System V) |
| `objfile/` | the assembler: the text assembled (`assemble`), layout and fixups (`resolve`), Mach-O (`macho`) and ELF (`elf`) writers, `-g`'s sections (`debug`) |
| `enc_arm64.vl`, `enc_x86.vl` | instruction encoding |
| `dwarf.vl` | `-g`: line tables and debug information |
