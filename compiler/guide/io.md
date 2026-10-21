# io

## Files, paths, the environment, processes

Rust's names; a path is any `[u8]`: a literal, a `str`, a `Path`, `&p`
of a PathBuf. `File::open(p)?`, `File::create(p)?`,
`OpenOptions::new().append(true).create(true).open(p)?`;
`fs::read_to_string_in(p, gpa)?` (a String), `fs::read_in(p, gpa)?` (a
`Vec<u8>`), `fs::write(p, data)?`, `fs::append(p, data)?`,
`fs::metadata(p)?` (`len()`, `is_dir()`), `fs::create_dir_all(p)?`,
`fs::remove_file`, `fs::remove_dir_all`, `fs::rename(a, b)`,
`fs::read_dir(p)?` (entries: `let e = e?; e.file_name()`, a view of the entry; `e.path_in(dir, gpa)`),
`fs::exists(p)`. Errors are `io::Error` (`e.kind()`, an `ErrorKind`;
Display as Rust's: `No such file or directory (os error 2)`), and
`io::Result<T>` goes with `?`. `BufReader::new(f)` and
`BufWriter::new(f)` keep an 8 KB buffer inline (no allocation):
`r.read_line(&s)?` appends a line, its `'\n'` included (0 at the
end); `r.lines_in(gpa)` yields each line as a String;
`writeln(&w, f"..")?` (Rust's `writeln!`; `use std::io::writeln`).
`Path::new(p)`: `file_name()`, `extension()`, `parent()`,
`components()`, `join_in(q, gpa)` (a PathBuf). `env::args()` yields
`str`s (`.collect_in(gpa)`), `env::get_in(name, gpa)` a
`Result<String, VarError>` (Rust's `env::var`). `Command::new(p)`, then `c.arg(a)` (it
changes `c`: `var c = ..`, no chaining), `c.output_in(gpa)?`
(`status`, `stdout`, `stderr`), `c.status()?`. A Rust `use std::io::{self,
Write}` is two lines here: `use std::io;` and `use std::io::Write;`.

```tach
use std::fs;
use std::fs::File;
use std::io;
use std::io::{BufReader, BufWriter, Write, writeln};
use std::process::Command;

fn run(gpa: Gpa) -> io::Result<()> {
    let path = "/tmp/tachyon-guide-files.txt";
    {
        var w = BufWriter::new(File::create(path)?);
        for i in 1..4 {
            writeln(&w, f"line {i}")?;
        }
    }
    var r = BufReader::new(File::open(path)?);
    var line = String::new_in(gpa);
    var total = 0;
    while r.read_line(&line)? > 0 {
        total += 1;
    }
    println(f"{total} {line.lines().count()} {fs::metadata(path)?.len()}");
    fs::remove_file(path)?;
    var c = Command::new("echo");
    c.arg("hi");
    let out = c.output_in(gpa)?;
    println(f"{out.status.success()} {out.stdout.len()}");
    match File::open(path) {
        Ok(_) => println("still there"),
        Err(e) => println(f"{e.kind():?}"),
    }
    Ok(())
}

fn main(gpa: Gpa) -> i32 {
    match run(gpa) {
        Ok(_) => 0,
        Err(e) => {
            eprintln(f"{e}");
            1
        }
    }
}
```
```out
3 3 21
true 3
NotFound
```
