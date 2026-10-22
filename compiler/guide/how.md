# How to add an X

Recipes for the changes made again and again (0.17): the files, the
commands in order, the test, the docs. `volec guide how TASK` prints
one; `volec query examples KIND` prints the items to start from, and
`volec query similar NAME` the items like one you name (copy the
nearest). In the vole repository (commands from its root):

- `add-std-fn`: a std function or method
- `add-peephole`: an instruction-combining or e-graph rule
- `add-pass`: an optimization pass
- `add-diagnostic`: a compiler error, or a tool diagnostic with a code
- `add-test`: a test case
- `add-subcommand`: a `volec` command, or a `query` command
- `add-guide-text`: a paragraph or an example in the guide

In a program of your own:

- `add-module`: a module (a file) to a program

## add-std-fn

To add a std function or method.

std is `compiler/std/`: the module `std` (`std.vl` and the files of
`flat/`) and its modules (`std::fmt` in `fmt.vl`, `std::collections::hash_map`
in `collections/hash_map.vl`); `compiler/std/embed.sh` builds it into the compiler (`compiler/src/front/stdsrc.vl`).

1. Find where it goes: `volec query similar std::trim` (or
   `Vec::swap`) prints its neighbours, with their files
   (`compiler/std/flat/io.vl:28`); `volec query examples std-fn`.
2. Add it by name, next to its kin:
   `volec edit insert --after std::trim < new.vl` (a method:
   `--after Vec::swap`). The edit is made in std's file and checked with
   the edited std, every function of it (a generic one with `i64` for
   its type parameters); then embed.sh runs (`note edit.std`). Inside
   std the prelude is as everywhere (0.17): `None`, `Ok(x)`. A function
   that allocates takes its allocator, `NAME_in(..., a: A)`, and has an
   `#[ambient]` wrapper without it, like `split_whitespace` and
   `split_whitespace_in`.
3. A test: `tests/run/std_NAME.vl` with `// EXPECT:` lines (edge
   cases: empty, too long, at the ends); see `add-test`.
4. The guide: a sentence and a `tach` example with its `out` block in
   `compiler/guide/std.md` (the API listing at its end is generated);
   `compiler/guide/embed.sh`.
5. `bootstrap/bootstrap.sh --dev` (the compiler with the new std), then
   `tests/run.sh std_NAME`, `tests/run.sh -O 0 std_NAME`,
   `tests/run.sh guide`.

`volec undo` takes a std edit back (and embeds again).

## add-peephole

To add an instruction-combining or e-graph rule.

An algebraic identity on constants and operations (`(x + c1) + c2`):
a line of `crate::middle::egraph::rule_text`, such as
`(neg (neg x)) => x` or `(mul x c1) if (pow2 c1) => (shl x (log2 c1))`;
the array's length and `RULE_COUNT` grow by one, in the same edit
(`volec edit patch rule_text --pairs FILE` with a `@@ RULE_COUNT`
block for the second target, or `volec edit apply`). `volec --check-rules` tests every rule on
random values (the suite runs it).

Anything else (a select, a negated comparison, an address): a function
`combine_X(v: i64) -> bool` in `compiler/src/middle/fold/mod.vl`,
section "Instruction combining", called from `combine` on the
instruction's op; true when it changed `v` (in place, or with
`replace_same_type`, `make_const`, `op_before`). Templates: `volec
query examples peephole`.

Test: `tests/run/opt_NAME.vl`, a program with `// EXPECT:` and
`// CHECK:` / `// CHECK-NOT:` lines on the optimized IR (`--emit-ir`;
`tests/run/opt_egraph.vl`); `tests/run.sh opt_` at `-O 0`, `1`, `2`.

## add-pass

To add an optimization pass.

1. `volec edit new-file compiler/src/middle/NAME.vl < text` (adds
   the `mod` line): `pub fn NAME(fi: i64) -> bool`, true when it
   changed function `fi`. Templates: `volec query examples pass`
   (`elide_copies`, `thread_tags`).
2. Call it in `compiler/src/middle/opt.vl`: in `simplify_function`
   (scalar, -O1 and -O2) as `if round == 0 && NAME(fi) { verify_func(fi,
   c"NAME"); }`, or in `optimize_loops` (-O2) as `if NAME(fi) { changed =
   true; light_cleanup(fi); }`. `verify_func` checks the IR under
   `--verify-ir` and prints it under `--print-after-all`.
3. Test: `tests/run/opt_NAME.vl` with `// CHECK:` lines (see
   `add-peephole`); `tests/run.sh opt_`; `tests/fuzz/run.sh` (random
   programs at every level); `--time-passes` for its compile time.
4. Docs: the module table of `compiler/src/middle/README.md`,
   `docs/optimizer.md`. Before committing: `bootstrap/gate.sh --quick`
   (and `bench/run.sh`: no program may get slower).

