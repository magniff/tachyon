#!/bin/sh
# (0.18.1) Incremental rebuilds give the bytes a clean build gives
# (docs/optimizer.md, "0.18.1: incremental rebuilds"): a program is
# built with the code cache (cold), then edited one function at a time
# and rebuilt with it (warm), and each object must be the one a build
# without the cache makes of the same tree. The compiler's own source is
# one program (EDITS edits), the examples and bench others (4 each), at
# -O1 and -O2, with -j1 and -j8; the edits are seeded and of four kinds,
# each changing what the cache must notice:
#
#   literal  `let x = N;` in a function becomes N + 1: its code;
#   string   a new `let` of a new string before a statement: every later
#            string's and symbol's id moves;
#   line     a comment line: every later function of the file has its
#            checks' positions (their strings) changed;
#   function a new function at the end of a file: every later function's
#            id moves.
#
# Then the tree is put back and built once more (the first build's
# entries, kept). The compiler's source also takes real edits: recent
# commits to compiler/src (git log) of at most 60 changed lines that
# still apply, each undone (git apply -R), built, and redone. The hits are
# counted ($TACHYON_CACHE_TRACE).
#
# usage: tests/incremental.sh [-c COMPILER] [-n EDITS] [-r COMMITS] [-s SEED] [-j JOBS] [FILTER]
#
#   -c COMPILER   the tachyonc to check (default: target/tachyonc)
#   -n EDITS      the compiler's edits (default 10)
#   -r COMMITS    the compiler's real edits, from git (default 6)
#   -s SEED       the edits' seed (default 1)
#   -j JOBS       programs checked at once (default: the number of CPUs,
#                 or the slots of $TACHYON_JOBSERVER, see tests/run.sh)
#   FILTER        only the programs whose path contains FILTER

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/tachyonc"
EDITS=10
COMMITS=6
SEED=1
JOBS=""
FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -n) EDITS=$2; shift 2 ;;
        -r) COMMITS=$2; shift 2 ;;
        -s) SEED=$2; shift 2 ;;
        -j) JOBS=$2; shift 2 ;;
        -h|--help) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
        *) FILTER=$1; shift ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
TARGET=$("$COMPILER" --version | sed 's/.*host: \([a-z0-9_-]*\).*/\1/')
WORK="$ROOT/target/incremental"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$ROOT" || exit 1

# A program's test directives (tests/directives.awk) into directory $2.
case_directives() { # <program> <dir>
    mkdir -p "$2"
    case "$1" in
        examples/*) cd_file=$(grep -l -x "// SOURCE: $1" tests/examples/*.test 2>/dev/null | head -1) ;;
        *) cd_file=$1 ;;
    esac
    [ -n "$cd_file" ] || return 0
    awk -v dir="$2" -v target="$TARGET" -f "$ROOT/tests/directives.awk" "$cd_file"
}

# Edit number $2 (seed $3) of the program in tree $1 (its .tach files);
# prints what it did.
edit() { # <tree> <n> <seed>
    find "$1" -name '*.tach' | sort >"$1.files"
    awk -v n="$2" -v seed="$3" -v list="$1.files" -v tree="$1/" '
        function rnd(m) { state = (state * 1103515245 + 12345) % 2147483648; return int(state / 65536) % m }
        BEGIN {
            state = seed * 7919 + n * 104729
            nf = 0
            nc = 0
            while ((getline f < list) > 0) files[nf++] = f
            kinds[0] = "literal"; kinds[1] = "string"; kinds[2] = "line"; kinds[3] = "function"
            kind = kinds[(n + seed) % 4]
            # the lines an edit of this kind may take, over every file (a
            # literal edit with none is a line edit)
            nl = 0
            for (i = 0; i < nf; i++) {
                ln = 0
                while ((getline line < files[i]) > 0) {
                    ln++
                    if (line ~ /^ +let [a-z_][a-z_0-9]* = [0-9]+;$/) { lf[nl] = i; ll[nl] = ln; nl++ }
                    if (line ~ /^ +let [a-z_]/) { cf[nc] = i; cl[nc] = ln; nc++ }
                }
                close(files[i])
            }
            if (kind == "literal" && nl > 0) {
                nc = nl
                for (i = 0; i < nl; i++) { cf[i] = lf[i]; cl[i] = ll[i] }
            } else if (kind == "literal") {
                kind = "line"
            }
            if (kind == "function") { cf[0] = rnd(nf); cl[0] = -1; nc = 1 }
            if (nc == 0) { print "none"; exit }
            k = rnd(nc)
            file = files[cf[k]]; target = cl[k]
            out = file ".new"
            ln = 0
            while ((getline line < file) > 0) {
                ln++
                if (ln == target) {
                    indent = line; sub(/[^ ].*/, "", indent)
                    if (kind == "literal") {
                        num = line; sub(/.* = /, "", num); sub(/;$/, "", num)
                        sub(/ = [0-9]+;$/, " = " (num + 1) ";", line)
                    } else if (kind == "string") {
                        print indent "let incr_s" n ": [u8] = \"incremental edit " n "\";" > out
                    } else {
                        print indent "// incremental edit " n > out
                    }
                }
                print line > out
            }
            close(file)
            if (kind == "function") print "\nfn incr_f" n "() -> i64 {\n    " n "\n}" > out
            close(out)
            system("mv \"" out "\" \"" file "\"")
            print kind " " substr(file, length(tree) + 1) (target > 0 ? ":" target : "")
        }' </dev/null
}

