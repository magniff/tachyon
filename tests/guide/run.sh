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
#             main's body (leading `use` and `import` lines above it;
#             0.16: main is `fn main(gpa: Gpa)`, its allocator `gpa`)
#   ```tach NAME.tach
#             (0.17) a file of a program of several modules: the blocks
#             named so, in a row (prose between them, no other block),
#             are written next to each other and main.tach is compiled;
#             an in and out block after the last one are the program's
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

HOST="$(uname -s)-$(uname -m)"
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
                if (lang ~ /^tach [a-z_][a-z0-9_]*\.tach$/) {
                    # (0.17) a file of a program of several: the blocks
                    # `tach NAME.tach` in a row are one program, built from
                    # main.tach; an in or out block after them is its
                    if (proj == "") {
                        n++
                        proj = dir "/" topic "-" sprintf("%05d", start)
                        system("mkdir -p \"" proj "\"")
                        printf "%s\n", topic ":" start > (proj "/name")
                        close(proj "/name")
                    }
                    fname = substr(lang, 6)
                    f = proj "/" (fname == "main.tach" ? "prog.tach" : fname)
                    for (i = 1; i <= nbody; i++) print b[i] > f
                    close(f)
                    pending = proj
                    next
                }
                if (lang == "in" || lang ~ /^out/ || lang == "err") {
                    if (proj != "") pending = proj
                } else {
                    proj = ""
                }
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
                        # (0.16: the allocator of main, gpa, for the statements)
                        print "fn main(gpa: Gpa) -> i32 {" > f
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
                    proj = ""
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
    # (0.18: from its directory, as main.tach: a failed check's position
    # reads `main.tach:LINE:COL`, as the guide shows it)
    cp "$d/prog.tach" "$d/main.tach"
    # (0.22) A program of std::gpu or std::objc links libobjc and runs on
    # macOS/arm64 (Metal); elsewhere it is compiled to an object only.
    link=""
    if grep -q 'std::gpu\|std::objc' "$d/main.tach"; then
        if [ "$HOST" = Darwin-arm64 ]; then
            link="-l objc"
        else
            if (cd "$d" && "$COMPILER" --deny-warnings --diagnostics=short main.tach -o prog.o) >"$d/compile.out" 2>&1; then
                echo "pass $name" >"$d/result"
            else
                { echo "FAIL $name: does not compile"; sed 's/^/    /' "$d/compile.out"; } >"$d/result"
            fi
            return
        fi
    fi
    if ! (cd "$d" && "$COMPILER" --deny-warnings --diagnostics=short main.tach $link -o prog) >"$d/compile.out" 2>&1; then
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
for t in core language rust syntax types std errors unsafe c-interop arch modules generics traits closures iterators conversions formatting memory views tools gpu; do
    awk -F '\t' -v t="$t" '$1 == t { found = 1 } END { exit !found }' "$WORK/list" || missing="$missing $t"
done
if [ -n "$missing" ]; then
    result FAIL guide-list "topics missing from --list:$missing"
else
    result pass guide-list
fi
cut -f 1 "$WORK/list" >"$WORK/topics"
while IFS= read -r t; do
    # (0.18.1: --whole, a topic past its first page, as --all prints it)
    if "$COMPILER" guide "$t" --whole >"$WORK/topic-$t.md" 2>"$WORK/topic-$t.err" && [ -s "$WORK/topic-$t.md" ] \
        && [ ! -s "$WORK/topic-$t.err" ]; then
        split_blocks "$WORK/topic-$t.md" "$t"
    else
        result FAIL "guide-topic-$t" "tachyonc guide $t failed:" "$(cat "$WORK/topic-$t.err")"
    fi
done <"$WORK/topics"

# The default output is the core guide; it stays in its budget (0.17:
# about 2k tokens, 2.5k at most, at 4 bytes a token), without std's
# listing (`guide std`).
"$COMPILER" guide >"$WORK/default.md" 2>&1
if ! cmp -s "$WORK/default.md" "$WORK/topic-core.md"; then
    result FAIL guide-default "tachyonc guide is not tachyonc guide core"
else
    size=$(wc -c <"$WORK/default.md" | tr -d ' ')
    if [ "$size" -gt 10240 ]; then
        result FAIL guide-budget "the core guide is $size bytes, over 10240 (2.5k tokens): move detail to a topic (language, rust, errors...)"
    elif grep -q 'fn with_capacity_in' "$WORK/default.md"; then
        result FAIL guide-budget "the core guide holds std's listing: it belongs in guide std"
    else
        result pass guide-budget
    fi
