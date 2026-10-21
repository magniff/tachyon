# c-math

Numerical methods in tachyon, checked against the C math library
(libm): composite and adaptive Simpson integration, bisection and
Newton's method for roots. The algorithms are generic over the function
they work on (`F: Fn(f64) -> f64`), so they take tachyon closures, and
libm's functions go in through closures too. The results print with
f-strings; libm's out-parameter functions (`frexp`, `modf`) show how C
returns a second value through a pointer.

## Build and run

From this folder (with `tachyonc` on your `PATH`, or as
`../../target/tachyonc` from a built tree).

```sh
tachyonc main.tach -o c-math && ./c-math
```

On Linux libm is a library of its own, apart from libc: `tachyonc` links
it (`-lm`) because the program calls its functions. Other libraries and
C files go on the same command line (`tachyonc main.tach helper.c -l png
-o prog`): see [c-mixed-build](../c-mixed-build/).

## Expected output

```
== libm
sqrt(2)      = 1.414213562373
cbrt(-27)    = -3.000000000000
hypot(3, 4)  = 5.000000000000
4 atan(1)    = 3.141592653590
exp(1)       = 2.718281828459
log10(1e6)   = 6.000000000000
pow(2, 0.5)  = 1.414213562373
tgamma(5)    = 24.000000000000  (4!)
floor(-2.5)  = -3.0, ceil(-2.5) = -2.0, round(-2.5) = -3.0
frexp(48)    = 0.7500 * 2^6
modf(pi)     = 3.0 + 0.141592653590
== integration
Simpson on sin over [0, pi] (exactly 2): the error / 16 per doubling
  n =  4  2.004559754984  error  4559754.984e-9
  n =  8  2.000269169948  error   269169.948e-9  ratio 16.9
  n = 16  2.000016591048  error    16591.048e-9  ratio 16.2
  n = 32  2.000001033369  error     1033.369e-9  ratio 16.1
  n = 64  2.000000064530  error       64.530e-9  ratio 16.0
P(|Z| < 2)  = 0.954499736104  erf: 0.954499736104  agree: true
Gamma(4.5)  = 11.6317283966  tgamma: 11.6317283966  agree: true
evaluations: 1961 for P, 5653 for Gamma (Simpson with n = 64: 65)
== roots
bisection: cos x = x at 0.7390851332 after 40 steps
bisection: x^2 + 1 has no sign change on [-1, 1]
Newton on x^3 = 2, from 1:
  step 1: 1.333333333333333
  step 2: 1.263888888888889
  step 3: 1.259933493449977
  step 4: 1.259921050017770
  step 5: 1.259921049894873
  step 6: 1.259921049894873
cbrt(2): Newton 1.259921049894873, libm 1.259921049894873, agree: true
Newton on x^2 = 4 from 0: None
```

## How it works

### libm through its header

```tach
import "math.h" as c;

println(f"sqrt(2)      = {c::sqrt(2.0):.12}");
```

`import "math.h" as c;` declares libm's functions as `c::sqrt`,
`c::tgamma`, ... with C's `double` as `f64`. A call to C is unsafe, so
the block of calls sits in one `unsafe { }`; an f-string hole can hold
any expression, a C call included, and `:.12` prints twelve decimals.
`round(-2.5)` is `-3`: C rounds halves away from zero.

Object-like macros that are numbers come in as constants:
`const PI: f64 = c::M_PI;`. Function-like macros (`isnan(x)` on some
systems) and `static inline` functions do not; call a real function
instead.

### Out-parameters

```tach
var exponent: i32 = 0;
let mantissa = unsafe { c::frexp(48.0, &exponent) };
println(f"frexp(48)    = {mantissa:.4} * 2^{exponent}");
```

C functions that return two values write the second through a pointer
(`int *exp`). `&exponent` is the address of a tachyon local, a `*i32`,
valid for the call.

### Algorithms generic over the function

```tach
fn simpson<F: Fn(f64) -> f64>(f: F, a: f64, b: f64, n: i64) -> f64 {
    let h = (b - a) / n as f64;
    var sum = f(a) + f(b);
    for i in 1..n {
        let x = a + i as f64 * h;
        sum += if i % 2 == 1 { 4.0 * f(x) } else { 2.0 * f(x) };
    }
    sum * h / 3.0
}
```

A parameter `f: F` with the bound `F: Fn(f64) -> f64` takes a closure or
a plain function; each call site gets its own copy of `simpson` with the
closure inlined, so there is no indirect call per evaluation. libm's
functions go in wrapped in closures, which also hold the `unsafe`:

```tach
let sin = |x: f64| unsafe { c::sin(x) };
let value = simpson(sin, 0.0, PI, n);
```

The convergence table shows Simpson's order: each doubling of `n`
divides the error by about 16 (the error goes as the 4th power of the
step).

### Adaptive Simpson and capturing closures

```tach
let x = 4.5;
let integrand = |t: f64| unsafe { c::pow(t, x - 1.0) * c::exp(-t) };
var gamma_calls = 0;
let gamma = adaptive(integrand, 0.0, 60.0, 1e-11, &gamma_calls);
```

The closure captures `x` (read only: `x` is a `let`). `adaptive` splits an
interval only where the two halves disagree with the whole, and counts
its evaluations through an `inout i64` parameter (`&gamma_calls` at the
call). The integral of
`t^(x-1) e^-t` is the Gamma function, which libm's `tgamma` computes
directly: the two agree to 1e-8 (the integral is cut at 60). The normal
distribution's mass within two standard deviations is checked the same
way against `erf`.

### Roots: bisection and Newton

```tach
fn bisect<F: Fn(f64) -> f64>(f: F, lo: f64, hi: f64, tolerance: f64) -> Option<(f64, i64)>
```

Bisection returns `None` when the interval has no sign change, else the
root and the steps taken, as an `Option` of a tuple matched with
`Some((root, steps))`.

```tach
fn newton<F: Fn(f64) -> f64, D: Fn(f64) -> f64, T: FnMut(i64, f64)>(
    f: F, df: D, x0: f64, mut trace: T,
) -> Option<f64>
```

Newton's method takes three closures: the function, its derivative, and
a `FnMut` that sees each iterate (here it prints them: the number of
correct digits doubles each step). A zero derivative gives `None`,
printed with `{flat:?}`.

## C interop rules in brief

- **Declaring C**: `import "math.h" as c;` or `extern "C" { fn sqrt(x:
  f64) -> f64; }` by hand. C calls are `unsafe`; a closure can wrap one so
  that generic code calls it safely.
- **Types**: `double` is `f64`, `float` is `f32`, `int` is `i32`, `T *`
  is `*T`. Floats pass to C by value exactly as C expects.
- **Out-parameters**: pass `&local`; C writes through it.
- **Callbacks into C APIs** must be `extern "C" fn` (see
  [c-qsort](../c-qsort/)); closures are for tachyon's own generic code.
- **Linking**: libm is linked when the program calls into it (on Linux
  it is apart from libc); other libraries with `-l NAME`, `-L DIR`.

## Language features

- `import "math.h" as c`, out-parameters, linking:
  `tachyonc guide c-interop`
- closures, captures, `Fn` and `FnMut` bounds: `tachyonc guide closures`
- generic functions with several type parameters: `tachyonc guide generics`
- f-strings with precision and width (`{x:.12}`, `{v:>12.3}`), `{o:?}`:
  `tachyonc guide formatting`
- tuples, `Option<(f64, i64)>`, pattern matching: `tachyonc guide syntax`
- `unsafe` blocks inside closures: `tachyonc guide unsafe`
