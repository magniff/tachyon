# Working on tachyon (for agents)

Tachyon's compiler is written in tachyon: `compiler/src/`, a module tree
under `main.tach`. Releases, the bootstrap chain and the release gate are
in [docs/releases.md](docs/releases.md) and
[docs/roadmap.md](docs/roadmap.md); the language in
[docs/grammar.md](docs/grammar.md).

**New to tachyon? Run `target/tachyonc guide` first**: the language in
about 5k tokens, for a reader who knows Rust (what differs, std's API,
the first errors and their fixes, the tools); `guide --list` lists the
topics (`guide errors`, `guide std`, `guide unsafe`, ...). Its text is
`compiler/guide/*.md`; every example in it is compiled and run by
`tests/run.sh guide`.

## Read source through the compiler

Ask `tachyonc` about the program instead of reading files with grep,
sed, head, cat or awk ([docs/query.md](docs/query.md)):

| you want | run |
|---|---|
| an item with what it calls, its types and callers, in one answer | `target/tachyonc query context NAME` (`--budget N`; a MODULE: its items and central bodies) |
| the source of a function, type, method | `target/tachyonc query show NAME` |
| where something is used | `target/tachyonc query refs NAME` (`--count`, `--in FILE\|MODULE`, `--kind write,call,...`; a local: `FN::x` or `FILE:LINE:COL`) |
| what a function calls, all it reaches; can it change a table | `target/tachyonc query callees FN` (`--transitive`; `--writes TABLE`: the writes and borrows it reaches, with the call chain) |
| text that is not a name (a message, a comment), with its item | `target/tachyonc query grep TEXT` (`--comments`, `--strings`, `--code`, `--word`, `--in`) |
| a module's section banners; one section | `target/tachyonc query items MODULE --comments`, `query show MODULE::section TITLE` |
| the type of an expression | `target/tachyonc query type FILE:LINE:COL` |
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
| replace an idiom everywhere, typed | `target/tachyonc rewrite 'grow($v, $n)' '$v.reserve($n)' --where '$v: *IntVec' --dry-run` (`--list`: the sites and their holes; `--subst 'P' 'R'`: inside the holes' code; `--where '$v: name ~ RE'`; `--in FN\|MODULE\|FILE`, repeated) |
| rename anything (a module: its file too), with every reference | `target/tachyonc refactor rename PATH NEW` (a local or parameter: `FILE:LINE:COL` or `FN::x`, shadowing respected) |
| move items to another module, imports and `pub` fixed | `target/tachyonc refactor move PATH... --to MODULE` (`--after\|--before ITEM`: where; a MODULE that does not exist is made) |
| make a module; move one (file, folder, paths) | `target/tachyonc refactor new-module crate::a::b`, `refactor move-module crate::a crate::x::a` |
| split a module into files | `target/tachyonc refactor split MODULE --plan` (then `--auto`, or `--into M --items a,b`; `--names a,b`; `--reexport` leaves code outside as it is; `--header TEXT`) |
| several changes, checked once, all or nothing | `target/tachyonc refactor --script steps.txt` (one command per line; `<<END` ... `END` gives one its stdin) |
| several queries and edits in one call, outputs under `## $ tachyonc ARGS` lines | `target/tachyonc batch < cmds.txt` (one command per line; `--stop` at the first failure) |
| the errors, one per line (front end only) | `target/tachyonc check` |
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
writes nothing and prints the errors ([docs/refactor.md](docs/refactor.md)).
`--json` on any command prints JSON lines, for scripts and hooks
([docs/query.md](docs/query.md), "JSON").

**Query and edit with `target/tools/tachyonc` while you change the
compiler.** Your own builds replace `target/tachyonc` (and a broken one
breaks `query`); `bootstrap/bootstrap.sh --dev` copies its compiler to
`target/tools/tachyonc` only after the fixpoint and the test suite
pass, so that one always works and knows the newest syntax that passed.
Use it instead of copies such as `T=target/tc0; $T query ...`. The
commands below say `target/tachyonc`; either works when the tree is
healthy.

**This is being tested.** A hook (`tools/agent-hooks/query-first.py`)
blocks shell commands that read `.tach` source (the compiler's,
compiler/src and compiler/std, and any program being worked on:
examples/, bench/, a `.tach` elsewhere) and suggests the query that
answers them. Test data is read freely: a `.tach` under a `tests/`
directory (a case, a refactoring fixture, an agent-eval task's
program) is not blocked, only logged. When the query is not enough,
rerun the shell command with a trailing comment saying why:

    sed -n '120,180p' compiler/src/middle/gvn.tach  # no-query: need the comment block above run_gvn, show omits it

The reason is recorded (`.git/agent-tools.jsonl`) and is how the tool
gets better, so be specific: what you needed, and what query gave or
lacked.

Edits go through `tachyonc edit` too: the hook also blocks shell
rewrites of compiler source (`sed -i`, `perl -pi`, Python writing a
`.tach` file under compiler/src or compiler/std) and suggests the `edit
patch` that does the same, checked and undoable. When the tools cannot
make the edit, append `# no-tool: <what the tools could not do>`. The
Edit and Write tools, test fixtures and docs are not affected.

**Checks come by themselves.** A second hook
(`tools/agent-hooks/check-after-edit.py`) runs `tachyonc check` after
every Write, Edit or MultiEdit of a `.tach` file and after every
`tachyonc edit|refactor|fix|rewrite|undo` that wrote: the program's
errors, at most 10, one line each, are added to that call's result.
Nothing added means the program checks clean: do not run `check` after
an edit. (The root is compiler/src/main.tach for the compiler's source,
else the nearest main.tach; the compiler is `target/tools/tachyonc`
when it exists.)

When any tachyon tool (query, edit, refactor, check, fix, the hooks)
falls short, record it in one line:

    tools/agent-feedback "query refs" "misses uses inside never-instantiated generic fns"

## The inner loop

Check and test only what a change touches, and widen at milestones:

- in a fresh git worktree, `bootstrap/bootstrap.sh --dev` builds
  `target/tachyonc` in about 20 s: the releases come from the main
  checkout's cache, only HEAD is built; when its suite passes it is also
  `target/tools/tachyonc`, the binary to query and edit with;

- after an edit: the check hook's errors (or `target/tachyonc check`
  when the hook is not there) and the cases it concerns, `tests/run.sh FILTER` (cases whose
  name contains FILTER; `-O 0` for another level);
- the whole suite (`tests/run.sh`) only at milestones;
- before committing a big change: `bootstrap/gate.sh --quick` (the chain
  from the working tree, the suite at -O2, a short fuzz in every mode, a
  few minutes; one table at the end);
- a release: `bootstrap/gate.sh --release`, then `gate.sh --only bench`
  on an idle machine ([docs/releases.md](docs/releases.md), "The gate").

## Conventions

- Commit as `git -c user.name=magniff -c user.email=tinysnippets@gmail.com
  commit -F msgfile`, the message in a file; no attribution trailers.
- A release's compiler is built by the previous release: features new in
  release N are used in `compiler/src` only from N+1.
- No undefined behaviour, no wildcard imports; compile speed is measured
  every release.