fi

# --full (0.17) is the long form, topic language, with std's API in it.
"$COMPILER" guide --full >"$WORK/full.md" 2>&1
if [ "$(head -1 "$WORK/full.md")" = "$(head -1 "$WORK/topic-language.md")" ]; then
    if grep -qF 'fn new_in(a: A) -> Vec<T, A>' "$WORK/full.md" \
        && ! grep -qF 'fn new_in(a: A) -> Vec<T, A>' "$WORK/topic-language.md" \
        && ! grep -q '@STD-API' "$WORK/full.md" "$WORK/topic-language.md"; then
        result pass guide-full
    else
        result FAIL guide-full "tachyonc guide --full lacks std's API (or guide language has it)"
    fi
else
    result FAIL guide-full "tachyonc guide --full does not start as guide language:" "$(head -2 "$WORK/full.md")"
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
# index has it, is in its section std#every-item (without `pub`).
mkdir -p "$WORK/std"
"$COMPILER" guide 'std#every-item' >"$WORK/std/every.md" 2>&1
printf 'fn main(gpa: Gpa) -> i32 {\n    let v: Vec<i64> = Vec::new_in(gpa);\n    0\n}\n' >"$WORK/std/main.tach"
if (cd "$WORK/std" && "$COMPILER" query items std --root main.tach) >"$WORK/std/items" 2>&1; then
    # (0.18: the index's signatures leave std's clauses out)
    awk -F '\t' '$3 ~ /^pub / && $3 !~ /^pub mod / { s = $3; sub(/^pub /, "", s); sub(/ (debug )?(requires|ensures) .*$/, "", s); print s }' "$WORK/std/items" >"$WORK/std/want"
    : >"$WORK/std/missing"
    while IFS= read -r sig; do
        grep -qF -- "$sig" "$WORK/std/every.md" || echo "$sig" >>"$WORK/std/missing"
    done <"$WORK/std/want"
    if [ ! -s "$WORK/std/want" ]; then
        result FAIL guide-std "query items std listed no public item"
    elif [ -s "$WORK/std/missing" ]; then
        result FAIL guide-std "std items missing from tachyonc guide std#every-item:" "$(head -5 "$WORK/std/missing")"
    else
        result pass guide-std
    fi
else
    result FAIL guide-std "query items std failed:" "$(cat "$WORK/std/items")"
fi

# (0.17) `guide std` whole is the index: a line per item, the receiver
# as `Self`, no comments, nothing of std's own workings, within about
# 4k tokens (under the 30000 characters an agent's shell shows whole;
# 0.18: 18500 bytes, for the assertions, Arbitrary and Gen, NonNull;
# 0.18.1: 21000, its first page longer and no longer read by default,
# the heaps' section, Vec's sort_by_key, retain, contains, first);
# std#every-item is not in it. (0.18.1) `guide std` alone is its first
# page: the most used names and where the rest is (std#the-api), 4500
# bytes at most (the 0.18 eval's agents read all 18k of it before
# writing a line).
"$COMPILER" guide std >"$WORK/std-page.md" 2>&1
size=$(wc -c <"$WORK/topic-std.md" | tr -d ' ')
page=$(wc -c <"$WORK/std-page.md" | tr -d ' ')
if [ "$size" -le 21000 ] && [ "$page" -le 4500 ] \
    && head -1 "$WORK/std-page.md" | grep -q '^# std$' \
    && grep -q '^## The most used$' "$WORK/std-page.md" \
    && grep -qF 'Vec::new_in(gpa) -> Vec<T>' "$WORK/std-page.md" \
    && grep -qF 'tachyonc guide std#the-api' "$WORK/std-page.md" && grep -qF 'MinHeap::new_in(gpa)' "$WORK/std-page.md" \
    && ! grep -q '^## Overview$' "$WORK/std-page.md" && ! grep -q '@PAGE-END@' "$WORK/std-page.md" "$WORK/topic-std.md" \
    && grep -q '^## Overview$' "$WORK/topic-std.md" && grep -qF 'fn push(self: &mut Self, x: T)' "$WORK/topic-std.md" \
    && grep -qF 'fn split_in<A: Allocator>(s: [u8], sep: u8, a: A) -> Vec<[u8], A>' "$WORK/topic-std.md" \
    && "$COMPILER" guide 'std#the-api' 2>&1 | grep -qF 'fn push(self: &mut Self, x: T)' \
    && ! grep -q '^## Every item' "$WORK/topic-std.md" \
    && ! grep -qF 'fn __' "$WORK/topic-std.md" \
    && ! grep -qF 'live_blocks' "$WORK/topic-std.md" \
    && grep -q '^## Every item with its comment$' "$WORK/std/every.md"; then
    result pass guide-std-index
