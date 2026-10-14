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
# after it, up to the next `$` line, are its output: stdout, then stderr,
# then `[exit N]` when N is not 0. Lines starting with `#` are comments.
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
trap 'rm -rf "$WORK"' EXIT INT TERM
STATUS=0

# The transcript of test file $1 (its `$` lines run again), on stdout.
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
        (
            cd "$HERE" || exit 1
            eval "set -- $args"
            "$COMPILER" query "$@" >"$WORK/out" 2>"$WORK/err"
            rc=$?
            cat "$WORK/out" "$WORK/err"
            [ $rc -eq 0 ] || echo "[exit $rc]"
        )
    done
}

for file in "$HERE"/*.q; do
    [ -f "$file" ] || continue
    name=$(basename "$file" .q)
    transcript "$file" >"$WORK/$name.got"
    if [ $UPDATE -eq 1 ]; then
        { grep '^#' "$file"; cat "$WORK/$name.got"; } >"$WORK/$name.new"
        cp "$WORK/$name.new" "$file"
    fi
    grep -v '^#' "$file" >"$WORK/$name.want"
    if cmp -s "$WORK/$name.want" "$WORK/$name.got"; then
        echo "pass $name"
    else
        echo "FAIL $name: the transcript differs (< expected, > got):"
        diff "$WORK/$name.want" "$WORK/$name.got" | sed 's/^/    /' | head -40
        STATUS=1
    fi
done

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
out=$("$COMPILER" query show gvn::run_gvn compiler/src/main.tach 2>&1)
ok=0
printf '%s\n' "$out" | head -1 | grep -q '^// crate::gvn::run_gvn  compiler/src/gvn.tach:[0-9]*-[0-9]*$' \
    && printf '%s\n' "$out" | grep -q '^pub fn run_gvn(' && ok=1
check self_show "$ok" "$out"
out=$("$COMPILER" query refs --count crate::gvn::run_gvn compiler/src/main.tach 2>&1)
ok=0
[ "$out" -ge 3 ] 2>/dev/null && ok=1
check self_refs_count "$ok" "$out"
# (the root found by default: ./compiler/src/main.tach)
out=$("$COMPILER" query refs IntVec::push 2>&1)
ok=0
n=$(printf '%s\n' "$out" | grep -c '  in crate::')
[ "$n" -ge 100 ] && printf '%s\n' "$out" | grep -q '^compiler/src/base.tach:[0-9]*:[0-9]*  def  |' && ok=1
check self_refs "$ok" "$(printf '%s\n' "$out" | head -5)"
out=$("$COMPILER" query callers check_program 2>&1)
ok=0
printf '%s\n' "$out" | grep -q '  in crate::gen::compile_program  |' && ok=1
check self_callers "$ok" "$out"
out=$("$COMPILER" query def NodeKind::Fn 2>&1)
ok=0
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && printf '%s\n' "$out" | grep -q '^crate::ast::NodeKind::Fn  compiler/src/ast.tach:[0-9]*:[0-9]*  variant  Fn$' && ok=1
check self_def_variant "$ok" "$out"
out=$("$COMPILER" query items gvn 2>&1)
ok=0
printf '%s\n' "$out" | head -1 | grep -q '^// crate::gvn  compiler/src/gvn.tach$' \
    && printf '%s\n' "$out" | grep -q '^[0-9]*  fn  pub fn run_gvn(fi: i64) -> bool$' && ok=1
check self_items "$ok" "$(printf '%s\n' "$out" | head -5)"
# (./main.tach, found by default)
out=$(cd "$HERE/clash" && "$COMPILER" query def a::helper 2>&1)
ok=0
[ "$out" = "crate::a::helper  a.tach:2:8  fn  pub fn helper() -> i64" ] && ok=1
check default_root "$ok" "$out"
exit $STATUS
