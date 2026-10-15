# helloworld

The smallest tachyon program: one line of output and an exit status.

## Build and run

From this folder (with `tachyonc` on your `PATH`, or `../../target/tachyonc`
after `bootstrap/bootstrap.sh`):

```sh
tachyonc main.tach -o helloworld && ./helloworld
```

`tachyonc` compiles the program and links it with the system's C compiler
(`cc`, or `$TACHYON_CC`). `-o helloworld.o` makes an object instead, and
`-o helloworld.s` assembly.

## Expected output

```text
Hello from tachyon!
```

## How it works

```tach
fn main() -> i32 {
    println("Hello from tachyon!");
    0
}
```

- `main` returns the process's exit status. Its last expression, `0`,
  written without a `;`, is the value of the body: there is no `return`.
  `fn main()` with no result type exits with 0 too.
- `"Hello from tachyon!"` is a `[u8]`, a slice of bytes. Tachyon has no
  `String` type: text is bytes, built with `std::Buf` when it grows.
- `println` comes from the prelude, the part of `std` every module sees
  without a `use`. It prints anything with `Display` (numbers, slices,
  f-strings) and a newline; `print` leaves the newline out.

## Language features

- functions, the block's value as the result: `tachyonc guide syntax`
- string literals as `[u8]` slices: `tachyonc guide types`
- the prelude (`println`, `print`, `Vec`, `Option`, ...): `tachyonc guide modules`
