#!/usr/bin/env python3
"""vole's agent eval: how well a coding agent writes vole (bare, with
the guide, with the tools, with both) against the same tasks in Rust.

    run.py check-tasks [--set all|programs|compiler|dev | --tasks-dir D] [TASK...]
    run.py list [--set ...]
    run.py run --model M --cond C[,C...] [--tasks T,...] [--reps N] [--jobs J] [--out DIR]
    run.py report RUNDIR... [--md docs/eval/FILE.md]
    run.py regrade RUNDIR... [--only-stopped | --only-failed | --only-check-failed]
    run.py analyze RUNDIR... [--write] [--check]      (0.17: each run's anatomy)
    run.py compare --baseline DIR... --new DIR... [--md FILE]   (0.17)
    run.py selfcheck --model M --kinds tach,rust,compiler [--offline]   (0.17)
    run.py debrief RUNDIR... [--md FILE]   (0.18: the +debrief answers by theme)
    run.py binaudit RUNDIR... [--expect VOLEC]   (0.18: the binary each run used)
    run.py costx --rust DIR[:COND]... --cell LABEL=DIR[:COND],... [--md FILE]   (0.18)

README.md next to this file has the details."""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib.common import (DEFAULT_TASKS_DIR, REPO_ROOT,  # noqa: E402
                        TASK_SETS, load_tasks)
from lib.conds import help_text as conds_help  # noqa: E402


