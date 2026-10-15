#!/bin/sh
# The 0.17 validation round (plans/0.17-validation.md): the deciding cells
# of docs/research/applying-to-tachyon.md's rerun matrix, against the 0.16
# round as the baseline. Run from the repository root of a checkout holding
# this runner:
#
#   sh tests/agent-eval/plans/0.17-validation.sh             # A, A-control, drift, tools, C, G, report
#   STEP=D sh tests/agent-eval/plans/0.17-validation.sh      # after `tachyonc test` and settings-eval.json
#   STEP=E TACHYONC_DIAG=... sh tests/agent-eval/plans/0.17-validation.sh   # after item 5
#
# Environment:
#   BASE        the 0.16 round's results (default: the main checkout's
#               .claude/briefs/evalruns/0.16)
#   TACHYONC    the 0.17 candidate for the program tasks (default
#               target/tachyonc; must have `tachyonc guide --full`)
#   TOOLS_TACHYONC  compiler tasks: the binary given as target/tools/tachyonc
#               (default: unset, the starter's)
#   TACHYONC_DIAG   step E: the compiler with item 5's diagnostics
#   MODELS      default "claude:haiku claude:sonnet" (side by side)
#   DREPS       reps of the deciding Sonnet program cells (default 10)
#   REPS        reps elsewhere (default 3)
#   JOBS, CJOBS parallel program / compiler runs per model (6, 2)
#   OUT         results root (default tests/agent-eval/results)
#   STEP        all (default: check dry A A-control drift tools C G report)
#               | check | dry | A | A-control | drift | tools | C | G | D | E | report
set -eu
cd "$(dirname "$0")/../../.."
RUN=tests/agent-eval/run.py
main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
BASE=${BASE:-$main/.claude/briefs/evalruns/0.16}
TACHYONC=${TACHYONC:-target/tachyonc}
TOOLS_TACHYONC=${TOOLS_TACHYONC:-}
MODELS=${MODELS:-"claude:haiku claude:sonnet"}
DREPS=${DREPS:-10}
REPS=${REPS:-3}
JOBS=${JOBS:-6}
CJOBS=${CJOBS:-2}
OUT=${OUT:-tests/agent-eval/results}
STEP=${STEP:-all}
HARD=13-port-c,14-ast-pass,15-multi-module,16-perf-tight,17-debug-crash,18-api-refactor
EASY=01-wordfreq,02-rpn,03-dijkstra,04-ledger,05-base64,06-intervals,07-fix-bugs,08-fix-compile,09-extend-calc,10-refactor-rename,11-add-variant,12-perf

say() { echo "==> $*" >&2; }
slug() { echo "$1" | tr ':' '-'; }
want() { [ "$STEP" = "$1" ] || { [ "$STEP" = all ] && case " check dry A A-control drift tools C G report " in *" $1 "*) true ;; *) false ;; esac; }; }
reps_for() { case "$1" in *sonnet*) echo "$DREPS" ;; *) echo "$REPS" ;; esac; }
pids=""
wait_all() {
    status=0
    for p in $pids; do wait "$p" || status=1; done
    pids=""
    [ $status -eq 0 ] || { echo "plan: a run failed (rerun the same command: runs resume)" >&2; exit 1; }
}

[ -d "$BASE" ] || { echo "plan: no baseline at $BASE (BASE=...)" >&2; exit 1; }
"$TACHYONC" guide --full > /dev/null 2>&1 ||
    { echo "plan: $TACHYONC has no 'guide --full' (not a 0.17 candidate with the short core)" >&2; exit 1; }
tools_arg=""
[ -n "$TOOLS_TACHYONC" ] && tools_arg="--tools-tachyonc $TOOLS_TACHYONC"

# J. the tasks are valid: solutions, variants, lints, the prompts' examples
if want check; then
    say "check-tasks"
    $RUN check-tasks --set all --tachyonc "$TACHYONC"
fi

# no model: every new condition's prompt, settings and hooks
if want dry; then
    say "dry run"
    rm -rf "$OUT/0.17v-dry"
    $RUN run --model claude:haiku --set dev --tasks 00-hello-sum --tachyonc "$TACHYONC" \
        --cond guide,guide-core,tools-core,both-core,rust-pairs,both+hook,both+hook+test,rust \
        --dry-run --out "$OUT/0.17v-dry" --ws-root "${TMPDIR:-/tmp}/tachyon-eval/0.17v-dry"
    $RUN run --model claude:haiku --set compiler --tasks 21-opt-peephole $tools_arg \
        --cond compiler-tools,compiler-plain,compiler-tools-core,compiler-tools-core+test \
        --dry-run --out "$OUT/0.17v-dry" --ws-root "${TMPDIR:-/tmp}/tachyon-eval/0.17v-dry"
    python3 - "$OUT/0.17v-dry" <<'PY'
