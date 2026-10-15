"""`run.py run`: every (task, condition, rep) in a fresh workspace, the
agent, then the grading; one result.json per run, resumable."""

import json
import os
import re
import shutil
import subprocess
import tarfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from lib import claude_backend, ctasks, ollama_backend
from lib.common import (ALL_CONDS, COMPILER_CONDS, DEFAULT_RESULTS_DIR, REPO_ROOT,
                        base_env, check_hook_summary, copy_tree, final_check,
                        install_hooks, kill_leftovers, lang_of, load_tasks,
                        private_paths, query_hook_summary, write_json)
from lib.grade import grade_dir, prepare_bins, tool_version
from lib.prompts import build_prompt, compiler_prompt, guide_text

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


def fits(task, cond):
    """A compiler task runs in the compiler conditions, a program task in
    the others."""
    return task.is_compiler == (cond in COMPILER_CONDS)


def one_run(ctx, task, cond, rep):
    if task.is_compiler:
        return one_compiler_run(ctx, task, cond, rep)
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
    hook = ((ctx["hooks"]["check"], os.path.join(base, "check-hook.jsonl"))
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
        if ctx.get("dry_run"):
            agent = dry_run(ctx, prompt, ws, rdir, hook, None)
        else:
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


def one_compiler_run(ctx, task, cond, rep):
    """(0.16) A compiler task: the workspace is a copy of the repository at
    the task's base (lib/ctasks.py), the prompt carries AGENTS.md for the
    condition; compiler-tools gets the query-first and check hooks. The
    agent's changes are kept as changes.patch (the tree is too big to
    keep), and the grading builds them and runs the task's tests."""
    model_slug = slug(ctx["model"])
    rel = os.path.join(task.id, model_slug, cond, "rep%d" % rep)
    rdir = os.path.join(ctx["out"], rel)
    if os.path.isfile(os.path.join(rdir, "result.json")):
        return None
    if os.path.isdir(rdir):
        shutil.rmtree(rdir)
    os.makedirs(rdir)
    info = ctx["ctasks"][task.id]
    base = os.path.join(ctx["ws_root"], rel)
    if os.path.exists(base):
        shutil.rmtree(base)
    ws, bin_dir = os.path.join(base, "ws"), os.path.join(base, "bin")
    os.makedirs(bin_dir)
    env = base_env(bin_dir)
    try:
        ctasks.setup_workspace(task, cond, info["sha"], ws, info["builder"], info["starter"],
                               env)
    except Exception as e:  # recorded, the other runs go on
        say("setup failed: %s %s rep%d: %r" % (task.id, cond, rep, e))
        write_json(os.path.join(rdir, "setup-error.json"), {"error": repr(e)})
        return None
    tools = cond == "compiler-tools"
    hook = (ctx["hooks"]["check"], os.path.join(base, "check-hook.jsonl")) if tools else None
    qhook = ctx["hooks"]["query"] if tools else None
    with open(os.path.join(ws, "AGENTS.md")) as fh:  # (the condition's)
        agents_text = fh.read()
    prompt = compiler_prompt(cond, task.text(), agents_text,
                             "compiler-shell.md" if ctx["backend"] == "claude"
                             and claude_backend.PERMS == "allowlist" else None)
    with open(os.path.join(rdir, "prompt.md"), "w") as fh:
        fh.write(prompt)
    say("start %s %s %s rep%d" % (task.id, ctx["model"], cond, rep))
    t0 = time.time()
    try:
        if ctx.get("dry_run"):
            agent = dry_run(ctx, prompt, ws, rdir, hook, qhook)
        elif ctx["backend"] != "claude":
            agent = {"error": "compiler tasks run on the claude backend only", "wall_s": 0}
        else:
            agent = claude_backend.run(prompt, ws, bin_dir, ctx["model_name"], task.timeout_s,
                                       rdir, check_hook=hook, query_hook=qhook)
    except Exception as e:  # a broken backend still leaves a result
        agent = {"error": "runner: %r" % e, "wall_s": round(time.time() - t0, 1)}
    agent["leftover_processes"] = kill_leftovers(ws)
    if hook:
        agent["check_hook"] = check_hook_summary(hook[1])
        if os.path.exists(hook[1]):
            shutil.copyfile(hook[1], os.path.join(rdir, "check-hook.jsonl"))
    qlog = os.path.join(ws, ".git", "agent-tools.jsonl")
    if os.path.exists(qlog):
        shutil.copyfile(qlog, os.path.join(rdir, "agent-tools.jsonl"))
    agent["query_hook"] = query_hook_summary(qlog) if tools else None
    files, adds, dels = ctasks.workspace_changes(ws, os.path.join(rdir, "changes.patch"))
    agent["changes"] = {"files": files, "added": adds, "removed": dels}
    starter_tc = os.path.join(info["starter"], "target", "tachyonc")
    if ctx.get("dry_run"):
        g = {"success": False, "tests_passed": 0, "tests_total": 0, "build_ok": None,
             "check_ok": None, "grade_error": "not graded (--dry-run)"}
    else:
        try:
            g = ctasks.grade(task, ws, os.path.join(base, "grade"), info["builder"], starter_tc)
        except Exception as e:
            g = {"success": False, "tests_passed": 0, "tests_total": 1, "build_ok": False,
                 "check_ok": None, "grade_error": repr(e)}
            agent["error"] = agent.get("error") or "grading: %r" % e
    write_json(os.path.join(rdir, "grade.json"), g)
    res = {
        "task": task.id, "kind": task.kind, "model": ctx["model"], "cond": cond,
        "lang": "compiler", "rep": rep, "success": g["success"],
        "tests_passed": g["tests_passed"], "tests_total": g["tests_total"],
        "build_ok": g["build_ok"], "check_ok": g.get("check_ok"),
        "same_output_ok": g.get("same_output_ok"),
        "grade_summary": ctasks.summary(g) if "suite" in g else g.get("grade_error"),
        "wall_s": None, "turns": None, "tool_calls": None, "tool_calls_by_kind": {},
        "input_tokens": None, "output_tokens": None, "cache_read_tokens": None,
        "cost_usd": None, "error": None, "base": info["ref"], "base_commit": info["sha"],
        "compiler": info["version"],
        "started": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(t0)),
    }
    res.update(agent)
    write_json(os.path.join(rdir, "result.json"), res)
    if not ctx["keep_ws"]:
        shutil.rmtree(base, ignore_errors=True)
    say("done  %s %s %s rep%d: %s %s; %ss, %s turns, %s tool calls, %s in / %s out tokens%s" % (
        task.id, ctx["model"], cond, rep, "OK  " if res["success"] else "FAIL",
        res["grade_summary"], res["wall_s"], res["turns"], res["tool_calls"],
        res["input_tokens"], res["output_tokens"],
        ("; error: " + res["error"]) if res["error"] else ""))
    return res


