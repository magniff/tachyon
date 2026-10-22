# Writing for the Vole Book

This is the guide for anyone writing or revising a chapter. Read
chapters 1 and 2 before you start: they are the reference for
everything below.

## What the book is

**A tutorial, not a specification.** Vole is pre-1.0 and still being
designed, so the book teaches by example and explains intent; it does
not try to pin down every rule.

- Teach the common case well. Leave corner cases out, or give them one
  sentence and a pointer (`volec guide TOPIC`, docs/grammar.md).
- No normative language: no "shall", no grammar productions, no
  exhaustive lists of rules. "You can", "the compiler checks", "usually"
  are fine.
- Say plainly when something is missing or likely to change ("vole has
  no `char` type yet"). Don't apologize, and don't promise dates.
- Keep chapters lean: a rewrite after a language change should be
  cheap. A chapter of about 3,000 to 5,000 words is right; if it grows
  past 6,000, it's probably two chapters or has corner cases to cut.
- The test harness catches drift (below), so write confidently about
  what the current compiler does, and let the tests tell us when it
  changes.

The reader is a programmer who knows at least one language, not
necessarily Rust, C++ or anything low-level. The guide
(`compiler/guide/*.md`, `volec guide`) is the opposite document: terse,
complete, for experienced programmers and AI agents. Use it as your
source; don't copy its style.

## Voice

- Warm, plain and concrete. Talk to the reader as "you"; "we" for things
  we do together ("let's add a loop").
- Short paragraphs: two to five sentences. One idea per paragraph.
- Show, then explain. Every concept appears in code first, then the
  prose says what happened and why. Never a paragraph of rules before
  the example.
- Motivate before you explain: what problem does this solve? A sentence
  is often enough ("Reading can fail, so...").
- Explain *why* vole does it this way when it differs from what the
  reader probably knows (explicit allocators, no references, effects).
  One or two sentences; the design docs have the long version.
- Prefer common words. Introduce each term once, in italics, with its
  meaning (*view*, *panic*, *allocator*), then use it consistently.
- Don't overpromise: "the compiler checks that..." only when it does
  (verify with a block). No marketing words (blazing, powerful,
  seamless).
- Errors are part of the teaching. Show a deliberate mistake, the real
  message, and how to read it, a few times per chapter, especially for
  the errors a newcomer will meet.

## Shape of a chapter

1. `# N. Title`, then a short opening: what the reader will be able to
   do by the end.
2. Sections (`##`) that each introduce one idea with a complete,
   runnable example where possible. Use `###` for sub-steps.
3. A running example that grows through the chapter beats many
   unrelated snippets.
4. `## Summary`: a short list of what was covered, then one sentence
   leading to the next chapter.
5. Optionally `## Try it yourself`: two or three small exercises.

Cross-reference by chapter number and title ("chapter 4 explains
this"), with a link the first time: `[chapter 4](04-value-semantics.md)`.
Don't explain a later chapter's topic early; one sentence and a pointer
is enough.

## "If you know Rust" and other asides

Use a block quote that starts with the bold label:

```markdown
> **If you know Rust:** `&line` here is not a reference. ...
```

- Use them only where vole looks like Rust but means something else, or
  where a Rust habit gives an error. Keep them to two to four sentences.
- The main text must never need the aside: a reader who skips them
  loses nothing.
- "If you know C", "If you know Go", "If you know Python" asides follow
  the same rules, sparingly.

## Conventions

- The language is *vole* (lowercase in prose, like a common noun; "Vole"
  at the start of a sentence), the compiler `volec`, source files `.vl`.
- Commands are written as the reader types them, with `volec` on the
  `PATH` (chapter 1 sets that up): `volec guess.vl -o guess`.
- File names: a program the reader saves gets a name (`guess.vl`), and
  the prose says so the first time ("Start a new file, `guess.vl`").
- Code style is `volec fmt`'s: four-space indents, braces on the same
  line. Run `volec fmt` on a program before pasting it.
- Prefer `str` and `String` for text in new examples; use `[u8]` and
  `Buf` when the topic is bytes.
- Keep lines in code blocks under about 90 characters, so they read on
  GitHub without scrolling.
- Markdown that renders on GitHub: no HTML except the hidden-code
  comment below, no footnotes, tables only when they really are tables.
- Plain ASCII punctuation is preferred (`--`, quotes `"`), so files are
  easy to search; non-ASCII is allowed where the topic is Unicode.

## Code blocks and the test harness

Every block fenced as `vole` is checked by `tests/book/run.sh`
(`tests/run.sh book` in the full suite). What a block is, and what is
checked, comes from its fence. The words after `vole` are annotations.

| fence | what it is | what is checked |
|---|---|---|
| ` ```vole ` | a snippet | compiles with `--deny-warnings` (see below for how it's wrapped) |
| ` ```vole NAME.vl ` | a file the reader saves | compiles as it is, never wrapped |
| ` ```vole ... warn ` | code that has a warning on purpose | compiles; warnings allowed |
| ` ```vole ... skip ` | an excerpt of a listing already shown, or code that can't compile on purpose without an error to show | nothing |
| ` ```in ` | after a vole block: the program's stdin | used by the next `out` |
| ` ```out ` | after a vole block (and its `in`) | the program runs; stdout and stderr together match exactly, trailing blanks aside; exit status 0 |
| ` ```out exit=N ` | the same | ...with exit status N (101 for a panic, 1 for `main -> Result` failing) |
| ` ```err ` | after a vole block | the build fails, and the compiler prints exactly this, in the form a terminal shows |
| ` ```console ` | a shell session | each `$ CMD` line runs; the lines after it are its output, exactly; `...` stands for any number of lines |
| ` ```sh `, ` ```text `, others | commands to read, not run; illustrations | nothing |

### Snippets

An unnamed ` ```vole ` block is compiled as `main.vl`:

- if a line starts with `fn main(`, it is a whole program;
- else, if every line at the left margin starts an item (`fn`,
  `struct`, `enum`, `impl`, `trait`, `use`, `const`, `//`, `#[`, `}`...),
  it's items, and an empty `main` is added at the end;
- else it's statements, compiled as the body of `fn main(gpa: Gpa) ->
  i32` (leading `use` lines stay above it; `gpa` is in scope).

For `out`, `err` or `console` blocks that show line numbers, use a whole
program or a named file, so the numbers the reader sees are the ones in
the block. Statements are wrapped, which moves them down a line.

### Programs in files

` ```vole NAME.vl ` blocks are files. Several in a row (prose between
them is fine, but no other code block) are one program: write
`main.vl` and `count.vl` blocks one after the other, then the `out` or
`console` block. A file name that appears again starts a new program,
so successive versions of `guess.vl` in one chapter are separate
programs. The root is `main.vl` if there is one, else the first file.
Error positions in `err` blocks then show the reader's file name
(`--> guess.vl: line 10, column 20`).

### Output

- `out` is compared exactly. Paste it from a real run; never type it.
- `err` is compared exactly, in the terminal ("human") form a build
  prints: `error[KIND]: message`, ` --> FILE: line L, column C`, `  =
  help:` and `  = try:` lines. Get it with `volec FILE.vl -o prog` in a
  terminal (or `--diagnostics=human`).
- In a `console` block, `volec` behaves as in a terminal: a build prints
  the human form; `volec check` and the tools print one line per error.
  Each session runs in a fresh directory holding the files of the last
  vole block or program before it; later sessions after the same program
  share that directory, so a session can build in one block and run in
  the next. stdin is empty: use a pipe (`echo 42 | ./guess`) or make a
  file in the session (`$ printf '1 2\n' > in.txt`). `$?` works as at a
  prompt (`$ echo $?`).
- Use `...` on a line of its own for output that varies or doesn't
  matter (timings, a long listing).

### Things the harness can't check

- **Interactive sessions**, where the reader types between the
  program's lines, are ` ```text ` blocks copied from a real run. Show
  each program's behaviour in a checked `in`/`out` pair too, and keep
  interactive transcripts to one or two per chapter.
- **Randomness and time.** Make the checked version deterministic (a
  fixed secret, a fixed seed, `Xoshiro256pp::seed_from_u64`) and show
  the random one's run as ` ```text `, saying it will differ. Timings are
  ` ```text ` blocks labelled as one machine's numbers.
- **Installation and editor setup** are ` ```sh ` blocks: they aren't
  run, so check them by hand when you touch them.

### Hidden code

When a snippet needs a definition shown in an earlier listing, put the
definition in an HTML comment right before the block; it's appended to
the snippet's file, and GitHub doesn't show it:

````markdown
<!-- vole-hidden
struct Song { title: str, seconds: i64 }
-->
```vole
fn minutes(s: Song) -> i64 { s.seconds / 60 }
```
````

Use it sparingly: a reader who copies the snippet alone gets an error.
Prefer complete programs.

### Running the tests

```sh
bootstrap/bootstrap.sh --dev           # builds target/volec, if needed
tests/book/run.sh -f book/NN-slug.md   # one chapter
tests/book/run.sh                      # the whole book (and the table of contents)
```

Each block reports `pass CHAPTER:LINE` or `FAIL CHAPTER:LINE` with the
difference, the line being where the block's fence starts. Run your
chapter's tests before every commit; a chapter is done when they all
pass and nothing is ` skip ` that could be checked.

## Getting real output

- Build and run your examples in a scratch directory, and paste what
  they print. Then let the harness confirm it.
- `volec try 'EXPR'` answers "what does this do" quickly.
- `volec guide TOPIC`, `volec guide --find WORDS` and `volec explain
  CODE` are where the facts are. If the guide and the compiler disagree,
  the compiler wins: write what it does, and report the difference.
- If the compiler accepts something the guide says it rejects (or the
  other way round), don't teach either behaviour as a rule; note it in
  the outline or in the commit message for review.

## Chapter status

An outline file starts with a "Status: outline" note. When the chapter
is written, remove the note and the outline headings (Goal, Sections,
Errors to show, Sources), and drop *(outline)* from its line in
[README.md](README.md).
