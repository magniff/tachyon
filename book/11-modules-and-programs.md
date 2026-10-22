# 11. Modules and programs

So far every program in this book has fit in one file, and has talked
to the world through stdin and stdout. Real programs outgrow both. In
this chapter you split a program into modules, decide what each module
shows to the others, and then teach it to read files, look at its
command line and environment, run other programs, and tell its caller
whether it worked.

We'll do it to a program you already know: the word counter from
[chapter 7](07-collections-and-text.md).

## One program, three files

Chapter 7's word counter reads its input, counts the words, and prints
the most common ones in a table. That's two jobs, counting and
reporting, plus a `main` that connects them. Let's give each job its own
file. Make a directory for the program, and in it three files. First
`main.vl`:

```vole main.vl
// wc: the most common words in its input.
mod count;
mod report;

fn main(gpa: Gpa) {
    let input = read_stdin_in(gpa).unwrap();
    let text = String::from_buf(input).unwrap();
    var counts: HashMap<String, i64> = HashMap::new_in(gpa);
    count::add_words(&counts, text, gpa);
    let top = report::top(counts, 5, gpa);
    report::print_table(top);
}
```

Then `count.vl`, the counting:

```vole count.vl
// Counting the words of a text.

// Letters, digits and apostrophes are parts of words. So is every
// byte of a non-ASCII character (0x80 and up), so "café" stays whole.
fn is_word_byte(b: u8) -> bool {
    match b {
        'a'..='z' | 'A'..='Z' | '0'..='9' | '\'' => true,
        0x80..=0xff => true,
        _ => false,
    }
}

// The word without the punctuation around it: "end!" is "end".
fn trim_punct(word: str) -> str {
    var start = 0;
    var end = word.len();
    while start < end && !is_word_byte(word[start]) {
        start += 1;
    }
    while end > start && !is_word_byte(word[end - 1]) {
        end -= 1;
    }
    word[start..end]
}

// Adds the words of text to counts, lowercased.
pub fn add_words(counts: inout HashMap<String, i64>, text: str, gpa: Gpa) {
    for word in text.split_whitespace() {
        let w = trim_punct(word);
        if w.is_empty() {
            continue;
        }
        counts.get_or_insert(w.to_lowercase_in(gpa), 0)[0] += 1;
    }
}
```

And `report.vl`, the table:

```vole report.vl
// The table of the most common words.

pub fn top(counts: HashMap<String, i64>, n: i64, gpa: Gpa) -> Vec<(String, i64)> {
    var pairs: Vec<(String, i64)> = Vec::new_in(gpa);
    for (word, k) in counts.iter() {
        pairs.push((word.clone(), k));
    }
    pairs.sort_by(|a, b| if a.1 != b.1 { b.1 - a.1 } else { a.0.cmp(b.0) });
    pairs.truncate(n);
    pairs
}

pub fn print_table(rows: [(String, i64)]) {
    for row in rows {
        println(f"{row.0:<12}{row.1:>5}");
    }
}
```

Given this input:

```in
the cat sat on the mat
the dog sat on the cat
a bird sat on the dog and the cat ran
```

it prints:

```out
the             6
cat             3
on              3
sat             3
dog             2
```

You build it as before, naming only `main.vl`:

```console
$ volec main.vl -o wc
ok: built wc
```

The compiler starts at `main.vl`, sees `mod count;` and `mod report;`,
and loads `count.vl` and `report.vl` from the same directory. All three
are compiled together into one program.

The code is chapter 7's, rearranged. `count.vl` has chapter 7's
`is_word_byte` and `trim_punct` as they were. Its `count_words` is now
`add_words`, which adds to a map it's given instead of making one, so
that, later in this chapter, the words of several files can go into
one map. `report.vl`'s `top` is chapter 7's `sorted_counts`, which now
also keeps only the first `n` rows (`truncate(n)`), so `print_table`
just prints what it's given, without chapter 7's header. What's really
new is where the functions live, and the two words that connect the
files: `mod` and `pub`.

## Modules

A *module* is a named group of items: functions, types, constants, and
other modules. Every file is a module. `mod count;` in `main.vl` says
"this program has a module named `count`; its code is in `count.vl`".
The files you name on the command line, here only `main.vl`, form the
*root* module, which is called `crate`.

Modules form a tree. The root's children are declared in the root, and
a module can have children of its own. When a module grows, give it a
directory: `mod count;` also finds `count/mod.vl`, and a `mod words;`
inside that file loads `count/words.vl`:

