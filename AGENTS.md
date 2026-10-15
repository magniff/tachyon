# Working on tachyon (for agents)

Tachyon's compiler is written in tachyon: `compiler/src/`, a module tree
under `main.tach`. Releases, the bootstrap chain and the release gate are
in [docs/releases.md](docs/releases.md) and
[docs/roadmap.md](docs/roadmap.md); the language in
[docs/grammar.md](docs/grammar.md).

**New to tachyon? Run `target/tachyonc guide` first**: the language in
about 2k tokens, for a reader who knows Rust (where it looks like Rust
and means something else, std's most used items, the first errors and
their fixes). Before using a construct you are unsure of, fetch the
lines on it: `target/tachyonc guide --find WORDS` or `guide
TOPIC#SECTION` (`guide --list`: the topics; `guide --full`: the long
form). The text is `compiler/guide/*.md`; every example in it is
compiled and run by `tests/run.sh guide`.

## Read source through the compiler

The compiler answers questions about the program and makes checked
edits; `tachyonc check` runs by itself after every edit (the hook,
below). **For an unfamiliar item, run `target/tachyonc query context
NAME` first**: its source, the signatures of what it calls and its
callers, in one call (`target/tachyonc query context run_gvn`). Use
these first:

| you want | run |
|---|---|
| an unfamiliar item: its source, callers and what it calls, in one call | `target/tachyonc query context NAME` (replaces show + refs + def) |
| the source of an item; a whole small file | `target/tachyonc query show NAME`; `query show FILE.tach` (a file under 300 lines is cheaper read whole) |
| every use of a name | `target/tachyonc query refs NAME` (`--count`, `--in FILE`) |
| change a few lines of an item, checked | `target/tachyonc edit patch NAME --old 'TEXT' --new 'TEXT'` |
| replace, add, remove an item | `target/tachyonc edit replace\|insert\|delete NAME` (`< text`) |
| rename, move, change a signature, field or variant everywhere | `target/tachyonc refactor rename\|move\|signature\|field\|variant ...` |
| missing imports, `pub`, `unsafe` blocks | `target/tachyonc fix` |
| a bug: where it fails, the values at a line, which change broke a test | `target/tachyonc guide debug` (`test` prints a crash's line and callers; `probe FILE:LINE EXPR... -- ARGS`; `reduce`) |
| build and test what a change touches | `bootstrap/bootstrap.sh --dev`, `tests/run.sh FILTER` (the inner loop, below) |

Everything else (`query grep|items|type|effects|impact`, `edit apply`,
`rewrite`, `refactor extract-function|inline|split`, `batch`, `undo`):
`target/tachyonc --help`, `target/tachyonc CMD --help`, `target/tachyonc
guide tools`, or `explain CODE` on any error; adding a std function, a
pass, a diagnostic: `target/tachyonc guide how`. Every command in one
table: [docs/query.md](docs/query.md#every-command-at-a-glance-for-agents);
the edits in [docs/refactor.md](docs/refactor.md). NAME is `foo`,
`module::foo`, `Type::method`, `Struct.field` or `FILE:LINE`; a problem
is one line, `error CODE: message`, then `try:` lines to run as they are.

**Query and edit with `target/tools/tachyonc` while you change the
compiler**: `bootstrap/bootstrap.sh --dev` copies its build there only
after the fixpoint and the suite pass, so it always works (your own
builds replace `target/tachyonc`, and a broken one breaks `query`).

**Hooks.** `tools/agent-hooks/query-first.py` blocks shell commands that
read or rewrite `.tach` source (grep, sed, `sed -i`, Python writing
compiler/src) and suggests the query or `edit patch`; a `.tach` under
`tests/`, or a whole file under 300 lines, is read freely. When the tool
is not enough, rerun with a trailing reason, which is recorded: `#
no-query: need the comment above run_gvn, show omits it` (or `# no-tool:
...` for an edit). `check-after-edit.py` runs `tachyonc check` after
every Write/Edit of a `.tach` file and every writing `tachyonc` command:
what changed since the last check (new errors, how many fixed) is added
to that call's result; nothing added means no change, so do not run
`check` after an edit. `turn-end.py` checks once more when you stop and
blocks the stop once if errors are left. When a tool falls short, record
it in one line: `tools/agent-feedback "query refs" "misses uses inside
never-instantiated generic fns"`.

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
