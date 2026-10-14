# Reorganizing modules: refactor rename, move, new-module, move-module, split

The module-structure refactorings of 0.11 (phase 2a), for changing how a
program is cut into modules and files without reading or rewriting the
files by hand. Release 0.12 uses them to reorganize the compiler's own
source into folders with no file over 1,000 lines.

```
tachyonc refactor rename PATH NEW [ROOT]
tachyonc refactor move PATH... --to MODULE [--after ITEM|--before ITEM] [--keep-impls] [--no-tidy]
tachyonc refactor new-module crate::a::b [--file|--dir]
tachyonc refactor move-module crate::a crate::x::b
tachyonc refactor split MODULE --into NEWMOD --items a,b,c [--keep-impls] [--reexport] [--header TEXT]
tachyonc refactor split MODULE --plan|--auto [--max-lines N] [--names a,b] [--reexport]
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

PATH may be `FILE:LINE:COL` (0.14, as a compiler error has it): the
local there (below), else the definition referred to or defined at
that column (`edit.not-source` for one of std), else the innermost item
holding the line.

A local variable or parameter (0.14) is named by `FILE:LINE:COL` (its
declaration or any use) or `FN::name` (`main::x`, `Catalog::add::qty`).
What is renamed is the local the checker resolved: its declaration and
every use, in each instance of a generic function too; a local of the
same name that it shadows, or that shadows it, keeps its name
(`FN::name` naming several is `error refactor.ambiguous-local`, `try:`
each by its position). Refused (`refactor.collision`) when NEW is
already a name in its scope: another local declared there, or a name
used there that is not this local. `self` keeps its name.

Mentions in comments are renamed only between backquotes on `//`
lines, never other words, and only in these forms:

- an item: `` `old` ``, `` `m::old` ``, `` `old()` ``, when no other
  definition is named old; a bare `` `old` `` is left alone inside a
  function that has a local or parameter named old, and in the comment
  above it (it may mean that local);
- a field, variant or method (here and in `refactor field|variant
  --rename`): `` `Owner.old` ``, `` `Owner::old` ``, `` `Owner::old()` ``,
  `` `m::Owner::old` ``, Owner its struct, enum, trait or impl type;
  never a bare `` `old` `` (a parameter of that name is as likely);
- a local: `` `old` `` in its scope; for a parameter, its function and
  the comment above it.

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
items after it, up to the next banner: its group. It goes with its
group, above it (0.13: with all of it, so that a move and the move back
leave it where it was; into a new module, the part `split` makes, with
the item right under it and most of the group's lines). It stays when
the group does not all go, and with `--after`/`--before` unless the
place ends a group (an item followed by a banner, or by nothing): it
would head the items after it there.

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
file after its imports; with `--after ITEM` or `--before ITEM` (0.13),
next to that item of the module (`refactor.anchor` when it has none of
that name with lines of its own). Items that had only blank lines
between them keep them, as many as there were (0.13; 0.12: a run of
constants stayed one); the others get a blank line before them.

**Blank lines (0.13).** The moved lines go with the blank lines on one
side: the ones after them stay, for what follows; the ones before them
when they start a run of one-line items of their kind (constants,
statics) that goes on after them, or follow a `use` line, a banner or
the file's start. Lines that were inside a run of another kind leave it
joined, as the run is written there. Where they go, the blank lines
there stay with what follows, and they get one blank line before them,
or join a run of their kind as it is written there (from its items
next to each other: none, or as many as the file has). A banner that
heads nothing (its items moved out) takes items put `--after` the item
before it. So a move and the move back, `--after` the item that was
before (or `--before` the one after, for the first item of a banner's
group), leave every file byte for byte as it was:
`tests/refactor/roundtrip.sh` checks it on random items (40 in the
suite; `-n 1000` for more). Not restored: a gap above an item larger
than the one below it (two blank lines, then one).

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
# crate::middle::gvn→932 lines→6 parts of at most 300 lines
# stays in crate::middle::gvn: the part most used from other modules
# walk: banner '// ---- The walk ----': 1 of 8 items, 87 of 142 lines
tachyonc refactor split crate::middle::gvn --into crate::middle::gvn::walk --items DOM_START,...
# memory_values: banner '// ---- Memory values ----': 5 of 6 items, 136 of 141 lines
tachyonc refactor split crate::middle::gvn --into crate::middle::gvn::memory_values --items copy_src,...
...
note refactor.plan: the same in one edit: --auto (other names: --names a,b)
try: tachyonc refactor split crate::middle::gvn --auto --max-lines 300
```

The parts come from `query deps`'s clustering (average linkage, then
packing: [refactor.md](refactor.md), query deps) on MODULE's items, an
impl block counted with its type (or its trait), at most N lines less
what stays in MODULE (its comments, imports, `mod` lines, extern blocks,
impls of other types) and 20 for the imports. The part most used from
other modules stays in MODULE; each other one becomes a child module,
named (0.13) after what its items share, the reason on the line above
its command:

- `banner`: the banner most of its lines are under, its first two words
  (`// ---- Pattern matching ----`: `pattern_matching`);
- `type`: the type most of its lines operate on, a struct, enum or trait
  of the part (with its impl blocks) or the type of its functions' first
  parameter (`*Liveness`: `liveness`), not a general one (used in more
  than a quarter of the program's modules: `IntVec`);
- `prefix`, `suffix`: the first or last word most of its items' names
  have (`emit_`, `_imports`), of two items or more.

The candidate covering the most lines wins (a third of them at least;
on a tie, in that order), when it is not a name MODULE has nor one a part
took: the parts that name best are named first. Else `partK`, said so.
`--names a,b` gives the names, in the order of the plan's parts (fewer:
the others are found; more: `refactor.usage`; a name taken:
`refactor.collision`). `--auto` makes the plan in one edit. A module of
at most N lines: `note refactor.fits`.

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