```text
main.vl            mod count;  mod report;
count/mod.vl       mod words;  pub fn add_words(...) { ... }
count/words.vl     the module crate::count::words
report.vl          pub fn top(...) { ... }
```

A module can also be written inline, with its items in braces. That's
handy for a small helper, and for the examples in this chapter:

```vole
mod units {
    pub fn kib(n: i64) -> i64 {
        n * 1024
    }
}

fn main() {
    println(f"{units::kib(4)} bytes");
}
```

```out
4096 bytes
```

> **If you know Python or JavaScript:** a module here is not a file run
> at import time. No code runs when a module is loaded; `mod` only says
> where the code is, and the whole program is compiled together.

## Visibility: pub

Every item is *private* unless it says otherwise: only its own module
(and the modules inside it) can use it. `pub` makes an item *public*,
usable from anywhere its module can be reached. That's why `add_words`,
`top` and `print_table` are all `pub fn`, while `is_word_byte` and
`trim_punct`, which only `add_words` uses, stay private to `count`.

Here's what happens without it. A smaller program, with the `pub` left
off:

```vole main.vl
mod count;

fn main(gpa: Gpa) {
    var counts: HashMap<String, i64> = HashMap::new_in(gpa);
    count::add_words(&counts, "the cat and the hat", gpa);
    println(f"{counts.len()} different words");
}
```

```vole count.vl
fn add_words(counts: inout HashMap<String, i64>, text: str, gpa: Gpa) {
    for word in text.split_whitespace() {
        let w = word.to_lowercase_in(gpa);
        counts.get_or_insert(w, 0)[0] += 1;
    }
}
```

```err
error[type error]: 'add_words' is private
 --> main.vl: line 5, column 5
  = help: make it public: `pub fn add_words` at count.vl: line 1, column 1
  = try: volec fix --suggested main.vl
```

The error is in `main.vl`, where the private function is used, and the
help says where the fix goes: the declaration in `count.vl`. `volec fix
--suggested main.vl` adds the `pub` for you (`volec fix --only pub`
does only that kind of fix).

Private is the default because most of a module is its own business.
What's `pub` is what other modules may rely on; everything else you can
change without reading the rest of the program.

A struct's fields are as visible as the struct: a `pub struct` can be
built and read field by field wherever it can be named. Methods are
visible wherever their type is.

## Paths and use

`count::add_words(...)` is a *path*: the module, `::`, and the item.
A path can be as long as it needs to be, and it starts with one of:

- a name in scope: a module declared here (`count`), or one imported;
- `crate`, the root: `crate::count::add_words`;
- `self`, this module, or `super`, its parent;
- `std`, the standard library.

In a module other than the root, a path can also start with a sibling:
in `report.vl`, `count::add_words` means `crate::count::add_words`,
because `count` is declared next to `report`.

Writing the module every time is often clearest: a reader of `main.vl`
sees at once that `top` comes from `report`. When a name is used a lot,
a `use` line brings it into scope by itself. Several names from one
module go in braces, and `as` renames one:

```vole
mod report {
    pub fn top(n: i64) -> i64 {
        n * 2
    }

    pub fn print_table(n: i64) {
        println(f"table of {n}");
    }

    pub mod style {
        pub fn width() -> i64 {
            super::top(6)
        }
    }
}

use report::{top, print_table as show};
use report::style::width;

fn main() {
    show(top(5));
    show(width());
}
```

```out
table of 10
table of 12
```

`super::top` in `style` reaches the parent module's `top`. The order of
`use` lines and items in a file doesn't matter, and a `pub use` line
re-exports a name: `pub use style::width;` inside `report` would make
`report::width` work too.

### No wildcard imports

Some languages let you import everything a module has. Vole doesn't:

```vole
mod count {
    pub fn add_words(n: i64) -> i64 {
        n
    }
}

use count::*;

fn main() {
    println(f"{add_words(3)}");
}
```

```err
error[module error]: wildcard imports are not allowed: write 'use count::add_words;' (volec --fix-imports rewrites a program this way)
 --> main.vl: line 7, column 1
  = help: every name a file uses is declared in it, imported by name, or written with its path (0.8)
```

The help says why. Every name in a vole file is defined in that file,
imported by name at the top, or written as a path. So when you meet
`add_words` in someone's code, the file itself tells you where it comes
from, and so it does for any tool that reads code, an editor or an AI
assistant. Nothing changes meaning because a module somewhere grew a new
item.

