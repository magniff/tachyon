#!/bin/sh
# The tests of `tachyonc lsp` (0.24, docs/lsp.md): scripted sessions.
# POSIX sh and awk only.
#
# usage: tests/lsp/run.sh [-c COMPILER] [-u]
#
#   -c COMPILER   the tachyonc binary (default: target/tachyonc)
#   -u            rewrite the .lsp files with the answers they get now
#
# Each tests/lsp/NAME.lsp is a session with the program tests/lsp/prog
# (copied to a scratch directory, @DIR@ in the file): a line `> JSON` is
# a message of the client, framed (`Content-Length`) and sent; `> @open
# FILE` sends didOpen with FILE's text as it is on disk, `> @change FILE
# TEXT` didChange, FILE getting the text of tests/lsp/texts/TEXT. After a
# request the next message waits for its response, as an editor does;
# in a session whose first line is `## burst` every message is sent at
# once (a request then sees the changes queued after it). A line `< JSON`
# is a message of the server: after a request's line, the messages up to
# its response (the diagnostics published before it), and at the end
# the ones after the last response. `##` lines are comments. The
# scratch directory is written @DIR@ in the answers, the compiler's path
# `tachyonc`.
#
# Then the compiler's own source is opened and asked for a file's symbols
# and a definition: the answers must be plausible (it changes too often
# for a transcript), and the times are printed (TACHYON_LSP_TIME).
#
# Prints `pass NAME` or `FAIL NAME` (and the difference) for each
# session; exits 1 if one failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/tachyonc"
UPDATE=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        -u) UPDATE=1; shift ;;
        *) echo "usage: tests/lsp/run.sh [-c COMPILER] [-u]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "lsp/run.sh: no compiler at $COMPILER" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-lsp.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
STATUS=0

# The JSON string of file $1's text (quoted, escaped).
json_text() {
    awk 'BEGIN { ORS = ""; print "\"" }
        { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); print $0 "\\n" }
        END { print "\"" }' "$1"
}

# Message $1 framed, onto stdout.
frame() {
    n=$(printf '%s' "$1" | wc -c)
    printf 'Content-Length: %d\r\n\r\n%s' $((n)) "$1"
}

# The messages of the session file $1 (the program at $2), framed, each
# into $WORK/msg.K, and $WORK/msgs: a line `K ID` per message (ID: a
# request's id, else -).
session_input() {
    : >"$WORK/msgs"
    k=0
    grep '^> ' "$1" | sed 's/^> //' | while IFS= read -r line; do
        case "$line" in
            @open\ *)
                f=${line#@open }
                msg="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://$2/$f\",\"languageId\":\"tachyon\",\"version\":1,\"text\":$(json_text "$2/$f")}}}"
                ;;
            @change\ *)
                set -- "$1" "$2" ${line#@change }
                msg="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"file://$2/$3\",\"version\":2},\"contentChanges\":[{\"text\":$(json_text "$HERE/texts/$4")}]}}"
                set -- "$1" "$2"
                ;;
            *) msg=$(printf '%s' "$line" | sed "s|@DIR@|$2|g") ;;
        esac
        k=$((k + 1))
        frame "$msg" >"$WORK/msg.$k"
        id=$(printf '%s' "$line" | sed -n 's/^{"jsonrpc":"2.0","id":\([0-9]*\),.*/\1/p')
        echo "$k ${id:--}" >>"$WORK/msgs"
    done
}

# Runs the server in directory $1 on the messages, waiting for each
# request's response unless $2 is burst; its exit status.
run_session() {
    if [ "$2" = burst ]; then
        # (from a file: all of it there when the server reads)
        : >"$WORK/in"
        while read -r k id; do cat "$WORK/msg.$k" >>"$WORK/in"; done <"$WORK/msgs"
        (cd "$1" && exec "$COMPILER" lsp <"$WORK/in" >"$WORK/out" 2>"$WORK/err")
        return
    fi
    rm -f "$WORK/fifo"
    mkfifo "$WORK/fifo"
    (cd "$1" && exec "$COMPILER" lsp <"$WORK/fifo" >"$WORK/out" 2>"$WORK/err") &
    pid=$!
    exec 3>"$WORK/fifo"
    while read -r k id; do
        cat "$WORK/msg.$k" >&3
        [ "$id" = - ] && continue
        tries=0
        until grep -q -F "\"jsonrpc\":\"2.0\",\"id\":$id," "$WORK/out"; do
            tries=$((tries + 1))
            if [ $tries -gt 3000 ] || ! kill -0 "$pid" 2>/dev/null; then
                break
            fi
            sleep 0.02
        done
    done <"$WORK/msgs"
    exec 3>&-
    wait "$pid"
}

