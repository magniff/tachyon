# floats

The distance between two points in space: `f64` arithmetic, a method on
a struct, and `sqrt` from C's math library.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o floats && ./floats
```

On Linux, C's math functions are in a library of their own, `libm`:
`volec` links it because the program calls `sqrt`.

## Expected output

```text
1.732051
```

## How it works

A C function can be declared by hand in an `extern "C"` block, with
vole's types for C's (`double` is `f64`):

```tach
extern "C" {
    fn sqrt(x: f64) -> f64;
}
```

Calling it is `unsafe`, as every call into C is: the compiler cannot
check what C does. The method takes `self` by value (`self: Point`, a
copy), which suits a small struct of three floats:

```tach
fn distance(self: Point, other: Point) -> f64 {
    let dx = self.x - other.x;
    let dy = self.y - other.y;
    let dz = self.z - other.z;
    unsafe { sqrt(dx * dx + dy * dy + dz * dz) }
}
```

The result is printed with six decimals, as C's `printf("%f")` would:

```tach
println(f"{a.distance(b):.6}");
```

Without a precision, an f-string prints the shortest text that reads back
as the same float (`1.7320508075688772`).

## Language features

- `f64`, float literals: `volec guide types`
- structs and methods, `self` by value: `volec guide syntax`
- `extern "C"` declarations, `unsafe` calls: `volec guide c-interop`
- format specs (`:.6`): `volec guide formatting`
