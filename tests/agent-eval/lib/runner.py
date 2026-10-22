"""`run.py run`: every (task, condition, rep) in a fresh workspace, the
agent, then the grading; one result.json per run, resumable."""

import hashlib
import json
import os
import re
import shutil
import subprocess
import tarfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from lib import anatomy, claude_backend, conds, ctasks, debrief, ollama_backend, selfcheck
from lib.common import (DEFAULT_RESULTS_DIR, REPO_ROOT, base_env, check_hook_summary,
                        copy_tree, eval_settings_hooks, final_check, install_hooks,
                        install_mktemp_shim, kill_leftovers, load_tasks, private_paths,
                        query_hook_summary, write_json)
from lib.grade import grade_dir, prepare_bins, tool_version
from lib.prompts import build_prompt, compiler_prompt, guide_text, guide_topic

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
    return task.is_compiler == conds.Cond(cond).is_compiler


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
    c = conds.Cond(cond)
    lang = c.lang
    base = os.path.join(ctx["ws_root"], rel)
    ws, bin_dir = program_workspace(ctx, task, lang, base)

    # (--check-hook) the tools and both conditions, (0.17) +hook and +test
    # in any: check after each change
    hook = ((ctx["hooks"]["check"], os.path.join(base, "check-hook.jsonl"))
            if lang == "tach" and (c.check_hook(ctx.get("check_hook")) or c.turn_end) else None)
    extra = eval_hooks(ctx, c.settings_key(ctx.get("check_hook")), c.hook_mods) \
        if lang == "tach" else None
    env_note = ("claude-env.md" if ctx["backend"] == "claude"
                and claude_backend.PERMS == "allowlist" else None)
    prompt = build_prompt(c, task.text(), ctx.get("guide"), env_note=env_note,
                          check_hook=bool(hook), guide_core=ctx.get("guide_core"),
                          guide_example=ctx.get("guide_example"))
    with open(os.path.join(rdir, "prompt.md"), "w") as fh:
        fh.write(prompt)
    db_text, snap, on_done = debrief_setup(c, ws, base, rdir)
    backend, name = ctx["backend"], ctx["model_name"]
    say("start %s %s %s rep%d" % (task.id, ctx["model"], cond, rep))
    t0 = time.time()
    try:
        mod = claude_backend if backend == "claude" else ollama_backend
        if ctx.get("dry_run"):
            agent = dry_run(ctx, prompt, ws, rdir, hook, None, extra, debrief=db_text)
        elif backend == "claude":
            agent = mod.run(prompt, ws, bin_dir, name, task.timeout_s, rdir, check_hook=hook,
                            extra_hooks=extra, tee=ctx["hooks"]["tee"], debrief=db_text,
                            on_task_done=on_done)
        else:
            agent = mod.run(prompt, ws, bin_dir, name, task.timeout_s, rdir, check_hook=hook)
    except Exception as e:  # a broken backend still leaves a result
        agent = {"error": "runner: %r" % e, "wall_s": round(time.time() - t0, 1)}
    agent["leftover_processes"] = kill_leftovers(ws)
    debrief_restore(ws, snap, agent)
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
        # (0.18) the binary the run had, for run.py binaudit
        "volec_md5": ctx.get("tach_md5") if lang == "tach" else None,
        "ws_root": ctx["ws_root"],
        "started": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(t0)),
    }
    res.update(agent)
    # (0.17) the run's anatomy: calls by role, errors by class, Rust habits,
    # tool n-grams, edit recovery, intent erosion (lib/anatomy.py)
    res["anatomy"] = anatomy.safe_for_run(rdir, res, starter=os.path.join(task.path, lang),
                                          final=ws)
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
    install_mktemp_shim(bin_dir)
    env = base_env(bin_dir)
    try:
        ctasks.setup_workspace(task, cond, info["sha"], ws, info["builder"], info["starter"],
                               env, tools_volec=ctx.get("tools_volec"))
    except Exception as e:  # recorded, the other runs go on
        say("setup failed: %s %s rep%d: %r" % (task.id, cond, rep, e))
        write_json(os.path.join(rdir, "setup-error.json"), {"error": repr(e)})
        return None
    c = conds.Cond(cond)
    tools = c.query_hook
    hook = (ctx["hooks"]["check"], os.path.join(base, "check-hook.jsonl")) if tools else None
    # (E3, E6) with +rewrite or +nohints the query-first hook comes from
    # settings-eval.json too, with the modifiers' environment
    qhook = ctx["hooks"]["query"] if tools and not c.hook_mods else None
    extra = eval_hooks(ctx, c.settings_key(), c.hook_mods, query=bool(c.hook_mods)) if tools else None
    with open(os.path.join(ws, "AGENTS.md")) as fh:  # (the condition's)
        agents_text = fh.read()
    prompt = compiler_prompt(cond, task.text(), agents_text,
                             "compiler-shell.md" if ctx["backend"] == "claude"
                             and claude_backend.PERMS == "allowlist" else None)
    with open(os.path.join(rdir, "prompt.md"), "w") as fh:
        fh.write(prompt)
    db_text, snap, on_done = debrief_setup(c, ws, base, rdir)
    say("start %s %s %s rep%d" % (task.id, ctx["model"], cond, rep))
    t0 = time.time()
    try:
        if ctx.get("dry_run"):
            agent = dry_run(ctx, prompt, ws, rdir, hook, qhook, extra, debrief=db_text)
        elif ctx["backend"] != "claude":
            agent = {"error": "compiler tasks run on the claude backend only", "wall_s": 0}
        else:
            agent = claude_backend.run(prompt, ws, bin_dir, ctx["model_name"], task.timeout_s,
                                       rdir, check_hook=hook, query_hook=qhook,
                                       extra_hooks=extra, tee=ctx["hooks"]["tee"],
                                       debrief=db_text, on_task_done=on_done)
    except Exception as e:  # a broken backend still leaves a result
        agent = {"error": "runner: %r" % e, "wall_s": round(time.time() - t0, 1)}
    agent["leftover_processes"] = kill_leftovers(ws)
    debrief_restore(ws, snap, agent)
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
    starter_tc = os.path.join(info["starter"], "target", "volec")
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
    res["anatomy"] = anatomy.safe_for_run(rdir, res)
    write_json(os.path.join(rdir, "result.json"), res)
    if not ctx["keep_ws"]:
        shutil.rmtree(base, ignore_errors=True)
    say("done  %s %s %s rep%d: %s %s; %ss, %s turns, %s tool calls, %s in / %s out tokens%s" % (
        task.id, ctx["model"], cond, rep, "OK  " if res["success"] else "FAIL",
        res["grade_summary"], res["wall_s"], res["turns"], res["tool_calls"],
        res["input_tokens"], res["output_tokens"],
        ("; error: " + res["error"]) if res["error"] else ""))
    return res


