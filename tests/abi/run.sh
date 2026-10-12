#!/bin/sh
# C interoperability conformance: random signatures (gen.awk) called in
# both directions between C and tachyon, every value checked. Each
# program is compiled at -O0, -O1 and -O2 (with --verify-ir), linked with
# its C half (compiled by cc) and run; it must print "ok".
#
# usage: tests/abi/run.sh [-c COMPILER] [-t TARGET] [-n COUNT] [-f FIRST]
#                         [-k DIR] [-j JOBS] [-i | -H]
#
#   -c COMPILER   the tachyonc to test (default: target/tachyonc)
#   -t TARGET     aarch64-macos, x86_64-linux or x86_64-macos (default:
#                 the host)
#   -n COUNT      number of programs (default 150; each has 5 to 11
#                 signatures)
#   -f FIRST      the first random seed (default 1)
#   -k DIR        where to keep failing programs (default: tests/abi/failures)
#   -j JOBS       programs tested at once (default: the number of CPUs)
#   -i            import mode: the C declarations are in a header, which the
#                 C half includes and the tachyon half imports (`import`);
#                 the tachyon half declares only its enums (which shadow C's)
#   -H            header mode: the C half uses the header tachyonc --emit-header
#                 writes for the tachyon half, not declarations of its own

set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
COMPILER="$ROOT/target/tachyonc"
TARGET=""
COUNT=150
FIRST=1
KEEP="$ROOT/tests/abi/failures"
JOBS=""
IMPORT=0
HEADER=0
CC=${CC:-cc}
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -t) TARGET=$2; shift 2 ;;
        -n) COUNT=$2; shift 2 ;;
        -f) FIRST=$2; shift 2 ;;
        -k) KEEP=$2; shift 2 ;;
        -j) JOBS=$2; shift 2 ;;
        -i) IMPORT=1; shift ;;
        -H) HEADER=1; shift ;;
        *) sed -n "2,23p" "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
if [ -z "$TARGET" ]; then
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) TARGET=aarch64-macos ;;
        Darwin-x86_64) TARGET=x86_64-macos ;;
        Linux-x86_64) TARGET=x86_64-linux ;;
        *) echo "abi: unknown host" >&2; exit 2 ;;
    esac
fi
case "$TARGET" in
    aarch64-macos) ARCH="-arch arm64" ;;
    x86_64-macos) ARCH="-arch x86_64" ;;
    *) ARCH="" ;;
esac
if [ -z "$JOBS" ]; then
    JOBS=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 4)
    case "$JOBS" in ''|*[!0-9]*) JOBS=4 ;; esac
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-abi.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

# Tests program $1; why it fails in $WORK/p$1.why; its signature count in
# $WORK/p$1.count.
test_seed() {
    seed=$1
    t="$WORK/p$seed.tach"
    c="$WORK/p$seed.c"
    awk -v seed="$seed" -v cfile="$c" -v tfile="$t" -v import="$IMPORT" -v header="$HEADER" -v hfile="$WORK/p$seed.h" -f "$ROOT/tests/abi/gen.awk"
    rm -f "$t.decls"
    grep -c '^extern "C" fn t_f\|^void v_f' "$t" "$c" | awk -F: '{ n += $2 } END { print n }' >"$WORK/p$seed.count"
    if [ "$HEADER" = 1 ]; then
        "$COMPILER" --target "$TARGET" --emit-header "$t" -o "$WORK/p$seed.h" >"$c.log" 2>&1 \
            || { echo "--emit-header failed: $(head -3 "$c.log")" >"$WORK/p$seed.why"; return; }
    fi
    # shellcheck disable=SC2086
    "$CC" $ARCH -c -w -o "$c.o" "$c" >"$c.log" 2>&1 || { echo "cc failed on the C half: $(head -3 "$c.log")" >"$WORK/p$seed.why"; return; }
    for level in O0 O1 O2; do
        exe="$WORK/p$seed.$level"
        "$COMPILER" --target "$TARGET" "-$level" --deny-warnings --verify-ir "$t" -o "$exe.o" >"$exe.log" 2>&1 \
            || { echo "-$level failed to compile it: $(head -3 "$exe.log")" >"$WORK/p$seed.why"; return; }
        # shellcheck disable=SC2086
        "$CC" $ARCH -o "$exe" "$exe.o" "$c.o" >>"$exe.log" 2>&1 \
            || { echo "-$level: cc failed: $(head -3 "$exe.log")" >"$WORK/p$seed.why"; return; }
        out=$("$exe" 2>&1)
        if [ "$out" != ok ]; then
            echo "-$level: $out" >"$WORK/p$seed.why"
            return
        fi
    done
    rm -f "$WORK/p$seed".O*
}

mkfifo "$WORK/slots"
exec 3<>"$WORK/slots"
i=0
while [ "$i" -lt "$JOBS" ]; do
    echo >&3
    i=$((i + 1))
done
last=$((FIRST + COUNT))
seed=$FIRST
while [ "$seed" -lt "$last" ]; do
    read -r _ <&3
    ( test_seed "$seed"; echo >&3 ) &
    seed=$((seed + 1))
done
wait
exec 3>&-

failures=0
signatures=0
seed=$FIRST
while [ "$seed" -lt "$last" ]; do
    signatures=$((signatures + $(cat "$WORK/p$seed.count" 2>/dev/null || echo 0)))
    if [ -f "$WORK/p$seed.why" ]; then
        failures=$((failures + 1))
        mkdir -p "$KEEP"
        cp "$WORK/p$seed.tach" "$WORK/p$seed.c" "$KEEP/"
        [ -f "$WORK/p$seed.h" ] && cp "$WORK/p$seed.h" "$KEEP/"
        echo "FAIL seed $seed: $(cat "$WORK/p$seed.why") (kept in $KEEP)"
    fi
    seed=$((seed + 1))
done
mode=""
[ "$IMPORT" = 1 ] && mode=" through import"
[ "$HEADER" = 1 ] && mode=" through --emit-header"
echo "abi: $COUNT programs ($signatures signatures) for $TARGET$mode, $failures failing"
[ "$failures" -eq 0 ]