# Builds program $2 of tree $1 at -O$3 -j$4 into $5 ($6: with the cache
# or not); its flags from directory $7.
build() { # <tree> <root> <level> <threads> <out> <cache> <directives>
    flags=""
    [ -f "$7/flags" ] && flags=$(sed "s|@ROOT@|$ROOT|g" "$7/flags")
    no=""
    [ "$6" = yes ] || no=--no-cache
    # shellcheck disable=SC2086
    (cd "$1" && TACHYON_CACHE="$1.cache" TACHYON_CACHE_SYNC=1 TACHYON_CACHE_TRACE="$1.trace" \
        "$COMPILER" --target "$TARGET" "-O$3" "-j$4" $flags $no -c "$2" -o "$5") >"$5.out" 2>&1
}

# One program at one level and thread count: the cold build, the edits,
# the tree put back.
check() { # <program> <level> <threads> <edits> <n>
    w="$WORK/$5"
    dd="$WORK/directives/$(echo "$1" | tr / _)"
    case "$1" in
        compiler/src/main.tach) src=compiler/src; root=src/main.tach ;;
        */main.tach) src=$(dirname "$1"); root=$(basename "$src")/main.tach ;;
        *) src=$1; root=$(basename "$1") ;;
    esac
    mkdir -p "$w/tree"
    cp -R "$src" "$w/tree/"
    cp -R "$w/tree" "$w/orig"
    what="$1 -O$2 -j$3"
    build "$w/tree" "$root" "$2" "$3" "$w/ref.o" no "$dd"
    if [ ! -f "$w/ref.o" ]; then
        echo "skip $what: it does not build ($(head -1 "$w/ref.o.out"))"
        return
    fi
    build "$w/tree" "$root" "$2" "$3" "$w/cold.o" yes "$dd"
    if ! cmp -s "$w/ref.o" "$w/cold.o"; then
        echo "FAIL $what: the cold build with the cache differs from the build without"
        return
    fi
    i=1
    while [ "$i" -le "$4" ]; do
        e=$(edit "$w/tree" "$i" "$SEED")
        build "$w/tree" "$root" "$2" "$3" "$w/ref.o" no "$dd"
        if [ ! -f "$w/ref.o" ]; then
            echo "skip $what: edit $i ($e) does not build ($(head -1 "$w/ref.o.out"))"
            return
        fi
        build "$w/tree" "$root" "$2" "$3" "$w/warm.o" yes "$dd"
        if ! cmp -s "$w/ref.o" "$w/warm.o"; then
            echo "FAIL $what: after edit $i ($e) the rebuild differs from a clean build; kept in $w"
            return
        fi
        i=$((i + 1))
    done
    rm -rf "$w/tree"
    mv "$w/orig" "$w/tree"
    build "$w/tree" "$root" "$2" "$3" "$w/ref.o" no "$dd"
    build "$w/tree" "$root" "$2" "$3" "$w/warm.o" yes "$dd"
    if ! cmp -s "$w/ref.o" "$w/warm.o"; then
        echo "FAIL $what: the tree put back rebuilds differently; kept in $w"
        return
    fi
    real=0
    if [ "$1" = compiler/src/main.tach ]; then
        for c in $(cat "$WORK/commits" 2>/dev/null); do
            git -C "$ROOT" show "$c" -- compiler/src >"$w/$c.diff"
            (cd "$w/tree" && git apply -R -p2 "$w/$c.diff") 2>/dev/null || continue
            build "$w/tree" "$root" "$2" "$3" "$w/ref.o" no "$dd"
            build "$w/tree" "$root" "$2" "$3" "$w/warm.o" yes "$dd"
            if [ ! -f "$w/ref.o" ] || ! cmp -s "$w/ref.o" "$w/warm.o"; then
                echo "FAIL $what: with commit $c undone the rebuild differs from a clean build; kept in $w"
                return
            fi
            (cd "$w/tree" && git apply -p2 "$w/$c.diff")
            real=$((real + 1))
        done
    fi
    hits=$(awk '$1 == "code" { h += $2; m += $3 } END { print h + 0, m + 0 }' "$w/tree.trace")
    rm -rf "$w"
    echo "ok $what: $4 edits, $real commits undone $hits"
}

