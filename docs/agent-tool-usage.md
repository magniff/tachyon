# How agents worked on tachyon: tools and their uses

A record of every shell command, search and file read the agents made
while building tachyon (0.2 through 0.10, about two days of work by some
thirty agents), classified by what each was for. The point: the common
uses should become compiler queries, so that an agent asks `tachyonc`
instead of reconstructing the answer with `grep`, `sed` and `head`
(see [agents.md](agents.md), items 2 and 3).

Regenerate with `tools/agent-tool-usage.py TRANSCRIPT_DIR > report.md`
(`--csv` writes every classified operation). The numbers below are from
the transcripts up to 0.10.

## What it shows

- **Reading code is most of the work, and it is done blind.** 56% of all
  source operations are `sed -n 'N,Mp'`, `head`, `tail` and file reads of
  line ranges, and another 9% are `grep "fn name" -A30`: an agent wants
  the text of one function or type and gets it by guessing line numbers
  or a number of following lines, often twice (too short, then again).
  **`tachyonc query show NAME`**: the item's exact source (with its doc
  comment, nothing more), by name, from the compiler's own spans.
- **"Who uses this" is the next biggest (17%).** `grep -rn NAME
  compiler/src` returns comments, strings, other things of the same name
  and misses uses through imports. **`tachyonc query refs NAME`** (and
  `callers`, `implementors`): resolved references, file:line and the
  enclosing function.
- **Definitions (2%) and module contents** are small but recur at the
  start of every task. **`tachyonc query def NAME`** and **`tachyonc query
  items MODULE`** (signatures only, like a generated header).
- **Mechanical edits (3%)**, `sed -i` / `perl -pi` / Python rewrites,
  carried the bugs that were hardest to see (a rename that also hit a
  comment, a wrong struct size). **`tachyonc refactor rename`**, and more
  `--fix-*` rewrites in the style of `--fix-imports` and `--fix-unsafe`.
- **Checking compiler output (3%)**: grepping `--emit-ir` and assembly for
  one function. **Filters by function** (`--emit-ir=fn_name`).
- **Counting (4%)** (`wc -l`, `grep -c`): sizes and use counts, which
  `query` can answer exactly.

Beyond reading: about 450 file writes and 260 edits, 1,150 `git` calls,
500 test-runner and 400 compiler invocations. Builds and tests are
already single commands; reading and changing code is not.

## Totals

| tool | calls |
|---|---|
| Bash | 4570 |
| Write | 452 |
| Edit | 264 |
| Agent | 57 |
| Read | 51 |
| SendMessage | 22 |
| ToolSearch | 7 |
| SubagentHandback | 5 |
| AskUserQuestion | 4 |
| Monitor | 3 |
| TaskStop | 2 |

Programs run from the shell (every simple command of every command line):

| program | runs |
|---|---|
| `grep` | 3310 |
| `head` | 2585 |
| `sed` | 1937 |
| `git` | 1148 |
| `tail` | 1142 |
| `cat` | 1046 |
| `python3` | 916 |
| `echo` | 782 |
| `do` | 734 |
| `done` | 726 |
| `for` | 555 |
| `run.sh` | 510 |
| `cd` | 482 |
| `fn` | 457 |
| `tachyonc` | 410 |
| `cc` | 385 |
| `ls` | 329 |
| `awk` | 300 |
| `sh` | 265 |
| `n` | 239 |
| `wc` | 237 |
| `cargo` | 226 |
| `printf` | 195 |
| `pub` | 167 |
| `sort` | 160 |

## Reading and editing tachyon source: 2659 operations

