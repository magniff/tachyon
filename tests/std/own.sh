#!/bin/sh
# std through the own pass (0.22): the programs of tests/run (all but the
# error cases and those read mixed or with --values=off) are compiled with
# TACHYON_OWN_STD=1, so that std's own functions, and the instances the
# programs make of std's generic ones, are reported too. Every finding in
# std is printed as `CODE ITEM` (ITEM: the std item holding the line) and
# must be in tests/std/own.allowed (`CODE ITEM  why`), a known pattern of
# std's internals; any other one is `FAIL`. Prints `pass std-own` or
# `FAIL std-own` lines. POSIX sh.
#
# usage: tests/std/own.sh [-c COMPILER]

set -u
LC_ALL=C
export LC_ALL
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/tachyonc"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        *) echo "usage: tests/std/own.sh [-c COMPILER]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
WORK=$(mktemp -d "${TMPDIR:-/tmp}/std-own.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cd "$ROOT" || exit 2

# The programs: no ERROR directive, no mixed reading, no --values=off.
for f in tests/run/*.tach; do
    grep -q '^// ERROR' "$f" && continue
    grep -q '^// FLAGS:.*\(--syntax=mixed\|--values=off\)' "$f" && continue
    echo "$f"
done >"$WORK/programs"

one() { # <n> <program>
    flags=$(grep -m1 '^// FLAGS:' "$2" | sed 's|^// FLAGS:||')
    # shellcheck disable=SC2086
    TACHYON_OWN_STD=1 TACHYON_OK=0 "$COMPILER" --no-cache $flags -c "$2" -o "$WORK/$1.o" 2>&1 \
        | grep '^<std>:[0-9]*:[0-9]*: error\[own\.' >"$WORK/$1.found"
    rm -f "$WORK/$1.o"
}
i=0
while read -r p; do
    i=$((i + 1))
    one "$i" "$p" &
    [ $((i % 8)) = 0 ] && wait
done <"$WORK/programs"
wait
cat "$WORK"/*.found 2>/dev/null | sed 's/^<std>:\([0-9]*\):[0-9]*: error\[\([^]]*\)\].*/\1 \2/' \
    | sort -u >"$WORK/lines"
# (each line's item, once)
: >"$WORK/pairs"
for l in $(cut -d' ' -f1 "$WORK/lines" | sort -un); do
    item=$("$COMPILER" query show "<std>:$l" "$ROOT/tests/std/own_root.tach" 2>/dev/null \
        | head -1 | sed 's|^// \([^	]*\)	.*|\1|')
    grep "^$l " "$WORK/lines" | while read -r _ code; do echo "$code $item"; done >>"$WORK/pairs"
done
sort -u "$WORK/pairs" >"$WORK/found"
sed 's/^\([^ ]*\) \([^ ]*\).*/\1 \2/' "$HERE/own.allowed" | grep -v '^#' | sort -u >"$WORK/allowed"
new=$(comm -23 "$WORK/found" "$WORK/allowed")
gone=$(comm -13 "$WORK/found" "$WORK/allowed")
n=$(wc -l <"$WORK/programs" | tr -d ' ')
if [ -z "$new" ]; then
    echo "pass std-own ($n programs; $(wc -l <"$WORK/found" | tr -d ' ') known findings)"
else
    echo "FAIL std-own: std's own functions have findings not in tests/std/own.allowed ($n programs):"
    printf '%s\n' "$new" | sed 's/^/    /'
fi
[ -n "$gone" ] && printf '%s\n' "$gone" | sed 's/^/note std-own: allowed but not found (remove it): /'
exit 0
