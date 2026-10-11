# Releases and the bootstrap chain

The tachyon compiler is written in tachyon. To build it on a machine that
has no tachyon compiler yet, the chain of releases is replayed from its root:

```
stage0 (Rust)  ──builds──▶  1.0.0  ──builds──▶  next release  ──▶ ... ──▶  HEAD
```

- **stage0** is the original Rust implementation (`stage0/`, Cranelift
  backend). It is frozen: it lives in the tree of `v1.0.0`, its toolchain is
  pinned (`stage0/rust-toolchain.toml`, `stage0/Cargo.lock`), and it only
  ever has to build release 1.0.0.
- **Every release** is a git tag (`v1.0.0`, `v1.1.0`, ...) whose tree is
  self-contained: the compiler for that release (`compiler/`), its examples
  (`examples/`), its test suite (`tests/`), the documentation of its language
  (`docs/`), and the chain tooling (`bootstrap/`).
- **Each release is built by the previous one**, and checked: it must reach
  the fixpoint (compiled by itself, it emits exactly what its first build
  emits) and pass its own test suite.

`bootstrap/releases.toml` lists the releases in order, with the tag, where
the compiler's source is, what builds it, how its binary is invoked, where
its test runner is and which hosts it runs on. `bootstrap/bootstrap.sh`
replays the chain.

## Versions

| release | tag | built by | hosts | introduced |
|---|---|---|---|---|
| stage0 | (in `v1.0.0`'s tree, `stage0/`) | Rust 1.98.0 | macOS arm64/x86-64, Linux x86-64 | the language and its Rust implementation |
| 1.0.0 | `v1.0.0` | stage0 | macOS arm64 | the compiler in tachyon: the whole stage0 language, AArch64 macOS assembly, a test suite run without cargo |

Add a row here, and an entry to `bootstrap/releases.toml`, for every release.

## Semantic versioning

The version is about the **language** the compiler accepts:

- **patch** (1.0.1): fixes; every program that compiled still compiles and
  means the same.
- **minor** (1.1.0): new features; every program the previous release
  accepted is still accepted with the same meaning.
- **major** (2.0.0): a breaking language change (something that used to
  compile is rejected or means something else). The release's own compiler
  source still has to be accepted by the previous release (the release
  rule below), so a breaking change is introduced in two steps: the release
  that makes it is written in the old language, and the next one may use
  the new one.

## The release rule

**The compiler source of a release may only use language features that the
previous release's binary supports.** The binary of release N-1 is what
builds release N on a new machine; if N's source used a feature N-1 does not
have, the chain breaks.

A new feature is therefore adopted in two releases:

1. Implement the feature in the compiler, keeping the compiler's own source
   in the old language. Add tests for it to the suite. Cut a release.
2. Only after that release exists may the compiler's source use the feature
   (in the next release).

## Cutting a release

Say the last release is 1.0.0 and you have implemented a feature on main.

1. Check the source rule: the compiler in `compiler/src` must still build
   with the previous release:
   ```
   $ bootstrap/bootstrap.sh            # builds 1.0.0, then HEAD with it
   ```
2. Add the tests for the new behaviour to `tests/` (`tests/run/*.tach` with
   `// EXPECT:` ... directives; see `tests/run.sh`), and examples if useful.
   Update `docs/grammar.md` for language changes.
3. Bump the version string in `compiler/src/90_main.tach` (`version()`).
4. Add the release to `bootstrap/releases.toml`:
   ```toml
   [[release]]
   version = "1.1.0"
   tag = "v1.1.0"
   compiler = "compiler/src"
   built_by = "1.0.0"
   cli = "tachyonc-v1"
   tests = "tests/run.sh"
   hosts = ["darwin-arm64"]
   summary = "What 1.1.0 introduced."
   ```
   and a row to the table above.
5. Run the whole chain with the new entry, in working-tree mode (the tag
   does not exist yet, so the new release is the working tree):
   ```
   $ bootstrap/bootstrap.sh --worktree --dev
   ```
   Then commit, and tag the commit: `git tag v1.1.0`. From now on,
   `bootstrap/bootstrap.sh` builds 1.0.0, then 1.1.0 from its tag, then
   HEAD.
6. Now (and not before) the compiler's source may use the new feature.

If a release changes how its binary is invoked or what it emits (another
command line, another target), give it a new `cli` value and teach
`compile_with` in `bootstrap/bootstrap.sh` about it; the script keeps every
interface that a release in the chain uses.

## Building and testing

With a compiler binary at hand (`target/tachyonc`, as `bootstrap.sh` leaves
it):

```
$ target/tachyonc compiler/src/*.tach -o tachyonc.s     # the compiler, by itself
$ clang -arch arm64 -o tachyonc tachyonc.s
$ tests/run.sh -c ./tachyonc                            # the test suite
$ tests/run.sh -c ./tachyonc prog_                      # only cases named *prog_*
```

`tests/run.sh` is a POSIX shell script: it needs the compiler and clang,
not cargo. Its directives (`// EXPECT:`, `// EXIT:`, `// ARGS:`,
`// STDIN:`, `// ERROR:`, `// XFAIL:`) are described at its top.

stage0 keeps its own tests, run with cargo:

```
$ cd stage0 && cargo test
```

## The whole chain on a new machine

You need git, a Rust toolchain (rustup; the pinned 1.98.0 is installed on
first use) and clang (on macOS: the Xcode command line tools). Then:

```
$ git clone <repository> tachyon && cd tachyon
$ git fetch --tags
$ bootstrap/bootstrap.sh
```

This extracts `v1.0.0`, builds stage0 from its `stage0/` with cargo, builds
1.0.0 with stage0, checks 1.0.0's fixpoint, runs 1.0.0's test suite, does the
same for every later release, and finally for HEAD. It prints a summary and
leaves the HEAD compiler in `target/tachyonc`.

Built releases are cached in `target/bootstrap/<tag>-<commit>`; a rerun only
rebuilds HEAD. Options:

```
--until 1.0.0      stop after a release: a from-scratch build of any release
--worktree         build the working tree instead of HEAD in the last step
--dev              before the tags exist: missing release tags are skipped and
                   stage0 comes from the working tree
--stage0-bin PATH  use an existing stage0 binary
--clean            empty the cache first
--out PATH         also copy the final compiler to PATH
```

The script fails early, with a message, on a host that a release in the
chain does not run on (today: anything but macOS on arm64). Supporting
another host means a release whose backend targets it, built by a release
that runs on the new host, or cross-compiled assembly from one that does.
