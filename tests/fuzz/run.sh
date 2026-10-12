#!/bin/sh
# Differential testing with random programs (gen.awk): each program is
# compiled at -O0, -O1 and -O2 (and by the seed, when given) and run; all
# must print the same. Mismatching programs are kept.
#
# usage: tests/fuzz/run.sh [-c COMPILER] [-s SEED] [-t TARGET] [-n COUNT]
#                          [-f FIRST] [-k DIR] [-j JOBS] [-l] [-g] [-p] [-C] [-N]
#
#   -c COMPILER   the tachyonc to test (default: target/tachyonc)
#   -s SEED       also compare with the seed binary (divisors are then
#                 positive: the seed traps on 0 and on MIN / -1)
#   -t TARGET     aarch64-macos, x86_64-linux or x86_64-macos (default:
#                 the host)
#   -n COUNT      number of programs (default 200)
#   -f FIRST      the first random seed (default 1)
#   -k DIR        where to keep failing programs (default: tests/fuzz/failures)
#   -l            the loop mode of gen.awk (more loops, slices, test chains)
#   -g            the generics mode of gen.awk (0.5)
#   -p            the pressure mode of gen.awk (many parameters and locals)
#   -C            the calls mode of gen.awk (aggregates passed and returned)
#   -N            the 0.6 language mode of gen.awk (defer, if let, ==, strings)
#   -j JOBS       programs tested at once (default: the number of CPUs)

set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
COMPILER="$ROOT/target/tachyonc"
SEED=""
TARGET=""
COUNT=200
FIRST=1
KEEP="$ROOT/tests/fuzz/failures"
JOBS=""
CC=${CC:-cc}
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -s) SEED=$2; shift 2 ;;
        -t) TARGET=$2; shift 2 ;;
        -n) COUNT=$2; shift 2 ;;
        -f) FIRST=$2; shift 2 ;;
        -k) KEEP=$2; shift 2 ;;
        -l) LOOPS=1; shift ;;
        -g) GENERICS=1; shift ;;
        -p) PRESSURE=1; shift ;;
        -C) CALLS=1; shift ;;
        -N) LANG06=1; shift ;;
        -j) JOBS=$2; shift 2 ;;
        *) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
if [ -z "$TARGET" ]; then
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) TARGET=aarch64-macos ;;
        Darwin-x86_64) TARGET=x86_64-macos ;;
        Linux-x86_64) TARGET=x86_64-linux ;;
        *) echo "fuzz: unknown host" >&2; exit 2 ;;
    esac
fi
case "$TARGET" in
    aarch64-macos) ARCH="-arch arm64"; SEED_TARGET=macos-aarch64 ;;
    x86_64-macos) ARCH="-arch x86_64"; SEED_TARGET=macos-x86_64 ;;
    *) ARCH=""; SEED_TARGET=linux-x86_64 ;;
esac
NONZERO=0
[ -n "$SEED" ] && NONZERO=1

if [ -z "$JOBS" ]; then
    JOBS=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 4)
    case "$JOBS" in ''|*[!0-9]*) JOBS=4 ;; esac
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-fuzz.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

# Tests program $1 (a random seed); why it fails, if it does, in
# $WORK/p$1.why.
test_seed() {
    seed=$1
    program="$WORK/p$seed.tach"
    awk -v seed="$seed" -v nonzero="$NONZERO" -v loops="${LOOPS:-0}" -v generics="${GENERICS:-0}" -v pressure="${PRESSURE:-0}" -v calls="${CALLS:-0}" -v lang06="${LANG06:-0}" -f "$ROOT/tests/fuzz/gen.awk" >"$program"
    reference=""
    why=""
    for level in O0 O1 O2 seed; do
        exe="$WORK/p$seed.$level"
        if [ "$level" = seed ]; then
            [ -n "$SEED" ] || continue
            awk -f "$ROOT/tests/seed-compat.awk" "$program" >"$exe.tach"
            "$SEED" build --target "$SEED_TARGET" "$exe.tach" -o "$exe" >"$exe.log" 2>&1 \
                || { why="the seed failed to compile it"; break; }
        else
            "$COMPILER" --target "$TARGET" "-$level" --verify-ir "$program" -o "$exe.o" >"$exe.log" 2>&1 \
                || { why="-$level failed to compile it: $(head -3 "$exe.log")"; break; }
            # shellcheck disable=SC2086
            "$CC" $ARCH -o "$exe" "$exe.o" >>"$exe.log" 2>&1 || { why="-$level: cc failed"; break; }
        fi
        # The exit status is part of the output (a bounds check exits
        # with 101, alike at every level).
        "$exe" >"$exe.out" 2>&1
        echo "exit $?" >>"$exe.out"
        if [ -z "$reference" ]; then
            reference="$exe.out"
        elif ! cmp -s "$reference" "$exe.out"; then
            why="$level output differs from -O0"
            break
        fi
    done
    [ -n "$why" ] && echo "$why" >"$WORK/p$seed.why"
    rm -f "$WORK/p$seed".O* "$WORK/p$seed".seed*
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
seed=$FIRST
while [ "$seed" -lt "$last" ]; do
    if [ -f "$WORK/p$seed.why" ]; then
        failures=$((failures + 1))
        mkdir -p "$KEEP"
        cp "$WORK/p$seed.tach" "$KEEP/"
        echo "FAIL seed $seed: $(cat "$WORK/p$seed.why") (kept as $KEEP/p$seed.tach)"
    fi
    seed=$((seed + 1))
done
echo "fuzz: $COUNT programs for $TARGET, $failures failing"
[ "$failures" -eq 0 ]
