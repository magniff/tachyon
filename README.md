# The Tachyon Programming Language

A small systems language: structs, raw pointers, fixed arrays, tuples,
function pointers, C interop, and expression-oriented control flow. The
compiler is written in tachyon itself.

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

Bindings are immutable unless declared `mut`. The grammar, with the operator
precedence table, is in [docs/grammar.md](docs/grammar.md).

## Getting a compiler

The compiler (`compiler/`) is written in tachyon, so the first one comes from
the release chain: the frozen Rust implementation, the seed (`seed/`),
builds release 0.1.0, each release builds the next, and the last one builds
HEAD. It runs on macOS (Apple silicon and Intel) and on x86-64 Linux.

On macOS, with the Xcode command line tools and Rust (rustup):

```
$ bootstrap/bootstrap.sh
...
compiler: target/tachyonc (tachyonc 0.1.0 (host: aarch64-macos))
```

On x86-64 Linux, with git, gcc (or clang) and the libc headers, and Rust
(rustup):

```
$ bootstrap/bootstrap.sh
...
compiler: target/tachyonc (tachyonc 0.1.0 (host: x86_64-linux))
```

Every step is checked: each compiler must compile itself to identical
output (the fixpoint) and pass its release's test suite. See
[docs/releases.md](docs/releases.md) for the versions, the release process
and the rules.

## Using it

```
$ target/tachyonc examples/md5.tach -o md5.s && cc -o md5 md5.s -lm
$ ./md5 < file
```

The compiler emits assembly for the host (`--target aarch64-macos`,
`x86_64-linux` or `x86_64-macos` picks another), which `cc` assembles and
links; on macOS, give `cc` the matching `-arch arm64` or `-arch x86_64`
when it is not the host's. Several files form one program:
`tachyonc a.tach b.tach -o out.s`.

## Tests

```
$ tests/run.sh                       # the suite, with target/tachyonc, for the host
$ tests/run.sh -c path/to/tachyonc prog_
$ tests/run.sh -t x86_64-macos       # x86-64 on Apple silicon, under Rosetta
$ bootstrap/linux-check.sh           # the whole chain on x86-64 Linux, in docker
$ cd seed && cargo test              # the seed's own tests
```

## Layout

| | |
|---|---|
| `compiler/` | the tachyon compiler, in tachyon ([compiler/README.md](compiler/README.md)) |
| `examples/`, `tests/` | examples and the test suite of this release |
| `docs/` | the grammar, and the release process |
| `bootstrap/` | the release chain (`releases.toml`), the script that replays it, and the Linux container check |
| `seed/` | the seed: the frozen Rust implementation, the root of the chain ([seed/README.md](seed/README.md)) |
