# Examples

Programs written in tachyon, one folder each: `main.tach` (and the
modules or C files it needs) and a `README.md` that says what the program
shows, how to build and run it, what it prints, and walks through the
interesting parts of the code.

## Build and run

Build the compiler once from the root of the repository
(`bootstrap/bootstrap.sh`, which leaves `target/tachyonc`), then, in an
example's folder:

```sh
../../target/tachyonc main.tach -o NAME && ./NAME
```

`tachyonc` compiles the program and links it with the system's C
compiler (`cc`, or `$TACHYON_CC`) and the C library. A program that
needs more (C's math library on Linux, its own C files) is compiled to
an object and linked with `cc`: `tachyonc main.tach -o NAME.o && cc
NAME.o -o NAME -lm`; the READMEs say when. Every
example builds and runs on macOS (Apple silicon) and Linux (x86-64 and
AArch64). New to the language? `tachyonc guide` is a tour of it in a few
pages, and `tachyonc guide TOPIC` goes into one area (the READMEs name
the topics).

Each example is a test case too: `tests/examples/NAME*.test` runs it
with its input and checks its output (`tests/run.sh example` runs them
all). `algorithms/` groups ten examples, one folder each; `tools/` holds
walkthroughs of the compiler's tools (query, edit, refactor), tested by
`tests/walkthrough/run.sh`.

## The examples

| example | what it shows | features |
|---|---|---|
| [helloworld](helloworld/) | the smallest program | `main`, `println`, `[u8]` text |
| [args](args/) | command-line arguments | `main(argc, argv)`, C strings to slices, `unsafe fn` |
| [factorial](factorial/) | factorials, recursive and folded | recursion, ranges as iterators, `fold`, f-strings |
| [floats](floats/) | the distance between two points | `f64`, methods, `extern "C"` `sqrt`, `{x:.6}` |
| [variadic](variadic/) | calling C's `printf` | variadic `extern "C"`, `c"..."` |
| [calc](calc/) | a calculator for lines of arithmetic | enums, `match`, a recursive-descent parser, `Result` and `?`, `impl Display` |
| [md5](md5/) | the MD5 digest of a file or stdin | arrays, wrapping `u32`, a streaming hash, `defer`, hex specs |
| [life](life/) | Conway's Game of Life in the terminal | `#[repr(C)]`, `ioctl`, `Vec` handles, ANSI colour through `Buf` |
| [httpd](httpd/) | an HTTP file server (`python -m http.server`) | sockets and `readdir` declared by hand, Linux and macOS layouts, modules, `defer` |
| [c-qsort](c-qsort/) | libc `qsort`/`bsearch` over `#[repr(C)]` structs with tachyon callbacks, a generic `c_sort<T>` | `import "stdlib.h"`, `extern "C" fn`, `#[repr(C)]`, `unsafe fn`, `size_of` |
| [c-libc-tour](c-libc-tour/) | `getenv`/`setenv`, `gmtime`/`localtime`/`strftime`/`mktime`, `mkdtemp`/`opendir`/`readdir`/`stat`: a small `ls -l` | system headers as `c`, C structs and constants, C strings, `defer`, `Option` at the boundary |
| [c-math](c-math/) | libm, and Simpson, adaptive Simpson, bisection and Newton checked against `erf`/`tgamma`/`cbrt` | `import "math.h"`, out-parameters, closures and `Fn`/`FnMut` generics, float specs, linking `-lm` |
| [c-mixed-build](c-mixed-build/) | a C ring buffer and hash linked into a tachyon program; C calls tachyon by pointer and by name | `import "./ring.h"`, `--emit-header`, `extern "C" static`, linking objects with `cc`, a safe wrapper type |
| [closures-iterators](closures-iterators/) | a log-file analyzer over stdin | closures capturing state, `Fn` bounds, your own `Iterator`, `map`/`filter`/`fold`/`zip`/`enumerate`/`collect`/`sort_by`, `HashMap` |
| [errors-and-results](errors-and-results/) | a config parser with layered typed errors; exits 1 with `Error: ...` on a bad config | `?`, `From`, `map_err`/`ok_or`, Option vs Result, `main -> Result`, `#[derive(Debug)]` |
| [traits-generics](traits-generics/) | a geometry and units library in modules: shapes, vectors, matrices, metres and feet | traits with defaults, bounds, associated types, `#[derive]`, operator traits, `From`/`Into`, enums instead of `dyn` |
| [formatting](formatting/) | a format-spec cheat sheet, an aligned table, Debug views, a hex dump | f-string specs, `Display`/`Debug` by hand and derived, `format`/`push_fmt`/`eprintln` |
| [algorithms](algorithms/) | ten classic algorithms with READMEs, timings and C comparisons | `tachyonc examples/algorithms/NAME/main.tach -o NAME && ./NAME` |
| [tools](tools/) | the agent toolset in action: eight tested walkthroughs (rename, split, rewrite, explore, fix errors, prove unchanged, conflicts) | see each README |
