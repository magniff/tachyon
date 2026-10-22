# cli

[args](../args/) with `std::cli`: it prints the words on its command
line, one a line, and takes a flag and two options. `args` reads C's
`argv` by hand; this program declares its arguments and lets std parse
them, so `--help`, `--version` and the errors for bad arguments come
with it.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o cli && ./cli -vv -n2 --prefix='>' foo -- -bar
./cli --help
./cli -n x foo      # an error: on stderr, exit status 2
```

## Expected output

```text
prefix: >, times: 2
words: 2
> foo
> -bar
> foo
> -bar
```

`./cli --help` (stdout, exit status 0):

```text
cli 0.25
prints its words, one a line

usage: cli [options] <word>...

arguments:
  <word>...            the words

options:
  -v, --verbose        also print the options (-vv: the count too)
  -p, --prefix <TEXT>  printed before each word [default: --]
  -n, --times <N>      print the words N times [default: 1]
  -h, --help           print this help
  -V, --version        print the version
```

`./cli -n x foo` (stderr, exit status 2):

```text
error: invalid value 'x' for '--times <N>'
try: --times <N>
usage: cli [options] <word>...
```

## How it works

A `Command` lists the arguments, each an `Arg`: a flag (`-v`), an option
with a value (`-n N`, a default when it is not given) or a positional
(`word`, `multiple()`: it takes the rest, `required()`: at least one):

```tach
let cmd = Command::new_in("cli", gpa).version("0.25").about("prints its words, one a line")
    .arg(Arg::flag("verbose").short('v').help("also print the options (-vv: the count too)"))
    .arg(Arg::option("prefix").short('p').value_name("TEXT").default("--")
        .help("printed before each word"))
    .arg(Arg::option("times").short('n').value_name("N").default("1")
        .help("print the words N times"))
    .arg(Arg::positional("word").required().multiple().help("the words"));
let m = cmd.parse_or_exit(env::args());
```

`parse_or_exit` takes the arguments as `env::args()` gives them, the
program's name first. On a bad argument, `--help` or `--version` it
prints what is asked and ends the program; otherwise it returns the
`Matches`: `m.count("verbose")` (`-vv` is 2), `m.get("prefix")` (the
value, or the default), `m.values("word")` (every positional, in order).
A value is text; `m.get_as::<i64>("times")` parses it, and its error,
given to `cmd.exit(e)`, is reported as a parse error is:

```tach
let times = match m.get_as::<i64>("times") {
    Ok(n) => n,
    Err(e) => cmd.exit(e),
};
```

`cmd.parse(args)` instead of `parse_or_exit` returns the error as a
`Result` for the program to handle, and does no io.

## Language features

- `std::cli`: `volec guide cli`
- `env::args()`, `str`: `volec guide text`
- `match` on a `Result`, a diverging arm (`cmd.exit(e)` is `!`): `volec guide syntax`
