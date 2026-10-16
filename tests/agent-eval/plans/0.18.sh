#!/bin/sh
# The 0.18 round (plans/0.18.md): how agents fare with 0.17's value
# semantics and 0.18's contracts and tests, against Rust and the 0.17
# rounds, and what they say about the language (+debrief). Run from the
# repository root of a 0.18 checkout holding this runner (eval-018 merged):
#
#   sh tests/agent-eval/plans/0.18.sh                 # estimate check dry P C report
#   STEP=estimate sh tests/agent-eval/plans/0.18.sh   # the run count and cost, nothing run
#   STEP=P MODELS=claude:haiku sh tests/agent-eval/plans/0.18.sh
#
# (0.18.1) The same round again with another compiler and guide text,
# everything else as it was (tasks, conditions, reps, models), its
# results beside the first round's and compared with them:
#
#   ROUND=0.18-polish sh tests/agent-eval/plans/0.18.sh --compiler target/tachyonc
#
# Environment (or --compiler PATH for TACHYONC):
#   ROUND       the round's name (default 0.18): results in $OUT/ROUND-P-*,
#               ROUND-C-*, reports docs/eval/ROUND-*.md, and ROUND-manifest.txt
#               (the compiler's md5 and version, the commit, the prompts' md5s)
#   PREV        another round's results to compare with (default, when ROUND
#               is not 0.18: $BASE/0.18, holding 0.18-P-claude-*)
#   BASE        the earlier rounds (default: the main checkout's
#               .claude/briefs/evalruns): 0.16/ (rust), 0.17-validation/,
#               iter/03-night017/
#   TACHYONC    the 0.18 compiler for the program tasks (default target/tachyonc)
#   CBASE       the compiler tasks' base (default v0.18.0; release-0.18 before the tag)
#   CTASKS      compiler tasks (default 21-opt-peephole,23-fix-checker: the
#               two whose patches apply to the 0.18 tree; 22 and 24 do not)
#   MODELS      default "claude:haiku claude:sonnet" (side by side). Hosted
#               Claude models only: no ollama, ever.
#   SREPS HREPS reps for Sonnet (3) and Haiku (6: a prompt-level change on
#               Haiku needs 6+ a cell to be read)
#   JOBS, CJOBS parallel program / compiler runs per model (6, 2)
#   OUT         results root (default tests/agent-eval/results)
#   STEP        all (default: estimate check dry P C report)
#               | estimate | check | dry | P | C | report
set -eu
cd "$(dirname "$0")/../../.."
while [ $# -gt 0 ]; do
    case "$1" in
        --compiler) [ $# -ge 2 ] || { echo "plan: --compiler needs a path" >&2; exit 2; }; TACHYONC=$2; shift 2 ;;
        --compiler=*) TACHYONC=${1#--compiler=}; shift ;;
        *) echo "plan: unknown argument '$1' (--compiler PATH; the rest is environment)" >&2; exit 2 ;;
    esac
done
RUN=tests/agent-eval/run.py
main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
BASE=${BASE:-$main/.claude/briefs/evalruns}
TACHYONC=${TACHYONC:-target/tachyonc}
CBASE=${CBASE:-v0.18.0}
CTASKS=${CTASKS:-21-opt-peephole,23-fix-checker}
MODELS=${MODELS:-"claude:haiku claude:sonnet"}
SREPS=${SREPS:-3}
HREPS=${HREPS:-6}
JOBS=${JOBS:-6}
CJOBS=${CJOBS:-2}
OUT=${OUT:-tests/agent-eval/results}
STEP=${STEP:-all}
ROUND=${ROUND:-0.18}
if [ "$ROUND" = 0.18 ]; then PREV=${PREV:-}; else PREV=${PREV-$BASE/0.18}; fi
[ -x "$TACHYONC" ] || { echo "plan: no compiler at $TACHYONC" >&2; exit 2; }

