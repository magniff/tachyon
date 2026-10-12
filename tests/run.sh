#!/bin/sh
# The test suite of this release, run with a tachyon compiler (no cargo
# needed): every tests/run/*.tach and tests/examples/*.test case is
# compiled, assembled and linked with the C compiler, run, and checked.
# POSIX sh and awk only, so it runs the same on macOS and Linux.
#
# usage: tests/run.sh [-c COMPILER] [-t TARGET] [-O LEVEL] [-j JOBS] [FILTER]
#
#   -c COMPILER   the tachyonc binary to test (default: target/tachyonc,
#                 as left by bootstrap/bootstrap.sh)
#   -t TARGET     aarch64-macos, x86_64-linux or x86_64-macos (default: the
#                 host; x86_64-macos runs under Rosetta on Apple silicon)
#   -O LEVEL      the optimization level (0, 1 or 2; default: the
#                 compiler's default)
#   -j JOBS       cases run at once (default: the number of CPUs); the
#                 report is the same for every JOBS
#   FILTER        run only the cases whose name contains FILTER
#
# Environment: CC is the assembler/linker (default cc).
#
# Directives, in `//` comments of the case file:
#   // ARGS: a b c       command-line arguments (whitespace separated)
#   // STDIN: text       stdin, one directive per line, joined with '\n'
#   // EXPECT: text      expected stdout, one directive per line
#   // EXIT: 3           expected exit code (default 0)
#   // STDERR: text      stderr contains text, one directive per line
#   // ERROR: text       compilation must fail (exit code 1) with an error
#                        containing this text; one directive per message
#   // XFAIL: reason     a known bug: the case is expected to fail, and
#                        reported as a failure (XPASS) once it passes
#   // XFAIL(T): reason  the same, only for target T
#   // SOURCE: path      (.test files) the program, relative to the root
#   // CHEADER: name.h    the program's C header (--emit-header), made for
#                        its C sources to include
#   // CSOURCE: path     a C file to compile and link with the program,
#                        relative to the root (one directive per file)
#   // BUILD: reason     (.test files) only compile and link it
#   // CHECK: text       the optimized IR (--emit-ir) has a line containing
#                        text, after the previous CHECK's line
#   // CHECK-NOT: text   no line containing text between the neighbouring
#                        CHECKs' lines (or the start and end)
#   // CHECK-OPT: n      the level for the CHECKs (default 2)
#   // ASM(T): text      the assembly for target T (at the CHECK-OPT level)
#                        has a line containing text, after the previous
#                        ASM(T)'s line; checked only when testing T
#   // ASM-NOT(T): text  no line containing text between the neighbouring
#                        ASM(T)s' lines
# Stdout is compared after removing trailing whitespace. Each program may
# run for 20 seconds.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/tachyonc"
CC=${CC:-cc}
TARGET=""
OPT=""
TIMEOUT=20
JOBS=""

usage() {
    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || usage; COMPILER=$2; shift 2 ;;
        -t) [ $# -ge 2 ] || usage; TARGET=$2; shift 2 ;;
        -O) [ $# -ge 2 ] || usage; OPT="-O$2"; shift 2 ;;
        -j) [ $# -ge 2 ] || usage; JOBS=$2; shift 2 ;;
        -h|--help) usage ;;
        -*) usage ;;
        *) break ;;
    esac
done
FILTER=${1:-}

case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "run.sh: no compiler at $COMPILER (use -c)" >&2; exit 2; }
command -v "$CC" >/dev/null 2>&1 || { echo "run.sh: '$CC' not found (set CC)" >&2; exit 2; }

if [ -z "$TARGET" ]; then
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) TARGET=aarch64-macos ;;
        Darwin-x86_64) TARGET=x86_64-macos ;;
        Linux-x86_64) TARGET=x86_64-linux ;;
        *) echo "run.sh: no tachyon target for this host ($(uname -s) $(uname -m)); use -t" >&2; exit 2 ;;
    esac
fi
# How the C compiler assembles and links for the target.
case "$TARGET" in
    aarch64-macos) LINK_FLAGS="-arch arm64" ;;
    x86_64-macos) LINK_FLAGS="-arch x86_64" ;;
    x86_64-linux) LINK_FLAGS="" ;;
    *) echo "run.sh: unknown target '$TARGET'" >&2; exit 2 ;;
esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
FAILURES="$WORK/failures"
TALLY="$WORK/tally"
: >"$FAILURES"
: >"$TALLY"

# Writes the directives of case file $1 into directory $2: one file per
# directive (args, stdin, expect, exit, errors, xfail, source, build).
read_directives() {
    awk -v dir="$2" -v target="$TARGET" '
        {
            line = $0
            sub(/\r$/, "", line)
            sub(/^[ \t]+/, "", line)
            if (substr(line, 1, 2) != "//") next
            c = substr(line, 3)
            if (substr(c, 1, 1) == " ") c = substr(c, 2)
            i = index(c, ":")
            if (i == 0) next
            key = substr(c, 1, i - 1)
            value = substr(c, i + 1)
            if (substr(value, 1, 1) == " ") value = substr(value, 2)
            if (key == "ARGS") args = value
            else if (key == "STDIN") stdin = stdin (nstdin++ ? "\n" : "") value
            else if (key == "EXPECT") expect = expect (nexpect++ ? "\n" : "") value
            else if (key == "EXIT") exitcode = value + 0
            else if (key == "STDERR") stderrs = stderrs value "\n"
            else if (key == "ERROR") errors = errors value "\n"
            else if (key == "XFAIL" || key == "XFAIL(" target ")") xfail = value
            else if (key == "SOURCE") source = value
            else if (key == "CSOURCE") csources = csources " " value
            else if (key == "CHEADER") cheader = value
            else if (key == "BUILD") build = 1
            else if (key == "CHECK") checks = checks "+" value "\n"
            else if (key == "CHECK-NOT") checks = checks "-" value "\n"
            else if (key == "CHECK-OPT") checkopt = value
            else if (key == "ASM(" target ")") asms = asms "+" value "\n"
            else if (key == "ASM-NOT(" target ")") asms = asms "-" value "\n"
        }
        END {
            printf "%s", args > (dir "/args")
            printf "%s", stdin > (dir "/stdin")
            printf "%s", expect > (dir "/expect")
            printf "%d", exitcode > (dir "/exit")
            printf "%s", stderrs > (dir "/stderrs")
            printf "%s", errors > (dir "/errors")
            printf "%s", xfail > (dir "/xfail")
            printf "%s", source > (dir "/source")
            printf "%s", csources > (dir "/csources")
            printf "%s", cheader > (dir "/cheader")
            printf "%d", build > (dir "/build")
            printf "%s", checks > (dir "/checks")
            printf "%s", asms > (dir "/asms")
            printf "%s", (checkopt == "" ? "2" : checkopt) > (dir "/checkopt")
        }
    ' "$1"
}

# The file's content without trailing whitespace.
trimmed() {
    awk '{ text = text $0 "\n" } END { sub(/[ \t\r\n]+$/, "", text); printf "%s", text }' "$1"
}

# Runs $dir/prog with a timeout; sets RC.
run_program() {
    dir=$1
    (
        cd "$dir" || exit 1
        # shellcheck disable=SC2046
        exec ./prog $(cat args) <stdin >stdout 2>stderr
    ) &
    pid=$!
    (sleep "$TIMEOUT" && kill -9 "$pid" 2>/dev/null) >/dev/null 2>&1 &
    watchdog=$!
    wait "$pid"
    RC=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
}

