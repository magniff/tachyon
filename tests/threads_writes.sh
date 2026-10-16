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
# (0.18.1, T8) And every static task code touches (reads too) must be one
# of READ below, with how the code cache (back::codecache) covers it: a
# task's entry is used only when what it read is the same, so a static it
# reads must be in the key (the options, the program's types), recorded
# as read (a fact of another function, cc_note), part of the IR's hash, a
# mode the cache is off in, or the cache's own. A new one fails: say how
# its value reaches the key, or the cache uses outputs made from another.
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
back::codecache::FN_IRH	the task'"'"'s own functions'"'"' entries; others read a lower level'"'"'s or an earlier phase'"'"'s (FN_IRH_OK)
back::codecache::FN_IRH_OK	the same
back::codecache::FN_STRS	the same
back::codecache::OUT_COMP	the task'"'"'s own component'"'"'s entry, read after the phases (the counts)
back::codecache::OUT_EMIT	the task'"'"'s own function'"'"'s entry, read after the phases
back::codecache::OUT_SCALAR	the task'"'"'s own function'"'"'s entry, read after the phases
back::codecache::SCALAR_REC	the task'"'"'s own function'"'"'s entry (its cleanup'"'"'s, then its scalar pipeline'"'"'s, a phase after)
back::codecache::pack::NEW	the task'"'"'s own slot, read when the pack is written
back::codecache::pack::USED	the entry of the task'"'"'s own key (a key is one task'"'"'s), read when the pack is written
back::codecache::pack::PACK	read only: an entry'"'"'s body is read through its address
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
front::distinct::NICHE	enum_niche: every enum'"'"'s is made before a phase (prepare_layouts)
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
base::CWD	-g (dbg_loc'"'"'s paths, out_path)
base::OUT_PATHS	-g
base::ROOT_DIR	-g
base::ROOT_LEX	-g
base::ROOT_LEX_ABS	-g
tools::query::checks::REMOVED	query checks (--print-checks), which runs on one thread
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

# Every static task code reads or writes: static <TAB> how the code cache
# covers it (key: in the entry's key; read: recorded, cc_note; IR: in
# hash::ir_hash; off: a mode the cache is off in, cc_wanted; own: the
# cache's, or the task's context's).
READ='back::codecache::CC_ON	own
back::codecache::CHECK	own (testing)
back::codecache::ENV	own: the key'"'"'s program hash
back::codecache::FN_IRH	own: read R_IR
back::codecache::FN_IRH_OK	own
back::codecache::FN_STRS	own: the strings of a read IR
back::codecache::OUT_COMP	own
back::codecache::OUT_EMIT	own
back::codecache::OUT_SCALAR	own
back::codecache::SCALAR_REC	own: a function'"'"'s recording, from its cleanup to its scalar pipeline
back::codecache::WHY	own (testing)
back::codecache::hash::FN_AMBIG	own
back::codecache::hash::FN_CANON	own: what IR names a function by
back::codecache::hash::FN_MOVES	own: MOVE_COPIES, in the IR hash
back::codecache::hash::FN_NAMEH	own
back::codecache::hash::NAME_FN	own
back::codecache::hash::NAME_IR	own
back::codecache::hash::STR_H	own: a string'"'"'s bytes
back::codecache::hash::STR_H_COUNT	own
back::codecache::pack::ENTRY_AT	own
back::codecache::pack::INDEX	own
back::codecache::pack::INDEX_SIZE	own
back::codecache::pack::NEW	own
back::codecache::pack::NEW_SLOTS	own
back::codecache::pack::PACK	own
back::codecache::pack::USED	own
back::dwarf::DBG_FNS	off: -g
back::dwarf::DBG_POS	off: -g
back::dwarf::DBG_PREFIX	off: -g
back::dwarf::DEBUG_INFO	off: -g
back::dwarf::FILES_USED	off: -g
back::dwarf::FILE_NUMBERS	off: -g
back::dwarf::LINE_STARTS	off: -g
back::dwarf::SRC_END	off: -g
back::emit::stats::STATS	off: --stats
back::emit::stats::ST_ALL	off: --stats
back::regalloc::PRINT_REGALLOC	off: --print-regalloc
back::regalloc::VERIFY_REGALLOC	off: --verify-regalloc
back::regalloc::scan::X86_ALLOC_ACD	key: options_hash
base::BUFS	own: the context'"'"'s buffers
base::BUF_CAP	own: buf_new on internal errors and printers
base::BUF_COUNT	own: the same
base::CWD	off: -g (out_path)
base::FILES	off: -g (dbg_loc, out_path)
base::FILE_COUNT	off: -g
base::FMT_SCRATCH	off: printers and -g
base::OUT_PATHS	off: -g
base::ROOT_DIR	off: -g
base::ROOT_LEX	off: -g
base::ROOT_LEX_ABS	off: -g
base::SRC	off: -g
base::STDOUT_CAPTURE	own: messages
base::STRESS_GROW	key: options_hash (stress_grow)
base::SYMS	IR: a symbol by its text
base::SYM_CAP	IR: the same (no symbol is made in a task)
base::SYM_COUNT	IR: the same
base::SYM_TABLE	IR: the same
base::SYM_TABLES	IR: the same
base::SYM_TABLES_CAP	IR: the same
base::SYM_TABLE_SIZE	IR: the same
base::diag::ERR_POISONED	off: the IR printers
base::json::DIAG_JSON	own: messages
base::target::APPLE_A64	key: options_hash
base::target::ELF	key: options_hash
base::target::X86	key: options_hash
base::timer::TIME_PASSES	off: --time-passes
base::timer::T_TOTALS	off: --time-passes
front::ast::NODES	IR: a closure'"'"'s mark (fn_canon), a distinct type'"'"'s name (types_hash); -g
front::check::LOCALS	own: a task makes variables above LOCAL_COUNT (ssa::new_synth_var), never reads a local'"'"'s
front::check::LOCAL_COUNT	own: the same; a variable'"'"'s number is never output
front::distinct::ANY_DISTINCT	key: options_hash
front::distinct::NICHE	key: types_hash (enum_niche)
front::distinct::NICHE_ALIASES	key: types_hash
front::effects::FN_EFFECTS	IR: a function'"'"'s effects (fn_canon)
front::effects::FN_EFFECTS_COUNT	IR: the same
front::effects::builtin::TABLE	IR: by a symbol'"'"'s text; the same in every build of a compiler
front::lexer::STRS	IR: a string'"'"'s bytes (STR_H)
front::lexer::STR_CAP	IR: the same (no string is made in a task)
front::lexer::STR_COUNT	IR: the same
front::own::diag::OWN_MODE	key: options_hash
front::types::ENUMS	key: types_hash
front::types::FIELDS	key: types_hash
front::types::FNS	IR: a function by fn_canon
front::types::FN_COUNT	IR: the same
front::types::STATICS	IR: a static by static_canon
front::types::STRUCTS	key: types_hash
front::types::SYM_STATIC	IR: the same
front::types::TLISTS	key: types_hash
front::types::TSCRATCH	key: types_hash (no type is made in a task)
front::types::TYPES	key: types_hash
front::types::TYPE_CAP	key: types_hash
front::types::TYPE_COUNT	key: types_hash
front::types::TYPE_HASH	key: types_hash
front::types::TYPE_HASH_SIZE	key: types_hash
front::types::TYPE_HASH_USED	key: types_hash
front::types::TY_ERROR	key: types_hash (a fixed id)
front::types::TY_V16I8	key: types_hash (a fixed id)
front::types::TY_V2F64	key: types_hash (a fixed id)
front::types::TY_V2I64	key: types_hash (a fixed id)
front::types::TY_V4F32	key: types_hash (a fixed id)
front::types::TY_V4I32	key: types_hash (a fixed id)
front::types::TY_V8I16	key: types_hash (a fixed id)
front::types::VARIANTS	key: types_hash
gen0::gen::MAIN_SYM	IR: a symbol by its text
gen0::target::LINK_NAMES	IR: fn_canon
gen0::target::RT_PANIC_SYM	IR: a symbol by its text
gen0::target::STR_ALIGN	IR: a string'"'"'s alignment (STR_H)
middle::copies::MOVE_COPIES	IR: FN_MOVES
middle::egraph::EGRAPH	key: options_hash
middle::egraph::PP	own: the rules, the same in every build of a compiler
middle::egraph::PT	own: the same
middle::egraph::PVARS	own: the same
middle::egraph::P_A	own: the same
middle::egraph::P_B	own: the same
middle::egraph::P_COND	own: the same
middle::egraph::P_KIND	own: the same
middle::egraph::P_OP	own: the same
middle::egraph::P_VAL	own: the same
middle::egraph::RULES_READY	own: the same
middle::egraph::R_BY_OP	own: the same
middle::egraph::R_BY_OP_START	own: the same
middle::egraph::R_GUARD	own: the same
middle::egraph::R_LHS	own: the same
middle::egraph::R_RHS	own: the same
middle::egraph::R_VARS	own: the same
middle::egraph::R_VARS_NOW	own: the same
middle::gvn::MEMCPY_SYM	IR: a symbol by its text
middle::gvn::NOALIAS_OFF	key: options_hash
middle::ifconv::IFCONV	key: options_hash
middle::inline::FN_ADDRESS	read: R_STATIC (facts_fixed); the key (own_fp)
middle::inline::FN_CALLS	read: R_CALLS, whether one is left
middle::inline::FN_DECIDERS	read: R_DEC
middle::inline::FN_DECIDERS_START	read: R_DEC
middle::inline::FN_LIVE	read: R_STATIC; the key
middle::inline::FN_RT	read: R_RT
middle::inline::FN_SCC	read: R_STATIC, whether in the task'"'"'s SCC
middle::inline::FN_SIZE	read: R_SIZE; the key
middle::inline::LEAF_DONE	read: R_STATIC; the key
middle::inline::LEAF_KEEP	read: R_STATIC; the key
middle::inline::LEAF_SMALL	read: R_STATIC; the key
middle::inline::PROGRAM_BUDGET	read: R_BUDGET, whether within
middle::inline::PROGRAM_SIZE	read: R_BUDGET
middle::inline::SCC_ORDER	key: the component'"'"'s functions
middle::ipo::ATTRS_READY	key: cc_phase
middle::ipo::CALLOC_SYM	IR: a symbol by its text
middle::ipo::FN_ATTRS	read: R_ATTRS; the key
middle::ipo::FN_ATTRS_DONE	read: R_ATTRS, R_STATIC (ready); the key
middle::ipo::FN_NOCAPTURE	read: R_ATTRS; the key
middle::ipo::FREE_SYM	IR: a symbol by its text
middle::ipo::MALLOC_SYM	IR: a symbol by its text
middle::ir::FN_IR	IR: fn_canon (whether it has IR)
middle::ir::IRFUNCS	IR: the task'"'"'s own; read: R_IR, another'"'"'s
middle::ir::FN_RTIDS	IR: an RTID value by its function and place, its class (the number is the join'"'"'s)
middle::ir::IRFUNC_COUNT	own
middle::ir::IR_CALL_LOCS	off: --trace
middle::ir::IR_EXPR_LOC	off: -g and --trace (IR_LOCS)
middle::ir::IR_LOC	off: the same
middle::ir::IR_LOCS	off: the same
middle::ir::verify::PRINT_AFTER_ALL	off: --print-after-all
middle::ir::verify::VERIFY_IR	off: --verify-ir
middle::opt::DEFERRED	the key (own_fp)
middle::opt::OPT_LEVEL	key: options_hash
middle::opt::PER_FUNCTION	key: options_hash
middle::parallel::COMP_END	key: the component'"'"'s functions
middle::parallel::COMP_GROWTH	own: an output
middle::parallel::COMP_INLINED	own: an output
middle::parallel::COMP_LEVEL	read: R_STATIC (ready)
middle::parallel::COMP_OF	read: R_STATIC (ready)
middle::parallel::COMP_START	key: the component'"'"'s functions
middle::parallel::FN_CONSTS	IR: constant data by owner, place and bytes (const_canon); outputs
middle::parallel::FN_TEXT	own: an output
middle::parallel::FRESH_CONTEXTS	key: options_hash (cc_args: $TACHYON_FRESH_CONTEXTS)
middle::parallel::ITEMS	own: the task'"'"'s function
middle::profile::PROFILE_MAX	off: --profile-use (and options_hash)
middle::slp::SLP	key: options_hash
middle::vectorize::VECTORIZE	key: options_hash
middle::vectorize::unroll::UNROLL_RUNTIME	key: options_hash
tools::query::checks::PRINT_CHECKS	off: --print-checks
tools::query::checks::REMOVED	off: --print-checks'

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
# (T8) Every static task code touches, against READ.
awk -F'\t' -v reached="$WORK/reached" '
    BEGIN { while ((getline f < reached) > 0) in_task[f] = 1 }
    /^## \$ tachyonc query refs / { s = $0; sub(/^## \$ tachyonc query refs crate::/, "", s); sub(/ --all$/, "", s); next }
    NF >= 4 && $1 ~ /^[0-9]+:[0-9]+$/ { if ($2 != "use" && $2 != "def" && ($3 in in_task)) print s }' "$WORK/refs" \
    | sort -u >"$WORK/touched"
printf '%s\n' "$READ" | cut -f1 | sort -u >"$WORK/read-allowed"
newr=$(comm -23 "$WORK/touched" "$WORK/read-allowed")
for s in $newr; do
    echo "FAIL $s: a task reads it, and the code cache does not know how it covers it (tests/threads_writes.sh READ); try: $COMPILER query refs crate::$s"
done
echo "threads-writes: $(wc -l <"$WORK/written" | tr -d ' ') statics written by tasks, $(wc -l <"$WORK/join-written" | tr -d ' ') by the join and used by tasks, $(wc -l <"$WORK/asm-shared" | tr -d ' ') shared by -O0's assembler thread; $(echo "$new$newj$newa" | grep -c .) not known to be race-free; $(wc -l <"$WORK/touched" | tr -d ' ') touched, $(echo "$newr" | grep -c .) the code cache does not cover"
[ -z "$new" ] && [ -z "$newj" ] && [ -z "$newa" ] && [ -z "$newr" ]
