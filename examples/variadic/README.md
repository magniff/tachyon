# variadic

Calls C's `printf`, a variadic function, with an `i32`, an `f64`, and
both together.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o variadic && ./variadic
```

## Expected output

```text
Just a humble int 1
A fancy float 2.000000
These two together, friendship, hey! 1 and 2.000000
```

## How it works

A variadic C function is declared with `...` after its fixed parameters:

```tach
extern "C" {
    fn printf(format: *u8, ...) -> i32;
}
```

The variadic arguments are passed as C passes them, on each target's
convention (on aarch64-macos they go on the stack, on Linux in registers):
an `i32` for `%d`, an `f64` for `%f`, a `*u8` for `%s`, an `i64` for
`%ld`. The format must be a C string, NUL-terminated, which is what a
`c"..."` literal is:

```tach
let integer: i32 = 1;
let float = 2.0;
unsafe {
    printf(c"These two together, friendship, hey! %d and %f\n", integer, float);
}
```

The types must match the format, as in C: nothing checks them. Vole's
own printing (`println(f"{x}")`) is checked and needs no `unsafe`; use
`printf` when you are talking to C anyway.

## Language features

- variadic `extern "C"` functions: `volec guide c-interop`
- `c"..."` literals: `volec guide types`
- `unsafe` blocks: `volec guide unsafe`
