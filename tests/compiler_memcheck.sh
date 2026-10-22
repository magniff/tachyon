#!/bin/sh
# (0.25) The compiler under macOS's memory checkers, beside valgrind's
# memcheck on Linux (tests/valgrind.sh, the gate's --release):
#
#   checkalloc  the compiler built with --check-alloc (the checking Gpa:
#               every block on pages of its own, never reused): a use
#               after free, a double free or a wrong free of Gpa memory
#               stops it. Leaks are listed and allowed (the compiler
#               leaves its memory to the exit, by design). At -j1: the
#               checking Gpa is not thread-safe (0.25.1).
#   gmalloc     the compiler as built, under Guard Malloc
#               (/usr/lib/libgmalloc.dylib, MallocScribble): the same for
#               the memory it takes from malloc directly (its tables,
#               base::grow), which the checking Gpa does not see; a bad
#               access faults.
#
# What each compiles: its own self-compile (-O0, and -O2 at -j4 under
# checkalloc), then the cases tests/valgrind.sh takes (opt_*, own_*,
# contract_* and a few examples) at -O0 and -O2. Every compilation must
# end as the plain compiler's does (the same exit status) and write the
# same object; under checkalloc nothing but leak lines may come from the
# checking allocator.
#
# usage: tests/compiler_memcheck.sh [-c COMPILER] [-m checkalloc|gmalloc|both] [-j JOBS] [FILTER]
set -u
LC_ALL=C
export LC_ALL
VOLE_CODE_CACHE=off
VOLE_CACHE=off
export VOLE_CODE_CACHE VOLE_CACHE

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/volec"
MODE=both
JOBS=""
FILTER=""
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -m) MODE=$2; shift 2 ;;
        -j) JOBS=$2; shift 2 ;;
        -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
        *) FILTER=$1; shift ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
case "$MODE" in checkalloc|gmalloc|both) ;; *) echo "compiler-memcheck: -m is checkalloc, gmalloc or both"; exit 2 ;; esac
GMALLOC=/usr/lib/libgmalloc.dylib
if [ "$MODE" != checkalloc ] && [ ! -f "$GMALLOC" ]; then
    [ "$MODE" = gmalloc ] && { echo "compiler-memcheck: no $GMALLOC (macOS only)"; exit 77; }
    MODE=checkalloc
fi
TARGET=$("$COMPILER" --version | sed 's/.*host: \([a-z0-9_-]*\).*/\1/')
SRC="compiler/src/main.vl"
WORK="$ROOT/target/compiler-memcheck"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$ROOT" || exit 1

CHECKED="$WORK/volec-checked"
if [ "$MODE" != gmalloc ]; then
    "$COMPILER" --check-alloc -O2 "$SRC" -o "$CHECKED" >"$WORK/build.log" 2>&1 \
        || { cat "$WORK/build.log"; echo "compiler-memcheck: the compiler does not build with --check-alloc"; exit 1; }
fi

# <how> <file> <level> <n> [options...]: one compilation by the plain
# compiler and by the checked one; "ok ..." or "FAIL ..." on stdout.
check() {
    ch_how=$1 ch_f=$2 ch_o=$3 ch_d="$WORK/$4"
    shift 4
    # shellcheck disable=SC2086
    "$COMPILER" "-O$ch_o" "$@" -c "$ch_f" -o "$ch_d.plain.o" >"$ch_d.plain.out" 2>&1
    ch_rc0=$?
    case "$ch_how" in
        checkalloc)
            # (-j1: the checking Gpa keeps its blocks in statics with no
            # lock, so the compiler's worker threads, which allocate from
            # it at -O1 and -O2, race in the checker itself: false reports
            # under load. The objects are the same at every -j.)
            "$CHECKED" "-O$ch_o" "$@" -j1 -c "$ch_f" -o "$ch_d.o" >"$ch_d.out" 2>&1 ;;
        gmalloc)
            DYLD_INSERT_LIBRARIES=$GMALLOC MallocScribble=1 MALLOC_PERMIT_INSANE_REQUESTS=1 \
                "$COMPILER" "-O$ch_o" "$@" -c "$ch_f" -o "$ch_d.o" >"$ch_d.out" 2>&1 ;;
    esac
    ch_rc=$?
    ch_what="$ch_how $ch_f -O$ch_o $*"
    if [ $ch_rc -ne $ch_rc0 ]; then
        echo "FAIL $ch_what: exit $ch_rc, $ch_rc0 without the checker ($ch_d.out):"
        tail -8 "$ch_d.out"
    elif grep -v -e '^check-alloc: [0-9]* blocks* of Gpa not freed' -e '^  block #[0-9]* (' "$ch_d.out" \
        | grep -q -e '^check-alloc:' -e 'GuardMalloc\[.*\]: .*error' ; then
        echo "FAIL $ch_what: the checker reports ($ch_d.out):"
        grep -e '^check-alloc:' -e 'GuardMalloc' "$ch_d.out" | head -8
    elif [ -f "$ch_d.plain.o" ] && ! cmp -s "$ch_d.plain.o" "$ch_d.o"; then
        echo "FAIL $ch_what: another object than without the checker ($ch_d.o)"
    else
        echo "ok $ch_what"
    fi
}

