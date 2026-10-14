# Tools

The compiler reads and changes programs by name: ask it instead of
reading files with grep or sed, and edit through it instead of
rewriting files. Names are resolved by the compiler, so a query sees
uses through imports and ignores comments and strings.

## The loop

1. Write the program; `tachyonc check` (the front end only: fast, every
   error, one line each).
2. Fix each error: `tachyonc query show FILE:LINE` prints the item at
   the error's position; `tachyonc edit patch` changes a few lines of it.
3. `tachyonc fix` for the mechanical ones (missing `use` lines, unsafe
   blocks, `pub`).
4. Build and run: `tachyonc main.tach -o prog && ./prog`.

## The program

Commands find the program's root file from `--root FILE`, a last
argument ending in `.tach`, `$TACHYON_ROOT`, or `./main.tach`. The other
files are the modules it loads.

## Reading

| to | run |
|---|---|
| an item's source | `tachyonc query show NAME` (`--with-comments`) |
| the item at an error | `tachyonc query show FILE:LINE` |
| where it is defined, its signature | `tachyonc query def NAME` |
| every use | `tachyonc query refs NAME` (`--count`, `--in FILE\|MODULE`) |
| who calls a function | `tachyonc query callers NAME` |
| a module's items, with signatures | `tachyonc query items MODULE`; every module: `query items` |
| a module's `use` lines, header comment | `tachyonc query show MODULE::use` (`::header`) |
| lines of any file | `tachyonc query text FILE:A-B` |
| what nothing uses | `tachyonc query unused` |
| sizes, dependencies | `tachyonc query stats`, `query deps MODULE` |

NAME is `f`, `module::f`, `Type::method`, `Enum::Variant`,
`Struct.field`, `<Type as Trait>::f` or `FILE:LINE`; several in one call.
Output is one fact per line, fields separated by a TAB.

## Changing

| to | run |
|---|---|
| change text inside an item | `tachyonc edit patch NAME --old 'TEXT' --new 'TEXT'` (pairs repeat) |
| replace, add, remove an item | `tachyonc edit replace NAME < new.tach`, `edit insert --after NAME < item.tach`, `edit delete NAME` |
| add statements inside an item | `tachyonc edit insert --in NAME --after 'ANCHOR' < text` |
| see the result | `--show` on any edit; `tachyonc query diff` |
| undo the last edit | `tachyonc undo` (in a git checkout: the journal is in `.git`) |
| rename anything, with every use | `tachyonc refactor rename PATH NEW` |
| a parameter, with every call | `tachyonc refactor signature FN --add 'x: i64 = 0'` (`--remove`, `--rename-param`, `--reorder`, `--type`) |
| a field, with every literal | `tachyonc refactor field STRUCT --add 'g: i64 = 0'` |
| a variant, with every match | `tachyonc refactor variant ENUM --add 'X(i64)' --arm 'EXPR'` |
| move items to a module | `tachyonc refactor move PATH --to MODULE` |
| an idiom everywhere, typed | `tachyonc rewrite 'old($a)' 'new($a)' --dry-run` |
| imports, unused, pub, unsafe | `tachyonc fix` (`--only imports,unused,pub,unsafe`, `--dry-run`) |

Every edit is atomic: the edited program is checked first, and an edit
that adds an error writes nothing and prints the errors. `--dry-run`
prints the diff instead; `--no-check` writes anyway.

## Diagnostics

Compiler errors, with `--diagnostics=short` or from `tachyonc check`:

```text
main.tach:4:20: error[type error] undefined variable 'totl' | help: did you mean 'total'?
```

A tool's problem is one line, `SEVERITY CODE: MESSAGE` (the code is
stable), followed by `try:` lines, each a command to run as it is:

```text
error patch.no-match: OLD 1 is not in crate::main; nearest, line 4: std::print_int(total);
try: tachyonc edit patch main --old 'print_int(total)' --new 'print_int(total + 1)'
```

Exit status: 0 done, 1 refused or failed (nothing written), 2 usage.

## Other compiler options

`-O0`, `-O1`, `-O2` (the default; all behave the same), `--target
aarch64-macos|aarch64-linux|x86_64-linux|x86_64-macos`, `-g` (debug line
tables), `--check-unsafe`, `--emit-header`, `--emit-imports`, `-I DIR`,
`--version`. `tachyonc guide TOPIC` for the language.
