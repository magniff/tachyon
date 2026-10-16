#!/bin/sh
# Differential testing with random programs (gen.awk): each program is
# compiled at -O0, -O1 and -O2 (and by the seed, when given) and run; all
# must print the same. Mismatching programs are kept.
#
# usage: tests/fuzz/run.sh [-c COMPILER] [-s SEED] [-t TARGET] [-n COUNT]
#                          [-f FIRST] [-k DIR] [-j JOBS] [-l] [-g] [-p] [-C] [-N]
#                          [-V] [-D] [-R]
#
#   -c COMPILER   the tachyonc to test (default: target/tachyonc)
#   -s SEED       also compare with the seed binary (divisors are then
#                 positive: the seed traps on 0 and on MIN / -1)
#   -t TARGET     aarch64-macos, aarch64-linux, x86_64-linux or
#                 x86_64-macos (default: the host)
#   -n COUNT      number of programs (default 200)
#   -f FIRST      the first random seed (default 1)
#   -k DIR        where to keep failing programs (default: tests/fuzz/failures)
#   -l            the loop mode of gen.awk (more loops, slices, test chains)
#   -g            the generics mode of gen.awk (0.5)
#   -p            the pressure mode of gen.awk (many parameters and locals)
#   -C            the calls mode of gen.awk (aggregates passed and returned)
#   -N            the 0.6 language mode of gen.awk (defer, if let, ==, strings)
#   -V            vectorizable loops and vector code, from genvec.awk (0.10)
#   -D            divisions by constants of every type, from gendiv.awk
#                 (0.11), each also checked against a division by an
#                 unknown divisor (a FAIL line is a failure; not run by
#                 the seed, which traps on 0)
#   -R            loops indexing arrays of fixed sizes with steps of any
#                 kind, from genrange.awk (0.11: ranges through phis)
#   -j JOBS       programs tested at once (default: the number of CPUs,
#                 or the slots of $TACHYON_JOBSERVER, see tests/run.sh)

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
        -V) VECTOR=1; shift ;;
        -D) DIVIDE=1; shift ;;
        -R) RANGES=1; shift ;;
        -j) JOBS=$2; shift 2 ;;
        *) sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
if [ -z "$TARGET" ]; then
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) TARGET=aarch64-macos ;;
        Darwin-x86_64) TARGET=x86_64-macos ;;
        Linux-x86_64) TARGET=x86_64-linux ;;
        Linux-aarch64) TARGET=aarch64-linux ;;
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
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM

# The C compiler, once more when it crashed (a signal, or gcc's "internal
# compiler error"): an emulated toolchain (x86-64 Linux under Rosetta)
# now and then does, and a crash of cc is not tachyon's. Its output (and
# the crash's, if any) on stdout.
cc_run() {
    cr_out=$("$CC" "$@" 2>&1)
    cr_rc=$?
    if [ $cr_rc -ne 0 ]; then
        case "$cr_rc:$cr_out" in
            1[3-9][0-9]:*|2[0-9][0-9]:*|*"internal compiler error"*|*"Segmentation fault"*|*"Bus error"*)
                printf '%s\n(%s crashed, exit %d: run again)\n' "$cr_out" "$CC" "$cr_rc"
                cr_out=$("$CC" "$@" 2>&1)
                cr_rc=$? ;;
        esac
    fi
    [ -z "$cr_out" ] || printf '%s\n' "$cr_out"
    return $cr_rc
}

# Tests program $1 (a random seed); why it fails, if it does, in
# $WORK/p$1.why.
test_seed() {
    seed=$1
    program="$WORK/p$seed.tach"
    if [ "${VECTOR:-0}" = 1 ]; then
        awk -v seed="$seed" -f "$ROOT/tests/fuzz/genvec.awk" >"$program"
    elif [ "${RANGES:-0}" = 1 ]; then
        awk -v seed="$seed" -f "$ROOT/tests/fuzz/genrange.awk" >"$program"
    elif [ "${DIVIDE:-0}" = 1 ]; then
        awk -v seed="$seed" -v iterations=500 -f "$ROOT/tests/fuzz/gendiv.awk" >"$program"
    else
        awk -v seed="$seed" -v nonzero="$NONZERO" -v loops="${LOOPS:-0}" -v generics="${GENERICS:-0}" -v pressure="${PRESSURE:-0}" -v calls="${CALLS:-0}" -v lang06="${LANG06:-0}" -f "$ROOT/tests/fuzz/gen.awk" >"$program"
    fi
    reference=""
    why=""
    for level in O0 O1 O2 seed; do
        exe="$WORK/p$seed.$level"
        if [ "$level" = seed ]; then
            [ -n "$SEED" ] && [ "${DIVIDE:-0}" = 0 ] || continue
            awk -f "$ROOT/tests/seed-compat.awk" "$program" >"$exe.tach"
            "$SEED" build --target "$SEED_TARGET" "$exe.tach" -o "$exe" >"$exe.log" 2>&1 \
                || { why="the seed failed to compile it"; break; }
        else
            # (0.17: --values=off. The programs are 0.16 code: slices
            # written through `let sl = a[..]` while a is read, and
            # genvec.awk's kernels aliased on purpose, for the run-time
            # alias checks; the own pass is not what they test, and they
            # hold no owned or reference values, so their code is the
            # default's)
            "$COMPILER" --target "$TARGET" "-$level" --deny-warnings --verify-ir --values=off "$program" -o "$exe.o" >"$exe.log" 2>&1 \
                || { why="-$level failed to compile it: $(head -3 "$exe.log")"; break; }
            # shellcheck disable=SC2086
            cc_run $ARCH -o "$exe" "$exe.o" >>"$exe.log" 2>&1 || { why="-$level: cc failed"; break; }
        fi
        # The exit status is part of the output (a bounds check exits
        # with 101, alike at every level).
        "$exe" >"$exe.out" 2>&1
        echo "exit $?" >>"$exe.out"
        if grep -q '^FAIL' "$exe.out"; then
            why="-$level: $(grep '^FAIL' "$exe.out" | head -1)"
            break
        fi
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

# The slots: JOBS of them, or (0.11) the ones $TACHYON_JOBSERVER shares
# between the runners of bootstrap/gate.sh (see tests/run.sh).
if [ -z "$JOBS" ] && [ -n "${TACHYON_JOBSERVER:-}" ] && [ -p "$TACHYON_JOBSERVER" ]; then
    exec 3<>"$TACHYON_JOBSERVER"
else
    if [ -z "$JOBS" ]; then
        JOBS=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 4)
        case "$JOBS" in ''|*[!0-9]*) JOBS=4 ;; esac
    fi
    mkfifo "$WORK/slots"
    exec 3<>"$WORK/slots"
    i=0
    while [ "$i" -lt "$JOBS" ]; do
        echo >&3
        i=$((i + 1))
    done
fi
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
