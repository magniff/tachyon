#!/bin/sh
# The tests of the refactoring tools (0.11): tachyonc edit, undo, check,
# fix, lint, same-output and the planning queries (query stats, deps,
# unused, impact). POSIX sh and awk only.
#
# usage: tests/refactor/run.sh [-c COMPILER] [-u]
#
#   -c COMPILER   the tachyonc binary (default: target/tachyonc)
#   -u            rewrite the .t files with the output they get now
#
# Each tests/refactor/NAME.t is a transcript run in a fresh copy of the
# program tests/refactor/NAME/ (a git repository of its own, so that
# edits are journaled for undo; plain*.t: a directory that is none):
#   $ ARGS    runs `tachyonc ARGS` there (ARGS are evaluated by the shell:
#             `< $T/inputs/x.tach` gives stdin from tests/refactor/inputs)
#   % CMD     runs shell command CMD there (`cat geom.tach`, to see what
#             an edit wrote)
# the lines after it, up to the next `$` or `%` line, are its output:
# stdout, then stderr, then `[exit N]` when N is not 0. The compiler's
# path is written `tachyonc`, the copy's `WORK`. Lines starting with `##`
# are comments. A test passes when the transcript it makes is the file,
# comments aside.
#
# Then the compiler's own source is asked for its stats, deps, unused
# items and lint, which must be plausible, and same-output compares the
# compiler with itself (identical) and with a copy that differs.
#
# Prints `pass NAME` or `FAIL NAME` (and why) for each test; exits 1 if
# one failed.

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
        *) echo "usage: tests/refactor/run.sh [-c COMPILER] [-u]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "refactor/run.sh: no compiler at $COMPILER" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-refactor.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
STATUS=0
T=$HERE
export T
unset TACHYON_ROOT

# The transcript of test file $1, run in a copy of its program, on stdout;
# (0.13) with $2 `off`, without the tools' cache, with `cache`, with a
# cache of its own (the queries and checks after each edit see the files
# changed under it).
transcript() {
    name=$(basename "$1" .t)
    if [ "$2" = off ]; then
        TACHYON_CACHE=off
    else
        TACHYON_CACHE="$WORK/cache-$name"
    fi
    export TACHYON_CACHE
    dir="$WORK/$name"
    rm -rf "$dir"
    mkdir -p "$dir"
    [ -d "$HERE/$name" ] && cp -R "$HERE/$name/." "$dir/"
    # (0.14: plain*.t run in a directory that is no git checkout, as a
    # user's program may be: the journal is then .tachyonc/edits)
    case "$name" in
        plain*) ;;
        *) (cd "$dir" && git init -q . && git -c user.name=t -c user.email=t@t add -A \
            && git -c user.name=t -c user.email=t@t commit -q -m fixture) >/dev/null 2>&1 ;;
    esac
    grep -E '^[$%] ' "$1" | while IFS= read -r line; do
        printf '%s\n' "$line"
        args=${line#? }
        (
            cd "$dir" || exit 1
            case "$line" in
                \$*) eval "\"\$COMPILER\" $args" >"$WORK/out" 2>"$WORK/err" </dev/null ;;
                *) eval "$args" >"$WORK/out" 2>"$WORK/err" </dev/null ;;
            esac
            rc=$?
            cat "$WORK/out" "$WORK/err" | sed -e "s|$COMPILER|tachyonc|g" -e "s|$dir|WORK|g" -e "s|$WORK|WORK|g"
            [ $rc -eq 0 ] || echo "[exit $rc]"
        )
    done
}

