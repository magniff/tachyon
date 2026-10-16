#!/bin/sh
# (0.18.1) The statics that code generation's tasks may write
# (docs/optimizer.md, "0.18.1: threads", "Why there is no data race"):
# the functions middle::parallel::run_task reaches (query callees
# --transitive) and, for every static of the compiler, its writes and
# borrows in them (query refs; a method call that changes it, X.push(..),
# counts) are listed, and each static found must be one below, with the
# reason it is no race. A new one fails: move it into middle::ctx::FnCtx,
# make it before the tasks run (parallel::prepare_tasks), or join it
# between phases.
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
echo "threads-writes: $(wc -l <"$WORK/written" | tr -d ' ') statics written by tasks, $(echo "$new" | grep -c .) not known to be race-free"
[ -z "$new" ]