# The tasks: iteration 1's seven (01, 03, 06 from a spec; 08, 10, 16, 17
# on existing code), the 0.17 rounds' comparison set, and three where
# owned values move and drop the most (04 a ledger of structs, 14 an AST
# of nested enums, 15 three modules passing owned state).
TASKS=01-wordfreq,03-dijkstra,04-ledger,06-intervals,15-multi-module,08-fix-compile,10-refactor-rename,14-ast-pass,16-perf-tight,17-debug-crash
# The adopted default (docs/eval/0.17-iterations.md, closing summary) and
# its Rust twin; the compiler tasks' tools (iteration 6) against plain.
G=guide-mini+readfirst
PCONDS=$G+debrief,rust+debrief
CCONDS=compiler-tools-core+hook+rewrite+debrief,compiler-plain+debrief

case "$MODELS" in *ollama*|*qwen*) echo "plan: hosted Claude models only (no ollama)" >&2; exit 1 ;; esac

say() { echo "==> $*" >&2; }
slug() { echo "$1" | tr ':' '-'; }
want() { [ "$STEP" = "$1" ] || { [ "$STEP" = all ] && case " estimate check dry P C report " in *" $1 "*) true ;; *) false ;; esac; }; }
reps_for() { case "$1" in *sonnet*) echo "$SREPS" ;; *) echo "$HREPS" ;; esac; }
count() { echo "$1" | tr ',' '\n' | grep -c .; }
pids=""
wait_all() {
    status=0
    for p in $pids; do wait "$p" || status=1; done
    pids=""
    [ $status -eq 0 ] || { echo "plan: a run failed (rerun the same command: runs resume)" >&2; exit 1; }
}

# The run count and a rough cost: each cell's medians from the 0.17
# iterations and the 0.16 baseline on these tasks (USD per run, input
# tokens per run in thousands, cache reads included; the debrief adds
# one request of the session's context, mostly cache reads).
if want estimate; then
    python3 - "$TASKS" "$CTASKS" "$MODELS" "$SREPS" "$HREPS" <<'PY'
import sys
tasks, ctasks, models, sreps, hreps = sys.argv[1].split(","), sys.argv[2].split(","), \
    sys.argv[3].split(), int(sys.argv[4]), int(sys.argv[5])
# (cost $, input k, output k) per run, the means over these tasks of the
# per-task medians: guide-mini+readfirst (iterations 1, 3, 5r, 9), rust
# (0.16), compiler-tools-core+hook+rewrite and compiler-plain (iteration 6)
EST = {
    "haiku":  {"tach": (0.054, 973, 26.8), "rust": (0.021, 533, 19.0),
               "ctools": (0.040, 1383, 22.5), "cplain": (0.050, 1422, 26.8),
               "debrief": (0.003, 40, 0.8)},
    "sonnet": {"tach": (0.170, 176, 6.5), "rust": (0.106, 93, 4.2),
               "ctools": (0.158, 213, 3.9), "cplain": (0.167, 296, 5.2),
               "debrief": (0.02, 30, 0.8)},
}
tot_runs = tot_cost = tot_in = tot_out = 0
for m in models:
    fam = "sonnet" if "sonnet" in m else "haiku"
    reps = sreps if fam == "sonnet" else hreps
    e = EST[fam]
    cells = [("tach", len(tasks)), ("rust", len(tasks)), ("ctools", len(ctasks)),
             ("cplain", len(ctasks))]
    runs = sum(n for _, n in cells) * reps
    cost = sum(e[k][0] * n * reps for k, n in cells) + e["debrief"][0] * runs
    tin = sum(e[k][1] * n * reps for k, n in cells) + e["debrief"][1] * runs
    tout = sum(e[k][2] * n * reps for k, n in cells) + e["debrief"][2] * runs
    print("%-14s %3d runs (%d program tasks x 2 conditions + %d compiler tasks x 2, x%d reps): "
          "~$%.0f, ~%.0fM input tokens (mostly cache reads), ~%.1fM output; debriefs ~$%.2f"
          % (m, runs, len(tasks), len(ctasks), reps, cost, tin / 1000, tout / 1000,
             e["debrief"][0] * runs))
    tot_runs += runs; tot_cost += cost; tot_in += tin; tot_out += tout
print("%-14s %3d runs: ~$%.0f, ~%.0fM input tokens, ~%.1fM output (estimate: 3-rep spreads are "
      "+-15%%; 15-multi-module dominates Haiku's cost)" % ("total", tot_runs, tot_cost,
                                                           tot_in / 1000, tot_out / 1000))
PY
fi

