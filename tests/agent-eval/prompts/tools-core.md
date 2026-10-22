# The vole tools

`volec` answers questions about the program and makes checked edits
by name (names resolved by the compiler: through imports, not in
comments or strings). Every command below names the program with
`--root main.vl`. **For an item you have not seen, run `volec
query context NAME --root main.vl` first**: its source, the
signatures of what it calls and its callers, in one call (`volec
query context parse_line --root main.vl`). Use these first:

| you want | run |
|---|---|
| an unfamiliar item: its source, callers and what it calls, in one call | `volec query context NAME --root main.vl` (replaces show + refs + def) |
| the source of an item; a whole small file | `volec query show NAME --root main.vl`; `query show FILE.vl` (a file under 300 lines is cheaper read whole) |
| every use of a name | `volec query refs NAME --root main.vl` (`--count`, `--in FILE`) |
| change a few lines of an item, checked | `volec edit patch NAME --old 'TEXT' --new 'TEXT' --root main.vl` |
| replace, add, remove an item | `volec edit replace\|insert\|delete NAME --root main.vl` (`< text`) |
| rename, move, change a signature, field or variant everywhere | `volec refactor rename\|move\|signature\|field\|variant ... --root main.vl` |
| missing imports, `pub`, `unsafe` blocks | `volec fix --root main.vl` |
| every error, one line each | `volec check --root main.vl` |
| a bug: where it fails, the values at a line, a smaller failing input | `volec guide debug` (`volec test` prints a crash's line and callers; `volec probe FILE:LINE EXPR... --input FILE`; `volec reduce FILE --until 'CMD'`) |

Everything else (`query grep|items|type`, `edit apply`, `rewrite`,
`undo`, `batch`): `volec --help`, `volec CMD --help`, `volec
guide tools`, or `volec explain CODE` on any error. NAME is `f`,
`module::f`, `Type::method`, `Struct.field` or `main.vl:LINE`. Every
edit is checked first: one that adds an error writes nothing and prints
the errors. A problem is one line, `error CODE: message`, then `try:`
lines: commands to run as they are.
