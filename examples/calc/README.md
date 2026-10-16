# calc

A calculator: reads lines of integer arithmetic from stdin and prints the
value of each, or what is wrong with it. A tokenizer and a
recursive-descent parser, with enums, `match`, `Result` and `?`.

## Build and run

From this folder (with `tachyonc` on your `PATH`, or `../../target/tachyonc`):

```sh
tachyonc main.tach -o calc
printf '1 + 2 * 3\n(1 + 2) * 3\n100 / (5 - 5)\n2 * (3 + 4\n2 $ 3\n' | ./calc
```

Or run `./calc` and type expressions, one per line (Ctrl-D ends).

## Expected output

```text
7
9
error: division by zero
error: unexpected the end
error: unexpected character '$'
```

`+ - * / %`, unary minus and parentheses are understood, with the usual
precedence; numbers are `i64`. Empty lines are skipped.

## How it works

**Tokens and errors are enums.** A variant may carry data (`Num(i64)`),
and `use Token::{...}` lets the variants be written without `Token::`:

```tach
enum Token { Num(i64), Plus, Minus, Star, Slash, Percent, Open, Close, End }
enum Error { BadChar(u8), Unexpected(Token), DivideByZero }
```

**The tokenizer** walks the line's bytes with a `match` on each one;
`'0'..='9'` is a range pattern, and `' ' => continue` skips a blank from
inside the `match`. A byte that starts no token ends it with an error:

```tach
fn tokenize(text: [u8]) -> Result<Vec<Token>, Error> {
    ...
        _ => {
            tokens.free();
            return Err(BadChar(c));
        }
```

There are no destructors in tachyon, so the vector is freed by hand on
the error path; the caller of the `Ok` frees it with `defer`.

**The parser** has one method per grammar rule, each returning
`Result<i64, Error>`. `?` returns the first error from every level at
once, so the grammar reads as it would without errors:

```tach
// term: unary (('*' | '/' | '%') unary)*
fn term(self: &mut Parser) -> Result<i64, Error> {
    let mut value = self.unary()?;
    loop {
        let op = self.peek();
        match op {
            Star | Slash | Percent => {
                self.at += 1;
                let rhs = self.unary()?;
                value = match op {
                    Star => value * rhs,
                    _ if rhs == 0 => return Err(DivideByZero),
                    Slash => value / rhs,
                    _ => value % rhs,
                };
            }
            _ => return Ok(value),
        }
    }
}
```

`Star | Slash | Percent` is an or-pattern and `_ if rhs == 0` a guard.
(Tachyon defines `x / 0` as 0, so the check is the program's choice, not
a crash it avoids.)

**Messages come from `Display` impls.** `impl Display for Error` writes
the text, with f-strings for the parts; the `c` spec prints a `u8` as its
character, and `{t}` uses `Token`'s own `Display`:

```tach
impl Display for Error {
    fn fmt(self: &Error, f: &mut Fmt) {
        match *self {
            BadChar(c) => f.write(f"unexpected character '{c:c}'"),
            Unexpected(t) => f.write(f"unexpected {t}"),
            DivideByZero => f.str("division by zero"),
        }
    }
}
```

**The main loop** reads stdin a line at a time with `std::read_line`,
which returns `Ok(false)` at the end of the input:

```tach
while read_line(&line).unwrap_or(false) {
    match evaluate(line.as_slice()) {
        Ok(value) => println(f"{value}"),
        Err(e) => println(f"error: {e}"),
    }
}
```

## Language features

- enums with data, `match`, or-patterns, ranges and guards: `tachyonc guide syntax`
- `Result` and `?`: `tachyonc guide conversions`
- `impl Display`, f-strings and specs (`{c:c}`): `tachyonc guide formatting`
- methods on `*Parser`, `Vec`, `defer` and `free`: `tachyonc guide memory`
- reading stdin (`read_line`): `tachyonc guide std`
