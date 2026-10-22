#!/bin/sh
# The compiler under valgrind's memcheck (0.18.1): its -O2 self-compile
# at -j4, then a representative set of compilations, the opt_*, own_* and
# contract_* cases of tests/run and a few examples, at -O0 and -O2. Any
# invalid read or write, or use of an uninitialised value, fails the
# check; leaks do not (the compiler leaves its memory to the exit, by
# design). Valgrind follows only the compiler, not the assembler or the
# linker it starts. Two memory bugs of 0.17 (an SLP table overflow, a read
# of the own pass's place -1) passed every macOS check and showed here.
# Run by bootstrap/gate.sh --release in the linux-aarch64 container (step
# valgrind); needs valgrind.
#
# usage: tests/valgrind.sh [-c COMPILER] [-j JOBS] [FILTER]
#
#   -c COMPILER   the volec to check (default: target/volec)
#   -j JOBS       compilations at once (default: the number of CPUs, or
#                 the slots of $VOLE_JOBSERVER, see tests/run.sh)
#   FILTER        only the programs whose path contains FILTER (the
#                 self-compile too: its path is compiler/src/main.vl)

set -u
LC_ALL=C
export LC_ALL
# (each compilation from its source, not the code cache's objects)
VOLE_CODE_CACHE=off
export VOLE_CODE_CACHE

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/volec"
JOBS=""
FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -j) JOBS=$2; shift 2 ;;
        -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
        *) FILTER=$1; shift ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
command -v valgrind >/dev/null 2>&1 || { echo "valgrind: not installed here (the step runs in the linux-aarch64 container)"; exit 77; }
TARGET=$("$COMPILER" --version | sed 's/.*host: \([a-z0-9_-]*\).*/\1/')
WORK="$ROOT/target/valgrind"
rm -rf "$WORK"
mkdir -p "$WORK"

# One compilation under memcheck: its log in $3.log, "ok" or "FAIL ..." on
# stdout. A compilation may fail by design (a case of ERROR directives);
# only valgrind's own errors count.
check() { # <file> <level> <dir> [options...]
    f=$1 o=$2 d=$3
    shift 3
    # shellcheck disable=SC2086
    valgrind --tool=memcheck --error-exitcode=1 --leak-check=no --track-origins=yes \
        --log-file="$d.log" "$COMPILER" "-O$o" "$@" -c "$f" -o "$d.o" >"$d.out" 2>&1
    rc=$?
    errors=$(sed -n 's/.*ERROR SUMMARY: \([0-9]*\) errors.*/\1/p' "$d.log" | tail -1)
    if [ -z "$errors" ]; then
        echo "FAIL $f -O$o $*: valgrind gave no summary (exit $rc): $(tail -3 "$d.log" | tr '\n' ' ')"
    elif [ "$errors" -ne 0 ]; then
        echo "FAIL $f -O$o $*: $errors memory errors ($d.log):"
        grep -E '^==[0-9]+== (Invalid|Conditional|Use of uninit|Syscall param|Source and dest|Mismatched|  *(at|by) )' "$d.log" | head -20
    else
        echo "ok $f -O$o $*"
    fi
}

cd "$ROOT" || exit 1
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
# The slots: JOBS of them, or the ones $VOLE_JOBSERVER shares.
if [ -z "$JOBS" ] && [ -n "${VOLE_JOBSERVER:-}" ] && [ -p "$VOLE_JOBSERVER" ]; then
    exec 3<>"$VOLE_JOBSERVER"
else
    [ -n "$JOBS" ] || JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
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
# The self-compile first (the longest): -O2 at -j4, the compiler's threads
# under valgrind's.
case "compiler/src/main.vl" in
    *"$FILTER"*)
        n=$((n + 1))
        read -r _ <&3
        ( check compiler/src/main.vl 2 "$WORK/$n" -j4 >"$WORK/$n.result"; echo >&3 ) & ;;
esac
while read -r f; do
    # The case's FLAGS (tests/directives.awk, as tests/run.sh reads them).
    dd="$WORK/directives/$(echo "$f" | tr / _)"
    mkdir -p "$dd"
    case "$f" in tests/run/*) awk -v dir="$dd" -v target="$TARGET" -f tests/directives.awk "$f" ;; esac
    flags=""
    [ ! -f "$dd/flags" ] || flags=$(sed "s|@ROOT@|$ROOT|g" "$dd/flags")
    for o in 0 2; do
        n=$((n + 1))
        read -r _ <&3
        # shellcheck disable=SC2086
        ( check "$f" "$o" "$WORK/$n" $flags >"$WORK/$n.result"; echo >&3 ) &
    done
done <"$list"
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
echo "valgrind: $ok of $n compilations clean under memcheck ($TARGET)$([ $failed -eq 0 ] || echo ", $failed with memory errors")"
[ "$failed" -eq 0 ] && [ "$n" -gt 0 ]
