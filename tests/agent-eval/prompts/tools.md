# The vole tools

`volec` reads and changes the program by name: ask it instead of
reading files with cat, grep or sed, and edit through it instead of
rewriting files. Names are resolved by the compiler, so a query sees
uses through imports and ignores comments and strings. Every command
below names the program with `--root main.vl` (its root file; the
other files are the modules it loads).

| you want | run |
|---|---|
| every error, one line each (front end only, fast) | `volec check --root main.vl` |
| the source of a function, type, method | `volec query show NAME --root main.vl` (several names in one call) |
| the item at an error's position | `volec query show main.vl:LINE --root main.vl` |
| where it is defined, its signature | `volec query def NAME --root main.vl` |
| where something is used | `volec query refs NAME --root main.vl` (`--count`, `--in FILE`) |
| who calls a function | `volec query callers NAME --root main.vl` |
| a module's items, with signatures | `volec query items crate --root main.vl` (the root, main.vl); `query items lexer` (lexer.vl) |
| lines of any file | `volec query text FILE:A-B --root main.vl` |
| change a few lines inside an item | `volec edit patch NAME --old 'TEXT' --new 'TEXT' --root main.vl` (pairs repeat; `--loose` ignores indentation) |
| replace, add or remove an item | `volec edit replace NAME --root main.vl < new.vl`, `edit insert --after NAME` (`--before`) `< item.vl`, `edit delete NAME` |
| add statements inside an item | `volec edit insert --in NAME --after 'ANCHOR' --root main.vl < text` |
| see what an edit changed | `--show` on any edit; `volec query diff --root main.vl` (the last edit) |
| take the last edit back | `volec undo --root main.vl` |
| rename anything (a module: its file too), with every use | `volec refactor rename PATH NEW --root main.vl` |
| a parameter, with every call | `volec refactor signature FN --add 'x: i64 = 0' --root main.vl` (`--remove x`, `--rename-param a b`, `--reorder b,a`) |
| a field, with every literal and access | `volec refactor field STRUCT --add 'g: i64 = 0' --root main.vl` (`--remove g`, `--rename g h`) |
| a variant, with an arm in each match | `volec refactor variant ENUM --add 'X(i64)' --arm 'EXPR' --root main.vl` (`--remove V`, `--rename V W`) |
| move items to another module | `volec refactor move NAME... --to MODULE --root main.vl` |
| missing imports, unused ones, `pub`, `unsafe` blocks | `volec fix --root main.vl` (`--only imports,unused,pub,unsafe`, `--dry-run`) |
| what a diagnostic code means | `volec explain CODE` |

NAME is `f`, `module::f`, `Type::method`, `Enum::Variant`,
`Struct.field` or `main.vl:LINE`. Every edit is checked first: an edit
that adds an error writes nothing and prints the errors (`--no-check`
writes anyway, `--dry-run` prints the diff). A problem is one stderr
line, `error CODE: message`, then `try:` lines: commands to run as they
are, for example

```text
error patch.no-match: OLD 1 is not in crate::largest; nearest, line 52: var best = 0;
try: volec query show main.vl:52
```

Compile errors print one line each with `volec check --root main.vl`
or `volec --diagnostics=short main.vl -o prog`:

```text
main.vl:4:20: error[type error] undefined variable 'totl' | help: did you mean 'total'?
```
