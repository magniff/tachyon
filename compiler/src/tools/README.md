# tools: query, edit, fix and the refactorings

The tools on the front end ([docs/query.md](../../../docs/query.md),
[docs/refactor.md](../../../docs/refactor.md)): they read a program as
the front end checks it (no code is generated) and change it by name.
Every change goes through the edit engine (`edit/`): byte ranges replaced,
the edited program checked before anything is written, a journal for
`undo`.

| module | |
|---|---|
| `query/` | `tachyonc query`: definitions (`defs`), positions, references (`refs`), `def`/`show`/`items` (`show`), diagnostics and `try:` lines; the tools' cache under target/ (`cache`, 0.13) |
| `query_text.tach` | `query text`, `query show FILE`, a module's regions (`::use`, `::header`, `::extern`) |
| `plan/` | the planning queries: `stats`, `deps` (with the clustering), `unused`, `impact`; `lint` |
| `proc.tach` | processes and files: running a program, workers, renames |
| `edit/` | the edit engine (`mod`, `apply`, `diff`, `undo`), items as text (`items`), `edit replace|insert|delete`, `check` (`cli`), `edit wrap` (`wrap`), `edit new-file` (`newfile`); `edit apply` (`applyfile`, 0.15); what an edit that adds errors broke, and the refactoring that fits (`breaks`, 0.15) |
| `patch/` | `edit patch`, `edit insert --in`: edits inside an item by its text (0.15: of several targets) |
| `fix.tach` | `tachyonc fix`: every machine-applicable fix, in rounds, as one edit |
| `fiximports.tach`, `fixunsafe.tach` | `fix --only imports` (0.8's wildcards), `fix --only unsafe` |
| `tidyimports.tach` | `fix --only tidy-imports`, and the round move and split run |
| `reexports.tach` | `fix --only reexports` |
| `sameout.tach` | `tachyonc same-output` |
| `rewrite/` | `tachyonc rewrite`: typed structural search and replace (`pattern`; the parsed nodes in `parsed`) |
| `refactor_shape/` | `refactor signature`, `field`, `variant` |
| `refactor_mod/` | `refactor rename`, `new-module`, `move-module`; the command line (`cli`); renaming a local (`local`, 0.14); the mentions in comments (`mentions`, 0.14) |
| `refactor_move/` | `refactor move`, `split`: units and blocks (`units`), imports (`imports`) |
| `script.tach` | `refactor --script`: commands checked once, one undo |
| `batch.tach` | `tachyonc batch` (0.15): several commands in one call, each in a fork, outputs under header lines |
| `commands.tach` | the table of the commands that change a program; `run_command`, every tool command (main, batch) |
| `fmt/` | `tachyonc fmt` (0.13, docs/fmt.md): the pieces of a text (`pieces`), lines and levels (`layout`), wrapping (`wrap`), `use` runs (`uses`); the edit engine formats its edits with it |
| `explain/` | `tachyonc explain CODE` (0.13): the table of every diagnostic code (`tools_table`, `refactor_table`) |
