# Types

| type | |
|---|---|
| `i8 i16 i32 i64 isize`, `u8 u16 u32 u64 usize` | integers; literals are `i64` unless the context or a suffix says |
| `f32`, `f64` | IEEE floats; literals are `f64` |
| `bool` | `true`, `false` |
| `()` | the unit type |
| `!` | never: `return`, `break`, `loop` without `break`, `fn f() -> !` |
| `(A, B)` | tuples: `t.0` (through a pointer too: `p.0`); `(x,)` has one element |
| `[T; N]` | an array, a value; `N` a constant expression |
| `[T]` | a slice: `.ptr` (a `*T`) and `.len` (an `i64`) |
| `*T` | a pointer (`*u8` is also C's `void *` and `char *`) |
| `fn(A, B) -> R` | a plain function value |
| `extern "C" fn(A) -> R` | a C function pointer, another type |
| `S`, `E`, `S<T>` | structs, enums, unions, their instances |
| `v2f64 v4f32 v2i64 v4i32 v8i16 v16i8` | SIMD vectors of 16 bytes |

## Numbers

Only widening converts implicitly (0.15: a narrower integer to a wider
one, `tachyonc guide conversions`); otherwise both sides of `+`, `==`,
`=` have one type, and `as` converts between numeric types (and `bool` to an integer,
fieldless enums to integers and back). An unsuffixed literal takes the
type the context needs (`let b: u8 = 7;`, `x + 1` with `x: u32`), and
must fit: `let b: u8 = 300;` is an error.

Every operation is defined, the same at every optimization level:

```tach
let max: i64 = 9223372036854775807;
let b: u8 = 250;
let s: u32 = 1;
std::print_int(max + 1); print(" ");                // wraps
std::print_int((b + 10) as i64); print(" ");        // u8 wraps: 4
std::print_int(10 / 0); print(" ");                 // 0
std::print_int(10 % 0); print(" ");                 // 10
std::print_int(-7 % 3); print(" ");                 // the sign of the dividend
std::print_int((s << 33) as i64); print(" ");       // the amount mod 32 for narrow types
std::print_int(1e30 as i64 - max); print(" ");      // float to int saturates
std::print_int(-1.9 as i64); print(" ");            // truncates
std::print_int((0.0 / 0.0) as i64);                 // NaN becomes 0
println("");
```
```out
-9223372036854775808 4 0 10 -1 2 0 -1 0
```

Floats are IEEE 754 without fast-math; `1.0 / 0.0` is infinity, and
`NaN != NaN`. There are no `MIN`/`MAX` constants, no `abs`, `pow` or
`sqrt` methods: write them, or call C's math functions
(`import "math.h" as m;`, `unsafe { m::sqrt(x) }`).

## Arrays and slices

```tach
let mut grid = [[0; 3]; 2];       // [[i64; 3]; 2]
grid[1][2] = 5;
let copy = grid;                  // arrays are values: copied whole
grid[0][0] = 1;
let row = grid[1][..];            // [i64]: a view of the array
let part = row[1..];              // checked: lo <= hi <= len
std::print_int(copy[0][0] + part.len + part[1]);
println("");
```
```out
7
```

Indexing (`a[i]`, any integer type) and slicing (`a[lo..hi]`, `a[..hi]`,
`a[lo..]`, `a[..]`) are checked: out of bounds, the program prints
`index out of bounds: index I, length N` and exits with 101. An array
has no `.len` field: `a.len()` (0.17), or slice it: `a[..].len`. A function taking `[T]` gets
`a[..]`, not `a`. A slice of a raw pointer, `p[0..n]`, is unchecked and
unsafe.

## References and pointers

`&place` makes a shared reference `&T`, `&mut place` an exclusive one
`&mut T` (0.17): both are checked (`tachyonc guide memory`), safe to read
and write through, kept in locals and fields. `*r` is the value, `r.f`
reaches a field (and `r.m()` calls a method) through it. A raw pointer
`*T` (from C, from a reference where a `*T` is expected, `0 as *T` for
null) is dereferenced only in `unsafe`. There is no pointer arithmetic:
index a raw pointer (`p[i]`, `&p[i]`) in unsafe code, or cast through
`i64`. On a reference to a Vec, a Buf or a slice, `p[i]` indexes the one
it points to, checked: safe through a reference, `unsafe` through a raw
pointer. A `*T` parameter (without `mut`) is still taken as `&mut T` in
0.17; `tachyonc fix --values` rewrites it.

```tach
struct Counter { n: i64 }

fn bump(c: &mut Counter) { c.n += 1; }   // a reference: safe

fn main() -> i32 {
    let mut c = Counter { n: 0 };
    bump(&mut c);
    let r = &mut c;                      // a reference in a local: safe
    r.n += 5;
    let p: *Counter = &mut c;            // a raw pointer: unsafe
    unsafe { p.n += 5; }
    std::print_int(c.n);
    println("");
    0
}
```
```out
11
```

## Enums as integers

```tach
#[repr(u8)]
enum Level { Low = 1, Mid = 5, High = 9 }

fn main() -> i32 {
    let l = Level::Mid;
    std::print_int(l as i64);
    if Level::Low < l { println(" above low"); }   // declaration order
    let back = 9 as Level;                         // checked: 4 as Level exits 101
    if back == Level::High { println("high"); }
    0
}
```
```out
5 above low
high
```

## Layout

`size_of(T)` and `align_of(T)` are constants. Tachyon's own types have
no guaranteed layout (field order, enum tags, slices); `#[repr(C)]`
gives C's. See `tachyonc guide c-interop`.

## SIMD vectors

`v4f32(a, b, c, d)`, `v4f32::splat(x)`, `v4f32::load(s, i)` (checked)
make vectors; `+ - *` work lane by lane on all six types, `/` on float
vectors, `& | ^` on integer ones; comparisons give a mask
(`m.select(a, b)`); `v.lane(i)`, `v.with_lane(i, x)`, `v.sum()`,
`v.store(s, i)`. They are not FFI-safe.

```tach
let xs: [f32; 4] = [1.0, 2.0, 3.0, 4.0];
let v = v4f32::load(xs[..], 0) * v4f32::splat(2.0);
std::print_int(v.sum() as i64);
println("");
```
```out
20
```
