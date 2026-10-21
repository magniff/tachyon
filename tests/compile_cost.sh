#!/bin/sh
# The gate's compile-cost row (0.21.1, after 0.20's std made a hello
# world 5.5 times dearer to build unnoticed): the instructions retired by
# three compilations, with this compiler and the previous release's,
# each the fewest of a few runs, and their ratios:
#
#   hello   a hello world built (an object: no linker), at most 1.5x
#   std     tests/cost/std_heavy.tach built (most of std read), at most 1.5x
#   check   `tachyonc check` of compiler/src (a copy without compiler/std,
#           so that both read their own std; no tools' cache), at most 1.15x
#
# Instructions, not time: they hardly move with the machine's load. They
# are read from /usr/bin/time -l (macOS); a host without it skips (77).
#
# usage: tests/compile_cost.sh -c COMPILER -p PREVIOUS [-r RUNS]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
C=""
P=""
RUNS=3
while [ $# -gt 0 ]; do
    case "$1" in
        -c) C=$2; shift ;;
        -p) P=$2; shift ;;
        -r) RUNS=$2; shift ;;
        *) echo "usage: tests/compile_cost.sh -c COMPILER -p PREVIOUS [-r RUNS]" >&2; exit 2 ;;
    esac
    shift
done
[ -x "$C" ] || { echo "compile-cost: no compiler (-c)"; exit 2; }
case "$C" in /*) ;; *) C="$(pwd)/$C" ;; esac
case "$P" in /*|'') ;; *) P="$(pwd)/$P" ;; esac
if [ -z "$P" ] || [ ! -x "$P" ]; then
    echo "compile-cost: no previous release built here (bootstrap/bootstrap.sh builds it)"
    exit 77
fi
if ! /usr/bin/time -l true 2>&1 | grep -q 'instructions retired'; then
    echo "compile-cost: /usr/bin/time -l counts no instructions on this host"
    exit 77
fi
W=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-cost.XXXXXX")
trap 'rm -rf "$W"' EXIT
printf 'fn main() {\n    println("hello");\n}\n' >"$W/hello.tach"
cp "$ROOT/tests/cost/std_heavy.tach" "$W/std_heavy.tach"
mkdir -p "$W/src"
cp -R "$ROOT/compiler/src/." "$W/src/"
TACHYON_CACHE=off
TACHYON_CODE_CACHE=off
export TACHYON_CACHE TACHYON_CODE_CACHE

# The fewest instructions of $RUNS runs of the command (in $W), or
# nothing when it fails.
count() {
    best=""
    i=0
    while [ $i -lt "$RUNS" ]; do
        (cd "$W" && /usr/bin/time -l "$@" >/dev/null 2>"$W/time.out") || return 1
        n=$(awk '/instructions retired/ { print $1 }' "$W/time.out")
        [ -n "$n" ] || return 1
        if [ -z "$best" ] || [ "$n" -lt "$best" ]; then best=$n; fi
        i=$((i + 1))
    done
    echo "$best"
}

FAILED=0
# <name> <limit> <command args...> (the compiler's place: COMPILER)
measure() {
    name=$1
    limit=$2
    shift 2
    new=$(count "$C" "$@") || { echo "compile-cost: $name fails with $C"; FAILED=1; return; }
    old=$(count "$P" "$@") || { echo "compile-cost: $name: skipped, the previous release cannot do it ($P $*)"; return; }
    awk -v n="$name" -v a="$old" -v b="$new" -v l="$limit" 'BEGIN {
        r = b / a
        bad = (r > l)
        printf "  %-6s %8.1f M instructions, was %8.1f M: %.2fx (at most %.2fx)%s\n", n, b / 1e6, a / 1e6, r, l, (bad ? "  TOO DEAR" : "")
        exit bad
    }' || FAILED=1
}
echo "compile cost against $P:"
measure hello 1.5 hello.tach -c -o hello.o
measure std 1.5 std_heavy.tach -c -o std_heavy.o
measure check 1.15 check src/main.tach
if [ $FAILED -ne 0 ]; then
    echo "compile-cost: a compilation is dearer than the previous release allows (see above; --time-passes splits it by phase, and std's sections: tests/std/core_sections.sh)"
    exit 1
fi
echo "compile-cost: hello, std and check within the bounds"
