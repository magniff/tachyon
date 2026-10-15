#!/bin/sh
# 22-refactor-rename: the structure of the refactoring (see README.md).
# Run in the graded tree's root with TACHYONC, EVAL_STARTER_TACHYONC,
# EVAL_STARTER_TREE. The reference counts come from the starter at grading
# time, so the check follows whatever the base's compiler source holds.

fail() { echo "$1" >&2; exit 1; }

: "${TACHYONC:?}" "${EVAL_STARTER_TACHYONC:?}" "${EVAL_STARTER_TREE:?}"
MOVED="emit_ir ir_const ir_binary ir_cmp ir_load ir_store ir_slot_addr ir_offset"
SRC=compiler/src

# calls TACHYONC TREE NAME: the number of calls to NAME in TREE ("" if none).
calls() {
    n=$(cd "$2" && "$1" query refs "$3" --kind call --count 2>/dev/null | tail -n 1)
    case "$n" in
        ''|*[!0-9]*) echo "" ;;
        *) echo "$n" ;;
    esac
}

# code_hits WORD: occurrences of WORD in compiler/src's code (comments cut).
code_hits() {
    grep -rhw --include='*.tach' "$1" "$SRC" | sed 's|//.*$||' | grep -cw "$1"
}

# defined_in NAME: the file of NAME's definition ("" if none).
defined_in() {
    "$TACHYONC" query def "$1" 2>/dev/null | awk -F'\t' 'NR == 1 { sub(/:[0-9]+:[0-9]+$/, "", $2); print $2 }'
}

# 1. The rename.
[ "$(code_hits ir_make)" = 0 ] || fail "ir_make is still defined or used in compiler/src"
[ -n "$(defined_in crate::middle::ir::ir_new_inst)" ] ||
    fail "crate::middle::ir::ir_new_inst is not defined"
want=$(calls "$EVAL_STARTER_TACHYONC" "$EVAL_STARTER_TREE" crate::middle::ir::ir_make)
[ -n "$want" ] || fail "grade.sh: cannot count the calls to ir_make in the starter"
got=$(calls "$TACHYONC" . crate::middle::ir::ir_new_inst)
[ "$got" = "$want" ] || fail "ir_new_inst has ${got:-no} calls, ir_make had $want"

# 2. The move.
for f in $MOVED; do
    file=$(defined_in "crate::middle::ir::build::$f")
    case "$file" in
        "$SRC/middle/ir/build.tach"|"$SRC/middle/ir/build/mod.tach") ;;
        '') fail "crate::middle::ir::build::$f is not defined" ;;
        *) fail "crate::middle::ir::build::$f is defined in $file, not compiler/src/middle/ir/build.tach" ;;
    esac
    defs=$(grep -rhw --include='*.tach' "fn $f" "$SRC" | sed 's|//.*$||' | grep -cw "fn $f")
    [ "$defs" = 1 ] || fail "$f is defined $defs times in compiler/src (want once, in crate::middle::ir::build)"
    want=$(calls "$EVAL_STARTER_TACHYONC" "$EVAL_STARTER_TREE" "crate::middle::ir::$f")
    [ -n "$want" ] || fail "grade.sh: cannot count the calls to $f in the starter"
    got=$(calls "$TACHYONC" . "crate::middle::ir::build::$f")
    [ "$got" = "$want" ] || fail "crate::middle::ir::build::$f has ${got:-no} calls, the starter's $f had $want"
done

# No re-export of a moved function (a `pub use` naming it, anywhere).
pat=$(echo $MOVED | sed 's/ /|/g')
reexp=$(find "$SRC" -name '*.tach' -exec awk '
    /^[ \t]*pub(\([a-z]+\))?[ \t]+use[ \t]/ { s = ""; inuse = 1 }
    inuse { line = $0; sub(/\/\/.*$/, "", line); s = s " " line
            if (line ~ /;/) { print FILENAME ":" s; inuse = 0 } }
' {} + | grep -E "(^|[^A-Za-z0-9_])($pat)([^A-Za-z0-9_]|$)" | head -n 1)
[ -z "$reexp" ] || fail "a moved function is re-exported: $(echo "$reexp" | cut -c1-200)"

exit 0
