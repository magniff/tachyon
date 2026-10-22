# std::arch: SIMD and CPU intrinsics

Vole 0.19 gives the CPU's own instructions as functions, under the
vendors' names: `vceqq_u8` (NEON), `__crc32d` (Arm's CRC-32),
`_mm_movemask_epi8` (SSE2). The compiler checks every call against the
features known at that point, so an instruction the CPU lacks never
runs: a program tests the CPU with `std::arch::detect("crc")` and keeps
a fallback, and the build's baseline (`neon` on every AArch64,
`sse2` on every x86-64) needs no test. `volec guide arch` is the
whole story; `volec query arch WORDS` finds an intrinsic.

| example | the program | what it shows |
|---|---|---|
| [bytesearch](bytesearch/) | `memchr`: where a byte first occurs | NEON compares 64 bytes an iteration, the AArch64 movemask (`vshrn_n_u16`), an SSE2 branch checked on arm and never generated there, against the portable loop: 15x, as fast as libc's `memchr` |
| [crc32](crc32/) | CRC-32, gzip's checksum | `__crc32d` behind `if !detect("crc") { return fallback }`, the table-driven fallback, `-C target-cpu=generic`, `VOLE_ARCH_DISABLE`, the error when the guard is missing: 24x the table, as fast as clang with `arm_acle.h` |
| [sha256sum](sha256sum/) | coreutils' `sha256sum`: files, stdin, `--tag`, `-c` | the sha2 instructions (`vsha256hq_u32` ...) in a `#[target_feature(enable = "sha2")]` function behind `detect("sha2")`, the portable rounds as the fallback, an x86-64 SHA-NI version compiled and checked only, 1 MiB reads into one buffer: 3 GB/s, faster than macOS's tool, 4.7x coreutils', as fast as OpenSSL |

Each README is a session: its `console` blocks are run by
`tests/walkthrough/run.sh` in a copy of the example's directory and
checked against what the commands print now. The timings are not run
(they are this machine's). Each program also has a test case,
`tests/examples/arch-NAME.test` (`tests/run.sh arch-` runs them), which
`tests/run.sh` runs a second time with `VOLE_ARCH_DISABLE=all`: the
fallbacks must print the same.
