# c-qsort

Sorting vole data with the C library's `qsort`, and searching it with
`bsearch`. The records are `#[repr(C)]` structs, so C sees exactly the
layout vole wrote, and the comparison functions are vole functions
with C's calling convention (`extern "C" fn`) that `qsort` calls back. A
small generic wrapper, `c_sort<T>`, sorts a slice of any element type
through C, and the same wrapper sorts plain `i32`s at the end.

## Build and run

From this folder (with `volec` on your `PATH`, or as
`../../target/volec` from a built tree):

```sh
volec main.vl -o c-qsort && ./c-qsort
```

`qsort`, `bsearch`, `strlen` and `strcmp` are in the C library every
program links with, so no extra flags are needed on macOS or Linux.

## Expected output

```
32 bytes per City, 7 cities

by population:
   1. Reykjavik    Iceland       139875    512.4/km2
   2. Oslo         Norway        709037   1561.8/km2
   3. Montevideo   Uruguay      1319108   6562.7/km2
   4. Lima         Peru        10092000   3776.5/km2
   5. Dhaka        Bangladesh  10278882  33547.3/km2
   6. Tokyo        Japan       13960000   6362.5/km2
   7. Lagos        Nigeria     15388000  13137.5/km2
by density, densest first:
   1. Dhaka        Bangladesh  10278882  33547.3/km2
   2. Lagos        Nigeria     15388000  13137.5/km2
   3. Montevideo   Uruguay      1319108   6562.7/km2
   4. Tokyo        Japan       13960000   6362.5/km2
   5. Lima         Peru        10092000   3776.5/km2
   6. Oslo         Norway        709037   1561.8/km2
   7. Reykjavik    Iceland       139875    512.4/km2
by name:
   1. Dhaka        Bangladesh  10278882  33547.3/km2
   2. Lagos        Nigeria     15388000  13137.5/km2
   3. Lima         Peru        10092000   3776.5/km2
   4. Montevideo   Uruguay      1319108   6562.7/km2
   5. Oslo         Norway        709037   1561.8/km2
   6. Reykjavik    Iceland       139875    512.4/km2
   7. Tokyo        Japan       13960000   6362.5/km2

found Oslo: 709037 people
found Lima: 10092000 people
no Atlantis
primes 2..19, sum 77
```

(The city figures are round illustrative numbers, not a census.)

## How it works

### The C side, imported

```tach
import "stdlib.h" as c;
import "string.h" as c;
```

`import "header.h" as c;` runs the system's C preprocessor on the header
and turns its declarations into vole ones under the name `c`: here
`c::qsort`, `c::bsearch`, `c::strlen`, `c::strcmp`. Every header of a
program shares one C module, so both imports use the same `c`. To see
what a header declares: `volec --emit-imports main.vl -o decls.vl`.
`qsort` arrives as

```tach
fn qsort(p0: *u8, p1: size_t, p2: size_t, p3: extern "C" fn(*u8, *u8) -> i32);
```

C's `void *` is `*u8`, `size_t` is `u64`, and the comparator is an
`extern "C" fn` pointer type.

### A struct C can read

```tach
#[repr(C)]
struct City { name: *u8, country: *u8, population: i64, area: f64 }
```

Vole's own structs have no promised layout. `#[repr(C)]` asks for
C's: fields in declaration order, C's padding and alignment, so an array
of `City` is exactly what a C `struct City[]` would be. `size_of(City)`
(32 here) is the element size `qsort` needs. The names are C strings,
`c"Lagos"`: NUL-terminated `*u8`s in read-only memory.

### Callbacks: `extern "C" fn`

```tach
extern "C" fn by_population(a: *u8, b: *u8) -> i32 {
    let x = unsafe { (*(a as *City)).population };
    let y = unsafe { (*(b as *City)).population };
    // not `x - y`: the difference of two i64 does not fit an i32
    if x < y { -1 } else if x > y { 1 } else { 0 }
}
```

Only an `extern "C" fn` can be a C callback: it has C's calling
convention and an unmangled symbol. A plain `fn` is a different type, and
a closure cannot be one at all (it has nowhere to keep what it
captures; C APIs that need state take a `void *` context, see
[c-mixed-build](../c-mixed-build/)). `qsort` passes pointers to two
elements as `const void *`; the callback casts them back to `*City` and
reads through them, which is unsafe: nothing checks that the pointers
really point at `City`s.