# Runs one case; prints nothing, returns 0 on success, and leaves the
# reason for a failure in $dir/why.
check_case() {
    file=$1
    dir=$2
    source=$(cat "$dir/source")
    if [ -n "$source" ]; then
        source="$ROOT/$source"
    else
        source=$file
    fi
    if [ -s "$dir/errors" ]; then
        "$COMPILER" --target "$TARGET" $OPT "$source" -o "$dir/prog.s" >"$dir/compile.out" 2>&1
        rc=$?
        if [ $rc -ne 1 ]; then
            { echo "expected a compile error (exit code 1), got exit code $rc:"; cat "$dir/compile.out"; } >"$dir/why"
            return 1
        fi
        while IFS= read -r message; do
            if ! grep -qF -- "$message" "$dir/compile.out"; then
                { echo "expected an error containing '$message', got:"; cat "$dir/compile.out"; } >"$dir/why"
                return 1
            fi
        done <"$dir/errors"
        return 0
    fi
    if [ -s "$dir/asms" ] && ! check_asm "$source" "$dir"; then
        return 1
    fi
    if [ -s "$dir/checks" ] && ! check_ir "$source" "$dir"; then
        return 1
    fi
    if ! "$COMPILER" --target "$TARGET" $OPT "$source" -o "$dir/prog.s" >"$dir/compile.out" 2>&1; then
        { echo "compile failed:"; cat "$dir/compile.out"; } >"$dir/why"
        return 1
    fi
    csources=""
    for c in $(cat "$dir/csources"); do
        csources="$csources $ROOT/$c"
    done
    # The program's C header, for its C sources.
    if [ -s "$dir/cheader" ]; then
        if ! "$COMPILER" --target "$TARGET" --emit-header "$source" -o "$dir/$(cat "$dir/cheader")" >"$dir/header.out" 2>&1; then
            { echo "--emit-header failed:"; cat "$dir/header.out"; } >"$dir/why"
            return 1
        fi
        csources="-I $dir $csources"
    fi
    # shellcheck disable=SC2086
    if ! "$CC" $LINK_FLAGS -o "$dir/prog" "$dir/prog.s" $csources -lm >"$dir/link.out" 2>&1; then
        { echo "$CC failed:"; cat "$dir/link.out"; } >"$dir/why"
        return 1
    fi
    [ "$(cat "$dir/build")" = 1 ] && return 0
    run_program "$dir"
    expected_exit=$(cat "$dir/exit")
    trimmed "$dir/stdout" >"$dir/actual"
    trimmed "$dir/expect" >"$dir/wanted"
    if ! cmp -s "$dir/actual" "$dir/wanted"; then
        {
            echo "stdout mismatch"
            echo "--- expected"; cat "$dir/wanted"; echo
            echo "--- actual"; cat "$dir/actual"; echo
        } >"$dir/why"
        return 1
    fi
    if [ "$RC" -ne "$expected_exit" ]; then
        { echo "exit code: expected $expected_exit, got $RC"; cat "$dir/stderr"; } >"$dir/why"
        return 1
    fi
    while IFS= read -r message; do
        if ! grep -qF -- "$message" "$dir/stderr"; then
            { echo "expected stderr containing '$message', got:"; cat "$dir/stderr"; } >"$dir/why"
            return 1
        fi
    done <"$dir/stderrs"
    return 0
}

# Matches the CHECK directives against the optimized IR of $1.
check_ir() {
    if ! "$COMPILER" --target "$TARGET" "-O$(cat "$2/checkopt")" --verify-ir --emit-ir "$1" -o "$2/ir.txt" >"$2/compile.out" 2>&1; then
        { echo "--emit-ir failed:"; cat "$2/compile.out"; } >"$2/why"
        return 1
    fi
    match_checks "$2/ir.txt" "$2/checks" "$2/check.out" && return 0
    { cat "$2/check.out"; echo "--- IR:"; cat "$2/ir.txt"; } >"$2/why"
    return 1
}

# Matches the ASM directives against the assembly of $1 for the target.
check_asm() {
    if ! "$COMPILER" --target "$TARGET" "-O$(cat "$2/checkopt")" "$1" -o "$2/check.s" >"$2/compile.out" 2>&1; then
        { echo "compile failed:"; cat "$2/compile.out"; } >"$2/why"
        return 1
    fi
    match_checks "$2/check.s" "$2/asms" "$2/check.out" && return 0
    { cat "$2/check.out"; echo "--- assembly:"; cat "$2/check.s"; } >"$2/why"
    return 1
}

# Matches the checks in file $2 (+text: a line containing text, after the
# previous one; -text: none until the next) against the lines of $1;
# writes what failed to $3.
match_checks() {
    awk -v checks="$2" '
        { line[NR] = $0 }
        END {
            n = 0
            while ((getline c < checks) > 0) { kind[n] = substr(c, 1, 1); text[n] = substr(c, 2); n++ }
            pos = 0
            nots = 0
            for (i = 0; i < n; i++) {
                if (kind[i] == "-") { pending[nots++] = text[i]; continue }
                found = 0
                for (j = pos + 1; j <= NR; j++) if (index(line[j], text[i])) { found = j; break }
                if (!found) { print "CHECK not found after line " pos ": " text[i]; exit 1 }
                for (k = 0; k < nots; k++)
                    for (j = pos + 1; j < found; j++)
                        if (index(line[j], pending[k])) { print "CHECK-NOT found at line " j ": " pending[k]; exit 1 }
                nots = 0
                pos = found
            }
            for (k = 0; k < nots; k++)
                for (j = pos + 1; j <= NR; j++)
                    if (index(line[j], pending[k])) { print "CHECK-NOT found at line " j ": " pending[k]; exit 1 }
        }
    ' "$1" >"$3" 2>&1
}

