#!/bin/sh
# (0.18.1) The statics that code generation's tasks may write
# (docs/optimizer.md, "0.18.1: threads", "Why there is no data race"):
# the functions middle::parallel::run_task reaches (query callees
# --transitive) and, for every static of the compiler, its writes and
# borrows in them (query refs; a method call that changes it, X.push(..),
# and an address taken, &X, count) are listed, and each static found must
# be one below, with the reason it is no race. A new one fails: move it
# into middle::ctx::FnCtx, make it before the tasks run
# (parallel::prepare_tasks), or join it between phases. The same for the
# join (parallel::join_task: the assembler, beside the tasks): a static
# it writes that a task reads or writes must be one of JOINED below; and
# for -O0's assembler thread (objfile::assemble_bytes, beside gen0's code
# generation, gen_function and asm_hand_over on the main thread): a static
# one side writes that the other touches must be one of ASSEMBLER below.
#
# usage: tests/threads_writes.sh [-c COMPILER]

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/tachyonc"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac

# static <TAB> why it is no race
ALLOWED='middle::inline::FN_SIZE	the task'"'"'s own function'"'"'s entry; others read a lower level'"'"'s
middle::inline::FN_RT	the task'"'"'s own function'"'"'s entry (finish_component_function)
middle::inline::FN_DECIDERS_START	the task'"'"'s own function'"'"'s entry
middle::inline::FN_DECIDERS	the task'"'"'s own function'"'"'s entry
middle::opt::DEFERRED	the task'"'"'s own function'"'"'s entry
middle::ir::IRFUNCS	the task'"'"'s own function'"'"'s entry (ir_save, ir_free_func, tail recursion)
middle::ipo::FN_ATTRS	the task'"'"'s own component'"'"'s entries
middle::ipo::FN_NOCAPTURE	the task'"'"'s own component'"'"'s entries
middle::ipo::FN_ATTRS_DONE	the task'"'"'s own component'"'"'s entries
middle::parallel::COMP_GROWTH	the task'"'"'s own component'"'"'s entry, read between levels
middle::parallel::COMP_INLINED	the task'"'"'s own component'"'"'s entry, read between levels
middle::parallel::FN_CONSTS	the task'"'"'s own function'"'"'s list; others read its entries made in earlier phases, which never move (chunks)
middle::parallel::FN_TEXT	the task'"'"'s own function'"'"'s entry, read at the join
middle::gvn::MEMCPY_SYM	made by prepare_tasks; the lazy branch never runs in a task
middle::ipo::MALLOC_SYM	made by prepare_tasks
middle::ipo::CALLOC_SYM	made by prepare_tasks
middle::ipo::FREE_SYM	made by prepare_tasks
gen0::target::RT_PANIC_SYM	made by prepare_tasks
front::effects::builtin::TABLE	filled by prepare_tasks (c_class)
base::STRESS_GROW	read by prepare_tasks (stress_grow)
middle::egraph::P_KIND	the rules, parsed by prepare_tasks (init_rules)
middle::egraph::P_OP	the rules
middle::egraph::P_COND	the rules
middle::egraph::P_A	the rules
middle::egraph::P_B	the rules
middle::egraph::P_VAL	the rules
middle::egraph::R_LHS	the rules
middle::egraph::R_RHS	the rules
middle::egraph::R_GUARD	the rules
middle::egraph::R_VARS	the rules
middle::egraph::RULES_READY	the rules
middle::egraph::PT	the rules
middle::egraph::PP	the rules
middle::egraph::PVARS	the rules
middle::egraph::R_VARS_NOW	the rules
middle::egraph::R_BY_OP	the rules
middle::egraph::R_BY_OP_START	the rules
base::SYMS	interned by the lazy branches above only (prepare_tasks)
base::SYM_COUNT	the same
base::SYM_TABLE	the same
base::SYM_TABLE_SIZE	the same
base::SYM_TABLES_CAP	the same
base::SYM_CAP	the same
front::types::TYPES	compute_layout: every layout is made before a phase (prepare_layouts)
front::types::ENUMS	compute_layout, the same
front::types::FIELDS	compute_layout (the fields'"'"' offsets), the same
front::types::TYPE_CAP	make_type: only on abi'"'"'s serial branches (task_phase 0)
front::types::TYPE_COUNT	make_type: only on abi'"'"'s serial branches (task_phase 0)
front::types::TLISTS	make_type, the same
front::types::TSCRATCH	make_type, the same
front::types::TYPE_HASH	make_type, the same
front::types::TYPE_HASH_SIZE	make_type, the same
front::types::TYPE_HASH_USED	make_type, the same
front::lexer::STRS	add_const_data: only on const_data'"'"'s serial branch (task_phase 0)
front::lexer::STR_COUNT	the same
gen0::target::STR_ALIGN	the same
front::lexer::STR_CAP	the same
back::dwarf::LINE_STARTS	-g, which runs on one thread (parallel::serial_only)
back::dwarf::SRC_END	-g
back::dwarf::FILE_NUMBERS	-g
back::dwarf::FILES_USED	-g
back::dwarf::DBG_FNS	-g
back::dwarf::DBG_PREFIX	-g
back::dwarf::DBG_POS	-g
back::emit::stats::ST_ALL	--stats, which runs on one thread
base::timer::T_TOTALS	--time-passes, which runs on one thread (timer_add writes only then)
base::BUFS	a task writes its context'"'"'s buffers'"'"' entries; none is made in a task (buf_new: below)
base::BUF_CAP	buf_new, below
base::BUF_COUNT	buf_new: the printers of --stats, --print-regalloc, --print-after-all, --verify-* (one thread), and internal errors, which exit
base::FMT_SCRATCH	buf_fmt: the same, and -g (tasks format with cx_fmt)
base::diag::ERR_POISONED	the IR printers (one thread)'

# The join's writes that task code touches: static <TAB> why it is no race
JOINED='base::BUFS	the join writes the program'"'"'s buffers'"'"' entries, a task its context'"'"'s
middle::parallel::FN_CONSTS	the join numbers the joined function'"'"'s constants, which no running task reads
middle::parallel::FN_TEXT	the join takes the joined function'"'"'s text, its task done
base::FMT_SCRATCH	asm_error (an internal error, which exits) and -g (one thread)
base::BUF_COUNT	asm_error, which exits
base::BUF_CAP	asm_error, which exits
base::SYMS	the -g directives (dwarf_file: one thread)
base::SYM_COUNT	the same
base::SYM_CAP	the same
base::SYM_TABLE	the same
base::SYM_TABLE_SIZE	the same
base::SYM_TABLES_CAP	the same
base::STRESS_GROW	read by prepare_tasks (stress_grow)
base::timer::T_TOTALS	--time-passes, which runs on one thread'

# The assembler thread's and -O0's main thread's: static <TAB> why
ASSEMBLER='base::BUFS	asm_error (an internal error, which exits) and dwarf_file (-g, which does not stream: no thread)
base::BUF_CAP	the same
base::BUF_COUNT	the same
base::FMT_SCRATCH	the same
base::SYMS	dwarf_file (-g: no thread)
base::SYM_CAP	the same
base::SYM_COUNT	the same
base::SYM_TABLE	the same
base::SYM_TABLES	the same
base::SYM_TABLES_CAP	the same
base::SYM_TABLE_SIZE	the same
base::STRESS_GROW	read by asm_thread_start before the thread starts (stress_grow)'

cd "$ROOT" || exit 1
WORK="$ROOT/target/threads"
mkdir -p "$WORK"
# The functions a task reaches.
{
    echo "middle::parallel::run_task"
    "$COMPILER" query callees crate::middle::parallel::run_task --transitive --all | awk -F'\t' 'NF >= 3 { print $3 }'
} | sort -u >"$WORK/reached"
[ -s "$WORK/reached" ] || { echo "threads-writes: query callees found nothing"; exit 1; }
# Every static, as a query path.
grep -rn '^ *\(pub \)\{0,1\}static mut [A-Za-z_0-9]* *:' compiler/src | awk -F: '{
    file = $1; sub(/^compiler\/src\//, "", file); sub(/\.tach$/, "", file); sub(/\/mod$/, "", file)
    gsub(/\//, "::", file)
    line = $0; sub(/^[^:]*:[^:]*:/, "", line)
    sub(/^ *(pub )?static mut /, "", line); sub(/ *:.*/, "", line)
    print (file == "main" ? "crate" : "crate::" file) "::" line
}' >"$WORK/statics"
sed 's/^/query refs /; s/$/ --all/' "$WORK/statics" | "$COMPILER" batch >"$WORK/refs" 2>&1
awk -F'\t' -v reached="$WORK/reached" '
    BEGIN { while ((getline f < reached) > 0) in_task[f] = 1 }
    /^## \$ tachyonc query refs / { s = $0; sub(/^## \$ tachyonc query refs crate::/, "", s); sub(/ --all$/, "", s); n = s; sub(/.*::/, "", n); next }
    NF >= 4 && $1 ~ /^[0-9]+:[0-9]+$/ {
        w = ($2 == "write" || $2 == "borrow")
        # (a method that changes it, through an element too; an address
        # taken, &X or &X[i], which a write may go through)
        if ($2 == "read" && match($4, n "(\\[[^]]*\\])?[ \t]*\\.[ \t]*(push|pop|clear|set|insert|put|reserve|truncate|remove|append|extend)[ \t]*\\(")) w = 1
        if ($2 == "read" && match($4, "&(mut )?" n "([^A-Za-z_0-9]|$)")) w = 1
        if (w && ($3 in in_task)) print s
    }' "$WORK/refs" | sort -u >"$WORK/written"
printf '%s\n' "$ALLOWED" | cut -f1 | sort -u >"$WORK/allowed"
new=$(comm -23 "$WORK/written" "$WORK/allowed")
for s in $new; do
    echo "FAIL $s: a task writes it; try: $COMPILER query callees crate::middle::parallel::run_task --writes crate::$s"
done
# The join's.
{
    echo "middle::parallel::join_task"
    "$COMPILER" query callees crate::middle::parallel::join_task --transitive --all | awk -F'\t' 'NF >= 3 { print $3 }'
} | sort -u >"$WORK/joined"
awk -F'\t' -v joined="$WORK/joined" -v reached="$WORK/reached" '
    BEGIN {
        while ((getline f < joined) > 0) in_join[f] = 1
        while ((getline f < reached) > 0) in_task[f] = 1
    }
    /^## \$ tachyonc query refs / { s = $0; sub(/^## \$ tachyonc query refs crate::/, "", s); sub(/ --all$/, "", s); n = s; sub(/.*::/, "", n); next }
    NF >= 4 && $1 ~ /^[0-9]+:[0-9]+$/ {
        w = ($2 == "write" || $2 == "borrow")
        if ($2 == "read" && match($4, n "(\\[[^]]*\\])?[ \t]*\\.[ \t]*(push|pop|clear|set|insert|put|reserve|truncate|remove|append|extend)[ \t]*\\(")) w = 1
        if ($2 == "read" && match($4, "&(mut )?" n "([^A-Za-z_0-9]|$)")) w = 1
        if (w && ($3 in in_join)) join_writes[s] = 1
        if ($2 != "use" && $2 != "def" && ($3 in in_task)) task_touches[s] = 1
    }
    END { for (s in join_writes) if (s in task_touches) print s }' "$WORK/refs" | sort -u >"$WORK/join-written"
printf '%s\n' "$JOINED" | cut -f1 | sort -u >"$WORK/join-allowed"
newj=$(comm -23 "$WORK/join-written" "$WORK/join-allowed")
for s in $newj; do
    echo "FAIL $s: the join writes it and a task uses it; try: $COMPILER query callees crate::middle::parallel::join_task --writes crate::$s"
done
# -O0's assembler thread against the main thread.
{
    echo "back::objfile::assemble_bytes"
    "$COMPILER" query callees crate::back::objfile::assemble_bytes --transitive --all | awk -F'\t' 'NF >= 3 { print $3 }'
} | sort -u >"$WORK/assembler"
{
    echo "gen0::gen::gen_function"
    echo "back::objfile::asm_hand_over"
    "$COMPILER" query callees crate::gen0::gen::gen_function crate::back::objfile::asm_hand_over --transitive --all | awk -F'\t' 'NF >= 3 { print $3 }'
} | sort -u >"$WORK/gen0"
awk -F'\t' -v A="$WORK/assembler" -v M="$WORK/gen0" '
    BEGIN {
        while ((getline f < A) > 0) in_asm[f] = 1
        while ((getline f < M) > 0) in_main[f] = 1
    }
    /^## \$ tachyonc query refs / { s = $0; sub(/^## \$ tachyonc query refs crate::/, "", s); sub(/ --all$/, "", s); n = s; sub(/.*::/, "", n); next }
    NF >= 4 && $1 ~ /^[0-9]+:[0-9]+$/ {
        w = ($2 == "write" || $2 == "borrow")
        if ($2 == "read" && match($4, n "(\\[[^]]*\\])?[ \t]*\\.[ \t]*(push|pop|clear|set|insert|put|reserve|truncate|remove|append|extend)[ \t]*\\(")) w = 1
        if ($2 == "read" && match($4, "&(mut )?" n "([^A-Za-z_0-9]|$)")) w = 1
        t = ($2 != "use" && $2 != "def")
        if ($3 in in_asm) { if (w) aw[s] = 1; if (t) at[s] = 1 }
        if ($3 in in_main) { if (w) mw[s] = 1; if (t) mt[s] = 1 }
    }
    END { for (s in aw) if (s in mt) print s; for (s in mw) if (s in at) print s }' "$WORK/refs" | sort -u >"$WORK/asm-shared"
printf '%s\n' "$ASSEMBLER" | cut -f1 | sort -u >"$WORK/asm-allowed"
newa=$(comm -23 "$WORK/asm-shared" "$WORK/asm-allowed")
for s in $newa; do
    echo "FAIL $s: -O0's assembler thread and its main thread share it; try: $COMPILER query callees crate::back::objfile::assemble_bytes --writes crate::$s"
done
echo "threads-writes: $(wc -l <"$WORK/written" | tr -d ' ') statics written by tasks, $(wc -l <"$WORK/join-written" | tr -d ' ') by the join and used by tasks, $(wc -l <"$WORK/asm-shared" | tr -d ' ') shared by -O0's assembler thread; $(echo "$new$newj$newa" | grep -c .) not known to be race-free"
[ -z "$new" ] && [ -z "$newj" ] && [ -z "$newa" ]
