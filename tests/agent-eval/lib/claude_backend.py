"""The hosted backend: Claude Code in print mode, isolated from this
machine's configuration.

Isolation (verified on a dev run, see README.md):
- the environment is rebuilt from scratch (lib.common.base_env): no
  CLAUDE_* variables of a calling session, PATH = the run's bin dir and
  the system directories (tachyonc for tachyon, rustc for Rust);
- `--setting-sources ""`: no user, project or local settings, so no hooks,
  plugins, permissions or model settings of this machine; the settings the
  run needs come from `--settings`;
- `--strict-mcp-config --mcp-config '{"mcpServers":{}}'`: no MCP servers
  (also none of the account's connectors);
- `--disable-slash-commands`: no skills; auto-memory off by environment;
  `--no-session-persistence`: nothing saved for resume;
- the workspace is outside the repository, so no CLAUDE.md or AGENTS.md
  is found walking up from it;
- `--tools` limits the built-in tools to Read, Write, Edit, Glob, Grep,
  Bash (no Agent, WebFetch, WebSearch).

Permissions without prompts: `--permission-mode acceptEdits` (file edits
inside the workspace), Bash runs in Claude Code's sandbox (writes only in
the workspace and temp, no network, the repository and ~/.claude
unreadable) and is auto-allowed there; anything else is denied at once
(`--permission-prompts none`) and recorded as a permission denial."""

import json
import os
import shlex
import shutil
import subprocess
import time
from collections import Counter

from lib.common import base_env, kill_group, private_paths
from lib.toolkinds import classify_call

TOOLS = "Read,Write,Edit,Glob,Grep,Bash"


# Commands a programmer runs; Bash runs in the sandbox anyway, and a
# command outside this list is still auto-allowed there unless Claude Code
# itself asks for approval (shell variables, or commands it does not know,
# such as `tachyonc edit`): the list covers those. Claude Code splits a
# compound line at && || ; | and newlines and wants every part allowed,
# so every command an agent chains must be here.
ALLOW = ["tachyonc", "rustc", "./prog", "prog", "cat", "ls", "echo", "printf",
         "head", "tail", "grep", "sed", "awk", "diff", "cmp", "wc", "sort",
         "uniq", "tr", "cut", "mkdir", "cp", "mv", "rm", "touch", "find",
         "python3", "time", "timeout", "test", "true", "false", "cd", "pwd",
         "which", "seq", "xxd", "od", "git", "sh", "bash", "chmod", "tee",
         "env", "file", "stat", "du",
         # (0.16) the compiler tasks
         "target/tachyonc", "target/tools/tachyonc", "./target/tachyonc",
         "bootstrap/eval-build.sh", "./bootstrap/eval-build.sh", "tests/run.sh",
         "./tests/run.sh", "tools/agent-feedback", "cc", "xargs", "cmp", "basename",
         "dirname", "date", "sleep",
         # (0.17) widened from the 0.16 round's denials (461 of 7,872 calls): what agents chained
         # with the commands above (every part of a chain must be allowed);
         # all of it runs in the sandbox (writes only in the workspace and
         # temp, no network)
         "./target/tools/tachyonc", "compiler/std/embed.sh", "./compiler/std/embed.sh",
         "compiler/guide/embed.sh", "./compiler/guide/embed.sh", "tools/agent-feedback",
         "perl", "patch", "paste", "join", "comm", "column", "fold", "rev", "split",
         "nl", "expr", "bc", "tar", "gzip", "gunzip", "shasum", "md5", "base64",
         "hexdump", "strings", "nm", "otool", "realpath", "readlink", "type",
         "command", "ulimit", "nproc", "sysctl", "clang", "gcc", "make", "zsh",
         "export", "set", "[", "/usr/bin/time", "mktemp", "jot", "yes", "less",
         "ln", "rmdir",
         "printenv"]
# Programs the agent built in its workspace (`./prog_dbg`, `./t0`,
# `./new_prog`, a script `./gen.py`): any `./NAME`, in the sandbox.
ALLOW_PATTERNS = ["Bash(./*)",
                  # (0.17) the one form the self-check still saw refused
                  # (2026-10-15, Haiku): a loop. Unverified whether a rule
                  # can pass it; the next self-check measures it.
                  "Bash(for *)", "Bash(while *)", "Bash(until *)"]


