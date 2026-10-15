# Changing a program by name: tachyonc edit, fix, check, same-output

The refactoring tools of 0.11 (phase 1), for agents that would otherwise
read a file to change one item, and edit it with `sed`, `perl` or a
Python script (see [agent-tool-usage.md](agent-tool-usage.md)). They are
built on `tachyonc query` ([query.md](query.md)): NAME is anything query
accepts, positions and spans are the compiler's, and every problem is
one line `SEVERITY CODE: MESSAGE` followed by `try:` lines, as there.
Every query, edit and refactoring in one table, a row each: [query.md,
"Every command at a glance"](query.md#every-command-at-a-glance-for-agents).

Sessions with these tools on small programs, each step's command and
its output, tested by `tests/walkthrough/run.sh`: [examples/tools](../examples/tools/README.md).

```
tachyonc edit patch TARGET --old TEXT --new TEXT [--old TEXT --new TEXT]... [--loose]
tachyonc edit patch TARGET [--loose] < PAIRS   (0.12; see "Edits inside an item")
tachyonc edit patch TARGET --pairs FILE [--loose]   (0.13)
tachyonc edit patch [TARGET] --old A --new B --in NAME --old C --new D   (0.15: several targets)
tachyonc edit apply [FILE]                     (0.15) several items' new text, one edit
tachyonc edit insert --in TARGET --after|--before ANCHOR [--loose] < TEXT
tachyonc edit wrap TARGET --in HEAD [--body | --lines A-B]   (0.13)
tachyonc edit new-file PATH [--pub] < TEXT     (0.13) the file and its mod line
tachyonc edit replace NAME [ROOT] < TEXT       the item's text becomes TEXT
tachyonc edit insert --after|--before NAME [ROOT] < TEXT
tachyonc edit delete NAME [ROOT]
tachyonc undo [--force]                        the last edit, undone
tachyonc check [ROOT]                          the front end's errors, one per line
tachyonc fix [ROOT] [--only imports,unused,pub,unsafe,tidy-imports,reexports,std015,alloc016] [--in FILE|MODULE]
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
   (short form, positions in the edited text), each tagged with the item
   it is in (0.15), with `error edit.breaks: N new errors; nothing
   written`, the refactoring that fits when one does, and `try:` the
   same command with `--no-check` (see "When an edit breaks the
   program");
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
which restores it anyway). A program in no git checkout (0.14: a
user's workspace) is journaled in `.tachyonc/edits/` next to its root;
`undo` and `query diff` find it from the root, or from the current
directory or one below it.

## Edits inside an item: edit patch, insert --in

Most edits change a few lines of one function: a condition, a statement,
an expression. `edit patch` makes them by text, as cheaply as a
`s.replace(OLD, NEW)`, and with the engine's check, journal and undo:

```
$ tachyonc edit patch range::decide --old 'if a < b {' --new 'if a <= b {'
patched crate::middle::range::decide→compiler/src/middle/range.tach→+1 -1 lines
```

- **TARGET** is a NAME as `query` takes it, or `FILE:LINE` (the innermost
  item holding that line: the position of a compiler error; 0.14: on a
  line no item holds, a banner, a comment between items, the header or
  the `use` lines, the lines from the end of the item before to the
  comments of the item after), or a module
  or a file of the program (all of its text: its `use` lines, its header
  comment), or (0.12) `MODULE::use` (its `use` lines: from the first to
  the last) or `MODULE::header` (the comment at the top of its file), or
  (0.17) `MODULE::extern` (its `extern "C" { ... }` blocks), as
  `query show` prints them; the root module is `crate` or the root file's
  name (`main::header`, `crate::extern`). `FILE:LINE` on a `mod x;` line
  (0.17) is that line (`mod x;` -> `pub mod x;`), not x's file, which the
  module's name gives. An item's text is its lines with the comment and attribute
  lines above it, as `query show` prints them.
- **Each OLD must occur exactly once** in TARGET's text, matched byte for
  byte; it may start and end inside a line, in every form (0.13). When
  some of its matches are whole lines (from a line's start or its
  indentation to a line's end), only those count: `total` names the line
  `    total`, not a part of `    total += i;`. Every OLD is found in the
  text as it was before the edit, the
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

  An OLD of several lines whose first lines are there together says
  where they match and how its next line differs (0.13):

```
error patch.no-match: OLD 1 is not in crate::calc::sum_to; its lines 1-2 match lines 18-19, then its line 3 'i += 2;' is not line 20 'i += 1;'
try: tachyonc query text calc.tach:18-20
```

- **Several matches**: `error patch.ambiguous` with their lines, and for
  each (at most three) `try:` the command with OLD and NEW widened to the
  lines around it, a line up and down at a time, until it is unique:

```
error patch.ambiguous: OLD 1 occurs 2 times in crate::calc::clamp, lines 6, 9; give more of the text around it, or --nth N (--all: every one)
try: tachyonc edit patch clamp --old 'return lo;' --new 'return 0 + lo;'
try: tachyonc edit patch clamp --old 'return hi;' --new 'return 0 + hi;'
```

  (0.16) Or say which: `--nth N` replaces the Nth match (1 is the first,
  in TARGET's text order: the order of the lines the error lists),
  `--all` every one; they hold for every pair of the command. Past the
  last: `error patch.nth: OLD 1 occurs 3 times in crate::calc::clamp;
  --nth 4 is past the last`. `edit insert --in` takes `--nth N` for its
  ANCHOR (not `--all`).

  Pairs of several lines, and pairs given as blocks, are not put on the
  command line (agent harnesses refuse `$'...'` quoting): they are
  written to `try-N.pairs` in the journal's directory, and the `try:`
  line is the command with `--pairs` (0.13; `$'...'` without a git
  checkout):

```
try: tachyonc edit patch clamp --pairs .git/tachyon-edits/try-1.pairs
```

- A match of whole lines replaced by an empty NEW removes the lines (and
  a blank line after them when one is before them, so that no two are
  left together: 0.12).
- `--loose`: a run of blanks (spaces, tabs, newlines) in OLD matches any
  run of blanks, and OLD's first and last blanks are ignored; NEW is
  indented like the text it replaces (its first line where OLD's
  started, the others keeping their indentation relative to NEW's least
  indented line, on top of the indentation OLD's least indented lines
  have in the file).
- `--dry-run` prints the diff (no context lines), `--no-check` writes an
  edit that adds errors, as for every edit.
- **Imports (0.14)**: when the check finds new errors, a round of `fix
  --only imports` on the edited file adds the `use` lines of the names
  the new text takes from other modules (as `edit replace` and `insert`
  do, below), and the edit is checked with them: `note edit.imports`
  (once per command: 0.16, a script's steps say it once).
- Only the summary line is printed, never the file.

### Pairs on stdin, or in a file

Without `--old`, the pairs are read from stdin, for text of several
lines without shell quoting; `--pairs FILE` (0.13) reads them from FILE,
for harnesses that refuse a redirection or `$'...'`. A pair is a block
of lines:

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
error (`error patch.format: stdin line N: ...`, `FILE line N`). OLD and
NEW are the lines between the markers, joined by newlines; OLD is
matched as on the command line (0.13: its first and last lines may be
parts of lines; before, they had to be whole). An empty NEW removes
OLD's lines.

### Several targets (0.15)

The pairs of one call may change several items, in several files: on
the command line `--in NAME` starts the pairs of another target (TARGET
before the first `--in` is optional), and in a pairs file (stdin or
`--pairs FILE`) a line `@@ NAME` does, for the blocks after it:

```
$ tachyonc edit patch area --old 'r.w * r.h' --new 'r.h * r.w' --in main --old '== 26' --new '== 27'
patched crate::shapes::area, crate::main→2 files→+2 -2 lines
```

```
@@ crate::shapes::area
<<<<<<< OLD
pub fn area(r: Rect) -> i64 {
=======
pub fn area(r: Rect) -> bool {
>>>>>>> NEW
@@ main
<<<<<<< OLD
    if area(r) + 1 == 7 {
=======
    if area(r) {
>>>>>>> NEW
```

Each target is found as TARGET is, each OLD in its target's text as it
was before the edit; all of it is one edit: checked once (so a signature
and its callers change together, with no error between them), written
all or not at all, one `undo`. A pair that does not match is reported
with its target; the `try:` line is then a pairs file with every
target's `@@` line. A pair before any target: `error edit.usage`.

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

## edit apply (0.15)

`edit apply [FILE]` (stdin without FILE) takes the new text of several
items in one file, each block introduced by a header line, and makes
them one edit: checked once, all or nothing, one `undo`, `--dry-run`,
`--show`, `--no-check` as for every edit.

| header | the block |
|---|---|
| `@@ NAME` | NAME's text becomes the block's (as `edit replace NAME`) |
| `// PATH<TAB>FILE:A-B` (a header of `query show`) | the same, for PATH |
| `@@ NAME` naming no definition, whose text defines its last segment | added at the end of its module (`@@ shapes::perimeter`) |
| `@@ new after NAME`, `@@ new before NAME` | inserted next to NAME (as `edit insert`) |
| `@@ new in MODULE` | added at the end of MODULE's file |
| `@@ delete NAME` | NAME deleted (no text) |
| `@@ MODULE::use`, `@@ MODULE::header` | the module's `use` lines or header comment |

(0.17) `@@ new after X` or `@@ new before X`, where X is an item an
earlier block of the file adds, goes next to that block's text: new
items chain in one file.

So the output of `query show A B` (or the items of `query context`),
changed and given back, is a round trip: change the items in place, add
blocks for new ones, apply. Each block is made as `edit replace`,
`insert` and `delete` make theirs (Items as text, below; the indentation
of a method's text is fitted); the `use` lines the new text needs are
added (`note edit.imports`).

```
$ tachyonc query show area main > items.tach      # then change them, add blocks
$ tachyonc edit apply items.tach --show
applied 3 blocks: replaced crate::shapes::area; added crate::shapes::perimeter; replaced crate::main→2 files→+9 -2 lines
```

Errors: `error edit.format` (text before the first header, a header
naming nothing, a block without text, a delete block with text; nothing
is read of the program), `error edit.overlap` (two blocks change one
item), `error edit.no-module` (a new item for a module with no file of
its own: name an item to put it after), and NAME's errors as for `edit
replace` (`query.no-match`, `query.ambiguous`).

### When an edit breaks the program (0.15)

An edit that adds errors prints them, each followed by the item it is
in: `[edited: PATH]` for text the edit changed, `[in PATH]` for an item
it does not change (errors outside items, in a `use` line, have no tag).
`edit.breaks` counts both, and its notes say what to do instead of
`--no-check`:

```
main.tach:15:5: error[type error] function 'shapes::scale' expects 3 arguments, got 2  [in crate::main]
error edit.breaks: 1 new error (1 in crate::main, which the edit does not change); nothing written
note edit.refactor: the uses of crate::shapes::scale no longer fit its new shape: a refactoring changes them with it (VALUE, EXPR: to fill in), then the rest of the edit
try: tachyonc refactor signature crate::shapes::scale --add 'm: i64 = VALUE'
note edit.together: change crate::main in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: tachyonc query show crate::main
try: tachyonc edit patch scale --old 'k: i64' --new 'k: i64, m: i64' --no-check
```

- **`note edit.refactor`**: an edited item's shape changed and its uses
  broke. The edit's old and new text of the item are compared: a
  function's name (`refactor rename PATH NEW`) and parameters
  (`refactor signature`: `--add 'x: T = VALUE'` with `--at N` when not
  last, `--remove x`, `--rename-param a b` when only names changed in
  place, `--type x T --default '$x as T'` between number types or
  `--default EXPR`, `--reorder`), a struct's fields (`refactor field
  --add`, `--rename`, `--type`; a removed field: `query refs S.g`, its
  uses), an enum's variants (`refactor variant --add 'X(T)' --arm
  'EXPR'`, `--rename`, `--remove`). VALUE and EXPR are to be filled in.
  With errors only in the edited text, a renamed parameter still used by
  its old name gets `--rename-param` (it renames the uses too).
- **`note edit.together`**: items the edit does not change have errors;
  `try:` their `query show`, to change them in the same edit (`edit
  apply`, `edit patch` with targets).
- **`--no-check`** is the last `try:`, as before.

## edit wrap

`edit wrap TARGET --in HEAD [--body | --lines A-B]` (0.13) puts a
function's body (`--body`, the default; its braces on lines of their
own) or lines A to B of TARGET (the file's line numbers, as `query show`
prints them; `--lines A` for one) in a block `HEAD { ... }`, every line
one level (4 spaces) deeper; HEAD is `unsafe`, `loop`, `if c`, or `''`
for a bare block. One edit: a wrap that breaks the program (a `let`
whose name is used after the block) is refused with the errors.

```
$ tachyonc edit wrap calc::first --in unsafe
wrapped the body of crate::calc::first in unsafe→calc.tach→+4 -2 lines
$ tachyonc edit wrap calc.tach:19 --in '' --lines 17-21
wrapped lines 17-21 of crate::calc::sum_to in a block→calc.tach→+6 -4 lines
```

`error edit.wrap` when TARGET is no function with a body (give
`--lines`) or the lines are not all in it; `error edit.layout` when the
body's braces share their lines with code.

## edit new-file

`edit new-file PATH [--pub] < TEXT` (0.13) makes file PATH with TEXT and
its `mod NAME;` line (`pub mod` with `--pub`) in the file of the module
whose child it is, as the module loader finds children (next to the
root or a `mod.tach`; else in the directory named after the parent's
file; `a/b/mod.tach` for a module with children of its own), in one
checked edit: the new module is at once a TARGET of `edit patch` and the
other commands. The `mod` line goes after the parent's last `mod NAME;`
line, as `refactor new-module` puts it.

```
$ tachyonc edit new-file lib/extra.tach --pub < extra.tach
made crate::lib::extra→2 files→+6 -0 lines
```

`error edit.exists` when PATH exists; `error edit.no-parent` when no
file of the program would have it as a child's file (`refactor
new-module` makes the modules of a path).

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

**Imports (0.14).** TEXT may name items of other modules that its file
does not import: when the check finds new errors, a round of `fix
--only imports` on the edited file adds their `use` lines (merged into a
`use` of that module, else a new line, as the file writes its paths),
and the edit is checked again with them: `note edit.imports`, and the
lines are in the diff (`--show`, `query diff`); not with `--no-check`,
which asks for the errors. A name is imported from the module the
error's help names (`add `use crate::m::name;``: the first module with a
public item of that name), so a name several modules have is worth a
look at the diff. So does `edit patch`; in a
script, a step's round runs whether it has errors or not (a step is not
checked).

**A module's use lines and header (0.12).** `MODULE::use` and
`MODULE::header` are NAMEs for `edit replace`, `insert` and `delete` too:
`edit replace m::header < header.txt` replaces the comment at the top of
m's file (or puts TEXT there, a blank line after it, when it has none);
`edit replace m::use < uses.tach` replaces its first block of `use` lines
with TEXT and removes the others (none: TEXT goes after the header);
`edit insert --after|--before m::use` adds lines after the last `use`
line or before the first; `edit delete` removes them. The header is the
comment lines at the top of the file, except those right above the first
item (its own comment; not above a `mod` or `use` line). A header is
replaced, not inserted next to (`edit.layout`). (0.17) `MODULE::extern`
is one too: its `extern "C"` blocks (replace: the first becomes TEXT;
with none, TEXT goes after the `use` lines; insert after the last or
before the first).

**Files and modules (0.17).** `edit replace FILE.tach < TEXT` replaces
the whole file. `edit delete MODULE` (or `@@ delete MODULE`) removes its
`mod` line and its file, and its children's files: one edit, one `undo`.
A one-line `const` or `static` inserted next to one (`edit insert
--after B`) joins its run: no blank line between them.

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
prints the long form. About 60 ms on the compiler's source (77,000
lines); 0.13: about 7 ms when the program has not changed since a
command read it, from the tools' cache ([query.md](query.md#speed-the-cache-013)).

## tachyonc fix

Every fix the compiler can make by itself, in one atomic edit, one
summary line:

```
fixed 2 missing imports, 3 unused imports, 1 pub, 1 unsafe block→3 files→+3 -5 lines
```

| `--only` | what |
|---|---|
| `imports` | the `use` lines the errors for unknown names ask for (`help: add `use crate::m::name;``): merged into a `use` of that module when there is one, however its path is written (`use m::{a}` gains `, name`; `use m::a;` becomes `use m::{a, name};`), else a line after the module's last `use` (a child module's path relative when the module writes them so, 0.14); and 0.8's wildcard migration (`use a::*;` becomes the names it brings) |
| `unused` | imports whose name is written nowhere else in their file, removed (the name of a list with its separator; the item when all go; `use p::{a}` left with one name becomes `use p::a`). `pub use` is kept |
| `pub` | `pub` on the items other modules use while they are private (`error ... is private`) |
| `unsafe` | the unsafe operations outside unsafe code, wrapped in unsafe blocks (the outermost unit around each: a statement, `let p = unsafe { e };`, an expression); a function with several of them gets its whole body in one block, one level deeper, when its braces have lines of their own (0.12, the codebase's style; `--fix-unsafe` keeps 0.9's units) |

| `tidy-imports` | (0.12) the `use` lines in the codebase's style: the paths of a module's child modules written as most of its `use` lines that could be written either way write them (0.14: relative, `use a::x;`, or from `crate`, `use crate::m::a::x;`; a tie, as the first), the `use` items of a module with one path (and one `pub`) merged where the first is, their names sorted (byte order) and each once, `use p::a;` for one, `use p::{a, b};` when the line fits in 100 columns, else wrapped four spaces in, a line per name imported under another name (`use p::a as b;`); a `use` with a comment on its lines, or sharing a line, is left as it is, and one with a comment right above it is not merged into another |
| `reexports` | (0.12) every import and path that reaches an item through a re-export (a `pub use` of another module, or an ancestor's import: `use crate::f` where the root imports f) is written from the module that defines the item (`mod` lines on the way made `pub` when needed); then the re-exports nothing goes through any more are removed, or made private imports when their file still names them |
| `std015` | (0.15) a program written against 0.14's std moved to 0.15's I/O API, where failure is a Result with a typed error: each call the checker resolved to std's `parse_int` or `Scanner::next_int` gets `.ok()` (the old `Option<i64>`), `read_line` `.unwrap_or(false)` (the old `bool`), `read_stdin` `.unwrap()` (the old `Buf`), so the program means what it meant (exactly, but for `read_stdin` on a read error, which 0.14 read as empty input). Calls in generic functions are found through their instances; a function of the program with one of those names is not std's. A call whose value is already handled as a Result is left as it is, so a second run finds nothing: the operand of `?`; the receiver of `ok`, `err`, `map_err`, `is_ok`, `is_err`, `unwrap`, `unwrap_or`, `expect`, or `unwrap_or_else` with a one-parameter closure (for `read_line` and `read_stdin`, whose old types had none of Result's methods: of `unwrap_or_else`, `map`, `and_then` too); the scrutinee of a `match` or `if let` with an `Ok` or `Err` pattern; the value of a `let` whose type is written `Result<...>`. A Result kept in a local and handled further on (`let r = parse_int(s); match r { Ok(..) .. }`) is not recognised: run it once, on 0.14 code |
| `alloc016` | (0.16) a program written against 0.15's std, whose containers took their memory from an ambient allocator, made explicit (docs/design/effects-allocation.md §2.3): each call the checker resolved to one of std's 0.15 allocating forms (`#[ambient]`: `Vec::new()`, `with_capacity`, `filled`, `Buf::new()`, `HashMap::new()`, `collect()`, `format(x)`, `read_stdin()`, `split`, `split_whitespace`, `sort_stable`, `sort_stable_by`) becomes its `_in` form with the allocator last (`Vec::new_in(gpa)`, `it.collect_in(gpa)`, `format_in(x, gpa)`), and the `use` lines naming them are renamed (or gain the new name while a call is left). N, the functions holding such a call (in a closure of theirs too) and every caller of one, transitively, take `gpa: Gpa` after their other parameters (`fn main()` becomes `fn main(gpa: Gpa)`, `main(argc, argv)` gets it last), and each call of them passes `gpa` (labelled when it leaves a default before it); a trait's function of the program changes with the trait's declaration and every impl; a function that has a parameter of type `Gpa` already uses it by its name, and its callers stay as they are. What cannot take a parameter is an error naming where it allocates, `fix.alloc016-manual`: an impl of std's trait (`Display::fmt`), a function used as a value, a C-called `extern "C" fn`, a call in a parameter's default (take an `Option` and make the value in the body); the functions of N only it calls are left too. A call in a static's or constant's value: `fix.alloc016-static`. The edit is checked with the 0.15 forms errors (the program before it is checked the same way, so the calls left by an error are no new errors); exit 1 when something was left. A second run finds nothing |

By default the first four (`imports`, `unused`, `pub`, `unsafe`),
everywhere; `tidy-imports`, `reexports`, `std015` and `alloc016` only when asked
for (`--only reexports,tidy-imports` does both: the rounds tidy what the
first rewrote).

**Re-exports kept: the interface.** A `pub use` with a comment line
starting `// api:` right above it (in its comment lines) is the module's
interface: `reexports` keeps it and the imports and paths through it. A
program's own modules need none (the compiler has none); a library's
modules mark what they offer. With `--in`, only the imports and paths
there are rewritten, and only the re-exports there removed.

`unused` (0.12) keeps an import that another module imports or names
through (`use crate::f` reaching the root's `use util::f`): it is used,
although its file does not name it; `query unused` likewise.

`--in FILE|MODULE` keeps the fixes of one file or module, its child modules included for every fix (0.13; before, missing imports were fixed in the module alone) (matched like query's `--in`; none:
`error fix.bad-in`). A fix can let the checker see more: the checker
stops at the first unknown name of a statement, so its second appears
only once the first is imported. So fix runs again on the edited program
(`fix --round`, with the copies as overlays; up to four more rounds)
before the check, and the summary counts every round. Nothing to fix:
`note fix.none: nothing to fix` (exit 0).

`tachyonc --fix-imports ROOT` (0.8) and `tachyonc --fix-unsafe ROOT`
(0.9) are `fix --only imports` and `fix --only unsafe`, silent when
there is nothing to do.

**Which module (0.16).** The error of an unknown name helps with the
first module that has a public item of that name. When several modules
the file can name have one (of the same kind: a value, or a type),
`imports` takes the nearest: the one whose innermost module holding both
it and the importing module is deepest (a sibling before a cousin; std
is farther than any of the program's), then the one with the fewest path
segments. When more than one is that near, nothing is imported for that
name, and `error fix.ambiguous` (exit 1, the other fixes made) lists
them with a `try:` line each: `--use PATH::NAME` (repeatable) imports
NAME from there.

```
error fix.ambiguous: crate::back uses 'is_blank', which 2 modules as near have: crate::back::asm, crate::back::obj; nothing is imported for it: name one with --use
try: tachyonc fix --only imports --use crate::back::asm::is_blank
try: tachyonc fix --only imports --use crate::back::obj::is_blank
```

## tachyonc same-output

A pure refactoring proven to change nothing: every program of the
corpus is compiled by OLD (a path; 0.16: a name without a `/` and no
such file here is looked up in `$PATH`, as the shell does) and by this
compiler, for every target both
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
try: tachyonc --target aarch64-macos -O1 examples/md5/main.tach -o new.s
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

`query unused [MODULE|FILE]` (0.17: MODULE with its child modules): the
definitions nothing refers to (its
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
largest first, each with the deps of its module. A generated file (one
starting `// Generated by`, as `front/stdsrc.tach` and the guide's
`text/`) is not counted: its size is its generator's (0.14).

```
error lint.max-lines: compiler/src/front/check.tach: 4785 lines (at most 1000)
try: tachyonc query deps crate::check --max-lines 1000
```

Exit 1 when a file is over, 0 when none is.

## tachyonc fmt (0.13)

`tachyonc fmt [FILE|DIR...|MODULE|--all] [--check] [--dry-run]`: one
layout for tachyon source, written as one edit (journaled, `undo`); the
edit engine lays out the lines every edit writes the same way, and
`tachyonc explain CODE` says what any code of this page means. See
[fmt.md](fmt.md).

## Merge conflicts: query conflicts, edit resolve (0.15)

A merge leaves git's conflict markers in a file, and the file does not
parse until they are gone, so neither `query` nor `edit` can read the
program. These two read the files as text:

```
tachyonc query conflicts [FILE|DIR|FILE:LINE...] [--show]
tachyonc edit resolve FILE:LINE|FILE|NAME --ours|--theirs|--both|--base [--all] [--in FILE]
tachyonc edit resolve TARGET < TEXT
```

`query conflicts` prints one line per region (`<<<<<<<` to `>>>>>>>`;
diff3's `|||||||` base side too): its lines, its items, and each side's
size and label. Without a FILE it reads the `.tach` files with markers
under the root's directory. The items are found from the text: the items
whose header lines the region has (`fn f`, `struct S`, `use` lines; a
method as `T::m`), else the item around it, `-` when none. `--show`
prints each side's lines.

```
$ tachyonc query conflicts
main.tach:4-8→use→ours 1 line (HEAD)→theirs 1 line (feature)
shapes.tach:10-17→Shape::grow→ours 1 line (HEAD)→base 1 line (base)→theirs 2 lines (feature)
shapes.tach:22-27→area→ours 1 line (HEAD)→theirs 2 lines (feature)
$ tachyonc query conflicts shapes.tach:12 --show
// shapes.tach:10-17→Shape::grow
// ours (HEAD), line 11:
        (*self).w += by;
// base (base), line 13:
        (*self).w = (*self).w + 1;
// theirs (feature), lines 15-16:
        (*self).w += by;
        (*self).h += by;
```

`edit resolve` replaces a region by our side, theirs, both (ours then
theirs; a blank line between two top-level items), the base, or TEXT
from stdin. TARGET is a line of the region (`FILE:LINE`, a marker's
line too), a FILE with one region, or an item's NAME (`area`,
`Shape::grow`; `--in FILE` to look in one file). When several regions
match: `error conflict.ambiguous` with a `try:` line for each, or
`--all` resolves every one the same way. The file is written whole (a
copy renamed onto it) and journaled: `undo` takes it back. `--dry-run`
prints the diff, `--show` the new lines.

```
$ tachyonc edit resolve area --theirs
resolved shapes.tach:22-27 (theirs)→shapes.tach→+0 -4 lines
note conflict.left: 2 conflict regions left in 2 files
try: tachyonc query conflicts
```

While regions are left, `note conflict.left` counts them. The resolve
of the last one checks the program, and prints its errors with `warning
conflict.check` (the resolve is written: the sides chosen may not fit
together, as both sides' `use` lines importing a name twice).

## Diagnostics

| code | severity | exit | when | try |
|---|---|---|---|---|
| `edit.breaks` | error | 1 | the edit adds errors (they are printed); nothing written | the command with `--no-check` |
| `edit.breaks` | warning | 1, 0 | the same with `--dry-run`, or `--no-check` (written) | `tachyonc check` |
| `edit.refactor` | note | | (0.15) with edit.breaks: an edited item's shape changed and its uses broke | the refactoring that changes them with it |
| `edit.together` | note | | (0.15) with edit.breaks: items the edit does not change have errors | `query show` of them |
| `edit.format` | error | 2 | (0.15) apply: the file is not blocks | |
| `edit.overlap` | error | 1 | (0.15) apply: two blocks change one item | |
| `edit.no-module` | error | 1 | (0.15) apply: a new item for a module with no file of its own | `query items MODULE` |
| `edit.no-text` | error | 2 | replace or insert without TEXT on stdin; patch without pairs | the command `< new.tach`; with `--old OLD --new NEW` |
| `patch.no-match` | error | 1 | an OLD or ANCHOR is not in TARGET (with the nearest line) | the command with that line's text, or with `--loose`, or `query show FILE:LINE` |
| `patch.ambiguous` | error | 1 | an OLD or ANCHOR occurs several times (their lines) | the command with more context around each |
| `patch.overlap` | error | 1 | two OLDs overlap | |
| `patch.format` | error | 2 | the pairs on stdin (or in --pairs FILE) are not blocks | |
| `edit.not-source` | error | 1 | NAME is std's or a C header's | |
| `edit.layout` | error | 1 | insert next to an item that shares its line; wrap a body whose braces share lines with code | |
| `edit.wrap` | error | 1 | (0.13) wrap: no function with a body, or lines not in TARGET | `query show NAME` |
| `edit.no-parent` | error | 1 | (0.13) new-file: no file of the program would hold PATH as a child's file | |
| `edit.unchanged` | note | 0 | the edit changes nothing | |
| `edit.unchecked` | warning | | the check could not run | |
| `edit.exists`, `edit.write` | error | 1 | a file to make exists, a file cannot be written | |
| `edit.journal` | warning | 0 | the journal cannot be written (undo will not know the edit) | |
| `edit.usage`, `fix.usage`, `check.usage`, `lint.usage`, `same-output.usage` | error | 2 | a usage error | the corrected command |
| `undo.empty` | error | 1 | no edit to undo | |
| `undo.changed` | error | 1 | a file changed since the edit | `undo --force` |
| `fix.none` | note | 0 | nothing to fix | |
| `patch.no-region` | error | 1 | `MODULE::use` or `::header` to patch, and the module has none | `edit replace MODULE::use\|header`, which adds them |
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
  without `--loose` (wrapping lines in a new block: `edit wrap`, 0.13).

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
