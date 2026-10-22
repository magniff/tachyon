# Tools

The compiler reads and changes programs by name: ask it instead of
reading files with grep or sed, and edit through it instead of
rewriting files. Names are resolved by the compiler, so a query sees
uses through imports and ignores comments and strings.

When they pay off: renames, moves, signature, field and variant
changes (every use, checked, in one command), errors across files, and
code too large to read. A small program (a few hundred lines) is
cheaper read whole, once (`volec query show FILE.vl` up to 200
lines, `query text FILE:A-B` 200 at a time), than explored with many
small queries.

## The loop

1. Write the program; `volec check` (the front end only: fast, every
   error, one line each; `ok: 0 errors in main.vl` when there is none). Before writing a construct you are unsure of,
   `volec guide --find WORDS` or `volec guide TOPIC#SECTION`
   prints the lines on it.
2. Fix each error: `volec query show FILE:LINE` prints the item at
   the error's position; `volec edit patch` changes a few lines of it.
3. `volec fix --suggested` when errors have `try: volec fix
   --suggested main.vl` (0.18): their exact fixes, one checked edit,
   then the errors left; `volec fix` for unsafe blocks.
4. Build and run: `volec main.vl -o prog && ./prog` (a build that
   works ends with `ok: built prog`).

## The program

Commands find the program's root file from `--root FILE`, a last
argument ending in `.vl`, `$VOLE_ROOT`, or `./main.vl`. The other
files are the modules it loads.

## Reading

For an item you have not seen, ask `volec query context NAME` first:
one call gives its source, the signatures of what it calls and uses,
and its callers (instead of `show`, then `def`, then `refs`):

```text
$ volec query context parse_item
// crate::parse_item  main.vl:5-9  effects: panic
fn parse_item(sc: inout Scanner) -> Option<Item> {
    let name = sc.next_token()?;
    ...
}
// calls (3)
std::Scanner::next_token  <std>:2184:12  method  pub fn next_token(inout self) -> Option<[u8]>
...
// types (3)
crate::Item  main.vl:3:8  struct  struct Item { name: [u8], qty: i64 }
...
// callers (1)
main  main.vl:19:26  while let Some(it) = parse_item(&sc) {
```

(The fields are separated by TABs.) It stays within about 2,000 tokens
(`--budget N`); a module's name gives its items and its most used
bodies.

| to | run |
|---|---|
| an item with what it calls, its types and callers | `volec query context NAME` (`--budget N`) |
| an item's source | `volec query show NAME` (`--with-comments`) |
| the item at an error | `volec query show FILE:LINE` |
| where it is defined, its signature | `volec query def NAME` |
| every use | `volec query refs NAME` (`--count`, `--in FILE\|MODULE`; a local: `FN::x`) |
| who calls a function; what it calls | `volec query callers NAME`; `query callees FN` (`--transitive`) |
| each local's kind, moves and views there (0.17) | `volec query own main.vl:12:5` |
| what a function may do: allocate, io, panic... (0.16) | `volec query effects NAME\|MODULE` (`--why io`, `--has alloc(Gpa)`) |
| a module's items, with signatures | `volec query items MODULE`; every module: `query items` |
| a module's `use` lines, header comment | `volec query show MODULE::use` (`::header`) |
| lines of any file | `volec query text FILE:A-B` |
| what nothing uses | `volec query unused` |
| sizes, dependencies | `volec query stats`, `query deps MODULE` |
| std's API, a std item | `volec query items std`, `query show std::read_line` (any program) |
| what a snippet does | `volec try 'let v = [3, 1]; v[..].len()'` prints `i64 = 2` |
| the guide on some words | `volec guide --find WORDS`, `guide TOPIC#SECTION`, `explain WORDS` |
| items like one, to copy for a new one; recipes for adding an X (0.17) | `volec query similar NAME`; `query examples KIND`; `volec guide how` |

NAME is `f`, `module::f`, `Type::method`, `Enum::Variant`,
`Struct.field`, `<Type as Trait>::f` or `FILE:LINE`; several in one call;
every name a tool prints is taken back. Output is one fact per line,
fields separated by a TAB; `--budget N` keeps it to about N tokens.
`CMD --help` lists a command's options.

Several commands in one call: `volec batch < cmds.txt`, one command
per line as typed after `volec` (`<<END` ... `END` gives one its
stdin); each output follows a line `## $ volec ARGS`. Chain what you
would run in turn: `query items` then `query show`, `show` then `refs`,
an edit then `check`.

## Changing