# The number of CPUs, for -j.
cpu_count() {
    n=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 4)
    case "$n" in
        ''|*[!0-9]*) echo 4 ;;
        *) echo "$n" ;;
    esac
}
[ -n "$JOBS" ] || JOBS=$(cpu_count)

# Runs case $1 in directory $2: its outcome in $2/status.
run_case() {
    file=$1
    dir=$2
    if check_case "$file" "$dir"; then
        if [ -s "$dir/xfail" ]; then echo xpass; else echo pass; fi
    elif [ -s "$dir/xfail" ]; then
        echo xfail
    else
        echo fail
    fi >"$dir/status"
}

# The cases, in order; up to JOBS at once (a FIFO holds the free slots).
CASES="$WORK/cases"
: >"$CASES"
for file in "$ROOT"/tests/run/*.tach "$ROOT"/tests/examples/*.test; do
    [ -f "$file" ] || continue
    base=$(basename "$file")
    name=${base%.*}
    case "$file" in
        *.test) name="example_$name" ;;
    esac
    case "$name" in
        *"$FILTER"*) ;;
        *) continue ;;
    esac
    echo "$name $file" >>"$CASES"
done
mkfifo "$WORK/slots"
exec 3<>"$WORK/slots"
i=0
while [ "$i" -lt "$JOBS" ]; do
    echo >&3
    i=$((i + 1))
done
while read -r name file; do
    dir="$WORK/$name"
    mkdir -p "$dir"
    read_directives "$file" "$dir"
    read -r _ <&3
    ( run_case "$file" "$dir"; echo >&3 ) &
done <"$CASES"
wait
exec 3>&-

count=0
while read -r name file; do
    dir="$WORK/$name"
    category=${name%%_*}
    [ -s "$dir/errors" ] && category=error
    status=$(cat "$dir/status" 2>/dev/null || echo fail)
    if [ "$status" = xpass ]; then
        echo "$category fail" >>"$TALLY"
        echo "XPASS $name: passes but is marked XFAIL ($(cat "$dir/xfail")); remove the directive" >>"$FAILURES"
    elif [ "$status" = fail ]; then
        echo "$category fail" >>"$TALLY"
        { echo "FAIL $name:"; sed 's/^/    /' "$dir/why"; echo; } >>"$FAILURES"
    else
        echo "$category $status" >>"$TALLY"
    fi
    count=$((count + 1))
done <"$CASES"

[ $count -gt 0 ] || { echo "run.sh: no cases match '$FILTER'" >&2; exit 2; }
cat "$FAILURES"
echo "tests for $TARGET with $("$COMPILER" --version 2>/dev/null || echo "$COMPILER"):"
awk '
    { n[$1, $2]++; cats[$1] = 1; total[$2]++ }
    END {
        printf "  %-10s %5s %6s %5s\n", "category", "pass", "xfail", "fail"
        for (c in cats) list = list c "\n"
        count = split(list, sorted, "\n")
        # Insertion sort, for awks without asort.
        for (i = 2; i < count; i++)
            for (j = i; j > 1 && sorted[j - 1] > sorted[j]; j--) {
                t = sorted[j]; sorted[j] = sorted[j - 1]; sorted[j - 1] = t
            }
        for (i = 1; i < count; i++) {
            c = sorted[i]
            printf "  %-10s %5d %6d %5d\n", c, n[c, "pass"], n[c, "xfail"], n[c, "fail"]
        }
        printf "  %-10s %5d %6d %5d\n", "total", total["pass"], total["xfail"], total["fail"]
    }
' "$TALLY"
if grep -q ' fail$' "$TALLY"; then
    exit 1
fi
exit 0
