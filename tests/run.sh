#!/bin/sh
# The test suite of this release, run with a tachyon compiler (no cargo
# needed): every tests/run/*.tach and tests/examples/*.test case is
# compiled, assembled and linked with clang, run, and checked.
#
# usage: tests/run.sh [-c COMPILER] [FILTER]
#
#   -c COMPILER   the tachyonc binary to test (default: target/tachyonc,
#                 as left by bootstrap/bootstrap.sh)
#   FILTER        run only the cases whose name contains FILTER
#
# Environment: CC is the assembler/linker (default clang).
#
# Directives, in `//` comments of the case file:
#   // ARGS: a b c       command-line arguments (whitespace separated)
#   // STDIN: text       stdin, one directive per line, joined with '\n'
#   // EXPECT: text      expected stdout, one directive per line
#   // EXIT: 3           expected exit code (default 0)
#   // ERROR: text       compilation must fail (exit code 1) with an error
#                        containing this text; one directive per message
#   // XFAIL: reason     a known bug: the case is expected to fail, and
#                        reported as a failure (XPASS) once it passes
#   // SOURCE: path      (.test files) the program, relative to the root
#   // BUILD: reason     (.test files) only compile and link it
# Stdout is compared after removing trailing whitespace. Each program may
# run for 20 seconds.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/tachyonc"
CC=${CC:-clang}
TIMEOUT=20

usage() {
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || usage; COMPILER=$2; shift 2 ;;
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
command -v "$CC" >/dev/null 2>&1 || { echo "run.sh: '$CC' not found" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
FAILURES="$WORK/failures"
TALLY="$WORK/tally"
: >"$FAILURES"
: >"$TALLY"

# Writes the directives of case file $1 into directory $2: one file per
# directive (args, stdin, expect, exit, errors, xfail, source, build).
read_directives() {
    awk -v dir="$2" '
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
            else if (key == "ERROR") errors = errors value "\n"
            else if (key == "XFAIL") xfail = value
            else if (key == "SOURCE") source = value
            else if (key == "BUILD") build = 1
        }
        END {
            printf "%s", args > (dir "/args")
            printf "%s", stdin > (dir "/stdin")
            printf "%s", expect > (dir "/expect")
            printf "%d", exitcode > (dir "/exit")
            printf "%s", errors > (dir "/errors")
            printf "%s", xfail > (dir "/xfail")
            printf "%s", source > (dir "/source")
            printf "%d", build > (dir "/build")
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
        "$COMPILER" "$source" -o "$dir/prog.s" >"$dir/compile.out" 2>&1
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
    if ! "$COMPILER" "$source" -o "$dir/prog.s" >"$dir/compile.out" 2>&1; then
        { echo "compile failed:"; cat "$dir/compile.out"; } >"$dir/why"
        return 1
    fi
    if ! "$CC" -arch arm64 -o "$dir/prog" "$dir/prog.s" -lm >"$dir/link.out" 2>&1; then
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
    return 0
}

count=0
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
    dir="$WORK/$name"
    mkdir -p "$dir"
    read_directives "$file" "$dir"
    category=${name%%_*}
    [ -s "$dir/errors" ] && category=error
    if check_case "$file" "$dir"; then
        if [ -s "$dir/xfail" ]; then
            echo "$category fail" >>"$TALLY"
            echo "XPASS $name: passes but is marked XFAIL ($(cat "$dir/xfail")); remove the directive" >>"$FAILURES"
        else
            echo "$category pass" >>"$TALLY"
        fi
    elif [ -s "$dir/xfail" ]; then
        echo "$category xfail" >>"$TALLY"
    else
        echo "$category fail" >>"$TALLY"
        { echo "FAIL $name:"; sed 's/^/    /' "$dir/why"; echo; } >>"$FAILURES"
    fi
    count=$((count + 1))
done

[ $count -gt 0 ] || { echo "run.sh: no cases match '$FILTER'" >&2; exit 2; }
cat "$FAILURES"
echo "tests with $("$COMPILER" --version 2>/dev/null || echo "$COMPILER"):"
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
