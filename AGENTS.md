# Working on tachyon (for agents)

Tachyon's compiler is written in tachyon: `compiler/src/`, a module tree
under `main.tach`. Releases, the bootstrap chain and the release gate are
in [docs/releases.md](docs/releases.md) and
[docs/roadmap.md](docs/roadmap.md); the language in
[docs/grammar.md](docs/grammar.md).

## Read source through the compiler

Ask `tachyonc` about the program instead of reading files with grep,
sed, head, cat or awk ([docs/query.md](docs/query.md)):

| you want | run |
|---|---|
| the source of a function, type, method | `target/tachyonc query show NAME` |
| where something is used | `target/tachyonc query refs NAME` (`--count`, `--in FILE\|MODULE`) |
| where it is defined, its signature | `target/tachyonc query def NAME` |
| what a module contains | `target/tachyonc query items MODULE` |
| the item at a compiler error's position | `target/tachyonc query show FILE:LINE` (`--with-comments`: its section comment too) |
| a module's `use` lines, header comment, extern blocks | `target/tachyonc query show MODULE::use` (`::header`, `::extern`) |
| change a module's `use` lines or header comment | `target/tachyonc edit patch\|replace MODULE::use` (`MODULE::header`; `edit insert --after MODULE::use`, `edit delete`) |
| lines of any file (a test, a fixture, conflict markers), a small file | `target/tachyonc query text FILE:A-B`, `query show FILE.tach` |
| change a few lines inside an item (a condition, a statement) | `target/tachyonc edit patch NAME\|FILE:LINE --old 'TEXT' --new 'TEXT'` (pairs repeat; several lines: `< pairs`, blocks `<<<<<<< OLD` / `=======` / `>>>>>>> NEW`; `--loose` for other indentation) |
| add statements inside an item | `target/tachyonc edit insert --in NAME --after\|--before 'ANCHOR' < text` |
| replace, add or remove an item by name | `target/tachyonc edit replace NAME < new.tach`, `edit insert --after\|--before NAME`, `edit delete NAME` (`--dry-run` for the diff) |
| see what an edit changed, without reading the file back | `--show` on any edit or refactoring; `target/tachyonc query diff` (the last one) |
| take the last edit back | `target/tachyonc undo` |
| add, remove, rename, reorder or retype a parameter, with every call | `target/tachyonc refactor signature FN --add 'x: i64 = 0'` (`--remove x`, `--rename-param a b`, `--reorder b,a`, `--type x T`) |
| add, remove, rename or retype a field, with every literal and access | `target/tachyonc refactor field STRUCT --add 'g: i64 = 0'` (`--remove g`, `--rename g h`, `--type g T`) |
| add a variant (an arm in each match that needs one), remove, rename one | `target/tachyonc refactor variant ENUM --add 'X(i64)' --arm 'EXPR'` (`--remove V`, `--rename V W`) |
| move lines of a function into a new one, parameters and result computed | `target/tachyonc refactor extract-function FN --lines A-B --to NEW` |
| put a small function's body where it is called (and delete it) | `target/tachyonc refactor inline FN` (`--at FILE:LINE`: one call) |
| replace an idiom everywhere, typed | `target/tachyonc rewrite 'grow($v, $n)' '$v.reserve($n)' --where '$v: *IntVec' --dry-run` |
| rename anything (a module: its file too), with every reference | `target/tachyonc refactor rename PATH NEW` |
| move items to another module, imports and `pub` fixed | `target/tachyonc refactor move PATH... --to MODULE` (`--after\|--before ITEM`: where) |
| make a module; move one (file, folder, paths) | `target/tachyonc refactor new-module crate::a::b`, `refactor move-module crate::a crate::x::a` |
| split a module into files | `target/tachyonc refactor split MODULE --plan` (then `--auto`, or `--into M --items a,b`; `--names a,b`; `--reexport` leaves code outside as it is; `--header TEXT`) |
| several changes, checked once, all or nothing | `target/tachyonc refactor --script steps.txt` (one command per line) |
| the errors, one per line (front end only) | `target/tachyonc check` |
| missing/unused imports, `pub`, `unsafe` blocks | `target/tachyonc fix` (`--only imports,unused,pub,unsafe`, `--in FILE\|MODULE`, `--dry-run`) |
| imports through re-exports, then the re-exports; merged, sorted, wrapped `use` lines | `target/tachyonc fix --only reexports,tidy-imports` (`// api:` above a `pub use` keeps it) |
| prove a refactoring changed no output | `target/tachyonc same-output OLD_TACHYONC` |
| file and item sizes | `target/tachyonc query stats [MODULE\|FILE]` |
| how a module's items use each other, how to split it | `target/tachyonc query deps MODULE --max-lines 1000` |
| what nothing uses | `target/tachyonc query unused [MODULE\|FILE]` |
| what a signature change touches | `target/tachyonc query impact NAME` |
| files over a size | `target/tachyonc lint --max-lines 1000` |

NAME is `foo`, `module::foo`, `Type::method`, `Enum::Variant`,
`Struct.field` or `FILE:LINE`; several in one call. The root defaults to
`compiler/src/main.tach` (`--root ROOT`, or a last argument ending in
`.tach`, for other programs). A problem is one stderr line, `error CODE:
message`, then `try:` lines: commands to run as they are. Compile with
`--diagnostics=short` for one line per error. Edits are atomic: an edit
that adds an error writes nothing and prints the errors
([docs/refactor.md](docs/refactor.md)).

**This is being tested.** A hook (`tools/agent-hooks/query-first.py`)
blocks shell commands that read `.tach` source and suggests the query
that answers them. When the query is not enough, rerun the shell command
with a trailing comment saying why:

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

When any tachyon tool (query, edit, refactor, check, fix, the hook)
falls short, record it in one line:

    tools/agent-feedback "query refs" "misses uses inside never-instantiated generic fns"

## The inner loop

Check and test only what a change touches, and widen at milestones:

- after an edit: `target/tachyonc check` (the front end, one line per
  error) and the cases it concerns, `tests/run.sh FILTER` (cases whose
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
