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
| `[T]` | a slice: `.len()` (an `i64`); `.ptr` (a `*T`) for C |
| `*T` | a pointer (`*u8` is also C's `void *` and `char *`) |
| `fn(A, inout B) -> R` | a plain function value; a parameter's convention is part of its type |
| `let T`, `inout T` | an access, in a field (`q: inout Query`) or a function type (`guide memory`) |
| `extern "C" fn(A) -> R` | a C function pointer, another type |
| `S`, `E`, `S<T>` | structs, enums, unions, their instances |
| `type X = distinct T` | a type of its own with T's representation (0.18) |
| `std::NonNull<T>` | a `*T` that is never null; `Option<NonNull<T>>` is one pointer |
| `v16u8 v8i16 v4f32 v2f64 ...` | SIMD vectors: 8, 16 or 32 bytes of signed, unsigned or float lanes (0.19: `guide arch`) |

## Numbers

Only widening converts implicitly (0.15: a narrower integer to a wider
one, `volec guide conversions`); otherwise both sides of `+`, `==`,
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
var grid = [[0; 3]; 2];           // [[i64; 3]; 2]
grid[1][2] = 5;
let copy = grid;                  // arrays are values: copied whole
grid[0][0] = 1;
let row = grid[1][..];            // [i64]: a view of the array
let part = row[1..];              // checked: lo <= hi <= len
std::print_int(copy[0][0] + part.len() + part[1]);
println("");
```
```out
7
```

Indexing (`a[i]`, any integer type) and slicing (`a[lo..hi]`, `a[..hi]`,
`a[lo..]`, `a[..]`) are checked: out of bounds, the program prints
`index out of bounds: index I, length N` and exits with 101. An array
has its length too: `a.len()` (0.17), or slice it: `a[..].len()`. A function taking `[T]` gets
`a[..]`, not `a`. A slice of a raw pointer, `p[0..n]`, is unchecked and
unsafe.

## Accesses and pointers

An *access* is how a function reaches a value it does not own: a let
parameter (read-only), an `x: inout T` parameter (exclusive, writes
reach the caller, passed as `&place`), an `inout r = &place;` local, an
access field (`q: inout Query`). All are checked (`volec guide
memory`), safe, and used as the value itself: `r.n += 5`, `r = v`, `n +
1`, with no `*`. A raw pointer `*T` (from C, `&place` where a `*T` is
expected, `0 as *T` for null) is dereferenced only in `unsafe`. There is
no pointer arithmetic: index a raw pointer (`p[i]`, `&p[i]`) in unsafe
code, or cast through `i64`. Through an access to a Vec, a Buf or a
slice, `p[i]` is that element, checked; through a raw pointer it is
`unsafe`.

```tach
struct Counter { n: i64 }

fn bump(c: inout Counter) { c.n += 1; }  // an access: safe

fn main() -> i32 {
    var c = Counter { n: 0 };
    bump(&c);
    inout r = &c;                        // an inout local: safe
    r.n += 5;
    let p = &c as *Counter;              // a raw pointer: unsafe
    unsafe { p.n += 5; }
    std::print_int(c.n);
    println("");
    0
}
```
```out
11
```

## Distinct types

`type NodeId = distinct i64;` is a new type, as Go's defined types are:
T's representation and ABI, but not interchangeable with T. `as`
converts both ways for free (`id as i64`, `n as NodeId`); a literal is
the one implicit conversion. T's operators work between two values of
the type, or one and a literal (`a + 1`, `m / 2.0`, `a < b` is a bool);
mixing it with T is `distinct.mix`, whose `try:` is the `as` to write
(`volec fix --suggested` writes them all). It has T's Eq, Ord, Hash,
Debug, Display and Clone (`Vec<NodeId>` sorts, prints, is a HashMap key)
and T's literal patterns, but none of T's methods (`distinct.method`):
`impl NodeId { .. }` adds its own. `type Id<T> = distinct i64;` makes
`Id<Node>` and `Id<Edge>` two types. T is plain: numbers, bool, raw
pointers, and structs, tuples and arrays of them; not owned (a Vec, a
type with a Drop impl) nor a view (a slice, an access field) (`distinct.kind`).

```tach
type NodeId = distinct i64;
type Meters = distinct f64;

impl NodeId {
    fn next(self) -> NodeId { self + 1 }
}

fn main() {
    let a: NodeId = 3;
    let b = a.next() * 2;              // NodeId
    let x: f64 = 0.5;
    let d: Meters = 2.0;
    let e = d + x as Meters;           // `d + x` is distinct.mix
    println(f"{b} {a < b} {e} {b as i64 + 1}");
}
```
```out
8 true 2.5 9
```

`std::NonNull<T>` is std's `distinct *T` that is never null:
`NonNull::new(p)` is `Some` unless p is null, `p as NonNull<T>` is
checked (a null p exits 101: `null pointer made NonNull`), `p.as_ptr()`
(or `p as *T`) is the raw pointer, and dereferencing stays `unsafe`.
`Option<NonNull<T>>` is one pointer, `None` the null one, so it is the
field type of a nullable link and C's nullable pointer in an `extern
"C"` signature; a C header's `_Nonnull` pointers import as NonNull (a
result is C's promise, which the unsafe call vouches for). `_Nonnull`
is clang's nullability qualifier: imports read headers as the system's
C compiler does, so they see it where that compiler is clang (macOS);
with gcc (most Linux systems) a header has no such qualifier and its
pointers import as `*T`. Any `*T` has `p.is_null()`.

```tach
use std::NonNull;

struct Node { value: i64, next: Option<NonNull<Node>> }

fn main() {
    let b = Node { value: 2, next: None };
    let a = Node { value: 1, next: NonNull::new(&b) };
    var total = 0;
    var cur = NonNull::new(&a);
    while let Some(p) = cur {
        unsafe {
            total += (*p.as_ptr()).value;
            cur = (*p.as_ptr()).next;
        }
    }
    println(f"{total} {size_of(Option<NonNull<Node>>)}");
}
```
```out
3 8
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

`size_of(T)` and `align_of(T)` are constants. Vole's own types have
no guaranteed layout (field order, enum tags, slices); `#[repr(C)]`
gives C's. See `volec guide c-interop`.

## SIMD vectors

`v4f32(a, b, c, d)`, `v4f32::splat(x)`, `v4f32::load(s, i)` (checked)
make vectors; `+ - *` work lane by lane on all six types, `/` on float
vectors, `& | ^` on integer ones; comparisons give a mask
(`m.select(a, b)`); `v.lane(i)`, `v.with_lane(i, x)`, `v.sum()`,
`v.store(s, i)`. They are not FFI-safe.

| bytes | signed | unsigned (0.19) | float |
|---|---|---|---|
| 8 (0.19) | `v8i8 v4i16 v2i32 v1i64` | `v8u8 v4u16 v2u32 v1u64` | `v2f32 v1f64` |
| 16 | `v16i8 v8i16 v4i32 v2i64` | `v16u8 v8u16 v4u32 v2u64` | `v4f32 v2f64` |
| 32 (0.19) | `v32i8 v16i16 v8i32 v4i64` | `v32u8 v16u16 v8u32 v4u64` | `v8f32 v4f64` |

An unsigned vector compares unsigned, and its mask is itself (a lane all
ones or 0); 32-byte vectors are two registers where the CPU has no wider
ones. `T::from_bits(v)` reinterprets a vector of the same size, with no
instruction. The CPU's own instructions on them (NEON, SSE, AVX2, CRC,
AES, SHA) are `std::arch`'s: `volec guide arch`.

```tach
let xs: [f32; 4] = [1.0, 2.0, 3.0, 4.0];
let v = v4f32::load(xs[..], 0) * v4f32::splat(2.0);
std::print_int(v.sum() as i64);
println("");
```
```out
20
```
