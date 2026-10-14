# Changing a program by name: tachyonc edit, fix, check, same-output

The refactoring tools of 0.11 (phase 1), for agents that would otherwise
read a file to change one item, and edit it with `sed`, `perl` or a
Python script (see [agent-tool-usage.md](agent-tool-usage.md)). They are
built on `tachyonc query` ([query.md](query.md)): NAME is anything query
accepts, positions and spans are the compiler's, and every problem is
one line `SEVERITY CODE: MESSAGE` followed by `try:` lines, as there.

```
tachyonc edit patch TARGET --old TEXT --new TEXT [--old TEXT --new TEXT]... [--loose]
tachyonc edit patch TARGET [--loose] < PAIRS   (0.12; see "Edits inside an item")
tachyonc edit insert --in TARGET --after|--before ANCHOR [--loose] < TEXT
tachyonc edit replace NAME [ROOT] < TEXT       the item's text becomes TEXT
tachyonc edit insert --after|--before NAME [ROOT] < TEXT
tachyonc edit delete NAME [ROOT]
tachyonc undo [--force]                        the last edit, undone
tachyonc check [ROOT]                          the front end's errors, one per line
tachyonc fix [ROOT] [--only imports,unused,pub,unsafe] [--in FILE|MODULE]
tachyonc same-output OLD [--corpus DIR|FILE]... [-j N] [--work DIR]
tachyonc lint --max-lines N [ROOT]
tachyonc query stats [MODULE|FILE] [--over N] [--all]
tachyonc query deps MODULE [--max-lines N]
tachyonc query unused [MODULE|FILE] [--all]
tachyonc query impact NAME
```

The editing commands (edit, fix) also take `--dry-run`, `--no-check`, `--show`,
`--exact`, `--root ROOT` and `--target T`. ROOT is found as for query
(`--root`, a last argument ending in `.tach`, `$TACHYON_ROOT`,
`./main.tach`, `./compiler/src/main.tach`).

Exit status: 0 done, 1 refused or failed (nothing written), 2 usage
error.

## The edit engine

Every change is a set of replacements of byte ranges of the program's
files, computed from the compiler's spans. It is applied atomically:

1. each changed file's new text is written to a copy next to it,
   `FILE.tachyon-edit~`;
2. the front end runs again on the edited program: `tachyonc check
   --overlay FILE COPY... ROOT`, in a process of its own, reads the copies
   in place of the files (parse, resolve, type check, unsafe check);
3. its errors are compared with the program's before the edit, by file
   and message (not by line: an edit moves lines). An error the edited
   program has and the program had not is a **new error**: the copies
   are removed, nothing is written, and the new errors are printed
   (short form, positions in the edited text) with
   `error edit.breaks: N new errors; nothing written` and `try:` the same
   command with `--no-check`;
4. otherwise the copies are renamed onto the files (rename(2): each file
   is replaced whole, never half written), the edit is journaled, and
   one line says what changed:

```
replaced crate::middle::gvn::run_gvn→compiler/src/middle/gvn.tach→+3 -5 lines
```

(`→` is a TAB; with several files, `N files`). Nothing outside the
replaced ranges changes, byte for byte. Errors the program had before
are not new: an edit of a program with errors is checked against them.

- `--dry-run` does all but write: it prints the edit as a unified diff
  with no context lines (`git apply --unidiff-zero` takes it), and says
  when it would add errors (`warning edit.breaks: N new errors (dry
  run)`, exit 1).
- `--no-check` writes an edit that adds errors anyway (a signature
  changed before its callers are), with `warning edit.breaks` and the
  errors; `tachyonc check` lists what is left.
- `--show` (0.12; every edit, fix, rewrite and refactoring) prints, after
  the summary line, the regions the edit changed as their new lines,
  numbered, so that the edit need not be read back:

```
patched crate::one→main.tach→+2 -1 lines
// main.tach:21-22
21→    let twice = k + k;
22→    unsafe { twice * abs(a) as i64 / 2 }
```

  (lines only removed: `// FILE:A: N lines removed after line A`).
  `tachyonc query diff` prints the last journaled edit as a diff.

### The journal and undo

