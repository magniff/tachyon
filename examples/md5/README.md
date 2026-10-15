# md5

The MD5 digest (RFC 1321) of a file, or of stdin, printed in hex like
`md5sum`. Fixed-size arrays, `u32` arithmetic that wraps, a streaming
hash state, and the C library's `open` and `read`.

## Build and run

From this folder (with `tachyonc` on your `PATH`, or `../../target/tachyonc`):

```sh
tachyonc main.tach -o md5
printf abc | ./md5
./md5 README.md          # a file
```

## Expected output

```text
900150983cd24fb0d6963f7d28e17f72
```

for `abc`; `d41d8cd98f00b204e9800998ecf8427e` for empty input. The result
agrees with `md5sum` (the Linux checks of the bootstrap compare them on 3
MB of random bytes), and the benchmarks (`bench/run.sh`) time it against
the same program in C.

## How it works

**Tables as statics.** The 64 round constants and shifts are arrays of
`u32`, known at compile time:

```tach
static K: [u32; 64] = [0xd76aa478, 0xe8c7b756, ...];
```

**Arithmetic that wraps.** MD5 is defined modulo 2^32, and tachyon's
integers wrap on overflow (it is defined, never undefined behaviour), so
`f + a + K[i] + m[g]` on `u32`s is MD5's addition as written in the RFC.

**A streaming state.** `Md5` keeps the four state words, the bytes of an
incomplete 64-byte block, and the total length; `update` takes any number
of bytes, and `finish` pads the message and returns the digest as a
`[u8; 16]` (an array, a value: returned by copy):

```tach
struct Md5 { state: [u32; 4], block: [u8; 64], used: i64, total: u64 }

impl Md5 {
    fn update(self: *Md5, data: [u8]) { ... }
    fn finish(self: *Md5) -> [u8; 16] { ... }
}
```

Methods take `self: *Md5`, a pointer, to change the state in place;
`hash.update(...)` passes `&hash` itself.

**Slices of an array.** `compress` gets each block as a slice,
`data[at..at + 64]`, a view (pointer and length) into the bytes read: no
copy. Indexing and slicing are bounds-checked.

**Reading through C.** The file is read 64 KB at a time with the C
library's `read`, declared by hand; `defer` closes the file whatever
path `main` leaves by:

```tach
defer if fd != 0 { unsafe { close(fd); } };
loop {
    let n = unsafe { read(fd, &chunk as *u8, 65536) };
    if n <= 0 { break; }
    hash.update(chunk[..n]);
}
```

**Hex output.** Each byte is two hex digits; the format spec `02x` pads
with a zero to a width of 2:

```tach
for byte in hash.finish() {
    hex.push_fmt(f"{byte:02x}");
}
```

## Language features

- fixed-size arrays, slices, `u32`/`u64` and wrapping arithmetic: `tachyonc guide types`
- statics, structs, methods on `*Self`: `tachyonc guide syntax`
- `defer`: `tachyonc guide memory`
- `extern "C"` and `unsafe` calls: `tachyonc guide c-interop`
- hex format specs, `push_fmt`: `tachyonc guide formatting`