def debrief_setup(c, ws, base, rdir):
    """(0.18, +debrief) The debrief's text (also rdir/debrief-prompt.md),
    where the workspace's snapshot goes, and the callback that takes it
    when the task's turn ends; (None, None, None) without +debrief."""
    if not c.debrief:
        return None, None, None
    text = debrief.prompt_for(c)
    with open(os.path.join(rdir, "debrief-prompt.md"), "w") as fh:
        fh.write(text + "\n")
    snap = os.path.join(base, "ws.task-end")
    return text, snap, lambda: debrief.snapshot(ws, snap)


def debrief_restore(ws, snap, agent):
    """(0.18) The workspace as the task left it, before the grading: the
    snapshot taken when the task's turn ended replaces what the debrief
    turn may have changed."""
    if snap and os.path.isdir(snap):
        try:
            debrief.restore(ws, snap)
            (agent.get("debrief") or {})["restored"] = True
        except OSError as e:
            agent["error"] = agent.get("error") or "debrief restore: %r" % e


def eval_hooks(ctx, key, mods=(), query=False):
    """(0.17) The hooks of settings-eval.json's condition `key` (None: no
    check or Stop hook), pointed at the copies; cached in ctx. None when
    the file does not exist (the conditions needing it refuse to run:
    conds.Cond.needs), when the harness's own check hook is used instead.
    (E3, E5, E6) mods: the condition's +rewrite, +nohints, +note (the
    file's `modifiers`); query: the query-first hook from the file too."""
    if key is None and not mods:
        return None
    cache = ctx.setdefault("eval_hooks", {})
    ck = (key, tuple(mods), query)
    if ck not in cache:
        cache[ck] = eval_settings_hooks(conds.SETTINGS_EVAL, ctx["hooks"]["dir"], key,
                                        mods=mods, query=query)
    return cache[ck]


