#!/bin/sh
# The prompts of the guide-mini and guide-example conditions render: a
# dry run (no model) of one program task in each, with the compiler under
# test, and the checks of what each prompt.md holds. guide-example's has
# `volec guide example` in place of @EXAMPLE@ (its three files and its
# test case), not guide-mini's one-file example; guide-mini's is as before.
#
# usage: tests/agent-eval/check-prompts.sh [-c COMPILER]   (default target/volec)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/volec"
if [ "${1:-}" = "-c" ] && [ $# -ge 2 ]; then COMPILER=$2; fi
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
[ -x "$COMPILER" ] || { echo "check-prompts: no compiler at $COMPILER" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/eval-prompts.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
STATUS=0
fail() { echo "FAIL $*"; STATUS=1; }

"$HERE/run.py" run --dry-run --model claude:haiku --set programs --tasks 01-wordfreq \
    --cond guide-example+readfirst,guide-mini+readfirst --reps 1 --selfcheck none \
    --volec "$COMPILER" --out "$WORK/out" --ws-root "$WORK/ws" >"$WORK/log" 2>&1 \
    || { fail "the dry run failed:"; sed 's/^/    /' "$WORK/log"; exit 1; }

ex="$WORK/out/01-wordfreq/claude-haiku/guide-example+readfirst/rep1/prompt.md"
mini="$WORK/out/01-wordfreq/claude-haiku/guide-mini+readfirst/rep1/prompt.md"
for f in "$ex" "$mini"; do [ -s "$f" ] || fail "no prompt.md: $f"; done
[ $STATUS -eq 0 ] || exit 1

# guide-example: the program, whole, where @EXAMPLE@ was; the lookup
# lines; readfirst; the task
"$COMPILER" guide example >"$WORK/example.md" 2>&1
if ! grep -q '^# vole by example$' "$ex"; then fail "guide-example: no intro"; fi
if grep -q '@EXAMPLE@\|placeholder' "$ex"; then fail "guide-example: @EXAMPLE@ not replaced"; fi
for want in '```tach main.vl' '```tach command.vl' '```tach store.vl' \
    'fn main(gpa: Gpa) -> i32 {' 'total 129' 'volec guide --find NAME' \
    'Read the code in the directory' '# Word frequencies'; do
    grep -qF -- "$want" "$ex" || fail "guide-example: no line with: $want"
done
# the topic, line for line, is in the prompt
awk 'NR == FNR { want[++n] = $0; next } { have[$0] = 1 }
     END { for (i = 1; i <= n; i++) if (!(want[i] in have)) { print want[i]; exit 1 } }' \
    "$WORK/example.md" "$ex" >"$WORK/missing" || fail "guide-example: lacks a line of guide example: $(cat "$WORK/missing")"
if grep -qF 'm.get_or_insert(s, 0)[0] += 1;' "$ex"; then fail "guide-example: holds guide-mini's example"; fi

# guide-mini: unchanged, without the example
grep -q '^# vole in brief$' "$mini" || fail "guide-mini: no intro"
if grep -qF '```tach main.vl' "$mini"; then fail "guide-mini: holds the example"; fi

[ $STATUS -eq 0 ] && echo "pass eval-prompts (guide-example, guide-mini)"
exit $STATUS
