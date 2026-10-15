# errors-and-results

A config-file parser that treats errors as typed values: two layers of
error enums, `?` to pass errors up, `From` to convert a lower layer's
error into a higher one's, `map_err` and `ok_or` to add context, the
difference between "absent" (`Option`) and "failed" (`Result`), and a
`main` that returns a `Result`.

## Build and run

From this folder (with `tachyonc` on your `PATH`, or `../../target/tachyonc`):

```sh
tachyonc main.tach -o errors-and-results
./errors-and-results < server.conf      # a good config: exit 0
./errors-and-results < broken.conf      # a bad one: exit 1
```

The config is one `key = value` per line, `#` starts a comment:

```text
# the demo server
name = demo
port = 8080
workers = 4
debug = true
```

`port` is required (1 to 65535); `name`, `workers` (1 to 64), `debug`
(`true`/`false`) and `timeout_ms` (0 to 60000) have defaults.

## Expected output

First the program parses a few built-in bad samples and prints why each
was rejected (errors handled as values), then it parses stdin. With
`server.conf`:

```text
rejected samples:
  "port = 80\nport = 81"     line 2: `port` is set twice
  "port: 80"                 line 1: expected `key = value`
  "port = 80\ncolour = blue" line 2: unknown key `colour`
  "port = 8o"                line 1: port: not a number (invalid digit at byte 1)
  "port = 70000"             line 1: port: 70000 is not in 1..=65535
  "port = 80\ndebug = yes"   line 2: debug: expected true or false
  "name = no port"           `port` is required
config: demo on port 8080
  workers 4, debug true, timeout 1000 ms
```

With `broken.conf` (`workers = many` on line 3) the same seven lines,
then on stderr, with exit status 1:

```text
Error: BadValue(3, "workers", NotANumber(InvalidDigit(0)))
```

## How it works

**Two layers, two error types.** The value layer parses one value and
knows nothing of files; the file layer knows lines and keys. Each layer
has its own enum, and `#[derive(Debug)]` writes the Debug text that
`main` prints on failure:

```tach
#[derive(Debug)]
enum ValueError { NotANumber(ParseIntError), NotABool, OutOfRange(i64, i64, i64) }

#[derive(Debug)]
enum ConfigError {
    Read(IoError),
    NoEquals(i64),
    UnknownKey(i64, [u8]),
    Duplicate(i64, [u8]),
    BadValue(i64, [u8], ValueError),
    Missing([u8]),
}
```

**`?` with `From`.** `parse_int` fails with std's `ParseIntError`.
Because `ValueError` implements `From<ParseIntError>`, `?` converts the
error on its way out; no `match` needed:

```tach
impl From<ParseIntError> for ValueError {
    fn from(e: ParseIntError) -> ValueError { ValueError::NotANumber(e) }
}

fn parse_number(text: [u8], lo: i64, hi: i64) -> Result<i64, ValueError> {
    let n = parse_int(text)?; // Err(ParseIntError) returns Err(ValueError::from(e))
    if n < lo || n > hi { return Err(ValueError::OutOfRange(n, lo, hi)); }
    Ok(n)
}
```

The same happens in `main`: `read_stdin()?` turns std's `IoError` into a
`ConfigError` through `impl From<IoError> for ConfigError`.

**`map_err` adds context.** A `ValueError` does not know its line or
key; the file layer wraps it with both before passing it up. When the
conversion needs more than the error itself, `map_err` with a closure
does it instead of `From`:

```tach
let n = parse_number(field.value, lo, hi)
    .map_err(|e| ConfigError::BadValue(field.line, key, e))?;
```

**Option means absent, Result means failed.** A missing optional key is
not an error, a malformed one is, so the getter returns
`Result<Option<i64>, ConfigError>`. The caller decides what absence
means: a default with `unwrap_or`, or an error with `ok_or`:

```tach
Ok(Config {
    name: fields.get("name").map(|f| f.value).unwrap_or("unnamed"),
    port: number(&fields, "port", 1, 65535)?.ok_or(ConfigError::Missing("port"))?,
    workers: number(&fields, "workers", 1, 64)?.unwrap_or(1),
    debug: flag(&fields, "debug")?.unwrap_or(false),
    timeout_ms: number(&fields, "timeout_ms", 0, 60000)?.unwrap_or(1000),
})
```

`ok_or` also turns a failed search into an error with the line number:

```tach
let eq = line.iter().position(|b| b == '=').ok_or(ConfigError::NoEquals(number))?;
```

**`defer` runs on every exit.** `parse_config` allocates a `HashMap` and
frees it with `defer`; each `?` that returns early runs the `defer`
first, so no path leaks it.

**Display for people, Debug for programmers.** `impl Display` writes
the messages printed for the rejected samples (`{e}`); the derived Debug
is what `main` prints on failure. Each `Display` impl may use the inner
error's own `Display`: `f.write(f"not a number ({e})")`.

**`main` returns a Result.** On `Ok(())` the exit status is 0; on
`Err(e)` the program prints `Error: ` and `e`'s Debug text on stderr and
exits with 1, as Rust does:

```tach
fn main() -> Result<(), ConfigError> {
    show_rejections();
    let mut input = read_stdin()?; // IoError -> ConfigError through From
    defer input.free();
    let config = parse_config(input.as_slice())?;
    ...
    Ok(())
}
```

## Language features

- `?`, `From`/`Into`, `main -> Result`, std's error enums: `tachyonc guide conversions`
- `Option`/`Result` methods (`map`, `map_err`, `ok_or`, `unwrap_or`): `tachyonc guide std`
- `#[derive(Debug)]`, `impl Display`, `{x:<26?}`: `tachyonc guide formatting`
- closures given to `map_err`, `position`, `any`: `tachyonc guide closures`
- `defer`, `HashMap`, `Scanner`, `trim`: `tachyonc guide std`, `tachyonc guide memory`
- a `type` alias (`type Fields = HashMap<[u8], Field>;`): `tachyonc guide generics`

## Going further

- No `Box<dyn Error>` or `anyhow`: errors are enums, one per layer, with
  `From` impls between them. Every case is visible to `match`.
- No `expect(msg)`: `unwrap` on an `Err` or `None` stops the program
  with a fixed message and exit status 101; for a message of your own,
  `match` and `unwrap_or_else`, or return a `Result` as here.
- No `let ... else`: `match` on the `Option`, as `number` does.
