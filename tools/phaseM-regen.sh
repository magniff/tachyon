#!/bin/sh
# Phase M (0.20): regenerate the tools' transcripts in one command, after
# the compiler-side fixes: tests/refactor, tests/query, tests/lsp and the
# walkthroughs (examples/*/*/README.md) with their runners' -u; then
# tests/guide and tests/fmt, which have no -u, are run and their failures
# listed. POSIX sh, plus python3 for the review filter.
#
# usage: tools/phaseM-regen.sh [-c COMPILER] [--accept-held] [--base REV]
#
#   -c COMPILER     the tachyonc binary (default: target/tachyonc)
#   --accept-held   keep what -u wrote into the HELD files too
#   --base REV      the originals to review against (default: bde11a83,
#                   the corpus before any migration)
#
# HELD (below) are transcripts whose current output is a known bug, not
# a new expectation: -u rewrites them, the script prints that diff and
# puts the committed file back (unless --accept-held). Remove a line
# from HELD once its bug is fixed and its diff reads as spelling.
#
# Then read the diffs before committing: `git diff --stat`, and the file
# $LOG/beyond-spelling.txt, the -/+ lines against REV that differ by more
# than 0.19 -> 0.20 spelling (let mut/var, &mut/&/inout/sink/*, self: T,
# numbers). Spelling, line drift and the new vocabulary are expected;
# anything else is a bug to report, not an expectation to commit.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/tachyonc"
ACCEPT=0
BASE=bde11a83
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        --accept-held) ACCEPT=1; shift ;;
        --base) BASE=$2; shift 2 ;;
        *) echo "usage: tools/phaseM-regen.sh [-c COMPILER] [--accept-held] [--base REV]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
[ -x "$COMPILER" ] || { echo "phaseM-regen: no compiler at $COMPILER" >&2; exit 2; }
cd "$ROOT" || exit 2

# FILE  why it is held
HELD=''

LOG=$(mktemp -d "${TMPDIR:-/tmp}/phaseM-regen.XXXXXX")
echo "phaseM-regen: logs in $LOG"

printf '%s\n' "$HELD" | while read -r f why; do
    [ -f "$f" ] && cp "$f" "$LOG/held.$(echo "$f" | tr / _)"
done

pids=
for t in refactor query lsp walkthrough; do
    "tests/$t/run.sh" -c "$COMPILER" -u >"$LOG/$t.out" 2>&1 &
    pids="$pids $!"
done
for t in guide fmt; do
    "tests/$t/run.sh" -c "$COMPILER" >"$LOG/$t.out" 2>&1 &
    pids="$pids $!"
done
wait $pids

printf '%s\n' "$HELD" | while read -r f why; do
    saved="$LOG/held.$(echo "$f" | tr / _)"
    [ -f "$saved" ] || continue
    if cmp -s "$saved" "$f"; then
        echo "held $f: unchanged ($why)"
    elif [ "$ACCEPT" = 1 ]; then
        echo "held $f: ACCEPTED the new output (--accept-held)"
    else
        echo "held $f: -u would change it; kept ($why); the diff:"
        diff "$saved" "$f" | sed 's/^/    /' | cut -c1-240 | head -40
        cp "$saved" "$f"
    fi
done

for t in refactor query lsp walkthrough guide fmt; do
    n=$(grep -c '^ *FAIL' "$LOG/$t.out")
    echo "$t: $n FAIL lines after the run ($LOG/$t.out)"
    grep '^ *FAIL' "$LOG/$t.out" | cut -c1-160 | sed 's/^/    /' | head -20
done

git diff "$BASE" -- tests/refactor tests/query tests/lsp 'examples/*/*/README.md' | python3 -c '
import re, sys
def norm(s):
    s = s[1:]
    s = re.sub(r"self: &mut \w+(<[^>]*>)?", "self", s)
    s = re.sub(r"self: &?\w+(<[^>]*>)?", "self", s)
    s = re.sub(r"\b(let mut|var|let|inout|sink|move|mut)\b", "", s)
    s = re.sub(r"[&*]", "", s)
    s = re.sub(r"\d+", "N", s)
    return re.sub(r"\s+", "", s)
cur = None; minus = []; plus = []
def flush():
    global minus, plus
    a = [norm(x) for x in minus]; b = [norm(x) for x in plus]
    ra = [x for x, n in zip(minus, a) if n not in b]
    rb = [x for x, n in zip(plus, b) if n not in a]
    if ra or rb:
        print("@@", cur)
        for x in ra + rb: print(x[:300])
    minus = []; plus = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if line.startswith("diff --git"):
        flush(); cur = line.split()[-1]; continue
    if line.startswith(("---", "+++", "index")): continue
    if line.startswith("-"): minus.append(line)
    elif line.startswith("+"): plus.append(line)
    else: flush()
flush()
' >"$LOG/beyond-spelling.txt"
echo "review: git diff --stat; $LOG/beyond-spelling.txt ($(wc -l <"$LOG/beyond-spelling.txt") lines against $BASE)"
git diff --stat | tail -1
