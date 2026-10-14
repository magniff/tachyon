#!/bin/sh
# The tests of `tachyonc guide` (0.13): the guide's examples compile and
# print what it says they print, its std section is std's API, the core
# guide stays in its token budget, and the topics answer. POSIX sh and
# awk only.
#
# usage: tests/guide/run.sh [-c COMPILER] [-j JOBS] [-f FILE]
#
#   -c COMPILER   the tachyonc binary (default: target/tachyonc)
#   -j JOBS       examples compiled at once (default 2)
#   -f FILE       check only the code blocks of FILE (a topic's source,
#                 compiler/guide/NAME.md), not the embedded guide
#
# The code blocks of every topic (`tachyonc guide NAME`), by the fence's
# language:
#
#   ```tach   tachyon code, compiled with --deny-warnings: a program when
#             it has a line starting `fn main(`; else items, when every
#             line at column 0 starts an item (fn, struct, impl, use...),
#             compiled with an empty main; else statements, compiled as
#             main's body (leading `use` and `import` lines above it)
#   ```in     right after a tach block: the program's stdin (else empty)
#   ```out    after a tach block (and its in block): it is run, and its stdout and
#             stderr together are this text (trailing blanks aside);
#             `out (exit N)` expects exit code N, else 0
#   ```err    right after a tach block: compiling it fails (exit code 1)
#             with each line of this text in its diagnostics (short form)
#   other     (sh, text, rust) not checked
#
# Prints `pass NAME` or `FAIL NAME` (and why) for each check; exits 1 if
# one failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/tachyonc"
JOBS=2
ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        -j) [ $# -ge 2 ] || exit 2; JOBS=$2; shift 2 ;;
        -f) [ $# -ge 2 ] || exit 2; ONLY=$2; shift 2 ;;
        *) echo "usage: tests/guide/run.sh [-c COMPILER] [-j JOBS] [-f FILE]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "guide/run.sh: no compiler at $COMPILER" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-guide.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
STATUS=0
RESULTS="$WORK/results"
: >"$RESULTS"