def dry_run(ctx, prompt, ws, rdir, check_hook, query_hook, extra_hooks=None, debrief=None):
    """--dry-run: no model. Writes the backend's settings and command line
    (settings.json, command.json) and feeds each registered hook a
    synthetic event, matched and run as Claude Code would run it: a Write
    adding an error to a .vl file (PostToolUse: the check hook reports
    it) and, for the query hook, a `grep` of a .vl file (PreToolUse:
    blocked). Proof that the hooks load and fire (result.json's dry_run)."""
    tee = ctx["hooks"]["tee"]
    settings = claude_backend.settings(private_paths(), check_hook and check_hook[0], query_hook,
                                       extra_hooks, tee)
    write_json(os.path.join(rdir, "settings.json"), settings)
    argv = claude_backend.command("(prompt.md)", ctx["model_name"],
                                  check_hook and check_hook[0], query_hook, extra_hooks, tee,
                                  stream_input=debrief is not None)
    write_json(os.path.join(rdir, "command.json"), argv)
    hooks = settings.get("hooks", {})
    out = {"hooks_registered": {ev: [h.get("matcher", "*") for h in hs] for ev, hs in hooks.items()}}
    if debrief is not None:
        # (0.18) the two stdin messages the session would get
        out["debrief"] = {"stdin": [claude_backend.user_message("(prompt.md)").strip(),
                                    claude_backend.user_message(debrief).strip()[:200]]}
    env = claude_backend.env(os.path.join(os.path.dirname(ws), "bin"))
    if check_hook:
        env["VOLE_CHECK_HOOK_LOG"] = check_hook[1]
    env["EVAL_HOOK_OUTPUT_LOG"] = os.path.join(rdir, "hook-output.jsonl")

    def fire(event, ev):
        got = []
        for h in hooks.get(ev, []):
            if h.get("matcher") and not re.fullmatch(h["matcher"], event.get("tool_name", "")):
                continue
            for c in h["hooks"]:
                p = subprocess.run(c["command"], shell=True, cwd=ws, env=env,
                                   input=json.dumps(dict(event, hook_event_name=ev, cwd=ws)),
                                   capture_output=True, text=True, timeout=120)
                words = [w.strip("'\"") for w in c["command"].split()]
                got.append({"hook": next((os.path.basename(w) for w in reversed(words)
                                          if w.endswith(".py") and "hook-tee" not in w), "?"),
                            "exit": p.returncode, "stdout": p.stdout[:600],
                            "stderr": p.stderr[:600]})
        return got

    # (0.17) a session id of its own: the hooks keep state per session
    # ($TMPDIR/vole-agent-hooks), and a fixed id made a second dry run at
    # the same paths see the first one's errors "as before"
    sid = "dry-run-%d-%d" % (os.getpid(), int(time.time() * 1000))
    probe = None
    for cand in ("compiler/src/main.vl", "main.vl"):
        if os.path.isfile(os.path.join(ws, cand)):
            probe = os.path.join(ws, cand)
            break
    if probe:
        with open(probe) as fh:
            saved = fh.read()
        with open(probe, "a") as fh:
            fh.write("\nfn eval_dry_run_probe() -> i64 { return undefined_name_xyz; }\n")
        try:
            out["post_write"] = fire({"tool_name": "Write", "session_id": sid,
                                      "tool_input": {"file_path": probe, "content": "..."},
                                      "tool_response": {}}, "PostToolUse")
            # (0.17) the Stop hook with the error still there: it blocks
            if hooks.get("Stop"):
                out["stop"] = fire({"session_id": sid, "stop_hook_active": False}, "Stop")
        finally:
            with open(probe, "w") as fh:
                fh.write(saved)
        out["pre_grep"] = fire({"tool_name": "Bash", "session_id": sid,
                                "tool_input": {"command": "grep -n main "
                                               + os.path.relpath(probe, ws)}},
                               "PreToolUse")
    return {"error": None, "wall_s": 0.0, "dry_run": out}