else
    result FAIL guide-std-index "tachyonc guide std --whole is $size bytes (21000 at most), its first page $page (4500 at most), or not the index (most used first, then std#the-api)"
fi

# The guide by piece (0.15): --find prints the paragraphs about the
# words under `# TOPIC#SECTION`, within its budget; TOPIC#SECTION one
# section; TOPIC# the sections; --budget cuts any of it, with a note.
"$COMPILER" guide --find read a line >"$WORK/find.out" 2>"$WORK/find.err"
rc=$?
if [ $rc -eq 0 ] && head -1 "$WORK/find.out" | grep -q '^# std#input$' \
    && grep -q 'read_line(&mut buf)' "$WORK/find.out" \
    && [ "$(wc -c <"$WORK/find.out" | tr -d ' ')" -le 4000 ]; then
    result pass guide-find
else
    result FAIL guide-find "exit $rc:" "$(head -3 "$WORK/find.out")" "$(cat "$WORK/find.err")"
fi
# (0.16) No paragraph within the budget: the best one's place, and the
# command that prints its section.
"$COMPILER" guide --find read a line --budget 5 >"$WORK/over.out" 2>"$WORK/over.err"
rc=$?
if [ $rc -eq 0 ] && [ "$(cat "$WORK/over.out")" = "# std#input" ] \
    && grep -q '^try: .* guide std#input$' "$WORK/over.err"; then
    result pass guide-find-over
else
    result FAIL guide-find-over "exit $rc:" "$(cat "$WORK/over.out")" "$(cat "$WORK/over.err")"
fi
# (0.17) A word naming a std item: its signature and comment first.
"$COMPILER" guide --find split_in >"$WORK/finditem.out" 2>"$WORK/finditem.err"
rc=$?
if [ $rc -eq 0 ] && head -1 "$WORK/finditem.out" | grep -q '^# std#every-item$' \
    && grep -qF 'fn split_in<A: Allocator>(s: [u8], sep: u8, a: A) -> Vec<[u8], A>' "$WORK/finditem.out" \
    && grep -q '^// The parts of s' "$WORK/finditem.out" \
    && [ "$(wc -c <"$WORK/finditem.out" | tr -d ' ')" -le 4000 ]; then
    result pass guide-find-item
else
    result FAIL guide-find-item "exit $rc:" "$(head -5 "$WORK/finditem.out")" "$(cat "$WORK/finditem.err")"
fi
"$COMPILER" guide --find vec::push >"$WORK/findm.out" 2>&1
if grep -q '^impl<T, A: Allocator> Vec<T, A> {$' "$WORK/findm.out" \
    && grep -qF '    fn push(self: &mut Vec<T, A>, x: T)' "$WORK/findm.out" \
    && ! grep -qF 'fn pop' "$WORK/findm.out"; then
    result pass guide-find-method
else
    result FAIL guide-find-method "$(head -8 "$WORK/findm.out")"
fi
# (0.19) The vendor names and plain words of std::arch land on guide arch.
missed=""
for w in simd neon avx2 intrinsic crc32 popcount 'byte search' sha256; do
    "$COMPILER" guide --find "$w" 2>/dev/null | head -1 >"$WORK/findarch.out"
    grep -q '^# arch#' "$WORK/findarch.out" || missed="$missed '$w' ($(cat "$WORK/findarch.out"))"
done
if [ -z "$missed" ]; then
    result pass guide-find-arch
else
    result FAIL guide-find-arch "not first on guide arch:$missed"
fi
"$COMPILER" guide --find xyzzy frobnicate >"$WORK/nofind.out" 2>&1
rc=$?
if [ $rc -eq 1 ] && grep -q '^error guide.no-match: ' "$WORK/nofind.out"; then
    result pass guide-find-none
else
    result FAIL guide-find-none "exit $rc:" "$(cat "$WORK/nofind.out")"
fi
"$COMPILER" guide 'tools#' >"$WORK/secs.out" 2>&1
"$COMPILER" guide 'tools#the-loop' >"$WORK/sec.out" 2>&1
rc=$?
if [ $rc -eq 0 ] && grep -q '^tools#the-loop$' "$WORK/secs.out" && head -1 "$WORK/sec.out" | grep -q '^## The loop$' \
    && ! grep -q '^## The program' "$WORK/sec.out"; then
    result pass guide-section
