# The Tachyon Programming Language

Target: x86-64 Linux, System V AMD64 ABI **only**

In addition to the Rust toolchain, you will need the following third-party dependencies:

- nasm - used to assemble the generated .asm file into an object file
- gcc - used to link the object file against libc

These tools are required by the tachyon.sh script to produce a final executable.

```
$ ./tachyon.sh run examples/helloworld.tach
[1/3] tachyon  examples/helloworld.tach → /tmp/tmp.9c6fgQIp8U/helloworld.asm
[2/3] nasm     /tmp/tmp.9c6fgQIp8U/helloworld.asm → /tmp/tmp.9c6fgQIp8U/helloworld.o
[3/3] gcc      /tmp/tmp.9c6fgQIp8U/helloworld.o → /tmp/tmp.9c6fgQIp8U/helloworld.bin  (libc)
running: examples/helloworld.tach
Hello from tachyon!
```

## Testing

```
$ cargo test                                       # unit tests, asm snapshots, golden programs
$ cargo test --test run -- --nocapture             # golden programs with a per-category summary
$ TACHYON_RUN_FILTER=prog_ cargo test --test run   # only cases whose name contains "prog_"
$ TACHYON_DOCKER=1 cargo test --test run           # run golden programs in a linux/amd64 container
$ cargo insta review                               # accept intended changes to generated assembly
```

Golden programs live in `tests/run/*.tach` and state their expected output in
comments (`// EXPECT:`, `// EXIT:`, `// ARGS:`, `// STDIN:`, `// ERROR:`,
`// XFAIL:` for known bugs; see `tests/run.rs`). They are compiled, assembled,
linked and executed natively on x86-64 Linux (nasm + gcc) and on macOS
(nasm + `clang -arch x86_64`; Apple Silicon runs the binaries under Rosetta 2),
through docker when `TACHYON_DOCKER=1` is set, and skipped otherwise
(`TACHYON_REQUIRE_RUN=1` turns the skip into a failure). Programs marked
`// SNAPSHOT` also have their assembly snapshotted.

The compiler targets x86-64 Linux by default when run on Linux and x86-64
macOS when run on macOS; pass `--target linux-x86_64|macos-x86_64` to choose.

WIP, stay tunned
