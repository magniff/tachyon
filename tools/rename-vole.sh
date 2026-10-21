#!/bin/sh
# 0.24's rename, tachyon to vole, done by the compiler's tools in one
# scripted, checked run (docs/refactor.md, "Renaming the language"):
#
#   1. the sources: every .tach file git tracks becomes .vl (refactor
#      extension --all: git mv, the mentions of their paths in every file,
#      each program compiled before and after: the same build);
#   2. the code: an identifier with `tachyon` in it would be renamed with
#      refactor rename (there is none: this step stops when one appears);
#   3. the sources' strings and comments: tachyonc to volec, tachyon to
#      vole (any case: TACHYON_ROOT is VOLE_ROOT, _tachyon. is _vole.),
#      .tach to .vl in string literals (rewrite --text --strings
#      --comments, the compiler checked: --check); the code of the tests,
#      examples, benchmarks and tools (the extern names C files share);
#   4. every other file (md, sh, py, toml, json, yml, transcripts): the
#      same words (rewrite --text --no-sources), [head]'s interface first,
#      paths with the name moved (--move-paths);
#   5. the sources laid out again (fmt --all: the lines the words made
#      shorter or longer), the generated ones made again: std's text,
#      the guide's;
#   6. the renamed compiler built (target/volec) and checked; with --test,
#      its suite; with --regen, the transcripts regenerated first;
#   7. what is left: `git grep -i tachyon`, counted by file
#      (target/rename-vole/leftovers.txt).
#
# Kept (tools/rename-vole.keep): the seed, the records of past releases and
# evals, the release notes and the bootstrap entries of the releases up to
# 0.23 (they are tachyonc and .tach, and bootstrap.sh builds them so).
#
# usage: tools/rename-vole.sh [-c COMPILER] [--dry-run] [--test] [--regen] [--force]
#
#   -c COMPILER  the compiler whose tools do it (default target/tools/tachyonc);
#                it must read .vl (0.21 on)
#   --dry-run    each step's plan (the tools' --dry-run); nothing changes
#   --test       after the build, the suite (tests/run.sh) with target/volec
#   --regen      before the suite, the transcripts made again (refactor's,
#                query's, the walkthroughs': -u); review their diff
#   --force      run in a tree with changes (else it must be clean)
#
# Each step is one edit of the journal: `tachyonc undo` (`volec undo` after
# step 6) takes the last one back.

set -u
# (no globbing: the tools take globs as words)
set -f
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 2
C=target/tools/tachyonc
DRY=""
TEST=0
REGEN=0
FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || { echo "rename-vole: -c needs a compiler" >&2; exit 2; }; C=$2; shift ;;
        --dry-run) DRY=--dry-run ;;
        --test) TEST=1 ;;
        --regen) REGEN=1 ;;
        --force) FORCE=1 ;;
        -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "rename-vole: unknown option '$1' (see --help)" >&2; exit 2 ;;
    esac
    shift
