# 17. The tools, and working with an agent

Most of the time you read code in an editor and change it by typing.
That works, and it's how you'll write most vole. But some jobs are
tedious and error-prone by hand: finding every caller of a function,
renaming something used in a dozen files, adding a parameter to a
function and to all its calls. The vole compiler can do those jobs for
you, from the command line, and check each change before it writes
it.

This chapter is a tour of those tools. By the end you'll be able to ask
the compiler about a program by name, make checked edits and
refactorings and take them back, let the compiler fix errors it knows
the fix for, format code, and use all of it from your editor. The last
section is about working on a vole program with an AI assistant, which
uses the same tools.

## Why ask the compiler

Suppose you want to know where a function called `top` is used. A text
search for `top` finds it, but it also finds the local variable called
`top` in `run`, the word "top" in comments and in `WC_TOP`, and any
field or function of the same name somewhere else. It misses nothing only if nothing is renamed on
import. The compiler doesn't have this problem: it has already worked
out which `rows` each use refers to, through every `use` line, and it
knows that a comment is a comment.

So vole's compiler answers questions about a program by name, and makes
changes by name. Each command prints its answer one fact per line, so
you can read it, pipe it into other commands, or hand it to a program.
Vole was designed so that its whole toolchain can be driven from a
shell, by a person or by an AI assistant, and the rest of this chapter
is about what that looks like.

## The program

We'll work on the word counter from [chapter 11](11-modules-and-programs.md),
which reads the files named on its command line and prints their most
common words. It's chapter 11's last version, with one addition: an
`Order` that says how to sort the table, which `top` now takes. Here it
is, in its three files:

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
        count::add_words(&counts, &text, gpa);
    }
    let n = match env::get_in("WC_TOP", gpa) {
        Ok(s) => s.parse::<i64>().unwrap_or(5),
        Err(_) => 5,
    };
    let top = report::top(counts, n, report::Order::ByCount, gpa);
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

pub fn add_words(counts: inout HashMap<String, i64>, text: str, gpa: Gpa) {
    for word in text.split_whitespace() {
        let w = word.to_lowercase_in(gpa);
        counts.get_or_insert(w, 0)[0] += 1;
    }
}
```

```vole report.vl
// The table of the most common words.

// The order of the table's rows.
pub enum Order {
    ByCount,
    Alphabetical,
}

pub fn top(counts: HashMap<String, i64>, n: i64, order: Order, gpa: Gpa) -> Vec<(String, i64)> {
    var pairs: Vec<(String, i64)> = Vec::new_in(gpa);
    for (word, k) in counts.iter() {
        pairs.push((word.clone(), k));
    }
    match order {
        Order::ByCount => pairs.sort_by(by_count),
        Order::Alphabetical => pairs.sort_by(|a, b| cmp_of(a.0, b.0)),
    }
    pairs.truncate(n);
    pairs
}

// The most common first; words as common as each other, alphabetically.
fn by_count(a: (String, i64), b: (String, i64)) -> i64 {
    if a.1 != b.1 { b.1 - a.1 } else { cmp_of(a.0, b.0) }
}

