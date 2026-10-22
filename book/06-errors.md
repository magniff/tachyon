# 6. Errors: Option, Result and panics

Programs meet things they didn't expect: a key that isn't in a table, a
line with a typo in it, a file that isn't there. This chapter is about
handling those things on purpose.

Vole has no exceptions. A function that might not have an answer says
so in its result type, and the caller decides what to do. By the end of
the chapter you'll know when to use `Option` and when `Result`, how to
design an error type of your own, how the `?` operator passes errors up
in one character, and how all this differs from a *panic*, which stops
the program because something is wrong with the program itself.

The running example is a parser for a small settings file, with lines
like these:

```text
port = 8080
name = vole
```

## Absence: Option

You met `Option` in chapter 5: `Some(value)` or `None`. Use it when a
value may simply not be there, and that's nothing unusual. The standard
library uses it that way everywhere:

```vole
fn main(gpa: Gpa) {
    let line: str = "port = 8080";
    println(f"{line.find("="):?} {line.find("#"):?}");

    var defaults: HashMap<str, i64> = HashMap::new_in(gpa);
    defaults.insert("port", 80);
    defaults.insert("workers", 4);
    let port = defaults.get("port").unwrap_or(0);
    let timeout = defaults.get("timeout").unwrap_or(30);
    println(f"{port} {timeout}");

    if let Some(w) = defaults.get("workers") {
        println(f"{w} workers");
    }
}
```

```out
Some(5) None
80 30
4 workers
```

`line.find("=")` is the position of the first `=`, if there is one.
`defaults.get(key)` is the value stored under `key`, if there is one (a
`HashMap` is a table from keys to values; chapter 7 has more). Neither
is an error when the answer is "nowhere": it's one of the two expected
outcomes.

You've now seen three ways to get at what's inside an `Option`:

- `match` (or `if let`), to do something different in each case;
- `unwrap_or(default)`, for "this, or else that";
- `unwrap()`, which stops the program on a `None`. Use it only when you
  know the value is there.

There are a few more methods that work on the value inside without
taking it out. `o.map(|x| x * 2)` doubles the number in a `Some` and
leaves a `None` alone; `o.and_then(f)` calls `f`, which itself returns
an `Option`. (The `|x| x * 2` is a *closure*, a small function written
in place; chapter 10 explains them.)

## Failure: Result

When something can *fail*, there's more to say than "nothing here". You
want to know what went wrong. That's `Result<T, E>`: either `Ok(value)`,
holding a `T`, or `Err(error)`, holding an `E` that describes the
failure. Parsing a number is the classic example:

```vole
fn main() {
    let good: str = "8080";
    let bad: str = "80x80";
    match good.parse::<i64>() {
        Ok(n) => println(f"got {n}"),
        Err(e) => println(f"error: {e}"),
    }
    match bad.parse::<i64>() {
        Ok(n) => println(f"got {n}"),
        Err(e) => println(f"error: {e}"),
    }
}
```

```out
got 8080
error: invalid digit at byte 2
```

`parse::<i64>()` returns a `Result<i64, ParseIntError>`. `ParseIntError`
is the standard library's enum of the ways parsing an integer can fail:
an empty string, a byte that isn't a digit, or a number too big for the
type. It knows how to print itself, which is what `{e}` did.

Option means absent, Result means failed. The standard library follows
this rule throughout, and your code should too. A key missing from a
table is an `Option`. A number that doesn't parse, a file that can't be
read, a settings line with a typo: those are `Result`s.

### An error type of your own

Our settings parser can fail in several ways, so let's give it an
error enum, with one variant for each way, and the facts a user would
need to fix the file:

