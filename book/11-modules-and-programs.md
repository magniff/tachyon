# 11. Modules and programs

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

Organize code in files, and talk to the outside world. By the end the
reader can:

- split a program into modules (`mod name;`, files and directories),
  control visibility with `pub`, and import with `use` (by name, with
  `as`, re-exporting with `pub use`);
- read and write files, walk a directory, read command-line arguments
  and environment variables, and run another program;
- return a meaningful exit status.

## Running example

Chapter 7's word counter, split into `main.vl`, `count.vl` (the
counting) and `report.vl` (the table), as a multi-file program (`vole
main.vl`, `vole count.vl`, `vole report.vl` blocks in a row, so the
harness builds them together). It then reads the files named on its
command line (`env::args()`) instead of stdin, with `fs::read_to_string_in`,
and reports a missing file as an `io::Error` with exit status 1.

## Sections

1. **Modules.** `mod count;` loads `count.vl` next to the file;
   `count/mod.vl` for a directory; inline `mod util { ... }`. A file is a
   module; the files on the command line are the root (`crate`).
2. **Visibility.** Private by default (to the module and its children),
   `pub` to share. Struct fields are as visible as the struct.
3. **Paths and use.** `crate::`, `self::`, `super::`, `std::`; `use a::{b,
   c as d};`; a sibling module by name. No wildcard imports, and why:
   every name in a file can be traced to its definition, by a person or a
   tool. `volec fix --only imports` adds missing `use` lines.
4. **The prelude.** What every file gets without `use`, and that a
   program's own definition of a prelude name hides it.
5. **Files.** `fs::read_to_string_in(p, gpa)?`, `fs::write`,
   `File::open`/`create`, `BufReader`/`BufWriter`, `writeln(&w, f"..")?`,
   `fs::read_dir`, `Path`. `io::Result` and `?`.
6. **Arguments and the environment.** `env::args()` (views; collect with
   `collect_in(gpa)`), `env::get_in(name, gpa)`. Mention `std::cli` and
   point to chapter 18 for real argument parsing.
7. **Running programs.** `process::Command`, `c.arg(..)` (it changes `c`:
   no chaining), `output_in(gpa)?`, `status()`.
8. **Exit status.** From `main`'s `i32`, or `main -> Result` (chapter 6).

## Errors to show

- `import.wildcard` for `use count::*;` (show the message and its
  `try:`).
- A private item used from another module, with `try: volec fix --only
  pub`.
- A missing `use`, with the `use` line the error suggests.
- A missing file at run time: `No such file or directory (os error 2)`
  through `eprintln(f"{e}")` and exit 1 (`out exit=1`; write the file
  path into a temp dir the test controls, or use a path that never
  exists).

## Asides

- If you know Rust: the same `mod`/`use`/`pub`, without `pub(crate)`,
  `extern crate` or Cargo; no packages yet (a pre-1.0 gap: say so).
- If you know Python or JavaScript: no import-time code runs; modules
  are compiled together into one program.

## Sources

`volec guide modules`, `guide io`, `guide example` (a program in three
files), examples/httpd (a bigger multi-module program).