pub fn print_table(rows: [(String, i64)]) {
    for row in rows {
        println(f"{row.0:<12}{row.1:>5}");
    }
}
```

Every session in this chapter runs in the directory holding these
files, and each one picks up where the last one left off. First, let's
make two files to count and check that the program works:

```console
$ printf 'the cat sat on the mat\n' > a.txt
$ printf 'the dog sat on the cat\n' > b.txt
$ volec main.vl -o wc
ok: built wc
$ ./wc a.txt b.txt
the             4
cat             2
on              2
sat             2
dog             1
```

## Reading a program

### query context

When you meet a function you haven't seen, the first question is
usually threefold: what does it do, what does it call, and who calls
it? `volec query context` answers all three at once:

```console
$ volec query context report::top
// crate::report::top	report.vl:9-20	effects: alloc(Gpa) panic diverge
pub fn top(counts: HashMap<String, i64>, n: i64, order: Order, gpa: Gpa) -> Vec<(String, i64)> {
    var pairs: Vec<(String, i64)> = Vec::new_in(gpa);
    for (word, k) in counts.iter() {
        pairs.push((word.clone(), k));
    }
    match order {
        Order::ByCount => pairs.sort_by(by_count),
        Order::Alphabetical => pairs.sort_by(|a, b| cmp_of(a.0, b.0)),
    }
    pairs.truncate(n);
    pairs
}
// calls (10)
...
// types (6)
...
// callers (1)
run	main.vl:20:23	let top = report::top(counts, n, report::Order::ByCount, gpa);
```

The first line is the item's full name, where it is (`report.vl`,
lines 9 to 20) and its effects, which chapter 12 explained. Then its
source. Then, under `// calls`, every function it
calls, with where each is defined and its signature, including the
ones in std; under `// types`, the types it uses; and under
`// callers`, who calls it. (We've cut the calls and types out of the
listing here, since the positions of things in std change with every
release.) Two of the calls look like this:

```text
crate::report::by_count	report.vl:23:4	fn	fn by_count(a: (String, i64), b: (String, i64)) -> i64
std::Vec::truncate	<std>:374:12	method	pub fn truncate(inout self, n: i64)
```

The fields on each line are separated by tabs, which makes them easy to
cut out with other tools.

`query context` keeps its answer to a page or two (`--budget N`
changes that), so it's safe to ask about something big. For just the source, there's `volec query show NAME`.

### Names

A NAME can be a plain name (`top`), a path (`report::top`,
`std::read_line`), a method (`Vec::push`), a field (`Point.x`), or a
place in a file (`main.vl:20`, the item on that line). A plain name that
means several things gets all of them. You don't need to say which
file the program starts at: the tools look for `main.vl` in the current
directory (or take the last argument ending in `.vl`).

### refs and callers

`query refs` lists every use of a name, grouped by file, with the kind
of use and the function it's in:

```console
$ volec query refs Order
# report.vl
4:10	def	pub enum Order {
9:57	type	report::top	pub fn top(counts: HashMap<String, i64>, n: i64, order: Order, gpa: Gpa) -> Vec<(String, i64)> {
15:9	type	report::top	Order::ByCount => pairs.sort_by(by_count),
16:9	type	report::top	Order::Alphabetical => pairs.sort_by(|a, b| cmp_of(a.0, b.0)),
# main.vl
20:46	type	run	let top = report::top(counts, n, report::Order::ByCount, gpa);
$ volec query callers add_words
# main.vl
14:16	call	run	count::add_words(&counts, &text, gpa);
```

Each line is `LINE:COLUMN`, then the kind (`def` for the definition,
`call`, `type`, and others), then the enclosing function, then the line
itself. `--count` gives just the number, and `--in FILE` limits it to
one file. `query callers` does the same for calls only.

### effects

Chapter 12 showed `query effects`. It works on a whole module too,
which is a quick way to check a design promise, here that the counting
module never does any input or output:

```console
$ volec query effects crate::count
crate::count::add_words	alloc(Gpa) panic diverge
```

`--why io` on a function explains an effect it has, call by call, down
to the line in std where it comes from.