Each edit is journaled in the git directory of the root's checkout,
`.git/tachyon-edits/`: `head` holds the number N of the last edit, and
`N/` its summary line, its files (absolute paths) and each file's text
before and after. `tachyonc undo` restores the files of the last edit
and forgets it; run again, it undoes the one before. It refuses when a
file changed since the edit (`error undo.changed`, `try:` `undo --force`,
which restores it anyway). Without a git checkout there is no journal.

## Edits inside an item: edit patch, insert --in

Most edits change a few lines of one function: a condition, a statement,
an expression. `edit patch` makes them by text, as cheaply as a
`s.replace(OLD, NEW)`, and with the engine's check, journal and undo:

```
$ tachyonc edit patch range::decide --old 'if a < b {' --new 'if a <= b {'
patched crate::middle::range::decide→compiler/src/middle/range.tach→+1 -1 lines
```

- **TARGET** is a NAME as `query` takes it, or `FILE:LINE` (the innermost
  item holding that line: the position of a compiler error), or a module
  or a file of the program (all of its text: its `use` lines, its header
  comment). An item's text is its lines with the comment and attribute
  lines above it, as `query show` prints them.
- **Each OLD must occur exactly once** in TARGET's text, matched byte for
  byte. Every OLD is found in the text as it was before the edit, the
  replacements must not overlap (`error patch.overlap`), and all pairs
  are one edit: checked once, written all or not at all, undone by one
  `undo`.
- **No match**: `error patch.no-match` with the line of TARGET nearest to
  OLD (by edit distance, blanks ignored), and `try:` the command with the
  part of that line nearest to OLD as OLD (or with `--loose` when OLD is
  there with other blanks; or `query show FILE:LINE`):

```
error patch.no-match: OLD 1 is not in crate::calc::clamp; nearest, line 5: if v < lo {
try: tachyonc edit patch clamp --old 'v < lo' --new 'v <= lo'
```

- **Several matches**: `error patch.ambiguous` with their lines, and for
  each (at most three) `try:` the command with OLD and NEW widened to the
  lines around it, a line up and down at a time, until it is unique:

```
error patch.ambiguous: OLD 1 occurs 2 times in crate::calc::clamp, lines 6, 9; give more of the text around it
try: tachyonc edit patch clamp --old 'return lo;' --new 'return 0 + lo;'
try: tachyonc edit patch clamp --old 'return hi;' --new 'return 0 + hi;'
```

- A match of whole lines replaced by an empty NEW removes the lines.
- `--loose`: a run of blanks (spaces, tabs, newlines) in OLD matches any
  run of blanks, and OLD's first and last blanks are ignored; NEW is
  indented like the text it replaces (its first line where OLD's
  started, the others keeping their indentation relative to NEW's least
  indented line, on top of the indentation OLD's least indented lines
  have in the file).
- `--dry-run` prints the diff (no context lines), `--no-check` writes an
  edit that adds errors, as for every edit.
- Only the summary line is printed, never the file.

### Pairs on stdin

Without `--old`, the pairs are read from stdin, for text of several
lines without shell quoting. A pair is a block of whole lines:

```
<<<<<<< OLD
    while i <= n {
        total += i;
=======
    while i <= n {
        // (one term)
        total += i;
>>>>>>> NEW
```

The markers are the line's first seven characters (`<<<<<<<`,
`=======`, `>>>>>>>`), alone or followed by a blank and a word; blank
lines between blocks are ignored, anything else outside a block is an
error (`error patch.format: stdin line N: ...`). OLD and NEW are the
lines between the markers, joined by newlines; OLD must match whole
lines (from a line's start or its indentation to a line's end), so
`    total` does not match inside `    total += i;`. An empty NEW removes
OLD's lines.

### insert --in

`edit insert --in TARGET --after ANCHOR < TEXT` inserts TEXT's lines
after the line where ANCHOR ends (`--before`: before the line where it
starts). ANCHOR is matched as OLD is (once in TARGET's text, `--loose`
too; the same diagnostics, with `try:` the command with a widened
anchor). TEXT is indented like the anchor's line, one level (4 spaces)
deeper after a line ending in `{` or before one starting with `}`: its
least indented lines get that indentation, the others keep theirs
relative to them.