```vole settings.vl
use std::ParseIntError;

enum ConfigError {
    MissingEquals(i64),
    BadNumber(ParseIntError),
    Unknown(i64),
}

enum Setting {
    Port(i64),
    Name(str),
}

fn parse_line(s: str, number: i64) -> Result<Setting, ConfigError> {
    let Some((key, value)) = s.split_once("=") else {
        return Err(ConfigError::MissingEquals(number));
    };
    let key = key.trim();
    let value = value.trim();
    if key == "port" {
        match value.parse::<i64>() {
            Ok(port) => Ok(Setting::Port(port)),
            Err(e) => Err(ConfigError::BadNumber(e)),
        }
    } else if key == "name" {
        Ok(Setting::Name(value))
    } else {
        Err(ConfigError::Unknown(number))
    }
}

fn report(line: str, number: i64) {
    match parse_line(line, number) {
        Ok(Setting::Port(p)) => println(f"port {p}"),
        Ok(Setting::Name(n)) => println(f"name {n}"),
        Err(ConfigError::MissingEquals(n)) => println(f"line {n}: no '='"),
        Err(ConfigError::BadNumber(e)) => println(f"bad number: {e}"),
        Err(ConfigError::Unknown(n)) => println(f"line {n}: unknown setting"),
    }
}

fn main() {
    report("port = 8080", 1);
    report("port = 80x80", 2);
    report("name: vole", 3);
    report("colour = red", 4);
}
```

```out
port 8080
bad number: invalid digit at byte 2
line 3: no '='
line 4: unknown setting
```

`MissingEquals` and `Unknown` carry the line number. `BadNumber`
carries the `ParseIntError` itself, so nothing about the failure is
lost. And the `match` in `report` must handle every variant, so a caller
can't forget a way the parser fails.

## The ? operator

Now let's parse a whole file. `load` goes through the lines, parses
each one, and stops at the first error. Written with `match`, every
line that can fail takes four lines:

```vole skip
match parse_line(line, number) {
    Ok(setting) => ...,
    Err(e) => return Err(e),
}
```

That "if it's an error, return it" is so common that it has an operator.
Put `?` after a `Result`, and:

- if it's `Ok(value)`, the expression is `value`, and the function goes
  on;
- if it's `Err(error)`, the function returns `Err(error)` right there.

Here's `load` with it:

<!-- vole-hidden
use std::ParseIntError;

enum ConfigError {
    MissingEquals(i64),
    BadNumber(ParseIntError),
    Unknown(i64),
}

enum Setting {
    Port(i64),
    Name(str),
}

fn parse_line(s: str, number: i64) -> Result<Setting, ConfigError> {
    let Some((key, value)) = s.split_once("=") else {
        return Err(ConfigError::MissingEquals(number));
    };
    let key = key.trim();
    let value = value.trim();
    if key == "port" {
        match value.parse::<i64>() {
            Ok(port) => Ok(Setting::Port(port)),
            Err(e) => Err(ConfigError::BadNumber(e)),
        }
    } else if key == "name" {
        Ok(Setting::Name(value))
    } else {
        Err(ConfigError::Unknown(number))
    }
}
-->
```vole
struct Config { port: i64, name: str }

fn load(text: str) -> Result<Config, ConfigError> {
    var config = Config { port: 80, name: "unnamed" };
    var number = 0;
    for line in text.lines() {
        number += 1;
        if line.trim() == "" {
            continue;
        }
        match parse_line(line, number)? {
            Setting::Port(p) => config.port = p,
            Setting::Name(n) => config.name = n,
        }
    }
    Ok(config)
}
```

`parse_line(line, number)?` is a `Setting` when the line parsed, and
the `match` looks at which one. When the line didn't parse, `load`
returns that error to its own caller. Everything the function owns is
dropped on the way out, as for any `return`.

Errors travel up this way, one `?` at a time, until they reach a
function that knows what to do with them, usually one close to `main`
that tells the user. Functions in between don't have to mention errors
at all, except for the `?`.

`?` works on an `Option` too: in a function that returns an `Option`,
`x?` gives the value in a `Some`, or returns `None`.