else
    result FAIL guide-section "exit $rc:" "$(head -3 "$WORK/sec.out")" "$(head -3 "$WORK/secs.out")"
fi
"$COMPILER" guide 'tools#nothing-like-it' >"$WORK/nosec.out" 2>&1
rc=$?
if [ $rc -eq 1 ] && grep -q '^error guide.no-section: ' "$WORK/nosec.out" \
    && grep -q '^try: .* guide tools#the-loop$' "$WORK/nosec.out"; then
    result pass guide-no-section
else
    result FAIL guide-no-section "exit $rc:" "$(cat "$WORK/nosec.out")"
fi
"$COMPILER" guide core --budget 300 >"$WORK/cut.out" 2>"$WORK/cut.err"
if [ "$(wc -c <"$WORK/cut.out" | tr -d ' ')" -le 1200 ] && grep -q '^note guide.budget: ' "$WORK/cut.err" \
    && grep -q '^try: .* guide core --budget [0-9]*$' "$WORK/cut.err"; then
    result pass guide-budget-cut
else
    result FAIL guide-budget-cut "$(cat "$WORK/cut.err")"
fi

# explain WORDS that are no code: the guide's paragraphs (0.15).
"$COMPILER" explain closure capture >"$WORK/ex.out" 2>"$WORK/ex.err"
rc=$?
if [ $rc -eq 0 ] && grep -q '^note explain.guide: ' "$WORK/ex.err" && grep -q '^# closures#' "$WORK/ex.out"; then
    result pass explain-words
else
    result FAIL explain-words "exit $rc:" "$(cat "$WORK/ex.err")"
fi

# --help on every command (0.15): the command's rows, no error.
for c in "" edit "edit patch" refactor "refactor signature" fix fmt check undo explain try "query context" rewrite lint same-output test probe reduce; do
    # shellcheck disable=SC2086
    if "$COMPILER" $c --help >"$WORK/help.out" 2>&1 && [ -s "$WORK/help.out" ] \
        && [ "$(wc -l <"$WORK/help.out")" -le 15 ] && ! grep -q '^error' "$WORK/help.out"; then
        :
    else
        result FAIL "help-$c" "$(head -3 "$WORK/help.out")"
    fi
done
result pass help

# tachyonc try (0.15): a snippet run with std; its last value and type,
# its output, its errors at the snippet's lines, its exit code.
try_case() { # <name> <expected output> <snippet...>
    n=$1
    want=$2
    shift 2
    got=$("$COMPILER" try "$@" 2>&1)
    if [ "$got" = "$want" ]; then
        result pass "try-$n"
    else
        result FAIL "try-$n" "expected:" "$want" "got:" "$got"
    fi
}
try_case int 'i64 = 3' '1 + 2'
try_case std 'Option<i64> = Some(42)' 'parse_int("42").ok()'
try_case vec 'Vec<i64> = [4, 5]' 'let mut v: Vec<i64> = Vec::new_in(gpa); v.push(4); v.push(5); v'
try_case output "hi
[u8] = \"abc\"" 'println("hi"); "abc"'
try_case item 'i64 = 49' 'fn sq(x: i64) -> i64 { x * x } sq(7)'
try_case tuple '(i64, bool) = (1, true)' '(1, true)'
try_case unit '' 'let x = 3;'
try_case error "snippet:2:5: error[type error] expected 'i64', got '[u8]'" 'let a = 1;
a + "b"'
try_case panic 'snippet:1:37: index out of bounds: index 3, length 0
exit 101' 'let v: Vec<i64> = Vec::new_in(gpa); v.get(3)'
printf 'struct P { x: i64 }\n\nlet p = P { x: 4 };\np.x * 10\n' >"$WORK/snip.tach"
try_case file 'i64 = 40' --file "$WORK/snip.tach"
got=$(printf '7\n' | "$COMPILER" try 'let mut b = Buf::new_in(gpa); read_line(&mut b).unwrap(); parse_int(b.as_slice()).ok()' 2>&1)
if [ "$got" = 'Option<i64> = Some(7)' ]; then result pass try-stdin; else result FAIL try-stdin "$got"; fi
"$COMPILER" try >"$WORK/try.out" 2>&1
rc=$?
if [ $rc -eq 2 ] && grep -q '^error try.usage: ' "$WORK/try.out" && grep -q "^try: .* try 'let v" "$WORK/try.out"; then
    result pass try-usage
else
    result FAIL try-usage "exit $rc:" "$(cat "$WORK/try.out")"
fi

check_blocks
cat "$RESULTS"
grep -q '^FAIL' "$RESULTS" && exit 1
exit 0
