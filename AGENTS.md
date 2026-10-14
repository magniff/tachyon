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
| the item at a compiler error's position | `target/tachyonc query show FILE:LINE` |
| replace, add or remove an item by name | `target/tachyonc edit replace NAME < new.tach`, `edit insert --after\|--before NAME`, `edit delete NAME` (`--dry-run` for the diff) |
| take the last edit back | `target/tachyonc undo` |
| the errors, one per line (front end only) | `target/tachyonc check` |
| missing/unused imports, `pub`, `unsafe` blocks | `target/tachyonc fix` (`--only imports,unused,pub,unsafe`, `--in FILE\|MODULE`, `--dry-run`) |
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

    sed -n '120,180p' compiler/src/gvn.tach  # no-query: need the comment block above run_gvn, show omits it

The reason is recorded (`.git/agent-tools.jsonl`) and is how the tool
gets better, so be specific: what you needed, and what query gave or
lacked. Editing files (Edit, Write, `sed -i`) is not affected.

When any tachyon tool (query, edit, refactor, check, fix, the hook)
falls short, record it in one line:

    tools/agent-feedback "query refs" "misses uses inside never-instantiated generic fns"

## Conventions

- Commit as `git -c user.name=magniff -c user.email=tinysnippets@gmail.com
  commit -F msgfile`, the message in a file; no attribution trailers.
- A release's compiler is built by the previous release: features new in
  release N are used in `compiler/src` only from N+1.
- No undefined behaviour, no wildcard imports; compile speed is measured
  every release.