# The server's messages in $WORK/out, one per line (bodies hold no
# newline), the directory and compiler written back as placeholders.
unframe() {
    tr -d '\r' <"$WORK/out" | sed 's/Content-Length: [0-9]*$//' | sed '/^$/d' \
        | sed "s|$2|@DIR@|g; s|$COMPILER|tachyonc|g"
}

# The transcript of session $1: its `##` and `>` lines, each request's
# answers after it.
transcript() {
    awk -v answers="$WORK/answers" '
        BEGIN { n = 0; while ((getline l < answers) > 0) a[n++] = l; k = 0 }
        /^##/ { print; next }
        /^> / {
            print
            if (match($0, /"id":[0-9]+/)) {
                id = substr($0, RSTART, RLENGTH)
                while (k < n) {
                    print "< " a[k]
                    hit = index(a[k], "\"jsonrpc\":\"2.0\"," id ",") > 0
                    k++
                    if (hit) break
                }
            }
            next
        }
        END { while (k < n) print "< " a[k++] }' "$1"
}

for case in "$HERE"/*.lsp; do
    [ -e "$case" ] || continue
    name=$(basename "$case" .lsp)
    dir="$WORK/$name"
    rm -rf "$dir"
    mkdir -p "$dir"
    cp "$HERE"/prog/*.tach "$dir/"
    session_input "$case" "$dir"
    mode=sync
    head -1 "$case" | grep -q '^## burst' && mode=burst
    run_session "$dir" "$mode"
    rc=$?
    unframe "$WORK/out" "$dir" >"$WORK/answers"
    transcript "$case" >"$WORK/got"
    if [ "$UPDATE" = 1 ]; then
        cp "$WORK/got" "$case"
    fi
    if [ "$rc" != 0 ]; then
        echo "FAIL $name"
        echo "    exit $rc"
        sed 's/^/    /' "$WORK/err"
        STATUS=1
    elif diff "$case" "$WORK/got" >"$WORK/diff"; then
        echo "pass $name"
    else
        echo "FAIL $name"
        sed 's/^/    /' "$WORK/diff" | head -40
        STATUS=1
    fi
done

# The compiler's own source: plausible answers, and their times.
SRC="$ROOT/compiler/src"
if [ -f "$SRC/main.tach" ]; then
    F="$SRC/tools/lsp/mod.tach"
    U="file://$F"
    {
        frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
        frame "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"$U\"}}}"
        line=$(grep -n '^pub fn run_lsp' "$F" | cut -d: -f1)
        frame "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/references\",\"params\":{\"textDocument\":{\"uri\":\"$U\"},\"position\":{\"line\":$((line - 1)),\"character\":8},\"context\":{\"includeDeclaration\":true}}}"
        frame "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"$U\"},\"position\":{\"line\":$((line - 1)),\"character\":8}}}"
        frame '{"jsonrpc":"2.0","id":5,"method":"shutdown"}'
        frame '{"jsonrpc":"2.0","method":"exit"}'
    } >"$WORK/in"
    TACHYON_LSP_TIME=1 "$COMPILER" lsp <"$WORK/in" >"$WORK/out" 2>"$WORK/err"
    rc=$?
    unframe "$WORK/out" "$WORK" >"$WORK/answers"
    if [ "$rc" = 0 ] && grep -q '"name":"run_lsp"' "$WORK/answers" \
        && grep -q 'tools/commands.tach' "$WORK/answers" \
        && grep -q 'effects: ' "$WORK/answers"; then
        echo "pass compiler-source"
        grep '^lsp' "$WORK/err" | sed 's/^/    /'
    else
        echo "FAIL compiler-source"
        echo "    exit $rc"
        cut -c1-300 "$WORK/answers" | sed 's/^/    /'
        sed 's/^/    /' "$WORK/err"
        STATUS=1
    fi
fi
exit $STATUS
