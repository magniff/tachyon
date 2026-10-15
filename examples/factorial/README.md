# factorial

Factorials of 1 to 10, computed two ways (a recursive function, and a
range folded by a closure) and checked against each other.

## Build and run

From this folder (with `tachyonc` on your `PATH`, or `../../target/tachyonc`):

```sh
tachyonc main.tach -o factorial && ./factorial
```

## Expected output

```text
Factorial of 1 == 1
Factorial of 2 == 2
Factorial of 3 == 6
Factorial of 4 == 24
Factorial of 5 == 120
Factorial of 6 == 720
Factorial of 7 == 5040
Factorial of 8 == 40320
Factorial of 9 == 362880
Factorial of 10 == 3628800
```

## How it works

The recursive definition: `if` is an expression, so each branch is a
value and the function needs no `return`.

```tach
fn factorial(n: i64) -> i64 {
    if n == 0 { 1 } else { n * factorial(n - 1) }
}
```

The same product without recursion: the range `1..=n` used as a value is
an iterator, and `fold` combines its items with a closure, starting from 1.

```tach
fn factorial_fold(n: i64) -> i64 {
    (1..=n).fold(1, |acc, k| acc * k)
}
```

The closure's parameter types come from `fold`'s bound, so `|acc, k|`
needs no annotations. Iterator chains are compiled to the loop you would
write by hand.

`main` prints each line with an f-string, and reports a disagreement on
stderr with `eprintln` (it never happens: `i64` holds every factorial up
to 20!).

```tach
println(f"Factorial of {n} == {f}");
```

## Language features

- `if` as an expression, recursion: `tachyonc guide syntax`
- ranges as iterators, `fold`: `tachyonc guide iterators`
- closures: `tachyonc guide closures`
- f-strings, `eprintln`: `tachyonc guide formatting`