### A generic wrapper

```tach
unsafe fn c_sort<T>(items: [T], cmp: extern "C" fn(*u8, *u8) -> i32) {
    c::qsort(items.ptr as *u8, items.len() as u64, size_of(T) as u64, cmp);
}
```

A slice `[T]` is a pointer and a length (`items.ptr`, `items.len()`): with
`size_of(T)` that is all `qsort` needs, for any `T`. The wrapper is an
`unsafe fn` because its contract cannot be checked: `cmp` must read its
pointers as `T`s. Its callers say so with `unsafe { c_sort(cities[..],
by_population); }`. Passing `by_population` as a value is safe in
itself; what is unsafe is the reads through `*u8` inside it, which is
why each one sits in an `unsafe { }` block.

### bsearch with a key of another type

```tach
extern "C" fn name_key(key: *u8, element: *u8) -> i32 {
    let wanted = unsafe { *(key as *[u8]) };
    let name = unsafe { text((*(element as *City)).name) };
    sign(wanted.cmp(name))
}
```

`bsearch(key, base, n, size, cmp)` passes the key as the first argument
and an element as the second. The key does not have to be a `City`: here
it is the address of a vole slice (`&name as *u8`). C never looks
inside it, it only hands it back to the callback, so any vole value
works, `#[repr(C)]` or not. The comparison is byte order (`[u8]`'s `cmp`),
the same order `strcmp` gave `qsort`: `bsearch` needs the array sorted by
the order it searches with.

`find` turns C's "a pointer or NULL" into an `Option<City>`:

```tach
if hit == 0 as *u8 { None } else { Some(unsafe { *(hit as *City) }) }
```

### C strings to vole text

```tach
unsafe fn text(p: *u8) -> [u8] {
    p[0..c::strlen(p) as i64]
}
```

Slicing a raw pointer makes a `[u8]` view of the C string (without its
NUL), printable with f-strings. It is unchecked, hence `unsafe fn`, and
its comment states the contract the caller takes on.

### Printing

```tach
println(f"  {i + 1:>2}. {name:<12} {country:<10} {city.population:>9} {d:>8.1}/km2");
```

f-strings with widths (`>` right, `<` left) and a precision for floats
(`.1`); `cities.iter().enumerate()` numbers the rows.

## C interop rules in brief

- **Declaring C**: `import "header.h" as c;` (the system's own
  declarations) or an `extern "C" { fn name(...) -> T; }` block written by
  hand. Every call to C is `unsafe`.
- **Layout**: only `#[repr(C)]` structs, unions and enums have C's layout;
  give them to C by pointer or by value. Slices, tuples and plain structs
  are not FFI-safe in signatures (the compiler says so).
- **Callbacks**: `extern "C" fn` (not a plain `fn`, not a closure).
- **Pointers**: `void *` is `*u8`; cast to the real type to read. Reading
  through a raw pointer is `unsafe`; wrap it in a small function whose
  comment states the contract.
- **Strings**: `c"..."` is a NUL-terminated `*u8`; a `[u8]` slice has no
  NUL (pass `.ptr` and `.len()`, or copy it with a 0 after).
- **Linking**: `volec main.vl -o prog` links with `cc` and the C
  library; other libraries and C files go through an object (see
  [c-mixed-build](../c-mixed-build/) and [c-math](../c-math/)).

## Language features

- `import "stdlib.h" as c`, `extern "C" fn`, `#[repr(C)]`, `size_of(T)`:
  `volec guide c-interop`
- `unsafe fn` with a stated contract, raw pointer casts and dereferences:
  `volec guide unsafe`
- generic functions over `[T]`: `volec guide generics`
- f-strings with width, alignment and precision: `volec guide formatting`
- `iter().enumerate()`, `fold` with a closure: `volec guide iterators`,
  `volec guide closures`
- `Option` for "found or not": `volec guide conversions`

## Going further

- `std::sort` and `slice.sort_by(|a, b| ...)` sort in vole, with a
  closure and no `unsafe`; the C route is for code that already speaks
  `qsort`.
- `qsort_r` would let the comparator take a context pointer, but its
  argument order differs between macOS (BSD) and glibc, which is why this
  example does not use it.
