# sha256sum: SHA-256 checksums by the sha2 instructions

coreutils' `sha256sum`, in vole: the same output, options, messages
and exit codes, and faster than the system's on every workload measured
below. Armv8's sha2 extension does SHA-256's compression four rounds an
instruction (`vsha256hq_u32`, `vsha256h2q_u32`), and its message
schedule four words at a time (`vsha256su0q_u32`, `vsha256su1q_u32`).

```text
sha256sum [OPTION]... [FILE]...     HASH  NAME, a line each (no FILE, or -: stdin)
  -b, --binary   HASH *NAME          -t, --text     HASH  NAME (the default)
  --tag          SHA256 (NAME) = HASH
  -c, --check    read HASH  NAME lines (or --tag's) and check each file:
                 NAME: OK, NAME: FAILED, NAME: FAILED open or read
  with -c:       --quiet (no OK lines), --status (nothing, the exit code),
                 --warn / -w (report malformed lines), --strict (fail on them),
                 --ignore-missing (skip files that do not exist)
exit code        0, or 1 when a file could not be read or a checksum did not match
```

Names with a backslash or a newline are escaped as coreutils does (a
`\` at the start of the line), errors go to stderr in coreutils' form
(`sha256sum: NAME: No such file or directory`), and `-c` reads
coreutils' lists, BSD's `--tag` lines and its own.

## The design

`sha256.vl` is the hashing; `main.vl` the command. Everything goes
through one function, which hashes whole 64-byte blocks and picks the
instructions once a call:

```tach
pub fn blocks(state: inout [u32], data: [u8]) {
    if detect("sha2") {
        blocks_arm(state, data);
    } else if detect("sha") && detect("sse4.1") {
        blocks_x86(state, data);
    } else {
        blocks_portable(state, data);
    }
}
```

- **The fast path**, `blocks_arm`, is `#[target_feature(enable = "sha2")]`:
  the state stays in two vector registers (`abcd`, `efgh`) across all
  of a call's blocks; each block is four 16-byte loads (`vld1q_u8`),
  `vrev32q_u8` to make the words big-endian, and the sixteen groups of
  four rounds written out. The 16 round-constant vectors are loaded once
  a call, outside the loop. The compiled loop is the instructions one
  would write by hand: 16 `sha256h`, 16 `sha256h2`, 12 `sha256su0` and
  `sha256su1`, 16 `add`s of the constants, the copies `sha256h`'s
  destructive form needs, and the bounds checks of the four loads.
- **The fallback**, `blocks_portable`, is FIPS 180-4's rounds as the
  standard writes them, on `u32`s (their arithmetic wraps, as SHA-256
  wants: vole defines it). `VOLE_ARCH_DISABLE=all` forces it.
- **x86-64**: `blocks_x86` is the SHA extensions' version (`sha256rnds2`
  two rounds at a time on the state as `abef`/`cdgh`, `sha256msg1` and
  `sha256msg2` for the schedule). On an arm machine it is type-checked and
  not generated; `tests/examples/arch-sha256sum.test` also compiles the
  program for x86_64-linux and checks the three instructions are there.
  It is compiled only: no machine here has them (Rosetta 2 does not), so
  it has never run.

**Why it is safe.** No `unsafe` is written for the hashing. The compiler
checks every intrinsic's call against the features known at that point:
`blocks_arm` declares sha2, so its callers must know it, and `blocks`
knows it only inside `if detect("sha2")`: remove the test and the
program does not compile. `detect` reads one bit filled before `main`
from the OS (macOS's sysctls, Linux's hwcaps). The loads take a slice
and an index and are checked like `s[i]`; a store into the state needs
it writable, an `inout [u32]`. Where sha2 is in the build's baseline (every Apple CPU:
`-C target-cpu=apple-m1`, the default on macOS), `detect("sha2")` is the
constant `true` and the fallback is not generated; on Linux (`generic`:
Armv8.0) it is a real test.

```console
$ volec query features sha256::blocks sha256::blocks_arm sha256::blocks_x86 sha256::blocks_portable main -C target-cpu=generic
crate::sha256::blocks	none
crate::sha256::blocks_arm	sha2 (declared)
crate::sha256::blocks_x86	sse4.1, sha (declared)
crate::sha256::blocks_portable	none
crate::main	none
```

**The reading.** One 1 MiB buffer, allocated once from `main`'s `gpa`,
serves every file; `read(2)` fills it, its whole blocks are hashed in
place, and the few bytes after them (fewer than 64) move to its start.
Nothing is allocated per block or per file; output is buffered (written
at 64 KiB and at the end, and before an error, so the two streams keep
their order). The C calls (`open`, `read`, `write`, `close`,
`strerror`) are declared in `main.vl` without headers, so the program
also compiles for another target without its C library; `errno` comes
from std (`std::sys::sys_errno`).