### A missing use

Leave out a `use` line, and the compiler usually knows which one you
meant:

```vole
mod count {
    pub fn add_words(n: i64) -> i64 {
        n
    }
}

fn main() {
    println(f"{add_words(3)}");
}
```

```err
error[type error]: undefined variable 'add_words'
 --> main.vl: line 8, column 16
  = help: add `use crate::count::add_words;`
  = try: volec fix --suggested main.vl
```

The `try:` line adds it. For a whole program that's missing several,
`volec fix --only imports main.vl` writes every `use` line it can work
out, for your own modules' items and for the standard library's.

> **If you know Rust:** `mod`, `use`, `pub`, `crate`, `self` and
> `super` work as you expect, without `pub(crate)` or `extern crate`.
> There is no Cargo and no package manager yet: a program is the files
> its root names, and `std`. That's a gap a pre-1.0 language still has
> to fill.

## The prelude

A few names work in every file without a `use`: `println` and `print`,
`Vec`, `String`, `HashMap`, `Option` with `Some` and `None`, `Result`
with `Ok` and `Err`, `Gpa`, `read_stdin_in`, `assert`, `panic`, and a
few dozen more. They are the *prelude*. Everything else in the standard
library you import, like `use std::fs;`, or write as a path,
`std::fs::read_to_string_in(...)`.

If your program defines a name the prelude also has, yours wins in that
module. A function of your own called `trim` hides the prelude's, and
nothing breaks if a later release adds a prelude name you already use.

## Reading files and arguments

Now let's make the word counter count the words in files instead of
stdin, so that `wc notes.txt diary.txt` counts both. Here is the new
`main.vl`. `count.vl` and `report.vl` don't change; they are shown
again only so the listing is complete:

```vole main.vl
// wc: the most common words in the files named on the command line.
mod count;
mod report;

use std::env;
use std::fs;
use std::io;

fn run(gpa: Gpa) -> io::Result<()> {
    let args: Vec<str> = env::args().collect_in(gpa);
    var counts: HashMap<String, i64> = HashMap::new_in(gpa);
    for path in args[1..] {
        let text = fs::read_to_string_in(path, gpa)?;
        count::add_words(&counts, text, gpa);
    }
    let n = match env::get_in("WC_TOP", gpa) {
        Ok(s) => s.parse::<i64>().unwrap_or(5),
        Err(_) => 5,
    };
    let top = report::top(counts, n, gpa);
    report::print_table(top);
    Ok(())
}

fn main(gpa: Gpa) -> i32 {
    match run(gpa) {
        Ok(()) => 0,
        Err(e) => {
            eprintln(f"wc: {e}");
            1
        }
    }
}
```

```vole count.vl
// Counting the words of a text.

// Letters, digits and apostrophes are parts of words. So is every
// byte of a non-ASCII character (0x80 and up), so "café" stays whole.
fn is_word_byte(b: u8) -> bool {
    match b {
        'a'..='z' | 'A'..='Z' | '0'..='9' | '\'' => true,
        0x80..=0xff => true,
        _ => false,
    }
}

// The word without the punctuation around it: "end!" is "end".
fn trim_punct(word: str) -> str {
    var start = 0;
    var end = word.len();
    while start < end && !is_word_byte(word[start]) {
        start += 1;
    }
    while end > start && !is_word_byte(word[end - 1]) {
        end -= 1;
    }
    word[start..end]
}

// Adds the words of text to counts, lowercased.
pub fn add_words(counts: inout HashMap<String, i64>, text: str, gpa: Gpa) {
    for word in text.split_whitespace() {
        let w = trim_punct(word);
        if w.is_empty() {
            continue;
        }
        counts.get_or_insert(w.to_lowercase_in(gpa), 0)[0] += 1;
    }
}
```

```vole report.vl
// The table of the most common words.

pub fn top(counts: HashMap<String, i64>, n: i64, gpa: Gpa) -> Vec<(String, i64)> {
    var pairs: Vec<(String, i64)> = Vec::new_in(gpa);
    for (word, k) in counts.iter() {
        pairs.push((word.clone(), k));
    }
    pairs.sort_by(|a, b| if a.1 != b.1 { b.1 - a.1 } else { a.0.cmp(b.0) });
    pairs.truncate(n);
    pairs
}

pub fn print_table(rows: [(String, i64)]) {
    for row in rows {
        println(f"{row.0:<12}{row.1:>5}");
    }
}
```

Let's make two files for it to read, and run it:

