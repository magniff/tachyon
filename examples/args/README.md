# args

Prints how many command-line arguments the program got, then each of
them, the program's own name first.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o args && ./args foo bar
```

## Expected output

```text
argc: 3
-- ./args
-- foo
-- bar
```

## How it works

`main` may take C's two parameters. `argv` is a pointer to `argc` C
strings, each a NUL-terminated `*u8`:

```tach
fn main(argc: i64, argv: **u8) -> i32 {
    println(f"argc: {argc}");
    for i in 0..argc {
        let arg = unsafe { c_bytes(argv[i]) };
        println(f"-- {arg}");
    }
    0
}
```

Indexing a raw pointer (`argv[i]`) is unchecked, so it is `unsafe`: the
compiler cannot know that `argv` holds `argc` pointers. A C string becomes
a vole slice, a pointer and a length, once its length is known; C's
`strlen` gives it, from the header `string.h`:

```tach
import "string.h" as c;

unsafe fn c_bytes(s: *u8) -> [u8] {
    s[0..c::strlen(s) as i64]
}
```

`c_bytes` is an `unsafe fn` because its argument must be a valid C string,
a promise its caller makes by calling it inside `unsafe { }`. The slice
`s[0..n]` of a raw pointer is how memory from C becomes a `[u8]`, which
the f-string `f"-- {arg}"` then prints as text.

## The same with std::cli

`argv` by hand is how a program reaches C's arguments. A program that
takes flags and options declares them instead, with `std::cli` (0.24),
which parses them and gives `--help` and the errors for bad arguments:
[cli](../cli/) is this program with a flag and two options, and no
`unsafe`.

## Language features

- `main(argc, argv)`, `**u8`: `volec guide types`
- `unsafe` blocks and `unsafe fn`: `volec guide unsafe`
- importing a C header, `c::strlen`: `volec guide c-interop`
- f-strings: `volec guide formatting`
- parsing flags and options instead: `volec guide cli`, [cli](../cli/)
