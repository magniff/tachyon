# Conversions and errors (0.15)

Widening between integers, `From`/`Into`, the `?` operator, `main`
returning a `Result`, and std's convention for failure: Option means
absent, Result means failed.

## Widening

A narrower integer becomes a wider one where a value of the wider type
is expected: `let x: T = v`, assignment and `+=`, arguments, `return`,
a block's last value, struct fields, variant payloads, array and tuple
elements. It is lossless, so it is implicit; nothing else is:

- it widens: `i8 -> i16 -> i32 -> i64` and `u8 -> u16 -> u32 -> u64`
  (the same signedness), and unsigned to a strictly wider signed type
  (`u8 -> i16`, `u32 -> i64`); `isize`/`usize` are `i64`/`u64`;
- it never converts int to float, `bool` to int, signed to unsigned, or
  to a narrower type: write `x as T`;
- it applies to a value, never inside another type: `*i32`, `[i32]`,
  `Vec<i32>`, `fn(i32)` stay what they are.

Where two integer types meet without an expected type (the operands of
`+` or `<`, the branches of `if` and `match`, two arguments for one
type parameter), the result is the wider one, if one widens to the
other: `a_i32 + b_i64` is an `i64`, `max(a_i32, b_i64)` is
`max::<i64>`. An expected type flows into the arithmetic, as it does for
literals: `let t: i64 = a_i32 * b_i32` multiplies in `i64`, so the
product cannot overflow `i32` first (C's bug, avoided).

```tach
fn total(xs: [i32]) -> i64 {
    let mut t: i64 = 0;
    for x in xs { t += x; }              // each i32 widens
    t
}

fn main() -> i32 {
    let a: i32 = 2000000000;
    let b: i32 = 2000000000;
    let wide: i64 = a + b;               // computed in i64
    let c: u32 = 1200;
    let xs = [1i32, 2, 3];
    std::print_int(wide);
    print(" ");
    std::print_int(total(xs[..]) + c);   // u32 + i64: an i64
    println("");
    0
}
```
```out
4000000000 1206
```

## From and Into

Traits may have type parameters (0.15): `trait From<T> { fn from(x: T)
-> Self; }` is std's. A type can implement it for several `T`s, one
impl per trait, arguments and type; `T::from(x)` picks the impl by the
type of `x`.

```tach
struct Celsius { deg: i64 }
struct Fahrenheit { deg: i64 }

impl From<Celsius> for Fahrenheit {
    fn from(c: Celsius) -> Fahrenheit { Fahrenheit { deg: c.deg * 9 / 5 + 32 } }
}

fn main() -> i32 {
    let f = Fahrenheit::from(Celsius { deg: 100 });
    let g: Fahrenheit = Celsius { deg: -40 }.into();   // Into: From backwards
    let n = i64::from(7i32);                           // widening is a From too
    std::print_int(f.deg);
    print(" ");
    std::print_int(g.deg);
    print(" ");
    std::print_int(n);
    println("");
    0
}
```
```out
212 -40 7
```

- Implement `From`, never `Into`: `x.into()` is `U::from(x)` with `U`
  the type expected there (`let y: U = x.into();`); without one it is an
  error. `t: Into<U>` holds when `U: From<t>`.
- `From` is there without an impl for the identity and for every
  widening (`i64::from(x_i32)` is a cast).
- Bounds take arguments: `fn f<T: From<i64>>(n: i64) -> T { T::from(n) }`.
- Restrictions of generic traits: no default bodies; the operator traits
  (`Add`, ...) stay without parameters; an impl names concrete types or
  its own parameters (`impl<T> From<T> for Wrap<T>`).

## The ? operator

`e?` on an `Option<T>` gives the `T`, or returns `None` from the
function. On a `Result<T, E>` it gives the `T`, or returns `Err`: the
error as it is when `E` is the function's error type `F`, widened when
`E` widens to `F`, else `F::from(err)` through an `impl From<E> for F`.
Inside a closure it returns from the closure (give it `-> T`). `defer`s
run, as for `return`.

```tach
use std::{ParseIntError, parse_int};

enum AppError { Parse(ParseIntError), Negative(i64) }

impl From<ParseIntError> for AppError {
    fn from(e: ParseIntError) -> AppError { AppError::Parse(e) }
}

fn checked(s: [u8]) -> Result<i64, AppError> {
    let n = parse_int(s)?;               // an Err returns Err(AppError::from(e))
    if n < 0 { return Err(AppError::Negative(n)); }
    Ok(n)
}

fn half(x: Option<i64>) -> Option<i64> {
    let v = x?;                          // None returns None
    Some(v / 2)
}

fn main() -> i32 {
    match checked("42") { Ok(n) => std::print_int(n), Err(_) => print("error") }
    print(" ");
    match checked("4x") {
        Err(AppError::Parse(ParseIntError::InvalidDigit(at))) => std::print_int(at),
        _ => print("?"),
    }
    print(" ");
    match checked("-3") { Err(AppError::Negative(n)) => std::print_int(n), _ => print("?") }
    print(" ");
    std::print_int(half(Some(8)).unwrap_or(-1) + half(None).unwrap_or(-1));
    println("");
    0
}
```
```out
42 1 -3 3
```

`?` on an Option in a function returning a Result needs the error
named: `x.ok_or(AppError::Missing)?`. std's `Option` has `ok_or`, `map`,
`and_then`, `unwrap_or_else`; `Result` has `map`, `map_err`, `err`,
`ok`, `unwrap_or_else`.

## main returning a Result

`fn main() -> Result<(), E>` with `E: Debug` (`#[derive(Debug)]`): on
`Err(e)` it prints `Error: ` and `e`'s Debug text on stderr and exits
with 1, as Rust does.

```tach
#[derive(Debug)]
enum ConfigError { Missing, Bad(i64) }

fn port(raw: i64) -> Result<i64, ConfigError> {
    if raw == 0 { return Err(ConfigError::Missing); }
    if raw < 0 { return Err(ConfigError::Bad(raw)); }
    Ok(raw)
}

fn main() -> Result<(), ConfigError> {
    let p = port(8080)?;
    println(f"port {p}");
    let q = port(-1)?;
    println(f"port {q}");
    Ok(())
}
```
```out (exit 1)
port 8080
Error: Bad(-1)
```

## std's errors and input

Option means absence (the end of the input, a key not found); a Result
with an error enum means failure. std's input (0.15):

| function | returns | at the end, on failure |
|---|---|---|
| `read_line(&buf)` | `Result<bool, IoError>` | `Ok(false)` at the end; `Err(IoError::Read)` |
| `read_stdin()` | `Result<Buf, IoError>` | `Err(IoError::Read)` |
| `parse_int(s)` | `Result<i64, ParseIntError>` | `Empty`, `InvalidDigit(at)` (the byte's index), `Overflow` |
| `sc.next_int()` | `Result<i64, ScanError>` | `ScanError::End`, `ScanError::Parse(e)` |
| `sc.next_token()`, `sc.next_line()` | `Option<[u8]>` | `None` at the end |

`pub enum IoError { Read, Write }`, `pub enum ParseIntError { Empty,
InvalidDigit(i64), Overflow }`, `pub enum ScanError { End,
Parse(ParseIntError) }`; each has Display and Debug.

```tach
use std::{ScanError, Scanner, read_stdin};

fn main() -> i32 {
    let mut input = read_stdin().unwrap();
    defer input.free();
    let mut sc = Scanner::new(input.as_slice());
    let mut sum = 0;
    loop {
        match sc.next_int() {
            Ok(n) => sum += n,
            Err(ScanError::End) => break,
            Err(ScanError::Parse(_)) => println("skipped a token"),
        }
    }
    std::print_int(sum);
    println("");
    0
}
```
```in
1 2 x 3
```
```out
skipped a token
6
```

Code written for 0.14's API (Option and bool results) is moved by
`tachyonc fix --only std015`: `parse_int(s)` becomes
`parse_int(s).ok()`, `sc.next_int()` `sc.next_int().ok()`,
`read_line(b)` `read_line(b).unwrap_or(false)`, `read_stdin()`
`read_stdin().unwrap()`. All four mean what they meant, but a read
error, which `read_stdin().unwrap()` now reports (exit 101).