```console
$ volec main.vl -o wc
ok: built wc
$ printf 'the cat sat on the mat\n' > a.txt
$ printf 'the dog sat on the cat\n' > b.txt
$ ./wc a.txt b.txt
the             4
cat             2
on              2
sat             2
dog             1
```

There are three new things in `run`: the arguments, the files, and the
environment.

### The command line

```vole skip
    let args: Vec<str> = env::args().collect_in(gpa);
```

`std::env` is the module for what a program gets from whoever started
it. `env::args()` gives the command-line arguments one at a time, each a
`str`; `collect_in(gpa)` keeps them in a `Vec`. The first argument is
the program's own name (`./wc`), so the loop starts at the second:
`args[1..]` is the slice of all the others.

### Reading a file

```vole skip
        let text = fs::read_to_string_in(path, gpa)?;
```

`std::fs` is the module for the file system, and
`fs::read_to_string_in` reads a whole file into a `String`. It takes an
allocator, as everything that allocates does, and it returns an
`io::Result<String>`: either the text, or an `io::Error` saying why the
file couldn't be read. The `?` passes an error up to `run`'s caller
([chapter 6](06-errors.md) explains `?`), which is why `run` returns
`io::Result<()>`.

### The environment

The *environment* is a set of named strings every program inherits
from whoever started it: `HOME`, `PATH`, and any you set yourself.
`env::get_in(name, gpa)` reads one, as a `Result`, because it may not be
set. The word counter reads `WC_TOP`, how many rows to print, and falls
back to 5 when it's missing or isn't a number. Set it for one run:

```console
$ WC_TOP=2 ./wc a.txt b.txt
the             4
cat             2
```

`std::cli` has a real argument parser, with flags, options and a
`--help` text; chapter 18 uses it to build a complete command-line
tool.

## Exit status

`main` returns an `i32`, the program's exit status: 0 when `run`
worked, 1 when it returned an error. Ask for a file that isn't there:

```console
$ ./wc a.txt nope.txt
wc: No such file or directory (os error 2)
$ echo $?
1
```

On an `Err`, `main` prints the error to stderr with `eprintln`, the
stderr twin of `println`, and returns 1. An `io::Error` prints the way
the operating system describes the problem. Most programs would add the
file's name to the message; that's one of the exercises at the end.

Splitting the program into a `run` that returns a `Result` and a short
`main` that turns it into a message and a status is a common shape. It
keeps every `?` in `run`, and every decision about what the user sees in
one place.

When the default message is all you need, `main` can return the
`Result` itself. Then an `Err` prints `Error: ` and the error's debug
form, and the program exits with status 1:

```vole
use std::fs;
use std::io;

fn main(gpa: Gpa) -> io::Result<()> {
    let text = fs::read_to_string_in("no-such-file.txt", gpa)?;
    println(f"{text.len()} bytes");
    Ok(())
}
```

```out exit=1
Error: Os { code: 2, kind: NotFound, message: "No such file or directory" }
```

That's fine for a quick tool, but the message is written for the
programmer. A program for other people usually has the `run` and `main`
pair.

## Writing files, and reading them a line at a time

`fs::read_to_string_in` and its partner `fs::write` handle a whole file
at once. For more control, open a `File` and wrap it in a `BufReader` or
a `BufWriter`, which read and write in large blocks:

```vole files.vl
use std::fs;
use std::fs::File;
use std::io;
use std::io::{BufReader, BufWriter, writeln};

fn main(gpa: Gpa) -> io::Result<()> {
    fs::write("notes.txt", "first line\n")?;
    fs::append("notes.txt", "second line\n")?;
    {
        var w = BufWriter::new(File::create("squares.txt")?);
        for i in 1..4 {
            writeln(&w, f"{i} squared is {i * i}")?;
        }
    }
    var r = BufReader::new(File::open("squares.txt")?);
    for line in r.lines_in(gpa) {
        let line = line?;
        println(f"read: {line}");
    }
    let notes = fs::read_to_string_in("notes.txt", gpa)?;
    print(notes);
    Ok(())
}
```

```out
read: 1 squared is 1
read: 2 squared is 4
read: 3 squared is 9
first line
second line
```

`fs::write` replaces a file's contents and `fs::append` adds to them.
`File::create` makes a file (or empties one that exists), and
`writeln(&w, ...)` writes a line to it; the `&` is there because writing
changes the writer. The writer lives in a block of its own: at the end
of the block it is dropped, which writes out what's left in its buffer
and closes the file, before we open the file again to read it.
`lines_in` gives the lines one at a time, each a `Result`, because
reading can fail halfway through.

