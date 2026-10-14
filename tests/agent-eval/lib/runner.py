"""`run.py run`: every (task, condition, rep) in a fresh workspace, the
agent, then the grading; one result.json per run, resumable."""

import json
import os
import shutil
import subprocess
import tarfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from lib import claude_backend, ollama_backend
from lib.common import (ALL_CONDS, DEFAULT_RESULTS_DIR, REPO_ROOT, base_env,
                        check_hook_summary, copy_tree, final_check,
                        install_check_hook, kill_leftovers, lang_of,
                        load_tasks, write_json)
from lib.grade import grade_dir, prepare_bins, tool_version
from lib.prompts import build_prompt, guide_text

_print_lock = threading.Lock()


def say(msg):
    with _print_lock:
        print(msg, flush=True)


def parse_model(m):
    backend, _, name = m.partition(":")
    if backend not in ("claude", "ollama") or not name:
        raise SystemExit("--model is claude:NAME or ollama:NAME, got %r" % m)
    return backend, name


def slug(s):
    return "".join(c if c.isalnum() or c in "-." else "-" for c in s)


def git_init(ws, env):
    e = dict(env, GIT_AUTHOR_NAME="eval", GIT_AUTHOR_EMAIL="eval@localhost",
             GIT_COMMITTER_NAME="eval", GIT_COMMITTER_EMAIL="eval@localhost")
    for argv in (["git", "init", "-q"],
                 ["git", "config", "user.name", "eval"],
                 ["git", "config", "user.email", "eval@localhost"],
                 ["git", "add", "-A"],
                 ["git", "commit", "-q", "--allow-empty", "-m", "starter"]):
        subprocess.run(argv, cwd=ws, env=e, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def tar_workspace(ws, dest):
    def keep(ti):
        name = os.path.basename(ti.name)
        if name in ("prog", ".git") or name.endswith(".o"):
            return None
        return ti
    with tarfile.open(dest, "w:gz") as tf:
        tf.add(ws, arcname="ws", filter=keep)


def one_run(ctx, task, cond, rep):
    model_slug = slug(ctx["model"])
    rel = os.path.join(task.id, model_slug, cond, "rep%d" % rep)
    rdir = os.path.join(ctx["out"], rel)
    if os.path.isfile(os.path.join(rdir, "result.json")):
        return None
    if os.path.isdir(rdir):
        shutil.rmtree(rdir)
    os.makedirs(rdir)
    lang = lang_of(cond)
    base = os.path.join(ctx["ws_root"], rel)
    if os.path.exists(base):
        shutil.rmtree(base)
    ws, bin_dir = os.path.join(base, "ws"), os.path.join(base, "bin")
    os.makedirs(bin_dir)
    tool = "tachyonc" if lang == "tach" else "rustc"
    os.symlink(os.path.join(ctx["bins"][lang], tool), os.path.join(bin_dir, tool))
    copy_tree(os.path.join(task.path, lang), ws)
    git_init(ws, base_env(bin_dir))

    # (--check-hook) the tools and both conditions: check after each change
    hook = ((ctx["check_hook"], os.path.join(base, "check-hook.jsonl"))
            if ctx.get("check_hook") and cond in ("tools", "both") else None)
    prompt = build_prompt(cond, task.text(), ctx.get("guide"),
                          "claude-env.md" if ctx["backend"] == "claude"
                          and claude_backend.PERMS == "allowlist" else None,
                          check_hook=bool(hook))
    with open(os.path.join(rdir, "prompt.md"), "w") as fh:
        fh.write(prompt)
    backend, name = ctx["backend"], ctx["model_name"]
    say("start %s %s %s rep%d" % (task.id, ctx["model"], cond, rep))
    t0 = time.time()
    try:
        mod = claude_backend if backend == "claude" else ollama_backend
        agent = mod.run(prompt, ws, bin_dir, name, task.timeout_s, rdir, check_hook=hook)
    except Exception as e:  # a broken backend still leaves a result
        agent = {"error": "runner: %r" % e, "wall_s": round(time.time() - t0, 1)}
    agent["leftover_processes"] = kill_leftovers(ws)
    if hook:
        agent["check_hook"] = check_hook_summary(hook[1])
        if os.path.exists(hook[1]):
            shutil.copyfile(hook[1], os.path.join(rdir, "check-hook.jsonl"))
    if lang == "tach":
        # (0.15) the errors left in the workspace, by code (check --json)
        agent["final_check"] = final_check(ws, base_env(bin_dir))
    try:
        g = grade_dir(task, lang, ws, os.path.join(base, "grade"), bin_dir)
    except Exception as e:
        g = {"success": False, "tests_passed": 0, "tests_total": len(task.tests()),
             "build_ok": False, "check_ok": None, "grade_error": repr(e)}
        agent["error"] = agent.get("error") or "grading: %r" % e
    with open(os.path.join(rdir, "grade.json"), "w") as fh:
        json.dump(g, fh, indent=1)
    tar_workspace(ws, os.path.join(rdir, "workspace.tar.gz"))
    res = {
        "task": task.id, "kind": task.kind, "model": ctx["model"],
        "cond": cond, "lang": lang, "rep": rep,
        "success": g["success"], "tests_passed": g["tests_passed"],
        "tests_total": g["tests_total"], "build_ok": g["build_ok"],
        "check_ok": g["check_ok"],
        "wall_s": None, "turns": None, "tool_calls": None,
        "tool_calls_by_kind": {}, "input_tokens": None, "output_tokens": None,
        "cache_read_tokens": None, "cost_usd": None, "error": None,
        "compiler": ctx["versions"][lang],
        "started": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(t0)),
    }
    res.update(agent)
    write_json(os.path.join(rdir, "result.json"), res)
    if not ctx["keep_ws"]:
        shutil.rmtree(base, ignore_errors=True)
    say("done  %s %s %s rep%d: %s %d/%d tests, %ss, %s turns, %s tool calls, "
        "%s in / %s out tokens%s" % (
            task.id, ctx["model"], cond, rep,
            "OK  " if res["success"] else "FAIL", res["tests_passed"],
            res["tests_total"], res["wall_s"], res["turns"], res["tool_calls"],
            res["input_tokens"], res["output_tokens"],
            ("; error: " + res["error"]) if res["error"] else ""))
    return res