## add-diagnostic

To add a compiler error, or a tool diagnostic with a code.

A compiler error (`error[type error] ... | help: ...`), where the
checker finds it: `err_begin(pos); err_str(c"..."); err_sym(name);
err_help(c"try ..."); err_end();` (`err_end_soft()` goes on checking).
Templates: `volec query examples diagnostic`. Test:
`tests/run/err_NAME.vl` with `// ERROR: text` lines, the help line
too (`// ERROR: help: ...`).

A tool diagnostic (`error edit.not-source: ...` then `try:` lines):
`let d = diag(c"error", c"tool.code"); buf_str(d, c"...\n");` then
`try_end(try_begin(c"cmd", name, true))`: a command that runs as it is
written. Then its `explain` entry: an `Explain { code, severity,
means, fix, example }` in `crate::tools::explain::tools_table::TOOLS_TABLE`
(or `refactor_table`), `TOOLS_COUNT` and the array's length one more,
in one `edit apply`; the Diagnostics table of `docs/query.md` or
`docs/refactor.md`. `tests/refactor/run.sh` fails on a code without an
entry. Test: a transcript (`tests/query/NAME.q`, `tests/refactor/NAME.t`).

## add-test

To add a test case.

- A program: `tests/run/CATEGORY_NAME.vl` (the category is the name
  up to its first `_`: `std_`, `opt_`, `err_`...), or
  `tests/run/NAME/main.vl` for several modules. Directives in `//`
  comments: `EXPECT:` (stdout, a line each), `STDIN:`, `ARGS:`,
  `EXIT:`, `STDERR:`, `ERROR:` (compiling fails with that message),
  `CHECK:` / `CHECK-NOT:` (the IR), `FLAGS:`; the header of
  `tests/run.sh` lists them all. Cases compile with `--deny-warnings`.
- Run it: `tests/run.sh NAME` (cases whose name holds NAME), with
  `-O 0` and `-O 1` too.
- A tool: a transcript, `$ ARGS` lines and their output:
  `tests/query/NAME.q` (on `tests/query/NAME/main.vl`),
  `tests/refactor/NAME.t` (in a copy of `tests/refactor/NAME/`; `%`
  lines run shell commands); `tests/query/run.sh -u` writes what the
  commands print now (read the diff before keeping it).
- Templates: `volec query examples test`.

## add-subcommand

To add a volec command, or a query command.

A command (`volec NAME ...`): `pub fn run_NAME(argc: i64, argv:
**u8) -> i64` (diagnostics with `diag`, written with `write_diags()`
before it returns), and its line in the chain of
`crate::tools::commands::run_command`: `if streq(word, c"NAME") {
return run_NAME(argc, argv); }` (`batch` runs it too). Its `--help`: a
`Help { cmd: "NAME", text: "..." }` row in `compiler/src/tools/help.vl`
(15 lines at most; `HELP_COUNT` and the array's length one more), and
the command in the list `tests/guide/run.sh` checks `--help` for.
Templates: `volec query examples subcommand` (`run_lint`).

A query (`volec query NAME ...`): its name in `command_name`
(`N_COMMANDS` one more), its branch in `answer`, its line in
`put_usage` and in the `query` row of the help table; `volec query
examples query-command`.

Docs: `docs/query.md` or `docs/refactor.md`, the tables of
`compiler/guide/tools.md` (then `compiler/guide/embed.sh`), the module
table of `compiler/src/tools/README.md`. Test: a transcript (`add-test`).

## add-guide-text

To add a paragraph or an example in the guide.

The guide is `compiler/guide/TOPIC.md` (the topics and their order:
`compiler/guide/topics.txt`). An example is a `tach` block, then an
`out` block with what it prints (an `in` block before it: its stdin; an
`err` block: it must fail to compile); each is compiled and run.
`tests/guide/run.sh -f compiler/guide/TOPIC.md` checks one topic as you
write it; then `compiler/guide/embed.sh`, `bootstrap/bootstrap.sh --dev`
and `tests/run.sh guide`. The core topic has a budget (the test says).

## add-module

To add a module (a file) to a program.

1. `volec edit new-file shapes.vl < text` writes the file and adds
   `mod shapes;` to its parent (`main.vl`); or `volec refactor
   new-module crate::shapes` for an empty one.
2. Items another module uses are `pub`; there they are named
   `crate::shapes::area` or imported: `use crate::shapes::{Shape,
   area};` (`volec fix --only imports` adds the lines a check asks
   for).
3. Items that should move there: `volec refactor move area Shape --to
   crate::shapes` (their uses and imports follow).
4. `volec check`; build with the root, `volec main.vl -o prog`.

`volec guide modules` has the rules (paths, `pub`, `use`).
