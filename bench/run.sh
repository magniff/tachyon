#!/bin/sh
# Benchmarks: every bench/*.tach (and examples/md5/main.tach over 8 MB) compiled
# by tachyon at -O0, -O1 and -O2, by the previous release and the seed when
# given, and the C equivalents (bench/*.c) by cc -O2. Prints the fastest of
# RUNS runs of each, in milliseconds, and checks that all outputs agree;
# then, for each variant, the geometric mean over the programs with a C
# version of its time divided by cc -O2's (below 1: faster than C);
# last (0.14), the time of bench/iterchain.tach (iterator chains) over
# that of bench/iterloop.tach (the same loops by hand) at -O2, which fails
# the run above 1.05, and (0.15) the same for bench/fmtloop.tach
# (f-strings) over bench/fmtints.tach (Buf's push_int). Those ratios are
# measured on their own, robust to a busy machine: the two -O2 programs
# run alternately, RUNS rounds of one run each, and each side's time is
# its fastest round.
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
        *) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
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
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
# shellcheck disable=SC2086
"$CC" -O2 -o "$WORK/timer" "$ROOT/bench/timer.c"
dd if=/dev/zero of="$WORK/md5.in" bs=1048576 count=8 2>/dev/null
: >"$WORK/empty"
: >"$WORK/times"

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

for source in "$ROOT"/bench/*.tach "$ROOT/examples/md5/main.tach"; do
    name=$(basename "$source" .tach)
    # (an example is a directory: its name)
    [ "$name" = main ] && name=$(basename "$(dirname "$source")")
    input="$WORK/empty"
    [ "$name" = md5 ] && input="$WORK/md5.in"
    printf "%-10s" "$name"
    reference=""
    row=""
    for v in $VARIANTS; do
        if ! build "$source" "$v" "$WORK/$name.$v"; then
            printf " %9s" "-"
            row="$row -"
            continue
        fi
        ms=$("$WORK/timer" "$RUNS" "$input" "$WORK/$name.$v.out" "$WORK/$name.$v")
        printf " %9s" "$ms"
        row="$row $ms"
        if [ "$v" = O2 ]; then
            case "$name" in
                iterchain) CHAIN_MS=$ms ;;
                iterloop) LOOP_MS=$ms ;;
                fmtloop) FMT_MS=$ms ;;
                fmtints) INTS_MS=$ms ;;
            esac
        fi
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
        echo "$row $ms" >>"$WORK/times"
    else
        printf " %9s\n" "-"
    fi
done

# The geometric means of the ratios to cc -O2 (a time of 0 counts as 1 ms).
printf "%-10s" "geomean"
awk -v n="$(echo $VARIANTS | wc -w)" '
    { c = $NF < 1 ? 1 : $NF
      for (i = 1; i <= n; i++) if ($i != "-") { t = $i < 1 ? 1 : $i; sum[i] += log(t / c); cnt[i]++ } }
    END { for (i = 1; i <= n; i++) {
              if (cnt[i] > 0) printf " %9.3f", exp(sum[i] / cnt[i]); else printf " %9s", "-" }
          printf " %9s\n", "1" }' "$WORK/times"

# (0.14) Iterator chains against the same loops written by hand, at -O2:
# zero cost is a ratio of 1; above 1.05 is a failure. The two run
# alternately, the fastest of RUNS rounds each (noise from other work on
# the machine hits both sides alike, and the minimum drops most of it).
# (0.15) The same for f-strings (bench/fmtloop.tach) against the text
# made by hand with Buf's push_int (bench/fmtints.tach).
# usage: ratio NAME MS OTHER OTHER_MS WHAT
ratio() {
    a_ms=$2
    b_ms=$4
    round=0
    while [ $round -lt "$RUNS" ]; do
        ms=$("$WORK/timer" 1 "$WORK/empty" "$WORK/$1.round.out" "$WORK/$1.O2")
        [ "$ms" -lt "$a_ms" ] && a_ms=$ms
        ms=$("$WORK/timer" 1 "$WORK/empty" "$WORK/$3.round.out" "$WORK/$3.O2")
        [ "$ms" -lt "$b_ms" ] && b_ms=$ms
        round=$((round + 1))
    done
    printf "%-10s %9s %9s\n" "$1" "$a_ms" "(min of $((RUNS * 2)))"
    printf "%-10s %9s\n" "$3" "$b_ms"
    r=$(awk -v a="$a_ms" -v b="$b_ms" 'BEGIN { if (b < 1) b = 1; if (a < 1) a = 1; printf "%.3f", a / b }')
    printf "%-10s %9s\n" "$1/$3" "$r"
    if awk -v r="$r" 'BEGIN { exit !(r > 1.05) }'; then
        echo "bench: $1/$3 is $r, above 1.05: $5 are not zero cost" >&2
        exit 1
    fi
}
if [ -n "${CHAIN_MS:-}" ] && [ -n "${LOOP_MS:-}" ]; then
    ratio iterchain "$CHAIN_MS" iterloop "$LOOP_MS" "iterator chains"
fi
if [ -n "${FMT_MS:-}" ] && [ -n "${INTS_MS:-}" ]; then
    ratio fmtloop "$FMT_MS" fmtints "$INTS_MS" "f-strings"
fi
