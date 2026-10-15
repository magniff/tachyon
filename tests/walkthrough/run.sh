#!/bin/sh
# The walkthroughs of examples/tools/ (0.15): each README.md is a
# transcript, run as it is written, so that its commands and their
# output never go stale. POSIX sh and awk only.
#
# usage: tests/walkthrough/run.sh [-c COMPILER] [-u] [NAME...]
#
#   -c COMPILER   the tachyonc binary (default: target/tachyonc)
#   -u            rewrite the READMEs' session blocks with the output
#                 they get now (the prose around them is kept)
#   NAME          only these examples (examples/tools/NAME/)
#
# Each examples/tools/NAME/README.md is run in a fresh copy of its
# directory, made a git repository (one commit, branch main, so that
# edits are journaled for undo and `git diff` shows what changed). The
# README's ```console blocks are the session, in order:
#
#   $ COMMAND     a shell command line, run in the copy (`tachyonc` is
#                 the compiler under test, first in PATH)
#   > MORE        the command's next line (a heredoc's text), right
#                 after its `$` line
#   other lines   the command's output: stdout, then stderr, then
#                 `[exit N]` when N is not 0
#
# The other blocks (```tach, ```diff, ...) and the prose are not run. An
# example passes when every console block is what its commands print now.
# HOME and git's configuration are the runner's own (git's defaults: a
# conflict looks the same on every machine).
#
# Prints `pass NAME` or `FAIL NAME` (and why) for each; exits 1 if one
# failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/tachyonc"
UPDATE=0
ONLY=
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        -u) UPDATE=1; shift ;;
        -*) echo "usage: tests/walkthrough/run.sh [-c COMPILER] [-u] [NAME...]" >&2; exit 2 ;;
        *) ONLY="$ONLY $1"; shift ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "walkthrough/run.sh: no compiler at $COMPILER" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-walkthrough.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
STATUS=0

# The environment of the sessions: the compiler as `tachyonc`, an empty
# HOME, git with no configuration but a name.
mkdir -p "$WORK/bin" "$WORK/home"
ln -s "$COMPILER" "$WORK/bin/tachyonc"
PATH="$WORK/bin:$PATH"
HOME="$WORK/home"
XDG_CONFIG_HOME="$WORK/home"
GIT_CONFIG_NOSYSTEM=1
GIT_AUTHOR_NAME=you
GIT_AUTHOR_EMAIL=you@example.com
GIT_COMMITTER_NAME=you
GIT_COMMITTER_EMAIL=you@example.com
GIT_AUTHOR_DATE='2026-01-01T00:00:00Z'
GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
export PATH HOME XDG_CONFIG_HOME GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL \
    GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_AUTHOR_DATE GIT_COMMITTER_DATE
unset TACHYON_ROOT

# Splits README $1 into $2/want (the console blocks, each ended by a
# line ```), $2/cmd.N (the commands, numbered from 1) and $2/blocks
# (`N B`: command N is in block B).
split_readme() {
    awk -v out="$2" '
        function flush() { if (cmd != "") { printf "%s", cmd > (out "/cmd." n); close(out "/cmd." n); cmd = "" } }
        /^```console[ \t]*$/ && !in_block { in_block = 1; b++; cont = 0; next }
        in_block && /^```[ \t]*$/ {
            flush(); in_block = 0; print "```" > (out "/want"); next
        }
        !in_block { next }
        /^\$ / {
            flush(); n++; cmd = substr($0, 3) "\n"; cont = 1
            print n " " b > (out "/blocks")
            print > (out "/want"); next
        }
        cont && /^> / { cmd = cmd substr($0, 3) "\n"; print > (out "/want"); next }
        { cont = 0; print > (out "/want") }
        END { flush() }
    ' "$1"
}

# Runs the session of README $1 into $WORK/meta-NAME/result (`pass NAME`
# or `FAIL NAME` and why).
run_one() {
    readme=$1
    src=$(dirname "$readme")
    name=$(basename "$src")
    meta="$WORK/meta-$name"
    dir="$WORK/$name"
    mkdir -p "$meta" "$dir"
    : >"$meta/want"
    : >"$meta/blocks"
    split_readme "$readme" "$meta"
    cp -R "$src/." "$dir/"
    (cd "$dir" && git init -q . && git symbolic-ref HEAD refs/heads/main && git add -A \
        && git commit -q -m start) >/dev/null 2>&1
    TACHYON_CACHE="$WORK/cache-$name"
    export TACHYON_CACHE
    : >"$meta/got"
    last=1
    while read -r n b; do
        while [ "$last" -lt "$b" ]; do
            echo '```' >>"$meta/got"
            last=$((last + 1))
        done
        awk 'NR == 1 { print "$ " $0; next } { print "> " $0 }' "$meta/cmd.$n" >>"$meta/got"
        (
            cd "$dir" || exit 1
            sh "$meta/cmd.$n" >"$meta/out" 2>"$meta/err" </dev/null
            rc=$?
            # (the compiler as the shell found it: some systems give
            # it its path in PATH, the link to COMPILER)
            cat "$meta/out" "$meta/err" | sed -e "s|$WORK/bin/tachyonc|tachyonc|g" -e "s|$COMPILER|tachyonc|g" -e "s|$dir|WORK|g" -e "s|$WORK|WORK|g"
            [ $rc -eq 0 ] || echo "[exit $rc]"
        ) >>"$meta/got"
    done <"$meta/blocks"
    nblocks=$(grep -c '^```$' "$meta/want")
    while [ "$last" -le "$nblocks" ]; do
        echo '```' >>"$meta/got"
        last=$((last + 1))
    done
    if [ "$UPDATE" -eq 1 ]; then
        # each console block's lines become the ones it got
        awk -v got="$meta/got" '
            /^```console[ \t]*$/ && !in_block {
                print; in_block = 1
                while ((getline line < got) > 0 && line != "```") print line
                next
            }
            in_block && /^```[ \t]*$/ { in_block = 0; print; next }
            in_block { next }
            { print }
        ' "$readme" >"$meta/new" && cp "$meta/new" "$readme"
        cp "$meta/got" "$meta/want"
    fi
    if cmp -s "$meta/want" "$meta/got"; then
        echo "pass $name"
    else
        echo "FAIL $name: the session differs (< README, > got):"
        diff "$meta/want" "$meta/got" | sed 's/^/    /' | head -40
    fi >"$meta/result"
}

# The examples run at once (each is serial, and mostly waits on the
# compiler and cc); the results are printed in order.
names=
for readme in "$ROOT"/examples/tools/*/README.md; do
    [ -f "$readme" ] || continue
    name=$(basename "$(dirname "$readme")")
    if [ -n "$ONLY" ]; then
        case " $ONLY " in *" $name "*) ;; *) continue ;; esac
    fi
    names="$names $name"
    run_one "$readme" &
done
wait
for name in $names; do
    cat "$WORK/meta-$name/result" 2>/dev/null || echo "FAIL $name: no result"
    grep -q '^pass' "$WORK/meta-$name/result" 2>/dev/null || STATUS=1
done
exit $STATUS
