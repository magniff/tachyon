#!/bin/sh
# Structural check for 10-refactor-rename, run in the finished workspace with
# EVAL_LANG=tach|rust. The hidden tests check that behaviour is unchanged;
# this checks that the renames and the move were made.

# (0.16) std's ambient allocator (`Vec::new()`) for the 0.15 corpus, until
# `tachyonc fix --only alloc016` migrates it: compiler/src/front/ambient.tach.
TACHYON_AMBIENT_GPA=${TACHYON_AMBIENT_GPA:-1}
export TACHYON_AMBIENT_GPA
case "$EVAL_LANG" in
    tach) ext=tach ;;
    rust) ext=rs ;;
    *) echo "check: EVAL_LANG must be tach or rust, got '$EVAL_LANG'" >&2; exit 2 ;;
esac

fail() {
    echo "check: $*" >&2
    exit 1
}

[ -f "main.$ext" ] || fail "main.$ext is missing"
[ -f "report.$ext" ] || fail "report.$ext is missing (the new module)"

files=$(find . -name "*.$ext" -not -path './.git/*' | sort)

# The old names are gone everywhere: code, comments and strings.
for w in Item qty calc; do
    hit=$(grep -nw -- "$w" $files | head -n 1 | cut -c1-100)
    [ -z "$hit" ] || fail "'$w' still appears: $hit"
done

# The new names are there.
grep -Eq 'struct[[:space:]]+Book([[:space:]]|\{|$)' $files || fail "no struct Book"
grep -Eq '(^|[^A-Za-z0-9_])copies[[:space:]]*:' $files || fail "no field copies"
grep -Eq 'fn[[:space:]]+late_fee[[:space:]]*\(' $files || fail "no fn late_fee"

# main declares the module; report holds the four reports; nobody else does.
grep -Eq '^[[:space:]]*(pub[[:space:]]+)?mod[[:space:]]+report[[:space:]]*;' "main.$ext" ||
    fail "main.$ext does not declare 'mod report;'"
for f in report_stock report_members report_overdue report_summary; do
    grep -Eq "fn[[:space:]]+$f[[:space:]]*\\(" "report.$ext" || fail "report.$ext does not define $f"
    for other in $files; do
        [ "$other" = "./report.$ext" ] && continue
        if grep -Eq "fn[[:space:]]+$f[[:space:]]*\\(" "$other"; then
            fail "$f is still defined in $other"
        fi
    done
done
grep -Eq 'fn[[:space:]]+cmd_report[[:space:]]*\(' "main.$ext" || fail "cmd_report is no longer in main.$ext"
exit 0
