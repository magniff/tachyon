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
# (0.11) Each program is also compiled with -g at both levels: then the two
# programs must have the same line table too, as decoded (the assemblers
# encode it each their own way): `objdump --dwarf=decodedline` of the
# executables on Linux, `dwarfdump --debug-line` of what dsymutil gathers
# on macOS (where the debug information stays in the objects), with each
# row's file named by its path; on macOS their .debug_info must be the
# same as well (on Linux it is part of the executables' data, compared
# above).
#
# usage: tests/objcheck.sh [-c COMPILER] [-t TARGET] [-j JOBS] [FILTER]
#
#   -c COMPILER   the tachyonc to check (default: target/tachyonc)
#   -t TARGET     aarch64-macos, aarch64-linux, x86_64-linux or
#                 x86_64-macos (default: the host)
#   -j JOBS       programs checked at once (default: the number of CPUs,
#                 or the slots of $TACHYON_JOBSERVER, see tests/run.sh)
#   FILTER        only the programs whose path contains FILTER

# (0.16) std's ambient allocator (`Vec::new()`) for the 0.15 corpus, until
# `tachyonc fix --only alloc016` migrates it: compiler/src/front/ambient.tach.
TACHYON_AMBIENT_GPA=${TACHYON_AMBIENT_GPA:-1}
export TACHYON_AMBIENT_GPA
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
        -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
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
WORK="$ROOT/target/objcheck/$TARGET"
mkdir -p "$WORK"

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

# The contents of every section but the code (and the line table, whose
# encoding is the assembler's).
data() {
    objdump -s "$1" | awk '
        /^Contents of section/ { skip = ($0 ~ /text|build-id|debug_line/); print; next }
        /file format/ { next }
        !skip && /^ [0-9a-f]+ / { print }'
}

# The rows of an executable's line table, decoded: address, line, column
# (macOS), file (by its path), flags.
lines() {
    case "$TARGET" in
        *-macos)
            dwarfdump --debug-line "$1.dSYM" | awk '
                /^debug_line\[/ { split("", dir); split("", name); split("", fdir) }
                /^include_directories\[/ {
                    i = $0; sub(/^include_directories\[ */, "", i); sub(/\].*/, "", i)
                    v = $0; sub(/^[^"]*"/, "", v); sub(/"[^"]*$/, "", v)
                    dir[i + 0] = v
                }
                /^file_names\[/ { f = $0; sub(/^file_names\[ */, "", f); sub(/\].*/, "", f); f += 0 }
                /^ +name: / { v = $0; sub(/^[^"]*"/, "", v); sub(/"[^"]*$/, "", v); name[f] = v }
                /^ +dir_index: / { fdir[f] = $2 + 0 }
                /^0x[0-9a-f]+ / {
                    path = (fdir[$4 + 0] > 0 ? dir[fdir[$4 + 0]] "/" : "") name[$4 + 0]
                    flags = ""
                    for (k = 8; k <= NF; k++) flags = flags " " $k
                    print $1, $2, $3, path, flags
                }' ;;
        *)
            objdump --dwarf=decodedline "$1" | awk 'NF >= 3 && $3 ~ /^0x/ { print }' ;;
    esac
}

# dsymutil, when the debug information of an executable is to be read
# (macOS); its notes on the relocations of cc's objects are not errors.
dsym() {
    case "$TARGET" in
        *-macos) dsymutil "$1" >/dev/null 2>&1 ;;
    esac
}

check() { # <file> <level> <dir> [-g]
    f=$1 o=$2 d=$3 g=${4:-}
    mkdir -p "$d"
    # shellcheck disable=SC2086
    "$COMPILER" --target "$TARGET" "-O$o" $g -c "$f" -o "$d/ours.o" >"$d/out" 2>&1 || { echo "FAIL $f -O$o $g: tachyonc -c: $(head -c 300 "$d/out")"; return; }
    # shellcheck disable=SC2086
    "$COMPILER" --target "$TARGET" "-O$o" $g -S "$f" -o "$d/prog.s" >"$d/out" 2>&1 || { echo "FAIL $f -O$o $g: tachyonc -S"; return; }
    # shellcheck disable=SC2086
    cc_run $LINK_FLAGS -c "$d/prog.s" -o "$d/cc.o" >"$d/out" 2>&1 || { echo "FAIL $f -O$o: cc -c"; return; }
    # shellcheck disable=SC2086
    cc_run $LINK_FLAGS -o "$d/ours" "$d/ours.o" -lm >"$d/out" 2>&1 || { echo "FAIL $f -O$o: linking ours: $(head -c 300 "$d/out")"; return; }
    # shellcheck disable=SC2086
    cc_run $LINK_FLAGS -o "$d/cc" "$d/cc.o" -lm >"$d/out" 2>&1 || { echo "FAIL $f -O$o: linking cc's"; return; }
    code "$d/ours" >"$d/ours.code"
    code "$d/cc" >"$d/cc.code"
    if ! cmp -s "$d/ours.code" "$d/cc.code"; then
        echo "FAIL $f -O$o $g: code differs: $(diff "$d/ours.code" "$d/cc.code" | sed -n 2,3p | tr '\n' ' ')"
        return
    fi
    data "$d/ours" >"$d/ours.data"
    data "$d/cc" >"$d/cc.data"
    if ! cmp -s "$d/ours.data" "$d/cc.data"; then
        echo "FAIL $f -O$o $g: data differs: $(diff "$d/ours.data" "$d/cc.data" | sed -n 2,3p | tr '\n' ' ')"
        return
    fi
    if [ -n "$g" ]; then
        dsym "$d/ours"
        dsym "$d/cc"
        lines "$d/ours" >"$d/ours.lines"
        lines "$d/cc" >"$d/cc.lines"
        if [ ! -s "$d/ours.lines" ] || ! cmp -s "$d/ours.lines" "$d/cc.lines"; then
            echo "FAIL $f -O$o $g: line tables differ: $(diff "$d/ours.lines" "$d/cc.lines" | sed -n 2,3p | tr '\n' ' ')"
            return
        fi
        case "$TARGET" in
            *-macos)
                dwarfdump --debug-info "$d/ours.dSYM" | grep -v 'file format' >"$d/ours.info"
                dwarfdump --debug-info "$d/cc.dSYM" | grep -v 'file format' >"$d/cc.info"
                if ! cmp -s "$d/ours.info" "$d/cc.info"; then
                    echo "FAIL $f -O$o $g: debug information differs: $(diff "$d/ours.info" "$d/cc.info" | sed -n 2,3p | tr '\n' ' ')"
                    return
                fi ;;
        esac
    fi
    echo "ok $f -O$o $g"
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
# The slots: JOBS of them, or (0.11) the ones $TACHYON_JOBSERVER shares
# between the runners of bootstrap/gate.sh (see tests/run.sh).
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
while read -r f; do
    for og in 0 2 0g 2g; do
        n=$((n + 1))
        o=${og%g}
        g=""
        [ "$o" = "$og" ] || g=-g
        read -r _ <&3
        ( check "$f" "$o" "$WORK/$n" $g >"$WORK/$n.result"; echo >&3 ) &
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
echo "objcheck: $ok of $n compilations for $TARGET give the same program as cc -c, $failed differ"
[ "$failed" -eq 0 ]
