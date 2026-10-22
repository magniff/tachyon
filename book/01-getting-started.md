# 1. Getting started

In this chapter you install vole, write the traditional first program,
and meet the compiler. By the end you will know how to build and run
a program, read an error message, try out a line of code without
writing a whole program, and ask the compiler to explain itself.

## Before we begin: vole is young

Vole is a **pre-1.0 language that is still being designed**. Releases
come often, and they change things: a keyword gets a new spelling, a
library function moves, a rule gets stricter. When that happens, the
compiler usually tells you what to write instead, and for bigger changes
it ships a `volec fix` command that rewrites your code for you.

This book tracks the current release. Every example in it is compiled
and run by the book's own test suite, so the code you see works with
the compiler it was written for. If you are using a newer compiler and
an example no longer builds, the error message is your best guide, and
the book will catch up soon.

## Who this book is for

You have written programs before, in any language: Python, JavaScript,
Go, C, Java, it doesn't matter. You know what a variable, a function
and a loop are. You do not need to know Rust or C++, although vole will
look familiar if you do.

Some vole code looks like Rust but means something different. Where
that happens, you will see a note like this one:

> **If you know Rust:** these asides are for you. Everyone else can skip
> them.

## Installing vole

Vole runs best on Apple silicon Macs (aarch64 macOS). It also works on
64-bit ARM Linux. Other platforms are not supported yet.

Vole's compiler, `volec`, is written in vole. That raises a question:
what compiles the compiler? The answer is a chain. A small compiler
written in Rust compiles the first release of vole, that release
compiles the next one, and so on up to today. The bootstrap script
replays that chain on your machine, so you need a few tools first:

- `git`;
- Rust, installed with [rustup](https://rustup.rs) (only the oldest link
  of the chain needs it);
- a C compiler: on macOS, the Xcode command line tools
  (`xcode-select --install`); on Linux, `cc` from your distribution.

Then clone the repository and run the bootstrap:

```sh
git clone https://github.com/magniff/vole
cd vole
git fetch --tags
bootstrap/bootstrap.sh
```

The first run takes a while, because it builds every release in turn
and runs each one's tests. Later runs reuse what was already built.
When it finishes, the compiler is at `target/volec`.

Put it on your `PATH` so you can type `volec` from anywhere. Add this
line to your shell's startup file (`~/.zshrc` or `~/.bashrc`), with the
path to your clone:

```sh
export PATH="$HOME/vole/target:$PATH"
```

Open a new terminal and check that it works:

```sh
volec --version
```

It prints the compiler's version and the platform it targets.

## Hello, world

Make a directory for your vole projects, and in it a file called
`hello.vl`. Vole source files end in `.vl`. Type this into it:

```vole hello.vl
fn main() {
    println("Hello, world!");
}
```

Now compile it and run the result:

```console
$ volec hello.vl -o hello
ok: built hello
$ ./hello
Hello, world!
```

