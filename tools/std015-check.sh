#!/bin/sh
# The acceptance check of `volec fix --only std015` (0.15,
# docs/design/errors-formatting.md): the tests/run cases written against
# 0.14's std (parse_int, Scanner::next_int, read_line, read_stdin), taken
# as they were at REV (before 0.15 migrated them by hand), migrated by the
# fix, compiled by a 0.15 compiler, print what their `// EXPECT:` lines
# say for their `// STDIN:` lines. POSIX sh.
#
# usage: tools/std015-check.sh [-c COMPILER] [REV]
#
#   COMPILER  a compiler with 0.15's std (default: target/volec)
#   REV       the commit the 0.14-API cases are read from (default:
#             c15-phase0, the 0.15 interface commit)
#
# Prints `pass NAME` or `FAIL NAME` (and why) for each case; exits 1 if
# one failed.

set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/volec"
if [ $# -ge 2 ] && [ "$1" = -c ]; then
    COMPILER=$2
    shift 2
fi
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
REV=${1:-c15-phase0}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-std015.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
STATUS=0
cases=$(git -C "$ROOT" grep -l -E 'parse_int|read_line|read_stdin|next_int' "$REV" -- tests/run \
    | sed "s|^$REV:||" | grep '\.vl$')
for path in $cases; do
    name=$(basename "$path" .vl)
    d="$WORK/$name"
    mkdir -p "$d"
    git -C "$ROOT" show "$REV:$path" >"$d/main.vl"
    # (an error case, or none with an output to compare: not this check's)
    if ! grep -q '^// EXPECT:' "$d/main.vl" || grep -q '^// ERROR' "$d/main.vl"; then
        continue
    fi
    # (as tests/run.sh: the lines joined with newlines, none after the last)
    awk 'sub(/^\/\/ STDIN: ?/, "") { printf "%s%s", (n++ ? "\n" : ""), $0 }' "$d/main.vl" >"$d/stdin"
    sed -n 's|^// EXPECT: \{0,1\}||p' "$d/main.vl" >"$d/want"
    (cd "$d" && git init -q . && git -c user.name=t -c user.email=t@t add -A \
        && git -c user.name=t -c user.email=t@t commit -q -m case) >/dev/null 2>&1
    if ! (cd "$d" && "$COMPILER" fix --only std015 main.vl) >"$d/fix.out" 2>&1; then
        echo "FAIL $name: fix --only std015 failed:"
        sed 's/^/    /' "$d/fix.out" | head -10
        STATUS=1
        continue
    fi
    if ! "$COMPILER" "$d/main.vl" -o "$d/prog" >"$d/build.out" 2>&1; then
        echo "FAIL $name: does not compile once migrated:"
        sed 's/^/    /' "$d/build.out" | head -10
        STATUS=1
        continue
    fi
    "$d/prog" <"$d/stdin" 2>/dev/null | awk 1 >"$d/got"
    if cmp -s "$d/want" "$d/got"; then
        echo "pass $name"
    else
        echo "FAIL $name: the output differs (< expected, > got):"
        diff "$d/want" "$d/got" | sed 's/^/    /' | head -20
        STATUS=1
    fi
done
exit $STATUS
