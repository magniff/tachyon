# crc32: CRC-32 by the crc instructions

CRC-32 is the checksum of gzip, zip and PNG. The portable way is a
table of 256 entries and one lookup a byte. Armv8's crc extension does
8 bytes an instruction: `__crc32d(crc, word)`, with `__crc32b` for the
bytes left over.

crc is in every Apple CPU but not in every Arm one: Linux on arm64
promises only Armv8.0, and its baseline (`-C target-cpu=generic`) has
only neon and fp. So the program asks the CPU once, and keeps the table
as the fallback:

```tach
fn crc32(t: [u32], crc: u32, s: [u8]) -> u32 {
    if !detect("crc") {
        return crc32_portable(t, crc, s);
    }
    crc32_hw(crc, s)
}
```

Below the early return, crc is known, so `crc32_hw` may be called; the
compiler checks it. `crc32_hw` itself needs no attribute: what a
function needs is inferred from what it calls, as its effects are.
`detect("crc")` reads one cached bit, filled once before `main`; on
macOS, where crc is in the build's baseline, it is the constant `true`
and the fallback is not even generated.

## Run it

```console
$ volec main.vl -o crc32 && ./crc32
crc32("123456789") = cbf43926
4800 checksums, 0 wrong
ok: built crc32
```

`cbf43926` is CRC-32's check value. For a build where crc is not known,
`-C target-cpu=generic` makes `detect` a real test of the CPU, and
`VOLE_ARCH_DISABLE` turns a feature off at run time (it can only
clear features, never add one), so the fallback runs and prints the
same:

```console
$ volec -C target-cpu=generic main.vl -o crc32-generic && VOLE_ARCH_DISABLE=crc ./crc32-generic
crc32("123456789") = cbf43926
4800 checksums, 0 wrong
ok: built crc32-generic
```

## What needs crc

```console
$ volec query features crc32_hw crc32 main -C target-cpu=generic
crate::crc32_hw	crc (inferred)
crate::crc32	none
crate::main	none
$ volec query features crc32_hw --why crc -C target-cpu=generic
crate::crc32_hw	crc (inferred)
  main.vl:42:13: calls 'std::arch::aarch64::__crc32d', which needs crc
```

Without the guard, the program would run an instruction the CPU may
lack. The edit that drops it is refused (an edit that adds an error
writes nothing). `crc32` then needs crc, and so do `check` and `bench`,
which call it: the requirement is inferred up the calls, and the error
is where it surfaces, at `main`'s calls, with the intrinsic it comes
from:

```console
$ volec edit patch crc32 --old '    if !detect("crc") {
>         return crc32_portable(t, crc, s);
>     }
> ' --new '' -C target-cpu=generic
main.vl:117:9: error[arch.feature] 'bench' needs crc (from '__crc32d' at main.vl:42:13), which 'main' does not know here: the build's features are neon | help: test the CPU and keep a fallback, declare #[target_feature] on the caller, or build only for CPUs that have it | try: volec edit patch main.vl:117 --old 'bench(gpa, t[..], mode == "hw");' --new 'if std::arch::detect("crc") { bench(gpa, t[..], mode == "hw"); };' -C target-cpu=generic main.vl | try: volec -C target-feature=+crc -C target-cpu=generic -o main main.vl | try: volec query features bench --why crc -C target-cpu=generic main.vl  [in crate::main]
main.vl:119:9: error[arch.feature] 'check' needs crc (from '__crc32d' at main.vl:42:13), which 'main' does not know here: the build's features are neon | help: test the CPU and keep a fallback, declare #[target_feature] on the caller, or build only for CPUs that have it | try: volec edit patch main.vl:119 --old 'check(gpa, t[..]);' --new 'if std::arch::detect("crc") { check(gpa, t[..]); };' -C target-cpu=generic main.vl | try: volec -C target-feature=+crc -C target-cpu=generic -o main main.vl | try: volec query features check --why crc -C target-cpu=generic main.vl  [in crate::main]
error edit.breaks: 2 new errors (2 in crate::main, which the edit does not change); nothing written
note edit.together: change crate::main in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: volec query show crate::main
try: volec edit patch crc32 --old '    if !detect("crc") {
        return crc32_portable(t, crc, s);
    }
' --new '' -C target-cpu=generic --no-check
[exit 1]
```

The guard belongs where the fallback is, as in `crc32`; a `try:` line
that wraps `main`'s call in a detect would skip the work instead.

## Timings

`./crc32 hw` and `./crc32 portable` checksum 1 MiB 1024 times (1 GiB),
each continuing the last. On an Apple M1 at -O2 (the default), the
fastest of two runs, with the same loop in C (`__crc32d` from
`arm_acle.h`, `cc -O2 -march=armv8-a+crc`) for comparison:

```text
./crc32 hw                                  0.09 s   (about 12 GB/s)
C, the same loop                            0.09 s
./crc32 portable                            2.21 s
-C target-cpu=generic, VOLE_ARCH_DISABLE=crc ./crc32-generic hw   1.75 s (the fallback)
```

24 times the table, and the same speed as clang's. The loop is one
dependency chain (each step waits for the last, three cycles); zlib's
fastest versions interleave three chains and fold them with `vmull_p64`
(`volec guide arch#recipes`).
