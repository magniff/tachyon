# The tachyon tools

`tachyonc` answers questions about the program and makes checked edits
by name (names resolved by the compiler: through imports, not in
comments or strings). Every command below names the program with
`--root main.tach`. **For an item you have not seen, run `tachyonc
query context NAME --root main.tach` first**: its source, the
signatures of what it calls and its callers, in one call (`tachyonc
query context parse_line --root main.tach`). Use these first:

| you want | run |
|---|---|
| an unfamiliar item: its source, callers and what it calls, in one call | `tachyonc query context NAME --root main.tach` (replaces show + refs + def) |
| the source of an item; a whole small file | `tachyonc query show NAME --root main.tach`; `query show FILE.tach` (a file under 300 lines is cheaper read whole) |
| every use of a name | `tachyonc query refs NAME --root main.tach` (`--count`, `--in FILE`) |
| change a few lines of an item, checked | `tachyonc edit patch NAME --old 'TEXT' --new 'TEXT' --root main.tach` |
| replace, add, remove an item | `tachyonc edit replace\|insert\|delete NAME --root main.tach` (`< text`) |
| rename, move, change a signature, field or variant everywhere | `tachyonc refactor rename\|move\|signature\|field\|variant ... --root main.tach` |
| missing imports, `pub`, `unsafe` blocks | `tachyonc fix --root main.tach` |
| every error, one line each | `tachyonc check --root main.tach` |
| a bug: where it fails, the values at a line, a smaller failing input | `tachyonc guide debug` (`tachyonc test` prints a crash's line and callers; `tachyonc probe FILE:LINE EXPR... --input FILE`; `tachyonc reduce FILE --until 'CMD'`) |

Everything else (`query grep|items|type`, `edit apply`, `rewrite`,
`undo`, `batch`): `tachyonc --help`, `tachyonc CMD --help`, `tachyonc
guide tools`, or `tachyonc explain CODE` on any error. NAME is `f`,
`module::f`, `Type::method`, `Struct.field` or `main.tach:LINE`. Every
edit is checked first: one that adds an error writes nothing and prints
the errors. A problem is one line, `error CODE: message`, then `try:`
lines: commands to run as they are.
