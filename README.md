# The Tachyon Programming Language

Targets: x86-64 Linux, x86-64 macOS and arm64 macOS (Apple Silicon).

In addition to the Rust toolchain you need a C toolchain (`cc`/`clang` or
`gcc`) to link the object file against libc.

```
$ ./tachyon.sh run examples/helloworld.tach
[1/2] tachyon  examples/helloworld.tach → /tmp/tmp.9c6fgQIp8U/helloworld.o  (macos-aarch64)
[2/2] clang  /tmp/tmp.9c6fgQIp8U/helloworld.o → /tmp/tmp.9c6fgQIp8U/helloworld.bin  (libc)
running: examples/helloworld.tach
Hello from tachyon!
```

## Code generation

The front end lowers a program to tachyon's IR (`src/lowering`). The backend
(`src/backend`) turns that IR into a native object file with
[Cranelift](https://cranelift.dev), for `macos-aarch64`, `macos-x86_64` and
`linux-x86_64`. Locals live in SSA values and registers. `-O` turns on
Cranelift's optimizer (GVN, LICM, constant folding, strength reduction).

```
$ ./tachyon.sh run -O examples/factorial.tach                 # optimized, native
$ ./tachyon.sh run --target macos-x86_64 examples/md5.tach    # x86-64 under Rosetta 2
$ ./tachyon.sh build examples/md5.tach -o md5
$ target/release/tachyon --emit clif -O -i examples/md5.tach -o md5.clif   # inspect CLIF and machine code
```

The target defaults to the host.

## Testing

```
$ cargo test                                       # unit tests, CLIF snapshots, golden programs
$ cargo test --test run -- --nocapture             # golden programs with a per-configuration summary
$ TACHYON_RUN_FILTER=prog_ cargo test --test run   # only cases whose name contains "prog_"
$ TACHYON_TARGET=macos-x86_64 TACHYON_OPT=1 cargo test --test run   # one target, -O only
$ TACHYON_DOCKER=1 cargo test --test run           # run linux-x86_64 in a linux/amd64 container
$ cargo insta review                               # accept intended changes to generated CLIF
```

Golden programs live in `tests/run/*.tach` and state their expected output in
comments (`// EXPECT:`, `// EXIT:`, `// ARGS:`, `// STDIN:`, `// ERROR:`,
`// XFAIL:` for known bugs, `// XFAIL(macos-aarch64):` for one target;
see `tests/run.rs`). Each program is compiled, linked and run under every
configuration: natively at `-O0` and `-O` and, on Apple Silicon, for x86-64
as well. Configurations that cannot run on the host are skipped
(`TACHYON_REQUIRE_RUN=1` turns the skip into a failure). Programs marked
`// SNAPSHOT` also have their CLIF snapshotted, and `tests/cranelift.rs`
builds every program for every target on any host.

WIP, stay tunned
