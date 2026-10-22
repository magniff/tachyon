# helloworld

The smallest vole program: one line of output and an exit status.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`
after `bootstrap/bootstrap.sh`):

```sh
volec main.vl -o helloworld && ./helloworld
```

`volec` compiles the program and links it with the system's C compiler
(`cc`, or `$VOLE_CC`). `-o helloworld.o` makes an object instead, and
`-o helloworld.s` assembly.

## Expected output

```text
Hello from vole!
```

## How it works

```tach
fn main() -> i32 {
    println("Hello from vole!");
    0
}
```

- `main` returns the process's exit status. Its last expression, `0`,
  written without a `;`, is the value of the body: there is no `return`.
  `fn main()` with no result type exits with 0 too.
- `"Hello from vole!"` is a `[u8]`, a slice of bytes (or a `str`, UTF-8
  text, where one is wanted). A literal needs no allocation; text that
  grows is built in a `Buf` or a `String`, on an allocator.
- `println` comes from the prelude, the part of `std` every module sees
  without a `use`. It prints anything with `Display` (numbers, slices,
  f-strings) and a newline; `print` leaves the newline out.

## Language features

- functions, the block's value as the result: `volec guide syntax`
- string literals as `[u8]` slices: `volec guide types`
- the prelude (`println`, `print`, `Vec`, `Option`, ...): `volec guide modules`