### Directories

`fs::read_dir` lists a directory. Each entry is a `Result` too:

```vole list.vl
use std::fs;
use std::io;

fn main(gpa: Gpa) -> io::Result<()> {
    var names: Vec<String> = Vec::new_in(gpa);
    for entry in fs::read_dir(".")? {
        let entry = entry?;
        let name = entry.file_name() as str;
        if name.ends_with(".txt") {
            names.push(String::from_in(name, gpa));
        }
    }
    names.sort();
    for n in names {
        println(f"{n}");
    }
    Ok(())
}
```

```console
$ volec list.vl -o list
ok: built list
$ touch b.txt a.txt c.md
$ ./list
a.txt
b.txt
```

A directory's entries come in whatever order the file system keeps
them, so we sort the names. `file_name()` gives a `Path`, the standard
library's type for file names, and `as str` reads it as text.
`std::path` has the rest of what you do with paths: `extension()`,
`parent()`, `join_in(other, gpa)` and so on.

## Running other programs

`std::process::Command` starts another program and waits for it:

```vole run.vl
use std::process::Command;

fn main(gpa: Gpa) {
    var c = Command::new("echo");
    c.arg("hello");
    c.arg("from echo");
    let out = c.output_in(gpa).unwrap();
    println(f"echo exited with {out.status.code():?}");
    let text = String::from_utf8(out.stdout).unwrap();
    print(f"it printed: {text}");

    var f = Command::new("false");
    let st = f.status().unwrap();
    println(f"false succeeded: {st.success()}");
}
```

```out
echo exited with Some(0)
it printed: hello from echo
false succeeded: false
```

`Command::new` names the program, and each `arg` adds one argument.
`output_in` runs it, collects what it printed (so it needs an
allocator), and gives back its exit status and its output as bytes;
`String::from_utf8` checks that they are text. `status()` runs a
program and only waits for its exit status, letting its output go
straight to yours. Both return a `Result`, because the program might
not exist.

Notice that `c` is a `var`, and the arguments are added one statement
at a time. `arg` changes the command and returns nothing, so calls
can't be chained:

```vole
use std::process::Command;

fn main(gpa: Gpa) {
    let out = Command::new("echo").arg("hi").output_in(gpa).unwrap();
    print(String::from_utf8(out.stdout).unwrap());
}
```

```err
error[type error]: no method 'output_in' on type '()'
 --> main.vl: line 4, column 15
  = help: no method of that name; the nearest: 'fmt_debug'
```

The message is about the symptom: `.arg("hi")` returned `()`, the empty
value, and `()` has no `output_in`. When you see a method missing on
`()`, look at the call before it.

> **If you know Rust:** the names are Rust's (`Command`, `arg`,
> `output`, `status`), but there is no builder chaining: a method that
> changes its value takes it `inout` and returns nothing, so
> `Command::new(p).arg(a)` doesn't give you the command back.

## Summary

The word counter is now three modules that read files. On the way you
saw:

- `mod name;`, which loads `name.vl` (or `name/mod.vl`) as a module, and
  inline `mod name { ... }`;
- that items are private to their module unless they're `pub`, and
  that `volec fix` adds a missing `pub` or `use` for you;
- paths (`crate::`, `self::`, `super::`, `std::`) and `use` lines, with
  braces and `as`, and why there are no wildcard imports;
- the prelude, the names every file has;
- `fs::read_to_string_in`, `fs::write`, `File`, `BufReader`,
  `BufWriter`, `writeln` and `fs::read_dir`, all returning `io::Result`;
- `env::args()` and `env::get_in` for the command line and the
  environment, and `Command` for running other programs;
- the exit status, from `main`'s `i32` or from `main` returning a
  `Result`.

The functions in these modules can now do a lot: allocate, read files,
print. The next chapter shows how the compiler keeps track of what
each function may do, and how to make it hold a function to a promise.

## Try it yourself

- Make the word counter's error message name the file:
  `wc: nope.txt: No such file or directory (os error 2)`. (Match on
  `fs::read_to_string_in(...)` instead of using `?`.)
- With no file names on the command line, make `wc` read stdin, as it
  did at the start of the chapter.
- Add a module `filter.vl` with a `pub fn is_boring(word: str) -> bool`
  that's true for "the", "a" and "and", and leave those words out of
  the count.
