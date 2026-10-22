#!/bin/sh
# The tests of the book (book/*.md): every ```vole block compiles, every
# program shown with its output prints that output, every error shown is
# the error the compiler gives, and every shell session shown prints what
# it says. POSIX sh and awk only. book/STYLE.md explains the annotations
# for the people writing chapters; this is the reference.
#
# usage: tests/book/run.sh [-c COMPILER] [-j JOBS] [-f FILE]
#
#   -c COMPILER   the volec binary (default: target/volec)
#   -j JOBS       units checked at once (default 4)
#   -f FILE       check only this chapter (book/NN-slug.md)
#
# The chapters are book/[0-9][0-9]-*.md. Their fenced blocks, by the
# fence's info string:
#
#   ```vole       a snippet, compiled with --deny-warnings: a program
#                 when a line starts `fn main(`; else items, when every
#                 line at column 0 starts an item, compiled with an
#                 empty main added at the end; else statements, compiled
#                 as the body of `fn main(gpa: Gpa) -> i32` (leading
#                 `use` lines kept above it)
#   ```vole NAME.vl
#                 a file the reader saves, compiled as it is (never
#                 wrapped). Named blocks in a row (prose between them,
#                 no other block) are the files of one program; a name
#                 seen again starts a new program. The root is main.vl
#                 when there is one, else the first file.
#   ```vole ... warn   compiled without --deny-warnings
#   ```vole ... skip   not checked at all (say why in the prose)
#   ```in         stdin for the program of the block before it
#   ```out        after a vole block (and its in block): the program is
#                 run, and its stdout and stderr together are this text,
#                 trailing blanks aside; `out exit=N` (or `out (exit N)`)
#                 expects exit status N, else 0
#   ```err        after a vole block: building it fails (exit status 1)
#                 and the compiler prints exactly this text, in the form a
#                 terminal shows (--diagnostics=human), the file named as
#                 the block names it (main.vl for an unnamed block)
#   ```console    a shell session in a directory holding the files of the
#                 last vole block or program before it (one directory per
#                 program, shared by its sessions, in order; an empty one
#                 when the chapter has no vole block yet). A line `$ CMD`
#                 is run by sh, with `volec` on PATH as a terminal sees it
#                 (a build prints human diagnostics; stdin is empty); the
#                 lines after it are its output (stdout and stderr). A
#                 line `...` stands for any number of lines.
#   other         (sh, text, ...) not checked; `tach` is refused: the
#                 book's fence is `vole`
#
# An HTML comment `<!-- vole-hidden` ... `-->` before a vole block holds
# items appended to that block's file, unseen on the page (a struct the
# snippet uses, defined in an earlier listing).
#
# Prints `pass NAME` or `FAIL NAME` (and why) for each unit, then a
# summary line; exits 1 if one failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/volec"
JOBS=4
ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        -j) [ $# -ge 2 ] || exit 2; JOBS=$2; shift 2 ;;
        -f) [ $# -ge 2 ] || exit 2; ONLY=$2; shift 2 ;;
        *) echo "usage: tests/book/run.sh [-c COMPILER] [-j JOBS] [-f FILE]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "book/run.sh: no compiler at $COMPILER" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-book.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
RESULTS="$WORK/results"
: >"$RESULTS"
mkdir -p "$WORK/units" "$WORK/real" "$WORK/bin"

# `volec` as a reader's shell finds it: the compiler under test, named
# volec (its try: lines print the name it was run by: an err block's
# build is run this way too), with a build's
# diagnostics in the human form a terminal gets (`check` and the other
# subcommands print one line per error in a terminal too).
ln -s "$COMPILER" "$WORK/real/volec"
cat >"$WORK/bin/volec" <<EOF
#!/bin/sh
case "\${1-}" in
    *.vl|-*) PATH="$WORK/real:\$PATH" exec volec --diagnostics=human "\$@" ;;
    *) PATH="$WORK/real:\$PATH" exec volec "\$@" ;;
esac
EOF
chmod +x "$WORK/bin/volec"

