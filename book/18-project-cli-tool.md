# 18. Project: a command-line tool

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

Put the book together in one program a reader would actually use. By
the end the reader has built, tested and polished `tally`, a text
statistics tool in the spirit of `wc`, and can structure a small real
program on their own.

## The program

```text
usage: tally [options] [file]...
  -w, --words        count words (default: lines, words, bytes)
  -t, --top N        print the N most common words
  -i, --ignore-case  fold case before counting
  -h, --help         this help
```

`tally -t 3 notes.txt` prints per-file and total counts, then the top
words as an aligned table. Reads stdin when no file is given. A missing
file is an error on stderr with exit status 1; a bad option is `std::cli`'s
error with its `try:` line and exit 2.

## Sections (each step a complete program with checked output)

1. **Plan the pieces.** Modules: `main.vl` (arguments and I/O),
   `count.vl` (pure counting: `#[no_io]`, takes text and an allocator),
   `report.vl` (formatting). Why the counting core is pure: easy to test,
   impossible to break by adding a stray print.
2. **Arguments with std::cli.** `Command::new_in`, `Arg::flag`,
   `Arg::option(..).short(..).default(..)`, `Arg::positional(..)
   .multiple()`, `parse_or_exit(env::args())`, `get_as::<i64>`. Show
   `--help` output and a misspelled option's error (console blocks).
3. **Counting.** Lines, words, bytes over a `str`; word frequencies in a
   `HashMap<str, i64>` of views into the text (chapter 4 pays off: no
   copies, and the compiler checks the views don't outlive the text);
   case folding with `to_lowercase_in`.
4. **Memory.** One arena per file (`arena_scope`) for the folded words
   and the map, so each file's scratch memory is freed at once.
5. **Reporting.** Sorting the pairs (`sort_by` on count, then word),
   f-string alignment, totals.
6. **Errors.** An `enum TallyError { Io(io::Error), ... }` with `From`,
   `?` throughout, `main` printing the error and returning 1.
7. **Tests.** `#[test]`s for the counter, a `#[property]` (word counts
   sum to the number of words), `tests/basic.in` / `basic.out` program
   cases, `volec test` (console).
8. **Checking the promises.** `volec query effects count` (console)
   shows the core does no I/O; contracts on the report's column widths.
9. **Polish and next steps.** `volec fmt`, `-O2`, timing on a large
   input (a `text` block with one machine's numbers). Where to go from
   here: examples/voltty (a terminal emulator), examples/httpd, std::gpu
   and std::window (`volec guide gpu`, `guide window`), the roadmap.

## Harness notes

The program's files are `vole main.vl` / `vole count.vl` / `vole
report.vl` blocks in a row. Input files the tool reads in console
sessions are made in the session itself (`$ printf 'a b\nb\n' >
notes.txt`), so the test needs nothing outside the chapter.

## Sources

`volec guide cli`, `guide io`, `guide text`, `guide allocators#arenas`,
`guide testing`, docs/design/cli.md.
