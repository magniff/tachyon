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
the release chain: the frozen Rust implementation (`stage0/`) builds release
1.0.0, each release builds the next, and the last one builds HEAD. On macOS
with Apple Silicon, with git, a Rust toolchain and clang:

```
$ bootstrap/bootstrap.sh
...
compiler: target/tachyonc (tachyonc 1.0.0 (aarch64-apple-darwin))
```

Every step is checked: each compiler must compile itself to identical
output (the fixpoint) and pass its release's test suite. See
[docs/releases.md](docs/releases.md) for the versions, the release process
and the rules.

## Using it

```
$ target/tachyonc examples/md5.tach -o md5.s && clang -arch arm64 -o md5 md5.s
$ ./md5 < file
```

Several files form one program: `tachyonc a.tach b.tach -o out.s`.

## Tests

```
$ tests/run.sh                       # the suite, with target/tachyonc
$ tests/run.sh -c path/to/tachyonc prog_
$ cd stage0 && cargo test            # stage0's own tests
```

## Layout

| | |
|---|---|
| `compiler/` | the tachyon compiler, in tachyon ([compiler/README.md](compiler/README.md)) |
| `examples/`, `tests/` | examples and the test suite of this release |
| `docs/` | the grammar, and the release process |
| `bootstrap/` | the release chain (`releases.toml`) and the script that replays it |
| `stage0/` | the frozen Rust implementation, the root of the chain ([stage0/README.md](stage0/README.md)) |