def main(argv):
    ap = argparse.ArgumentParser(prog="run.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd")

    def common(p):
        p.add_argument("--tasks-dir", default=DEFAULT_TASKS_DIR,
                       help="the task directories, comma-separated (default "
                       "tests/agent-eval/tasks)")
        p.add_argument("--set", choices=sorted(TASK_SETS),
                       help="instead of --tasks-dir: programs (tasks/), compiler "
                       "(ctasks/), all (both), dev (devtasks/)")
        p.add_argument("--base", help="compiler tasks: the base commit instead of "
                       "meta.toml's base (then base_fallback)")
        p.add_argument("--builder", help="compiler tasks: the compiler that builds the "
                       "base (default: the release its releases.toml names, from a "
                       "bootstrap cache)")
        p.add_argument("--volec", default=os.path.join(REPO_ROOT, "target", "volec"),
                       help="the vole compiler under test (default target/volec)")

    p = sub.add_parser("check-tasks", help="validate tasks: solutions pass, starters fail")
    common(p)
    p.add_argument("--keep", action="store_true", help="keep the scratch directory")
    p.add_argument("--no-lint", action="store_true",
                   help="(0.17) skip the reference solutions' lints")
    p.add_argument("tasks", nargs="*", metavar="TASK")

    p = sub.add_parser("list", help="the tasks, with kind, title and time limit")
    common(p)

    p = sub.add_parser("run", help="run agents on tasks and grade them")
    common(p)
    p.add_argument("--model", required=True,
                   help="claude:sonnet, claude:haiku, ollama:qwen3-coder:30b, ...")
    p.add_argument("--cond", required=True, help="comma-separated; " + conds_help()
                   + " (lib/conds.py)")
    p.add_argument("--tasks", default="", help="comma-separated task ids (default: all)")
    p.add_argument("--reps", type=int, default=1)
    p.add_argument("--jobs", type=int, default=4,
                   help="parallel runs for hosted models (ollama: always 1)")
    p.add_argument("--out", help="the run directory (default "
                   "tests/agent-eval/results/<timestamp>); rerun with the same "
                   "--out to resume")
    p.add_argument("--ws-root", help="where workspaces go (default "
                   "$TMPDIR/vole-eval/<run>); must be outside the repository")
    p.add_argument("--claude-permissions", choices=("allowlist", "bypass"),
                   default="allowlist",
                   help="claude backend: acceptEdits + sandbox + Bash allowlist "
                   "(default), or bypassPermissions inside the same sandbox")
    p.add_argument("--check-hook", action="store_true",
                   help="tools and both conditions (always on in compiler-tools): "
                   "tools/agent-hooks/check-after-edit.py "
                   "after every change to a .vl file (its errors appended to the "
                   "tool result); result.json gets check_hook")
    p.add_argument("--dry-run", action="store_true",
                   help="no model: set up each workspace, write prompt.md, settings.json "
                   "and command.json, and fire the hooks on synthetic events (result.json "
                   "gets dry_run); workspaces are kept")
    p.add_argument("--keep-workspaces", action="store_true",
                   help="keep the live workspaces (a tarball is kept anyway)")
    p.add_argument("--skip-existing-in", nargs="+", default=[], metavar="DIR",
                   help="(0.17) leave out the runs (task, model, condition, rep) that have a "
                   "result.json in one of these run directories: a baseline round's cells "
                   "are reused, only the missing ones run")
    p.add_argument("--selfcheck", choices=("auto", "hosted", "offline", "none"), default="auto",
                   help="(0.17) before the round: offline (no model: the workspace, sandbox "
                   "approximation), hosted (plus one cheap session per kind in the real "
                   "sandbox), auto (hosted for claude, offline for ollama); the round "
                   "stops when a probe fails")
    p.add_argument("--selfcheck-model", default="claude:haiku",
                   help="the model of the hosted self-check sessions")
    p.add_argument("--tools-volec",
                   help="(0.17) compiler-tools conditions: the binary given as "
                   "target/tools/volec (default the starter's): newer tools on the same tasks")

    p = sub.add_parser("report", help="tables from result.json files")
    p.add_argument("rundirs", nargs="+", metavar="RUNDIR")
    p.add_argument("--md", help="write the report here (and FILE.json next to it)")

    p = sub.add_parser("regrade", help="grade finished runs again without the agent "
                       "(compiler tasks: changes.patch; programs: workspace.tar.gz)")
    p.add_argument("rundirs", nargs="+", metavar="RUNDIR")
    p.add_argument("--only-stopped", action="store_true",
                   help="compiler runs: only those where a suite filter stopped before any case")
    p.add_argument("--only-failed", action="store_true", help="program runs: only failed ones")
    p.add_argument("--only-check-failed", action="store_true",
                   help="program runs: only those whose check.sh failed")
    p.add_argument("--tasks", default="", help="program runs: these task ids only")
    p.add_argument("--volec", default=os.path.join(REPO_ROOT, "target", "volec"),
                   help="program runs: the compiler under test (default target/volec)")
    p.add_argument("--ws-root", help="where the starter trees are built and the grading "
                   "runs (default $TMPDIR/vole-eval/regrade)")
    p.add_argument("--builder", help="the compiler that builds the base (default: the "
                   "release its releases.toml names)")

    p = sub.add_parser("analyze", help="(0.17) each run's anatomy from its transcript")
    p.add_argument("rundirs", nargs="+", metavar="RUNDIR")
    p.add_argument("--write", action="store_true", help="store it in result.json")
    p.add_argument("--check", action="store_true",
                   help="reconcile the role totals with tool_calls_by_kind")
    p.add_argument("--top", type=int, default=25, help="messages to list")

    p = sub.add_parser("compare", help="(0.17) new runs against a baseline, per task")
    p.add_argument("--baseline", nargs="+", required=True, metavar="DIR")
    p.add_argument("--new", nargs="+", required=True, metavar="DIR")
    p.add_argument("--pairs", default="",
                   help="NEWCOND=BASECOND,... (default: every new condition against every "
                   "baseline condition of the same kind)")
    p.add_argument("--md", help="write the report here (and FILE.json next to it)")

    p = sub.add_parser("selfcheck", help="(0.17) can agents build, run, test and write, "
                       "inside the sandbox")
    common(p)
    p.add_argument("--model", default="claude:haiku")
    p.add_argument("--kinds", default="tach", help="tach,rust,compiler")
    p.add_argument("--cond", default="", help="conditions whose needs are probed "
                   "(+test: volec test)")
    p.add_argument("--offline", action="store_true", help="no model session")
    p.add_argument("--out", help="where selfcheck.json goes (default results/selfcheck-TIME)")
    p.add_argument("--ws-root")

    p = sub.add_parser("debrief", help="(0.18) the +debrief answers: ratings, themes, "
                       "codes, every answer per task")
    p.add_argument("rundirs", nargs="+", metavar="RUNDIR")
    p.add_argument("--md", help="write the report here")
    p.add_argument("--quotes", type=int, default=3,
                   help="quotes per theme and cell (default 3; 0: none)")

    p = sub.add_parser("binaudit", help="(0.18) which compiler each program run used")
    p.add_argument("rundirs", nargs="+", metavar="RUNDIR")
    p.add_argument("--expect", help="the compiler (a path or its md5) every run must have used")

    p = sub.add_parser("costx", help="(0.18) cells against Rust: cost x Rust, tier-free, "
                       "turns, success, errors by family (own, contract, test, distinct)")
    p.add_argument("--rust", nargs="+", required=True, metavar="DIR[:COND]")
    p.add_argument("--cell", action="append", default=[], metavar="LABEL=DIR[:COND],...")
    p.add_argument("--tasks", default="", help="task id prefixes, comma-separated")
    p.add_argument("--models", default="", help="claude:haiku,claude:sonnet (default: all)")
    p.add_argument("--md", help="write the report here")

    args = ap.parse_args(argv)
    if args.cmd == "debrief":
        from lib import debrief
        return debrief.main(args)
    if args.cmd == "binaudit":
        from lib import binaudit
        return binaudit.main(args)
    if args.cmd == "costx":
        from lib import costx
        return costx.main(args)
    if args.cmd == "analyze":
        from lib import anatomy
        return anatomy.analyze_main(args)
    if args.cmd == "compare":
        from lib import compare
        return compare.main(args)
    if args.cmd == "selfcheck":
        from lib import selfcheck
        return selfcheck.main(args)
    if args.cmd == "check-tasks":
        from lib import checktasks
        return checktasks.main(args)
    if args.cmd == "list":
        for t in load_tasks(args.tasks_dir, None, args.set):
            extra = ""
            if t.is_compiler:
                extra = " base %s (fallback %s); suite %s" % (
                    t.base, t.base_fallback, ",".join(t.suite))
            print("%-20s %-9s %5ds  %s%s" % (t.id, t.kind, t.timeout_s, t.title, extra))
        return 0
    if args.cmd == "run":
        from lib import runner
        return runner.main(args)
    if args.cmd == "regrade":
        from lib import ctasks
        return ctasks.regrade_main(args)
    if args.cmd == "report":
        from lib import report
        return report.main(args)
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
