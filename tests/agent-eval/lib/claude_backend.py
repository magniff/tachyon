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
# such as `tachyonc edit`): the list covers those.
ALLOW = ["tachyonc", "rustc", "./prog", "prog", "cat", "ls", "echo", "printf",
         "head", "tail", "grep", "sed", "awk", "diff", "cmp", "wc", "sort",
         "uniq", "tr", "cut", "mkdir", "cp", "mv", "rm", "touch", "find",
         "python3", "time", "timeout", "test", "true", "false", "cd", "pwd",
         "which", "seq", "xxd", "od", "git", "sh", "bash", "chmod", "tee",
         "env", "file", "stat", "du"]


# "allowlist" (the default): acceptEdits + the sandbox's auto-allow + ALLOW;
# Claude Code still asks (so denies) before command lines it cannot check
# statically: shell variables, `$?`, subshells. "bypass": no prompts at
# all; the sandbox still confines Bash, deny rules still hold (and an Edit
# deny rule for the home directory keeps the file tools out of it).
PERMS = "allowlist"


def settings(deny_read):
    home = os.path.realpath(os.path.expanduser("~"))
    deny = ["Read(/%s/**)" % p for p in deny_read]
    if PERMS == "bypass":
        deny.append("Edit(/%s/**)" % home)
    return {
        "sandbox": {
            "enabled": True,
            "autoAllowBashIfSandboxed": True,
            "allowUnsandboxedCommands": False,
            "filesystem": {"denyRead": deny_read},
        },
        "permissions": {
            "allow": ["Bash(%s:*)" % c for c in ALLOW],
            "deny": deny,
        },
    }


def command(prompt, model):
    claude = shutil.which("claude")
    if not claude:
        raise SystemExit("claude not found on PATH")
    return [
        claude, "-p", prompt,
        "--model", model,
        "--output-format", "stream-json", "--verbose",
        "--setting-sources", "",
        "--settings", json.dumps(settings(private_paths())),
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


def run(prompt, ws, bin_dir, model, timeout_s, rdir):
    """Runs the agent in `ws`; the stream goes to rdir/transcript.jsonl.
    Returns the agent's half of result.json."""
    tpath = os.path.join(rdir, "transcript.jsonl")
    epath = os.path.join(rdir, "agent.stderr")
    t0 = time.time()
    timed_out = False
    with open(tpath, "wb") as out, open(epath, "wb") as err:
        p = subprocess.Popen(command(prompt, model), cwd=ws, env=env(bin_dir),
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


def parse_stream(path):
    init, result = None, None
    usage_by_msg = {}
    calls = []
    denials = []
    with open(path, "rb") as fh:
        for raw in fh:
            try:
                d = json.loads(raw)
            except ValueError:
                continue
            t = d.get("type")
            if t == "system" and d.get("subtype") == "init":
                init = d
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
                result = d
    kinds = Counter()
    for name, inp in calls:
        kinds.update(classify_call(name, inp))
    if result and result.get("usage"):
        u = result["usage"]
    else:  # killed: add up the messages seen
        u = Counter()
        for mu in usage_by_msg.values():
            for k in ("input_tokens", "output_tokens", "cache_read_input_tokens",
                      "cache_creation_input_tokens"):
                u[k] += mu.get(k) or 0
    fresh = u.get("input_tokens") or 0
    cread = u.get("cache_read_input_tokens") or 0
    cwrite = u.get("cache_creation_input_tokens") or 0
    res = {
        "turns": (result or {}).get("num_turns", len(usage_by_msg)),
        "tool_calls": len(calls),
        "tool_calls_by_kind": dict(sorted(kinds.items())),
        # every prompt token the model read: fresh + cache writes + cache reads
        "input_tokens": fresh + cwrite + cread,
        "output_tokens": u.get("output_tokens") or 0,
        "cache_read_tokens": cread,
        "cache_creation_tokens": cwrite,
        "cost_usd": (result or {}).get("total_cost_usd"),
        "permission_denials": len((result or {}).get("permission_denials") or denials),
        "permission_denied": [
            json.dumps(x.get("tool_input"))[:300]
            for x in (result or {}).get("permission_denials") or []] or
            [x["tool"] for x in denials],
        "error": None,
    }
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
