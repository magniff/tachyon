#!/bin/sh
# The tests of `tachyonc query` (0.11). POSIX sh and awk only.
#
# usage: tests/query/run.sh [-c COMPILER] [-u]
#
#   -c COMPILER   the tachyonc binary (default: target/tachyonc)
#   -u            rewrite the .q files with the output they get now
#
# Each tests/query/NAME.q is a transcript: a line `$ ARGS` runs
# `tachyonc query ARGS` in tests/query (ARGS are split as the shell
# splits them: quote a name with spaces), with TACHYON_ROOT set to
# NAME/main.tach when that directory exists (unset otherwise); the lines
# after it, up to the next `$` line, are its output: stdout, then stderr
# (the compiler's path in `try:` lines written `tachyonc`), then `[exit N]`
# when N is not 0. Lines starting with `##` are comments (`#` starts
# the file headers of refs).
# A test passes when the transcript it makes is the file, comments aside.
#
# Then the compiler's own source, compiler/src/main.tach, is asked a few
# questions whose answers must be plausible (it changes too often for a
# transcript): a definition is found and shown, references are counted.
#
# Prints `pass NAME` or `FAIL NAME` (and why) for each test; exits 1 if
# one failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/tachyonc"
UPDATE=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        -u) UPDATE=1; shift ;;
        *) echo "usage: tests/query/run.sh [-c COMPILER] [-u]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "query/run.sh: no compiler at $COMPILER" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-query.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
STATUS=0

# One run of `tachyonc query ARGS` (in $1, the line's ARGS), its output as
# the transcript has it, into $WORK/run.
run_line() {
    (
        cd "$HERE" || exit 1
        eval "set -- $1"
        "$COMPILER" query "$@" >"$WORK/out" 2>"$WORK/err"
        rc=$?
        # (`try:` lines name the compiler as it was run: `tachyonc` here)
        cat "$WORK/out" "$WORK/err" | sed "s|$COMPILER|tachyonc|g"
        [ $rc -eq 0 ] || echo "[exit $rc]"
    ) >"$WORK/run"
}

