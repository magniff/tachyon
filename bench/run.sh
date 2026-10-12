#!/bin/sh
# Benchmarks: every bench/*.tach (and examples/md5.tach over 8 MB) compiled
# by tachyon at -O0, -O1 and -O2, by the previous release and the seed when
# given, and the C equivalents (bench/*.c) by cc -O2. Prints the fastest of
# RUNS runs of each, in milliseconds, and checks that all outputs agree.
#
# usage: bench/run.sh [-c COMPILER] [-p PREVIOUS] [-s SEED] [-r RUNS] [-t TARGET]
#
#   -c COMPILER   the tachyonc to measure (default: target/tachyonc)
#   -p PREVIOUS   another tachyonc (e.g. the previous release), at its
#                 default level
#   -s SEED       the seed binary (`tachyon build -O`)
#   -r RUNS       runs per measurement (default 5)
#   -t TARGET     the target (default: the host)

set -eu
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/tachyonc"
PREVIOUS=""
SEED=""
RUNS=5
TARGET=""
CC=${CC:-cc}
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -p) PREVIOUS=$2; shift 2 ;;
        -s) SEED=$2; shift 2 ;;
        -r) RUNS=$2; shift 2 ;;
        -t) TARGET=$2; shift 2 ;;
        *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
if [ -z "$TARGET" ]; then
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) TARGET=aarch64-macos ;;
        Darwin-x86_64) TARGET=x86_64-macos ;;
        Linux-x86_64) TARGET=x86_64-linux ;;
        *) echo "bench: unknown host" >&2; exit 2 ;;
    esac
fi
case "$TARGET" in
    aarch64-macos) ARCH="-arch arm64"; SEED_TARGET=macos-aarch64 ;;
    x86_64-macos) ARCH="-arch x86_64"; SEED_TARGET=macos-x86_64 ;;
    *) ARCH=""; SEED_TARGET=linux-x86_64 ;;
esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-bench.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
# shellcheck disable=SC2086
"$CC" -O2 -o "$WORK/timer" "$ROOT/bench/timer.c"
dd if=/dev/zero of="$WORK/md5.in" bs=1048576 count=8 2>/dev/null
: >"$WORK/empty"

# Builds variant $2 of program $1 (a .tach file) into $3; fails when that
# compiler does not know the program's language (the previous release and
# the seed do not know what came after them).
build() {
    case "$2" in
        # (from 0.7 the compiler writes objects; the previous release may
        # only write assembly)
        O0|O1|O2) "$COMPILER" --target "$TARGET" "-$2" "$1" -o "$3.o"
            # shellcheck disable=SC2086
            "$CC" $ARCH -o "$3" "$3.o" -lm
            return ;;
        previous) "$PREVIOUS" --target "$TARGET" "$1" -o "$3.s" >/dev/null 2>&1 || return 1 ;;
        seed)
            # The seed knows only 0.2's declarations of C functions.
            awk -f "$ROOT/tests/seed-compat.awk" "$1" >"$3.tach"
            "$SEED" build -O --target "$SEED_TARGET" "$3.tach" -o "$3" >/dev/null 2>&1
            return ;;
    esac
    # shellcheck disable=SC2086
    "$CC" $ARCH -o "$3" "$3.s" -lm
}

VARIANTS="O0 O1 O2"
[ -n "$PREVIOUS" ] && VARIANTS="previous $VARIANTS"
[ -n "$SEED" ] && VARIANTS="$VARIANTS seed"
printf "%-10s" "program"
for v in $VARIANTS; do printf " %9s" "$v"; done
printf " %9s\n" "cc -O2"

for source in "$ROOT"/bench/*.tach "$ROOT/examples/md5.tach"; do
    name=$(basename "$source" .tach)
    input="$WORK/empty"
    [ "$name" = md5 ] && input="$WORK/md5.in"
    printf "%-10s" "$name"
    reference=""
    for v in $VARIANTS; do
        if ! build "$source" "$v" "$WORK/$name.$v"; then
            printf " %9s" "-"
            continue
        fi
        ms=$("$WORK/timer" "$RUNS" "$input" "$WORK/$name.$v.out" "$WORK/$name.$v")
        printf " %9s" "$ms"
        if [ -z "$reference" ]; then
            reference="$WORK/$name.$v.out"
        elif ! cmp -s "$reference" "$WORK/$name.$v.out"; then
            echo; echo "bench: $name: the $v output differs" >&2; exit 1
        fi
    done
    c="$ROOT/bench/$name.c"
    if [ -f "$c" ]; then
        # shellcheck disable=SC2086
        "$CC" $ARCH -O2 -o "$WORK/$name.c.bin" "$c" -lm
        ms=$("$WORK/timer" "$RUNS" "$input" "$WORK/$name.c.out" "$WORK/$name.c.bin")
        cmp -s "$reference" "$WORK/$name.c.out" || { echo; echo "bench: $name: the C output differs" >&2; exit 1; }
        printf " %9s\n" "$ms"
    else
        printf " %9s\n" "-"
    fi
done
