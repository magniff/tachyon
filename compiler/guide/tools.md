# Tools

The compiler reads and changes programs by name: ask it instead of
reading files with grep or sed, and edit through it instead of
rewriting files. Names are resolved by the compiler, so a query sees
uses through imports and ignores comments and strings.

When they pay off: renames, moves, signature, field and variant
changes (every use, checked, in one command), errors across files, and
code too large to read. A small program (a few hundred lines) is
cheaper read whole, once (`tachyonc query show FILE.tach` up to 200
lines, `query text FILE:A-B` 200 at a time), than explored with many
small queries.

## The loop

1. Write the program; `tachyonc check` (the front end only: fast, every
   error, one line each). Before writing a construct you are unsure of,
   `tachyonc guide --find WORDS` or `tachyonc guide TOPIC#SECTION`
   prints the lines on it.
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

For an item you have not seen, ask `tachyonc query context NAME` first:
one call gives its source, the signatures of what it calls and uses,
and its callers (instead of `show`, then `def`, then `refs`):

```text
$ tachyonc query context parse_item
// crate::parse_item  main.tach:5-9  effects: panic
fn parse_item(sc: *Scanner) -> Option<Item> {
    let name = sc.next_token()?;
    ...
}
// calls (3)
std::Scanner::next_token  <std>:2184:12  method  pub fn next_token(self: *Scanner) -> Option<[u8]>
...
// types (3)
crate::Item  main.tach:3:8  struct  struct Item { name: [u8], qty: i64 }
...
// callers (1)
main  main.tach:19:26  while let Some(it) = parse_item(&sc) {
```

(The fields are separated by TABs.) It stays within about 2,000 tokens
(`--budget N`); a module's name gives its items and its most used
bodies.

| to | run |
|---|---|
| an item with what it calls, its types and callers | `tachyonc query context NAME` (`--budget N`) |
| an item's source | `tachyonc query show NAME` (`--with-comments`) |
| the item at an error | `tachyonc query show FILE:LINE` |
| where it is defined, its signature | `tachyonc query def NAME` |
| every use | `tachyonc query refs NAME` (`--count`, `--in FILE\|MODULE`; a local: `FN::x`) |
| who calls a function; what it calls | `tachyonc query callers NAME`; `query callees FN` (`--transitive`) |
| what a function may do: allocate, io, panic... (0.16) | `tachyonc query effects NAME\|MODULE` (`--why io`, `--has alloc(Gpa)`) |
| a module's items, with signatures | `tachyonc query items MODULE`; every module: `query items` |
| a module's `use` lines, header comment | `tachyonc query show MODULE::use` (`::header`) |
| lines of any file | `tachyonc query text FILE:A-B` |
| what nothing uses | `tachyonc query unused` |
| sizes, dependencies | `tachyonc query stats`, `query deps MODULE` |
| std's API, a std item | `tachyonc query items std`, `query show std::read_line` (any program) |
| what a snippet does | `tachyonc try 'let v = [3, 1]; v[..].len'` prints `i64 = 2` |
| the guide on some words | `tachyonc guide --find WORDS`, `guide TOPIC#SECTION`, `explain WORDS` |
| items like one, to copy for a new one; recipes for adding an X (0.17) | `tachyonc query similar NAME`; `query examples KIND`; `tachyonc guide how` |

NAME is `f`, `module::f`, `Type::method`, `Enum::Variant`,
`Struct.field`, `<Type as Trait>::f` or `FILE:LINE`; several in one call;
every name a tool prints is taken back. Output is one fact per line,
fields separated by a TAB; `--budget N` keeps it to about N tokens.
`CMD --help` lists a command's options.

Several commands in one call: `tachyonc batch < cmds.txt`, one command
per line as typed after `tachyonc` (`<<END` ... `END` gives one its
stdin); each output follows a line `## $ tachyonc ARGS`. Chain what you
would run in turn: `query items` then `query show`, `show` then `refs`,
an edit then `check`.

