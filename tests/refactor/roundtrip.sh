#!/bin/sh
# The round-trip property of `refactor move` (0.13): items moved to
# another module and back where they were (`--after` the item that was
# before them, or `--before` the one after) leave every file byte for
# byte as it was: their comments and attributes, the blank lines around
# them, the imports and `use` lines of every file. POSIX sh and awk only.
#
# usage: tests/refactor/roundtrip.sh [-c COMPILER] [-n ROUNDS] [-s SEED] [-p PROGRAM]
#
#   -c COMPILER   the volec binary (default: target/volec)
#   -n ROUNDS     the number of round trips (default: 40)
#   -s SEED       the first round's seed (default: 1); round k uses SEED+k
#   -p PROGRAM    the program's directory, with main.vl (default:
#                 tests/refactor/layout)
#
# Each round, in a fresh copy of the program (a git repository of its
# own): one item, or two next to each other, of a random module go to
# another module (at its end, or after or before a random item of it),
# then back; `git diff` must be empty. A move the tools refuse (a name
# taken there) is skipped. Prints `FAIL` lines with the diff, and one
# summary line; exits 1 when a round failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/volec"
ROUNDS=40
SEED=1
PROGRAM="$HERE/layout"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -n) ROUNDS=$2; shift 2 ;;
        -s) SEED=$2; shift 2 ;;
        -p) PROGRAM=$2; shift 2 ;;
        *) echo "usage: tests/refactor/roundtrip.sh [-c COMPILER] [-n ROUNDS] [-s SEED] [-p PROGRAM]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "roundtrip.sh: no compiler at $COMPILER" >&2; exit 2; }
PROGRAM=$(cd "$PROGRAM" && pwd)

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-roundtrip.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
unset VOLE_ROOT

# The modules of the program (but the root), one per line.
modules() {
    "$COMPILER" query items "$PROGRAM/main.vl" | awk -F'\t' '$1 != "crate" { print $1 }'
}

# The top-level items of module $1 in the copy, in order, after a line
# `M MODULE FILE`: `KIND NAME LINE`, KIND `-` for what cannot be named
# for a move (an impl block).
items() {
    "$COMPILER" query items "$1" main.vl | awk -F'\t' 'NR == 1 { print "M", substr($1, 3), $2; next }
        $2 != "method" && $2 != "field" && $2 != "variant" {
        k = $2; t = $3; name = "-"
        if (k == "fn" || k == "const" || k == "static" || k == "struct" || k == "enum" || k == "trait") {
            sub(/^pub /, "", t); sub(/^(fn|const|static mut|static var|static|struct|enum|trait) /, "", t)
            match(t, /^[A-Za-z_][A-Za-z0-9_]*/); name = substr(t, 1, RLENGTH)
        } else { k = "-" }
        print k, name, $1
    }'
}

