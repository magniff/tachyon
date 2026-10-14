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
tachyonc query def NAME [ROOT] [--exact]
tachyonc query show NAME [ROOT] [--exact]
tachyonc query refs NAME [ROOT] [--exact] [--count] [--in FILE|MODULE] [--limit N] [--all]
tachyonc query callers NAME [ROOT] [--exact] [--count] [--in FILE|MODULE] [--limit N] [--all]
tachyonc query items [MODULE] [ROOT]
tachyonc query --help
```

`ROOT` is the program's root file. Without it: `$TACHYON_ROOT`, else
`./main.tach`, else `./compiler/src/main.tach`. Positions are
`file:line:col`, 1-based, with the file as the module loader names it
(relative to the current directory when ROOT is).

Exit status: 0 answered, 1 no answer (nothing matches, an ambiguous
`show`, a program that could not be read), 2 usage error (or no root).

## Output formats

One line of grammar per kind of line (`\t` is a TAB; `[...]` optional):

| command | line | grammar |
|---|---|---|
| def | definition | `PATH \t FILE:LINE:COL \t KIND \t SIGNATURE` |
| show | header | `// PATH \t FILE:FIRST-LAST`, then the source lines, verbatim |
| show, > 5 matches | path | `PATH` (stdout), then `error query.ambiguous` |
| refs, callers | file header | `# FILE` |
| refs, callers | reference | `LINE:COL \t (def \| ENCLOSING) [\t ->TARGET] \t SOURCE` |
| refs, callers, > 60 | summary | `FILE \t COUNT`, then `note query.truncated` |
| refs, callers `--count` | count | `COUNT`, or `COUNT \t PATH` per definition when several match |
| items MODULE | module header | `# PATH \t FILE` |
| items MODULE | item | `LINE \t KIND \t SIGNATURE` |
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
| item of a module (a file, or an inline `mod m { }`) | `crate::gvn::run_gvn`, `crate::sys::SockaddrIn` |
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
- Import aliases are not definitions: `use a::f as g;` makes `g` a
  reference to `crate::a::f`, but `query def g` finds nothing
  (`error query.alias`, with `try:` the same query of what `g` imports).
- No match: exit 1, `error query.no-match`, and a `try:` line for each of
  the (at most 3) definitions whose names are nearest to NAME's last
  segment (edit distance at most a third of its length).

## def

One line per matching definition (shown here with the TABs as `→`):

```
crate::gvn::run_gvn→compiler/src/gvn.tach:721:8→fn→pub fn run_gvn(fi: i64) -> bool
```

The position is the name's. The signature is the source up to the body
or the `{`, its whitespace collapsed, with `pub` when the item is public;
a long constant's value is cut to `...`.

## show

Each matching definition's exact source: a header, then whole lines from
the comments and attributes directly above it through its end.

```
// crate::gvn::run_gvn→compiler/src/gvn.tach:721-796
pub fn run_gvn(fi: i64) -> bool {
    ...
}
```

A struct or enum shows its whole declaration (not its impl blocks);
`Type::method` shows the method. When more than 5 definitions match,
`show` prints only their paths, one per line, and fails (exit 1) with
`error query.ambiguous` and a `try:` line showing the first.

## refs and callers

Every resolved reference, one per line, under a header per file:

```
# compiler/src/gvn.tach
721:8→def→pub fn run_gvn(fi: i64) -> bool {
# compiler/src/opt.tach
17:17→opt→use crate::gvn::run_gvn;
533:13→opt::simplify_function→run_gvn(fi);
```

ENCLOSING (the second field) is the innermost definition holding the
reference (a function, or the struct, constant, trait... whose
declaration it is in), else the module (a `use`, an `impl` header), by
its short path. The definition itself is the line marked `def`.