There are more questions you can ask. `query items MODULE` lists a
module's items with their signatures (`query items std` lists the
standard library), `query own FILE:LINE:COL` shows what the compiler
knows about each variable at a point (chapter 4's moves and views),
and `query unused` lists what nothing uses. `volec query --help` lists
them all.

## Checked edits

### edit patch

`volec edit patch` changes text inside one item, found by name. Let's
widen the table's count column. Suppose we misremember what the format
says:

```console
$ volec edit patch print_table --old '{row.1:>4}' --new '{row.1:>6}'
error patch.no-match: OLD 1 is not in crate::report::print_table; nearest, line 29: println(f"{row.0:<12}{row.1:>5}");
try: volec edit patch print_table --old '{row.1:>5}' --new '{row.1:>6}'
```

Nothing was changed. The problem is one line with a stable code
(`patch.no-match`), then the nearest text that does exist, then a
`try:` line: the command we probably meant, ready to run as it is. Every
vole tool reports a problem in this shape. Running the `try:` line:

```console
$ volec edit patch print_table --old '{row.1:>5}' --new '{row.1:>6}'
patched crate::report::print_table	report.vl	+1 -1 lines
```

Because `edit patch` finds the item by name, it doesn't care which file
it's in or on what line, and the text must occur inside that item, so
it can't change a similar line somewhere else by accident.

### An edit that would break the program

Every edit is checked before it's written: the compiler checks the
whole program with the change in place, and if the change adds an
error, it writes nothing. Let's try to print a variable that doesn't
exist:

```console
$ volec edit patch print_table --old '{row.1:>6}' --new '{row.1:>6} {share}'
report.vl:29:42: error[type error] undefined variable 'share'  [edited: crate::report::print_table]
error edit.breaks: 1 new error; nothing written
try: volec edit patch print_table --old '{row.1:>6}' --new '{row.1:>6} {share}' --no-check
```

The error says what would go wrong, tagged `[edited: ...]` to show it
comes from our change, and `edit.breaks` says nothing was written. The
`try:` line offers `--no-check`, which writes the edit anyway; that's
for the rare case when you'll fix the error with a second edit right
after. `--dry-run` on any edit prints the change as a diff without
writing it.

For bigger changes, `volec edit replace NAME` replaces a whole item with
text from standard input, `edit insert` adds a new one, and `edit
delete` removes one. All of them are checked the same way.

## Refactoring

A *refactoring* is a change to a program's structure that leaves what
it does the same, like renaming a function. Done by hand, it means
finding every place to change, and missing one is an error at best.
`volec refactor` does the finding.

### rename

`add_words` would read better as `count_words`, and it's called from
another file:

```console
$ volec refactor rename count::add_words count_words
renamed crate::count::add_words to count_words	2 files	+2 -2 lines
$ volec query refs count_words
# count.vl
3:8	def	pub fn count_words(counts: inout HashMap<String, i64>, text: str, gpa: Gpa) {
# main.vl
14:16	call	run	count::count_words(&counts, &text, gpa);
```

Both the definition and the call changed. A rename changes the uses the
compiler resolved, so a comment that happens to say `add_words`, or a
different function of the same name in another module, is left alone.
`refactor rename` works on anything with a name: types, fields,
variants, modules, and local variables (give `FILE:LINE:COL` or
`FUNCTION::name`).

### signature

Let's give `count_words` a new parameter, `min_len`, so that it can
skip short words like "a" and "on". Adding a parameter means changing every call, so
`refactor signature` does both. `--add` takes the new parameter with a
value for the existing calls, and `--fill-calls` writes that value into
each of them:

```console
$ volec refactor signature count::count_words --add 'min_len: i64 = 1' --fill-calls
added parameter min_len: i64 to crate::count::count_words, 1 call	2 files	+2 -2 lines
$ volec query callers count_words
# main.vl
14:16	call	run	count::count_words(&counts, &text, gpa, 1);
```

The call in `run` now passes `1`, which keeps every word, as before.
(Without `--fill-calls`, the parameter keeps `= 1` as a default, and
the calls stay as they were.) A new parameter goes last, after the
allocator; std's convention is to keep the allocator last, so
`--reorder` puts the parameters in the order we want, at the
definition and at every call:

```console
$ volec refactor signature count::count_words --reorder counts,text,min_len,gpa
reordered the parameters of crate::count::count_words, 1 call	2 files	+2 -2 lines
$ volec query callers count_words
# main.vl
14:16	call	run	count::count_words(&counts, &text, 1, gpa);
```

Now the body can use `min_len`. It's a one-line change, so a patch
does it:

```console
$ volec edit patch count_words --old 'counts.get_or_insert(w, 0)[0] += 1;' --new 'if w.len() >= min_len { counts.get_or_insert(w, 0)[0] += 1; }'
patched crate::count::count_words	count.vl	+1 -1 lines
$ volec query show count_words
// crate::count::count_words	count.vl:3-8	effects: alloc(Gpa) panic diverge
pub fn count_words(counts: inout HashMap<String, i64>, text: str, min_len: i64, gpa: Gpa) {
    for word in text.split_whitespace() {
        let w = word.to_lowercase_in(gpa);
        if w.len() >= min_len { counts.get_or_insert(w, 0)[0] += 1; }
    }
}
```

`refactor signature` also removes and renames parameters, changes a
parameter's type, and changes its convention: `--convention v inout`
makes `v` an `inout` parameter and adds the `&` at every call (chapter
4).

### variant

Adding a variant to an enum breaks every `match` on it: the match no
longer covers every case (chapter 5). `refactor variant` adds the
variant and an arm to each match, with the expression you give:

```console
$ volec refactor variant report::Order --add 'Longest' --arm 'pairs.sort_by(|a, b| b.0.len() - a.0.len())'
added variant Longest to crate::report::Order, an arm in 1 match	report.vl	+2 -0 lines
$ volec query show report::top
// crate::report::top	report.vl:10-22	effects: alloc(Gpa) panic diverge
pub fn top(counts: HashMap<String, i64>, n: i64, order: Order, gpa: Gpa) -> Vec<(String, i64)> {
    var pairs: Vec<(String, i64)> = Vec::new_in(gpa);
    for (word, k) in counts.iter() {
        pairs.push((word.clone(), k));
    }
    match order {
        Order::ByCount => pairs.sort_by(by_count),
        Order::Alphabetical => pairs.sort_by(|a, b| cmp_of(a.0, b.0)),
        Order::Longest => pairs.sort_by(|a, b| b.0.len() - a.0.len()),
    }
    pairs.truncate(n);
    pairs
}
```

`--arm` gives every match the same arm; `--arm-in FUNCTION 'EXPR'`
gives one function's match its own. `refactor field` does the same for
a struct's field and every struct literal, and `refactor move` moves
items to another module, fixing the paths that name them.

For changes that aren't about one name, `volec rewrite` replaces code by
its shape: `volec rewrite 'trim($s)' '$s.trim()'` rewrites every call of
`trim` into a method call, whatever the argument is. Like everything
else here, it's checked before anything is written.

### undo

Every edit the tools make goes into a journal, and `volec undo` takes
the last one back. Let's say we didn't want that variant after all:

```console
$ volec undo
undid added variant Longest to crate::report::Order, an arm in 1 match	report.vl	+2 -0 lines
$ volec query refs Longest
error query.no-match: no definition 'Longest'
try: volec query items
```

## Fixing errors

Many of the compiler's errors know their own fix. You've seen `try:`
lines throughout this book; when the fix is an exact edit, `volec fix
--suggested` makes it for you.

Let's make a mistake on purpose. `--no-check` writes an edit even when it
breaks the program, so we can drop the `&` from the call in `run`, the
mark chapter 4 explained:

```console
$ volec edit patch run --old '(&counts' --new '(counts' --no-check
main.vl:14:27: error[conv.marker] 'counts' is lent inout here (the callee may change it): mark it '&counts' | help: an inout parameter takes '&place'; when the callee never changes it, take it let: 'volec refactor signature F --convention x let' | try: volec edit patch main.vl:14 --old '(counts' --new '(&counts' | try: volec fix --suggested main.vl  [edited: crate::run]
patched crate::run	main.vl	+1 -1 lines
warning edit.breaks: 1 new error; written anyway (--no-check)
try: volec check
$ volec check
main.vl:14:27: error[conv.marker] 'counts' is lent inout here (the callee may change it): mark it '&counts' | help: an inout parameter takes '&place'; when the callee never changes it, take it let: 'volec refactor signature F --convention x let' | try: volec edit patch main.vl:14 --old '(counts' --new '(&counts' | try: volec fix --suggested main.vl
```

`volec check` reports the error with two `try:` lines: one makes that
edit by hand, the other fixes every error in the program whose fix is
exact. Let's run the second:

```console
$ volec fix --suggested
fixed 1 suggested fix	main.vl	+1 -1 lines
$ volec check
ok: 0 errors in main.vl
```

`fix --suggested` applies all the exact fixes as one checked edit, so
it can also be undone. It only applies fixes that are certain: an
error that needs a decision (which of two names you meant, say) is
left for you, with its `try:` lines.

Plain `volec fix`, without `--suggested`, does a few common clean-ups:
it adds missing `use` lines and `pub` markers, removes unused imports,
and wraps unsafe operations in `unsafe { }` (chapter 15). `--only`
limits it to some of them, and `--dry-run` shows what it would do.

### Following the language

`volec fix` also carries *migrations*. Vole is pre-1.0 and its syntax
still changes, and when a release changes how something is written, it
usually comes with a `fix --only NAME` that rewrites old code to the new
form. For example, `volec fix --only conventions` turns code written
with an older, Rust-like spelling of parameters (`&T`, `&mut T`, `let
mut`) into today's. When an upgrade breaks your code, the errors' `try:`
lines name the migration to run.

## Formatting

`volec fmt FILE` lays code out in the standard style: four-space
indents, braces on the same line, imports from one module in one `use`
line. `--check` only checks: it names the files that need formatting
and exits with status 1, which is handy before a commit. Our `main.vl`
has three `use` lines where `fmt` would write one:

```console
$ volec fmt --check main.vl count.vl report.vl
main.vl
error fmt.unformatted: 1 of 3 files are not formatted
try: volec fmt --dry-run main.vl
try: volec fmt main.vl
$ echo $?
1
$ volec fmt --dry-run main.vl
--- a/main.vl
+++ b/main.vl
@@ -5,3 +5 @@
-use std::env;
-use std::fs;
-use std::io;
+use std::{env, fs, io};
$ volec fmt main.vl
formatted	main.vl	+1 -3 lines
```

`--dry-run` shows what `fmt` would change, as a diff, before it changes
anything. Every other example in this book is laid out by `volec fmt`.

With all our changes in, the program still works, with its wider
column, and still exits with status 1 when a file is missing:

```console
$ volec main.vl -o wc
ok: built wc
$ ./wc a.txt b.txt
the              4
cat              2
on               2
sat              2
dog              1
$ ./wc a.txt nope.txt
wc: No such file or directory (os error 2)
$ echo $?
1
```

> **If you know Rust:** these are rust-analyzer's assists, run from the
> command line, plus `cargo fmt` and `cargo fix`, with every change
> checked by the compiler before it's written.

## In your editor

Chapter 1 set up the VS Code extension, which runs `volec lsp`, the
compiler's *language server*. It's the same compiler and the same
answers, through the Language Server Protocol that most editors speak:

- **errors as you type**, the ones `volec check` gives, on unsaved text
  too, with their `try:` lines attached;
- **go to definition** and **find references**, the editor's versions
  of `query def` and `query refs`;
- **hover**: a function's signature and its effects, declared or
  inferred, each with a line saying why ("alloc(Gpa) because of
  'v.push(i)' at line 19"), or the type of a variable;
- **the file's outline**, its items, as `query items` lists them.

Any editor with LSP support can run it: configure the server command as
`volec lsp`. It finds the program's root by looking for the nearest
`main.vl`. The rest of the tools, the refactorings especially, are
command-line only for now.

## Working with an agent

AI coding assistants, *agents*, are programs that read and change code
by running commands in a loop: they read some files, make an edit,
build, read the errors, and go round again. Vole's tools were designed
with them in mind. Most of the commands in this chapter exist because
agents working on the vole compiler spent most of their effort reading
files a few lines at a time, searching with `grep`, and making edits
with `sed` that sometimes changed the wrong line.

### What an agent uses

An agent working on a vole program does what you've done in this
chapter, with a few habits that matter more for a program than for a
person:

- **It learns the language from the compiler.** `volec guide` is
  written for agents: compact, complete, with every example tested.
  `volec guide --find WORDS` gives the lines about one construct before
  using it.
- **It reads by name, not by line number.** `query context` instead of
  opening a file at a guessed line; `query refs` instead of `grep`.
- **It edits by name, checked.** `edit patch` and `refactor` instead of
  rewriting a file, so a bad edit is refused instead of written.
- **It checks after every edit,** with `volec check`, which takes a
  fraction of a second.
- **It runs `try:` lines as they are.** Every problem the tools report
  ends with exact commands, so the agent doesn't have to work out the
  fix.

None of this is magic. It's the same reason the tools help you: the
compiler knows things about the program that a text search can only
guess.

### Setting up a project for an agent

Most agents read an instructions file at the root of a project, often
named `AGENTS.md` (or `CLAUDE.md`, depending on the agent). For a vole
project, a few lines go a long way:

```text
# Working on this project

This is a vole program; the root is main.vl. Run `volec guide` first:
the language in a few pages. Before using a construct you're unsure
of, run `volec guide --find WORDS`.

- Read code with `volec query context NAME` and `query refs NAME`,
  not grep.
- Change code with `volec edit patch` and `volec refactor`; run
  `volec check` after every edit, and fix errors with the commands on
  their `try:` lines (`volec fix --suggested` for the exact ones).
- Build with `volec main.vl -o prog`; test with `volec test`.
```

Some agents also run *hooks*, small scripts that run before or after
each command the agent issues. The vole repository's own setup is an
example: `tools/agent-hooks` has one hook that runs `volec check` after
every edit and shows the agent what changed, and one that stops an
agent from reading source with `grep` or `sed` and suggests the
`query` command instead. Its `AGENTS.md` is a longer example of the
file above.

### Reviewing what an agent did

An agent's change still needs a person to review it, and vole gives you
a few ways to see what changed in behaviour, not just in text:

- **`volec query effects`** on the functions it touched: if a function
  that did no I/O now does, or one that never allocated now does, the
  effects say so. Effect declarations (chapter 12) turn that into a
  compile error.
- **Contracts** (chapter 13): a `requires` or `ensures` that still holds
  after the change is a promise that still holds. An agent that has to
  weaken one, to make its change compile, has told you something
  important.
- **`volec test`**, which runs the tests at two optimization levels.
- **`volec query diff`**, which shows the last edit the tools made.

## Summary

- The compiler answers questions by name: `query context`, `show`,
  `refs`, `callers`, `effects`, `items`, `own`. Its answers follow the
  program's real names, through imports, and ignore comments and
  strings.
- `edit patch`, `replace`, `insert` and `delete` change items by name;
  every edit is checked, and one that would add an error writes
  nothing. `volec undo` takes the last one back.
- `refactor rename`, `signature`, `variant`, `field` and `move` change
  a definition and every use of it at once.
- `volec fix --suggested` applies the errors' exact fixes; `volec fix`
  does common clean-ups and migrations to new language versions.
- `volec fmt` lays code out; `volec lsp` brings the compiler into your
  editor.
- An agent working on vole uses the same tools; an `AGENTS.md` pointing
  at `volec guide` and the tools sets it up, and effects, contracts and
  tests help you review its work.

The next chapter puts the whole book together, in a complete
command-line tool built from this word counter.

## Try it yourself

- Use `refactor signature` to give `report::top` a `min: i64 = 1`
  parameter, and make it leave out words seen fewer than `min` times.
- Add a `ByLength` variant to `Order` with `refactor variant`, sorting
  the longest words first, and add a command-line way to choose it.
- Run `volec query own main.vl:9:9`. What does it tell you about
  `counts`?