## Run it

```console
$ volec main.vl -o sha256sum
ok: built sha256sum
$ printf abc > abc.txt && : > empty.txt && ./sha256sum abc.txt empty.txt | tee sums
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  abc.txt
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  empty.txt
$ printf abc | ./sha256sum --tag
SHA256 (-) = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
$ ./sha256sum -c sums
abc.txt: OK
empty.txt: OK
$ printf '!' >> abc.txt && ./sha256sum -c sums
abc.txt: FAILED
empty.txt: OK
sha256sum: WARNING: 1 computed checksum did NOT match
[exit 1]
$ ./sha256sum nope empty.txt
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  empty.txt
sha256sum: nope: No such file or directory
[exit 1]
```

`test.sh` checks the rest, with a second build where sha2 is not in the
baseline, so that `VOLE_ARCH_DISABLE=all` takes the portable rounds:
FIPS 180-4's examples and a million a's (the known answers), the lengths
around the padding's edges (0, 1, 55, 56, 63, 64, 65, 119, 120) and the
buffer's (1 MiB and one byte either side), as files and through a pipe
in 37-byte writes, 40 random files against the system's tool (coreutils'
`sha256sum` on Linux, macOS's own), both paths, and `-c` of its lists
and the system's:

```console
$ volec -C target-cpu=generic main.vl -o sha256sum-generic
ok: built sha256sum-generic
$ sh test.sh
known answers: 5 messages, both paths
lengths: 12, as files and through a pipe, the system's hashes
random files: 40, by both paths, the system's hashes
-c: its own lists (plain, --tag, -b) and the system's
names with \ and a newline: escaped as coreutils does
all passed
```

The suite also runs `tests/examples/arch-sha256sum*.test` (stdin, a
missing file, `-c` with every kind of line), the generic build a second
time with `VOLE_ARCH_DISABLE=all`.

## Timings

`sh bench.sh DIR TOOL...` makes the inputs and prints the best wall time
of five runs: a 1 GiB file (warm cache), 10,000 files of 1 byte to
16 KiB (82 MB in all, one command line), and the 1 GiB file through a
pipe from `cat`. At -O2 (the default):

On an Apple M5 (10 cores), macOS 26, load average 3 to 7 (other work on
the machine):

```text
tool                              1 GiB file          10,000 files   1 GiB pipe
./sha256sum                       0.352 s  3.05 GB/s  0.119 s        0.347 s  3.09 GB/s
/sbin/sha256sum (macOS)           0.428 s  2.51 GB/s  0.227 s        0.359 s  2.99 GB/s
openssl dgst -sha256 (4.0.3)      0.399 s  2.69 GB/s  0.150 s        0.368 s  2.92 GB/s
shasum -a 256 (perl)              1.902 s  0.56 GB/s  0.310 s        2.156 s  0.50 GB/s
```

In a linux/arm64 container on the same machine (colima, Debian 12,
idle), the program built for aarch64-linux, where sha2 is detected at
run time:

```text
tool                              1 GiB file          10,000 files   1 GiB pipe
./sha256sum                       0.381 s  2.82 GB/s  0.049 s        0.403 s  2.66 GB/s
sha256sum (coreutils 9.1)         1.799 s  0.60 GB/s  0.173 s        1.920 s  0.56 GB/s
openssl dgst -sha256 (3.0.22)     0.407 s  2.64 GB/s  0.069 s        0.538 s  2.00 GB/s
./sha256sum, VOLE_ARCH_DISABLE=all (the fallback)
                                  3.796 s  0.28 GB/s  0.318 s        3.892 s  0.28 GB/s
```

- The fast path is 20% faster than macOS's `sha256sum` on a file, 4.7
  times coreutils' (which Debian builds without OpenSSL, so it hashes in
  portable C), and a little faster than OpenSSL's hand-written assembly
  on both systems. The compression loop runs at about 3.2 GB/s (its user
  time); the rest is the kernel copying the file.
- 10,000 small files: twice macOS's tool, 3.5 times coreutils': one
  `open`, two `read`s and a `close` a file, and one `write` for 64 KiB of
  output.
- Through a pipe, everything but perl is as fast as the pipe (`cat big |
  cat > /dev/null` alone takes about 0.43 s in the container).
- The fallback is honest but slow: half of coreutils' portable C. The
  compiler does not yet fuse `(x >> n) | (x << (32 - n))` into one `ror`
  (six rotates a round become twelve instructions) and rematerializes
  the constants' address inside the round loop; both are reported. The
  fast path also keeps the bounds checks of the loads at `i + 16`,
  `i + 32` and `i + 48` (the loop's `i + 64 <= len` proves them):
  six compares a block, which the measurements above include.