def dry_run(ctx, prompt, ws, rdir, check_hook, query_hook):
    """--dry-run: no model. Writes the backend's settings and command line
    (settings.json, command.json) and feeds each registered hook a
    synthetic event, matched and run as Claude Code would run it: a Write
    adding an error to a .tach file (PostToolUse: the check hook reports
    it) and, for the query hook, a `grep` of a .tach file (PreToolUse:
    blocked). Proof that the hooks load and fire (result.json's dry_run)."""
    settings = claude_backend.settings(private_paths(), check_hook and check_hook[0], query_hook)
    write_json(os.path.join(rdir, "settings.json"), settings)
    argv = claude_backend.command("(prompt.md)", ctx["model_name"],
                                  check_hook and check_hook[0], query_hook)
    write_json(os.path.join(rdir, "command.json"), argv)
    hooks = settings.get("hooks", {})
    out = {"hooks_registered": {ev: [h["matcher"] for h in hs] for ev, hs in hooks.items()}}
    env = claude_backend.env(os.path.join(os.path.dirname(ws), "bin"))
    if check_hook:
        env["TACHYON_CHECK_HOOK_LOG"] = check_hook[1]

    def fire(event, ev):
        got = []
        for h in hooks.get(ev, []):
            if not re.fullmatch(h["matcher"], event["tool_name"]):
                continue
            for c in h["hooks"]:
                p = subprocess.run(c["command"], shell=True, cwd=ws, env=env,
                                   input=json.dumps(dict(event, hook_event_name=ev, cwd=ws)),
                                   capture_output=True, text=True, timeout=120)
                got.append({"hook": os.path.basename(c["command"].split()[-1].strip("'")),
                            "exit": p.returncode, "stdout": p.stdout[:600],
                            "stderr": p.stderr[:600]})
        return got

    probe = None
    for cand in ("compiler/src/main.tach", "main.tach"):
        if os.path.isfile(os.path.join(ws, cand)):
            probe = os.path.join(ws, cand)
            break
    if probe:
        with open(probe) as fh:
            saved = fh.read()
        with open(probe, "a") as fh:
            fh.write("\nfn eval_dry_run_probe() -> i64 { return undefined_name_xyz; }\n")
        try:
            out["post_write"] = fire({"tool_name": "Write", "session_id": "dry-run",
                                      "tool_input": {"file_path": probe, "content": "..."},
                                      "tool_response": {}}, "PostToolUse")
        finally:
            with open(probe, "w") as fh:
                fh.write(saved)
        out["pre_grep"] = fire({"tool_name": "Bash", "session_id": "dry-run",
                                "tool_input": {"command": "grep -n main "
                                               + os.path.relpath(probe, ws)}},
                               "PreToolUse")
    return {"error": None, "wall_s": 0.0, "dry_run": out}