## Changing

| to | run |
|---|---|
| change text inside an item | `tachyonc edit patch NAME --old 'TEXT' --new 'TEXT'` (pairs repeat) |
| replace, add, remove an item | `tachyonc edit replace NAME < new.tach`, `edit insert --after NAME < item.tach`, `edit delete NAME` |
| add statements inside an item | `tachyonc edit insert --in NAME --after 'ANCHOR' < text` |
| several items at once, one edit | `tachyonc edit apply items.tach`: `@@ NAME` then its new text, `@@ new after NAME`, `@@ delete NAME` (or `query show A B`'s output, edited) |
| see the result | `--show` on any edit; `tachyonc query diff` |
| undo the last edit | `tachyonc undo` (the journal: in `.git`, else in `.tachyonc/` next to main.tach) |
| merge conflicts | `tachyonc query conflicts --show`, then `tachyonc edit resolve FILE:LINE --ours` (`--theirs`, `--both`, `< text`) |
| rename anything, with every use | `tachyonc refactor rename PATH NEW` |
| rename a local or parameter | `tachyonc refactor rename FILE:LINE:COL NEW` or `refactor rename FN::x NEW` (shadowing respected) |
| a parameter, with every call | `tachyonc refactor signature FN --add 'x: i64 = 0'` (a default; `--fill-calls`: each call gets 0; `--remove`, `--rename-param`, `--reorder`, `--type`) |
| a field, with every literal | `tachyonc refactor field STRUCT --add 'g: i64 = 0'` |
| a variant, with every match | `tachyonc refactor variant ENUM --add 'X(i64)' --arm 'EXPR'` (`--arm-in FN 'EXPR'` per match) |
| move items to a module | `tachyonc refactor move PATH --to MODULE` (made when missing) |
| an idiom everywhere, typed | `tachyonc rewrite 'old($a)' 'new($a)' --dry-run` |
| imports, unused, pub, unsafe | `tachyonc fix` (`--only imports,unused,pub,unsafe`, `--dry-run`) |

Every edit is atomic: the edited program is checked first, and an edit
that adds an error writes nothing and prints the errors, each tagged
`[edited: PATH]` or `[in PATH]` (an item the edit did not change: change
it in the same `edit apply`, or run the refactoring the `try:` line
names). `--dry-run` prints the diff instead; `--no-check` writes anyway.

## Testing

`tachyonc test` builds the program when a source changed and runs its
cases: `tests/NAME.in` (stdin; none: empty) with `tests/NAME.out` (the
expected stdout), next to `main.tach`; `tests/NAME.exit` holds an exit
status other than 0. It prints the counts first, then each failing case
with a few lines of difference, within about 1,000 tokens:

```text
$ tachyonc test
test main.tach: 4 passed, 1 failed (tests/)
FAIL big: stdout differs at line 3 (10 lines expected, 9 printed)
  - 42 apples
  - 43 pears
  + 41 apples
  + 43 pears
(outputs: .tachyonc/test/NAME.got, NAME.err)
```

`tachyonc test big small` runs the cases whose names contain a word;
`--full` every failure in full; `--input FILE` (`-`: stdin) one run,
its output and exit status; `--timeout S` per case (10). Output is
compared with `\r\n` as `\n` and trailing whitespace at the end left
out. In the tachyon tree, `tachyonc test FILTER` rebuilds
`target/tachyonc` when the source is newer and runs `tests/run.sh
FILTER`, summarized the same way.

## Diagnostics

Compiler errors, from `tachyonc check` or a build whose output is not a
terminal (`--diagnostics=short` anywhere, `--diagnostics=human` for the
multi-line form):

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
tables), `--check-unsafe`, `--check-alloc` (0.16), `--emit-header`,
`--emit-imports`, `-I DIR`, `--version`. `tachyonc guide TOPIC` for the language.
