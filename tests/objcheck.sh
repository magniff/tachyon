#!/bin/sh
# Checks the compiler's object files (0.7) against the system assembler:
# every program of the corpus (tests/run, examples, bench, the compiler
# itself) is compiled at -O0 and -O2 both to an object (tachyonc -c) and
# to assembly, which `cc -c` assembles; both objects are linked by cc into
# executables, and the two executables must hold the same code and data:
# their disassembly (alignment padding aside: the system assemblers pick
# their own NOPs) and the contents of every other section (but GNU ld's
# build id, a hash of the whole file, symbol tables included). POSIX sh, cc
# and objdump only, so it runs the same on macOS and Linux.
#
# usage: tests/objcheck.sh [-c COMPILER] [-t TARGET] [-j JOBS] [FILTER]
#
#   -c COMPILER   the tachyonc to check (default: target/tachyonc)
#   -t TARGET     aarch64-macos, x86_64-linux or x86_64-macos (default:
#                 the host)
#   -j JOBS       programs checked at once (default: the number of CPUs)
#   FILTER        only the programs whose path contains FILTER

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/tachyonc"
TARGET=""
JOBS=""
FILTER=""
CC=${CC:-cc}

while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -t) TARGET=$2; shift 2 ;;
        -j) JOBS=$2; shift 2 ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
        *) FILTER=$1; shift ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
if [ -z "$TARGET" ]; then
    TARGET=$("$COMPILER" --version | sed 's/.*host: \([a-z0-9_-]*\).*/\1/')
fi
LINK_FLAGS=""
case "$TARGET" in
    aarch64-macos) LINK_FLAGS="-arch arm64" ;;
    x86_64-macos) LINK_FLAGS="-arch x86_64" ;;
esac
if [ -z "$JOBS" ]; then
    JOBS=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
fi
WORK="$ROOT/target/objcheck/$TARGET"
mkdir -p "$WORK"

# The code of an executable: instructions with their addresses, without
# symbol names, comments or NOPs.
code() {
    objdump -d --no-show-raw-insn "$1" | awk '
        /^ *[0-9a-f]+:/ {
            line = $0
            sub(/[<#;].*/, "", line)
            if (line ~ /nop|xchg *%ax, *%ax|data16|cs /) next
            gsub(/[ \t]+/, " ", line)
            print line
        }'
}

# The contents of every section but the code.
data() {
    objdump -s "$1" | awk '
        /^Contents of section/ { skip = ($0 ~ /text|build-id/); print; next }
        /file format/ { next }
        !skip && /^ [0-9a-f]+ / { print }'
}

check() { # <file> <level> <dir>
    f=$1 o=$2 d=$3
    mkdir -p "$d"
    "$COMPILER" --target "$TARGET" "-O$o" -c "$f" -o "$d/ours.o" >"$d/out" 2>&1 || { echo "FAIL $f -O$o: tachyonc -c: $(head -c 300 "$d/out")"; return; }
    "$COMPILER" --target "$TARGET" "-O$o" -S "$f" -o "$d/prog.s" >"$d/out" 2>&1 || { echo "FAIL $f -O$o: tachyonc -S"; return; }
    # shellcheck disable=SC2086
    "$CC" $LINK_FLAGS -c "$d/prog.s" -o "$d/cc.o" >"$d/out" 2>&1 || { echo "FAIL $f -O$o: cc -c"; return; }
    # shellcheck disable=SC2086
    "$CC" $LINK_FLAGS -o "$d/ours" "$d/ours.o" -lm >"$d/out" 2>&1 || { echo "FAIL $f -O$o: linking ours: $(head -c 300 "$d/out")"; return; }
    # shellcheck disable=SC2086
    "$CC" $LINK_FLAGS -o "$d/cc" "$d/cc.o" -lm >"$d/out" 2>&1 || { echo "FAIL $f -O$o: linking cc's"; return; }
    code "$d/ours" >"$d/ours.code"
    code "$d/cc" >"$d/cc.code"
    if ! cmp -s "$d/ours.code" "$d/cc.code"; then
        echo "FAIL $f -O$o: code differs: $(diff "$d/ours.code" "$d/cc.code" | sed -n 2,3p | tr '\n' ' ')"
        return
    fi
    data "$d/ours" >"$d/ours.data"
    data "$d/cc" >"$d/cc.data"
    if ! cmp -s "$d/ours.data" "$d/cc.data"; then
        echo "FAIL $f -O$o: data differs: $(diff "$d/ours.data" "$d/cc.data" | sed -n 2,3p | tr '\n' ' ')"
        return
    fi
    echo "ok $f -O$o"
}

cd "$ROOT" || exit 1
list="$WORK/list"
: >"$list"
for f in tests/run/*.tach tests/run/*/main.tach examples/*.tach bench/*.tach compiler/src/main.tach; do
    [ -f "$f" ] || continue
    case "$f" in *"$FILTER"*) ;; *) continue ;; esac
    # Programs that fail to compile (or compile once --fix-imports or, 0.10,
    # --fix-unsafe has rewritten them, 0.8), or need C sources or a header.
    grep -q '// ERROR\|// CSOURCE\|// CHEADER\|// FIXIMPORTS\|// FIXUNSAFE' "$f" && continue
    echo "$f" >>"$list"
done
n=0
running=0
while read -r f; do
    for o in 0 2; do
        n=$((n + 1))
        check "$f" "$o" "$WORK/$n" >"$WORK/$n.result" &
        running=$((running + 1))
        if [ "$running" -ge "$JOBS" ]; then
            wait
            running=0
        fi
    done
done <"$list"
wait
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
echo "objcheck: $ok of $n compilations for $TARGET give the same program as cc -c, $failed differ"
[ "$failed" -eq 0 ]