list="$WORK/list"
: >"$list"
for f in tests/run/opt_*.vl tests/run/own_*.vl tests/run/contract_*.vl \
    tests/run/opt_*/main.vl tests/run/own_*/main.vl tests/run/contract_*/main.vl \
    examples/md5/main.vl examples/calc/main.vl examples/life/main.vl \
    examples/httpd/main.vl examples/algorithms/huffman/main.vl \
    examples/algorithms/bigint/main.vl examples/closures-iterators/main.vl; do
    [ -f "$f" ] || continue
    case "$f" in *"$FILTER"*) ;; *) continue ;; esac
    echo "$f" >>"$list"
done
if [ -z "$JOBS" ] && [ -n "${VOLE_JOBSERVER:-}" ] && [ -p "$VOLE_JOBSERVER" ]; then
    exec 3<>"$VOLE_JOBSERVER"
else
    [ -n "$JOBS" ] || JOBS=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
    rm -f "$WORK/slots"
    mkfifo "$WORK/slots"
    exec 3<>"$WORK/slots"
    i=0
    while [ "$i" -lt "$JOBS" ]; do
        echo >&3
        i=$((i + 1))
    done
fi
n=0
hows=$([ "$MODE" = both ] && echo "checkalloc gmalloc" || echo "$MODE")
for how in $hows; do
    case "$SRC" in
        *"$FILTER"*)
            n=$((n + 1)); read -r _ <&3
            ( check "$how" "$SRC" 0 "$n" >"$WORK/$n.result"; echo >&3 ) &
            if [ "$how" = checkalloc ]; then
                n=$((n + 1)); read -r _ <&3
                ( check "$how" "$SRC" 2 "$n" -j4 >"$WORK/$n.result"; echo >&3 ) &
            fi ;;
    esac
    while read -r f; do
        dd="$WORK/directives/$(echo "$f" | tr / _)"
        mkdir -p "$dd"
        case "$f" in tests/run/*) awk -v dir="$dd" -v target="$TARGET" -f tests/directives.awk "$f" ;; esac
        flags=""
        [ ! -f "$dd/flags" ] || flags=$(sed "s|@ROOT@|$ROOT|g" "$dd/flags")
        for o in 0 2; do
            n=$((n + 1)); read -r _ <&3
            # shellcheck disable=SC2086
            ( check "$how" "$f" "$o" "$n" $flags >"$WORK/$n.result"; echo >&3 ) &
        done
    done <"$list"
done
wait
exec 3>&-
i=1
ok=0
failed=0
while [ "$i" -le "$n" ]; do
    if grep -q '^ok' "$WORK/$i.result"; then
        ok=$((ok + 1))
    else
        failed=$((failed + 1))
        cat "$WORK/$i.result"
    fi
    i=$((i + 1))
done
echo "compiler-memcheck: $ok of $n compilations clean ($hows, $TARGET)$([ $failed -eq 0 ] || echo ", $failed failed")"
[ "$failed" -eq 0 ] && [ "$n" -gt 0 ]