# "allowlist" (the default): acceptEdits + the sandbox's auto-allow + ALLOW;
# Claude Code still asks (so denies) before command lines it cannot check
# statically: shell variables, `$?`, subshells. "bypass": no prompts at
# all; the sandbox still confines Bash, deny rules still hold (and an Edit
# deny rule for the home directory keeps the file tools out of it). (0.17)
# The rounds use the allowlist; bypass is not used (a machine safety check
# refuses it), and the denials are measured instead (lib/anatomy.py, the
# self-check's probes).
PERMS = "allowlist"


def sandbox_tmp_dirs():
    """Claude Code's sandbox temp directory (/tmp/claude-UID, where Bash's
    $TMPDIR points inside the sandbox) under both its spellings: the file
    tools need an Edit rule to write there (the 0.16 round: 60-odd Write
    calls to /tmp/claude-501/... denied), as Bash already may."""
    d = "/tmp/claude-%d" % os.getuid()
    return [d, "/private" + d]


def edit_allow_rules():
    """(0.17) Edit allow rules (they cover Write and MultiEdit too) for the
    sandbox's temp directory."""
    return ["Edit(/%s/**)" % d for d in sandbox_tmp_dirs()]


def hook_command(script, tee=None):
    """A hook's command line; with `tee` (lib/hook-tee.py's copy) the hook
    runs under the wrapper that logs what it returned."""
    if tee:
        return {"type": "command", "command": "/usr/bin/python3 -I %s %s"
                % (shlex.quote(tee), shlex.quote(script))}
    return {"type": "command", "command": "/usr/bin/python3 -I " + shlex.quote(script)}


def _tee_entry(h, tee):
    if not tee or h.get("type", "command") != "command" or not h.get("command"):
        return h
    return dict(h, command="/usr/bin/python3 -I %s --sh %s"
                % (shlex.quote(tee), shlex.quote(h["command"])))


def hooks_for(check_hook=None, query_hook=None, extra=None, tee=None):
    """The `hooks` of --settings: (--check-hook, +hook, compiler-tools)
    `tachyonc check` after every change to a .tach file, its errors added
    to the tool result; (compiler-tools) the query-first hook before and
    after tool calls, as .claude/settings.json registers it in the
    repository; (0.17, +test) `extra`: the hooks of settings-eval.json
    instead of the check hook. Hooks run outside the sandbox; the scripts
    are copies outside the repository (lib/common.install_hooks). With
    `tee`, every hook runs under lib/hook-tee.py (its output logged)."""
    pre, post = [], []
    if query_hook:
        pre.append({"matcher": "Bash|Read|Grep|Edit|Write|MultiEdit",
                    "hooks": [hook_command(query_hook, tee)]})
        post.append({"matcher": "Bash", "hooks": [hook_command(query_hook, tee)]})
    if check_hook and not extra:
        post.append({"matcher": "Write|Edit|MultiEdit|Bash",
                     "hooks": [hook_command(check_hook, tee)]})
    hooks = {}
    if pre:
        hooks["PreToolUse"] = pre
    if post:
        hooks["PostToolUse"] = post
    for ev, entries in (extra or {}).items():
        for e in entries:
            hooks.setdefault(ev, []).append(
                dict(e, hooks=[_tee_entry(h, tee) for h in e.get("hooks") or []]))
    return hooks


def settings(deny_read, check_hook=None, query_hook=None, extra_hooks=None, tee=None):
    home = os.path.realpath(os.path.expanduser("~"))
    deny = ["Read(/%s/**)" % p for p in deny_read]
    if PERMS == "bypass":
        deny.append("Edit(/%s/**)" % home)
    extra = {}
    hooks = hooks_for(check_hook, query_hook, extra_hooks, tee)
    if hooks:
        extra["hooks"] = hooks
    return {
        **extra,
        "sandbox": {
            "enabled": True,
            "autoAllowBashIfSandboxed": True,
            "allowUnsandboxedCommands": False,
            "filesystem": {"denyRead": deny_read},
        },
        "permissions": {
            "allow": (["Bash(%s:*)" % c for c in dict.fromkeys(ALLOW)] + ALLOW_PATTERNS
                      + edit_allow_rules()),
            "deny": deny,
        },
    }


def command(prompt, model, check_hook=None, query_hook=None, extra_hooks=None, tee=None,
            stream_input=False):
    """The command line. stream_input (0.18, +debrief): the prompt comes on
    stdin as a stream-json user message instead of the argument, so that
    the same session can be asked a second message (the debrief); the
    model sees the same first message either way."""
    claude = shutil.which("claude")
    if not claude:
        raise SystemExit("claude not found on PATH")
    head = ([claude, "-p", "--input-format", "stream-json"] if stream_input
            else [claude, "-p", prompt])
    return head + [
        "--model", model,
        "--output-format", "stream-json", "--verbose",
        "--setting-sources", "",
        "--settings", json.dumps(settings(private_paths(), check_hook, query_hook,
                                          extra_hooks, tee)),
        "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
        "--tools", TOOLS,
        "--permission-mode", "bypassPermissions" if PERMS == "bypass" else "acceptEdits",
        "--permission-prompts", "none",
        "--no-session-persistence",
        "--disable-slash-commands",
    ]


