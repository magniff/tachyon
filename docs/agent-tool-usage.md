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

