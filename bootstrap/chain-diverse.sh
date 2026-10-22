#!/bin/sh
# (0.25) A diverse-path fixpoint, after Wheeler's diverse double-compiling:
# HEAD's compiler built along paths that share as little code as possible,
# which must end in the same bytes.
#
#   normal      the chain's: PREVIOUS builds HEAD (-O2), that builds HEAD
#               (-O2): A2; A2 builds HEAD again: A3.o
#   no-opt      no optimizer anywhere before the last step: PREVIOUS at -O0
#               builds HEAD (B1), B1 at -O0 builds HEAD (B2: HEAD's code
#               from HEAD's own -O0 back end, run unoptimized), B2 builds
#               HEAD at -O2: B3.o
#   serial      the normal path at -j1: J1, then J2.o
#
# Checked: B3.o and A3.o are the same bytes (and A2.o: the fixpoint); B2.o
# is what A2 emits at -O0; J1.o is A1.o and J2.o is A2.o. An optimizer bug
# that miscompiled the compiler in a way that changes what it does would
# make the paths diverge; one that hides itself (the same wrong code
# from both paths) would need the -O0 back end of PREVIOUS and of HEAD to
# miscompile HEAD the same way too. Then `same-output` compares A2's
# outputs with B2's on the whole corpus (every program, target and level),
# the try: lines that name the compiler's own path excepted.
#
# Every object is linked by the system's cc, as bootstrap.sh does, not by
# the compiler's own linker. Slow: B1 and B2 are unoptimized compilers
# (several minutes in all, same-output most of it).
#
# usage: bootstrap/chain-diverse.sh -p PREVIOUS [-w DIR] [--no-same-output]
#
#   -p PREVIOUS        the previous release's compiler (v0.24.0's volec)
#   -w DIR             the work directory (default target/chain-diverse)
#   --no-same-output   only the byte comparisons
set -u
LC_ALL=C
export LC_ALL
VOLE_CODE_CACHE=off
VOLE_CACHE=off
export VOLE_CODE_CACHE VOLE_CACHE

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PREV=""
W="$ROOT/target/chain-diverse"
SAME=1
while [ $# -gt 0 ]; do
    case "$1" in
        -p) PREV=$2; shift 2 ;;
        -w) W=$2; shift 2 ;;
        --no-same-output) SAME=0; shift ;;
        -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
[ -n "$PREV" ] && [ -x "$PREV" ] || { echo "chain-diverse: no previous release (-p; bootstrap/bootstrap.sh builds it)"; exit 77; }
case "$PREV" in /*) ;; *) PREV="$(pwd)/$PREV" ;; esac
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) HOST=aarch64-macos; LINK="-arch arm64" ;;
    Darwin-x86_64) HOST=x86_64-macos; LINK="-arch x86_64" ;;
    Linux-x86_64) HOST=x86_64-linux; LINK="" ;;
    *) echo "chain-diverse: no chain on $(uname -s) $(uname -m)"; exit 77 ;;
esac
SRC="$ROOT/$(sh "$ROOT/bootstrap/release-tags.sh" --head compiler)/$(sh "$ROOT/bootstrap/release-tags.sh" --head root)"
BIN=$(sh "$ROOT/bootstrap/release-tags.sh" --head bin)
rm -rf "$W"
mkdir -p "$W"
FAILED=0

# <compiler> <name> <options...>: <name>.o from HEAD's source, and the
# executable <name> linked by cc.
build() {
    b_c=$1 b_n=$2
    shift 2
    echo "  $b_n: $(basename "$(dirname "$b_c")")/$(basename "$b_c") $*"
    "$b_c" --target "$HOST" "$@" "$SRC" -o "$W/$b_n.o" >"$W/$b_n.log" 2>&1 \
        || { echo "chain-diverse: $b_n failed to build (log: $W/$b_n.log)"; tail -5 "$W/$b_n.log"; exit 1; }
    # shellcheck disable=SC2086
    ${CC:-cc} $LINK -o "$W/$b_n" "$W/$b_n.o" -lm \
        || { echo "chain-diverse: cc failed to link $b_n"; exit 1; }
}

# <a> <b> <what>: the two objects are the same bytes.
same() {
    if cmp -s "$W/$1.o" "$W/$2.o"; then
        echo "  same: $1.o = $2.o ($3)"
    else
        echo "FAIL $1.o and $2.o differ: $3 ($W)"
        FAILED=1
    fi
}

echo "chain-diverse: HEAD's compiler ($SRC) by three paths from $PREV"
build "$PREV" A1 -O2
build "$W/A1" A2 -O2
build "$W/A2" A3 -O2
build "$PREV" B1 -O0
build "$W/B1" B2 -O0
build "$W/B2" B3 -O2
build "$W/A2" A2O0 -O0
build "$PREV" J1 -O2 -j1
build "$W/J1" J2 -O2 -j1
same A2 A3 "the normal fixpoint"
same A3 B3 "-O2 by the optimized and by the unoptimized compiler"
same A2O0 B2 "-O0 by A2 and by B1"
same A1 J1 "PREVIOUS at -j8 and -j1"
same A2 J2 "HEAD at -j8 and -j1"

if [ $SAME -eq 1 ] && [ $FAILED -eq 0 ]; then
    # A2 against B2 on the corpus. Both are run by an absolute path, which
    # the try: lines of some diagnostics print: those lines are compared
    # with B2's path written as A2's.
    mkdir -p "$W/a" "$W/b"
    cp "$W/A2" "$W/a/$BIN"
    cp "$W/B2" "$W/b/$BIN"
    echo "  same-output: A2 (optimized) against B2 (unoptimized)"
    # (its own work directory: target/same-output keeps every earlier
    # run's compilations, which are not this run's to judge)
    rm -rf "$W/so"
    (cd "$ROOT" && "$W/a/$BIN" same-output "$W/b/$BIN" --work "$W/so") >"$W/same-output.log" 2>&1
    rc=$?
    if [ $rc -ne 0 ]; then
        kept="$W/so"
        real=0
        for d in "$kept"/*; do
            [ -d "$d" ] || continue
            if [ -d "$d/old" ] && ! diff -rq "$d/old" "$d/new" >/dev/null 2>&1; then
                real=$((real + 1))
                [ $real -le 5 ] && echo "FAIL same-output: $d: the output files differ"
            elif [ -f "$d/old.out" ] && ! cmp -s "$d/old.out" "$d/new.out" \
                && ! sed "s#$W/b/$BIN#$W/a/$BIN#g" "$d/old.out" | cmp -s - "$d/new.out"; then
                real=$((real + 1))
                [ $real -le 5 ] && echo "FAIL same-output: $d: the messages differ"
            fi
        done
        if [ $real -gt 0 ]; then
            echo "FAIL same-output: $real compilations differ between A2 and B2 (log: $W/same-output.log)"
            FAILED=1
        else
            echo "  same-output: the differences are only the compiler's own path in try: lines"
        fi
    else
        echo "  same-output: no difference"
    fi
fi
if [ $FAILED -ne 0 ]; then
    echo "chain-diverse: the paths diverge (kept in $W)"
    exit 1
fi
echo "chain-diverse: the normal, unoptimized and -j1 paths give the same compiler$([ $SAME -eq 1 ] && echo ", and the same output on the corpus")"