```
$ tachyonc edit insert --in calc::sum_to --after 'while i <= n {' < stmt.tach
inserted in crate::calc::sum_to→calc.tach→+3 -0 lines
```

## Items as text

`edit` works on an item's text: whole lines when the item has its lines
to itself, from the line of its first token (its attributes, `pub`, its
keyword) to the line of its last (`}`, or the `;` of a constant; the `,`
of a field or variant), a comment after it on that line included. The
comment and attribute lines directly above it (what `query show`
prints) belong to it as follows:

- **replace**: what TEXT has, it replaces. TEXT starting with a comment
  (`//`) replaces the item's comment and attribute lines too; starting
  with an attribute (`#[`), its attribute lines (its comment stays);
  otherwise both stay, and only the lines from its `pub` or keyword are
  replaced. So `query show NAME`, changed and given back, is a round
  trip; its header line (`// PATH<TAB>FILE:A-B`) is dropped.
- **insert --after**: TEXT goes after the item's last line, a blank line
  between them (no blank line for a field or a variant).
- **insert --before**: TEXT goes before the item's comments, a blank
  line between them.
- **delete**: the item's lines with its comments and attributes, and one
  blank line next to them, so that no two are left together (nor one
  after an opening brace or before a closing one).

TEXT is read from stdin: blank lines first and last, and trailing
blanks, are dropped; when none of its lines is indented and the item is
(a method), every line gets the item's indentation.

An item that shares a line with other code (a field of
`struct P { x: i64, y: i64 }`) is its exact bytes: replace replaces
them, delete removes them with their `, `, insert is refused
(`error edit.layout`).

NAME may be `FILE:LINE`, for every edit and refactoring of an item (the
innermost item holding that line, as for query): `edit replace
gvn.tach:740`, `edit delete`, `refactor rename`, `signature`.
NAME must name one definition of the program's own files; std's and
the C headers' definitions are left out when one of the program's
matches. When several match: `error query.ambiguous` with a `try:` line
per path (the first two and `query def NAME` when there are more).

## tachyonc check

`tachyonc check [ROOT]` runs the front end alone (parse, modules and
names, type check, unsafe check: no lowering, no code) and prints every
error and warning in the short form, one per line:

```
main.tach:13:25: error[type error] undefined variable 'twice' | help: add `use crate::util::twice;`
```

Exit 0 without errors (and then nothing is printed but warnings), 1 with
them; at most 50 errors, as in a compilation. `--diagnostics=human`
prints the long form. About 30 ms on the compiler's source (55,000
lines).

## tachyonc fix

Every fix the compiler can make by itself, in one atomic edit, one
summary line:

```
fixed 2 missing imports, 3 unused imports, 1 pub, 1 unsafe block→3 files→+3 -5 lines
```

| `--only` | what |
|---|---|
| `imports` | the `use` lines the errors for unknown names ask for (`help: add `use crate::m::name;``): merged into a `use` of that module when there is one (`use m::{a}` gains `, name`; `use m::a;` becomes `use m::{a, name};`), else a line after the module's last `use`; and 0.8's wildcard migration (`use a::*;` becomes the names it brings) |
| `unused` | imports whose name is written nowhere else in their file, removed (the name of a list with its separator; the item when all go; `use p::{a}` left with one name becomes `use p::a`). `pub use` is kept |
| `pub` | `pub` on the items other modules use while they are private (`error ... is private`) |
| `unsafe` | the unsafe operations outside unsafe code, wrapped in unsafe blocks (the outermost unit around each: a statement, `let p = unsafe { e };`, an expression); a function with several of them gets its whole body in one block, one level deeper, when its braces have lines of their own (0.12, the codebase's style; `--fix-unsafe` keeps 0.9's units) |

By default all four, everywhere; `--in FILE|MODULE` keeps the fixes of
one file or module (matched like query's `--in`; none:
`error fix.bad-in`). A fix can let the checker see more: the checker
stops at the first unknown name of a statement, so its second appears
only once the first is imported. So fix runs again on the edited program
(`fix --round`, with the copies as overlays; up to four more rounds)
before the check, and the summary counts every round. Nothing to fix:
`note fix.none: nothing to fix` (exit 0).