done
case "$C" in /*) ;; *) C="$ROOT/$C" ;; esac
[ -x "$C" ] || { echo "rename-vole: no compiler at $C (bootstrap/bootstrap.sh --dev builds it)" >&2; exit 2; }
# (a copy: the steps rewrite the tree, never the compiler doing it)
OUT="$ROOT/target/rename-vole"
mkdir -p "$OUT"
cp "$C" "$OUT/tools-compiler"
C="$OUT/tools-compiler"
KEEP=tools/rename-vole.keep
# (the generated sources: not rewritten, made again in step 5)
GEN="--exclude compiler/src/front/stdsrc.* --exclude compiler/src/guide/text/*"
if [ $FORCE -eq 0 ] && [ -z "$DRY" ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "rename-vole: the tree has changes; commit them first (or --force)" >&2
    exit 2
fi

step() {
    echo "==> $*" >&2
}
# Runs a tool's command; stops the rename when it fails.
run() {
    echo "\$ tachyonc $*" >&2
    "$C" "$@"
    st=$?
    if [ $st -ne 0 ]; then
        echo "rename-vole: the step failed (exit $st); the steps before it stay (tachyonc undo takes one back)" >&2
        exit 1
    fi
}

# After step 1 the compiler's root is main.vl (in a dry run, still .tach).
if [ -n "$DRY" ] || [ -f compiler/src/main.vl ]; then
    MAIN=compiler/src/main.tach
    [ -f compiler/src/main.vl ] && MAIN=compiler/src/main.vl
else
    MAIN=compiler/src/main.vl
fi

step "1. the sources: .tach to .vl"
if [ -f compiler/src/main.tach ]; then
    run refactor extension .tach .vl --all --exclude-from "$KEEP" $DRY
else
    echo "(done before: compiler/src/main.vl)" >&2
fi
[ -n "$DRY" ] || MAIN=compiler/src/main.vl

step "2. the code: identifiers with tachyon in them"
"$C" query grep --code --ignore-case tachyon --root "$MAIN" --all >"$OUT/identifiers.txt" 2>&1
if grep -q '	code	' "$OUT/identifiers.txt"; then
    cat "$OUT/identifiers.txt" >&2
    echo "rename-vole: identifiers have the old name: rename them (tachyonc refactor rename OLD NEW), then run this again" >&2
    exit 1
fi
echo "(none)" >&2

step "3. the sources' strings and comments"
# shellcheck disable=SC2086
run rewrite --text tachyonc volec --word --case --strings --comments --move-paths \
    --exclude-from "$KEEP" $GEN --check "$MAIN" $DRY
# shellcheck disable=SC2086
run rewrite --text tachyon vole --word --case --strings --comments --move-paths \
    --exclude-from "$KEEP" $GEN --check "$MAIN" $DRY
# shellcheck disable=SC2086
run rewrite --text .tach .vl --word --strings --exclude-from "$KEEP" $GEN --check "$MAIN" $DRY
# (the code of the tests, examples, benchmarks and tools: extern names
# their C files share, `tachyon_take_a64`, which step 4 renames there;
# compiler/src has none, step 2)
for w in tachyonc:volec tachyon:vole; do
    # shellcheck disable=SC2086
    run rewrite --text "${w%%:*}" "${w##*:}" --word --case --code --files 'tests/*' --files 'examples/*' \
        --files 'bench/*' --files 'tools/*' --exclude-from "$KEEP" $DRY
done

step "4. every other file"
# ([head]'s interface: tachyonc-0.10's, named volec-0.24)
run rewrite --text 'cli = "tachyonc-0.10"' 'cli = "volec-0.24"' --files bootstrap/releases.toml \
    --exclude 'bootstrap/releases.toml:/^\[seed\]/,/^# HEAD/' $DRY
# shellcheck disable=SC2086
run rewrite --text tachyonc volec --word --case --no-sources --move-paths --exclude-from "$KEEP" $GEN $DRY
# shellcheck disable=SC2086
run rewrite --text tachyon vole --word --case --no-sources --move-paths --exclude-from "$KEEP" $GEN $DRY

if [ -n "$DRY" ]; then
    step "5-7: not in a dry run (the generated sources, the build, the leftovers)"
    exit 0
fi

step "5. the sources laid out again, the generated ones made again"
# (a line the words made shorter or longer: fmt lays it out as it would)
run fmt --all

sh compiler/std/embed.sh || { echo "rename-vole: compiler/std/embed.sh failed" >&2; exit 1; }
sh compiler/guide/embed.sh || { echo "rename-vole: compiler/guide/embed.sh failed" >&2; exit 1; }

step "6. the renamed compiler"
"$C" compiler/src/main.vl -o target/volec || { echo "rename-vole: the renamed compiler does not build" >&2; exit 1; }
target/volec check compiler/src/main.vl || { echo "rename-vole: volec's check of itself fails" >&2; exit 1; }
# (the fixpoint: built by itself, then by that, the same object)
target/volec compiler/src/main.vl -o "$OUT/volec2.o" && cc -o "$OUT/volec2" "$OUT/volec2.o" -lm \
    && "$OUT/volec2" compiler/src/main.vl -o "$OUT/volec3.o" && cmp -s "$OUT/volec2.o" "$OUT/volec3.o" \
    || { echo "rename-vole: volec reaches no fixpoint (built by itself twice, the objects differ)" >&2; exit 1; }
if [ $REGEN -eq 1 ]; then
    sh tests/refactor/run.sh -c target/volec -u >"$OUT/regen-refactor.log" 2>&1
    sh tests/query/run.sh -c target/volec -u >"$OUT/regen-query.log" 2>&1
    sh tests/walkthrough/run.sh -c target/volec -u >"$OUT/regen-walkthrough.log" 2>&1
    echo "(transcripts regenerated: review git diff -- tests/refactor tests/query examples)" >&2
fi
if [ $TEST -eq 1 ]; then
    sh tests/run.sh -c target/volec >"$OUT/tests.log" 2>&1
    tail -3 "$OUT/tests.log" >&2
fi

step "7. what is left"
git grep -I -i -c tachyon -- . ':!seed' >"$OUT/leftovers.txt" 2>/dev/null
git grep -I -i -c tachyon -- seed | awk -F: '{ n += $2 } END { if (n) print "seed/ (kept): " n " lines" }' >&2
awk -F: '{ n += $NF } END { print NR " files, " n " lines with tachyon (target/rename-vole/leftovers.txt)" }' "$OUT/leftovers.txt" >&2
exit 0
