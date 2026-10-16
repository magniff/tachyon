#!/bin/sh
# (0.18.1) Code generation on threads gives the same output whatever
# their number (docs/optimizer.md, "0.18.1: threads"): every program of
# the corpus (tests/run, examples, bench, the compiler itself) is
# compiled at -O1 and -O2 with -j1 and with -jN, to an object, and the
# two must be the same bytes (and print the same; the compiler's own to
# assembly too). The compiler's own
# self-compile is also checked at -O0, at -j3, and with
# TACHYON_FRESH_CONTEXTS=1 (each task in a context of its own: a task
# that used what an earlier task left in its thread's context would make
# the output depend on the schedule). -O0 compiles from the syntax tree on
# one thread; it is here so that the flag stays harmless there.
#
# usage: tests/threads.sh [-c COMPILER] [-t TARGET] [-n THREADS] [-j JOBS] [FILTER]
#
#   -c COMPILER   the tachyonc to check (default: target/tachyonc)
#   -t TARGET     any target the compiler has (default: the host)
#   -n THREADS    the threads compared with one (default 8)
#   -j JOBS       programs checked at once (default: the number of CPUs,
#                 or the slots of $TACHYON_JOBSERVER, see tests/run.sh)
#   FILTER        only the programs whose path contains FILTER

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/tachyonc"
TARGET=""
THREADS=8
JOBS=""
FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -t) TARGET=$2; shift 2 ;;
        -n) THREADS=$2; shift 2 ;;
        -j) JOBS=$2; shift 2 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
        *) FILTER=$1; shift ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
if [ -z "$TARGET" ]; then
    TARGET=$("$COMPILER" --version | sed 's/.*host: \([a-z0-9_-]*\).*/\1/')
fi
WORK="$ROOT/target/threads/$TARGET"
rm -rf "$WORK"
mkdir -p "$WORK"

# A program's test directives (tests/directives.awk) into directory $2.
case_directives() { # <program> <dir>
    mkdir -p "$2"
    case "$1" in
        examples/*) cd_file=$(grep -l -x "// SOURCE: $1" tests/examples/*.test 2>/dev/null | head -1) ;;
        *) cd_file=$1 ;;
    esac
    [ -n "$cd_file" ] || return 0
    awk -v dir="$2" -v target="$TARGET" -f "$ROOT/tests/directives.awk" "$cd_file"
}

# Compiles program $1 at level $2 with environment setting $3 and threads
# $4 into $5.s and $5.o (stdout and stderr in $5.out, exit status first).
build() { # <file> <level> <env> <threads> <out>
    flags=""
    dd="$WORK/directives/$(echo "$1" | tr / _)"
    [ -f "$dd/flags" ] && flags=$(sed "s|@ROOT@|$ROOT|g" "$dd/flags")
    kinds=o
    [ "$1" = compiler/src/main.tach ] && kinds="s o"
    for kind in $kinds; do
        opt=-S
        [ $kind = o ] && opt=-c
        # shellcheck disable=SC2086
        env $3 "$COMPILER" --target "$TARGET" "-O$2" "-j$4" $flags $opt "$1" -o "$5.$kind" \
            >"$5.$kind.out" 2>&1
        echo "exit $?" >>"$5.$kind.out"
    done
}

check() { # <file> <level> <env> <threads> <n>
    a="$WORK/$5.a"
    b="$WORK/$5.b"
    build "$1" "$2" "" 1 "$a"
    build "$1" "$2" "$3" "$4" "$b"
    what="-O$2 -j$4${3:+ $3}"
    for kind in o s; do
        [ -f "$a.$kind.out" ] || continue
        if ! cmp -s "$a.$kind.out" "$b.$kind.out"; then
            echo "FAIL $1 $what: the compiler's output or exit differs: $(diff "$a.$kind.out" "$b.$kind.out" | sed -n 2,3p | tr '\n' ' ')"
            return
        fi
        if [ -f "$a.$kind" ] && ! cmp -s "$a.$kind" "$b.$kind"; then
            echo "FAIL $1 $what: the $( [ $kind = s ] && echo assembly || echo object) differs from -j1's"
            return
        fi
    done
    rm -f "$a".* "$b".*
    echo "ok $1 $what"
}

cd "$ROOT" || exit 1
list="$WORK/list"
: >"$list"
for f in tests/run/*.tach tests/run/*/main.tach examples/*/main.tach examples/*/*/main.tach bench/*.tach compiler/src/main.tach; do
    [ -f "$f" ] || continue
    case "$f" in examples/tools/*) continue ;; esac
    case "$f" in *"$FILTER"*) ;; *) continue ;; esac
    grep -q '// CSOURCE\|// CHEADER\|// FIXIMPORTS\|// FIXUNSAFE' "$f" && continue
    case "$f" in
        examples/*) grep -l -x "// SOURCE: $f" tests/examples/*.test 2>/dev/null \
            | xargs grep -q '^// CSOURCE' 2>/dev/null && continue ;;
    esac
    case_directives "$f" "$WORK/directives/$(echo "$f" | tr / _)"
    echo "$f" >>"$list"
done
# The slots (as tests/objcheck.sh).
if [ -z "$JOBS" ] && [ -n "${TACHYON_JOBSERVER:-}" ] && [ -p "$TACHYON_JOBSERVER" ]; then
    exec 3<>"$TACHYON_JOBSERVER"
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
run() { # <file> <level> <env> <threads>
    n=$((n + 1))
    read -r _ <&3
    ( check "$1" "$2" "$3" "$4" "$n" >"$WORK/$n.result"; echo >&3 ) &
}
while read -r f; do
    for o in 1 2; do
        run "$f" "$o" "" "$THREADS"
    done
done <"$list"
if [ -z "$FILTER" ] || echo compiler/src/main.tach | grep -q "$FILTER"; then
    run compiler/src/main.tach 0 "" "$THREADS"
    for o in 1 2; do
        run compiler/src/main.tach "$o" "" 3
        run compiler/src/main.tach "$o" TACHYON_FRESH_CONTEXTS=1 "$THREADS"
    done
fi
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
echo "threads: $ok of $n compilations the same at -j1 and -j$THREADS ($TARGET)$([ $failed -eq 0 ] || echo ", $failed differ")"
[ $failed -eq 0 ]