def env(bin_dir):
    e = base_env(bin_dir)
    e["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
    e["DISABLE_AUTOUPDATER"] = "1"
    e["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
    return e


def run(prompt, ws, bin_dir, model, timeout_s, rdir, check_hook=None, query_hook=None,
        extra_hooks=None, tee=None, debrief=None, on_task_done=None):
    """Runs the agent in `ws`; the stream goes to rdir/transcript.jsonl.
    Returns the agent's half of result.json. check_hook: (the hook
    script, its log) for --check-hook and compiler-tools, or None;
    query_hook: the query-first hook script (compiler-tools), or None;
    (0.17) extra_hooks: settings-eval.json's hooks (+test); tee: the
    hook-tee.py copy, whose log is rdir/hook-output.jsonl. (0.18,
    +debrief) debrief: a second message for the same session once the
    task's turn has ended (lib/debrief.py); on_task_done() runs between
    the two (the runner snapshots the workspace there)."""
    if debrief is not None:
        return _run_with_debrief(prompt, ws, bin_dir, model, timeout_s, rdir, check_hook,
                                 query_hook, extra_hooks, tee, debrief, on_task_done)
    tpath = os.path.join(rdir, "transcript.jsonl")
    epath = os.path.join(rdir, "agent.stderr")
    t0 = time.time()
    timed_out = False
    with open(tpath, "wb") as out, open(epath, "wb") as err:
        e = _env(bin_dir, rdir, check_hook, tee)
        argv = command(prompt, model, check_hook and check_hook[0], query_hook, extra_hooks, tee)
        with open(os.path.join(rdir, "command.json"), "w") as fh:
            json.dump(argv[:2] + ["(prompt.md)"] + argv[3:], fh, indent=1)
        p = subprocess.Popen(argv, cwd=ws, env=e,
                             stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                             start_new_session=True)
        try:
            p.wait(timeout=timeout_s)
        except subprocess.TimeoutExpired:
            timed_out = True
            kill_group(p)
            p.wait()
    wall = time.time() - t0
    res = parse_stream(tpath)
    res["wall_s"] = round(wall, 1)
    res["exit_code"] = p.returncode
    if timed_out:
        res["error"] = "timeout after %ds" % timeout_s
    elif res.get("error") is None and p.returncode != 0:
        with open(epath, "rb") as fh:
            res["error"] = "claude exited %d: %s" % (
                p.returncode, fh.read()[-300:].decode("utf-8", "replace"))
    return res


def _env(bin_dir, rdir, check_hook, tee):
    e = env(bin_dir)
    if check_hook:
        e["TACHYON_CHECK_HOOK_LOG"] = check_hook[1]
    if tee:
        e["EVAL_HOOK_OUTPUT_LOG"] = os.path.join(rdir, "hook-output.jsonl")
    return e


# (0.18, +debrief) how long the debrief turn may take, and how long the
# stream must be quiet after the task's result before it is sent (a
# background command finishing then starts another turn of the task)
DEBRIEF_TIMEOUT_S = 240
QUIET_S = 3.0


def user_message(text):
    return json.dumps({"type": "user", "message": {"role": "user", "content": text}}) + "\n"


def _run_with_debrief(prompt, ws, bin_dir, model, timeout_s, rdir, check_hook, query_hook,
                      extra_hooks, tee, debrief, on_task_done):
    """The task as run() runs it, but its prompt sent on stdin (stream-json);
    when the task's turn ends (a `result` event, then QUIET_S without
    output), on_task_done(), then the debrief as a second user message of
    the same session, whose events go to rdir/debrief.jsonl. The task's
    half of result.json comes from transcript.jsonl alone, as without
    the debrief; the debrief's (its answer, cost, tokens) is
    res["debrief"]. A task that times out or dies gets no debrief."""
    import queue
    import threading
    tpath = os.path.join(rdir, "transcript.jsonl")
    dpath = os.path.join(rdir, "debrief.jsonl")
    epath = os.path.join(rdir, "agent.stderr")
    t0 = time.time()
    timed_out = False
    debrief_out = {"sent": False}
    lines = queue.Queue()

    def reader(stream):
        for raw in iter(stream.readline, b""):
            lines.put(raw)
        lines.put(None)

    with open(tpath, "wb") as out, open(epath, "wb") as err:
        e = _env(bin_dir, rdir, check_hook, tee)
        argv = command(prompt, model, check_hook and check_hook[0], query_hook, extra_hooks, tee,
                       stream_input=True)
        with open(os.path.join(rdir, "command.json"), "w") as fh:
            json.dump(argv + ["(stdin: prompt.md, then debrief-prompt.md)"], fh, indent=1)
        p = subprocess.Popen(argv, cwd=ws, env=e, stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=err, start_new_session=True)
        th = threading.Thread(target=reader, args=(p.stdout,), daemon=True)
        th.start()
        p.stdin.write(user_message(prompt).encode())
        p.stdin.flush()
        deadline = t0 + timeout_s
        ended = False      # the task's result seen
        eof = False
        task_wall = None
        while True:
            now = time.time()
            if now >= deadline:
                timed_out = not ended
                break
            wait = min(deadline - now, QUIET_S) if ended else deadline - now
            try:
                raw = lines.get(timeout=wait)
            except queue.Empty:
                if ended:
                    break  # quiet after the result: the task is over
                continue
            if raw is None:
                eof = True
                break
            out.write(raw)
            out.flush()
            if _event_type(raw) == "result":
                ended = True
                task_wall = time.time() - t0
        if timed_out:
            kill_group(p)
        if ended and not eof and not timed_out:
            if on_task_done:
                try:
                    on_task_done()
                except Exception as x:  # the debrief is skipped, the task stands
                    debrief_out["error"] = "on_task_done: %r" % x
            if "error" not in debrief_out:
                debrief_out = _debrief_turn(p, lines, debrief, dpath)
        try:
            p.stdin.close()
        except OSError:
            pass
        try:
            p.wait(timeout=30)
        except subprocess.TimeoutExpired:
            kill_group(p)
            p.wait()
    wall = task_wall if task_wall is not None else time.time() - t0
    res = parse_stream(tpath)
    res["wall_s"] = round(wall, 1)
    res["exit_code"] = p.returncode
    if timed_out:
        res["error"] = "timeout after %ds" % timeout_s
    elif res.get("error") is None and not ended:
        with open(epath, "rb") as fh:
            res["error"] = "claude exited %s before the task's result: %s" % (
                p.returncode, fh.read()[-300:].decode("utf-8", "replace"))
    if not debrief_out.get("sent"):
        debrief_out.setdefault("error", "not asked: " + ("the task timed out" if timed_out
                                                          else "the session ended"))
    else:
        debrief_out.update(parse_debrief(dpath, res.get("cost_usd")))
    res["debrief"] = debrief_out
    return res


def _event_type(raw):
    try:
        return json.loads(raw).get("type")
    except ValueError:
        return None


def _debrief_turn(p, lines, text, dpath):
    """Sends the debrief and copies its events to dpath until its result
    (or DEBRIEF_TIMEOUT_S)."""
    import queue
    out = {"sent": True}
    t0 = time.time()
    try:
        p.stdin.write(user_message(text).encode())
        p.stdin.flush()
    except OSError as x:
        return {"sent": False, "error": "could not send: %r" % x}
    with open(dpath, "wb") as fh:
        while True:
            left = t0 + DEBRIEF_TIMEOUT_S - time.time()
            if left <= 0:
                out["error"] = "no answer in %ds" % DEBRIEF_TIMEOUT_S
                break
            try:
                raw = lines.get(timeout=left)
            except queue.Empty:
                continue
            if raw is None:
                out["error"] = "the session ended before the answer"
                break
            fh.write(raw)
            fh.flush()
            if _event_type(raw) == "result":
                break
    out["wall_s"] = round(time.time() - t0, 1)
    return out


def parse_debrief(dpath, task_cost):
    """The debrief's answer (its assistant text), tool calls, tokens and
    cost: the session's cumulative total_cost_usd after the debrief minus
    the task's."""
    text, calls, total = [], 0, None
    u = Counter()
    if not os.path.isfile(dpath):
        return {"answer": None}
    with open(dpath, "rb") as fh:
        for raw in fh:
            try:
                d = json.loads(raw)
            except ValueError:
                continue
            if d.get("type") == "assistant" and d.get("parent_tool_use_id") is None:
                for c in (d.get("message") or {}).get("content") or []:
                    if c.get("type") == "text":
                        text.append(c.get("text") or "")
                    elif c.get("type") == "tool_use":
                        calls += 1
            elif d.get("type") == "result":
                total = d.get("total_cost_usd")
                for k in ("input_tokens", "output_tokens", "cache_read_input_tokens",
                          "cache_creation_input_tokens"):
                    u[k] += (d.get("usage") or {}).get(k) or 0
    cost = (round(total - task_cost, 6) if total is not None and task_cost is not None
            else None)
    answer = "\n".join(t.strip() for t in text if t.strip()) or None
    return {"answer": answer, "words": len(answer.split()) if answer else 0,
            "tool_calls": calls, "cost_usd": cost,
            "input_tokens": u["input_tokens"] + u["cache_read_input_tokens"]
            + u["cache_creation_input_tokens"],
            "output_tokens": u["output_tokens"], "cache_read_tokens": u["cache_read_input_tokens"]}


def parse_stream(path):
    init, result = None, None
    results = []
    usage_by_msg = {}
    calls = []
    denials = []
    hook_events = Counter()
    with open(path, "rb") as fh:
        for raw in fh:
            try:
                d = json.loads(raw)
            except ValueError:
                continue
            t = d.get("type")
            if t == "system" and d.get("subtype") == "init":
                init = d
            elif t == "system" and "hook" in (d.get("subtype") or ""):
                hook_events[d.get("subtype")] += 1
            elif t == "system" and d.get("subtype") == "permission_denied":
                denials.append({"tool": d.get("tool_name"),
                                "reason": (d.get("message") or "")[-200:]})
            elif t == "assistant" and d.get("parent_tool_use_id") is None:
                m = d.get("message") or {}
                if m.get("id") and m.get("usage"):
                    usage_by_msg[m["id"]] = m["usage"]
                for c in m.get("content") or []:
                    if c.get("type") == "tool_use":
                        calls.append((c.get("name"), c.get("input") or {}))
            elif t == "result":
                # (0.16) a session can end more than once: a background task
                # finishing after the answer starts another turn and another
                # result. num_turns, usage and permission_denials are per
                # result (summed below); total_cost_usd is cumulative.
                result = d
                results.append(d)
    kinds = Counter()
    for name, inp in calls:
        kinds.update(classify_call(name, inp))
    if results and all(r.get("usage") for r in results):
        u = Counter()
        for r in results:
            for k in ("input_tokens", "output_tokens", "cache_read_input_tokens",
                      "cache_creation_input_tokens"):
                u[k] += r["usage"].get(k) or 0
    else:  # killed: add up the messages seen
        u = Counter()
        for mu in usage_by_msg.values():
            for k in ("input_tokens", "output_tokens", "cache_read_input_tokens",
                      "cache_creation_input_tokens"):
                u[k] += mu.get(k) or 0
    result_denials = [x for r in results for x in r.get("permission_denials") or []]
    fresh = u.get("input_tokens") or 0
    cread = u.get("cache_read_input_tokens") or 0
    cwrite = u.get("cache_creation_input_tokens") or 0
    res = {
        "turns": (sum(r.get("num_turns") or 0 for r in results) if results
                  else len(usage_by_msg)),
        "tool_calls": len(calls),
        "tool_calls_by_kind": dict(sorted(kinds.items())),
        # every prompt token the model read: fresh + cache writes + cache reads
        "input_tokens": fresh + cwrite + cread,
        "output_tokens": u.get("output_tokens") or 0,
        "cache_read_tokens": cread,
        "cache_creation_tokens": cwrite,
        "cost_usd": (result or {}).get("total_cost_usd"),
        "permission_denials": len(result_denials or denials),
        "permission_denied": [
            json.dumps(x.get("tool_input"))[:300] for x in result_denials] or
            [x["tool"] for x in denials],
        "error": None,
    }
    if len(results) > 1:
        res["results"] = len(results)
    if hook_events:
        res["hook_events"] = dict(hook_events)
    if init:
        res["agent_env"] = {
            "model": init.get("model"),
            "tools": init.get("tools"),
            "mcp_servers": init.get("mcp_servers"),
            "skills": init.get("skills"),
            "plugins": [p.get("name") for p in init.get("plugins") or []],
            "permission_mode": init.get("permissionMode"),
            "cwd": init.get("cwd"),
            "version": init.get("claude_code_version"),
        }
        res["model_id"] = init.get("model")
    else:
        res["error"] = "no init event in the stream"
    if result and result.get("is_error"):
        res["error"] = "result: %s %s" % (result.get("subtype"),
                                          str(result.get("result"))[:300])
    return res
