# tachyonc query

`tachyonc query` answers questions about a program from the compiler's
front end: where a name is defined, its source, every reference the
checker resolved to it, and a module's items. It replaces reading the
source with `grep`, `sed -n 'N,Mp'` and `head` (see
[agent-tool-usage.md](agent-tool-usage.md)). Its reader is an agent: the
output is plain text, one fact per line, fields separated by a TAB (never
padding), as few tokens as the answer allows, and every problem is one
line saying what went wrong followed by the commands that recover
([Diagnostics](#diagnostics)). Facts are sorted by file (by path; the
compiler's own `<std>` and `<C import>` last), then line, then column.

```
tachyonc query def NAME... [--root ROOT] [--exact]
tachyonc query show NAME... [--root ROOT] [--exact] [--with-comments]
tachyonc query show FILE.tach... | MODULE::use | MODULE::header | MODULE::extern
tachyonc query context NAME...|MODULE [--budget TOKENS]     (0.15) source, calls, types, callers
tachyonc query text FILE[:A[-B]]...                         (no program read)
tachyonc query diff [ROOT]                                  the last journaled edit
tachyonc query refs NAME... [--root ROOT] [--exact] [--count] [--in FILE|MODULE] [--kind K,...] [--limit N] [--all]
tachyonc query callers NAME... [--root ROOT] [--exact] [--count] [--in FILE|MODULE] [--limit N] [--all]
tachyonc query callees FN... [--transitive] [--writes TABLE] [--count] [--limit N] [--all]   (0.16)
tachyonc query effects NAME...|MODULE [--has EFFECT] [--why EFFECT]   (0.16) the inferred effects
tachyonc query views NAME...|MODULE [--why]   (0.17) what results and `&mut` parameters view
tachyonc query features NAME... [--why FEATURE] [-C OPTION]   (0.19) what a function needs of the CPU
tachyonc query arch WORDS... [--feature F] [--arch A] [--equiv NAME]   (0.19) the intrinsic tables (also `intrinsics`; no program read)
tachyonc query items [MODULE|TYPE...] [--root ROOT] [--comments]
tachyonc query show MODULE::section TITLE                   (0.13)
tachyonc query grep PATTERN... [--in FILE|MODULE|ITEM] [--code] [--comments] [--strings] [--word] [--count] [--limit N] [--all]
tachyonc query type FILE:LINE[:COL]...                      (0.13)
tachyonc query own FILE:LINE:COL...                         (0.17)
tachyonc query stats [MODULE|FILE] [--over N] [--all]      (refactor.md)
tachyonc query deps MODULE [--max-lines N]                 (refactor.md)
tachyonc query unused [MODULE|FILE] [--all]                (refactor.md)
tachyonc query impact NAME                                 (refactor.md)
tachyonc query --help
```

Every command takes `--budget TOKENS` (0.15, [The output
budget](#the-output-budget-015)), and answers about std from any program
([std](#std-from-any-program-015)).

`ROOT` is the program's root file: `--root ROOT`, or (the form of 0.11's
first query) a last argument ending in `.tach` after the NAMEs (`items
ROOT` alone too). Without it: `$TACHYON_ROOT`, else `./main.tach`, else
`./compiler/src/main.tach`. Positions are `file:line:col`, 1-based, with
the file as the module loader names it (relative to the current
directory when ROOT is).

Several NAMEs are answered in one call, in turn (`show A B C`); refs and
callers list the references to all of them together, each line naming
its target. A NAME that matches nothing gets its diagnostic and the
others are still answered (exit 1).

The tools that change a program by name (`tachyonc edit`, `undo`,
`check`, `fix`, `lint`, `same-output`) and the planning queries (stats,
deps, unused, impact) are in [refactor.md](refactor.md).

Exit status: 0 answered, 1 no answer (nothing matches, an ambiguous
`show`, a program that could not be read), 2 usage error (or no root).

## Every command at a glance (for agents)

The table AGENTS.md carried until 0.17, when its core was cut to the
eight rows agents use (the rest cost tokens on every turn and was not
used: docs/research/applying-to-tachyon.md, item 2). Each row is what you
want and the command that does it, for the compiler's own source
(`target/tachyonc`; any program with `--root ROOT`). `tachyonc --help`
and `tachyonc CMD --help` print the same commands, `tachyonc guide
tools` the ones a program needs.

| you want | run |
|---|---|
| an item with what it calls, its types and callers, in one answer | `target/tachyonc query context NAME` (`--budget N`; a MODULE: its items and central bodies) |
| the source of a function, type, method | `target/tachyonc query show NAME` |
| where something is used | `target/tachyonc query refs NAME` (`--count`, `--in FILE\|MODULE`, `--kind write,call,...`; a local: `FN::x` or `FILE:LINE:COL`) |
| what a function calls, all it reaches; can it change a table | `target/tachyonc query callees FN` (`--transitive`; `--writes TABLE`: the writes and borrows it reaches, with the call chain) |
| text that is not a name (a message, a comment), with its item | `target/tachyonc query grep TEXT` (`--comments`, `--strings`, `--code`, `--word`, `--in`) |
| a module's section banners; one section | `target/tachyonc query items MODULE --comments`, `query show MODULE::section TITLE` |
| the type of an expression | `target/tachyonc query type FILE:LINE:COL` |
| each local's kind, moves and views at a position (0.17) | `target/tachyonc query own FILE:LINE:COL` |
| what a function may do (allocate, io, panic, loop forever) | `target/tachyonc query effects NAME\|MODULE` (`--why EFFECT`: the chain; `--has alloc(Gpa)`: which still allocate) |
| where it is defined, its signature | `target/tachyonc query def NAME` |
| what a module contains; a type's methods | `target/tachyonc query items MODULE`; `query items TYPE` |
| the item at a compiler error's position | `target/tachyonc query show FILE:LINE` (`--with-comments`: its section comment too) |
| a module's `use` lines, header comment, extern blocks | `target/tachyonc query show MODULE::use` (`::header`, `::extern`) |
| change a module's `use` lines or header comment | `target/tachyonc edit patch\|replace MODULE::use` (`MODULE::header`, `MODULE::extern`; `edit insert --after MODULE::use`, `edit delete`) |
| lines of any file (a test, a fixture, conflict markers), a small file | `target/tachyonc query text FILE:A-B`, `query show FILE.tach` |
| merge conflicts: the regions, their items, both sides; resolve one | `target/tachyonc query conflicts [FILE] [--show]`; `target/tachyonc edit resolve FILE:LINE\|NAME --ours\|--theirs\|--both` (`< text`, `--all`) |
| change a few lines inside an item (a condition, a statement; FILE:LINE: a comment between items too) | `target/tachyonc edit patch NAME\|FILE:LINE --old 'TEXT' --new 'TEXT'` (pairs repeat; several lines: `< pairs` or `--pairs FILE`, blocks `<<<<<<< OLD` / `=======` / `>>>>>>> NEW`; `--loose` for other indentation; OLD there several times: `--nth N`, `--all`) |
| add statements inside an item | `target/tachyonc edit insert --in NAME --after\|--before 'ANCHOR' < text` |
| replace, add or remove an item by name | `target/tachyonc edit replace NAME < new.tach`, `edit insert --after\|--before NAME`, `edit delete NAME` (a module: its file too; `edit replace FILE.tach`: a whole file; `--dry-run` for the diff; the `use` lines new text needs are added) |
| change several items (several files) in one checked edit | `target/tachyonc edit apply items.tach`: blocks `@@ NAME` (its new text), `@@ new after NAME`, `@@ new in MODULE`, `@@ delete NAME`, or `query show`'s output edited; `edit patch --in NAME` (or `@@ NAME` in `--pairs FILE`) starts another target's pairs |
| an edit refused with `edit.breaks` | each error says `[edited: PATH]` or `[in PATH]`; run the `try:` refactoring it names (`note edit.refactor`), or change the broken items in the same edit (`note edit.together`); `--no-check` last |
| see what an edit changed, without reading the file back | `--show` on any edit or refactoring; `target/tachyonc query diff` (the last one) |
| wrap a body or lines in a block (`unsafe`, `loop`), re-indented; make a file with its `mod` line | `target/tachyonc edit wrap NAME --in unsafe [--lines A-B]`, `edit new-file PATH < text` |
| take the last edit back | `target/tachyonc undo` (outside git: the journal is `.tachyonc/` next to the root) |
| add, remove, rename, reorder or retype a parameter, with every call | `target/tachyonc refactor signature FN --add 'x: i64 = 0'` (`--remove x`, `--rename-param a b`, `--reorder b,a`, `--type x T --default '$x as T'`) |
| add, remove, rename or retype a field, with every literal and access | `target/tachyonc refactor field STRUCT --add 'g: i64 = 0'` (`--remove g`, `--rename g h`, `--type g T`) |
| add a variant (an arm in each match that needs one), remove, rename one | `target/tachyonc refactor variant ENUM --add 'X(i64)' --arm 'EXPR'` (`--arm-in FN 'EXPR'` per match; `--remove V`, `--rename V W`) |
| move lines of a function into a new one, parameters and result computed | `target/tachyonc refactor extract-function FN --lines A-B --to NEW` |
| put a small function's body where it is called (and delete it) | `target/tachyonc refactor inline FN` (`--at FILE:LINE`: one call) |
| replace an idiom everywhere, typed | `target/tachyonc rewrite 'grow($v, $n)' '$v.reserve($n)' --where '$v: &mut IntVec' --dry-run` (`--list`: the sites and their holes; `--subst 'P' 'R'`: inside the holes' code; `--where '$v: name ~ RE'`; `--in FN\|MODULE\|FILE`, repeated) |
| rename anything (a module: its file too), with every reference | `target/tachyonc refactor rename PATH NEW` (a local or parameter: `FILE:LINE:COL` or `FN::x`, shadowing respected) |
| move items to another module, imports and `pub` fixed | `target/tachyonc refactor move PATH... --to MODULE` (`--after\|--before ITEM`: where; a MODULE that does not exist is made) |
| make a module; move one (file, folder, paths) | `target/tachyonc refactor new-module crate::a::b`, `refactor move-module crate::a crate::x::a` |
| split a module into files | `target/tachyonc refactor split MODULE --plan` (then `--auto`, or `--into M --items a,b`; `--names a,b`; `--reexport` leaves code outside as it is; `--header TEXT`) |
| several changes, checked once, all or nothing | `target/tachyonc refactor --script steps.txt` (one command per line; `<<END` ... `END` gives one its stdin) |
| several queries and edits in one call, outputs under `## $ tachyonc ARGS` lines | `target/tachyonc batch < cmds.txt` (one command per line; `--stop` at the first failure) |
| the errors, one per line (front end only) | `target/tachyonc check` |
| build what changed and run the tests; counts, then each failure | `target/tachyonc test [FILTER...]` (a program: `tests/NAME.in`/`.out`; `--full`, `--budget N`) |
| a crash's line and callers; values at a line as the program runs; a failing input made small | `target/tachyonc test` (built with `--trace`), `target/tachyonc probe FILE:LINE EXPR... -- ARGS`, `target/tachyonc reduce FILE --until 'CMD'` (`guide debug`) |
| missing/unused imports, `pub`, `unsafe` blocks | `target/tachyonc fix` (`--only imports,unused,pub,unsafe`, `--in FILE\|MODULE`, `--dry-run`; several modules have the name: `--use PATH::NAME`) |
| imports through re-exports, then the re-exports; merged, sorted, wrapped `use` lines | `target/tachyonc fix --only reexports,tidy-imports` (`// api:` above a `pub use` keeps it) |
| prove a refactoring changed no output | `target/tachyonc same-output OLD_TACHYONC` |
| file and item sizes | `target/tachyonc query stats [MODULE\|FILE]` |
| how a module's items use each other, how to split it | `target/tachyonc query deps MODULE --max-lines 1000` |
| what nothing uses | `target/tachyonc query unused [MODULE\|FILE]` |
| what a signature change touches | `target/tachyonc query impact NAME` |
| files over a size | `target/tachyonc lint --max-lines 1000` |
| lay code out (indentation, spaces, wrapping, `use` lines; edits do it too) | `target/tachyonc fmt FILE\|MODULE` (`--check`, `--dry-run`; `--all` the tree) |
| what a diagnostic code means, how to fix it | `target/tachyonc explain CODE` (`explain TOOL` lists its codes; `explain WORDS`: the guide on them) |
| std's API, a std item (from any program, or none) | `target/tachyonc query items std`, `query show std::read_line`, `query def Vec::push` |
| what an expression or a few statements do, with std | `target/tachyonc try 'STATEMENTS'` (prints the output and `TYPE = VALUE`; `--file F`) |
| the language on a word, an error message; one section | `target/tachyonc guide --find WORDS`, `guide TOPIC#SECTION` (`guide TOPIC#`: its sections) |
| add a std function, pass, diagnostic, test, subcommand: the steps; items to copy | `target/tachyonc guide how TASK`; `query examples KIND`; `query similar NAME` |
| a command's options | `target/tachyonc CMD [SUB] --help` |

NAME is `foo`, `module::foo`, `Type::method`, `Enum::Variant`,
`Struct.field` or `FILE:LINE`; several in one call; every spelling a
tool prints is taken back (`FILE:L:C:`, `FILE:A-B`, `Vec<i64>::push`,
`main.0`, `./x.tach`). Any query takes `--budget N` (tokens; answers over
8000 are cut, with the command that prints the rest). The root defaults to
`compiler/src/main.tach` (`--root ROOT`, or a last argument ending in
`.tach`, for other programs). A problem is one stderr line, `error CODE:
message`, then `try:` lines: commands to run as they are. A build prints
its errors as `check` does, one line each, when its output is not a
terminal (`--diagnostics=human` for the long form), so a `check` before
a build is redundant. Edits are atomic: an edit that adds an error
writes nothing and prints the errors ([refactor.md](refactor.md)).
`--json` on any command prints JSON lines, for scripts and hooks
([JSON](#json-for-a-harness-015)).

## Output formats

One line of grammar per kind of line (`\t` is a TAB; `[...]` optional):

| command | line | grammar |
|---|---|---|
| def | definition | `PATH \t FILE:LINE:COL \t KIND \t SIGNATURE [\t effects: SET]` |
| show | header | `// PATH \t FILE:FIRST-LAST [\t effects: SET]`, then the source lines, verbatim |
| effects (0.16) | function | `PATH \t SET`, then with `--why` its chain, indented two spaces |
| views (0.17) | function | `PATH \t views(..) [stores(..)] HOW`, then with `--why` a line per source, indented two spaces |
| show, > 5 matches | path | `PATH` (stdout), then `error query.ambiguous` |
| refs, callers | file header | `# FILE` |
| refs, callers | reference | `LINE:COL \t (def \| REFKIND \t ENCLOSING) [\t ->TARGET] \t SOURCE` |
| refs, callers, grep, > 60 | summary | `FILE \t COUNT`, then `note query.truncated` |
| refs, callers `--count` | count | `COUNT`, or `COUNT \t PATH` per definition when several match |
| callees (0.16) | callee | `DEPTH \t call\|ref \t PATH \t FILE:LINE [\t via CALLER]` |
| callees `--writes` (0.16) | place | `# FILE`, then `LINE:COL \t write\|borrow \t FN > ... > F \t SOURCE` |
| grep | file header, hit | `# FILE`; `LINE:COL \t (code \| comment \| string) \t ENCLOSING \t SOURCE` |
| type | type | `TYPE \t EXPRESSION` |
| context | item | the show header (`\t section: TITLE` when in one), source, then `// calls (N)`, `// types (N)`, `// uses (N)` with def lines, `// callers (N)` with `ENCLOSING \t FILE:LINE:COL \t SOURCE` |
| items MODULE | module header | `# PATH \t FILE` |
| items MODULE | item | `LINE \t KIND \t SIGNATURE` |
| items MODULE `--comments` | banner, comment | `FIRST-LAST \t (section \| comment) \t TITLE` |
| items | module | `PATH \t FILE \t ITEMS` |
| (stderr) | diagnostic | `SEVERITY CODE: MESSAGE` |
| (stderr) | recovery | `try: COMMAND` |

- PATH is a full path ([Paths](#paths)); it may contain spaces
  (`<crate::geom::V2 as Add>::add`), never a TAB.
- KIND is one word: `fn`, `method` (a function of an impl block, of a
  type or of a trait impl), `trait-method`, `struct` (also unions), `enum`,
  `variant`, `field`, `trait`, `const`, `static`, `type` (an alias), `mod`,
  and in `items` `impl` (an impl block's header).
- ENCLOSING and TARGET are short paths: the full path without its
  `crate::` prefixes (`gvn::run_gvn`, `<geom::V2 as Add>::add`; `crate` for
  the root module), which NAME accepts back.
- SOURCE is the line trimmed, cut to 100 bytes with `…` when longer.
- SIGNATURE and SOURCE are the last field: split a line at its first
  TABs only.

## Paths

Every definition has a fully qualified path, printed first wherever a
definition is named, and accepted back as NAME:

| definition | path |
|---|---|
| item of the root module | `crate::main` |
| item of a module (a file, or an inline `mod m { }`) | `crate::middle::gvn::run_gvn`, `crate::sys::SockaddrIn` |
| the standard library | `std::Vec`, `std::HashMap` |
| a C header's declaration (`import "h.h" as c;`) | `crate::c::printf` (the importing module's path and the `as` name of the first such import) |
| function of an `impl T { }` block | `crate::geom::V2::len`, `std::Vec::push` |
| function of an `impl Trait for T` block | `<crate::geom::V2 as Add>::add` (the trait by its path when two traits share its name) |
| function a trait declares (with or without a default) | `crate::shapes::Area::twice`, `std::Add::add` |
| enum variant | `crate::ast::NodeKind::Fn` |
| struct field | `crate::ir::Inst.op` |
| module | `crate::gvn` |

## Matching NAME

- A full path matches that definition.
- A partial path matches every path it ends, by whole segments:
  `run_gvn`, `gvn::run_gvn`, `V2::len`, `NodeKind::Fn`, `Inst.op`.
- A bare name (`push`) matches every function, type, variant, constant,
  static, trait, alias and module of that name, in any module, type or
  trait. Fields match only with a dot: `Inst.op`, or `.op` for every
  field named `op`.
- A trait impl's function also answers to `Type::f` (`V2::add`), and to
  `<Type as Trait>::f` with each part full or partial
  (`<V2 as Add>::add`).
- `--exact`: only a full path matches.
- `FILE:LINE` (or `FILE:LINE:COL`, as a compiler error has it) is the
  innermost item whose text (its comments and attributes included)
  holds that line: `query show gvn.tach:740` after an error there. FILE
  is matched like `--in`'s (the path, or its end by whole components).
  A line between items: `error query.no-match: no item at FILE:LINE`,
  `try:` the items of its module; an unknown file: `no file 'FILE' in
  the program`.
- An import alias (0.13): `use a::f as g;` makes `g` a reference to
  `crate::a::f`, and `g` as NAME answers for what it imports (when no
  definition is named `g`), with `note query.alias: 'g' is an import
  alias in crate, for crate::a::f`. `--exact` does not follow aliases.
- No match: exit 1, `error query.no-match`, and a `try:` line for each of
  the (at most 3) definitions whose names are nearest to NAME's last
  segment (edit distance at most a third of its length).

### Every spelling a tool prints (0.15)

What one command prints, another takes back as NAME, FILE or MODULE
(`query/names.tach`; `tests/query/run.sh` round-trips every name def,
show, refs, items, check and the assembly print):

| printed | taken as |
|---|---|
| `main.tach:12:5:` (a short diagnostic), `main.tach:12-30` (a show header) | `main.tach:12` |
| `./main.tach`, `/home/me/prog/main.tach` | the program's `main.tach` (by whole components) |
| `Vec<i64>::push`, `Vec::<i64>::new`, `twice<V2>` (an instance) | `Vec::push`, `Vec::new`, `twice` |
| `main.0`, `main.0.1` (a closure's symbol) | `main` |
| `_tachyon.std.Buf.new`, `tachyon.apply.GN6main.0`, `_tachyon.Tl.cmp` (a symbol of the generated code) | `std::Buf::new`, `apply`, `i64::cmp` |
| `a::mod`, `f()` | `a`, `f` |
| `std`, `std.tach`, `<std>` (a FILE) | std's source |
| `crate`, `a::b` (a module) | its `mod` item; the root's items, with `note query.module` |

`FILE:LINE` on a comment line is the item below it (a show header's
first line); outside every item (a `use` line) it is what the name at
COL (or the first on the line) names. `--in`, `items` and the
refactorings' module paths take a file's path (`./catalog.tach`) and a
path without `crate::` (`refactor new-module report`).

## def

One line per matching definition (shown here with the TABs as `→`):

```
crate::middle::gvn::run_gvn→compiler/src/middle/gvn.tach:721:8→fn→pub fn run_gvn(fi: i64) -> bool
```

The position is the name's. The signature is the source up to the body
or the `{`, its whitespace collapsed, with `pub` when the item is public;
a long constant's value is cut to `...`.

(0.15) A method `#[derive(...)]` makes (Eq's `eq`, Ord's `cmp`, Hash's
`hash`, Debug's `fmt_debug`, Clone's `clone`) has no source of its own:
`def P::cmp` (and show, refs, the refactorings' NAME) answers with the
attribute, `note query.derived: 'P::cmp' is derived, at main.tach:6:14:
#[derive] makes it; it has no source of its own` and `try: tachyonc
query show crate::P` (exit 1).

## show

Each matching definition's exact source: a header, then whole lines from
the comments and attributes directly above it through its end.

```
// crate::middle::gvn::run_gvn→compiler/src/middle/gvn.tach:721-796
pub fn run_gvn(fi: i64) -> bool {
    ...
}
```

A struct or enum shows its whole declaration (not its impl blocks);
`Type::method` shows the method. When more than 5 definitions match,
`show` prints only their paths, one per line, and fails (exit 1) with
`error query.ambiguous` and a `try:` line showing the first.

`--with-comments` (0.12) starts the text higher: with the comment block
above the item's own comments, after blank lines (a section comment,
`// ---- The edit engine ----`), when there is one.

### Text that is not an item (0.12)

Most reads that queries could not answer were plain text: a module's
`use` lines, a file's header comment, a test fixture, a file with merge
conflict markers. These are answered too:

| NAME | what show prints |
|---|---|
| `MODULE::use` | the module's `use` lines (each run of consecutive ones, with their continuation lines) |
| `MODULE::header` | the comment at the top of its file (to its first line that is neither a comment nor blank) |
| `MODULE::extern` | its `extern "C" { ... }` blocks |
| `FILE.tach` (every NAME a file) | the whole file, `// FILE:1-N` then its lines, when it has at most 200 lines; else `error query.too-long` with `try:` `query stats FILE` (compiler source) and `query text FILE:1-200` |

Each region is printed as an item is (`// crate::middle::gvn::use→compiler/src/middle/gvn.tach:12-20`,
then its lines); none: `note query.empty`. A module of an inline `mod m
{ }` has no file of its own: its name is matched as a NAME.

`query text FILE[:A[-B]]...` prints lines A to B of any file (`FILE:A`
one line, `FILE:A-` to the end, `FILE` all), numbered, without reading
the program (no root, no parse: a test fixture, a generated program, a
file with conflict markers, a doc):

```
// text/main.tach:6-8
6→mod util;
7→
8→use util::{
```

At most 200 lines: past them `note query.truncated` and `try:` the next
range. Lines past the end: `error query.no-match` with the file's
length and `try:` its last lines; a file that cannot be read: `error
query.no-file`.

`query conflicts [FILE|DIR|FILE:LINE...] [--show]` (0.15) lists the
merge conflict regions of files read as text, one line each, with their
items; `--show` prints both sides. `edit resolve` resolves them
([refactor.md](refactor.md), "Merge conflicts").

`query diff [ROOT]`: the last edit of the journal (what `undo` would take
back, [refactor.md](refactor.md)): `# SUMMARY`, then its diff with no
context lines. Nothing changes. In a git checkout the journal is in its
git directory; elsewhere (0.14) in `.tachyonc/edits/` next to the root.

### A file outside the compiler's source (0.12)

When the default root would be the compiler's (`./compiler/src/main.tach`,
or none) and a NAME is a `FILE.tach` or `FILE:LINE` outside compiler/src
and compiler/std, the root is that file's program: the `main.tach` of its
directory or of one of the two above it, else the file itself. So `query
show tests/run/loops.tach:12` answers from that test, not from the
compiler.

## refs and callers

Every resolved reference, one per line, under a header per file:

```
# compiler/src/middle/gvn.tach
721:8→def→pub fn run_gvn(fi: i64) -> bool {
# compiler/src/middle/opt.tach
17:17→use→opt→use crate::middle::gvn::run_gvn;
533:13→call→opt::simplify_function→run_gvn(fi);
```

The second field is the reference's kind (0.13), one word:

| kind | the reference is |
|---|---|
| `def` | the definition itself (no ENCLOSING follows) |
| `call` | a call (a method or operator call too) |
| `read` | a value read: a constant, a static, a field, a function as a value |
| `write` | the target of an assignment (`=`, `+=`...), or part of it: in `A.b[i].c = x`, `A`, `b` and `c`; not what a pointer it goes through points to, nor a method call's receiver (`V.push(x)` reads `V`) |
| `init` | a struct literal (its type and its fields), a constructed variant |
| `pat` | a variant in a pattern |
| `type` | a struct, enum, trait or alias in a type, an `impl` header or a path (`T::f`) |
| `mod` | a module in a path |
| `use` | an import |

`--kind K[,K...]` keeps those kinds (`refs COUNT --kind write`).

ENCLOSING (the third field) is the innermost definition holding the
reference (a function, or the struct, constant, trait... whose
declaration it is in), else the module (a `use`, an `impl` header), by
its short path.

References are what the compiler resolved, never text: calls, functions
used as values, constants and statics, types (in signatures, fields,
casts, `impl` headers, struct literals, patterns, paths `T::f`), field
accesses and the fields of struct literals, variants (constructed or
matched), method calls (resolved through the receiver's type, and
through a bound's impl in generic code), operator calls of trait impls
(`a + b` calls `<T as Add>::add`; at the start of the operation),
module paths, `Self` (0.13: a reference to the type of its impl block),
and `use` imports. A local that shadows a function,
another module's item of the same name, comments and strings are never
references.

- When the references are to several definitions (NAME matches several,
  or a trait's function and its impls), every line names its target in
  a third field, `->TARGET` (a short path):
  `32:29→main→->b::helper→let n = a_helper() + b::helper();`.
- A trait's function (`Area::area`, `std::Add::add`) also counts the
  references to the impl functions that implement it (`-><T as
  Trait>::f`); the functions of a trait impl that do not override a
  default are the default's references.
- Generic code is checked once per instance; a reference in it is
  listed once per position (and target). A generic function no code
  instantiates (0.13) is checked for a query as an instance whose type
  arguments are the error type: its references that do not depend on
  them are found (calls, constants, statics, types, struct literals);
  what does (a method of `T`, through a bound) is not.
- A function whose body has a syntax error (0.13) is checked for a query
  as far as it was parsed (the statement with the error left out, and
  the names it would have bound unknown, without errors).
- A reference inside a closure's body (0.14) is the enclosing
  function's (ENCLOSING names it). A closure's function and its
  environment struct are no definitions: refs, unused, stats and deps
  never list them; a call of a closure is no reference.
- (0.15) What `#[derive]` makes (impls written at the attribute's
  position) is no definition, and its uses of the type, its fields and
  std are no references; a trait the attribute names is one. A field
  shorthand `S { x }` is a reference to the field and to the value `x`
  at one position. An argument's label (`f(b: 1)`) is no reference: the
  call is `f`'s.
- `--count` prints the number of references refs would print (the
  definition included); for several definitions, `N→PATH` per definition.
- `callers` is `refs` restricted to calls (method and operator calls
  included; no definition line).
- `--in FILE|MODULE` keeps the references in a file (an argument with a
  `/`, ending in `.tach` or `<std>`: the path, or its end by whole
  components, `gvn.tach`) or a module (matched like NAME, its inline
  modules included: `gvn`, `crate::ir`), or the item holding a line,
  `FILE:LINE` (0.12; `rewrite --in` too; `fix --in FILE:LINE` fixes that
  line's module), or (0.13) a directory, by whole components
  (`compiler/src/front/`, `front/check`), or (0.17) an item, by NAME
  (`--in run_patch`: the references in its text; a function, a type, a
  const...).
- (0.17) A string or C-string constant (`const S: [u8] = "..."`, `const
  C: *u8 = c"..."`) has its uses as references: the checker puts the
  literal in their place, refs finds them by their name.
- None left: `note query.empty: 0 refs` (exit 0).
- (0.16) A local variable or a parameter: `FN::x` (every local named
  `x` in FN: the one a `let` shadows and the one shadowing it too), or
  `FILE:LINE:COL` at its declaration or at a use (as `refactor rename`
  takes a local). Its declaration is `def`, an assignment to it (or into
  it: `x.f = 1`, `x[i] += 1`) `write`, any other use `read`; `--kind`,
  `--count` and `--in` apply. A FILE:LINE:COL that is on no local is
  answered as before (the item holding the line). Locals are what the
  checker resolved, so these read the program in full (no cache).

```
$ tachyonc query refs sum::total
# calls016/main.tach
12:13→def→let mut total = 0;
15:9→write→sum→total += i;
17:13→read→sum→total = total * 2;
```

### The budget

More than 60 references (after `--in`) are not listed: refs prints how
many each file has, and how to narrow the question:

```
compiler/src/back/abi.tach→10
...
compiler/src/middle/vectorize.tach→60
note query.truncated: 645 refs in 44 files
try: target/tachyonc query refs IntVec::push --in compiler/src/middle/vectorize.tach
try: target/tachyonc query refs IntVec::push --limit 60
try: target/tachyonc query refs IntVec::push --all
```

(the `--in` suggestion is the file with the most). `--limit N` lists the
first N, then `note query.truncated: showing N of M refs`; `--all` lists
everything.

## callees (0.16)

`callees FN` lists the functions FN calls and the functions it names as
values (a function passed as `fn(..)`: it may be called through the
pointer), one per line: `DEPTH→call|ref→PATH→FILE:LINE` (where the
callee is defined). `--transitive` follows them: every function reachable
so, by depth, each from depth 2 on with `via CALLER`, the function it was
first reached from. They come from the references the checker resolved
(each counted for the innermost item holding it); a call through a
function pointer is not followed, the function named where the pointer
was made is. Past 100 lines, `note query.truncated` and `--all`;
`--count` the number.

```
$ tachyonc query callees add_and_sum --transitive
1→call→sum→calls016/main.tach:11
1→call→table::grow→calls016/table.tach:6
2→call→table::peek→calls016/table.tach:19→via sum
2→call→table::put→calls016/table.tach:12→via table::grow
```

`--writes TABLE` (a static or a field) answers whether FN can change
TABLE: the places in FN and every function it reaches that write it (an
assignment to it, or into it: `TABLE.count = 0`, `TABLE.data[i] = x`) or
borrow it (`&TABLE`, and a method taking `self: *T` called on it, as
`TABLE.push(x)`: it may grow), each with the chain of calls from FN.
None: `note query.empty: FN reaches no write or borrow of TABLE (N
functions reached ...)`.

```
$ tachyonc query callees main --writes TABLE
# calls016/table.tach
8:14→borrow→main > add_and_sum > table::grow→put(&TABLE, x);
```

## effects (0.16)

`effects NAME...` prints the effect set the front end inferred for each
function NAME names (docs/design/effects-allocation.md §2.1; `guide
effects`): `PATH \t SET`, the set written `alloc(Gpa, Arena) io global
panic diverge unsafe` (that order; `alloc` alone for any allocator,
`alloc(extern)` for C's; `none` for the empty set; ` (unknown)` after a
set the front end could not infer, a body that failed to check). A
generic function's line is each of its instances' (`apply<closure(i64)
-> i64 at main.tach:47:32> \t panic`). A MODULE gives the functions of
it and of the modules under it (the root's: not std's).

- `--has EFFECT` keeps the functions whose set has EFFECT: `alloc` (any
  allocator), `alloc(T)` (that allocator type, or any), `alloc(extern)`,
  `io`, `global`, `panic`, `diverge`, `unsafe`, or `none` (the empty
  set). `query effects crate --has alloc(Gpa)` finds what still
  allocates from a Gpa.
- `--why EFFECT` adds, under each function's line, why it has EFFECT:
  the chain of calls down to the operation it starts at
  (front/effects/why.tach), each line indented two spaces; `(not:
  EFFECT)` when it has not.
- An unknown EFFECT is `error query.usage` (exit 2).

`def`, `show` and `context` add `effects: SET` to a function's line (a
TAB before it): not for a generic function (its instances differ) nor a
set that could not be inferred. The cache keeps the text per definition,
so the warm answers stay as fast; `effects` without `--has` and `--why`
is answered from it too.

```
$ tachyonc query effects total --why alloc
crate::total→alloc(Gpa) panic
  ...the chain...
```

## features (0.19)

`features NAME...` prints what each function NAME names needs of the CPU
beyond the build's features (docs/design/arch.md §2.4): `PATH \t
FEATURES (inferred)`, `FEATURES (declared)` for a #[target_feature]
function (its declaration is its requirement), or `none` (callable
anywhere; `none (declared: crc)` when the build has what it declares). The
requirement is inferred over the calls, as effects are: an intrinsic's
features, less what each call's point knows (the build's, the function's
declaration, the has()/detect() guards around it). A generic function's
line is each of its instances'. `-C target-cpu=CPU` and `-C
target-feature=+x,-y` set the build's features, as for a build (`check`
and the editing commands take them too).

- `--why FEATURE` adds, under each line, the calls that bring FEATURE in,
  one indented line each, `FILE:L:C: calls 'NAME'`, down to the intrinsic
  (`, which needs crc`); `(not: FEATURE)` when it does not need it.
- An unknown FEATURE is `error query.usage` (exit 2).

```
$ tachyonc query features twice --why crc -C target-cpu=generic
crate::twice	crc (inferred)
  features019/main.tach:11:5: calls 'hw'
  features019/main.tach:7:5: calls 'std::arch::aarch64::__crc32cd', which needs crc
```

### features: on def, show and context

`def`, `show` and `context` print `features: crc (inferred)` (or
`(declared)`) after `effects:` on a function's first line when it needs
something beyond the build's features; nothing when it needs nothing
(the requirement of `query features`, cached with the effects).

## arch (0.19)

`arch WORDS...` (also spelled `intrinsics`) searches the intrinsic
tables (`compiler/arch/*.def`, docs/design/arch.md §2.1) without reading
a program: one intrinsic a line, `MODULE::NAME \t FEATURES \t
INSTRUCTION \t DOC`, the module below `std::arch` (`aarch64::`,
`x86_64::`, none for the portable ones), the instruction the table's
template (`<d>` the result, `<a>` parameter a).

- A WORD matches (any case) the name, a feature, the instruction, the
  doc, the semantics or the equivalent, weighed in that order; the best
  first, the tables' order among equals. Every WORD must match; when no
  intrinsic matches them all, those matching the most are printed with
  `note query.partial`. A few plain words also match the tables'
  spellings: `subtract` is `sub`, `multiply` `mul`, `search`, `find`,
  `equal` and `compare` a `== b`, `popcount` `1 bits`, `byte` `u8`,
  `checksum` `crc`.
- `--feature F` keeps the intrinsics that need F (alone: lists them);
  `--arch aarch64|x86_64|portable` one table.
- `--equiv NAME` prints NAME's line, its `equivalent:` column (the
  other architecture's intrinsic, or a recipe), the lines of the
  intrinsics that names, and those whose equivalent names NAME.
- Nothing matches: `error query.no-match` and `try: tachyonc guide
  arch#recipes` (exit 1). The answer is cut at `--budget` as any.

```
$ tachyonc query arch saturating subtract u8
aarch64::vqsubq_u8→neon→uqsub <d>.16b, <a>.16b, <b>.16b→lanewise a - b, saturating at 0 and 255
aarch64::vqsub_u8→neon→uqsub <d>.8b, <a>.8b, <b>.8b→lanewise a - b, saturating at 0 and 255
$ tachyonc query arch --equiv _mm_movemask_epi8
x86_64::_mm_movemask_epi8→sse2→pmovmskb <a>, <d:w>→the 16 bytes' top bits as a 16-bit mask
equivalent: aarch64: (recipe) vshrn_n_u16(vreinterpretq_u16_u8(m), 4)
aarch64::vshrn_n_u16→neon→shrn <d>.8b, <a>.8h, #<n>→each lane shifted right by n, narrowed ...
aarch64::vreinterpretq_u16_u8→neon→-→the same bits as 8 u16 lanes
```

### An intrinsic in def, show and context

A NAME that is an intrinsic (`vqtbl1q_u8`, `_mm_movemask_epi8`, or any
`std::arch::...` path) is declared for the question, whether or not the
program names it, and the program is read with std (with no program,
std alone). Its first line carries `features:` and `instruction:` from
the table; `show` and `context` add its doc, what it computes, its
equivalent and its `use` line:

```
$ tachyonc query show vqtbl1q_u8
// std::arch::aarch64::vqtbl1q_u8→<std::arch::aarch64>:109-110→effects: none→features: neon→instruction: tbl <d>.16b, {<t>.16b}, <idx>.16b
// a table lookup: lane k is t[idx[k]], 0 when idx[k] >= 16
// computes: r[k] = if idx[k] < 16 { t[idx[k]] } else { 0 }
// equivalent: x86_64: _mm_shuffle_epi8 (zeroes when bit 7 is set instead)
// use std::arch::aarch64::vqtbl1q_u8;
#[intrinsic(1404)]
pub fn vqtbl1q_u8(t: uint8x16_t, idx: uint8x16_t) -> uint8x16_t;
```

## views (0.17)

`views NAME...` prints each function's view summary
(docs/design/value-semantics.md §2.4): which parameters its result
points into, and what its `&mut` parameters may come to hold. `p` is
what the argument p points into (the referent of `p: &T`, the storage of
`p: [T]`), `*p` what the views p holds point into: `Vec::as_slice` is
`views(self)`, a parser method returning a token's text `views(*self)`,
`intern(names: &mut Vec<[u8]>, word: [u8])` `views() stores(word)`.
After it, how it is known: `inferred` (from the body, callees first),
`declared` (`#[views(..)]`, `#[stores(..)]`), `parametric` (a generic
result made of its type parameters: by its type), `assumed` (a body that
did not check: every parameter). A MODULE gives its functions whose
summary is not `views()`.

- `--why` adds, under each function's line, the `return` or tail that
  makes each source, and the callee's summary when the value is a call.

`def`, `show` and `context` add `views: SUMMARY` after the effects when
it is not `views()`; `--print-views` prints every function's summary
after checking, as `--print-effects` does.

```
$ tachyonc query views Parser --why
crate::Parser::name→views(*self) inferred
  why: parse.tach:4:83 't.text': views what 'self' holds
```

## context (0.15)

`query context NAME` answers in one call what takes three to five
queries (show, then show of what it calls, then refs): the item's source
with its comments (and the title of its section, `items --comments`),
the def lines of what it calls (the most specific first: the least used
in the program) and of the types and statics it uses (a short struct or
enum whole), and its callers with their lines (`used by` for a type). It
is fitted to a budget, 2000 tokens by default (`--budget N`): the source
gets at least half; what does not fit is counted in a last note with
the commands that print it:

```
$ tachyonc query context report --budget 120
// crate::report→context/main.tach:9-15→section: Reports
// The total, after restocking the empty items.
fn report(items: *Vec<Item>) -> i64 {
    ...
}
// calls (3)
std::Vec::len→<std>:120:12→method→pub fn len(self: *Vec<T>) -> i64
crate::stock::restock→context/stock.tach:10:8→fn→pub fn restock(items: *Vec<Item>, i: i64, n: i64)
// callers (2)
main→context/main.tach:21:13→let n = report(&items);
note query.budget: over the budget of 120 tokens, left out: calls 1, types or uses 2, callers 1
try: tachyonc query callers report
try: tachyonc query context report --budget 360
```

`query context MODULE` prints `items MODULE --comments`, then the
bodies of the module's functions, those its own code calls most first,
then those called most from outside, as far as the budget goes.

## The output budget (0.15)

`--budget TOKENS` (4 bytes a token) on any query cuts the answer at a
line, with `note query.budget: cut at about N tokens: L of M lines
(about T tokens in all)` and `try:` the command with the budget it
needs. Without --budget an answer over 8000 tokens is cut the same way
(not with `--all`; `--budget 0` is no limit). The diagnostics come after
the answer.

## std from any program (0.15)

std's items answer from every root, whether the program uses std or
not, and where there is no program at all (a directory without
`main.tach`):

- a question that names std (`std`, `std::read_line`, `<std>`,
  `std:A-B`, `--in std`) reads the program with std (and without the
  cache);
- a NAME that std defines and the program does not (`Vec::push`,
  `read_line`) is asked again with std;
- `items std` lists std's API: its `pub` items and trait impls (`--all`:
  the rest);
- `show` of a std item adds the `use` line a program needs (`// use
  std::HashMap;`; none for the prelude);
- `text std:A-B` prints std's source (as `<std>` numbers it), `grep
  TEXT --in std` searches it.

(0.17) In the tachyon repository, where std's files are
(`compiler/std/*.tach`, found from the current directory or one of the
three above it) and are the std built into the compiler, std's
positions are those files' lines: `query def std::trim` prints
`compiler/std/io.tach:102:8`, not `<std>:2075:8`; a FILE:LINE in one of
them (`query show compiler/std/io.tach:102`, `--in
compiler/std/io.tach`) reads std from its files. Elsewhere std is the
compiler's text, `<std>`. The edits of std items: refactor.md, "Editing
std by name".

## similar and examples (0.17)

`query similar NAME...` prints the items like NAME, nearest first (3,
`--limit N`), in full as `show` prints them, after a line saying how
many there are and the edit that adds one beside NAME: the templates
for a new item of the kind. A method: the methods of its type (none:
of the other types of its module); a trait's method: the same method
of the trait's other impls; anything else: the items of its kind in
its module, its file's first.

```
$ tachyonc query similar std::trim --limit 1
// 1 of 135 fns like std::trim, nearest first; a new one beside it: tachyonc edit insert --after std::trim < new.tach
// std::is_digit→compiler/std/io.tach:96-99→effects: none
...
```

`query examples` lists the kinds of "add an X" change to the compiler
and std (`std-fn`, `std-method`, `peephole`, `egraph-rule`, `pass`,
`diagnostic`, `tool-diagnostic`, `subcommand`, `query-command`,
`test`), each with where it goes and its recipe in `tachyonc guide how`;
`query examples KIND` prints the kind's items to start from (their
definitions, then the first one's source; `test`: files). The table of
items is the compiler's own; tests/query/run.sh checks that every one
is still found (`self_examples`).

## items

`items MODULE` lists a module's items in order, without bodies:

```
# crate::geom→clash/geom.tach
4→fn→pub fn Point(x: i64) -> i64
8→struct→pub struct V2
13→impl→impl V2
15→method→pub fn len(self: *V2) -> i64
20→impl→impl Add for V2
21→method→fn add(self: V2, o: V2) -> V2
```

An impl block is its header line (kind `impl`) followed by its
functions. MODULE is a module path, matched like NAME (`gvn`,
`crate::gvn`, `crate`, `std`). `items` alone lists the module tree:
`PATH→FILE→ITEMS` per module.

`items TYPE` (0.17), when no module has that name: a struct's, enum's
or trait's line (`# PATH→FILE:LINE:COL`, then `LINE→KIND→SIGNATURE`),
then the functions of its impl blocks, each block under its header; a
std type (`items Buf`, `items std::Vec`) lists std's API for it. An
unknown method's error names it as its `try:` line.

### Banners and comments (0.13)

`items MODULE --comments` lists, between the items, the module's
section banners and its comments that belong to no item, each with the
lines it spans:

```
# crate::middle::gvn→compiler/src/middle/gvn.tach
58-156→section→The value table
62→static→static mut VT_KEYS: IntVec = ...
...
158-361→section→Alias analysis
```

A banner (`section`) is a block of comment lines outside every item
whose first line is a rule: `// ---- Title ----` (a run of `-`, `=`, `#`,
`*` or `~`; a run of two or three needs another after the title); its
section runs to the next banner of its file, or the file's end (its
trailing blank lines left out). A `comment` is any other block of
comment lines outside the items that no item follows directly (a blank
line, or nothing, comes after it) and that is not the file's header;
its title is its first line.

`show MODULE::section TITLE` (`main::section` for the root) prints a
section, as show prints an item: `// MODULE::section Title→FILE:A-B`,
then its lines (at most 200: then `note query.truncated` and `try:` the
next lines with `query text`). TITLE matches a title exactly, else but
for case, else as a part of it (`value table`); a section before a
comment. None: `error query.no-match`, `try:` the listing.

## grep (0.13)

`grep PATTERN...` searches the program's files for the text (any of
the PATTERNs, literally), for what is not a name: a message, a word in
the comments, part of an identifier. Each hit is printed as a reference
is, under its file, with where it is and the item holding it:

```
# compiler/src/tools/query/diagnostics.tach
23:42→comment→tools::query::diagnostics→// The codes are stable: query.no-match, query.alias, ...
288:40→string→tools::query::diagnostics::no_match→let out = diag(c"error", c"query.alias");
```

Code, comment or string (a string or character literal) comes from the
lexer's tokens. `--code`, `--comments`, `--strings` keep the hits there
(any of them); `--word` the hits that are whole identifiers. `--in`,
`--count`, `--limit N`, `--all` and the budget are refs'. The files the
compiler makes (`<std>`, `<C import>`) are searched only when `--in`
names them. No hit: `note query.empty`. (0.17) A hit in a comment right
above an item (its doc comment, no blank line between) is that item's
(`route::ride_cost`, a field's `Entry.line`), not the module's.

## type (0.13)

`type FILE:LINE:COL` prints the type the checker gave the innermost
expression holding that position, and the expression; without COL, the
outermost expression that starts on the line:

```
i64→area(s) + area(s) + unsafe { COUNT }
```

In a generic function, one line per type its instances give it. A
position in no checked expression (a declaration, a type, a function
never checked): `error query.no-match`, `try:` the item at that line.

(0.14) A closure's type is written `closure(i64) -> i64 at FILE:LINE:COL`
(where it is written); a closure's parameter has its type; a use of a
captured local has the local's type (the environment the closure reads
it from is not shown).

(0.15) `e?` has the type of its value (`i64→half(v)?`); a value the
checker widens is shown with its own type and what it becomes,
`i32 (widened to i64)→n`; a hole of an f-string is an expression as any
other (`{p.x + q.y:>4}`: `i64→p.x + q.y`), and a position on its text
gives the f-string's type. What the compiler writes for an f-string or a
`?` (the hidden locals `__f0`, `__out`, the match a `?` is) is never
shown.

## own (0.17)

`own FILE:LINE:COL` shows the own pass's state at a position
(docs/design/value-semantics.md §2.9): the position and its function,
then a line per local in scope there (parameters first, then in the
order they are declared), its name, type and kind (`plain`, `owned`,
`view`, `owned view`), and, from the own pass's walk of the function
(front/own/observe.tach), whether it is moved (where, into what) and the
views it holds (what they view, where they were taken, what invalidated
them). Without the walk (a template never instantiated, or before the
checker has it), the kinds alone:

```
main.tach:16:17 in crate::main
gpa    Gpa       plain
v      Vec<i64>  owned
first  [i64]     view
```

A `let`'s names are in scope after the `let`. A position in no function
the checker saw: `error query.no-match`, `try:` the item at that line.

## Diagnostics

Every problem is reported on stderr, after the answer, in one format:

```
SEVERITY CODE: MESSAGE
try: COMMAND
```

SEVERITY is `error` (no answer), `warning` (an answer that may be
wrong) or `note` (an answer cut short, or empty). CODE is stable and
dotted; MESSAGE is one line. Zero to three `try:` lines follow, best
first, each a command to run as it is (the compiler as it was run, ROOT
when it was given, names quoted for the shell when they need it).

| code | severity | exit | when | try |
|---|---|---|---|---|
| `query.no-kind` | error | 2 | (0.17) `query examples KIND` names no kind | `query examples` |
| `query.no-match` | error | 1 | no definition (or module, for items) answers to NAME | the nearest definitions by edit distance (the same command with their paths); else the items of the module NAME names, or the module tree |
| `query.alias` | note | (the answer's) | NAME is the other name an import gives (`use a::f as g;`), answered for what it imports (0.13) | |
| `query.empty` | note | 0 | grep found nothing | |
| `query.no-match` | error | 1 | `show MODULE::section TITLE`: no such title; `type`: no checked expression there | `items MODULE --comments`; `show FILE:LINE` |
| `query.ambiguous` | error | 1 | `show` matches more than 5 definitions (their paths on stdout) | `show` of the first |
| `query.truncated` | note | 0 | refs/callers past the budget, or cut by `--limit` | `--in` the file with the most, `--limit 60`, `--all` |
| `query.empty` | note | 0 | refs/callers found nothing (after `--in`) | |
| `query.bad-in` | error | 1 | `--in` names no file or module of the program (`no item at FILE:LINE` for a line between items) | the command without `--in` |
| `query.no-file` | error | 1 | `text` or `show FILE`: the file cannot be read | |
| `query.too-long` | error | 1 | `show FILE` of more than 200 lines | `query stats FILE`, `query text FILE:1-200` |
| `query.truncated` | note | 0 | `text` of more than 200 lines | the next range |
| `query.empty` | note | 0 | `show MODULE::use` (`header`, `extern`): none | |
| `undo.empty` | error | 1 | `diff`: no edit in the journal | |
| `query.program-errors` | warning | (the answer's) | the program has errors: their number, and the first one when nothing answered | the compilation that lists them all, one per line |
| `query.program-errors` | error | 1 | the program could not be parsed at all | the same |
| `query.no-root` | error | 2 | no ROOT, no `$TACHYON_ROOT`, no `./main.tach` or `./compiler/src/main.tach` | the command with a root |
| `query.bad-root` | error | 2 | ROOT cannot be read | the command without it, when a default root exists |
| `query.usage` | error | 2 | no command, an unknown command or option, a missing NAME or option value, an extra argument | the command corrected (the nearest command, the option dropped, `--limit 60`), or `items` |

```
error query.no-match: no definition 'run_gnv'
try: target/tachyonc query def crate::middle::gvn::run_gvn
note query.alias: 'MyVec' is an import alias in crate, for crate::myvec::Vec
error query.no-root: no root (TACHYON_ROOT, ./main.tach, ./compiler/src/main.tach)
try: target/tachyonc query def main path/to/main.tach
warning query.program-errors: 4 errors in the program; results may be incomplete
try: target/tachyonc --diagnostics=short broken/main.tach -c -o /dev/null
```

`tachyonc explain CODE` (0.13; [fmt.md](fmt.md)): what a code means, how
to fix it, an example; for every code of every tool, and the compiler's
error kinds (`explain type-error`).

## JSON, for a harness (0.15)

`--json`, anywhere on the command line of any command (`query`, `check`,
`edit`, `refactor`, `fix`, `undo`, a build), prints one JSON object per
line instead of the text: for a harness, a hook or a script, not for
the model, which reads the text form as well and in fewer tokens.

- Each diagnostic (on stderr, where the text would be): the tools'
  `SEVERITY CODE: MESSAGE` with its `try:` lines, a compiler error, an
  edit's new errors (on stdout, as now):

  ```
  {"kind":"diagnostic","severity":"error","code":"type error","file":"main.tach","line":4,"col":5,
   "message":"undefined variable 'prinln'","help":["did you mean 'println'?"],"notes":[],"try":[]}
  {"kind":"diagnostic","severity":"error","code":"query.no-match","file":null,"line":null,"col":null,
   "message":"no definition 'nosuch'","help":[],"notes":[],"try":["tachyonc query items"]}
  ```

  `code` is the tool's code or the compiler error's kind (`type error`,
  `parser error`, ...); `file`, `line` and `col` are null without a
  position; positions inside the texts are `FILE:LINE:COL`. `try` holds
  the commands as the agent would run them (without `--json`).
- Every other line of stdout: `{"kind":"output","fields":[...]}`, its
  TAB-separated fields ([Output formats](#output-formats)); an edit's
  summary is `["patched crate::add","main.tach","+1 -1 lines"]`.
- Every key is always there, in this order; new keys may be added at
  the end.

tools/agent-hooks/check-after-edit.py (the check after every edit, in
AGENTS.md) and the agent eval's `final_check` (tests/agent-eval) read
`check --json`. tests/refactor/json.t has a transcript.

## Programs with errors

The query runs the front end as a compilation would, with its error
recovery, and answers from what it got: definitions come from the parsed
program, references from what the checker resolved. The errors are never
listed: `warning query.program-errors` counts them, names the first when
nothing answered, and gives the compilation that prints them all with
`--diagnostics=short` (one line each:
`FILE:LINE:COL: error[KIND] MESSAGE | help: ...`). (0.15) A build whose
stderr is not a terminal (an agent's shell, a pipe, a file) prints that
form by default, the same lines as `tachyonc check`;
`--diagnostics=human` asks for the multi-line form.

## Speed: the cache (0.13)

A question reads the program as a compilation would: about 60 ms on the
compiler's source (77,000 lines), of which reading and lexing take 18,
parsing 9, checking 31 and the query's index 2 (`--time-passes` on
`query`, `check` and `edit` prints the phases). Agents ask hundreds of
questions of a program that has not changed between them, so a command
that read a program in full leaves what the queries take from it in a
cache, and the next question about the same program reads the cache and
the program's files, and neither lexes, parses nor checks:

| command (compiler/src) | 0.12 | 0.13, cache missed | 0.13, from the cache |
|---|---|---|---|
| `query show run_gvn` | 66 ms | 62 ms | 5.9 ms |
| `query def run_gvn` | 64 ms | 65 ms | 6.1 ms |
| `query refs run_gvn` | 69 ms | 68 ms | 6.5 ms |
| `query refs IntVec::push --count` | 70 ms | 69 ms | 7.7 ms |
| `query items gvn` | 61 ms | 62 ms | 6.0 ms |
| `check` | 59 ms | 63 ms | 7.6 ms |
| `edit patch run_gvn ...`, after a query or an edit | 129 ms | | 73 ms (its own reading) |
| the query after that edit | 66 ms | | 7.8 ms |

(wall time, best of 7; after `undo` the next command reads the program
in full.) What is used from the cache: `query def`, `show` (with
`MODULE::section`), `refs` (with the kinds), `callers`, `items` (with
`--comments`); `check`; and the reading of `edit patch`, `insert`,
`replace` and `delete` (their check of the edited program reads it in
full). `query grep` and `query type` take the tokens and the checked
nodes, which are not cached: they read the program in full and leave the
cache as it is. The answers are the same code, on the same tables,
byte for byte: tests/query/run.sh and tests/refactor/run.sh run every
transcript without the cache and with it (a query twice: the second
must come from the cache when the first made it).

- Where: `target/tachyonc-cache/q-KEY.bin` and `q-KEY.refs` (every
  reference, read by refs and callers only), KEY a hash of the root as
  given, the current directory and the target. `$TACHYON_CACHE` names
  another directory, or `off`; without it there is a cache only when the
  current directory has a `target` directory.
- When it holds: for the compiler that wrote it (a hash of its
  executable), when every file of the program has the text it had (each
  is read again and hashed: an edit by any means is seen), and when the
  module files that were looked for and not found (`a.tach` before
  `a/mod.tach`) still do not exist. Else the program is read in full and
  the cache made anew.
- Made: by the `query` commands that use it and `check` (which then
  also records what the queries need), after the answer is out, by a copy of the process (fork) while
  the command ends; in the process itself with `--time-passes` or
  `$TACHYON_CACHE_TRACE` (a file that gets `hit`, `miss` or `save` per
  use: the tests). `check --overlay` (an edit's check of the edited
  program) makes `q-KEY.next.bin`: the cache once the edit is written,
  taken over by the next command that finds it holds (else removed).
- Not cached: a program that imports C headers (their text is not a
  file of the program), one that could not be parsed. A damaged or
  partly written file is not read (a hash of its contents; written
  through a new file renamed over the old).
- (0.18.1) Beside it, a build's code cache, `g-KEY.pack`: each
  function's optimized code at -O1 and -O2, reused by a rebuild where an
  edit did not change it ([optimizer.md](optimizer.md), "0.18.1:
  incremental rebuilds"); `--no-cache` goes without.

## Several commands in one call: batch (0.15)

`tachyonc batch [FILE] [--root R] [--stop]` runs the commands of FILE
(or stdin), one per line as typed after `tachyonc`: any tool command
(`query`, `edit`, `undo`, `check`, `fix`, `fmt`, `refactor`, `rewrite`,
`explain`, `guide`, `lint`, `same-output`), quoted as in sh, `#`
comments, `< PATH` or `<<WORD` (the lines after it up to a line WORD)
for a command's stdin, as `refactor --script` reads them. It is for the
sequences agents run call after call: `query items` then `query show`,
`show` then `refs`, an edit then `check` or `query show`.

```
$ tachyonc batch < cmds.txt        (query show clamp; query refs clamp --count)
## $ tachyonc query show clamp
// crate::calc::clamp→calc.tach:3-12
...
## $ tachyonc query refs clamp --count
3
```

- Each command runs in turn, in a copy of the process (fork), as it
  would alone: its stdout and stderr together, in the order written,
  after a line `## $ tachyonc ARGS`, then `## exit N` when N is not 0.
  A command without `<` or `<<` reads an empty stdin.
- A command sees what the commands before it wrote (an edit is written
  when its check passes, as alone). Unlike `refactor --script`, the
  commands are not one edit: each edit is checked, written and undone
  on its own.
- A failing command does not end the batch; `--stop` ends it at the
  first. The exit status is the first one that is not 0 (else 0).
- `--root R` is every command's root (`$TACHYON_ROOT` in each).
- The program is read once: the first command parses it and leaves it
  in the cache (above), and each command after it restores it (about
  10 ms on the compiler's source). Loading it in the batch process and
  handing it to the commands would save little more, at the risk of
  state one command leaves for the next; it is not done.
- `error batch.format` (a quote not closed, `<<WORD` without its line
  WORD): nothing runs. `error batch.usage`: the options, a FILE that
  cannot be read, a line that is no tool command (`## exit 2`).

## test: build, run the cases, a summary (0.17)

`tachyonc test [FILTER...] [ROOT.tach]` is the one verification command
(docs/research/applying-to-tachyon.md, item 3): it builds what changed,
runs the tests and ends with a summary whose first line is always the
counts, then only the failing cases, each with a few lines of
difference, within `--budget N` tokens (1,000; `--full`: every failure,
40 lines each, no budget unless given). It never needs `| tail`.

**A program** (ROOT, default `./main.tach`). A case is `tests/NAME.in`
(its stdin; none: empty) with `tests/NAME.out` (the expected stdout) in
ROOT's directory (`--dir DIR`: another), and `tests/NAME.exit`, when
there, the expected exit status (default 0): the agent eval's own
convention, and the one agents write by hand. Output is compared as the
eval grades it: `\r\n` as `\n`, trailing whitespace at the end left out.
The program is built into `.tachyonc/test/prog` next to ROOT when a
`.tach` file under ROOT's directory is newer than the build, or the
compiler or `-O` level differs; each run's stdout and stderr stay there
(`NAME.got`, `NAME.err`). A case may run `--timeout S` seconds (10).

```text
$ tachyonc test --timeout 1
test main.tach: 2 passed, 3 failed (tests/)
FAIL bad: stdout differs at line 2 (3 lines expected, 3 printed)
  - line 2: B
  - line 3: c
  + line 2: b
  + line 3: c
FAIL crash: exit 3 (expected 0)
FAIL hang: no exit after 1 s (--timeout S)
  stderr: stopped by signal 14 (SIGALRM: a time limit)
  stderr: trace, innermost call first:
  stderr:   main.tach:12  main
(outputs: .tachyonc/test/NAME.got, NAME.err)
```

(0.17) The program is built with `--trace` (not with `-O 0`; `--no-trace`
turns it off): a case that crashes or runs out of time shows the first
12 lines of its stderr, the message and the frames, innermost first, each
`FILE:LINE  function`.

A FILTER selects the cases whose name contains it. Without cases, the
build alone (`test main.tach: builds; no tests in tests/ ...`), or one
run on `--input FILE` (`-`: stdin): its exit status, its output within
the budget, its stderr. A build that fails prints `test ROOT: does not
build (N errors)` and the errors, one line each.

**The tachyon tree** (`./compiler/src/main.tach` and `./tests/run.sh`,
no ROOT): `compiler/std/embed.sh` when compiler/std is newer than its
embedding; `target/tachyonc` rebuilt (one build, by
`target/tools/tachyonc` when there; `bootstrap/bootstrap.sh --dev`
checks the fixpoint) when a `.tach` file of compiler/src or compiler/std
is newer; then `tests/run.sh [-O N] FILTER` once per FILTER (none: the
whole suite), its `FAIL` blocks (8 lines each) and totals summarized:

```text
$ target/tachyonc test gvn inline
test gvn inline: 40 passed, 1 failed (tests/run.sh; target/tachyonc rebuilt in 1.9 s; 7.31 s)
FAIL run_gvn_loads:
  stdout mismatch
  ...
```

(0.17) Each failing case is run again with `target/tools/tachyonc`, the
last build whose suite passed (when its bytes differ from
`target/tachyonc`'s; `--against TACHYONC` another, `--against none`
not at all): its block ends with `(new: passes with ...)` or `(fails
with ... too: not from this change)`, and the headline counts both
(`with target/tools/tachyonc: 1 new, 6 failing too`). A failure that
fails before the change too is the environment's or older: no need to
stash the change and rebuild to find out.

A FILTER that matches no case is named in the headline (`no case
matches 'x'`). Exit status: 0 every case passed, 1 a failure or a build
error, 2 a usage error (`test.usage`) or nothing to run (`test.no-root`).
tests/refactor/testcmd.t has a transcript.

## probe, reduce, --trace: what a program does (0.17)

`tachyonc guide debug` is the agent-facing text, with the recipe.

- `tachyonc FILE.tach --trace -o prog` (middle/trace.tach): each
  function of the program's own files keeps a frame on a shadow stack
  (4096 entries, a ring), set at its entry, before each call (the line
  of the expression lowered last, so the line of `v[i]` in a statement
  of several lines) and at each loop header; a failed check (rt.panic,
  std's panic) prints the frames after its message, and SIGINT, SIGALRM,
  SIGTERM and SIGSEGV print them too. Built on the IR after lowering,
  before inlining, so the frames are the source's at every level (with
  -O0: -O1). The cost: about 25% on the compiler's own run time, a
  larger binary (the site strings); none without the flag. Without it,
  a failure is one line, `FILE:LINE:COL: message` (0.18; 0.17 added a
  note on --trace).
- `tachyonc probe FILE:LINE [EXPR...]... [--count FILE:LINE] [--max N]
  [--input FILE] [--timeout S] [-O N] [--root ROOT] [-- ARGS]`
  (tools/probe/): the line's statement found in the front end's tree
  (before it; after a `let`; in a loop's body; at the start of a block
  the line opens); copies of the files with the probes written in, on
  the same lines, passed to the compiler with `--overlay PATH COPY`;
  `check` of the copies with `let _: () = (EXPR);` names each
  expression's type, which picks its printer (Display for numbers and
  bool, quoted `[u8]`, elements of arrays, slices, Option and tuples,
  addresses of pointers, Debug, else a struct's fields, else `<TYPE>`);
  the build (with --trace) is run, and its stderr's `@@probe` lines
  become the report. Counts come from an atexit report, else (stopped)
  from the powers of two each probe announces (`at least N`).
- `tachyonc reduce FILE --until 'CMD' [--out F] [--max-runs N]
  [--timeout S]` (tools/reduce.tach): delta debugging on lines; CMD
  (`sh -c`, `{}` the candidate, which keeps FILE's name in
  `.tachyonc/reduce/`) exits 0 while the failure is there; each run in
  a process group killed after S seconds (5).

Codes: `probe.usage`, `probe.no-root`, `probe.no-file`,
`probe.no-line`, `probe.no-statement`, `probe.expr`, `probe.build`,
`reduce.usage`, `reduce.no-file`, `reduce.not-failing`
(`tachyonc explain CODE`). tests/refactor/debugtools.t has a
transcript; tests/run/trace_*.tach the traces.

## The agent hooks (0.17)

tools/agent-hooks, registered in .claude/settings.json (and per
condition in tools/agent-hooks/settings-eval.json for the agent eval):

- **check-after-edit.py** (PostToolUse): `check --json` after every
  Write or Edit of a `.tach` file, every `tachyonc edit|refactor|fix|
  rewrite|undo` that wrote, and every shell command that writes a `.tach`
  file (`> f.tach`, `tee`, `cp`, `mv`). The root and the compiler are
  the command's own: a Bash line's `cd`s are followed (`cd WORKTREE &&
  tachyonc edit ...` checks WORKTREE). The compiler is
  target/tools/tachyonc, except for a program outside the compiler's
  own source (a test case, an example) when target/tachyonc is newer: a
  compiler just rebuilt from a fixed source checks the programs written
  for the fix (0.17; the tools binary reported the errors the fix had
  removed). After the session's first check
  of a root it reports the delta: `tachyonc check main.tach: 2 errors (1
  new, 1 fixed, 1 as before)` and only the new errors; `0 errors (2
  fixed)` when it became clean; nothing when it was and is clean. After
  a clean check of a program with tests (`tests/*.out`), `tachyonc test
  ROOT --full --timeout 2` runs (not again within 20 s,
  `$TACHYON_TEST_DEBOUNCE`; never again for a program whose tests took
  over 8 s) and its line follows: the counts, the newly failing cases
  with their differences, the fixed ones by name. TACHYON_CHECK_TESTS=0
  leaves the tests out. (0.18.1) Errors whose `try:` is `tachyonc fix
  --suggested` (the compiler gives it only for an exact fix: a
  did-you-mean name with one candidate, a missing `use` or `pub`, a
  conversion) are fixed by the hook: it runs `fix --suggested --json
  ROOT` (one checked, journaled edit), checks again, and prints a head
  line (`tachyonc fix --suggested main.tach, run by the hook (tachyonc
  undo takes it back; ...)`), a `fixed FILE:L:C: MESSAGE | FIX` line per
  error it fixed, then the errors left. A refused fix leaves the report
  as before, with its `try:`; TACHYON_HOOK_FIX=0 turns it off; the
  record says `hook_fixed`. (The 0.18 eval: the `try:` was offered 43
  times and run once.)
- **turn-end.py** (Stop): when a root this session touched (or the
  current directory's) changed since its last clean check and test run,
  `check` (and the tests) once; errors or failures block the stop once,
  with `turn-end: unchecked changes in main.tach: 2 errors` and the
  errors as the reason. Never twice for the same sources.
- **query-first.py** (PreToolUse, PostToolUse on Bash): blocks a shell
  read of `.tach` source, judging each command of a line on its own (in
  the directory its `cd`s lead to, `$VAR`s assigned on the line
  expanded); a whole file under 300 lines is read freely with `cat`,
  `head`, `tail`, `sed -n`; a larger one gets its length and `query items
  MODULE`; a `.tach` file outside any program's module tree (a probe, a
  scratch copy: not a main.tach, not declared by a `mod` line) is not
  source. The blocked record logs the `try:` commands it gave. After a
  call: a `# no-query:` reason asking for line numbers for the Edit tool
  is answered with `edit insert --after NAME` and `query def NAME`; the
  hints of tools/agent-hooks/hints.txt (`repeat-query` after the third
  show, refs, def or callers in a row on related items: one name, a name
  and its type or module, a name the previous answer printed;
  `unfamiliar-construct` from the check hook) are printed as written
  there, each once a session; TACHYON_HINTS=0 turns them off. Every text
  a hook adds is a factual statement with its command, the same words
  every time (no times, no ids: appended text is written to the prompt
  cache once). With TACHYON_QUERY_MODE=rewrite (the eval's `+rewrite`), a
  read whose query is not in doubt runs as that query instead of being
  blocked (PreToolUse `updatedInput`, permission `allow`, and a one-line
  `note hook.query-first: ... ran as ...` beside the result): `sed -n
  'A,Bp' F`, `head -N F`, `tail -n N F` → `query text F:A-B`; `cat F` →
  `query items MODULE`; `grep -n NAME F` (flags among `-nrRwHsI`) →
  `query refs NAME --in F`, else `query grep NAME`. A pipe, several
  files, a regex or another flag is blocked as before; writes always are.
- **lookup-note.py** (PostToolUse on Bash; the eval's `+note`): when a
  `guide`, `query`, `explain` or `--help` call prints the same text as
  the same call earlier in the session, one line: ``note: `tachyonc
  guide std` printed the same text at shell call 4 of this session``, once
  per call. The call runs: an old result may have been cleared from the
  context. TACHYON_LOOKUP_NOTE=0 turns it off.

The hooks keep a small per-session state ($TACHYON_HOOK_STATE, default
$TMPDIR/tachyon-agent-hooks). Measured on an M-series Mac under load
(load average 6 on 12 cores; medians, Python's start included): a Bash
call that changes nothing, 46 ms in the check hook (45 before 0.17) and
60 ms in query-first (as before); the check hook after an edit, 76 ms
(62 before: the state and the fingerprint); with a build and the 10
cases of the eval's 01-wordfreq, 180 ms; the turn-end hook with nothing
to check, 60 ms.

## Known limits

- In a generic function that is never instantiated, the references that
  depend on its type parameters (methods of `T`, through its bounds) are
  missing.
- In a function whose body has a syntax error, the statement holding it
  is left out (and, when the parser lost its place, what follows it);
  in a function with a type error, the references after the error in
  the failing statement or expression may be missing.
- Operator calls are placed at the start of the operation, not at the
  operator.
- `write` is an assignment's target: a method that changes its receiver
  (`V.push(x)`) or a pointer passed on reads it.
- Module references are the `mod` item, `use` and paths (`m::f`), not
  the module's file.
- Items the parser skipped after a syntax error are not defined.
- The C headers' declarations are shown as the compiler writes them out
  (`<C import>`), not as the header has them.

## Tokens

What an agent reads for a typical question, in tokens (bytes / 4), before
(0.11's first `query`) and after (this format), on the compiler's own
source:

| question | before | after |
|---|---|---|
| `refs IntVec::push` (645 references) | 14,790 (every line) | 354 (per-file summary and 3 `try:`) |
| `refs IntVec::push`, one module's (31) | 630 (grep of the above) | 350 (`--in gvn`) |
| `show .name` (20 matches) | 353 | 171 (paths, error, `try:`) |
| `def run_gnv` (no match) | 20 | 24 (with the command that answers) |
| `refs nowhere` on a program with 4 errors | 121 (all the errors) | 85 (count, first error, `try:`) |
| compiling that program | 128 (human) | 108 (`--diagnostics=short`) |