def main(args):
    backend, model_name = parse_model(args.model)
    claude_backend.PERMS = args.claude_permissions
    conds = [c for c in args.cond.split(",") if c]
    bad = [c for c in conds if c not in ALL_CONDS]
    if bad or not conds:
        raise SystemExit("--cond takes %s; got %s" % (",".join(ALL_CONDS), args.cond))
    tasks = load_tasks(args.tasks_dir, args.tasks.split(",") if args.tasks else None,
                       args.set)
    out = os.path.abspath(args.out or os.path.join(
        DEFAULT_RESULTS_DIR, time.strftime("%Y%m%d-%H%M%S")))
    os.makedirs(out, exist_ok=True)
    ws_root = os.path.realpath(args.ws_root or os.path.join(
        os.environ.get("TMPDIR", "/tmp"), "tachyon-eval", os.path.basename(out)))
    repo = os.path.realpath(REPO_ROOT)
    if ws_root == repo or ws_root.startswith(repo + os.sep):
        raise SystemExit("workspaces must be outside the repository: %s" % ws_root)
    os.makedirs(ws_root, exist_ok=True)
    jobs = [(t, c, r) for r in range(1, args.reps + 1) for t in tasks for c in conds
            if fits(t, c)]
    if not jobs:
        raise SystemExit("no task fits the conditions: compiler tasks (--set compiler) run "
                         "in %s, program tasks in the others" % ",".join(COMPILER_CONDS))
    bins = prepare_bins(ws_root, os.path.abspath(args.tachyonc))
    ctx = {"model": args.model, "backend": backend, "model_name": model_name,
           "out": out, "ws_root": ws_root, "bins": bins,
           "keep_ws": args.keep_workspaces or args.dry_run, "dry_run": args.dry_run,
           "check_hook": args.check_hook, "hooks": install_hooks(ws_root),
           "versions": {"tach": tool_version(bins["tach"], "tach"),
                        "rust": tool_version(bins["rust"], "rust")}}
    # (0.16) compiler tasks: the base, its builder and the starter's
    # compiler, built once per task (cached under the workspaces' root)
    ctx["ctasks"] = {}
    for t in {j[0].id: j[0] for j in jobs if j[0].is_compiler}.values():
        ref, sha = ctasks.resolve_base(t, args.base)
        builder = ctasks.builder_for(sha, args.builder)
        say("%s: base %s (%s), building the starter" % (t.id, ref, sha[:12]))
        st = ctasks.built_tree(t, sha, builder, ws_root)
        ctx["ctasks"][t.id] = {"ref": ref, "sha": sha, "builder": builder, "starter": st,
                               "version": tool_version(os.path.join(st, "target"), "tach")}
    if any(c in ("guide", "both") for c in conds):
        ctx["guide"] = guide_text(bins["tach"])
    runs_meta = os.path.join(out, "runs.jsonl")
    with open(runs_meta, "a") as fh:
        fh.write(json.dumps({
            "date": time.strftime("%Y-%m-%dT%H:%M:%S"), "model": args.model,
            "conds": conds, "tasks": [t.id for t in tasks], "reps": args.reps,
            "claude_permissions": args.claude_permissions,
            "check_hook": bool(args.check_hook), "dry_run": bool(args.dry_run),
            "ctasks": {k: {"base": v["ref"], "commit": v["sha"], "builder": v["builder"]}
                       for k, v in ctx["ctasks"].items()},
            "tachyonc": os.path.abspath(args.tachyonc),
            "versions": ctx["versions"], "ws_root": ws_root}) + "\n")
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