def main(args):
    backend, model_name = parse_model(args.model)
    claude_backend.PERMS = args.claude_permissions
    conds = [c for c in args.cond.split(",") if c]
    bad = [c for c in conds if c not in ALL_CONDS]
    if bad or not conds:
        raise SystemExit("--cond takes %s; got %s" % (",".join(ALL_CONDS), args.cond))
    tasks = load_tasks(args.tasks_dir, args.tasks.split(",") if args.tasks else None)
    out = os.path.abspath(args.out or os.path.join(
        DEFAULT_RESULTS_DIR, time.strftime("%Y%m%d-%H%M%S")))
    os.makedirs(out, exist_ok=True)
    ws_root = os.path.realpath(args.ws_root or os.path.join(
        os.environ.get("TMPDIR", "/tmp"), "tachyon-eval", os.path.basename(out)))
    repo = os.path.realpath(REPO_ROOT)
    if ws_root == repo or ws_root.startswith(repo + os.sep):
        raise SystemExit("workspaces must be outside the repository: %s" % ws_root)
    os.makedirs(ws_root, exist_ok=True)
    bins = prepare_bins(ws_root, os.path.abspath(args.tachyonc))
    ctx = {"model": args.model, "backend": backend, "model_name": model_name,
           "out": out, "ws_root": ws_root, "bins": bins,
           "keep_ws": args.keep_workspaces,
           "check_hook": install_check_hook(ws_root) if args.check_hook else None,
           "versions": {"tach": tool_version(bins["tach"], "tach"),
                        "rust": tool_version(bins["rust"], "rust")}}
    if any(c in ("guide", "both") for c in conds):
        ctx["guide"] = guide_text(bins["tach"])
    runs_meta = os.path.join(out, "runs.jsonl")
    with open(runs_meta, "a") as fh:
        fh.write(json.dumps({
            "date": time.strftime("%Y-%m-%dT%H:%M:%S"), "model": args.model,
            "conds": conds, "tasks": [t.id for t in tasks], "reps": args.reps,
            "claude_permissions": args.claude_permissions,
            "check_hook": bool(args.check_hook),
            "tachyonc": os.path.abspath(args.tachyonc),
            "versions": ctx["versions"], "ws_root": ws_root}) + "\n")
    jobs = [(t, c, r) for r in range(1, args.reps + 1) for t in tasks for c in conds]
    todo = [j for j in jobs if not os.path.isfile(os.path.join(
        out, j[0].id, slug(args.model), j[1], "rep%d" % j[2], "result.json"))]
    nj = 1 if backend == "ollama" else max(1, args.jobs)
    say("run %s: %d runs (%d done before), %d at a time; results in %s, "
        "workspaces in %s" % (args.model, len(jobs), len(jobs) - len(todo), nj,
                              out, ws_root))
    results = []
    if nj == 1:
        for j in todo:
            results.append(one_run(ctx, *j))
    else:
        with ThreadPoolExecutor(nj) as ex:
            results = list(ex.map(lambda j: one_run(ctx, *j), todo))
    done = [r for r in results if r]
    ok = sum(1 for r in done if r["success"])
    say("finished: %d runs, %d succeeded; report: tests/agent-eval/run.py report %s"
        % (len(done), ok, out))
    return 0