# Splits the guide text $1 (topic $2) into one directory per tach block
# under $WORK/blocks: prog.tach (wrapped as its kind needs), and, when an
# out or err block follows, out (with exit) or err.
split_blocks() {
    awk -v topic="$2" -v dir="$WORK/blocks" '
        function flush_pending() { pending = "" }
        function item_line(l) {
            return l ~ /^(pub |fn |struct |enum |union |impl|trait |const |static |type |use |mod |import |extern |unsafe fn |#\[|}|\/\/|$)/
        }
        {
            line = $0
            if (!infence) {
                if (line ~ /^```/) {
                    lang = substr(line, 4)
                    infence = 1
                    body = ""
                    start = NR
                    nbody = 0
                    next
                }
                if (line !~ /^[ \t]*$/) pending = ""
                next
            }
            if (line == "```") {
                infence = 0
                if (lang == "tach") {
                    n++
                    name = topic ":" start
                    d = dir "/" topic "-" sprintf("%05d", start)
                    system("mkdir -p \"" d "\"")
                    printf "%s\n", name > (d "/name")
                    close(d "/name")
                    # the kind: program, items or statements
                    kind = "items"
                    for (i = 1; i <= nbody; i++) {
                        if (b[i] ~ /^fn main\(/) { kind = "program"; break }
                    }
                    if (kind != "program") {
                        for (i = 1; i <= nbody; i++)
                            if (b[i] !~ /^[ \t]/ && !item_line(b[i])) { kind = "stmts"; break }
                    }
                    f = d "/prog.tach"
                    if (kind == "program" || kind == "items") {
                        for (i = 1; i <= nbody; i++) print b[i] > f
                        if (kind == "items") print "fn main() -> i32 { 0 }" > f
                    } else {
                        i = 1
                        while (i <= nbody && (b[i] ~ /^(use |import )/ || b[i] ~ /^[ \t]*$/)) { print b[i] > f; i++ }
                        print "fn main() -> i32 {" > f
                        for (; i <= nbody; i++) print b[i] > f
                        print "0" > f
                        print "}" > f
                    }
                    close(f)
                    pending = d
                } else if (lang == "in" && pending != "") {
                    printf "%s", body > (pending "/stdin")
                    close(pending "/stdin")
                } else if ((lang ~ /^out/ || lang == "err") && pending != "") {
                    f = pending "/" (lang == "err" ? "err" : "out")
                    printf "%s", body > f
                    close(f)
                    if (lang ~ /^out/) {
                        code = 0
                        if (match(lang, /exit [0-9]+/)) code = substr(lang, RSTART + 5, RLENGTH - 5) + 0
                        printf "%d", code > (pending "/exit")
                        close(pending "/exit")
                    }
                    pending = ""
                } else {
                    pending = ""
                }
                next
            }
            b[++nbody] = line
            body = body line "\n"
        }
        END { if (infence) print "unterminated code block at line " start > "/dev/stderr" }
    ' "$1"
}

# Without trailing whitespace (on each line).
trimmed() {
    awk '{ sub(/[ \t\r]+$/, ""); text = text $0 "\n" } END { sub(/[\n]+$/, "", text); printf "%s", text }' "$1"
}

# Checks the block in directory $1; writes `pass NAME` or `FAIL NAME` and
# why to $1/result.
check_block() {
    d=$1
    name=$(cat "$d/name")
    if [ -f "$d/err" ]; then
        "$COMPILER" --deny-warnings --diagnostics=short "$d/prog.tach" -o "$d/prog" >"$d/compile.out" 2>&1
        rc=$?
        if [ $rc -ne 1 ]; then
            { echo "FAIL $name: expected a compile error (exit 1), got exit $rc"; sed 's/^/    /' "$d/compile.out"; } >"$d/result"
            return
        fi
        while IFS= read -r want; do
            [ -n "$want" ] || continue
            if ! grep -qF -- "$want" "$d/compile.out"; then
                { echo "FAIL $name: no error containing: $want"; sed 's/^/    /' "$d/compile.out"; } >"$d/result"
                return
            fi
        done <"$d/err"
        echo "pass $name" >"$d/result"
        return
    fi
    if ! "$COMPILER" --deny-warnings --diagnostics=short "$d/prog.tach" -o "$d/prog" >"$d/compile.out" 2>&1; then
        { echo "FAIL $name: does not compile"; sed 's/^/    /' "$d/compile.out"; } >"$d/result"
        return
    fi
    if [ ! -f "$d/out" ]; then
        echo "pass $name" >"$d/result"
        return
    fi
    [ -f "$d/stdin" ] || : >"$d/stdin"
    ( cd "$d" && exec ./prog <stdin >run.out 2>&1 ) &
    pid=$!
    (sleep 20 && kill -9 "$pid" 2>/dev/null) >/dev/null 2>&1 &
    watchdog=$!
    wait "$pid"
    rc=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    trimmed "$d/run.out" >"$d/actual"
    trimmed "$d/out" >"$d/wanted"
    if ! cmp -s "$d/actual" "$d/wanted"; then
        { echo "FAIL $name: output differs"; echo "    --- the guide says"; sed 's/^/    /' "$d/wanted"; echo
          echo "    --- it prints"; sed 's/^/    /' "$d/actual"; echo; } >"$d/result"
        return
    fi
    if [ "$rc" -ne "$(cat "$d/exit")" ]; then
        echo "FAIL $name: exit code $rc, the guide says $(cat "$d/exit")" >"$d/result"
        return
    fi
    echo "pass $name" >"$d/result"
}

# Every block under $WORK/blocks, JOBS at once; the results in order.
check_blocks() {
    i=0
    for d in "$WORK"/blocks/*/; do
        [ -d "$d" ] || continue
        check_block "${d%/}" &
        i=$((i + 1))
        if [ $((i % JOBS)) -eq 0 ]; then wait; fi
    done
    wait
    for d in "$WORK"/blocks/*/; do
        [ -f "$d/result" ] && cat "$d/result" >>"$RESULTS"
    done
}

result() { # <pass|FAIL> <name> [why...]
    if [ "$1" = pass ]; then
        echo "pass $2" >>"$RESULTS"
    else
        n=$2
        shift 2
        { echo "FAIL $n: $1"; shift; for l in "$@"; do echo "    $l"; done; } >>"$RESULTS"
    fi
}

mkdir -p "$WORK/blocks"
if [ -n "$ONLY" ]; then
    split_blocks "$ONLY" "$(basename "$ONLY" .md)"
    check_blocks
    cat "$RESULTS"
    grep -q '^FAIL' "$RESULTS" && exit 1
    exit 0
fi

# The guide built into the compiler is its source's.
if "$ROOT/compiler/guide/embed.sh" -c >"$WORK/embed.out" 2>&1; then
    result pass guide-embedded
else
    result FAIL guide-embedded "$(cat "$WORK/embed.out")"
fi

# The source is ASCII, without tabs: the text is embedded byte for byte.
if grep -n '[^ -~]' "$ROOT"/compiler/guide/*.md >"$WORK/ascii.out"; then
    result FAIL guide-ascii "a byte that is not printable ASCII:" "$(head -3 "$WORK/ascii.out")"
else
    result pass guide-ascii
fi

# The topics: --list names each one, with its size; each answers.
if ! "$COMPILER" guide --list >"$WORK/list" 2>&1; then
    result FAIL guide-list "tachyonc guide --list failed:" "$(cat "$WORK/list")"
fi
missing=""
for t in core rust syntax types std errors unsafe c-interop modules generics traits closures iterators memory tools; do
    awk -F '\t' -v t="$t" '$1 == t { found = 1 } END { exit !found }' "$WORK/list" || missing="$missing $t"
done
if [ -n "$missing" ]; then
    result FAIL guide-list "topics missing from --list:$missing"
else
    result pass guide-list
fi
cut -f 1 "$WORK/list" >"$WORK/topics"
while IFS= read -r t; do
    if "$COMPILER" guide "$t" >"$WORK/topic-$t.md" 2>"$WORK/topic-$t.err" && [ -s "$WORK/topic-$t.md" ] \
        && [ ! -s "$WORK/topic-$t.err" ]; then
        split_blocks "$WORK/topic-$t.md" "$t"
    else
        result FAIL "guide-topic-$t" "tachyonc guide $t failed:" "$(cat "$WORK/topic-$t.err")"
    fi
done <"$WORK/topics"

# The default output is the core guide; it stays in its budget (about 7k
# tokens, at 4 bytes a token).
"$COMPILER" guide >"$WORK/default.md" 2>&1
if ! cmp -s "$WORK/default.md" "$WORK/topic-core.md"; then
    result FAIL guide-default "tachyonc guide is not tachyonc guide core"
else
    size=$(wc -c <"$WORK/default.md" | tr -d ' ')
    if [ "$size" -gt 28672 ]; then
        result FAIL guide-budget "the core guide is $size bytes, over 28672 (7k tokens): move detail to a topic"
    else
        result pass guide-budget
    fi
fi

# A topic that does not exist: one line, and what to run.
"$COMPILER" guide no-such-topic >"$WORK/bad.out" 2>&1
rc=$?
if [ $rc -eq 1 ] && grep -q '^error guide.no-topic: ' "$WORK/bad.out" && grep -q '^try: .* guide --list$' "$WORK/bad.out"; then
    result pass guide-no-topic
else
    result FAIL guide-no-topic "exit $rc:" "$(cat "$WORK/bad.out")"
fi

# --all is every topic, in order.
"$COMPILER" guide --all >"$WORK/all.md" 2>&1
: >"$WORK/cat.md"
while IFS= read -r t; do cat "$WORK/topic-$t.md" >>"$WORK/cat.md"; done <"$WORK/topics"
if cmp -s "$WORK/all.md" "$WORK/cat.md"; then
    result pass guide-all
else
    result FAIL guide-all "tachyonc guide --all is not every topic in turn"
fi

# The std topic is std's API: every public item, as the compiler's item
# index has it, is there (without `pub`).
mkdir -p "$WORK/std"
printf 'fn main() -> i32 {\n    let v: Vec<i64> = Vec::new();\n    0\n}\n' >"$WORK/std/main.tach"
if (cd "$WORK/std" && "$COMPILER" query items std --root main.tach) >"$WORK/std/items" 2>&1; then
    awk -F '\t' '$3 ~ /^pub / { s = $3; sub(/^pub /, "", s); print s }' "$WORK/std/items" >"$WORK/std/want"
    : >"$WORK/std/missing"
    while IFS= read -r sig; do
        grep -qF -- "$sig" "$WORK/topic-std.md" || echo "$sig" >>"$WORK/std/missing"
    done <"$WORK/std/want"
    if [ ! -s "$WORK/std/want" ]; then
        result FAIL guide-std "query items std listed no public item"
    elif [ -s "$WORK/std/missing" ]; then
        result FAIL guide-std "std items missing from tachyonc guide std:" "$(head -5 "$WORK/std/missing")"
    else
        result pass guide-std
    fi
else
    result FAIL guide-std "query items std failed:" "$(cat "$WORK/std/items")"
fi

check_blocks
cat "$RESULTS"
grep -q '^FAIL' "$RESULTS" && exit 1
exit 0
