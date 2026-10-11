# The seed: the Rust implementation of tachyon

This is the original tachyon compiler, written in Rust with a Cranelift
backend. It is the **seed** of the release chain and it is **frozen**: its
only job is to build tachyon 0.1.0, whose compiler is written in tachyon
(`../compiler`). New language features go into the tachyon compiler, never
here. See [../docs/releases.md](../docs/releases.md).

Everything below runs inside this directory (`cd seed`). The examples and
golden programs here are a frozen copy for the seed's own tests.

Targets: x86-64 Linux, x86-64 macOS and arm64 macOS (Apple Silicon).

In addition to the Rust toolchain you need a C compiler (`cc`, or whatever
`$CC` names) to link programs against libc.

```
$ cargo run -- run examples/helloworld.tach
Hello from tachyon!
```

## A taste

```
extern fn printf(format: *u8, ...) -> i32;

struct Point { x: i64, y: i64 }

const N: i64 = 10;

fn main() -> i64 {
    let mut sum = 0;
    for i in 0..N {
        if i % 3 == 0 { continue; }
        sum += i;
    }
    let p = Point { x: sum, y: -1 };
    let found = loop {
        if p.x > 20 { break 'y'; }
        break 'n';
    };
    printf(c"%ld %c\n", p.x, found as i32);
    0
}
```

Bindings are immutable unless declared `mut`. The full grammar, with the
operator precedence table, is in [docs/grammar.md](docs/grammar.md).

## The `tachyon` command

```
$ tachyon build examples/md5.tach -O              # an executable ./md5
$ tachyon build examples/md5.tach -o md5 --emit obj   # an object file (or --emit clif)
$ tachyon run -O examples/md5.tach < file         # build in a temp dir, run, forward the exit code
$ tachyon run examples/args.tach -- one two       # arguments after `--` go to the program
$ tachyon run --target macos-x86_64 examples/md5.tach   # x86-64 under Rosetta 2
$ tachyon check examples/httpd.tach               # report errors without generating code
$ tachyon clif -O examples/md5.tach               # Cranelift IR and machine code
```

From a checkout, use `cargo run --release -- <subcommand> ...`. The target
defaults to the host. Diagnostics go to stderr (coloured on a terminal;
`NO_COLOR` turns colour off). Exit codes: 1 for errors in the program or a
failed link, 101 for an internal compiler error, and for `run` the program's
own exit code.

## Code generation

The front end type checks a program and lowers it to tachyon's IR
(`src/lowering`). The backend (`src/backend`) turns that IR into a native
object file with [Cranelift](https://cranelift.dev), for `macos-aarch64`,
`macos-x86_64` and `linux-x86_64`, and `src/driver.rs` links it with the
system C compiler. Locals live in SSA values and registers. `-O` turns on
Cranelift's optimizer (GVN, LICM, constant folding, strength reduction).

## Testing

```
$ cargo test                                       # unit tests, CLI tests, CLIF snapshots, golden programs
$ cargo test --test run -- --nocapture             # golden programs with a per-configuration summary
$ TACHYON_RUN_FILTER=prog_ cargo test --test run   # only cases whose name contains "prog_"
$ TACHYON_TARGET=macos-x86_64 TACHYON_OPT=1 cargo test --test run   # one target, -O only
$ TACHYON_DOCKER=1 cargo test --test run           # run linux-x86_64 in a linux/amd64 container
$ cargo insta review                               # accept intended changes to generated CLIF
```

Golden programs live in `tests/run/*.tach` and state their expected output in
comments (`// EXPECT:`, `// EXIT:`, `// ARGS:`, `// STDIN:`, `// ERROR:`,
`// XFAIL:` for known bugs, `// XFAIL(macos-aarch64):` for one target;
see `tests/run.rs`). Each program is compiled, linked (the same way as
`tachyon build`) and run under every configuration: natively at `-O0` and
`-O` and, on Apple Silicon, for x86-64 as well. Configurations that cannot
run on the host are skipped (`TACHYON_REQUIRE_RUN=1` turns the skip into a
failure). Programs marked `// SNAPSHOT` also have their CLIF snapshotted, and
`tests/cranelift.rs` builds every program for every target on any host.
`tests/cli.rs` exercises the `tachyon` command itself.

`tachyon tokens <file>` (hidden) prints the token dump that
`tachyonc --tokens` reproduces.