def file_md5(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def program_workspace(ctx, task, lang, base):
    """A program run's workspace under `base`: bin/ with the compiler (or
    rustc) and the mktemp shim, ws/ with the starter and one git commit.
    (ws, bin_dir)."""
    if os.path.exists(base):
        shutil.rmtree(base)
    ws, bin_dir = os.path.join(base, "ws"), os.path.join(base, "bin")
    os.makedirs(bin_dir)
    tool = "volec" if lang == "tach" else "rustc"
    os.symlink(os.path.join(ctx["bins"][lang], tool), os.path.join(bin_dir, tool))
    install_mktemp_shim(bin_dir)
    copy_tree(os.path.join(task.path, lang), ws)
    git_init(ws, base_env(bin_dir))
    return ws, bin_dir


def main(args):
    backend, model_name = parse_model(args.model)
    claude_backend.PERMS = args.claude_permissions
    try:
        cs = conds.parse_list(args.cond)
    except ValueError as e:
        raise SystemExit("--cond: %s (%s)" % (e, conds.help_text()))
    if not cs:
        raise SystemExit("--cond takes %s" % conds.help_text())
    names = [c.name for c in cs]
    if backend != "claude" and any(c.debrief for c in cs):
        raise SystemExit("--cond: +debrief runs on the claude backend only")
    missing = [(c.name, f, what) for c in cs for f, what in c.needs()]
    if missing and not args.dry_run:
        raise SystemExit("not yet runnable (a dry run works with a stub):\n" + "\n".join(
            "  %s needs %s: %s" % m for m in missing))
    tasks = load_tasks(args.tasks_dir, args.tasks.split(",") if args.tasks else None,
                       args.set)
    out = os.path.abspath(args.out or os.path.join(
        DEFAULT_RESULTS_DIR, time.strftime("%Y%m%d-%H%M%S")))
    os.makedirs(out, exist_ok=True)
    # (0.17 iterations) the default root is named by the run's whole --out
    # path, not its last part: two runs with --out .../a/claude-haiku and
    # .../b/claude-haiku shared a root, its compiler copy and hooks
    ws_root = os.path.realpath(args.ws_root or os.path.join(
        os.environ.get("TMPDIR", "/tmp"), "vole-eval", "%s-%s" % (
            os.path.basename(out), hashlib.sha1(os.path.abspath(out).encode()).hexdigest()[:8])))
    repo = os.path.realpath(REPO_ROOT)
    if ws_root == repo or ws_root.startswith(repo + os.sep):
        raise SystemExit("workspaces must be outside the repository: %s" % ws_root)
    os.makedirs(ws_root, exist_ok=True)
    jobs = [(t, c, r) for r in range(1, args.reps + 1) for t in tasks for c in names
            if fits(t, c)]
    if not jobs:
        raise SystemExit("no task fits the conditions: compiler tasks (--set compiler) run "
                         "in the compiler-* conditions, program tasks in the others")
    bins = prepare_bins(ws_root, os.path.abspath(args.volec))
    tach_md5 = file_md5(os.path.join(bins["tach"], "volec"))
    hooks = install_hooks(ws_root)
    ctx = {"model": args.model, "backend": backend, "model_name": model_name,
           "out": out, "ws_root": ws_root, "bins": bins,
           "keep_ws": args.keep_workspaces or args.dry_run, "dry_run": args.dry_run,
           "check_hook": args.check_hook, "hooks": hooks, "tach_md5": tach_md5,
           "tools_volec": os.path.abspath(args.tools_volec)
           if getattr(args, "tools_volec", None) else None,
           "versions": {"tach": tool_version(bins["tach"], "tach"),
                        "rust": tool_version(bins["rust"], "rust")}}
    # (0.17) every condition's hooks from settings-eval.json, checked now
    for c in cs:
        eval_hooks(ctx, c.settings_key(args.check_hook) if not c.is_compiler else c.settings_key(),
                   c.hook_mods, query=c.query_hook and bool(c.hook_mods))
    # (0.16) compiler tasks: the base, its builder and the starter's
    # compiler, built once per task (cached under the workspaces' root)
    ctx["ctasks"] = {}
    for t in {j[0].id: j[0] for j in jobs if j[0].is_compiler}.values():
        ref, sha = ctasks.resolve_base(t, args.base)
        builder = ctasks.builder_for(sha, args.builder)
        say("%s: base %s (%s), building the starter" % (t.id, ref, sha[:12]))
        st = ctasks.built_tree(t, sha, builder, os.path.dirname(ws_root))  # cached by commit, shared
        ctx["ctasks"][t.id] = {"ref": ref, "sha": sha, "builder": builder, "starter": st,
                               "version": tool_version(os.path.join(st, "target"), "tach")}
    if any(c.guide == "full" for c in cs):
        ctx["guide"] = guide_text(bins["tach"], "full")
    if any(c.guide == "core" for c in cs):
        try:
            ctx["guide_core"] = guide_text(bins["tach"], "core")
        except SystemExit as e:
            if not args.dry_run:
                raise
            say("dry run: %s; a stub stands in" % e)
    if any(c.guide == "example" for c in cs):
        try:
            ctx["guide_example"] = guide_topic(bins["tach"], "example")
        except SystemExit as e:
            if not args.dry_run:
                raise
            say("dry run: %s; a stub stands in" % e)
    def have(d, j):
        return os.path.isfile(os.path.join(d, j[0].id, slug(args.model), j[1],
                                           "rep%d" % j[2], "result.json"))
    reuse = [os.path.abspath(d) for d in getattr(args, "skip_existing_in", None) or []]
    reused = [j for j in jobs if any(have(d, j) for d in reuse)]
    if reused:
        say("%d runs reused from %s" % (len(reused), ", ".join(reuse)))
    jobs = [j for j in jobs if j not in reused]
    todo = [j for j in jobs if not have(out, j)]
    # (0.17) the self-check: the agents can build, run, test and write in
    # their workspaces, inside the sandbox; the round stops if not
    sc = None
    mode = getattr(args, "selfcheck", "auto")
    if mode != "none" and not args.dry_run and todo:
        sc = selfcheck.before_round(ctx, jobs, args, mode)
        if not sc["ok"]:
            raise SystemExit("self-check failed, the round does not start: %s (details: %s)"
                             % ("; ".join(sc["failed"][:6]), sc.get("path")))
    runs_meta = os.path.join(out, "runs.jsonl")
    with open(runs_meta, "a") as fh:
        fh.write(json.dumps({
            "date": time.strftime("%Y-%m-%dT%H:%M:%S"), "model": args.model,
            "conds": names, "tasks": [t.id for t in tasks], "reps": args.reps,
            "claude_permissions": args.claude_permissions,
            "allow_rules": len(claude_backend.ALLOW) + len(claude_backend.ALLOW_PATTERNS),
            "check_hook": bool(args.check_hook), "dry_run": bool(args.dry_run),
            "selfcheck": sc and {k: sc.get(k) for k in ("ok", "mode", "path", "refusals")},
            "ctasks": {k: {"base": v["ref"], "commit": v["sha"], "builder": v["builder"]}
                       for k, v in ctx["ctasks"].items()},
            "volec": os.path.abspath(args.volec), "volec_md5": tach_md5,
            "tools_volec": ctx["tools_volec"],
            "versions": ctx["versions"], "ws_root": ws_root}) + "\n")
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