# The transcript of test file $1 (its `$` lines run again), on stdout, in
# mode $2 (0.13): `off`, without the tools' cache; `cache`, each line run
# twice with a cache of its own ($WORK/cache): the first run may make it,
# the second must answer the same, and from the cache when the first made
# it (TACHYON_CACHE_TRACE says which).
transcript() {
    name=$(basename "$1" .q)
    if [ -d "$HERE/$name" ]; then
        TACHYON_ROOT="$name/main.tach"
        export TACHYON_ROOT
    else
        unset TACHYON_ROOT
    fi
    grep '^\$ ' "$1" | while IFS= read -r line; do
        printf '%s\n' "$line"
        args=${line#\$ }
        if [ "$2" = off ]; then
            TACHYON_CACHE=off run_line "$args"
            cat "$WORK/run"
            continue
        fi
        : >"$WORK/trace"
        TACHYON_CACHE="$WORK/cache" TACHYON_CACHE_TRACE="$WORK/trace" run_line "$args"
        mv "$WORK/run" "$WORK/run1"
        saved=$(grep -c '^save$' "$WORK/trace")
        : >"$WORK/trace"
        TACHYON_CACHE="$WORK/cache" TACHYON_CACHE_TRACE="$WORK/trace" run_line "$args"
        cat "$WORK/run"
        cmp -s "$WORK/run1" "$WORK/run" || echo "[cache: the second run answered otherwise]"
        if [ "$saved" != 0 ]; then
            grep -q '^hit$' "$WORK/trace" || echo "[cache: made, then not used]"
        fi
        grep '^hit$' "$WORK/trace" >>"$WORK/hits"
    done
}

: >"$WORK/hits"
for file in "$HERE"/*.q; do
    [ -f "$file" ] || continue
    name=$(basename "$file" .q)
    for mode in off cache; do
        transcript "$file" $mode >"$WORK/$name.got"
        if [ $UPDATE -eq 1 ] && [ $mode = off ]; then
            { grep '^##' "$file"; cat "$WORK/$name.got"; } >"$WORK/$name.new"
            cp "$WORK/$name.new" "$file"
        fi
        grep -v '^##' "$file" >"$WORK/$name.want"
        if cmp -s "$WORK/$name.want" "$WORK/$name.got"; then
            echo "pass $name ($mode)"
        else
            echo "FAIL $name ($mode): the transcript differs (< expected, > got):"
            diff "$WORK/$name.want" "$WORK/$name.got" | sed 's/^/    /' | head -40
            STATUS=1
        fi
    done
done
# (the cache was made and used: by some lines of every program)
hits=$(grep -c hit "$WORK/hits")
if [ "$hits" -ge 10 ]; then
    echo "pass cache_used ($hits lines)"
else
    echo "FAIL cache_used: the cache answered $hits lines"
    STATUS=1
fi

# The compiler's own source.
check() { # <name> <condition> <output>
    if [ "$2" = 1 ]; then
        echo "pass $1"
    else
        echo "FAIL $1:"
        printf '%s\n' "$3" | head -20 | sed 's/^/    /'
        STATUS=1
    fi
}
cd "$ROOT" || exit 2
unset TACHYON_ROOT
TAB=$(printf '\t')
out=$("$COMPILER" query show gvn::run_gvn compiler/src/main.tach 2>&1)
ok=0
printf '%s\n' "$out" | head -1 | grep -q "^// crate::middle::gvn::run_gvn${TAB}compiler/src/middle/gvn.tach:[0-9]*-[0-9]*\$" \
    && printf '%s\n' "$out" | grep -q '^pub fn run_gvn(' && ok=1
check self_show "$ok" "$out"
out=$("$COMPILER" query refs --count crate::middle::gvn::run_gvn compiler/src/main.tach 2>&1)
ok=0
[ "$out" -ge 3 ] 2>/dev/null && ok=1
check self_refs_count "$ok" "$out"
# (the root found by default: ./compiler/src/main.tach)
# More refs than the budget (60): a summary per file, and how to narrow.
out=$("$COMPILER" query refs IntVec::push 2>"$WORK/err")
err=$(cat "$WORK/err")
ok=0
n=$(printf '%s\n' "$out" | grep -c "^compiler/src/[a-z_0-9/]*\.tach${TAB}[0-9]*\$")
[ "$n" -ge 10 ] && [ "$n" = "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" ] \
    && printf '%s\n' "$err" | head -1 | grep -q '^note query.truncated: [0-9]* refs in [0-9]* files$' \
    && [ "$(printf '%s\n' "$err" | grep -c '^try: .* query refs IntVec::push --')" = 3 ] && ok=1
check self_refs_budget "$ok" "$(printf '%s\n' "$out" "$err" | tail -6)"
out=$("$COMPILER" query refs IntVec::push --in compiler/src/base/mod.tach 2>&1)
ok=0
n=$(printf '%s\n' "$out" | grep -c "^[0-9]*:[0-9]*${TAB}call${TAB}base::[A-Za-z_:]*${TAB}")
[ "$n" -ge 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^# compiler/src/base/mod.tach$' \
    && printf '%s\n' "$out" | grep -q "^[0-9]*:[0-9]*${TAB}def${TAB}fn push(" && ok=1
check self_refs_in_file "$ok" "$(printf '%s\n' "$out" | head -5)"
out=$("$COMPILER" query refs IntVec::push --in gvn --limit 5 2>&1)
ok=0
[ "$(printf '%s\n' "$out" | grep -c "^[0-9]*:[0-9]*${TAB}call${TAB}middle::gvn::")" = 5 ] \
    && printf '%s\n' "$out" | grep -q '^note query.truncated: showing 5 of [0-9]* refs$' && ok=1
check self_refs_in_module_limit "$ok" "$out"
n=$("$COMPILER" query refs IntVec::push --all 2>/dev/null | grep -c "^[0-9]*:[0-9]*${TAB}")
ok=0
[ "$n" -ge 100 ] && ok=1
check self_refs_all "$ok" "$n"
out=$("$COMPILER" query callers check_program 2>&1)
ok=0
printf '%s\n' "$out" | grep -q "^[0-9]*:[0-9]*${TAB}call${TAB}gen0::gen::compile_program${TAB}" && ok=1
check self_callers "$ok" "$out"
out=$("$COMPILER" query def NodeKind::Fn 2>&1)
ok=0
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && printf '%s\n' "$out" | grep -q "^crate::front::ast::NodeKind::Fn${TAB}compiler/src/front/ast.tach:[0-9]*:[0-9]*${TAB}variant${TAB}Fn\$" && ok=1
check self_def_variant "$ok" "$out"
out=$("$COMPILER" query items gvn 2>&1)
ok=0
printf '%s\n' "$out" | head -1 | grep -q "^# crate::middle::gvn${TAB}compiler/src/middle/gvn.tach\$" \
    && printf '%s\n' "$out" | grep -q "^[0-9]*${TAB}fn${TAB}pub fn run_gvn(fi: i64) -> bool\$" && ok=1
check self_items "$ok" "$(printf '%s\n' "$out" | head -5)"
# More than 5 definitions for show: their paths, and an error.
out=$("$COMPILER" query show .name 2>&1)
rc=$?
ok=0
[ $rc = 1 ] && printf '%s\n' "$out" | grep -q '^crate::front::modules::Module.name$' \
    && printf '%s\n' "$out" | grep -q "^error query.ambiguous: [0-9]* definitions match '.name'; showing paths only\$" \
    && printf '%s\n' "$out" | grep -q '^try: .* query show crate::[a-z_0-9:]*::[A-Za-z]*\.name$' && ok=1
check self_show_ambiguous "$ok" "$out"
# A long source line is cut at 100 bytes, with `…`.
out=$("$COMPILER" query refs IntVec::push --in vectorize --all 2>&1 | awk -F "$TAB" 'length($3) > 100')
ok=0
[ -z "$out" ] && ok=1
check self_line_max "$ok" "$out"
# Banners and text search (0.13).
out=$("$COMPILER" query items gvn --comments 2>&1)
ok=0
printf '%s\n' "$out" | grep -q "^[0-9]*-[0-9]*${TAB}section${TAB}The value table\$" && ok=1
check self_banners "$ok" "$(printf '%s\n' "$out" | head -5)"
out=$("$COMPILER" query show gvn::section 'value table' 2>&1)
ok=0
printf '%s\n' "$out" | head -1 | grep -q "^// crate::middle::gvn::section The value table${TAB}compiler/src/middle/gvn.tach:[0-9]*-[0-9]*\$" \
    && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "// ---- The value table ----" ] && ok=1
check self_section "$ok" "$(printf '%s\n' "$out" | head -3)"
out=$("$COMPILER" query grep 'fn run_gvn(' 2>&1)
ok=0
printf '%s\n' "$out" | grep -q "^[0-9]*:[0-9]*${TAB}code${TAB}middle::gvn::run_gvn${TAB}pub fn run_gvn(" && ok=1
check self_grep "$ok" "$out"
n=$("$COMPILER" query grep 'query.no-match' --strings --in compiler/src/tools/ --count 2>&1)
ok=0
[ "$n" -ge 3 ] 2>/dev/null && ok=1
check self_grep_strings "$ok" "$n"
# (./main.tach, found by default)
out=$(cd "$HERE/clash" && "$COMPILER" query def a::helper 2>&1)
ok=0
[ "$out" = "crate::a::helper${TAB}a.tach:2:8${TAB}fn${TAB}pub fn helper() -> i64" ] && ok=1
check default_root "$ok" "$out"
exit $STATUS
