# 17. The tools, and working with an agent

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

Use the compiler as a tool for reading and changing code, by hand and
with an AI assistant. By the end the reader can:

- ask the compiler about a program by name: `query context`, `show`,
  `refs`, `callers`, `effects`, `own`, `views`;
- make checked edits (`edit patch`, `edit replace`) and refactorings
  (`refactor rename`, `signature`, `field`, `variant`, `move`), and take
  one back with `undo`;
- fix errors with `volec fix` and `fix --suggested`; format with `volec
  fmt`;
- use the editor integration (`volec lsp`);
- set up a vole project so an AI agent works well in it, and know what
  the agent will use.

## Running example

The word counter from chapters 7 and 11, about 150 lines in three
files. Every command is a console block run on it, so its output is
checked. Sessions: explore it (`query context`), rename a function
everywhere, add a parameter with a default to every call (`refactor
signature --add`), add an enum variant and its match arms (`refactor
variant`), make a planted error go away with `fix --suggested`, and
`undo`. examples/tools has eight tested walkthroughs to borrow from.

## Sections

1. **Why the compiler answers questions.** Names are resolved by the
   compiler, so a query sees through imports and ignores comments and
   strings; that's more precise than text search. Vole was designed so
   the toolchain can be driven from a shell, by people and agents.
2. **Reading.** `query context NAME` (source, what it calls, its
   callers, in one call), `query show`, `query refs --count`, `query
   callers`, `query items MODULE`, `query effects --why`, `query own
   FILE:LINE:COL`. NAME forms: `f`, `module::f`, `Type::method`,
   `Struct.field`, `FILE:LINE`.
3. **Checked edits.** `edit patch NAME --old --new`; an edit that adds an
   error writes nothing and shows the errors; `--dry-run`; `undo`.
4. **Refactoring.** `rename`, `signature` (`--add 'x: i64 = 0'`,
   `--convention v inout` rewrites the calls to `&v`), `field`,
   `variant --arm`, `move --to`, `rewrite 'old($a)' 'new($a)'`.
5. **Fixing.** `volec fix` (imports, unused, pub, unsafe), `fix
   --suggested` (the errors' exact fixes, as one checked edit), the
   migrations (`--only conventions`, `alloc016`) that follow language
   changes: how a pre-1.0 language stays livable.
6. **Formatting.** `volec fmt FILE`, `--check`.
7. **In the editor.** `volec lsp`: diagnostics with their `try:` lines,
   definition, references, hover with effects.
8. **Working with an agent.** What an AI assistant does in a vole
   project: `volec guide` to learn the language (it's written for
   them), `query` instead of grep, `edit`/`refactor` instead of
   rewriting files, `check` after every edit, `try:` lines run as they
   are. How to set up a project for it: an `AGENTS.md` pointing at
   `volec guide`; optional hooks (the vole repository's
   `tools/agent-hooks` as an example). How to review its work:
   `query effects` and contracts make changes in behaviour visible.

## Errors to show

- A tool's one-line problem with a `try:` line (`patch.no-match`).
- An edit refused because it would add an error (`edit.breaks` or the
  real code), showing nothing was written.

## Asides

- If you know Rust: like rust-analyzer's assists, from the command line,
  checked before writing.

## Sources

`volec guide tools`, docs/query.md, docs/refactor.md, docs/lsp.md,
examples/tools, AGENTS.md (as an example of agent instructions).