MODULES=$(modules)
pass=0
fail=0
skip=0
r=0
while [ $r -lt "$ROUNDS" ]; do
    seed=$((SEED + r))
    r=$((r + 1))
    dir="$WORK/$seed"
    cp -R "$PROGRAM" "$dir"
    (cd "$dir" && git init -q . && git -c user.name=t -c user.email=t@t add -A \
        && git -c user.name=t -c user.email=t@t commit -q -m fixture) >/dev/null 2>&1
    cd "$dir" || exit 2
    # The plan: module a, the items, module b and where they go there,
    # where they go back.
    plan=$(for m in $MODULES; do items "$m"; done | awk -v seed="$seed" '
        # Whether a banner heads the group of the item at line l of file f:
        # above its own comment and attribute lines, blank lines, then a
        # comment that is not the file header.
        function banner(f, l,    n, i, s, text, top) {
            n = 0
            while ((getline s < f) > 0) text[++n] = s
            close(f)
            i = l - 1
            while (i > 0 && text[i] ~ /^[ \t]*(\/\/|#\[)/) i--
            if (i < 1 || text[i] !~ /^[ \t]*$/) return 0
            while (i > 0 && text[i] ~ /^[ \t]*$/) i--
            if (i < 1 || text[i] !~ /^[ \t]*\/\//) return 0
            top = i
            while (top > 1 && text[top - 1] ~ /^[ \t]*\/\//) top--
            return top > 1
        }
        $1 == "M" { m = $2; nm++; mod[nm] = m; file[m] = $3; next }
        { cnt[m]++; kind[m, cnt[m]] = $1; name[m, cnt[m]] = $2; line[m, cnt[m]] = $3 }
        END {
            srand(seed)
            for (t = 0; t < 100; t++) {
                a = mod[1 + int(rand() * nm)]
                if (cnt[a] == 0) continue
                i = 1 + int(rand() * cnt[a])
                if (kind[a, i] == "-") continue
                j = i
                # (two of one banner group: one place to put them back)
                if (rand() < 0.3 && i < cnt[a] && kind[a, i + 1] != "-" && !banner(file[a], line[a, i + 1])) j = i + 1
                b = a
                while (b == a) b = mod[1 + int(rand() * nm)]
                break
            }
            if (t == 100) exit
            what = a "::" name[a, i]
            if (j > i) what = what " " a "::" name[a, j]
            # where they go in b
            to = ""
            if (cnt[b] > 0 && rand() < 0.6) {
                k = 1 + int(rand() * cnt[b])
                # (not before the item under a banner: they would head
                # its group, and the banner go back with them)
                before = rand() < 0.5 && !banner(file[b], line[b, k])
                if (kind[b, k] != "-") to = (before ? " --before " : " --after ") name[b, k]
            }
            # where they come back: after the item before, else before the
            # one after (an impl block of a moved struct goes with it)
            # (the first item of a banner group that goes on after it goes
            # back before the next one: the banner stays)
            back = ""
            n = j + 1
            if (n <= cnt[a] && kind[a, n] == "-" && kind[a, j] == "struct") n++
            nb = n <= cnt[a] && kind[a, n] != "-"
            if (nb && banner(file[a], line[a, i]) && !banner(file[a], line[a, n])) back = " --before " name[a, n]
            else if (i > 1 && kind[a, i - 1] != "-") back = " --after " name[a, i - 1]
            else if (nb) back = " --before " name[a, n]
            back_what = b "::" name[a, i]
            if (j > i) back_what = back_what " " b "::" name[a, j]
            print what "|" b to "|" back_what "|" a back
        }')
    if [ -z "$plan" ]; then
        skip=$((skip + 1))
        continue
    fi
    what=${plan%%|*}; rest=${plan#*|}
    to=${rest%%|*}; rest=${rest#*|}
    back_what=${rest%%|*}; back=${rest#*|}
    out1=$(eval "\"\$COMPILER\" refactor move $what --to $to" 2>&1)
    s1=$?
    if [ $s1 -ne 0 ]; then
        case "$out1" in
            *refactor.collision*|*refactor.not-movable*) skip=$((skip + 1)); continue ;;
        esac
        echo "FAIL $seed: refactor move $what --to $to"
        printf '%s\n' "$out1" | sed 's/^/    /'
        fail=$((fail + 1))
        continue
    fi
    out2=$(eval "\"\$COMPILER\" refactor move $back_what --to $back" 2>&1)
    s2=$?
    if [ $s2 -ne 0 ] || ! git diff --quiet; then
        echo "FAIL $seed: refactor move $what --to $to; back: --to $back"
        printf '%s\n' "$out2" | sed 's/^/    /'
        git diff | sed 's/^/    /' | head -40
        fail=$((fail + 1))
        continue
    fi
    pass=$((pass + 1))
done
echo "roundtrip: $pass identical, $fail differ, $skip skipped ($ROUNDS rounds from seed $SEED)"
[ $fail -eq 0 ]