`tachyonc --fix-imports ROOT` (0.8) and `tachyonc --fix-unsafe ROOT`
(0.9) are `fix --only imports` and `fix --only unsafe`, silent when
there is nothing to do.

## tachyonc same-output

A pure refactoring proven to change nothing: every program of the
corpus is compiled by OLD and by this compiler, for every target both
have (a target OLD lacks is skipped, `note same-output.target`), at
`-O0`, `-O1` and `-O2`, and the outputs are compared byte for byte (the
assembly, what the compiler printed, its exit status). The corpus is
`tests/run`, `examples`, `bench` and `compiler/src` (relative to the
current directory), or the `--corpus` entries: a file, or a directory
whose `main.tach` is a module tree's root, or else each of its `.tach`
files and each `SUB/main.tach`. Up to `-j N` comparisons run at once
(default: the processors), each in a copy of this process; their
outputs go to `--work DIR` (`target/same-output`), kept when they
differ.

```
identical→3375 compilations→375 programs→3 targets→-O0 -O1 -O2
```

or, when they differ, one line per differing compilation (at most 10:
program, target, level, what: `exit A B`, `asm line N`, `output line
N`), the first one's differing lines (`-→old`, `+→new`), and

```
error same-output.differs: 3 of 81 compilations differ (kept in target/same-output)
try: diff target/same-output/64/old/out.s target/same-output/64/new/out.s
try: tachyonc --target aarch64-macos -O1 examples/md5.tach -o new.s
```

`tests/compare.sh` does the same and more (random programs, C interop,
IR and tokens), in sh.

## Planning queries

For deciding how to change a program, from the same front end as the
other queries. An item's lines are its text's (its comments to its last
line, as `query show` prints it).

### query stats

`query stats`: per file of the program, largest first,
`LINES→ITEMS→FILE`, with `→over` after a file of more than `--over N`
lines (1000), and a last line `LINES→ITEMS→total`; then, when files are
over, `note query.over: N files over 1000 lines` and `try:` the deps of
the largest one's module. `query stats MODULE` or `query stats FILE` (a
path with a `/`, or ending in `.tach`): its items, largest first, under
a header:

```
# crate::middle::gvn→compiler/src/middle/gvn.tach→834 lines→51 items
102→fn→memory_step
76→fn→run_gvn
```

(names are relative to the module; more than 60 items: the 60 largest,
`note query.truncated`, `try:` with `--all`).

### query deps

`query deps MODULE [--max-lines N]`: the input for splitting a module
into cohesive parts. One line per item, in order:

```
# crate::lang→lang.tach→27 lines→8 items
lex→3→Token lex_digit→parse→0
```

`ITEM→LINES→USES→USED-BY→OUTSIDE`: the items of the module it refers to
(a field or variant counts as its type, a trait's function as its
trait), the ones that refer to it (`-` for none), and how many
references to it come from other modules. Then a grouping into parts of
at most N lines (1000):

```
groups→3→at most 12 lines→8 references between them
group 1→10→Token lex_digit check
group 2→9→report describe summary
```

found by agglomerative clustering with average linkage: from one part
per item, the two parts with the most references between them per pair
of their items are merged, while they fit together; then the parts that
have no references between them are packed, first fit, largest first.
An item larger than N is a part of its own (`→over`). The references
between parts are what a split would turn into imports (on the
compiler's check.tach, 214 items in 5 parts of at most 1000 lines, 156
references between them).

### query unused

`query unused [MODULE|FILE]`: the definitions nothing refers to (its
own `use` lines and itself aside: a function that only calls itself is
unused) and the imports nothing in their file names, in order:
`PATH→FILE:LINE:COL→KIND` (`KIND` `import` for an import, whose PATH is
what it imports). Left out: `main`, C's (`extern "C"` declarations and
`extern "C" fn` definitions), the functions of trait impls and of
traits, modules, std's. Fields and variants of an unused item are not
listed again. More than 60: a count per file, `note query.truncated`,
`try:` the file with the most, and `--all`.

### query impact