for file in "$HERE"/*.t; do
    [ -f "$file" ] || continue
    name=$(basename "$file" .t)
    for mode in off cache; do
    transcript "$file" $mode >"$WORK/$name.got"
    if [ $UPDATE -eq 1 ] && [ $mode = off ]; then
        # (each comment stays before the command it was before)
        awk 'NR == FNR {
                if ($0 ~ /^##/) { pending = pending $0 "\n" }
                else if ($0 ~ /^[$%] /) { before[++n] = pending; pending = "" }
                next
            }
            /^[$%] / { printf "%s", before[++k] }
            { print }
            END { printf "%s", pending }' "$file" "$WORK/$name.got" >"$WORK/$name.new"
        cp "$WORK/$name.new" "$file"
    fi
    grep -v '^##' "$file" >"$WORK/$name.want"
    if cmp -s "$WORK/$name.want" "$WORK/$name.got"; then
        echo "pass $name ($mode)"
    else
        echo "FAIL $name ($mode): the transcript differs (< expected, > got):"
        diff "$WORK/$name.want" "$WORK/$name.got" | sed 's/^/    /' | head -40
        STATUS=1
    fi
    done
done
unset TACHYON_CACHE

# The compiler's own source.
check() { # <name> <condition> <output>
    if [ "$2" = 1 ]; then
        echo "pass $1"
    else
        echo "FAIL $1:"
        printf '%s\n' "$3" | head -20 | sed 's/^/    /'
        STATUS=1
    fi
}
cd "$ROOT" || exit 2
TAB=$(printf '\t')
# stats: every file of the compiler, largest first (the largest over 300
# lines), a total.
out=$("$COMPILER" query stats --over 300 2>&1)
ok=0
n=$(printf '%s\n' "$out" | grep -c "^[0-9]*${TAB}[0-9]*${TAB}compiler/src/[a-z_0-9/]*\.tach")
[ "$n" -ge 40 ] && printf '%s\n' "$out" | head -1 | grep -q "^[0-9]*${TAB}[0-9]*${TAB}compiler/src/[a-z_0-9/]*\.tach${TAB}over\$" \
    && printf '%s\n' "$out" | grep -q "^[0-9]*${TAB}[0-9]*${TAB}total\$" \
    && printf '%s\n' "$out" | grep -q '^note query.over: [0-9]* files over 300 lines$' && ok=1
check self_stats "$ok" "$(printf '%s\n' "$out" | head -8)"
out=$("$COMPILER" query stats gvn 2>&1)
ok=0
printf '%s\n' "$out" | head -1 | grep -q "^# crate::middle::gvn${TAB}compiler/src/middle/gvn.tach${TAB}[0-9]* lines${TAB}[0-9]* items\$" \
    && printf '%s\n' "$out" | grep -q "^[0-9]*${TAB}fn${TAB}run_gvn\$" && ok=1
check self_stats_module "$ok" "$(printf '%s\n' "$out" | head -5)"
# deps: every item of a module, and groups of at most N lines, each at
# most N lines unless one item is larger.
out=$("$COMPILER" query deps check --max-lines 60 2>&1)
ok=0
items=$(printf '%s\n' "$out" | head -1 | sed -n "s/.*${TAB}\([0-9]*\) items\$/\1/p")
rows=$(printf '%s\n' "$out" | grep -v "^groups${TAB}" | grep -c "^[A-Za-z_][A-Za-z_0-9:]*${TAB}[0-9]*${TAB}")
groups=$(printf '%s\n' "$out" | grep -c "^group [0-9]*${TAB}")
big=$(printf '%s\n' "$out" | awk -F "$TAB" '/^group / && $2 > 60 && $4 != "over"' | wc -l | tr -d ' ')
[ -n "$items" ] && [ "$rows" = "$items" ] && [ "$groups" -ge 5 ] && [ "$big" = 0 ] \
    && printf '%s\n' "$out" | grep -q "^check_program${TAB}" \
    && printf '%s\n' "$out" | grep -q "^groups${TAB}[0-9]*${TAB}at most 60 lines${TAB}[0-9]* references between them\$" && ok=1
check self_deps "$ok" "$(printf '%s\n' "$out" | head -3; printf '%s\n' "$out" | grep '^groups')"
# unused: something, by file, and every listed definition really has no
# reference; or (0.12, after the clean-up) nothing.
out=$("$COMPILER" query unused --all 2>&1)
ok=0
[ "$out" = "note query.empty: nothing unused" ] && ok=1
n=$(printf '%s\n' "$out" | grep -c "${TAB}compiler/src/[a-z_0-9/]*\.tach:[0-9]*:[0-9]*${TAB}")
first=$(printf '%s\n' "$out" | grep "${TAB}fn\$" | head -1 | cut -f1)
[ "$n" -ge 1 ] && [ -n "$first" ] && [ "$("$COMPILER" query refs --count "$first" 2>/dev/null)" = 1 ] \
    && ! printf '%s\n' "$out" | grep -q "^crate::main${TAB}" && ok=1
check self_unused "$ok" "$(printf '%s\n' "$out" | head -5)"
# impact: the calls of a function used in several files.
out=$("$COMPILER" query impact base::grow 2>&1)
ok=0
printf '%s\n' "$out" | head -1 | grep -q "^crate::base::grow${TAB}compiler/src/base/mod.tach:" \
    && printf '%s\n' "$out" | grep -q "^instances${TAB}[0-9]*${TAB}grow<" \
    && printf '%s\n' "$out" | grep -q "^total${TAB}[0-9]*${TAB}[0-9]*${TAB}[0-9]* files" && ok=1
check self_impact "$ok" "$(printf '%s\n' "$out" | head -3)"
# lint: the files over 300 lines, each with the deps of its module.
out=$("$COMPILER" lint --max-lines 300 2>&1)
rc=$?
ok=0
[ $rc = 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^error lint.max-lines: compiler/src/[a-z_0-9/]*\.tach: [0-9]* lines (at most 300)$' \
    && printf '%s\n' "$out" | grep -q "^try: .* query deps crate::[a-z_0-9:]* --max-lines 300\$" && ok=1
check self_lint "$ok" "$(printf '%s\n' "$out" | head -4)"
"$COMPILER" lint --max-lines 100000 >/dev/null 2>&1
check self_lint_ok "$([ $? = 0 ] && echo 1)" "lint --max-lines 100000 failed"
# check: the compiler's source has no errors, quickly.
"$COMPILER" check compiler/src/main.tach >"$WORK/check.out" 2>&1
check self_check "$([ $? = 0 ] && [ ! -s "$WORK/check.out" ] && echo 1)" "$(cat "$WORK/check.out")"
# same-output: the compiler against a copy of itself (identical), and
# against a wrapper that changes one compilation (different).
cp "$COMPILER" "$WORK/old-tachyonc"
out=$("$COMPILER" same-output "$WORK/old-tachyonc" --corpus examples --corpus tests/refactor/edits --work "$WORK/so" 2>&1)
ok=0
printf '%s\n' "$out" | grep -q "^identical${TAB}[0-9]* compilations${TAB}[0-9]* programs${TAB}[0-9]* targets${TAB}-O0 -O1 -O2\$" && ok=1
check same_output_identical "$ok" "$out"
# (0.16) OLD named without a `/`: looked up in $PATH.
out=$(PATH="$WORK:$PATH" "$COMPILER" same-output old-tachyonc --corpus tests/refactor/edits --work "$WORK/so-path" 2>&1)
ok=0
printf '%s\n' "$out" | grep -q "^identical${TAB}" && ok=1
check same_output_in_path "$ok" "$out"
cat >"$WORK/differs.sh" <<EOS
#!/bin/sh
# tachyonc, but its assembly for md5/main.tach at -O1 has one more line
"$WORK/old-tachyonc" "\$@"
st=\$?
out=
prev=
for a in "\$@"; do [ "\$prev" = -o ] && out=\$a; prev=\$a; done
case "\$*" in *-O1*md5/main.tach*) printf '\t// differs\n' >>"\$out" ;; esac
exit \$st
EOS
chmod +x "$WORK/differs.sh"
out=$("$COMPILER" same-output "$WORK/differs.sh" --corpus examples --work "$WORK/so2" 2>&1)
rc=$?
ok=0
[ $rc = 1 ] && printf '%s\n' "$out" | head -1 | grep -q "^examples/md5/main.tach${TAB}[a-z0-9_-]*${TAB}-O1${TAB}asm line [0-9]*\$" \
    && printf '%s\n' "$out" | grep -q "^-${TAB}${TAB}// differs\$" \
    && printf '%s\n' "$out" | grep -q '^error same-output.differs: [0-9]* of [0-9]* compilations differ' \
    && printf '%s\n' "$out" | grep -q '^try: diff .*/old/out.s .*/new/out.s$' && ok=1
