#!/bin/sh
# (0.18.1) Code generation on threads gives the same output whatever
# their number (docs/optimizer.md, "0.18.1: threads"): every program of
# the corpus (tests/run, examples, bench, the compiler itself) is
# compiled at -O0, -O1 and -O2 with -j1 and with -jN, to an object, and the
# two must be the same bytes (and print the same; the compiler's own to
# assembly too). The compiler's own
# self-compile is also checked at -O0, at -j3, and with
# VOLE_FRESH_CONTEXTS=1 (each task in a context of its own: a task
# that used what an earlier task left in its thread's context would make
# the output depend on the schedule). -O0 compiles from the syntax tree on
# the main thread and assembles on another.
#
# (0.25) A schedule that shows a difference only now and then is caught by
# repeats: tests/run/std_gpu_wgsl_reflect.vl for aarch64-linux at -O2, the
# program whose SLP tables, left by an earlier function in a thread's
# context, once gave 1 build in 40 other code, compiled REPEATS times
# (default 96) at -jN, 32 at once, each the same assembly as -j1's.
#
# usage: tests/threads.sh [-c COMPILER] [-t TARGET] [-n THREADS] [-j JOBS] [FILTER]
#
#   -c COMPILER   the volec to check (default: target/volec)
#   -t TARGET     any target the compiler has (default: the host)
#   -n THREADS    the threads compared with one (default 8)
#   -j JOBS       programs checked at once (default: the number of CPUs,
#                 or the slots of $VOLE_JOBSERVER, see tests/run.sh)
#   -r REPEATS    the repeated builds (0: none)
#   FILTER        only the programs whose path contains FILTER

set -u
LC_ALL=C
export LC_ALL
# (0.18.1) Without the code cache: -jN's tasks would take -j1's outputs.
VOLE_CACHE=off
export VOLE_CACHE

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/volec"
TARGET=""
THREADS=8
JOBS=""
FILTER=""
REPEATS=96

while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -t) TARGET=$2; shift 2 ;;
        -n) THREADS=$2; shift 2 ;;
        -j) JOBS=$2; shift 2 ;;
        -r) REPEATS=$2; shift 2 ;;
        -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
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
    [ "$1" = compiler/src/main.vl ] && kinds="s o"
    for kind in $kinds; do
        opt=-S
        [ $kind = o ] && opt=-c
        # shellcheck disable=SC2086
        env $3 "$COMPILER" --target "$TARGET" "-O$2" "-j$4" $flags $opt "$1" -o "$5.$kind" \
            >"$5.$kind.raw" 2>&1
        rc=$?
        # (the success line names the output file, which differs per build)
        sed "s|$5\.$kind|OUT.$kind|g" "$5.$kind.raw" >"$5.$kind.out"
        echo "exit $rc" >>"$5.$kind.out"
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

# Build $3 of program $1 for target $2 at -O2 -jN, against -j1's ($4).
repeat_check() { # <file> <target> <n> <reference>
    out="$WORK/repeat.$3.s"
    "$COMPILER" --target "$2" -O2 "-j$THREADS" -S "$1" -o "$out" >/dev/null 2>&1
    if cmp -s "$4" "$out"; then
        rm -f "$out"
        echo "ok $1 $2 -O2 -j$THREADS, repeat $3"
    else
        echo "FAIL $1 $2 -O2 -j$THREADS, repeat $3: the assembly differs from -j1's (kept: $out)"
    fi
}

cd "$ROOT" || exit 1
list="$WORK/list"
: >"$list"
for f in tests/run/*.vl tests/run/*/main.vl examples/*/main.vl examples/*/*/main.vl bench/*.vl compiler/src/main.vl; do
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
run() { # <file> <level> <env> <threads>
    n=$((n + 1))
    read -r _ <&3
    ( check "$1" "$2" "$3" "$4" "$n" >"$WORK/$n.result"; echo >&3 ) &
}
while read -r f; do
    for o in 0 1 2; do
        run "$f" "$o" "" "$THREADS"
    done
done <"$list"
if [ -z "$FILTER" ] || echo compiler/src/main.vl | grep -q "$FILTER"; then
    for o in 1 2; do
        run compiler/src/main.vl "$o" "" 3
        run compiler/src/main.vl "$o" VOLE_FRESH_CONTEXTS=1 "$THREADS"
    done
fi
rp=tests/run/std_gpu_wgsl_reflect.vl
if [ "$REPEATS" -gt 0 ] && [ -f "$rp" ] && { [ -z "$FILTER" ] || echo "$rp" | grep -q "$FILTER"; }; then
    "$COMPILER" --target aarch64-linux -O2 -j1 -S "$rp" -o "$WORK/repeat.ref.s" >/dev/null 2>&1
    wait
    # (in bursts of 32 at once, past the slots: a loaded machine
    # interleaves the threads' tasks most)
    r=0
    while [ "$r" -lt "$REPEATS" ]; do
        r=$((r + 1))
        n=$((n + 1))
        repeat_check "$rp" aarch64-linux "$r" "$WORK/repeat.ref.s" >"$WORK/$n.result" &
        [ $((r % 32)) -eq 0 ] && wait
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
