#!/bin/sh
# The 0.16 agent-eval round, in one command (plans/0.16.md says why and
# what it costs). Run from the repository root of a checkout holding this
# runner, after v0.16.0 is tagged and bootstrapped:
#
#   sh tests/agent-eval/plans/0.16.sh            # everything, resumable
#   STEP=check sh tests/agent-eval/plans/0.16.sh # only the validation
#
# Environment:
#   TACHYONC   the compiler under test for the program tasks (default
#              target/tachyonc; must say 0.16.0 unless FORCE=1)
#   MODELS     default "claude:haiku claude:sonnet" (run side by side)
#   REPS       default 3
#   JOBS       parallel program runs per model (default 6)
#   CJOBS      parallel compiler-task runs per model (default 2: each
#              builds the compiler and runs tests on every core)
#   OUT        results root (default tests/agent-eval/results)
#   STEP       all (default) | check | dry | programs | hook | compiler | report
#   FORCE=1    run with a compiler that is not 0.16.0
set -eu
cd "$(dirname "$0")/../../.."
RUN=tests/agent-eval/run.py
TACHYONC=${TACHYONC:-target/tachyonc}
MODELS=${MODELS:-"claude:haiku claude:sonnet"}
REPS=${REPS:-3}
JOBS=${JOBS:-6}
CJOBS=${CJOBS:-2}
OUT=${OUT:-tests/agent-eval/results}
STEP=${STEP:-all}
FORCE=${FORCE:-0}

say() { echo "==> $*" >&2; }
slug() { echo "$1" | tr ':' '-'; }
want() { [ "$STEP" = all ] || [ "$STEP" = "$1" ]; }

version=$("$TACHYONC" --version 2>/dev/null | head -1 || true)
case "$version" in
    *0.16.0*) ;;
    *) [ "$FORCE" = 1 ] || { echo "plan: $TACHYONC is '$version', not 0.16.0 (FORCE=1 to run anyway)" >&2; exit 1; } ;;
esac
git rev-parse -q --verify 'v0.16.0^{commit}' >/dev/null \
    || [ "$FORCE" = 1 ] || { echo "plan: no tag v0.16.0 (the compiler tasks' base); FORCE=1 runs on base_fallback" >&2; exit 1; }

# 1. the tasks are valid on 0.16.0: every program task's solutions pass and
# starters fail with $TACHYONC; every compiler task's patches apply to
# v0.16.0, its reference solution passes the grading and its starter fails
if want check; then
    say "check-tasks (programs with $version; compiler tasks on v0.16.0)"
    $RUN check-tasks --set all --tachyonc "$TACHYONC"
fi

# 2. no model: the workspaces, prompts and settings of the compiler
# conditions, and the hooks fired on synthetic events
if want dry; then
    say "dry run of the compiler conditions"
    rm -rf "$OUT/0.16-dry"
    $RUN run --model claude:haiku --set compiler --cond compiler-tools,compiler-plain \
        --dry-run --out "$OUT/0.16-dry" --ws-root "${TMPDIR:-/tmp}/tachyon-eval/0.16-dry"
    python3 - "$OUT/0.16-dry" <<'PY'
import json, os, sys
bad = 0
for root, _, files in os.walk(sys.argv[1]):
    if "result.json" not in files:
        continue
    r = json.load(open(os.path.join(root, "result.json")))
    d = r.get("dry_run") or {}
    if r["cond"] == "compiler-tools":
        post = [h for h in d.get("post_write", []) if h["hook"] == "check-after-edit.py"]
        pre = [h for h in d.get("pre_grep", []) if h["hook"] == "query-first.py"]
        ok = (post and "undefined_name_xyz" in post[0]["stdout"]
              and pre and pre[0]["exit"] == 2)
    else:
        ok = not d.get("hooks_registered")
    print("%-4s %s %s" % ("ok" if ok else "FAIL", r["task"], r["cond"]))
    bad += not ok
sys.exit(1 if bad else 0)
PY
fi

pids=""
wait_all() {
    status=0
    for p in $pids; do wait "$p" || status=1; done
    pids=""
    [ $status -eq 0 ] || { echo "plan: a run failed (rerun the same command: runs resume)" >&2; exit 1; }
}

# 3. the program tasks (18): no help, everything, Rust
if want programs; then
    for m in $MODELS; do
        say "programs: $m, bare,both,rust x $REPS"
        $RUN run --model "$m" --set programs --cond bare,both,rust --reps "$REPS" \
            --jobs "$JOBS" --tachyonc "$TACHYONC" --out "$OUT/0.16-programs-$(slug "$m")" &
        pids="$pids $!"
    done
    wait_all
fi

# 3b. `guide` on the hard tasks 13-18: both against guide isolates the tools
if want programs; then
    for m in $MODELS; do
        say "programs 13-18: $m, guide x $REPS"
        $RUN run --model "$m" --set programs --cond guide --reps "$REPS" \
            --tasks 13-port-c,14-ast-pass,15-multi-module,16-perf-tight,17-debug-crash,18-api-refactor \
            --jobs "$JOBS" --tachyonc "$TACHYONC" --out "$OUT/0.16-programs-$(slug "$m")" &
        pids="$pids $!"
    done
    wait_all
fi

# 4. the same with the check hook (0.15), in `both`
if want hook; then
    for m in $MODELS; do
        say "programs with the check hook: $m, both x $REPS"
        $RUN run --model "$m" --set programs --cond both --check-hook --reps "$REPS" \
            --jobs "$JOBS" --tachyonc "$TACHYONC" --out "$OUT/0.16-hook-$(slug "$m")" &
        pids="$pids $!"
    done
    wait_all
fi

# 5. the compiler tasks: tools against plain
if want compiler; then
    for m in $MODELS; do
        say "compiler tasks: $m, compiler-tools,compiler-plain x $REPS"
        $RUN run --model "$m" --set compiler --cond compiler-tools,compiler-plain \
            --reps "$REPS" --jobs "$CJOBS" --out "$OUT/0.16-compiler-$(slug "$m")" &
        pids="$pids $!"
    done
    wait_all
fi

# 6. the reports
if want report; then
    say "reports"
    # shellcheck disable=SC2086
    $RUN report $(ls -d "$OUT"/0.16-programs-* "$OUT"/0.16-compiler-* 2>/dev/null) \
        --md docs/eval/0.16.md
    # shellcheck disable=SC2086
    $RUN report $(ls -d "$OUT"/0.16-hook-* 2>/dev/null) --md docs/eval/0.16-check-hook.md
fi
say "done"