The function has to be one that can return the error, though. Use `?`
in a function that returns nothing, and the compiler says what to
change:

```vole
fn main() {
    let port = "8080".parse::<i64>()?;
    println(f"{port}");
}
```

```err
error[type error]: '?' needs 'main' to return Option or Result; it returns '()'
 --> main.vl: line 2, column 37
  = help: make it return a Result: '-> Result<(), ParseIntError>'
```

## Converting errors

Look back at `parse_line`. It still has a `match` to turn the
`ParseIntError` from `parse` into a `ConfigError`. Can we use `?`
there too? Let's try:

```vole
use std::ParseIntError;

enum ConfigError {
    MissingEquals(i64),
    BadNumber(ParseIntError),
    Unknown(i64),
}

fn parse_port(value: str) -> Result<i64, ConfigError> {
    let port = value.parse::<i64>()?;
    Ok(port)
}

fn main() {
    if let Ok(p) = parse_port("8080") {
        println(f"{p}");
    }
}
```

```err
error[type error]: '?' cannot convert the error 'ParseIntError' into 'ConfigError', the function's error type
 --> main.vl: line 10, column 36
  = help: implement it: 'impl From<ParseIntError> for ConfigError { fn from(e: ParseIntError) -> ConfigError { ConfigError::BadNumber(e) } }'
```

The function returns `ConfigError`s, and `parse` fails with a
`ParseIntError`. `?` can return a different error type than the one it
was given, but only if it knows how to convert one into the other. You
tell it with an `impl From`, and the help line has written it out for
you:

<!-- vole-hidden
use std::ParseIntError;

enum ConfigError {
    MissingEquals(i64),
    BadNumber(ParseIntError),
    Unknown(i64),
}
-->
```vole
impl From<ParseIntError> for ConfigError {
    fn from(e: ParseIntError) -> ConfigError {
        ConfigError::BadNumber(e)
    }
}
```

`From` is a *trait*, a set of functions a type can provide (chapter 9).
This one says "here's how to make a `ConfigError` from a
`ParseIntError`". With it in the program, every `?` on a
`ParseIntError` in a function returning `ConfigError` converts the
error by calling it. So `parse_line` shrinks to:

```vole skip
    if key == "port" {
        Ok(Setting::Port(value.parse::<i64>()?))
    }
```

When there's no `From` to use, or you want a different conversion in
one place, convert by hand. `map_err` changes the error inside a
`Result`, and `ok_or` turns an `Option` into a `Result` by saying which
error a `None` is:

<!-- vole-hidden
use std::ParseIntError;

enum ConfigError {
    MissingEquals(i64),
    BadNumber(ParseIntError),
    Unknown(i64),
}

enum Setting {
    Port(i64),
    Name(str),
}
-->
```vole
fn parse_port_line(s: str, number: i64) -> Result<Setting, ConfigError> {
    let (key, value) = s.split_once("=").ok_or(ConfigError::MissingEquals(number))?;
    if key.trim() != "port" {
        return Err(ConfigError::Unknown(number));
    }
    let port = value.trim().parse::<i64>().map_err(|e| ConfigError::BadNumber(e))?;
    Ok(Setting::Port(port))
}
```

## main can return a Result

The last step is `main`. It can return a `Result` too, which makes `?`
work all the way up. When `main` returns an `Err`, the program prints
`Error:` and the error, and exits with status 1. To print the error,
the type needs `#[derive(Debug)]`, as in chapter 5. Here's the whole
program, reading the settings from standard input:

```vole settings.vl
use std::{ParseIntError, io};
use std::io::BufReader;

#[derive(Debug)]
enum ConfigError {
    MissingEquals(i64),
    BadNumber(ParseIntError),
    Unknown(i64),
}

impl From<ParseIntError> for ConfigError {
    fn from(e: ParseIntError) -> ConfigError {
        ConfigError::BadNumber(e)
    }
}

enum Setting {
    Port(i64),
    Name(str),
}

struct Config { port: i64, name: str }

fn parse_line(s: str, number: i64) -> Result<Setting, ConfigError> {
    let Some((key, value)) = s.split_once("=") else {
        return Err(ConfigError::MissingEquals(number));
    };
    let key = key.trim();
    let value = value.trim();
    if key == "port" {
        Ok(Setting::Port(value.parse::<i64>()?))
    } else if key == "name" {
        Ok(Setting::Name(value))
    } else {
        Err(ConfigError::Unknown(number))
    }
}

fn load(text: str) -> Result<Config, ConfigError> {
    var config = Config { port: 80, name: "unnamed" };
    var number = 0;
    for line in text.lines() {
        number += 1;
        if line.trim() == "" {
            continue;
        }
        match parse_line(line, number)? {
            Setting::Port(p) => config.port = p,
            Setting::Name(n) => config.name = n,
        }
    }
    Ok(config)
}

fn main(gpa: Gpa) -> Result<(), ConfigError> {
    var input = BufReader::new(io::stdin());
    var text = String::new_in(gpa);
    while input.read_line(&text).unwrap() > 0 {}
    let config = load(text.as_str())?;
    println(f"serving {config.name} on port {config.port}");
    Ok(())
}
```

The first `use` line imports two names from `std` at once.
`read_line` adds each line to the end of `text`, so the empty `while`
loop reads the whole input. (Reading can fail too; we `unwrap` it here,
and the first exercise fixes that.) A good settings file:

```in
port = 8080

name = vole
```

```out
serving vole on port 8080
```

And a few bad ones:

```console
$ volec settings.vl -o settings
ok: built settings
$ printf 'port = 80x80\n' | ./settings
Error: BadNumber(InvalidDigit(2))
$ echo $?
1
$ printf 'name = vole\ncolour = red\n' | ./settings
Error: Unknown(2)
```

The `Debug` form isn't the friendliest message for a user, but it's
exact, and it costs one line. When you want a better one, match on the
error in `main` as we did before, or give the type a `Display`
(chapter 9).

> **If you know Rust:** `?`, `From`, and `main` returning a `Result`
> work as in Rust. The difference is that vole has nothing else: there
> is no `Box<dyn Error>`, so a function's error type is always a
> concrete type you can match on.

> **If you know Go:** `x?` is `if err != nil { return err }`, in one
> character, and the compiler checks that you didn't forget it: a
> `Result` can't be used as the value inside it.

> **If you know Python or Java:** there are no exceptions. A failure is
> a value, returned like any other, and the function's type says it can
> happen. `?` keeps passing it on as short as letting an exception
> propagate.

## Panics

Some failures aren't the input's fault. An index past the end of a list,
an `unwrap` of an `Err` you were sure couldn't happen, a case your code
thought impossible: those are bugs in the program. For them, vole
*panics*: it prints one line saying where and why, and exits with
status 101. You've seen panics already:

```vole port.vl
fn port_of(value: str) -> i64 {
    value.parse::<i64>().unwrap()
}

fn show(value: str) {
    println(f"port {port_of(value)}");
}

fn main() {
    show("8080");
    show("80x80");
}
```

```out exit=101
port 8080
port.vl:2:5: called unwrap on Err
```

The line names the position of the failing call: line 2, the `unwrap`
in `port_of`. When the function that failed is called from many
places, you'll also want to know how the program got there. Build with
`--trace`, and a panic prints the calls that led to it, innermost
first:

```console
$ volec port.vl -o port --trace
ok: built port
$ ./port
port 8080
port.vl:2:5: called unwrap on Err
trace, innermost call first:
  port.vl:2  port_of
  port.vl:6  show
  port.vl:11  main
```

You can panic on purpose too. `panic("message")` stops the program with
that message, and `unreachable()` marks a place your code should never
get to:

```vole
fn main() {
    let n = 7;
    let parity = match n % 2 {
        0 => "even",
        1 => "odd",
        _ => unreachable(),
    };
    println(parity);
}
```

```out
odd
```

(The remainder of a positive number divided by 2 is 0 or 1, but the
compiler only knows it's an `i64`, so the `match` needs the last arm.)

A panic is not a crash. Nothing goes on running in a broken state:
vole checks, and stops cleanly at the first sign of trouble, before a
bad index can read or write memory it shouldn't. Drops don't run on a panic, and
there's no way to catch one. The program is over, and the line on
stderr says where to look.

So when should code panic, and when return an error? Ask whose fault
the failure is:

- **The input's, or the world's**: a user's typo, a missing file, a
  network that's down. Your program should expect it, so return a
  `Result` and let the caller decide.
- **The program's**: a broken assumption, a case that can't happen if
  the code is right. Panic. There's nothing sensible a caller could do,
  and stopping at once, at the exact line, is the fastest way to find
  the bug.

`unwrap` sits on that line. It's fine in a quick program, in a test, or
where you can see why the value must be there. In code that handles
other people's input, prefer `?` and a real error.

## Checks as documentation

Some assumptions are worth writing down, so that the compiler checks
them for you. `assert` checks a condition and panics if it's false:

```vole
fn main() {
    let workers = 3;
    let per_worker = 10;
    assert_eq(workers * per_worker, 30);
    assert(workers > 4, "need more than four workers");
    println("not reached");
}
```

```out exit=101
main.vl:5:5: need more than four workers: workers = 3
```

`assert_eq(a, b)` checks that two values are equal; `assert(c,
"message")` checks a condition, with a message for when it fails. The
failure line shows the values of the numbers in the condition, which is
often all you need to see what went wrong.

A function can state what it needs from its caller, with `requires`
between its signature and its body:

```vole listen.vl
fn listen(port: i64)
    requires port > 0 && port < 65536 else "a port is between 1 and 65535"
{
    println(f"listening on {port}");
}

fn main() {
    listen(8080);
    listen(0);
}
```

```out exit=101
listening on 8080
listen.vl:9:5: a port is between 1 and 65535: port = 0
```

A `requires` is checked at every call, before the body runs. When it
fails, the line it names is the *caller's* (line 9 here), because
that's the code that broke the promise and the one to change. The
condition is also documentation: anyone reading `listen` sees what it
expects, and knows it's checked rather than hoped for. Chapter 13 has
the rest: promises about results, tests, and more.

A `requires` is for the program's own mistakes, like any panic. If the
port comes from a settings file, check it where you read it, and return
an error.

## Summary

This chapter was about failure, handled on purpose:

- `Option` for a value that may be absent, `Result` for an operation
  that may fail, with an error that says what went wrong;
- error enums of your own, one variant per way to fail;
- `match`, `if let`, `unwrap_or`, `map`, `and_then`, `map_err` and
  `ok_or` to work with them;
- the `?` operator, which returns an error to the caller, and `impl
  From` to let it convert errors;
- `main` returning a `Result`: `Error:` and exit status 1;
- panics for bugs: one line with the position, exit status 101,
  `--trace` for the calls that led there, `panic` and `unreachable`;
- `assert`, `assert_eq` and `requires`, checks that document what the
  code expects.

You've now seen the core of the language. The next chapter puts it to
work on the data structures every program needs: lists, tables and
text.

## Try it yourself

- `main` still `unwrap`s the result of `read_line`, whose error is an
  `io::Error`. Add a variant `Io(io::Error)` to `ConfigError`, an `impl
  From<io::Error> for ConfigError`, and replace the `unwrap()` with `?`.
- Add a `workers` setting that must be between 1 and 64, and a
  `ConfigError::OutOfRange(i64)` variant for a number outside that
  range.
- Make `main` print friendly messages instead of the `Debug` form: keep
  `main` returning `()`, and match on the result of `load`.