| purpose | operations | share | what could answer it |
|---|---|---|---|
| find-definition: where is NAME defined | 59 | 2% | tachyonc query def NAME (file:line, signature) |
| find-references: who uses NAME | 459 | 17% | tachyonc query refs NAME / callers NAME |
| list-items: what does this module or file contain | 8 | 0% | tachyonc query items MODULE (signatures, no bodies) |
| show-item: show the source of a function or type by name | 234 | 9% | tachyonc query show NAME (the item's source, with its doc comment) |
| read-range: show lines N..M of a file | 1497 | 56% | tachyonc query show NAME (the item's source) |
| extract-section: a section of a document between two markers | 32 | 1% | (docs: tachyonc doc TOPIC) |
| count: how many matches or lines | 97 | 4% | tachyonc query refs --count / --stats |
| mechanical-edit: a rename or rewrite with sed/perl/python | 80 | 3% | tachyonc refactor rename / fix-* rewrites |
| check-output: inspect what the compiler emitted (IR, asm) | 71 | 3% | --emit-ir / --emit-mir / -S, with filters by function |
| other-source: other reads of source | 122 | 5% |  |

## Examples per purpose

### find-definition

- `Bash:grep` `grep -n "pub fn buf_\w*" compiler/src/base.tach`: Read operand helpers, printing helpers
- `Bash:grep` `grep -n "fn simplify_function" compiler/src/opt.tach`: Check bitwise-not syntax
- `Bash:grep` `grep -n "^fn synth_binary" compiler/src/31_check.tach`: Read synth_binary and range pattern handling
- `Bash:grep` `grep -rn "struct HMap" compiler/src/`: Interner internals and HMap location
- `Bash:grep` `grep -n "fn bounds_check" compiler/src/lower.tach`: Read IR index lowering and bounds_check
- `Bash:grep` `grep -n "fn max_i64" compiler/src/*.tach`: Add frame-block marking to regalloc
- `Bash:grep` `grep -n "fn is_commutative" compiler/src/*.tach`: Rebuild with phi-hint override; measure
- `Bash:grep` `grep -n "pub fn mx_select" compiler/src/mc_x86_64.tach`: Read start of emit_select and locate mx_select

### find-references

- `Bash:grep` `grep -v '^ M tests/run/\`: Check grammar branch progress
- `Bash:grep` `grep -v 'tests/run/\`: Check grammar branch progress again
- `Bash:grep` `grep -n "0.3.0" bootstrap/releases.toml compiler/src/90_main.tach`: Static checks and launch both chains for 0.3
- `Bash:grep` `grep -rln "\.len" tests/run/opt_loop*.tach tests/run/opt_ranges.tach bench/stencil.tach`: Find u64 length uses in 2a tests
- `Bash:grep` `grep -n "\.len" tests/run/opt_loop_transforms.tach`: Show surrounding test code
- `Bash:grep` `grep -n "0.3.0" compiler/src/90_main.tach README.md compiler/README.md`: Fast-forward and find version references
- `Bash:grep` `grep -n "0.4.0" docs/releases.md bootstrap/releases.toml compiler/src/90_main.tach README.md`: Bump version to 0.4.0, add release entries and notes
- `Bash:grep` `grep -n "std" $S/g.tach`: Run generics program at -O0/-O2 and a multi-error file

### list-items

- `Bash:grep` `grep -n "^fn " compiler/src/21_parser.tach`: Read AST and parser function list
- `Bash:grep` `grep -n "^fn " compiler/src/41_target.tach compiler/src/41_abi.tach compiler/src/42_arm64.tach compiler/src/43`: List backend helper functions
- `Bash:grep` `grep -n "^fn " compiler/src/40_gen.tach compiler/src/41_arm64.tach compiler/src/90_main.tach`: Read arm64 backend structure
- `Bash:grep` `grep -n "^fn " compiler/src/52_mc_arm64.tach compiler/src/53_mc_x86_64.tach`: Outline machine layers and copy
- `Bash:grep` `grep -n "^fn " f16.tach`: Find differing function in seed 16
- `Bash:grep` `grep -n "^struct" compiler/src/*.tach`: List compiler structs
- `Bash:grep` `grep -n "^pub fn" compiler/src/target.tach`
- `Bash:grep` `grep -n "^    fn " compiler/src/base.tach`

### show-item

- `Bash:grep` `grep -n "fn avail_kill_call" -A30 compiler/src/gvn.tach`: Read call-kill logic in GVN and LICM
- `Bash:grep` `grep -n "fn call_may_write" -B3 -A30 compiler/src/licm.tach`: Read call-kill logic in GVN and LICM
- `Bash:grep` `grep -n "fn is_private_slot" -A15 compiler/src/*.tach`: Read call-kill logic in GVN and LICM
- `Bash:grep` `grep -n "pub struct FnInfo" -A25 compiler/src/types.tach`: Inspect attribute parsing and FnInfo
- `Bash:grep` `grep -n "pub fn calls_returns_twice" -A25 compiler/src/regalloc.tach`: Read returns-twice and global helpers
- `Bash:grep` `grep -n "pub fn fn_is_global" -A10 compiler/src/gen.tach`: Read returns-twice and global helpers
- `Bash:grep` `grep -n "fn verify_func" -A12 compiler/src/ir.tach`: Find helper symbols for the new module
- `Bash:grep` `grep -n "fn print_ir_func" -A20 compiler/src/ir.tach`: Read operand helpers, printing helpers

### read-range

- `Bash:sed` `sed -n 205,226p tests/run.rs`: Check whether the run.rs match error is real
- `Bash:head` `head -80 tests/run.sh`: Inspect built compiler and its CLI usage
- `Bash:cat` `cat bench/sieve.tach`: Locate cached release binaries; show sieve
- `Bash:sed` `sed -n 1,20p bench/run.sh`: Host-independence check and bench usage
- `Bash:sed` `sed -n 28,42p tests/run/opt_ranges.tach`: Show surrounding test code
- `Bash:sed` `sed -n 34p tests/run/opt_ranges.tach`: Fix test, rebuild chain, rerun suite
- `Bash:cat` `cat bench/collatz.tach`: Compare collatz asm 0.3.0 vs 0.4
- `Bash:cat` `cat > $S/g.tach <<HEREDOC`: Dev chain and a hand-written generics program

### extract-section

- `Bash:grep` `grep -n "#\[cold\]" tests/run/*.tach`: Import fn_attr_cold; find cold attribute tests
- `Bash:awk` `awk '/^fn check_expr_inner/,/^}/' compiler/src/31_check.tach`: Read check_expr_inner and collect_names
- `Bash:awk` `awk '/^fn collect_names/,/^}/' compiler/src/31_check.tach`: Read check_expr_inner and collect_names
- `Bash:awk` `awk '/^fn ma_cmp\(/,/^}/' compiler/src/52_mc_arm64.tach`: Read comparison code in fold and backends
- `Bash:awk` `awk '/^fn ma_cmp_branch\(/,/^}/' compiler/src/52_mc_arm64.tach`: Read comparison code in fold and backends
- `Bash:awk` `awk '/^fn mx_cmp\(/,/^}/' compiler/src/53_mc_x86_64.tach`: Read comparison code in fold and backends
- `Bash:awk` `awk '/^fn mx_cmp_branch\(/,/^}/' compiler/src/53_mc_x86_64.tach`: Read comparison code in fold and backends
- `Bash:awk` `awk '/^fn a64_compare\(/,/^}/' compiler/src/42_arm64.tach`: Read -O0 compare paths

### count

- `Bash:wc` `wc -l compiler/src/41_target.tach compiler/src/42_arm64.tach compiler/src/43_x86_64.tach`: Size of target layer and backends
- `Bash:wc` `wc -l compiler/src/4*.tach`: Check 0.1 work progress again
- `Bash:wc` `wc -l compiler/src/*.tach`: Create release-0.2 branch, peek at codegen structure
- `Bash:wc` `wc -l $S/v01.tach`: Compile-time comparison on the 0.1.0 compiler source
- `Bash:wc` `wc -l $S/compiler/src/*.tach`: Compare -O0 compile time on identical inputs
- `Bash:wc` `wc -l examples/*`: Create branch and list examples
- `Bash:grep` `grep -c "::\*" compiler/src/*.tach 2>/dev/null`: Check 0.8 progress
- `Bash:wc` `wc -l compiler/src/inline.tach compiler/src/opt.tach compiler/src/gvn.tach compiler/src/licm.tach compiler/src`: Reset worktree onto phase 1 and survey files

### mechanical-edit

- `Bash:sed` `sed -i '' '34s/while i < s.len {/while i < s.len as u64 {/' tests/run/opt_ranges.tach`: Fix test, rebuild chain, rerun suite
- `Bash:sed` `sed -i '' '29s/c"0.3.0"/c"0.4.0"/' compiler/src/90_main.tach`: Bump version to 0.4.0, add release entries and notes
- `Bash:sed` `sed 's/^extern fn \(.*\)$/extern "C" { fn \1 }/' $S/v01.tach > $S/v01-new.tach`: Compile-time comparison on the 0.1.0 compiler source
- `Bash:sed` `sed -i '' '113s/c"0.5.0"/c"0.6.0"/' compiler/src/main.tach`: Bump to 0.6.0, add release notes, rebuild
- `Bash:sed` `sed -e 's#^"\$C" --target "\$T" examples/httpd.tach -o "\$W/httpd".*#gcc -o "$W/httpd" /in/httpd.o`: Run httpd and life smoke test inside Debian
- `Bash:sed` `sed -i '' "${L}s/c\"0.7.0\"/c\"0.8.0\"/" compiler/src/main.tach`: Bump to 0.8.0, commit, tag, fresh clone, start colima
- `Bash:perl` `perl -pi -e 's/subst\(m, 0, 0\)/subst(m, 0 as *i64, 0)/' compiler/src/15_cpp.tach`: Fix null pointer arg and rebuild
- `Bash:perl` `perl -pi -e 's/strtoull\(digits, &end, base\)/strtoull(digits, &end, base as i32)/' compiler/src/15_cpp.tach`: Fix strtoull base type and rebuild

### check-output

- `Bash:tachyonc` `target/tachyonc -S $S/bad.tach -o $S/bad.s`: Reproduce error output for each invocation form
- `Bash:tachyonc` `target/tachyonc --emit-ir bench/interp.tach -o target/interp.ir`: Inspect interp's optimized IR
- `Bash:tachyonc` `target/tachyonc --emit-ir bench/stencil.tach -o target/stencil.ir`: Check promotion, bounds checks, and attrs
- `Bash:tachyonc` `target/tachyonc --print-attrs bench/stencil.tach -o target/st.s`: Check promotion, bounds checks, and attrs
- `Bash:tachyonc` `target/tachyonc --emit-ir tests/run/opt_promote.tach -o target/p.ir`: Inspect promotion test IR
- `Bash:tachyonc` `target/tachyonc --print-attrs compiler/src/main.tach -o target/s3.s 2> target/attrs.txt`: Fixpoint check and attribute statistics
- `Bash:tachyonc` `target/tachyonc --emit-ir tests/run/opt_heap_to_stack.tach -o target/h.ir`: Build and run heap-to-stack test
- `Bash:tachyonc` `target/tachyonc --emit-ir tests/run/opt_devirtualize.tach -o target/d.ir`: Run devirtualization test at -O0 and -O2, inspect IR

### other-source

- `Bash:python3` `python3 -I $S/timeit.py 7 target/tachyonc -O0 compiler/src/main.tach -o $S/s0.s`: Quiet benchmarks and compile-time measurements
- `Bash:awk` `awk -F: '{s+=$2} END {print "globs left in compiler/src:", s}'`: Check 0.8 progress
- `Bash:python3` `python3 -I $S/timeit.py 7 $c -O$o -c compiler/src/main.tach -o $S/self.o`: Benchmarks and compile times vs 0.9.0
- `Bash:python3` `python3 -I - compiler/src/inline.tach <<HEREDOC`: Rewrite the inliner policy with cost model and rounds
- `Bash:awk` `awk 'length==0' compiler/src/15_cpp.tach`: Inspect raw bytes of file start
- `Bash:awk` `awk -v seed=7 -v cfile=p7.c -v tfile=p7.tach -v import=1 -v hfile=p7.h -f ../../tests/abi/gen.awk`: Make extern blocks conditional and try import mode
- `Bash:perl` `perl -0pi -e 's/\$ tachyonc --tokens file\.tach        # the token dump/\$ tachyonc --emit-imports prog.tach -`: Finish docs, usage, README; commit
- `Bash:perl` `perl -0pi -e 's/\[--emit-ir\] \[--verify-ir\] <file\.tach>\.\.\. \[-o out\.s\]/[--emit-ir] [--verify-ir] [--em`: Finish docs, usage, README; commit


## 0.11: with the compiler's tools

From the query-first hook going live (2026-10-14, 10:33, when `tachyonc
query` first answered) to the 0.11.0 release, about 3.5 hours of agent
work (the toolkit itself, the 0.11 performance work, the release).
Sources: the hook's log (`tools/agent-tool-usage.py --hook-log
.git/agent-tools.jsonl`) for reads, the transcripts for edits.

**Reading and searching source.** 234 shell attempts or queries:

| how | commands | share |
|---|---|---|
| `tachyonc query` (show 84, items 30, refs 19, def 7, stats 5, callers 3, deps 2) | 150 | 64% |
| shell, with a `# no-query:` reason | 61 | 26% |
| shell, blocked by the hook (then a query or an escape) | 23 | 10% |

Besides these, 49 Read-tool reads of `.tach` files (logged, not
blocked). Over all the transcripts (0.2 to 0.11, `tools/agent-tool-usage.py
TRANSCRIPT_DIR`), 56% of source operations are still line-range reads;
the hook period is where that changed.

**Editing source** (the compiler's tree, not scratch copies):

| how | edits | share |
|---|---|---|
| `tachyonc edit`, `refactor`, `fix`, `undo` (written) | 15 | 8% |
| shell: Python and `sed -i` rewrites | 117 | 65% |
| Write (mostly new modules) | 28 | 16% |
| Edit | 20 | 11% |

Also 54 dry runs and plans, and 39 written edits of scratch copies while
the refactorings were built and tested. Edits went through the tools
where one fit the change (a whole item, a signature, imports, a
version); everything inside an item went through Python or `sed`.

**Why the shell: the 61 escape reasons, by cause.**

| cause | count |
|---|---|
| not compiler source: tests' directives (`// CHECK`, `// EXPECT`), fixtures, generated programs, scratch copies, a shell script | 19 |
| reading back an edit just made with Python or `sed` | 17 |
| a module's `use` lines, header comment, `extern` block or `mod` list | 12 |
| lines of a long item, or around a reported line or a section comment | 10 |
| merge conflicts (a file with markers does not parse) | 3 |

**Feedback** (`tools/agent-feedback`, 33 entries, one a test):

| cause | count |
|---|---|
| module text no query or edit reaches: `use` blocks, header and section comments, `extern` blocks, line ranges, whole small files | 12 |
| query precision: types at a position, reads vs writes of a field, several names at once, `FILE:LINE`, `--root` in `try:` lines (some fixed in 0.11) | 7 |
| refactoring output: imports not merged, long paths, `fix --only unsafe` per statement, `split`'s part names, one-hunk diffs, `--type` without a new default | 6 |
| the hook: false positives (patterns, writes, generated programs, scripts) | 5 |
| merge conflicts | 2 |

**The top gaps, for 0.13:**

1. **Module text by name**: `query show`/`edit` of a module's `use`
   block, header comment, `extern` blocks and `mod` list; comments and
   section markers findable; `query show FILE:A-B` for a range
   (escapes 22, feedback 12).
2. **Edits inside an item** (replace text anchored in NAME, or lines of
   it), with the diff printed: the 117 Python and `sed` rewrites and the
   17 read-backs that checked them.
3. **Test files and other programs**: directives shown by `query`, a
   file outside the compiler's tree answered with its own root (and the
   `try:` line saying so), the hook counting only reads of compiler
   source (19 escapes, 5 feedback).
4. **Query precision**: the type at a position, references by kind
   (read, write, literal), merge-conflict regions.
5. **Refactoring output in the codebase's style**: new imports merged
   into existing `use` lines with short paths, `unsafe` at function
   level, named split parts.

## 0.11: why edits bypassed the tools

Of the edits agents made to `.tach` files after the query-first hook went
live, about 20% of the edits to existing compiler source went through
`tachyonc` (the headline "8%" also counted new files, test fixtures and
agents exercising the new tools on scratch programs). The rest were small
changes inside one function (two to five lines: a condition, a
statement, an expression), which the tools could only do by replacing a
whole item. Agents read the function with `query show`, then patched it
with a Python `s.replace(OLD, NEW)` behind an `assert`, cheap in tokens
but unchecked, unjournaled and without undo, or with `sed -i 'Ns/.../'`
on a line number from a compiler error, fragile once lines move.

So for 0.12: `tachyonc edit patch NAME|FILE:LINE --old TEXT --new TEXT`
(an anchor unique within one item, atomic, journaled, undoable, the file
never read whole), `edit insert --in NAME --after ANCHOR`, the hook
steering Python and `sed -i` rewrites of compiler source to them, and the
metric counted on edits to existing compiler source only.

## 0.12: edits inside an item, and the edit metric

Gap 2 above is `tachyonc edit patch` and `edit insert --in`
([refactor.md](refactor.md)); the hook now blocks shell rewrites of
compiler source (`# no-tool:` to go around it) and logs every tool run
with whether it wrote, and Edit/Write with whether the file existed.

`tools/agent-tool-usage.py --hook-log` reports **edits to existing
compiler source** (compiler/src, compiler/std) on their own: tool edits
(`tachyonc edit`, `refactor`, `fix`, `rewrite`, `undo`, written, on the
compiler's source) against shell rewrites that ran (`sed -i`, `perl -pi`,
Python) plus Edit and Write of existing compiler files. The share of the
tools is the headline number. New files, test fixtures, docs, scratch
programs (target/, /tmp), dry runs and blocked rewrites are listed apart
and not counted. Logs from before 0.12 have no tool runs and no
existence for Write, so the number is meaningful from 0.12 on.

## 0.12: the reorganization through the tools

The 0.12 reorganization of `compiler/src` (2026-10-14, 15:37 to 17:00)
was made with the tools, in three steps: phase 1, one agent moving the
modules into six folders by phase; phase 2, six agents in parallel
worktrees, each splitting one area's files over 1,000 lines; then the
clean-up (the tools the agents asked for, then the source tidied with
them). Sources: the agents' reports, and the hook's log for each window
(`tools/agent-tool-usage.py --hook-log`, the log cut by time).

**Edits to existing compiler source, through `tachyonc`:**

| step | agent | tool share | how |
|---|---|---|---|
| phase 1 | the folders | 100% (11 edits) | one `refactor --script` of `move-module`s, then `edit` and `fix` |
| phase 2 | front-syntax (parser, cpp, cimport) | 100% | `refactor split`, `edit patch` |
| phase 2 | middle (ir, lower, range, vectorize) | ~100% | `refactor split`, `edit patch` |
| phase 2 | objects, gen0, base | ~100% | `refactor split`, `edit patch` |
| phase 2 | back-codegen (emit, isel, regalloc, mc_*) | 97% | `refactor split`, `edit patch`; the rest Edit |
| phase 2 | tools (query, edit, patch, rewrite, plan, refactor_shape) | 94% | `refactor split`, `edit patch`; the rest Edit |
| phase 2 | front-check (check, patterns, generics, modules) | 15% | its parts' header comments and moved banners, edited with the Edit tool: no tool reached a module's header or `use` lines |
| clean-up | the tools, then the source | 96% (22 of 23) | `fix --only reexports` (805 imports and paths, 291 re-exports, one edit), `fix --only tidy-imports` (126 `use` items), `fix --only unused`, the unused items deleted in one script, comments with `edit patch FILE`; the one shell edit, a Python rewrite of a new file before its `mod` line existed |

Over phase 2 the log has 103 tool edits and 34 Edit-tool edits (most of
them front-check's), and 186 queries (`text` 84, `show` 38, `deps` 16,
`items` 14, `refs` 10, `stats` 7). Its "shell rewrites" (3 in phase 1, 3
in phase 2) were none of them compiler source: `sed -i` on
`compiler/std/embed.sh`, test scripts and scratch files under target/ or
/tmp, and a feedback message quoting `sed -i`; the hook of 0.12 no longer
counts them. Its records then had one agent id for all six agents, so
the per-agent shares are the agents' own counts.

**The recurring shortfalls** (42 feedback entries in phases 1 and 2), and
what 0.12 fixed:

| shortfall | entries | 0.12 |
|---|---|---|
| `split` rewrote every importer outside the module (so parallel splits touched each other's files), and the hand-written `pub use` then clashed with the imports `split` had added | 8 | `split --reexport`; `fix --only reexports` removes such re-exports later |
| a module's `use` lines and header comment out of the tools' reach: `edit patch MODULE::use`, `edit replace`, `FILE:LINE` on a `use` line, the root's `main::header`; a new part with no header | 13 | `MODULE::use`, `MODULE::header` (and `main::`) as targets of `edit patch`, `replace`, `insert`, `delete`; `split --header`, or the part's banner |
| imports left untidy by `move`, `split` and `fix`: new lines not merged, names unsorted, lists not rewrapped, ragged lines | 6 | `fix --only tidy-imports`; `move` and `split` tidy what they edit |
| the layout of moved code: adjacent constants and statics double-spaced, banners following the last items of their group or left over unrelated ones | 6 | adjacent items stay together; a banner goes where most of its group goes |
| the hook and its report: writes judged by every path a command names (a doc, a scratch helper, a quoted `sed`), one agent id for all; `tools/agent-feedback` refused in worktrees (it ran git) | 6 | judged by the files written; agent id and worktree logged; no git run |
| `edit patch` with multi-line OLD: its lines must be whole lines | 3 | (0.13) |
| `fix --only unused` and `query unused` counted the root's imports that others import through as unused | 1 | fixed |
| no query lists a module's banners; `mod` and `use` lines inserted between a comment and its item; an extern block's moved functions in a new block at the end | 3 | (0.13) |

Found in the clean-up itself: `edit patch` removing whole lines between
two blank lines left both (fixed: one goes with them); `fix --in MODULE`
reaches the module's children for unused imports but not for missing
ones (0.13).

**The remaining gaps, for 0.13:**

1. `edit patch` whole-line rules: a multi-line OLD whose last line is a
   prefix, matched or said plainly; `FILE:LINE` on a line outside any
   item (a `use`, a comment) taken as that file's region.
2. Comments as first-class: section banners listed by `query` (`query
   items --banners`), moved and edited by name; the comment above an item
   kept with it when imports or `mod` lines are added.
3. `--in` meaning the same subtree for every fix; `split --plan`'s part
   names from the banners.
4. Per-agent numbers from the log itself (0.12's hook logs the agent id
   and worktree; the report prints a table per agent).

## 0.13: the tools, built with the tools

0.13 (2026-10-14, 17:24 to 19:53) was made by six agents in parallel
worktrees, one per area (edit, query, the cache, refactor, fmt and
explain, the guide), then one integrating them (the merges, `tachyonc
fmt --all`, two files split that formatting had grown past 1,000 lines).
Source: the hook's log from the 0.12.0 release on
(`tools/agent-tool-usage.py --hook-log`, the log cut by time); 0.12's
hook logs the agent id, so the table per agent is the report's own.

**Edits to existing compiler source, through `tachyonc`: 151 of 182,
83%.**

| agent | tools | shell | Edit | Write | tool share |
|---|---|---|---|---|---|
| edit | 14 | 0 | 0 | 0 | 100% |
| query | 27 | 1 | 5 | 0 | 82% |
| the cache | 51 | 1 | 0 | 1 | 96% |
| refactor | 33 | 0 | 6 | 0 | 85% |
| fmt and explain | 20 | 1 | 11 | 0 | 62% |
| the guide | 4 | 0 | 0 | 0 | 100% |
| the integration | 2 | 3 | 2 | 0 | 29% |

The tools: `edit` 127, `fix` 13, `refactor` 6, `undo` 5. Of the 31
other edits, 26 were to files new in 0.13 that the agent had written
itself in the same session (`tools/query/sections.tach`, `cache.tach`,
`tools/fmt/`, `refactor_shape/extract.tach` and `inline.tach`): drafts,
some before their `mod` line existed, where the hook counts a file as
existing once written. On the files that existed before they began,
every edit of the six feature agents went through the tools. The
integration's five: two merges whose conflict markers left
`main.tach` and others unparseable (Python, as the Edit tool would),
ten entries of the explain table at once (Python), and the banner that
`refactor split` left behind in `back/enc_arm64/mod.tach` moved by hand
(Edit, two files).

Queries: 278 (`show` 133, `text` 39, `refs` 22, `items` 21, `def` 12,
`stats` 10, `unused` 7, `grep` 2); 11 shell reads blocked by the hook,
17 gone around it (`# no-query`): 10 of them text searches (string
literals, banner styles, extern declarations, a static's initializer),
which `query grep`, built in the same hours, now answers; the rest
searches of a tree mid-merge, which does not parse, a comparison with
another branch, and lines around a banner or a table.

**The shortfalls** (32 feedback entries), and what 0.13 did:

| shortfall | entries | 0.13 |
|---|---|---|
| `fix --in MODULE` not reaching the children for missing imports | 3 | fixed (the edit branch; the others branched before it) |
| `edit patch` with an OLD that ends inside a line; multi-line pairs on the command line refused by the harness | 3 | fixed: partial-line pairs, `--pairs FILE` |
| `edit insert` and `delete` next to a run of one-line items (`mod`, `static`, `const`) adding or leaving a blank line | 4 | (0.14) |
| `fix --only imports`: a same-named static from another module chosen; no import of, nor `help:` for, std types (`use std::Buf`); a private static not offered as `pub` plus import; a relative and a `crate::` spelling of one path not merged | 6 | where it puts a new line: fixed (an edit tidies the `use` runs it touches); the rest (0.14) |
| `edit insert` of a new item that needs imports fails `edit.breaks` (`--no-check`, then `fix`) | 1 | (0.14) |
| `refactor split --items` of a banner's section leaving the banner behind | 1 | (0.14) |
| `edit patch FILE:LINE` on a comment line between items: no item | 1 | (0.14) |
| no tool for merge conflicts in `.tach` files (they do not parse; `query text` only) | 1 | (0.14) |
| unwrapping a block (the opposite of `edit wrap`); `edit delete` of one NAME only; `MODULE::extern` not an edit target | 3 | (0.14) |
| arguments and `try:` lines: `query show FILE --root R`, `query stats` and `query unused` of one module without its children, `edit patch FILE:LINE` outside the default root, `query.ambiguous` dropping `--old`/`--new`, `undo` outside a repository, `tests/query/run.sh -u` moving comments, the harness refusing shell variables | 9 | (0.14) |

**The remaining gaps, for 0.14:**

1. `edit insert --imports`: a new item's imports added in the same
   checked edit.
2. Comments outside items as targets: `edit patch FILE:LINE` on a banner
   or comment line; `split --items` moving a section's banner with it.
3. Merge conflicts: `query conflicts FILE` and `edit resolve FILE
   --ours|--theirs|--both N` on files that do not parse.
4. `fix --only imports` for std types and private items; one-line items
   kept together by `edit insert` and `delete` as `move` keeps them.

## 0.14: the language through the tools, and the first agent eval

0.14 (2026-10-14, 20:00 to 22:56) was made by 11 agents in parallel
worktrees:

- phase 0, the interfaces;
- in parallel, std, the diagnostics, tools part 1 and part 2;
- the language tracks: T1 closures, T2 associated types, T3 iterators,
  T4 the optimizer, T5 the tools for closures;
- the integration.

Beside them, five agents wrote the agent eval: the runner and the task
authors. The 0.13 baseline ran on it (Haiku and Sonnet, 12 tasks; see
[eval/0.13-findings.md](eval/0.13-findings.md)).

Sources:

- the hook's log from 20:00 on: 1,360 records, without the 0.13
  release agents;
- the 17 agents' transcripts (aggregates only);
- the eval transcripts.

The details, the sequences of calls and the ranked gaps are in
[tool-gaps-014.md](tool-gaps-014.md).

**Edits to existing compiler source, through `tachyonc`: 225 of 266,
85%.**

| agent | tools | shell | Edit | Write | tool share |
|---|---|---|---|---|---|
| phase 0 | 36 | 0 | 1 | 0 | 97% |
| tools part 2 | 18 | 0 | 0 | 0 | 100% |
| diag | 39 | 0 | 0 | 0 | 100% |
| T4 optimizer | 41 | 1 | 2 | 0 | 93% |
| tools part 1 | 27 | 1 | 1 | 0 | 93% |
| T5 tools for closures | 21 | 0 | 0 | 0 | 100% |
| T1 closures | 14 | 2 | 0 | 1 | 82% |
| T2 associated types | 10 | 3 | 4 | 1 | 56% |
| T3 iterators | 11 | 4 | 6 | 1 | 50% |
| std | 4 | 2 | 10 | 0 | 25% |
| the integration | 4 | 1 | 0 | 0 | 80% |

How the table was counted:

- **The tool edits** come from the transcripts. The hook's report
  (`--hook-log`) counts 91 of 131 (69%). The difference: five agents
  ran a copy of the compiler (`T=target/tc0; $T edit ...`), because
  their own builds replaced `target/tachyonc`. The hook did not
  recognize these, so 51 tool edits and about 280 queries are missing
  from its log.
- **Edit** comes from the transcripts too; **shell rewrites and Write**
  come from the hook, which knows whether a written file existed.

The low shares are std's and its users':

- The std agent edited `compiler/std/std.tach` with the Edit tool
  (10 edits). No query or edit reaches std as a program ("std.tach is a
  separate program root").
- T3 drafted std's iterators in staged copies and edited them with
  Python.
- T2 made "several related additions" across items in one Python
  script, where `edit patch` takes one item per call.

**Queries:** 922 in the transcripts (`show` 391, `text` 131, `grep`
121, `refs` 113, `items` 93, `def` 42, `type` 13), of which the hook
logged 467.

**Blocked and escaped:**

- 43 shell reads blocked (`grep` 20, `cat` 13, `sed` 5, `head` 4).
- 63 went around the hook with `# no-query`:
  - 26 read test fixtures, eval tasks and docs, which are not the
    program;
  - 8 were merge conflicts;
  - 7 were std;
  - 6 read whole modules past `query text`'s 200 lines;
  - 6 were text searches across worktrees;
  - the rest were scratch files.
- 14 shell edits went around it with `# no-tool`: std 6, conflict
  resolution 3, several edits at once 2, the agent's own new file 2,
  scratch 1.

**Tool errors:** 102 of the 995 calls that ran a tool (10%). 75% of
them were retried at once with the tool, and 11 were given up for Edit,
Write or a shell rewrite. The codes: `query.no-match` 31, `edit.breaks`
25, `edit.usage` 15 (`--help` refused, a second TARGET), `undo.empty`
9, `patch.no-match` 8, `fmt.unformatted` 8, `query.no-root` 5.

**The shortfalls** (36 feedback entries), and what 0.14 did:

| shortfall | entries | 0.14 |
|---|---|---|
| tools on a user's program: `undo` and `query diff` need git; a local cannot be renamed; renaming a field rewrote a comment's same-named parameter; `move` writes `use crate::...` where the file says `use catalog::...` | 6 | fixed (undo without git, locals, precise mentions, import paths in the file's style) |
| language and diagnostics met by the eval authors: `const` of `[u8]`, no stdin reader, privacy errors reported late and without a fix, no did-you-mean for methods, a module and a fn of one name, a literal not typed from the other branch | 6 | fixed (std, diag) |
| `edit patch` targets: a comment line between items, a banner by `MODULE::section`, a `mod` line, a file outside the default root | 4 | between items fixed; the rest (0.15) |
| imports: a new item or patch needing imports fails `edit.breaks`; `fix --only imports` misses a private parent's fn and a bare enum variant | 4 | edits add the imports their text needs; `fix` (0.15) |
| `edit patch` UX: one item per call; an ambiguous OLD suggesting the wrong occurrence first; `edit.breaks` not naming the error | 3 | (0.15: tool-gaps-014 gaps 2, 5) |
| `tests/query/run.sh -u` moving `##` comment lines of a passing transcript | 3 | (0.15) |
| std as a program: `query grep --root compiler/std/std.tach` finds nothing; a std item not found unless the program uses std | 2 | (0.15: gap 4) |
| `fix --in` refusing `./catalog.tach` and `front::check::mod` | 2 | (0.15: gap 6) |
| the hook: an alternation glued into one name; `-o` of a compile seen as a Python write target | 2 | the first fixed |
| `split --items` leaving a banner behind; merge conflicts out of reach; uses of a C-string const missing from `refs`; `query items` with no argument listing modules; the default root (a note) | 5 | the banner fixed; the rest (0.15) |

**In the eval**, the tools condition (the tools table in the prompt,
no guide) was the costliest:

| condition | Haiku | Sonnet |
|---|---|---|
| tools | 11.5M | 3.35M |
| bare | 7.9M | 2.28M |
| both | 7.4M | 2.09M |
| guide | 7.3M | 2.03M |

- **The tools won where they were built to:** renames and moves
  (10-refactor: Sonnet 105k tokens, 163k in Rust), a new variant
  (Sonnet 120k against 196k with the guide), compile errors across
  files.
- **They lost on programs written from a spec:**
  - The agents looked std up through the tools, which cannot show it
    (`query.no-file: cannot read 'std'`), or ran `strings` on the
    binary.
  - They wrote 56 probe programs to learn what compiles, against 3–4
    with the guide.
  - Each new item went into a file and then through `edit replace <
    FILE`, one call per item.

**The remaining gaps, for 0.15** (ranked in
[tool-gaps-014.md](tool-gaps-014.md)):

1. `query context NAME --budget N`: definition, body, callers, callees'
   signatures and types in one sized answer. 89 dev pairs of `query
   show > query show`.
2. Several edits, one checked call: `edit patch --pairs FILE` with `@@
   TARGET` blocks, and `edit apply FILE` (items replaced or inserted by
   name).
3. Feedback without calls: a PostToolUse hook that checks after every
   Write or Edit of a `.tach`, and builds that print `check`'s lines.
   124 eval checks came right after a write.
4. std in every program's queries, std's files as edit targets, and
   `tachyonc try 'STATEMENTS'` for probing.
5. `edit.breaks` that points to the refactoring that fits; every
   spelling of a name the tools print, accepted, with did-you-mean;
   `--help` everywhere; `query conflicts` and `edit resolve`; a tools
   binary the agent's own builds do not replace.