# The tasks are valid with this compiler: solutions pass, starters fail,
# the prompts' examples build; the compiler tasks apply to CBASE
if want check; then
    say "check-tasks (programs) with $TACHYONC"
    $RUN check-tasks --set programs --tachyonc "$TACHYONC" $(echo "$TASKS" | tr ',' ' ')
    say "check-tasks (compiler) on $CBASE"
    $RUN check-tasks --set compiler --base "$CBASE" $(echo "$CTASKS" | tr ',' ' ')
fi

# No model: every cell's prompt, debrief prompt, command line and hooks
if want dry; then
    say "dry run"
    rm -rf "$OUT/$ROUND-dry"
    $RUN run --model claude:haiku --set programs --tasks 01-wordfreq --tachyonc "$TACHYONC" \
        --cond "$PCONDS" --dry-run --selfcheck none --out "$OUT/$ROUND-dry"
    $RUN run --model claude:haiku --set compiler --tasks "${CTASKS%%,*}" --base "$CBASE" \
        --cond "$CCONDS" --dry-run --selfcheck none --out "$OUT/$ROUND-dry"
    python3 - "$OUT/$ROUND-dry" <<'PY'
import json, os, sys
bad = 0
for root, _, files in os.walk(sys.argv[1]):
    if "result.json" not in files:
        continue
    r = json.load(open(os.path.join(root, "result.json")))
    d = r.get("dry_run") or {}
    cmd = json.load(open(os.path.join(root, "command.json")))
    ok = (os.path.isfile(os.path.join(root, "debrief-prompt.md"))
          and "--input-format" in cmd and len((d.get("debrief") or {}).get("stdin", [])) == 2
          and "bypassPermissions" not in cmd)
    if r["cond"].startswith("compiler-tools"):
        post = [h for h in d.get("post_write", []) if h["hook"] == "check-after-edit.py"]
        ok = ok and bool(post) and "undefined_name_xyz" in post[0]["stdout"]
    print("%-4s %s %s" % ("ok" if ok else "FAIL", r["task"], r["cond"]))
    bad += not ok
sys.exit(1 if bad else 0)
PY
fi

