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
tachyonc query items [MODULE...] [--root ROOT] [--comments]
tachyonc query show MODULE::section TITLE                   (0.13)
tachyonc query grep PATTERN... [--in FILE|MODULE|ITEM] [--code] [--comments] [--strings] [--word] [--count] [--limit N] [--all]
tachyonc query type FILE:LINE[:COL]...                      (0.13)
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

## Output formats

One line of grammar per kind of line (`\t` is a TAB; `[...]` optional):

| command | line | grammar |
|---|---|---|
| def | definition | `PATH \t FILE:LINE:COL \t KIND \t SIGNATURE [\t effects: SET]` |
| show | header | `// PATH \t FILE:FIRST-LAST [\t effects: SET]`, then the source lines, verbatim |
| effects (0.16) | function | `PATH \t SET`, then with `--why` its chain, indented two spaces |
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