list="$WORK/list"
: >"$list"
for f in compiler/src/main.tach examples/*/main.tach bench/*.tach; do
    [ -f "$f" ] || continue
    case "$f" in *"$FILTER"*) ;; *) continue ;; esac
    grep -q '// CSOURCE\|// CHEADER' "$f" && continue
    case "$f" in
        examples/*) grep -l -x "// SOURCE: $f" tests/examples/*.test 2>/dev/null \
            | xargs grep -q '^// CSOURCE' 2>/dev/null && continue ;;
    esac
    case_directives "$f" "$WORK/directives/$(echo "$f" | tr / _)"
    echo "$f" >>"$list"
done
# Recent commits to compiler/src of at most 60 changed lines, which undo
# on the tree as it is (the compiler's real edits).
if [ "$COMMITS" -gt 0 ] && git -C "$ROOT" rev-parse >/dev/null 2>&1; then
    : >"$WORK/commits"
    for c in $(git -C "$ROOT" log --no-merges --format=%h -n 80 -- compiler/src); do
        lines=$(git -C "$ROOT" show --numstat --format= "$c" -- compiler/src | awk '{ n += $1 + $2 } END { print n + 0 }')
        [ "$lines" -gt 0 ] && [ "$lines" -le 60 ] || continue
        git -C "$ROOT" show "$c" -- compiler/src | git -C "$ROOT" apply -R --check 2>/dev/null || continue
        echo "$c" >>"$WORK/commits"
        [ "$(wc -l <"$WORK/commits")" -ge "$COMMITS" ] && break
    done
fi
# The slots (as tests/threads.sh).
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
run() { # <program> <level> <threads> <edits>
    n=$((n + 1))
    read -r _ <&3
    ( check "$1" "$2" "$3" "$4" "$n" >"$WORK/$n.result"; echo >&3 ) &
}
while read -r f; do
    edits=4
    [ "$f" = compiler/src/main.tach ] && edits=$EDITS
    for o in 1 2; do
        for j in 1 8; do
            run "$f" "$o" "$j" "$edits"
        done
    done
done <"$list"
wait
exec 3>&-
i=1
ok=0
failed=0
skipped=0
while [ "$i" -le "$n" ]; do
    if grep -q '^ok' "$WORK/$i.result"; then
        ok=$((ok + 1))
        case "$(cat "$WORK/$i.result")" in "ok compiler/"*) cat "$WORK/$i.result" ;; esac
    elif grep -q '^skip' "$WORK/$i.result"; then
        skipped=$((skipped + 1))
        cat "$WORK/$i.result"
    else
        failed=$((failed + 1))
        cat "$WORK/$i.result"
    fi
    i=$((i + 1))
done
hits=$(cat "$WORK"/*.result | awk '$1 == "ok" { h += $(NF - 1); m += $NF } END { if (h + m > 0) printf "%d%%", 100 * h / (h + m); else print "-" }')
echo "incremental: $ok of $n edit series rebuilt the same as clean builds ($TARGET, hits $hits)$([ $skipped -eq 0 ] || echo ", $skipped skipped")$([ $failed -eq 0 ] || echo ", $failed differ")"
[ $failed -eq 0 ]