That's it: you wrote a vole program. `volec hello.vl -o hello` read
the source, compiled it to machine code, and wrote an executable named
`hello` (that's what `-o` means: the output). Then `./hello` ran it.

The compiler's `ok: built hello` line is its way of saying nothing went
wrong. You'll see a line like it at the end of every successful build.

## What's in a vole program

Let's look at those three lines again.

```vole
fn main() {
    println("Hello, world!");
}
```

`fn main()` declares a function named `main`. Every program has one:
it's where the program starts. The empty parentheses mean `main`
takes no parameters, and the body of the function goes between the
curly braces `{` and `}`.

Inside the body, `println("Hello, world!");` calls the function
`println`, which prints its argument and then ends the line. The text
in double quotes is a string literal. You didn't have to import
`println` from anywhere: a small set of very common names, called the
*prelude*, is available in every vole file.

The line ends with a semicolon. In vole, statements end with `;`.

Indentation is four spaces by convention. The compiler doesn't care
about indentation, but `volec fmt` (which you'll meet later) lays code
out this way, and every example in this book follows it.

> **If you know Rust:** there are no macros in vole, so it's
> `println(...)`, not `println!(...)`. Formatting values into text is
> done with f-strings, which you'll see in the next chapter.

## When things go wrong

Sooner or later, you'll make a typo. Let's make one on purpose, so you
know what it looks like. Misspell `println` in `hello.vl`, and build it again:

```vole hello.vl
fn main() {
    printn("Hello, world!");
}
```

```err
error[type error]: undefined variable 'printn'
 --> hello.vl: line 2, column 5
  = help: did you mean 'print'?
```

Every vole error has the same shape. The first line says what kind of
error it is (here a `type error`, the compiler's name for most problems
with names and types) and what went wrong. The `-->` line says where:
the file, the line and the column. Most errors end with a `help:` line
suggesting a fix. Here it guessed `print`, which also exists (it prints
without ending the line); we meant `println`, of course.

Here's a different mistake, a missing semicolon:

```vole hello.vl
fn main() {
    println("Hello, world!")
    println("Goodbye!");
}
```

```err
error[parser error]: expected ';' or '}' after expression, got 'println'
 --> hello.vl: line 3, column 5
```

Notice that the error points at line 3, not line 2. The compiler only
discovers the semicolon is missing when it reaches the next word and
finds that it can't continue. When an error's position looks wrong,
look just before it.

If a file has several errors, the compiler reports them all at once,
and it's worth fixing them from the top: an early error can confuse the
compiler about what comes after it.

### Checking without building

Compiling to machine code takes a moment. When you just want to know
whether your program is correct, `volec check` is faster: it looks
for errors and stops there. Run it on the file with the missing
semicolon:

```console
$ volec check hello.vl
hello.vl:3:5: error[parser error] expected ';' or '}' after expression, got 'println'
```

`check` prints each error on a single line, `FILE:LINE:COLUMN:` first,
which is handy when there are many of them. It's also the form editors
and other tools read. Put the semicolon back and run it again, and it
answers `ok: 0 errors in hello.vl`.

## Exit status

When a program finishes, it hands a number back to whoever started it,
usually the shell. Zero means success; anything else means some kind
of failure. Scripts and build tools look at that number.

`main` can return it. Save this as `status.vl`:

```vole status.vl
fn main() -> i32 {
    println("Something went wrong.");
    3
}
```

`-> i32` says that `main` returns a 32-bit integer. The last line of
the body, `3`, has no semicolon: in vole, the last expression of a
block is the block's value, so that's the value `main` returns. (You'll
see much more of this idea in chapter 3.)

```console
$ volec status.vl -o status
ok: built status
$ ./status
Something went wrong.
$ echo $?
3
```

The shell keeps the last exit status in `$?`. A `main` without `->
i32`, like the one in `hello.vl`, always exits with 0.

## Trying things out with `volec try`

Sometimes you want to know what a single expression does, and writing
a whole program for it is too much ceremony. `volec try` runs a
snippet and tells you its type and its value:

```console
$ volec try '6 * 7'
i64 = 42
$ volec try 'let name = "vole"; name.len()'
i64 = 4
```

`i64` is a 64-bit integer, the type vole gives a whole number unless
you ask for another. Keep `volec try` in mind as you read: whenever
you wonder how something behaves, try it.

## Asking the compiler

The compiler knows its own language, and it will tell you about it.

`volec explain` describes an error in more detail. Give it the kind or
code in square brackets from an error message:

```sh
volec explain 'type error'
```

`volec guide` prints a compact description of the whole language.
It's written in a dense style meant for experienced programmers and AI
agents rather than for learning, but it's a useful reference once you
know the basics. `volec guide --list` shows its topics, and `volec
guide --find WORDS` finds the paragraphs about something:

```sh
volec guide --find read a line
```

You'll meet more of the compiler's tools as the book goes on. Chapter
17 is about them: vole was built so that the compiler can answer
questions about your program and change it safely, for you and for an
AI assistant working with you.

## Setting up an editor

Any text editor works for vole. If you use Visual Studio Code, the
repository has an extension in `editors/vscode` that highlights vole
code and shows errors as you type. To build and install it, you need
Node.js 18 or newer:

```sh
cd editors/vscode
npm install
npm run compile
npm run package
code --install-extension vole.vsix
```

The extension starts `volec lsp`, the compiler's language server, in
the background. That gives you error messages in the editor, "go to
definition", "find references", and hovers that show a function's
signature and what it does (whether it allocates memory, does I/O, and
so on). It finds `volec` on your `PATH`; if it doesn't, set
`vole.server.path` in VS Code's settings to the full path of
`target/volec`.

Other editors that speak the Language Server Protocol can run `volec
lsp` too.

## Summary

You now have a working vole setup. You've seen:

- that vole is pre-1.0, so details will change, and the compiler will
  help you follow them;
- how to build a program (`volec FILE.vl -o NAME`) and run it;
- that `main` is where a program starts, and that it can return an exit
  status;
- what an error looks like, and that `volec check` finds errors
  quickly;
- `volec try` for experiments, and `volec explain` and `volec guide` for
  questions.

In the next chapter you'll write a real, if small, program: a guessing
game. It will introduce variables, input, decisions and loops all at
once, and the chapters after it explain each idea properly.