import json, os, sys
bad = 0
for root, _, files in os.walk(sys.argv[1]):
    if "result.json" not in files:
        continue
    r = json.load(open(os.path.join(root, "result.json")))
    d = r.get("dry_run") or {}
    post = [h for h in d.get("post_write", []) if h["hook"] == "check-after-edit.py"]
    pre = [h for h in d.get("pre_grep", []) if h["hook"] == "query-first.py"]
    c = r["cond"]
    if c.startswith("compiler-tools"):
        ok = post and "undefined_name_xyz" in post[0]["stdout"] and pre and pre[0]["exit"] == 2
    elif "+hook" in c or "+test" in c:
        ok = bool(post) and "undefined_name_xyz" in post[0]["stdout"]
    else:
        ok = not d.get("hooks_registered")
    print("%-4s %s %s" % ("ok" if ok else "FAIL", r["task"], c))
    bad += not ok
sys.exit(1 if bad else 0)
PY
fi

# A. the core guide: guide-core on every program task (Sonnet x DREPS)
if want A; then
    for m in $MODELS; do
        say "A: $m guide-core x $(reps_for "$m")"
        $RUN run --model "$m" --set programs --cond guide-core --reps "$(reps_for "$m")" \
            --jobs "$JOBS" --tachyonc "$TACHYONC" --out "$OUT/0.17v-A-$(slug "$m")" &
        pids="$pids $!"
    done
    wait_all
fi

# A-control: `guide` (guide --full) where the baseline has no guide cell
if want A-control; then
    for m in $MODELS; do
        say "A-control: $m guide x $REPS, baseline cells reused"
        $RUN run --model "$m" --set programs --cond guide --reps "$REPS" \
            --skip-existing-in "$BASE/0.16-programs-$(slug "$m")" \
            --jobs "$JOBS" --tachyonc "$TACHYONC" --out "$OUT/0.17v-Actl-$(slug "$m")" &
        pids="$pids $!"
    done
    wait_all
fi

# drift: the guide control again on three hard tasks with the 0.17 compiler
if want drift; then
    for m in $MODELS; do
        say "drift: $m guide on 13, 16, 17 x $REPS"
        $RUN run --model "$m" --set programs --cond guide --reps "$REPS" \
            --tasks 13-port-c,16-perf-tight,17-debug-crash \
            --jobs "$JOBS" --tachyonc "$TACHYONC" --out "$OUT/0.17v-drift-$(slug "$m")" &
        pids="$pids $!"
    done
    wait_all
fi

# tools: the core guide and the tiered tools together, on the hard tasks
if want tools; then
    for m in $MODELS; do
        say "tools: $m both-core on 13-18 x $(reps_for "$m")"
        $RUN run --model "$m" --set programs --cond both-core --tasks "$HARD" \
            --reps "$(reps_for "$m")" --jobs "$JOBS" --tachyonc "$TACHYONC" \
            --out "$OUT/0.17v-tools-$(slug "$m")" &
        pids="$pids $!"
    done
    wait_all
fi

# C. the compiler tasks with the tiered AGENTS.md
if want C; then
    for m in $MODELS; do
        say "C: $m compiler-tools-core x $REPS"
        $RUN run --model "$m" --set compiler --cond compiler-tools-core --reps "$REPS" \
            --jobs "$CJOBS" $tools_arg --out "$OUT/0.17v-C-$(slug "$m")" &
        pids="$pids $!"
    done
    wait_all
fi

# G. paired Rust -> tachyon lines against the core guide, hard tasks
if want G; then
    for m in $MODELS; do
        say "G: $m rust-pairs on 13-18 x $REPS"
        $RUN run --model "$m" --set programs --cond rust-pairs --tasks "$HARD" --reps "$REPS" \
            --jobs "$JOBS" --tachyonc "$TACHYONC" --out "$OUT/0.17v-G-$(slug "$m")" &
        pids="$pids $!"
    done
    wait_all
fi

# D. tachyonc test in the hook (needs it in TACHYONC and settings-eval.json)
if want D; then
    for m in $MODELS; do
        say "D: $m both+hook+test on 13-18; the check-hook control where missing"
        $RUN run --model "$m" --set programs --cond both+hook+test --tasks "$HARD" \
            --reps "$(reps_for "$m")" --jobs "$JOBS" --tachyonc "$TACHYONC" \
            --out "$OUT/0.17v-D-$(slug "$m")"
        $RUN run --model "$m" --set programs --cond both --check-hook --tasks "$HARD" \
            --reps "$REPS" --skip-existing-in "$BASE/0.16-hook-$(slug "$m")" --jobs "$JOBS" \
            --tachyonc "$TACHYONC" --out "$OUT/0.17v-Dctl-$(slug "$m")"
        $RUN run --model "$m" --set compiler --cond compiler-tools-core+test --reps "$REPS" \
            --jobs "$CJOBS" $tools_arg --out "$OUT/0.17v-D-$(slug "$m")" &
        pids="$pids $!"
    done
    wait_all