References are what the compiler resolved, never text: calls, functions
used as values, constants and statics, types (in signatures, fields,
casts, `impl` headers, struct literals, patterns, paths `T::f`), field
accesses and the fields of struct literals, variants (constructed or
matched), method calls (resolved through the receiver's type, and
through a bound's impl in generic code), operator calls of trait impls
(`a + b` calls `<T as Add>::add`; at the start of the operation),
module paths, and `use` imports. A local that shadows a function,
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
  listed once per position (and target).
- `--count` prints the number of references refs would print (the
  definition included); for several definitions, `N→PATH` per definition.
- `callers` is `refs` restricted to calls (method and operator calls
  included; no definition line).
- `--in FILE|MODULE` keeps the references in a file (an argument with a
  `/`, ending in `.tach` or `<std>`: the path, or its end by whole
  components, `gvn.tach`) or a module (matched like NAME, its inline
  modules included: `gvn`, `crate::ir`).
- None left: `note query.empty: 0 refs` (exit 0).

### The budget

More than 60 references (after `--in`) are not listed: refs prints how
many each file has, and how to narrow the question:

```
compiler/src/abi.tach→10
...
compiler/src/vectorize.tach→60
note query.truncated: 645 refs in 44 files
try: target/tachyonc query refs IntVec::push --in compiler/src/vectorize.tach
try: target/tachyonc query refs IntVec::push --limit 60
try: target/tachyonc query refs IntVec::push --all
```

(the `--in` suggestion is the file with the most). `--limit N` lists the
first N, then `note query.truncated: showing N of M refs`; `--all` lists
everything.

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
| `query.no-match` | error | 1 | no definition (or module, for items) answers to NAME | the nearest definitions by edit distance (the same command with their paths); else the items of the module NAME names, or the module tree |
| `query.alias` | error | 1 | NAME is the other name an import gives (`use a::f as g;`), not a definition | the same command with what it imports |
| `query.ambiguous` | error | 1 | `show` matches more than 5 definitions (their paths on stdout) | `show` of the first |
| `query.truncated` | note | 0 | refs/callers past the budget, or cut by `--limit` | `--in` the file with the most, `--limit 60`, `--all` |
| `query.empty` | note | 0 | refs/callers found nothing (after `--in`) | |
| `query.bad-in` | error | 1 | `--in` names no file or module of the program | the command without `--in` |
| `query.program-errors` | warning | (the answer's) | the program has errors: their number, and the first one when nothing answered | the compilation that lists them all, one per line |
| `query.program-errors` | error | 1 | the program could not be parsed at all | the same |
| `query.no-root` | error | 2 | no ROOT, no `$TACHYON_ROOT`, no `./main.tach` or `./compiler/src/main.tach` | the command with a root |
| `query.bad-root` | error | 2 | ROOT cannot be read | the command without it, when a default root exists |
| `query.usage` | error | 2 | no command, an unknown command or option, a missing NAME or option value, an extra argument | the command corrected (the nearest command, the option dropped, `--limit 60`), or `items` |

```
error query.no-match: no definition 'run_gnv'
try: target/tachyonc query def crate::gvn::run_gvn
error query.alias: 'MyVec' is an import alias in crate
try: target/tachyonc query refs crate::myvec::Vec
error query.no-root: no root (TACHYON_ROOT, ./main.tach, ./compiler/src/main.tach)
try: target/tachyonc query def main path/to/main.tach
warning query.program-errors: 4 errors in the program; results may be incomplete
try: target/tachyonc --diagnostics=short broken/main.tach -c -o /dev/null
```

## Programs with errors

The query runs the front end as a compilation would, with its error
recovery, and answers from what it got: definitions come from the parsed
program, references from what the checker resolved. The errors are never
listed: `warning query.program-errors` counts them, names the first when
nothing answered, and gives the compilation that prints them all with
`--diagnostics=short` (one line each:
`FILE:LINE:COL: error[KIND] MESSAGE | help: ...`).

## Known limits

- A generic function that is never instantiated is never checked: the
  references in its body are missing (its definition is found).
- A function whose body has a syntax error is not checked (no references
  in it); in a function with a type error, the references after the
  error in the failing statement or expression may be missing.
- Operator calls are placed at the start of the operation, not at the
  operator.
- `Self` in a struct literal or a type is not a reference to the type.
- Import aliases (`use a::f as g`) are not names of definitions;
  module references are the `mod` item, `use` and paths (`m::f`), not
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

