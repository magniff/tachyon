#!/bin/sh
# Every intrinsic of the tables against a scalar reference (0.19,
# docs/design/arch.md §6). tests/arch/gen.awk writes, from each table
# (compiler/arch/portable.def, aarch64.def, x86_64.def), one program per
# family (the table's `# ---- Family ----` sections, 40 intrinsics at
# most each): target/arch-tests/arch_<a64|x86|portable>_<family>.tach.
# Each intrinsic is called
#
#   - at run time, on inputs the optimizer cannot see: every pair of edge
#     values (0, 1, 2, MAX, MIN, MIN + 1, -2, -1, 0x55.., 0x33..; floats:
#     ±0, ±1, ±inf, NaN, the least denormal, MAX, the least normal) of
#     its first two inputs, mixed edges, random values (-r), and every
#     value (one 8-bit input) or every pair (two) of its 8-bit inputs;
#     a memory form at every index of a slice twice its size;
#   - with constant arguments, edges and random lanes, which -O1 and -O2
#     may fold: a fold must agree with the instruction;
#   - for every value of a constant parameter (a range of 16 or more: its
#     ends, the middle and three more), so every immediate's extremes are
#     encoded,
#
# and each result is compared, lane by lane, with the reference: the
# table's `semantics` column, translated (compiler/arch/README.md,
# "Semantics"), or, when the column is prose, `fn ref_NAME` in
# tests/arch/ref/*.tach. The reference takes the intrinsic's parameters
# (a vector or a slice as its lanes, `[D]`; a scalar as `D`; a constant
# or an index as `i64`; the slice of a store as `inout [D]`, which it
# writes) and, for a vector result, the lane `k: i64`, and returns that
# lane (or the scalar) as `D`: D is i64 for integers narrower than 64
# bits, the lane type itself for 64-bit ones, f64 for floats. A ref file
# holds only functions; its helpers' names must be its own. A failure
# prints `FAIL NAME`, the inputs and the lane.
#
# --check builds each program at each level (-O): the host's
# architecture's programs (and the portable ones) are run and must
# report no failure; the other architecture's are compiled and assembled
# for its Linux and macOS targets (x86-64 is not executed). An intrinsic
# the generator cannot test (prose semantics and no ref_NAME, a type it
# does not know) is an error.
#
# usage: tests/arch/gen.sh [-c COMPILER] [-o DIR] [-r N] [-O LEVELS] [-j JOBS] [--check] [FILTER]
#
#   -c COMPILER   the tachyonc to build with (default: target/tachyonc)
#   -o DIR        where the programs go (default: target/arch-tests)
#   -r N          random cases per intrinsic (default 2000; memory forms
#                 take N / 50 + 4, at every index)
#   -O LEVELS     the levels to build at, comma-separated (default 0,2)
#   -j JOBS       builds at once (default: the CPUs, or the slots of
#                 $TACHYON_JOBSERVER, see tests/run.sh)
#   --check       then build, run and check them
#   FILTER        only the programs whose name contains FILTER
set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
COMPILER="$ROOT/target/tachyonc"
OUT="$ROOT/target/arch-tests"
RANDOM_N=2000
LEVELS="0,2"
JOBS=""
CHECK=0
FILTER=""
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -o) OUT=$2; shift 2 ;;
        -r) RANDOM_N=$2; shift 2 ;;
        -O) LEVELS=$2; shift 2 ;;
        -j) JOBS=$2; shift 2 ;;
        --check) CHECK=1; shift ;;
        -*) sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
        *) FILTER=$1; shift ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
mkdir -p "$OUT"
rm -f "$OUT"/arch_*.tach

# The hand-written references: `NAME PATH` for each `fn ref_NAME(`.
for f in "$ROOT"/tests/arch/ref/*.tach; do
    [ -f "$f" ] || continue
    sed -n 's/^fn ref_\([A-Za-z0-9_]*\)(.*/\1/p' "$f" | while read -r n; do echo "$n $f"; done
done >"$OUT/refs"

status=0
: >"$OUT/gen.log"
for t in portable aarch64 x86_64; do
    awk -v table="$t" -v out="$OUT" -v nrandom="$RANDOM_N" -v refs="$OUT/refs" \
        -f "$ROOT/tests/arch/gen.awk" "$ROOT/compiler/arch/$t.def" >>"$OUT/gen.log" || status=1
