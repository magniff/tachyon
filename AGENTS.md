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
| where something is used | `target/tachyonc query refs NAME` (`--count`) |
| where it is defined, its signature | `target/tachyonc query def NAME` |
| what a module contains | `target/tachyonc query items MODULE` |

NAME is `foo`, `module::foo`, `Type::method`, `Enum::Variant` or
`Struct.field`. The root defaults to `compiler/src/main.tach` (pass
another root file as the last argument for other programs).

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