`query impact NAME`: what changing NAME's signature touches. Its
definition line (as `query def` prints it), then per file
`FILE→CALLS→OTHER→FUNCTIONS` (other references: types, imports,
functions as values; the functions they are in, at most 10), the generic
instances of a generic function (`instances→N→grow<i64> grow<Buf>
...`), the functions implementing a trait's function (`impls→...`), and
`total→CALLS→OTHER→N files[, N instances][, N impls]`.

## tachyonc lint

`tachyonc lint --max-lines N [ROOT]`: one error per file over N lines,
largest first, each with the deps of its module:

```
error lint.max-lines: compiler/src/front/check.tach: 4785 lines (at most 1000)
try: tachyonc query deps crate::check --max-lines 1000
```

Exit 1 when a file is over, 0 when none is.

## Diagnostics

| code | severity | exit | when | try |
|---|---|---|---|---|
| `edit.breaks` | error | 1 | the edit adds errors (they are printed); nothing written | the command with `--no-check` |
| `edit.breaks` | warning | 1, 0 | the same with `--dry-run`, or `--no-check` (written) | `tachyonc check` |
| `edit.no-text` | error | 2 | replace or insert without TEXT on stdin; patch without pairs | the command `< new.tach`; with `--old OLD --new NEW` |
| `patch.no-match` | error | 1 | an OLD or ANCHOR is not in TARGET (with the nearest line) | the command with that line's text, or with `--loose`, or `query show FILE:LINE` |
| `patch.ambiguous` | error | 1 | an OLD or ANCHOR occurs several times (their lines) | the command with more context around each |
| `patch.overlap` | error | 1 | two OLDs overlap | |
| `patch.format` | error | 2 | the pairs on stdin are not blocks | |
| `edit.not-source` | error | 1 | NAME is std's or a C header's | |
| `edit.layout` | error | 1 | insert next to an item that shares its line | |
| `edit.unchanged` | note | 0 | the edit changes nothing | |
| `edit.unchecked` | warning | | the check could not run | |
| `edit.exists`, `edit.write` | error | 1 | a file to make exists, a file cannot be written | |
| `edit.journal` | warning | 0 | the journal cannot be written (undo will not know the edit) | |
| `edit.usage`, `fix.usage`, `check.usage`, `lint.usage`, `same-output.usage` | error | 2 | a usage error | the corrected command |
| `undo.empty` | error | 1 | no edit to undo | |
| `undo.changed` | error | 1 | a file changed since the edit | `undo --force` |
| `fix.none` | note | 0 | nothing to fix | |
| `fix.bad-in` | error | 1 | `--in` names no file or module of the program | |
| `lint.max-lines` | error | 1 | a file over N lines | `query deps MODULE --max-lines N` |
| `same-output.differs` | error | 1 | compilations differ | the `diff`, the compilation |
| `same-output.no-compiler`, `same-output.no-corpus`, `same-output.work` | error | 2 | OLD cannot be run, no programs, no work directory | |
| `same-output.target` | note | | OLD has no such target | |
| `query.over` | note | 0 | stats: files over --over | `query deps` of the largest |
| `query.ambiguous` | error | 1 | NAME names several definitions (edit) | the paths |

Problems with ROOT are query's (`query.no-root`, `query.bad-root`), for
every command.

## Known limits

- `edit patch` matches text, not syntax: an OLD inside a comment or a
  string is an occurrence like any other, and NEW is not re-indented
  without `--loose` (wrapping a body in a new block re-indents every line
  of it: `edit replace` the item).

- The check compares errors by file and message: an edit that fixes one
  error and makes another with the same message in the same file is not
  told apart.
- `unused` imports are found by name: a name written anywhere else in
  the file (a local, a field) keeps its import.
- `query unused` and `query deps` see references the checker resolved:
  a generic function never instantiated is not checked (see
  [query.md](query.md), Known limits).
- Phase 2 (0.11): `refactor signature`, `field`, `variant`, the typed
  `rewrite` and `refactor --script` are in
  [refactor-shape.md](refactor-shape.md); `refactor rename`, `move`,
  `new-module`, `move-module`, `split` in
  [refactor-modules.md](refactor-modules.md); all on this engine
  (`edit_replace`, `edit_new_file`, `apply_edit` in
  compiler/src/tools/edit.tach), and a command registered in
  compiler/src/tools/commands.tach runs in scripts too.
