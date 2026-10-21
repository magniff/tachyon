# The tachyon tools

`tachyonc` reads and changes the program by name: ask it instead of
reading files with cat, grep or sed, and edit through it instead of
rewriting files. Names are resolved by the compiler, so a query sees
uses through imports and ignores comments and strings. Every command
below names the program with `--root main.tach` (its root file; the
other files are the modules it loads).

| you want | run |
|---|---|
| every error, one line each (front end only, fast) | `tachyonc check --root main.tach` |
| the source of a function, type, method | `tachyonc query show NAME --root main.tach` (several names in one call) |
| the item at an error's position | `tachyonc query show main.tach:LINE --root main.tach` |
| where it is defined, its signature | `tachyonc query def NAME --root main.tach` |
| where something is used | `tachyonc query refs NAME --root main.tach` (`--count`, `--in FILE`) |
| who calls a function | `tachyonc query callers NAME --root main.tach` |
| a module's items, with signatures | `tachyonc query items crate --root main.tach` (the root, main.tach); `query items lexer` (lexer.tach) |
| lines of any file | `tachyonc query text FILE:A-B --root main.tach` |
| change a few lines inside an item | `tachyonc edit patch NAME --old 'TEXT' --new 'TEXT' --root main.tach` (pairs repeat; `--loose` ignores indentation) |
| replace, add or remove an item | `tachyonc edit replace NAME --root main.tach < new.tach`, `edit insert --after NAME` (`--before`) `< item.tach`, `edit delete NAME` |
| add statements inside an item | `tachyonc edit insert --in NAME --after 'ANCHOR' --root main.tach < text` |
| see what an edit changed | `--show` on any edit; `tachyonc query diff --root main.tach` (the last edit) |
| take the last edit back | `tachyonc undo --root main.tach` |
| rename anything (a module: its file too), with every use | `tachyonc refactor rename PATH NEW --root main.tach` |
| a parameter, with every call | `tachyonc refactor signature FN --add 'x: i64 = 0' --root main.tach` (`--remove x`, `--rename-param a b`, `--reorder b,a`) |
| a field, with every literal and access | `tachyonc refactor field STRUCT --add 'g: i64 = 0' --root main.tach` (`--remove g`, `--rename g h`) |
| a variant, with an arm in each match | `tachyonc refactor variant ENUM --add 'X(i64)' --arm 'EXPR' --root main.tach` (`--remove V`, `--rename V W`) |
| move items to another module | `tachyonc refactor move NAME... --to MODULE --root main.tach` |
| missing imports, unused ones, `pub`, `unsafe` blocks | `tachyonc fix --root main.tach` (`--only imports,unused,pub,unsafe`, `--dry-run`) |
| what a diagnostic code means | `tachyonc explain CODE` |

NAME is `f`, `module::f`, `Type::method`, `Enum::Variant`,
`Struct.field` or `main.tach:LINE`. Every edit is checked first: an edit
that adds an error writes nothing and prints the errors (`--no-check`
writes anyway, `--dry-run` prints the diff). A problem is one stderr
line, `error CODE: message`, then `try:` lines: commands to run as they
are, for example

```text
error patch.no-match: OLD 1 is not in crate::largest; nearest, line 52: var best = 0;
try: tachyonc query show main.tach:52
```

Compile errors print one line each with `tachyonc check --root main.tach`
or `tachyonc --diagnostics=short main.tach -o prog`:

```text
main.tach:4:20: error[type error] undefined variable 'totl' | help: did you mean 'total'?
```