fi

# E. the diagnostics (item 5): guide-core again with that compiler
if want E; then
    : "${TACHYONC_DIAG:?STEP=E needs TACHYONC_DIAG, the compiler with item 5}"
    for m in $MODELS; do
        say "E: $m guide-core with $TACHYONC_DIAG x $REPS"
        $RUN run --model "$m" --set programs --cond guide-core --reps "$REPS" \
            --jobs "$JOBS" --tachyonc "$TACHYONC_DIAG" --out "$OUT/0.17v-E-$(slug "$m")" &
        pids="$pids $!"
    done
    wait_all
fi

# the comparisons, docs/eval/0.17-validation-*.md
if want report; then
    say "reports"
    dirs() { for d in "$@"; do [ -d "$d" ] && printf '%s ' "$d"; done; }
    bp=$(dirs "$BASE"/0.16-programs-claude-*)
    bc=$(dirs "$BASE"/0.16-compiler-claude-sonnet "$BASE"/0.16-compiler-claude-haiku)
    bh=$(dirs "$BASE"/0.16-hook-claude-*)
    actl=$(dirs "$OUT"/0.17v-Actl-*)
    # shellcheck disable=SC2086
    {
    n=$(dirs "$OUT"/0.17v-A-*)
    [ -n "$n" ] && $RUN compare --baseline $bp $actl --new $n \
        --pairs guide-core=guide,guide-core=both,guide-core=rust --md docs/eval/0.17-validation-A.md
    n=$(dirs "$OUT"/0.17v-drift-*)
    [ -n "$n" ] && $RUN compare --baseline $bp --new $n --pairs guide=guide \
        --md docs/eval/0.17-validation-drift.md
    n=$(dirs "$OUT"/0.17v-tools-*)
    [ -n "$n" ] && $RUN compare --baseline $bp --new $n --pairs both-core=both,both-core=guide \
        --md docs/eval/0.17-validation-tools.md
    n=$(dirs "$OUT"/0.17v-C-*)
    [ -n "$n" ] && $RUN compare --baseline $bc --new $n \
        --pairs compiler-tools-core=compiler-tools,compiler-tools-core=compiler-plain \
        --md docs/eval/0.17-validation-C.md
    n=$(dirs "$OUT"/0.17v-G-*)
    a=$(dirs "$OUT"/0.17v-A-*)
    [ -n "$n" ] && [ -n "$a" ] && $RUN compare --baseline $a --new $n \
        --pairs rust-pairs=guide-core --md docs/eval/0.17-validation-G.md
    n=$(dirs "$OUT"/0.17v-D-*)
    dctl=$(dirs "$OUT"/0.17v-Dctl-*)
    c=$(dirs "$OUT"/0.17v-C-*)
    # (three baselines kept apart: 0.16-hook's cells are named `both` too)
    [ -n "$n" ] && $RUN compare --baseline $bh $dctl --new $n --pairs both+hook+test=both \
        --md docs/eval/0.17-validation-D-hook.md
    [ -n "$n" ] && $RUN compare --baseline $bp --new $n --pairs both+hook+test=both \
        --md docs/eval/0.17-validation-D-both.md
    [ -n "$n" ] && [ -n "$c" ] && $RUN compare --baseline $c --new $n \
        --pairs compiler-tools-core+test=compiler-tools-core --md docs/eval/0.17-validation-D-C.md
    n=$(dirs "$OUT"/0.17v-E-*)
    [ -n "$n" ] && [ -n "$a" ] && $RUN compare --baseline $a --new $n \
        --pairs guide-core=guide-core --md docs/eval/0.17-validation-E.md
    all=$(dirs "$OUT"/0.17v-A-* "$OUT"/0.17v-Actl-* "$OUT"/0.17v-drift-* "$OUT"/0.17v-tools-* \
        "$OUT"/0.17v-C-* "$OUT"/0.17v-G-* "$OUT"/0.17v-D-* "$OUT"/0.17v-Dctl-* "$OUT"/0.17v-E-*)
    [ -n "$all" ] && $RUN report $all --md docs/eval/0.17-validation.md
    } || true
fi
say "done"
