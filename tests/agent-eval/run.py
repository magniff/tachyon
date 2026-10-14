#!/usr/bin/env python3
"""tachyon's agent eval: how well a coding agent writes tachyon (bare, with
the guide, with the tools, with both) against the same tasks in Rust.

    run.py check-tasks [--tasks-dir D] [TASK...]
    run.py run --model M --cond C[,C...] [--tasks T,...] [--reps N] [--jobs J] [--out DIR]
    run.py report RUNDIR... [--md docs/eval/FILE.md]

README.md next to this file has the details."""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib.common import ALL_CONDS, DEFAULT_TASKS_DIR, REPO_ROOT  # noqa: E402


def main(argv):
    ap = argparse.ArgumentParser(prog="run.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd")

    def common(p):
        p.add_argument("--tasks-dir", default=DEFAULT_TASKS_DIR,
                       help="the tasks (default tests/agent-eval/tasks)")
        p.add_argument("--tachyonc", default=os.path.join(REPO_ROOT, "target", "tachyonc"),
                       help="the tachyon compiler under test (default target/tachyonc)")

    p = sub.add_parser("check-tasks", help="validate tasks: solutions pass, starters fail")
    common(p)
    p.add_argument("tasks", nargs="*", metavar="TASK")

    p = sub.add_parser("run", help="run agents on tasks and grade them")
    common(p)
    p.add_argument("--model", required=True,
                   help="claude:sonnet, claude:haiku, ollama:qwen3-coder:30b, ...")
    p.add_argument("--cond", required=True, help="comma-separated: " + ",".join(ALL_CONDS))
    p.add_argument("--tasks", default="", help="comma-separated task ids (default: all)")
    p.add_argument("--reps", type=int, default=1)
    p.add_argument("--jobs", type=int, default=4,
                   help="parallel runs for hosted models (ollama: always 1)")
    p.add_argument("--out", help="the run directory (default "
                   "tests/agent-eval/results/<timestamp>); rerun with the same "
                   "--out to resume")
    p.add_argument("--ws-root", help="where workspaces go (default "
                   "$TMPDIR/tachyon-eval/<run>); must be outside the repository")
    p.add_argument("--claude-permissions", choices=("allowlist", "bypass"),
                   default="allowlist",
                   help="claude backend: acceptEdits + sandbox + Bash allowlist "
                   "(default), or bypassPermissions inside the same sandbox")
    p.add_argument("--keep-workspaces", action="store_true",
                   help="keep the live workspaces (a tarball is kept anyway)")

    p = sub.add_parser("report", help="tables from result.json files")
    p.add_argument("rundirs", nargs="+", metavar="RUNDIR")
    p.add_argument("--md", help="write the report here (and FILE.json next to it)")

    args = ap.parse_args(argv)
    if args.cmd == "check-tasks":
        from lib import checktasks
        return checktasks.main(args)
    if args.cmd == "run":
        from lib import runner
        return runner.main(args)
    if args.cmd == "report":
        from lib import report
        return report.main(args)
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