# (0.18.1) What this round ran with: the compiler (the binaudit of the
# report step checks every run used it), the commit, the prompts.
manifest() {
    mkdir -p "$OUT"
    {
        echo "round $ROUND"
        echo "tachyonc $TACHYONC $(md5 -q "$TACHYONC" 2>/dev/null || md5sum "$TACHYONC" | cut -d' ' -f1)"
        echo "version $("$TACHYONC" --version 2>/dev/null)"
        echo "commit $(git rev-parse HEAD)$(git diff --quiet HEAD -- tests/agent-eval || echo ' (tests/agent-eval changed)')"
        for f in tests/agent-eval/prompts/*.md; do
            echo "prompt $(basename "$f") $(md5 -q "$f" 2>/dev/null || md5sum "$f" | cut -d' ' -f1)"
        done
    } >"$OUT/$ROUND-manifest.txt"
}
if want P || want C; then
    manifest
fi

# P. the program tasks: the default guide and its Rust twin, with the debrief
if want P; then
    for m in $MODELS; do
        say "P: $m $PCONDS on $(count "$TASKS") tasks x $(reps_for "$m")"
        $RUN run --model "$m" --set programs --tasks "$TASKS" --cond "$PCONDS" \
            --reps "$(reps_for "$m")" --jobs "$JOBS" --tachyonc "$TACHYONC" \
            --out "$OUT/$ROUND-P-$(slug "$m")" &
        pids="$pids $!"
    done
    wait_all
fi

# C. the compiler tasks on the 0.18 tree: tools against plain
if want C; then
    for m in $MODELS; do
        say "C: $m $CCONDS on $CTASKS ($CBASE) x $(reps_for "$m")"
        $RUN run --model "$m" --set compiler --tasks "$CTASKS" --base "$CBASE" --cond "$CCONDS" \
            --reps "$(reps_for "$m")" --jobs "$CJOBS" --out "$OUT/$ROUND-C-$(slug "$m")" &
        pids="$pids $!"
    done
    wait_all
fi

# The reports: docs/eval/$ROUND-*.md
if want report; then
    say "reports"
    dirs() { for d in "$@"; do [ -d "$d" ] && printf '%s ' "$d"; done; }
    p=$(dirs "$OUT"/"$ROUND"-P-*)
    c=$(dirs "$OUT"/"$ROUND"-C-*)
    n17=$BASE/iter/03-night017
    v17=$(dirs "$BASE"/0.17-validation/0.17v-A-claude-*)
    tasks_short=$(echo "$TASKS" | tr ',' '\n' | cut -c1-2 | paste -sd, -)
    # shellcheck disable=SC2086
    {
    # the binary every program run used (the 0.17 iterations' harness lesson)
    [ -n "$p" ] && $RUN binaudit $p --expect "$TACHYONC"
    if [ -n "$p" ]; then
        rust18=""; g18=""
        for d in $p; do rust18="$rust18 $d:rust"; g18="$g18${g18:+,}$d:$G"; done
        v17c=""
        for d in $v17; do v17c="$v17c${v17c:+,}$d:guide-core"; done
        # cost x Rust against 0.18's own Rust cells, then against 0.16's
        # (the 0.17 iterations' denominator), with the 0.17 cells beside
        $RUN costx --rust $rust18 --tasks "$tasks_short" --cell "G 0.18=$g18" \
            --cell "G night-017=$n17:$G" ${v17c:+--cell "guide-core 0.17v=$v17c"} \
            --md docs/eval/$ROUND-costx.md
        $RUN costx --rust "$BASE/0.16:rust" --tasks "$tasks_short" --cell "G 0.18=$g18" \
            --cell "rust 0.18=$(echo $rust18 | tr ' ' ',')" --cell "G night-017=$n17:$G" \
            ${v17c:+--cell "guide-core 0.17v=$v17c"} --md docs/eval/$ROUND-costx-rust016.md
        # per task, paired, with the anatomy's means
        $RUN compare --baseline "$n17" --new $p --pairs "$G+debrief=$G" \
            --md docs/eval/$ROUND-vs-night017.md
        [ -n "$v17" ] && $RUN compare --baseline $v17 --new $p --pairs "$G+debrief=guide-core" \
            --md docs/eval/$ROUND-vs-0.17v.md
        $RUN compare --baseline $p --new $p --pairs "$G+debrief=new:rust+debrief" \
            --md docs/eval/$ROUND-vs-rust.md
    fi
    # (0.18.1) against an earlier round (PREV): the same cells, by task
    if [ -n "$PREV" ] && [ -n "$p" ]; then
        pp=$(dirs "$PREV"/0.18-P-*)
        if [ -n "$pp" ]; then
            prev_g=""; prev_r=""
            for d in $pp; do prev_g="$prev_g${prev_g:+,}$d:$G"; prev_r="$prev_r $d:rust"; done
            $RUN costx --rust $rust18 --tasks "$tasks_short" --cell "G $ROUND=$g18" \
                --cell "G 0.18=$prev_g" --cell "rust 0.18 (as G)=$(echo $prev_r | tr ' ' ',')" \
                --md docs/eval/$ROUND-costx-vs-0.18.md
            $RUN compare --baseline $pp --new $p --pairs "$G+debrief=$G+debrief,rust+debrief=rust+debrief" \
                --md docs/eval/$ROUND-vs-0.18.md
        fi
        pc=$(dirs "$PREV"/0.18-C-*)
        [ -n "$pc" ] && [ -n "$c" ] && $RUN compare --baseline $pc --new $c \
            --pairs "compiler-tools-core+hook+rewrite+debrief=compiler-tools-core+hook+rewrite+debrief" \
            --md docs/eval/$ROUND-compiler-vs-0.18.md
    fi
    [ -n "$c" ] && $RUN compare --baseline $c --new $c \
        --pairs "compiler-tools-core+hook+rewrite+debrief=new:compiler-plain+debrief" \
        --md docs/eval/$ROUND-compiler.md
    all=$(dirs "$OUT"/"$ROUND"-P-* "$OUT"/"$ROUND"-C-*)
    [ -n "$all" ] && $RUN report $all --md docs/eval/$ROUND-results.md
    [ -n "$all" ] && $RUN debrief $all --md docs/eval/$ROUND-debrief.md
    } || true
fi
say "done"
