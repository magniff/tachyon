# errors-and-results

A config-file parser that treats errors as typed values: two layers of
error enums, `?` to pass errors up, `From` to convert a lower layer's
error into a higher one's, `map_err` and `ok_or` to add context, the
difference between "absent" (`Option`) and "failed" (`Result`), and a
`main` that returns a `Result`.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o errors-and-results
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
    UnknownKey(i64, Buf),
    Duplicate(i64, Buf),
    BadValue(i64, Buf, ValueError),
    Missing(Buf),
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

The same happens in `main`: `read_stdin_in(gpa)?` turns std's `IoError` into a
`ConfigError` through `impl From<IoError> for ConfigError`.

**`map_err` adds context.** A `ValueError` does not know its line or
key; the file layer wraps it with both before passing it up. When the
conversion needs more than the error itself, `map_err` with a closure
does it instead of `From`:

```tach
let n = parse_number(field.value, lo, hi)
    .map_err(|e| ConfigError::BadValue(field.line,
        Buf::from_in(key, fields.allocator()), e))?;
```

(The error owns a copy of the key, made on the map's allocator: see
"An error that owns its text" below.)

**Option means absent, Result means failed.** A missing optional key is
not an error, a malformed one is, so the getter returns
`Result<Option<i64>, ConfigError>`. The caller decides what absence
means: a default with `unwrap_or`, or an error with `ok_or`:

```tach
Ok(Config {
    name: fields.get("name").map(|f| f.value).unwrap_or("unnamed"),
    port: number(fields, "port", 1, 65535)?.ok_or(ConfigError::Missing(Buf::from_in("port", gpa)))?,
    workers: number(fields, "workers", 1, 64)?.unwrap_or(1),
    debug: flag(fields, "debug")?.unwrap_or(false),
    timeout_ms: number(fields, "timeout_ms", 0, 60000)?.unwrap_or(1000),
})
```

`ok_or` also turns a failed search into an error with the line number:

```tach
let eq = line.iter().position(|b| b == '=').ok_or(ConfigError::NoEquals(number))?;
```

**Drops run on every exit.** `parse_config` allocates a `HashMap`, which
is dropped when the function returns; each `?` that returns early drops
it too, so no path leaks it.

**Display for people, Debug for programmers.** `impl Display` writes
the messages printed for the rejected samples (`{e}`); the derived Debug
is what `main` prints on failure. Each `Display` impl may use the inner
error's own `Display`: `f.write(f"not a number ({e})")`.

**`main` returns a Result.** On `Ok(())` the exit status is 0; on
`Err(e)` the program prints `Error: ` and `e`'s Debug text on stderr and
exits with 1, as Rust does:

```tach
fn main(gpa: Gpa) -> Result<(), ConfigError> {
    show_rejections(gpa);
    let input = read_stdin_in(gpa)?; // IoError -> ConfigError through From
    let config = parse_config(input.as_slice(), gpa)?;
    ...
    Ok(())
}
```

**An error that owns its text.** `UnknownKey` and the others carry the
key as a `Buf`, a copy, not a `[u8]` view of `input`: `main` prints its
error *after* it returns, and `input` is dropped when main returns. A
view there would outlive its owner, which the compiler rejects
(`own.escape`: main returns a view of `input`, which is dropped when main
returns); before 0.17 the program had to leak `input` on the
error path instead. An owned field (the `Buf`, not a view of it) is what
`volec explain own.escape` suggests for a value that must outlive its
source.

## Language features

- `?`, `From`/`Into`, `main -> Result`, std's error enums: `volec guide conversions`
- `Option`/`Result` methods (`map`, `map_err`, `ok_or`, `unwrap_or`): `volec guide std`
- `#[derive(Debug)]`, `impl Display`, `{x:<26?}`: `volec guide formatting`
- closures given to `map_err`, `position`, `any`: `volec guide closures`
- drops, `HashMap`, `Scanner`, `trim`: `volec guide std`, `volec guide memory`
- a `type` alias (`type Fields = HashMap<[u8], Field>;`): `volec guide generics`

## Going further

- No `Box<dyn Error>` or `anyhow`: errors are enums, one per layer, with
  `From` impls between them. Every case is visible to `match`.
- No `expect(msg)`: `unwrap` on an `Err` or `None` stops the program
  with a fixed message and exit status 101; for a message of your own,
  `match` and `unwrap_or_else`, or return a `Result` as here.
- `let ... else` (0.18.1) is the other way to handle absence:
  `let Some(field) = fields.get(key) else { return Ok(None); };` does
  what `number`'s `match` does, with one level less of nesting.