# Splits chapter $1 (named $2) into units under $WORK/units: a directory
# per program, holding name, src/ (its files), root, and as given stdin,
# out, exit, err, warn, console-NNN. Problems with the annotations go to
# $WORK/lint.
split_chapter() {
    awk -v chap="$2" -v dir="$WORK/units" -v lint="$WORK/lint" '
        function item_line(l) {
            return l ~ /^(pub |fn |struct |enum |union |impl|trait |const |static |type |use |mod |import |extern |unsafe fn |#\[|}|\/\/|$)/
        }
        function new_unit(line,    d) {
            d = dir "/" chap "-" sprintf("%05d", line)
            system("mkdir -p \"" d "/src\"")
            printf "%s:%d\n", chap, line > (d "/name")
            close(d "/name")
            return d
        }
        function problem(msg) {
            printf "FAIL %s:%d: %s\n", chap, start, msg >> lint
            close(lint)
        }
        function write_body(f, from, to,    i) {
            for (i = from; i <= to; i++) print b[i] > f
        }
        function write_hidden(f,    i) {
            for (i = 1; i <= nhid; i++) print hid[i] > f
            nhid = 0
        }
        {
            line = $0
            if (inhidden) {
                if (line ~ /^-->[ \t]*$/) { inhidden = 0; next }
                hid[++nhid] = line
                next
            }
            if (!infence) {
                if (line ~ /^<!-- vole-hidden[ \t]*$/) { inhidden = 1; nhid = 0; next }
                if (line ~ /^```/) {
                    match(line, /^`+/)
                    marker = substr(line, 1, RLENGTH)
                    info = substr(line, RLENGTH + 1)
                    sub(/^[ \t]+/, "", info)
                    sub(/[ \t]+$/, "", info)
                    infence = 1
                    start = NR
                    nbody = 0
                }
                next
            }
            if (line != marker) { b[++nbody] = line; next }
            infence = 0
            n = split(info, w, /[ \t]+/)
            lang = (n > 0) ? w[1] : ""
            if (lang == "vole") {
                fname = ""; skip = 0; warn = 0
                for (i = 2; i <= n; i++) {
                    if (w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*\.vl$/) fname = w[i]
                    else if (w[i] == "skip") skip = 1
                    else if (w[i] == "warn") warn = 1
                    else problem("unknown annotation `" w[i] "` on a vole block (NAME.vl, warn, skip)")
                }
                if (skip) { pending = ""; row = 0; nhid = 0; nskip++; next }
                if (fname == "") {
                    d = new_unit(start)
                    kind = "items"
                    for (i = 1; i <= nbody; i++) if (b[i] ~ /^fn main\(/) { kind = "program"; break }
                    if (kind != "program")
                        for (i = 1; i <= nbody; i++)
                            if (b[i] !~ /^[ \t]/ && !item_line(b[i])) { kind = "stmts"; break }
                    f = d "/src/main.vl"
                    if (kind == "stmts") {
                        i = 1
                        while (i <= nbody && (b[i] ~ /^(use |import )/ || b[i] ~ /^[ \t]*$/)) { print b[i] > f; i++ }
                        print "fn main(gpa: Gpa) -> i32 {" > f
                        write_body(f, i, nbody)
                        print "0" > f
                        print "}" > f
                    } else {
                        write_body(f, 1, nbody)
                        if (kind == "items") print "fn main() -> i32 { 0 }" > f
                    }
                    write_hidden(f)
                    close(f)
                    printf "main.vl\n" > (d "/root"); close(d "/root")
                    row = 0
                } else {
                    if (!(row && !((proj, fname) in seen))) {
                        proj = new_unit(start)
                        d = proj
                    }
                    d = proj
                    seen[proj, fname] = 1
                    f = d "/src/" fname
                    write_body(f, 1, nbody)
                    write_hidden(f)
                    close(f)
                    if (fname == "main.vl" || !(proj in hasroot)) {
                        printf "%s\n", fname > (d "/root"); close(d "/root")
                        hasroot[proj] = 1
                    }
                    row = 1
                }
                if (warn) { printf "" > (d "/warn"); close(d "/warn") }
                pending = d
                last = d
                nunits++
                next
            }
            row = 0
            if (lang == "in" || lang == "out" || lang == "err") {
                if (pending == "") { problem("a " lang " block with no vole block right before it"); next }
                if (lang == "in") {
                    f = pending "/stdin"
                } else {
                    f = pending "/" lang
                    if (lang == "out") {
                        code = 0
                        if (match(info, /exit[= ][0-9]+/)) code = substr(info, RSTART + 5, RLENGTH - 5) + 0
                        printf "%d\n", code > (pending "/exit"); close(pending "/exit")
                    }
                }
                write_body(f, 1, nbody)
                if (nbody == 0) printf "" > f
                close(f)
                if (lang != "in") pending = ""
                next
            }
            pending = ""
            if (lang == "console") {
                if (last == "") { last = new_unit(start) }
                ncons[last]++
                f = last "/console-" sprintf("%03d", ncons[last])
                write_body(f, 1, nbody)
                close(f)
                printf "%s:%d\n", chap, start > (f ".name"); close(f ".name")
                next
            }
            if (lang ~ /^tach/) problem("the fence is `vole`, not `" lang "`")
        }
        END {
            if (infence) { start = NR; problem("unterminated code block") }
            if (inhidden) { start = NR; problem("unterminated vole-hidden comment") }
            printf "%d %d\n", nunits, nskip >> (dir "/../counts")
        }
    ' "$1"
}

# Without trailing whitespace and carriage returns, and without blank
# lines at the end.
trimmed() {
    awk '{ sub(/[ \t\r]+$/, ""); text = text $0 "\n" } END { sub(/[\n]+$/, "", text); printf "%s", text }' "$1"
}

# Runs `$@` with a watchdog of $1 seconds (shifted off).
with_timeout() {
    t=$1
    shift
    "$@" &
    pid=$!
    (sleep "$t" && kill -9 "$pid" 2>/dev/null) >/dev/null 2>&1 &
    dog=$!
    wait "$pid"
    rc=$?
    kill "$dog" 2>/dev/null
    wait "$dog" 2>/dev/null
    return $rc
}

# Does actual $2 match expected $1, where a line `...` in $1 stands for
# any number of lines?
transcript_matches() {
    awk '
        FNR == NR { e[++ne] = $0; next }
        { a[++na] = $0 }
        function m(i, j,    k) {
            key = i SUBSEP j
            if (key in memo) return memo[key]
            if (i > ne) return memo[key] = (j > na)
            if (e[i] == "...") {
                for (k = j; k <= na + 1; k++) if (m(i + 1, k)) return memo[key] = 1
                return memo[key] = 0
            }
            if (j > na || e[i] != a[j]) return memo[key] = 0
            return memo[key] = m(i + 1, j + 1)
        }
        END { exit !m(1, 1) }
    ' "$1" "$2"
}

# Makes the sh script that replays console block $1 into $2: each `$ CMD`
# line is echoed, then run with stderr joined to stdout; `$?` is the
# previous command's, as at a prompt (`echo $?`).
console_script() {
    {
        echo '__rc=0'
        awk '
            /^\$ / {
                cmd = substr($0, 3)
                shown = $0
                gsub(/\047/, "\047\\\047\047", shown)
                printf "printf \047%%s\\n\047 \047%s\047\n", shown
                printf "(exit $__rc)\n{ %s\n} 2>&1\n__rc=$?\n", cmd
            }
        ' "$1"
    } >"$2"
}

# Checks unit $1; writes its result lines to $1/result.
check_unit() {
    d=$1
    name=$(cat "$d/name")
    : >"$d/result"
    if [ -f "$d/root" ]; then
        rootf=$(cat "$d/root")
        mkdir -p "$d/build"
        cp "$d"/src/* "$d/build/"
        if [ -f "$d/err" ]; then
            (cd "$d/build" && PATH="$WORK/bin:$PATH" volec "$rootf" -o prog) >"$d/compile.out" 2>&1
            rc=$?
            trimmed "$d/compile.out" >"$d/got"
            trimmed "$d/err" >"$d/want"
            if [ $rc -ne 1 ]; then
                { echo "FAIL $name: expected a compile error (exit 1), got exit $rc"; sed 's/^/    /' "$d/compile.out"; } >>"$d/result"
            elif ! cmp -s "$d/got" "$d/want"; then
                { echo "FAIL $name: the compiler's error differs"; echo "    --- the book says"; sed 's/^/    /' "$d/want"; echo
                  echo "    --- volec prints"; sed 's/^/    /' "$d/got"; echo; } >>"$d/result"
            else
                echo "pass $name" >>"$d/result"
            fi
        else
            deny="--deny-warnings"
            [ -f "$d/warn" ] && deny=""
            # shellcheck disable=SC2086
            if ! (cd "$d/build" && "$COMPILER" $deny --diagnostics=short "$rootf" -o prog) >"$d/compile.out" 2>&1; then
                { echo "FAIL $name: does not compile"; sed 's/^/    /' "$d/compile.out"; } >>"$d/result"
            elif [ -f "$d/out" ]; then
                [ -f "$d/stdin" ] || : >"$d/stdin"
                (cd "$d/build" && with_timeout 20 sh -c './prog <../stdin >run.out 2>&1')
                rc=$?
                trimmed "$d/build/run.out" >"$d/got"
                trimmed "$d/out" >"$d/want"
                want_rc=$(cat "$d/exit")
                if ! cmp -s "$d/got" "$d/want"; then
                    { echo "FAIL $name: output differs"; echo "    --- the book says"; sed 's/^/    /' "$d/want"; echo
                      echo "    --- it prints"; sed 's/^/    /' "$d/got"; echo; } >>"$d/result"
                elif [ "$rc" -ne "$want_rc" ]; then
                    echo "FAIL $name: exit status $rc, the book says $want_rc" >>"$d/result"
                else
                    echo "pass $name" >>"$d/result"
                fi
            else
                echo "pass $name" >>"$d/result"
            fi
        fi
    fi
    for c in "$d"/console-[0-9][0-9][0-9]; do
        [ -f "$c" ] || continue
        cname=$(cat "$c.name")
        if [ ! -d "$d/sess" ]; then
            mkdir -p "$d/sess"
            for s in "$d"/src/*; do [ -f "$s" ] && cp "$s" "$d/sess/"; done
        fi
        console_script "$c" "$c.sh"
        (cd "$d/sess" && PATH="$WORK/bin:$PATH" with_timeout 120 sh "$c.sh" </dev/null >"$c.got" 2>&1)
        trimmed "$c.got" >"$c.got.t"
        trimmed "$c" >"$c.want"
        if transcript_matches "$c.want" "$c.got.t"; then
            echo "pass $cname" >>"$d/result"
        else
            { echo "FAIL $cname: the session differs"; echo "    --- the book says"; sed 's/^/    /' "$c.want"; echo
              echo "    --- the shell prints"; sed 's/^/    /' "$c.got.t"; echo; } >>"$d/result"
        fi
    done
}

if [ -n "$ONLY" ]; then
    CHAPTERS=$ONLY
else
    CHAPTERS=$(ls "$ROOT"/book/[0-9][0-9]-*.md 2>/dev/null)
fi
: >"$WORK/lint"
: >"$WORK/counts"
for ch in $CHAPTERS; do
    [ -f "$ch" ] || { echo "FAIL $ch: no such chapter" >>"$WORK/lint"; continue; }
    split_chapter "$ch" "$(basename "$ch" .md)"
done

# The table of contents (book/README.md) links every chapter, and every
# chapter it links exists.
if [ -z "$ONLY" ]; then
    toc="$ROOT/book/README.md"
    for ch in $CHAPTERS; do
        b=$(basename "$ch")
        grep -qF "]($b)" "$toc" || echo "FAIL book-toc: book/README.md does not link $b" >>"$WORK/lint"
    done
    grep -o '](\([0-9][0-9]-[a-z0-9-]*\.md\))' "$toc" | sed 's/^](//; s/)$//' | while IFS= read -r l; do
        [ -f "$ROOT/book/$l" ] || echo "FAIL book-toc: book/README.md links $l, which does not exist"
    done >>"$WORK/lint"
fi

i=0
for d in "$WORK"/units/*/; do
    [ -d "$d" ] || continue
    check_unit "${d%/}" &
    i=$((i + 1))
    if [ $((i % JOBS)) -eq 0 ]; then wait; fi
done
wait
cat "$WORK/lint" >>"$RESULTS"
for d in "$WORK"/units/*/; do
    [ -f "$d/result" ] && cat "$d/result" >>"$RESULTS"
done
cat "$RESULTS"
awk '{ u += $1; s += $2 } END { printf "book: %d blocks checked, %d skipped\n", u, s }' "$WORK/counts"
awk '/^pass/ { p++ } /^FAIL/ { f++ } END { printf "book: %d passed, %d failed\n", p, f }' "$RESULTS"
grep -q '^FAIL' "$RESULTS" && exit 1
exit 0