| to | run |
|---|---|
| change text inside an item | `volec edit patch NAME --old 'TEXT' --new 'TEXT'` (pairs repeat) |
| replace, add, remove an item | `volec edit replace NAME < new.vl`, `edit insert --after NAME < item.vl`, `edit delete NAME` |
| add statements inside an item | `volec edit insert --in NAME --after 'ANCHOR' < text` |
| several items at once, one edit | `volec edit apply items.vl`: `@@ NAME` then its new text, `@@ new after NAME`, `@@ delete NAME` (or `query show A B`'s output, edited) |
| see the result | `--show` on any edit; `volec query diff` |
| undo the last edit | `volec undo` (the journal: in `.git`, else in `.volec/` next to main.vl) |
| merge conflicts | `volec query conflicts --show`, then `volec edit resolve FILE:LINE --ours` (`--theirs`, `--both`, `< text`) |
| rename anything, with every use | `volec refactor rename PATH NEW` |
| rename a local or parameter | `volec refactor rename FILE:LINE:COL NEW` or `refactor rename FN::x NEW` (shadowing respected) |
| a parameter, with every call | `volec refactor signature FN --add 'x: i64 = 0'` (a default; `--fill-calls`: each call gets 0; `--remove`, `--rename-param`, `--reorder`, `--type`; `--convention v inout`: the calls pass `&v`, `--convention v let` or `sink`: `v`) |
| a field, with every literal | `volec refactor field STRUCT --add 'g: i64 = 0'` (`--type g T --default EXPR`) |
| a variant, with every match | `volec refactor variant ENUM --add 'X(i64)' --arm 'EXPR'` (`--arm-in FN 'EXPR'` per match) |
| move items to a module | `volec refactor move PATH --to MODULE` (made when missing) |
| an idiom everywhere, typed | `volec rewrite 'old($a)' 'new($a)' --dry-run` |
| a word in every file git tracks (docs, scripts, a source's comments or strings) | `volec rewrite --text OLD NEW --word --case --dry-run --diff` (`--files GLOB`, `--comments`, `--strings`, `--no-sources`, `--exclude SPEC`, `--check ROOT`) |
| sources to another extension, with the mentions of their paths | `volec refactor extension .vl .vl ROOT\|DIR\|--all --dry-run` (git mv; the build compared before and after) |
| imports, unused, pub, unsafe | `volec fix` (`--only imports,unused,pub,unsafe`, `--dry-run`) |
| 0.19's spelling to 0.20's (`&T` to `T`, `&mut T` to `inout T`, `let mut` to `var`, receivers, `&mut v` to `&v`, `*r` to `r`) | `volec fix --only conventions` (`--dry-run`) |
| `*T` and by-value parameters of 0.16 code to accesses, with every call (0.17) | `volec fix --values` (`--dry-run`) |
| the errors' exact fixes (their `try: volec fix --suggested`) | `volec fix --suggested` (`--dry-run`, `--at FILE:LINE`) |

Every edit is atomic: the edited program is checked first, and an edit
that adds an error writes nothing and prints the errors, each tagged
`[edited: PATH]` or `[in PATH]` (an item the edit did not change: change
it in the same `edit apply`, or run the refactoring the `try:` line
names). `--dry-run` prints the diff instead; `--no-check` writes anyway.

## Testing

`volec test` builds the program when a source changed and runs its
cases: `tests/NAME.in` (stdin; none: empty) with `tests/NAME.out` (the
expected stdout), next to `main.vl`; `tests/NAME.exit` holds an exit
status other than 0. It prints the counts first, then each failing case
with a few lines of difference, within about 1,000 tokens:

```text
$ volec test
test main.vl: 4 passed, 1 failed (tests/)
FAIL big: stdout differs at line 3 (10 lines expected, 9 printed)
  - 42 apples
  - 43 pears
  + 41 apples
  + 43 pears
(outputs: .volec/test/NAME.got, NAME.err)
```

`volec test big small` runs the cases whose names contain a word;
`--full` every failure in full; `--input FILE` (`-`: stdin) one run,
its output and exit status; `--timeout S` per case (10). Output is
compared with `\r\n` as `\n` and trailing whitespace at the end left
out. In the vole tree, `volec test FILTER` rebuilds
`target/volec` when the source is newer and runs `tests/run.sh
FILTER`, summarized the same way.

## Debugging

A bug: `volec guide debug`. Tests are built with `--trace`, so a crash
or a hang prints its line and callers. `volec probe FILE:LINE EXPR...
--input FILE` prints values at a line without editing the source.
`volec reduce FILE --until 'CMD'` shrinks a failing input. In the
vole tree, `volec test FILTER` also runs each failure with
`target/tools/volec`, to tell new failures from old ones.

## Diagnostics

Compiler errors, from `volec check` or a build whose output is not a
terminal (`--diagnostics=short` anywhere, `--diagnostics=human` for the
multi-line form):

```text
main.vl:4:20: error[type error] undefined variable 'totl' | help: did you mean 'total'?
```

A tool's problem is one line, `SEVERITY CODE: MESSAGE` (the code is
stable), followed by `try:` lines, each a command to run as it is:

```text
error patch.no-match: OLD 1 is not in crate::main; nearest, line 4: std::print_int(total);
try: volec edit patch main --old 'print_int(total)' --new 'print_int(total + 1)'
```

Exit status: 0 done, 1 refused or failed (nothing written), 2 usage.

## In an editor

`volec lsp` (0.24) is a language server over stdin and stdout: the
same answers in an editor, unsaved edits included. Definition and
references; hover with a function's signature, effects (declared or
inferred, a line of why each) and features, or a local's type; the
file's symbols; `check`'s errors as diagnostics, their `try:` lines
attached. The root: the nearest `main.vl` (docs/lsp.md).

## Other compiler options

`-O0`, `-O1`, `-O2` (the default; all behave the same), `-j N` (0.18.1:
the threads -O1 and -O2 compile on; the output is the same whatever N),
`--no-cache` (0.18.1: -O1 and -O2 keep each function's optimized code in
`target/volec-cache/`, as the tools' cache, and a rebuild reuses what
an edit did not change, the same bytes, for a program past about 8000
IR instructions or with `--cache=on`; `--no-cache` goes without),
`--target aarch64-macos|aarch64-linux|x86_64-linux|x86_64-macos`, `-g` (debug line
tables), `--trace` (0.17: a failure prints its line and callers),
`--check-unsafe`, `--check-alloc` (0.16), `--emit-header`,
`--emit-imports`, `-I DIR`, `--version`; `--emit-ir` and `--emit-mir`
(the IR after the optimizer, after instruction selection) print to
stdout, or to `-o FILE`. `volec guide TOPIC` for the language.
