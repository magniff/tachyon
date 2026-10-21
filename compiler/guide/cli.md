# Command lines: std::cli (0.24)

`std::cli` parses a program's arguments: clap's builder, without derive.
A `Command` lists flags, options and positionals (and subcommands);
`parse` gives `Matches` or a `CliError`. `--help`, `-h` and (with a
version) `--version`, `-V` are built in. The design: docs/design/cli.md.

```text
use std::cli::{Arg, Command};
use std::env;

fn main(gpa: Gpa) -> i32 {
    let cmd = Command::new_in("grep", gpa).version("1.0").about("find lines")
        .arg(Arg::flag("count").short('c').help("print how many"))
        .arg(Arg::option("max").short('m').value_name("N").default("0"))
        .arg(Arg::positional("pattern").required())
        .arg(Arg::positional("file").multiple());
    let m = cmd.parse_or_exit(env::args());    // an error: printed, exit 2
    let max = match m.get_as::<i64>("max") { Ok(n) => n, Err(e) => cmd.exit(e) };
    for f in m.values("file") { .. }
    0
}
```

## Parsing and Matches

`cmd.parse(args)` takes any iterator of `str`, the program's name first
(`env::args()`, `line.split(' ')`, `v.iter()`); `parse_in(args, a)`
puts the Matches on allocator `a` (an arena). Accepted: `-v`, `-vvv`,
clusters `-vq`, `-ofile`, `-o file`, `-o=file`, `--out file`,
`--out=file`, `--` (the rest is positional), `-` (a positional). An
option takes the next argument even when it starts with `-` (`-n -5`).

```tach
use std::cli::{Arg, Command};

fn main(gpa: Gpa) -> i32 {
    let cmd = Command::new_in("tool", gpa)
        .arg(Arg::flag("verbose").short('v'))
        .arg(Arg::option("out").short('o').default("-"))
        .arg(Arg::option("jobs").short('j').default("1"))
        .arg(Arg::positional("file").multiple())
        .subcommand(Command::new_in("push", gpa).arg(Arg::flag("force").short('f')));
    let m = cmd.parse("tool -vv -ofile a b".split(' ')).unwrap();
    let jobs = m.get_as::<i64>("jobs").unwrap();
    println(f"{m.count("verbose")} {m.get("out").unwrap()} {jobs} {m.values("file").len()}");
    let p = cmd.parse("tool -j 4 push -f".split(' ')).unwrap();
    match p.subcommand() {
        Some((name, sub)) => println(f"{name} {sub.flag("force")}"),
        None => println("none"),
    }
    match cmd.parse("tool --outt x".split(' ')) {
        Ok(_) => println("ok"),
        Err(e) => print(cmd.render_in(e, gpa).as_slice()),
    }
    0
}
```
```out
2 file 1 2
push true
error: unknown option '--outt'
try: --out
usage: tool [options] [file]... [command]
```

- `m.flag(name)`: given (a default is not); `m.count(name)`: how many
  times; `m.get(name)`: the last value or the default, an
  `Option<str>`; `m.values(name)`: every value, a `[str]`;
  `m.get_as::<T>(name)`: parsed (`FromStr`), `Err(CliError)` naming the
  argument; `m.subcommand()`: `Option<(str, Matches)>`. A name that is
  no Arg of that command panics.
- An Arg: `.short('x')`, `.long("s")` (its name by default),
  `.help(..)`, `.value_name("FILE")`, `.default(..)`, `.required()`,
  `.multiple()` (a positional taking the rest). Options may repeat.

## Help and errors

`cmd.exit(e)` prints a CliError and exits with `e.exit_code()`: the
help or version on stdout (0), else on stderr (2) the error, a `try:`
line (the nearest option or command by edit distance, or the fix) and
the usage line. `cmd.render_in(e, a)` and `cmd.help_in(a)` give that
text as a `Buf`; `.width(n)` wraps the help (80). Parsing does no io
(`query effects`): only `exit` and `parse_or_exit` print.
