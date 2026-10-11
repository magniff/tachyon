#!/bin/sh
# Differential testing with random programs (gen.awk): each program is
# compiled at -O0, -O1 and -O2 (and by the seed, when given) and run; all
# must print the same. Mismatching programs are kept.
#
# usage: tests/fuzz/run.sh [-c COMPILER] [-s SEED] [-t TARGET] [-n COUNT]
#                          [-f FIRST] [-k DIR]
#
#   -c COMPILER   the tachyonc to test (default: target/tachyonc)
#   -s SEED       also compare with the seed binary (divisors are then
#                 positive: the seed traps on 0 and on MIN / -1)
#   -t TARGET     aarch64-macos, x86_64-linux or x86_64-macos (default:
#                 the host)
#   -n COUNT      number of programs (default 200)
#   -f FIRST      the first random seed (default 1)
#   -k DIR        where to keep failing programs (default: tests/fuzz/failures)

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
CC=${CC:-cc}
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -s) SEED=$2; shift 2 ;;
        -t) TARGET=$2; shift 2 ;;
        -n) COUNT=$2; shift 2 ;;
        -f) FIRST=$2; shift 2 ;;
        -k) KEEP=$2; shift 2 ;;
        *) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
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

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-fuzz.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
failures=0
seed=$FIRST
last=$((FIRST + COUNT))
while [ "$seed" -lt "$last" ]; do
    program="$WORK/p$seed.tach"
    awk -v seed="$seed" -v nonzero="$NONZERO" -f "$ROOT/tests/fuzz/gen.awk" >"$program"
    reference=""
    why=""
    for level in O0 O1 O2 seed; do
        exe="$WORK/p$seed.$level"
        if [ "$level" = seed ]; then
            [ -n "$SEED" ] || continue
            "$SEED" build --target "$SEED_TARGET" "$program" -o "$exe" >"$exe.log" 2>&1 \
                || { why="the seed failed to compile it"; break; }
        else
            "$COMPILER" --target "$TARGET" "-$level" --verify-ir "$program" -o "$exe.s" >"$exe.log" 2>&1 \
                || { why="-$level failed to compile it: $(head -3 "$exe.log")"; break; }
            # shellcheck disable=SC2086
            "$CC" $ARCH -o "$exe" "$exe.s" >>"$exe.log" 2>&1 || { why="-$level: cc failed"; break; }
        fi
        "$exe" >"$exe.out" 2>&1 || { why="$level: exit code $?"; break; }
        if [ -z "$reference" ]; then
            reference="$exe.out"
        elif ! cmp -s "$reference" "$exe.out"; then
            why="$level output differs from -O0"
            break
        fi
    done
    if [ -n "$why" ]; then
        failures=$((failures + 1))
        mkdir -p "$KEEP"
        cp "$program" "$KEEP/"
        echo "FAIL seed $seed: $why (kept as $KEEP/p$seed.tach)"
    fi
    seed=$((seed + 1))
done
echo "fuzz: $COUNT programs for $TARGET, $failures failing"
[ "$failures" -eq 0 ]