check same_output_differs "$ok" "$out"
# (0.13) items moved to another module and back: every file as it was.
out=$(sh "$HERE/roundtrip.sh" -c "$COMPILER" -n 40 2>&1)
check roundtrip "$([ $? = 0 ] && echo 1)" "$out"
# (0.15) A module path without `crate::`, as a user writes it: made,
# then an item moved to it.
mkdir -p "$WORK/nocrate"
printf 'fn helper() -> i64 {\n    2\n}\n\nfn main() -> i32 {\n    (helper() - 2) as i32\n}\n' >"$WORK/nocrate/main.tach"
out=$(cd "$WORK/nocrate" && git init -q . 2>/dev/null; "$COMPILER" refactor new-module report 2>&1 \
    && "$COMPILER" refactor move helper --to report 2>&1 && "$COMPILER" query def report::helper 2>&1)
ok=0
printf '%s\n' "$out" | grep -q '^made module report' \
    && printf '%s\n' "$out" | grep -q "^crate::report::helper${TAB}report.tach:1:8${TAB}" && ok=1
check module_path_without_crate "$ok" "$out"
# explain (0.13): every code the compiler's source can print has an
# entry: the tools' codes (`c"query.no-match"`; 0.17: the own pass's,
# `c"own.moved"`), the kinds of the
# compiler's errors (ERR_KIND) and warnings and keyed errors (their
# third argument); and every entry is such a code.
{
    grep -rhoE 'c"(query|edit|patch|undo|check|fix|lint|fmt|same-output|refactor|rewrite|explain|batch|conflict|try|test|probe|reduce|own|fuzz)\.[a-z0-9_-]+"' \
        compiler/src
    grep -rhoE 'ERR_KIND = c"[^"]*"' compiler/src
    grep -rhoE 'report_(warning|error_once)\([^,]*, [^,]*, c"[^"]*"' compiler/src
    # (0.15: guide's codes, written into its own messages)
    grep -rhoE '"(error|note) guide\.[a-z-]+' compiler/src | sed -e 's/^"[a-z]* \(.*\)$/c"\1"/'
} | sed -e 's/.*c"\([^"]*\)"$/\1/' | sort -u >"$WORK/codes"
"$COMPILER" explain --list | sort >"$WORK/explained"
missing=$(comm -23 "$WORK/codes" "$WORK/explained")
extra=$(comm -13 "$WORK/codes" "$WORK/explained")
bad=
while IFS= read -r code; do
    "$COMPILER" explain "$code" >"$WORK/explain.out" 2>&1 \
        && [ "$(sed -n 1p "$WORK/explain.out")" != "" ] && grep -q '^fix: ' "$WORK/explain.out" \
        && grep -q '^example:$' "$WORK/explain.out" || bad="$bad $code"
done <"$WORK/codes"
check self_explain "$([ "$(wc -l <"$WORK/codes")" -ge 90 ] && [ -z "$missing$extra$bad" ] && echo 1)" \
    "$(wc -l <"$WORK/codes") codes; no entry:$(echo $missing); not a code:$(echo $extra); bad:$bad"
# The own pass (0.17, front/own): compiler/src walks clean under
# --values=report (the default only walks when its findings are printed).
out=$(TACHYON_CACHE="$WORK/owncache" "$COMPILER" check --values=report compiler/src/main.tach 2>&1)
check own_report_compiler "$(printf '%s\n' "$out" | grep -q '^own: 0 findings' && echo 1)" "$out"
exit $STATUS
