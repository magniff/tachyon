# Reorganizing modules: refactor rename, move, new-module, move-module, split

The module-structure refactorings of 0.11 (phase 2a), for changing how a
program is cut into modules and files without reading or rewriting the
files by hand. Release 0.12 uses them to reorganize the compiler's own
source into folders with no file over 1,000 lines.

```
tachyonc refactor rename PATH NEW [ROOT]
tachyonc refactor move PATH... --to MODULE [--keep-impls] [--no-tidy]     (or: move PATH MODULE)
tachyonc refactor new-module crate::a::b [--file|--dir]
tachyonc refactor move-module crate::a crate::x::b
tachyonc refactor split MODULE --into NEWMOD --items a,b,c [--keep-impls] [--reexport] [--header TEXT]
tachyonc refactor split MODULE --plan|--auto [--max-lines N] [--reexport]
```

Every one is one edit of the edit engine ([refactor.md](refactor.md)):
checked by the front end before anything is written (an edit that adds
an error writes nothing: `error edit.breaks`, the new errors, `try:` with
`--no-check`), journaled for `tachyonc undo` (file moves too), printed as
a zero-context diff with `--dry-run` (a moved file as git's `rename
from`/`rename to`), and summed up in one line:

```
moved 2 items to crate::util→3 files→+15 -14 lines
```

They take the editing options (`--dry-run`, `--no-check`, `--exact`,
`--root ROOT`, `--target T`), and run in `refactor --script` like the
others ([refactor-shape.md](refactor-shape.md)): a script can move
modules, split them and rewrite what it moved, checked once, one undo.
PATH is anything `query` accepts ([query.md](query.md)); MODULE a module
path (`crate::a::b`, or its end when only one module has it).

Exit status: 0 done (or nothing to do: `note edit.unchanged`), 1 refused
(nothing written), 2 usage error.

## rename

`refactor rename PATH NEW`: the definition and every reference the
checker resolved to it get the new name: calls, types, paths, struct
literals and field accesses, method calls, variants, `use` lines (an
alias, `use a::f as g`, keeps its own name). For

- an item (function, type, trait, constant, static, alias): its module
  and every module that imports it by name must not have a NEW already;
- a method: its type must not have a method NEW; a trait impl's function
  is renamed with its trait's function and every impl of it (a trait not
  in the program's files: `edit.not-source`);
- a field or a variant: its struct or enum must not have one NEW;
- a module: its parent must not have a NEW, and its file is renamed
  (`a.tach` -> `NEW.tach`, `a/` with it; `a/mod.tach`: the directory).

Mentions in comments between backquotes, `` `old` ``, `` `m::old` ``,
`` `old()` ``, are renamed too when no other definition is named old.

A name taken is `error refactor.collision: 'NEW' is already a name in
MODULE (KIND PATH)`, `try:` the query that shows it.

## move

`refactor move PATH... --to MODULE` moves items (functions, types,
traits, constants, statics, aliases, extern functions) into another
module, all in one edit. What moves with an item, and what is fixed:

**Its text.** The item's lines, from the comment and attribute lines
directly above it (no blank line between) to its last line, with a
comment after it on that line. Comments elsewhere stay, with one
exception:

**Banners.** A banner is a block of comment lines with a blank line
after it, after some code in the file (a comment at the top of a file
is the file's, and never moves): `// ---- Scaling ----`. It heads the
items after it, up to the next banner: its group. It goes (0.12) where
most of its group's lines go: above the first item of the group that
goes there, with one blank line after it; it stays when most of them
stay.

**Impl blocks.** A type's impl blocks in its module move with it: its
inherent impls and its trait impls (`--keep-impls` leaves them). A
trait's impls in its module move with it when their type is not an item
of that module (`impl Tr for i64`); an impl of a moved trait for a type
that stays, stays with the type. A method never moves alone
(`refactor.not-movable`: move its type).

**Extern functions.** A function of an `extern "C" { }` block moves into
an `extern "C" { }` block of its own in the new module; the whole block
moves when all its functions do.

**Where it goes.** At the end of the module's file; into a new module's
file after its imports. Items that were next to each other (no blank
line between: a run of constants) stay so (0.12); the others get a
blank line before them.

**A new file's header (0.12).** A module that `split` makes starts with
a header comment: `--header TEXT` (with `--into`), else the banner its
first item comes with (moved to the top, its rules dropped: `// ----
Scaling ----` is `// Scaling`), else a copy of the banner above that
item where it was. No banner, no header.

**Tidy imports (0.12).** Then the files the move edited and made get
their `use` lines tidied, as `fix --only tidy-imports` does
([refactor.md](refactor.md)): a name added to a `use` of the same path
is merged into it, the lists are sorted and wrapped at 100 columns
(`--no-tidy`: as the move wrote them). This is a round of `fix` on the
edited program, before the check.

**References.** Every reference the checker resolved, in every module:

- a path naming the item (`m::f`, `crate::m::f`, `super::f`) is written
  from `crate`: `crate::new::f`;
- a `use` importing it: when all its names move to one module, its path
  becomes that module's (`use crate::new::f;`); else the name leaves it
  for a `use` line of its own; in the module it moves to, the import is
  dropped (the item is local there);
- code that named it bare (its old module's) gets a `use` line;
- the moved code gets the imports it needs: what its old module imported
  that it names, and its old module's items it names (`use
  crate::old::helper;`); `super::` and `self::` paths in it are written
  from `crate`;
- an item used from where it is private becomes `pub` (an item moved
  out of reach of its users, a helper of the old module the moved code
  calls), and so does a `mod` line on the way;
- the imports of the old module that nothing there names any more are
  removed (the ones that were used before).

New `use` lines go after the module's last `use` (else before its first
item), one per module path, its names sorted, wrapped at 100 columns.
Nothing outside the edited ranges changes, byte for byte, but the `use`
lines of the files edited, tidied (above). A `mod` line and imports added
at one place: the `mod` line first (0.12).

Refused, nothing written: a name the item would take that is taken
there (`refactor.collision`), a method or a field (`refactor.not-movable`),
an inline module (`refactor.inline`), a module that does not exist
(`refactor.no-module`, `try: refactor new-module MODULE`).

## new-module, move-module

`refactor new-module crate::a::b`: makes `b`'s file, empty, and its
`mod b;` line in `a` (after `a`'s last `mod` line, else before its first
item). `--dir` makes it a dir module (`b/mod.tach`). The modules of the
path that do not exist are made too, as dir modules. A file module that
gains a child becomes a dir module: `a.tach` is moved to `a/mod.tach`
(its children were in `a/` already). A module that exists:
`refactor.exists`; a name taken: `refactor.collision`.

`refactor move-module crate::a crate::x::b`: module `a`, its file (or
directory) and its children's files, becomes `crate::x::b` (renamed, if
`b` is not `a`). Its `mod` line (with its comments) moves to its new
parent, `pub` when code outside the new parent uses it; the parents
that do not exist are made, and a file module parent becomes a dir
module. Every path naming it is written from `crate` (`crate::x::b::f`),
a `use` of it gets its new path (`as a` when its name changes), and the
`super::` paths of its files that lead out of it are written from
`crate`. Within one parent it is a rename (the name, where it is
written).

## split

`refactor split MODULE --into NEWMOD --items a,b,c`: `move` of the items
(names in MODULE, or paths) to NEWMOD, made when it does not exist: a
child (`crate::m::part`) makes MODULE a dir module (`m.tach` ->
`m/mod.tach`, `m/part.tach`).

`--reexport` (0.12) keeps MODULE's interface: code outside MODULE is
left as it is, and MODULE re-exports its parts' items that code outside
uses, with what it uses of them itself: `pub use part::{a, b};`, one
line per part (an item made `pub` when it was not; the `mod part;` line
stays private). For splits that must not touch other files (parallel
agents each splitting one module); `fix --only reexports` removes such
re-exports later.

`--plan [--max-lines N]` (1000): the split of MODULE into parts of at
most N lines, as the commands that make it, one per line, to run in
order (or edit first):

```
# crate::check→4785 lines→8 parts of at most 1000 lines
tachyonc refactor split crate::check --into crate::check::index --items SCOPES,type_error,...
...
note refactor.plan: the same in one edit: --auto
try: tachyonc refactor split crate::check --auto --max-lines 1000
```

The parts come from `query deps`'s clustering (average linkage, then
packing: [refactor.md](refactor.md), query deps) on MODULE's items, an
impl block counted with its type (or its trait), at most N lines less
what stays in MODULE (its comments, imports, `mod` lines, extern blocks,
impls of other types) and 20 for the imports. The part most used from
other modules stays in MODULE; each other one becomes a child module,
named after the word of its items' names most its own (`check::local`,
`regalloc::live`; not a name MODULE has; `partK` else) — `refactor
rename` renames it after. `--auto` makes the plan in one edit. A module
of at most N lines: `note refactor.fits`.

## In a script

A `refactor --script` step that moves files lists them (`gone PATH`
besides `file` and `new`): the steps after it read the program without
them, and the script's one edit removes them. One check, one `undo`:

```
refactor move-module crate::shapes crate::figures::shapes
rewrite 'scale() * $e' '$e * scale()'
refactor split crate::geom --into crate::geom::scaling --items scale,half,double
```

## The engine

`edit_move_file(f, PATH)` (edit.tach): file f, with its edits, becomes
PATH: a new file and a removed one. The check reads the new file's copy
and the removed file as missing (an overlay with no file), the journal
keeps the removed file's text (undo writes it back and removes the new
file and the directories it made), the diff is git's rename.
`edit_remove_file(PATH)` removes one (a script's step moved it).

## Dress rehearsal

On a copy of the compiler's source (0.11, 61 files, 60,000 lines), `split
--auto --max-lines 1000` of each of the 23 files over 1000 lines took 3
seconds in all; every split passed the check, `lint --max-lines 1000`
found no file over, the copy built with target/tachyonc, and
`same-output` against target/tachyonc was identical (3375 compilations).

## Known limits

- References are what the checker resolved: a generic function never
  instantiated has none (its code is not checked), so moving what only
  it uses may leave an error the check then refuses.
- Inline modules (`mod m { }`) are not moved into or out of.
- A module moved back leaves the dir module made for it on the way.
- Paths written from `crate` are long (0.12: imports are tidied, merged
  into a `use` of the same path, but `use crate::a::b::f` and `use
  b::f` are two paths).
- Names of `--plan`'s parts are guesses: rename them.