done
grep '^error' "$OUT/gen.log" | sed 's/^/gen: /'
grep -q '^error' "$OUT/gen.log" && status=1
programs=""
for p in $(sed -n 's/^program //p' "$OUT/gen.log"); do
    case "$(basename "$p")" in *"$FILTER"*) programs="$programs $p" ;; esac
done
ntests=0
[ -z "$programs" ] || ntests=$(cat $programs | grep -c '^fn test_')
echo "gen: $(echo $programs | wc -w | tr -d ' ') programs, $ntests intrinsics, $(grep -c '^skip' "$OUT/gen.log") skipped, $(grep -c '^error' "$OUT/gen.log") not testable"
[ "$CHECK" = 1 ] || exit $status

host=$("$COMPILER" --version | sed 's/.*host: \([a-z0-9_]*\)-\([a-z]*\).*/\1/')

# One build (and run): program $1 at level $2; $3 a target to compile
# for without running, or "" for the host. A line `ok ...` or `FAIL ...`.
build() {
    p=$1 o=$2 t=$3
    b="$OUT/$(basename "$p" .tach).O$o${t:+.$t}"
    if [ -n "$t" ]; then
        "$COMPILER" "-O$o" --target "$t" -c "$p" -o "$b.o" >"$b.log" 2>&1 \
            || { echo "FAIL $(basename "$p") -O$o --target $t: $(grep -v '^ok' "$b.log" | head -3)"; return; }
        rm -f "$b.o"
        echo "ok $(basename "$p") -O$o --target $t"
        return
    fi
    "$COMPILER" "-O$o" "$p" -o "$b" >"$b.log" 2>&1 \
        || { echo "FAIL $(basename "$p") -O$o: $(grep -v '^ok' "$b.log" | head -3)"; return; }
    "$b" >"$b.out" 2>&1
    rc=$?
    rm -f "$b"
    if [ $rc -ne 0 ] || grep -q '^FAIL' "$b.out"; then
        echo "FAIL $(basename "$p") -O$o: exit $rc"
        grep '^FAIL' "$b.out" | head -5 | sed 's/^/    /'
        tail -1 "$b.out" | sed 's/^/    /'
        return
    fi
    echo "ok $(basename "$p") -O$o"
}

# The slots: JOBS of them, or the ones $TACHYON_JOBSERVER shares (see
# tests/run.sh).
if [ -z "$JOBS" ] && [ -n "${TACHYON_JOBSERVER:-}" ] && [ -p "$TACHYON_JOBSERVER" ]; then
    exec 3<>"$TACHYON_JOBSERVER"
else
    [ -n "$JOBS" ] || JOBS=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
    rm -f "$OUT/slots"
    mkfifo "$OUT/slots"
    exec 3<>"$OUT/slots"
    i=0
    while [ "$i" -lt "$JOBS" ]; do
        echo >&3
        i=$((i + 1))
    done
fi
n=0
for p in $programs; do
    case "$(basename "$p")" in
        arch_a64_*) native=aarch64 ;;
        arch_x86_*) native=x86_64 ;;
        *) native=$host ;;
    esac
    for o in $(echo "$LEVELS" | tr ',' ' '); do
        if [ "$native" = "$host" ]; then
            targets="-"
        else
            targets="$native-linux $native-macos"
        fi
        # (the portable programs, also for the other architecture)
        case "$(basename "$p")" in
            arch_portable_*) [ "$host" = aarch64 ] && targets="- x86_64-linux" || targets="- aarch64-linux" ;;
        esac
        for t in $targets; do
            [ "$t" = - ] && t=""
            n=$((n + 1))
            read -r _ <&3
            ( build "$p" "$o" "$t" >"$OUT/result.$n"; echo >&3 ) &
        done
    done
done
wait
exec 3>&-
rm -f "$OUT/slots"
i=1
failed=0
while [ "$i" -le "$n" ]; do
    if ! grep -q '^ok' "$OUT/result.$i"; then
        failed=$((failed + 1))
        cat "$OUT/result.$i"
    fi
    rm -f "$OUT/result.$i"
    i=$((i + 1))
done
echo "gen: $n builds, $failed failing"
[ "$failed" -eq 0 ] || status=1
[ $status = 0 ] && echo "gen: ok"
exit $status
