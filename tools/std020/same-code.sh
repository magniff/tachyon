#!/bin/sh
# The proof that std020-tree.script changed no generated code: every
# program of tests/run, bench and examples compiled by OLD (the compiler
# before the reorganization, e.g. v0.19.0's) and NEW at -O0, -O1 and -O2
# for the host, and their functions' code compared (norm.py: std's module
# segments dropped from symbols, local and string labels made anonymous;
# the string pool and std's source-position tables follow std's text,
# which moved). `tachyonc same-output` compares bytes, which the new
# symbol names change.
#
# usage: tools/std020/same-code.sh OLD [NEW]   (NEW: target/tachyonc)
set -eu
cd "$(dirname "$0")/../.."
here=$PWD/tools/std020
if [ "${1:-}" = --one ]; then
    # (one comparison: --one OLD NEW LEVEL FILE)
    old=$2 new=$3 lvl=$4 f=$5
    d=$(mktemp -d "${TMPDIR:-/tmp}/std020.XXXXXX")
    a=0; "$old" "-O$lvl" -S "$f" -o "$d/old.s" >/dev/null 2>&1 || a=$?
    b=0; "$new" "-O$lvl" -S "$f" -o "$d/new.s" >/dev/null 2>&1 || b=$?
    if [ "$a" != "$b" ]; then echo "DIFF exit $a $b -O$lvl $f"
    elif [ "$a" != 0 ]; then echo "BOTHFAIL -O$lvl $f"
    elif python3 -I "$here/norm.py" "$d/old.s" "$d/new.s"; then echo "SAME -O$lvl $f"
    else echo "DIFF code -O$lvl $f"; fi
    rm -rf "$d"
    exit 0
fi
old=$1
new=${2:-$PWD/target/tachyonc}
work=$(mktemp -d "${TMPDIR:-/tmp}/std020.XXXXXX")
trap 'rm -rf "$work"' EXIT
{ ls tests/run/*.tach bench/*.tach; ls examples/*/main.tach examples/*/*/main.tach 2>/dev/null || true; } >"$work/corpus"
for lvl in 0 1 2; do
    xargs -P 8 -I{} sh "$here/same-code.sh" --one "$old" "$new" "$lvl" {} <"$work/corpus"
done >"$work/all"
echo "same $(grep -c '^SAME' "$work/all"), both fail $(grep -c '^BOTHFAIL' "$work/all"), differ $(grep -c '^DIFF' "$work/all" || true)"
! grep '^DIFF' "$work/all"
