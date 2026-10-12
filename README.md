# The Tachyon Programming Language

A small systems language: structs, enums with `match`, methods, slices,
raw pointers, fixed arrays, tuples, function pointers, C interop
(`extern "C"`, `#[repr(C)]`), and expression-oriented control flow. The
compiler is written in tachyon itself.

```
extern "C" {
    fn printf(format: *u8, ...) -> i32;
}

enum Shape { Circle(f64), Rect(f64, f64), Empty }

impl Shape {
    fn area(self: Shape) -> f64 {
        match self {
            Shape::Circle(r) => 3.14159 * r * r,
            Shape::Rect(w, h) => w * h,
            Shape::Empty => 0.0,
        }
    }
}

fn main() -> i32 {
    let shapes: [Shape; 3] = [Shape::Circle(1.0), Shape::Rect(2.0, 3.5), Shape::Empty];
    let mut total = 0.0;
    for i in 0..3 {
        total += shapes[i].area();
    }
    let middle = shapes[1..];
    printf(c"%.2f %lu\n", total, middle.len);
    0
}
```

Bindings are immutable unless declared `mut`. The grammar, with the operator
precedence table and what is (and is not) guaranteed about layout and
calling conventions, is in [docs/grammar.md](docs/grammar.md).

## Getting a compiler

The compiler (`compiler/`) is written in tachyon, so the first one comes from
the release chain: the frozen Rust implementation, the seed (`seed/`),
builds release 0.1.0, each release builds the next, and the last one builds
HEAD. It runs on macOS (Apple silicon and Intel) and on x86-64 Linux.

On macOS, with the Xcode command line tools and Rust (rustup):

```
$ bootstrap/bootstrap.sh
...
compiler: target/tachyonc (tachyonc 0.4.0 (host: aarch64-macos))
```

On x86-64 Linux, with git, gcc (or clang) and the libc headers, and Rust
(rustup):

```
$ bootstrap/bootstrap.sh
...
compiler: target/tachyonc (tachyonc 0.4.0 (host: x86_64-linux))
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

The compiler optimizes: `-O2` (the default) replaces aggregates by scalars,
forwards memory across blocks, removes dead stores, turns `match` into jump
tables, inlines, moves invariant code
out of loops, propagates constants, numbers values and allocates
registers; `-O1` does the same without inlining and loop motion; `-O0` is
plain stack-machine code. `--emit-ir` shows the optimized IR. See
[docs/optimizer.md](docs/optimizer.md).

## Tests

```
$ tests/run.sh                       # the suite, with target/tachyonc, for the host
$ tests/run.sh -c path/to/tachyonc prog_
$ tests/run.sh -t x86_64-macos       # x86-64 on Apple silicon, under Rosetta
$ tests/run.sh -O 0                  # at another optimization level (0, 1, 2)
$ tests/abi/run.sh -n 150            # random C signatures, called both ways
$ tests/fuzz/run.sh -n 500           # random programs: -O0, -O1 and -O2 must agree
$ bench/run.sh                       # benchmarks against cc -O2
$ bootstrap/linux-check.sh           # the whole chain on x86-64 Linux, in docker
$ cd seed && cargo test              # the seed's own tests
```

## Layout

| | |
|---|---|
| `compiler/` | the tachyon compiler, in tachyon ([compiler/README.md](compiler/README.md)) |
| `examples/`, `tests/` | examples and the test suite of this release |
| `docs/` | the grammar, the optimizer, the release process and the roadmap |
| `bench/` | benchmarks (with C equivalents) and their runner |
| `bootstrap/` | the release chain (`releases.toml`), the script that replays it, and the Linux container check |
| `seed/` | the seed: the frozen Rust implementation, the root of the chain ([seed/README.md](seed/README.md)) |
