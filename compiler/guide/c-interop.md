# C interop

C compatibility is asked for explicitly and then exact. Tachyon's own
types and functions have no fixed layout or convention; `#[repr(C)]`
types and `extern "C"` functions have C's, for the target.

## Calling C

Import a header (its names are reached through the `as` name; every
header of a program shares one C module, so one name serves them all),
or declare the functions yourself. Every call is `unsafe`.

```tach
import "stdio.h" as c;
import "string.h" as c;

extern "C" {
    fn getenv(name: *u8) -> *u8;          // declared by hand
    #[link_name = "strlen"]
    fn c_length(s: *u8) -> u64;           // another name for a C symbol
}

fn main() -> i32 {
    let s = c"tachyon";
    let n = unsafe { c::strlen(s) } as i64;
    let home = unsafe { getenv(c"NO_SUCH_VARIABLE_HERE") };
    unsafe {
        c::printf(c"%s has %ld bytes, %d %.3f\n", s, n, home == 0 as *u8, 1.0 / 8.0);
        c::printf(c"%lu\n", c_length(c"abc"));
    }
    0
}
```
```out
tachyon has 7 bytes, 1 0.125
3
```

- `c"..."` is a NUL-terminated `*u8`, for C. A `[u8]` slice (`"..."`) is
  not terminated: pass `s.ptr` and `s.len` to C (`write(1, s.ptr,
  s.len as u64)`), or copy into a buffer with a 0 at the end.
- A C string to a slice: `unsafe { p[0..c::strlen(p) as i64] }`.
- Variadic functions (`printf`) take any FFI-safe value; `%ld` for `i64`,
  `%d` for `i32` and `bool`, `%f` for `f64` (and `f32`), `%s` for `*u8`.
- Types from C: `int` is `i32`, `long` is `i64`, `char *` and `void *`
  are `*u8`, `size_t` is `u64`, structs are `#[repr(C)]` structs, enums
  are integer types with constants. `tachyonc --emit-imports prog.tach
  -o decls.tach` shows what a program's headers declare.
- What headers cannot give: function-like macros, `static inline`
  functions, `errno` (call `__error()` on macOS, `__errno_location()` on
  Linux).
- `-I DIR` adds an include directory; `import "./mine.h" as c;` is
  relative to the importing file.

## Layout: #[repr(C)]

```tach
#[repr(C)]
struct Header { tag: u8, size: u32 }          // C's field order and padding

#[repr(C, packed)]
struct Packed { tag: u8, size: u32 }          // no padding

#[repr(C)]
union Bits { i: u32, f: f32 }                 // reading a field is unsafe

#[repr(u8)]
enum Kind { A = 1, B = 2 }                    // an enum with a u8 tag

fn main() -> i32 {
    let b = Bits { f: 1.0 };
    std::print_int(size_of(Header) + size_of(Packed) + size_of(Kind));
    print(" ");
    std::print_int(unsafe { b.i } as i64);
    println("");
    0
}
```
```out
14 1065353216
```

Also `#[repr(C, align(N))]` and `#[repr(C, packed(N))]`. A `#[repr(C)]`
enum with fields is C's struct of a tag and a union. Types in `extern
"C"` signatures must be FFI-safe: numbers, `bool`, pointers, `extern
"C" fn` pointers, `#[repr(C)]` types. Slices, tuples, plain structs and
plain `fn` pointers are rejected with a hint.

## C calling tachyon

`extern "C" fn` defines a function with C's convention and an unmangled
symbol; only such a function is a C callback (a plain `fn` is another
type).

```tach
import "stdlib.h" as c;

extern "C" fn by_value(a: *u8, b: *u8) -> i32 {
    let x = unsafe { *(a as *i32) };
    let y = unsafe { *(b as *i32) };
    if x < y { -1 } else if x > y { 1 } else { 0 }
}

fn main() -> i32 {
    let mut a: [i32; 5] = [4, 2, 5, 1, 3];
    unsafe { c::qsort(&a as *u8, 5, 4, by_value); }
    for x in a { std::print_int(x as i64); }
    println("");
    0
}
```
```out
12345
```

`extern "C" static mut COUNT: i64 = 0;` defines a static C can use.
`tachyonc --emit-header prog.tach -o prog.h` writes the C header of a
program's `extern "C"` functions and statics, with the `#[repr(C)]`
types they use.

## Building with C

`tachyonc prog.tach -o prog` links with `cc` (`$TACHYON_CC` instead).
For other libraries or C files, make an object and link it yourself:

```sh
tachyonc prog.tach -o prog.o && cc prog.o helper.c -o prog -lm
```

Reading stdin: `getchar()` from `stdio.h`, or `read(0, buf, n)` from
`unistd.h`, into a `Buf` or an array:

```tach
import "stdio.h" as c;
use std::Buf;

fn main() -> i32 {
    let mut line = Buf::new();
    defer line.free();
    loop {
        let ch = unsafe { c::getchar() };
        if ch < 0 || ch == '\n' as i32 { break; }
        line.push(ch as u8);
    }
    print("read ");
    std::print_int(line.len());
    println(" bytes");
    0
}
```
```out
read 0 bytes
```
