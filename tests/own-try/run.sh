#!/bin/sh
# The try: lines of the own pass's diagnostics, run (0.17,
# docs/design/value-semantics.md §2.9: "The try: lines are tested"). POSIX
# sh and awk only.
#
# usage: tests/own-try/run.sh [-c COMPILER] [FILTER]
#
# Each tests/own-try/NAME/ is a program (main.tach, and its other files);
# directives in `//` comments of main.tach:
#   // OWN: CODE     `check --values=error` reports CODE first (own.moved,
#                    own.conflict, ...; `type error` too); `none`: the
#                    program checks clean (an agent's pattern that must not
#                    be rejected)
#   // TRY: text     one of the first diagnostic's try: lines contains text
#                    (§2.9's exact commands), one directive per line
#   // XFAIL: why    the checker task that reports CODE has not landed:
#                    the case is expected to fail, and reported as a
#                    failure (XPASS) once it passes
# Then every try: line of the first diagnostic that is a tachyonc command
# is run on a fresh copy (as printed: the compiler's path replaced), and
# the program checked again: it must check clean, or report a different
# next step (another code, an edit.breaks with its own try: lines); a
# `query` line must answer (exit 0).
#
# Prints `pass NAME`, `xfail NAME` or `FAIL NAME` (and why); exits 1 if
# one failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/tachyonc"
FILTER=""
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        -*) echo "usage: tests/own-try/run.sh [-c COMPILER] [FILTER]" >&2; exit 2 ;;
        *) FILTER=$1; shift ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "own-try/run.sh: no compiler at $COMPILER" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-own-try.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
unset TACHYON_ROOT
STATUS=0

# directive NAME FILE: the values of `// NAME: value` lines, one per line.
directive() {
    awk -v key="$1" '
        { line = $0; sub(/^[ \t]*/, "", line) }
        index(line, "// " key ":") == 1 {
            v = substr(line, length(key) + 5); sub(/^[ \t]*/, "", v); print v
        }' "$2"
}

# The first diagnostic of `check --values=error` in directory $1 (one
# line, short form), into $1/../diag; its exit code is the function's.
first_diag() {
    (cd "$1" && "$COMPILER" check --values=error main.tach) >"$WORK/out" 2>&1
    st=$?
    grep -m 1 'error' "$WORK/out" >"$WORK/diag" || : >"$WORK/diag"
    return $st
}

# The try: lines of the diagnostic in $WORK/diag, one per line.
try_lines() {
    awk '{
        n = split($0, parts, / \| /)
        for (i = 1; i <= n; i++) {
            p = parts[i]; sub(/^[ \t]*/, "", p); sub(/[ \t]*\[(in|edited)[^]]*\][ \t]*$/, "", p)
            if (index(p, "try: ") == 1) print substr(p, 6)
        }
    }' "$WORK/diag"
}

for dir in "$HERE"/*/; do
    name=$(basename "$dir")
    case "$name" in *"$FILTER"*) ;; *) continue ;; esac
    main="$dir/main.tach"
    [ -f "$main" ] || continue
    code=$(directive OWN "$main" | head -n 1)
    xfail=$(directive XFAIL "$main" | head -n 1)
    why=""
    rm -rf "$WORK/case"
    cp -R "$dir" "$WORK/case"
    if first_diag "$WORK/case"; then
        if [ "$code" != "none" ]; then
            why="checks clean; expected $code"
        fi
    elif [ "$code" = "none" ]; then
        why="rejected: $(head -n 1 "$WORK/out")"
    elif ! grep -q "error\[$code\]" "$WORK/diag"; then
        why="expected error[$code] first, got: $(head -n 1 "$WORK/out")"
    fi
    if [ -z "$why" ] && [ "$code" != "none" ]; then
        try_lines >"$WORK/tries"
        directive TRY "$main" >"$WORK/wanted"
        while IFS= read -r want; do
            if ! grep -qF -- "$want" "$WORK/tries"; then
                why="no try: line has: $want"
                break
            fi
        done <"$WORK/wanted"
        k=0
        while [ -z "$why" ] && IFS= read -r cmd; do
            k=$((k + 1))
            # (a command: its first word is the compiler, as printed)
            first=${cmd%% *}
            case "$first" in
                *tachyonc) ;;
                *) continue ;;
            esac
            rest=${cmd#"$first"}
            rm -rf "$WORK/run"
            cp -R "$dir" "$WORK/run"
            (cd "$WORK/run" && git init -q . 2>/dev/null \
                && git -c user.name=t -c user.email=t@t add -A >/dev/null 2>&1 \
                && git -c user.name=t -c user.email=t@t commit -q -m case >/dev/null 2>&1)
            (cd "$WORK/run" && eval "\"\$COMPILER\" $rest") >"$WORK/tryout" 2>&1
            st=$?
            case "$rest" in
                " query "*)
                    [ $st -eq 0 ] || why="try $k ($cmd) failed: $(head -n 1 "$WORK/tryout")"
                    continue ;;
            esac
            if [ $st -ne 0 ] && ! grep -q "edit.breaks" "$WORK/tryout"; then
                why="try $k ($cmd) failed: $(head -n 1 "$WORK/tryout")"
                continue
            fi
            if [ $st -ne 0 ]; then
                # (edit.breaks: the next step is named, with its own try:)
                grep -q "try:" "$WORK/tryout" \
                    || why="try $k ($cmd): edit.breaks without a next step"
                continue
            fi
            if ! first_diag "$WORK/run"; then
                if grep -q "error\[$code\]" "$WORK/diag"; then
                    why="try $k ($cmd) left the error: $(cat "$WORK/diag")"
                fi
            fi
        done <"$WORK/tries"
    fi
    if [ -n "$xfail" ]; then
        if [ -n "$why" ]; then
            echo "xfail $name"
        else
            echo "FAIL $name: XPASS: passes but is marked XFAIL ($xfail); remove the directive"
            STATUS=1
        fi
    elif [ -n "$why" ]; then
        echo "FAIL $name: $why"
        STATUS=1
    else
        echo "pass $name"
    fi
done
exit $STATUS
