"""The local backend: a minimal agent loop against Ollama's native
/api/chat, with four tools confined to the workspace.

bash runs `/bin/bash -c COMMAND` in the workspace under macOS
sandbox-exec (writes only in the workspace and temp, no network, the
repository and ~/.claude unreadable: the same box as the hosted backend's
sandbox), 60 s per command, output cut to about 8 KB. read_file,
write_file and edit_file refuse paths outside the workspace."""

import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from collections import Counter

from lib.common import base_env, kill_group, private_paths
from lib.toolkinds import classify_call

URL = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")
if not URL.startswith("http"):
    URL = "http://" + URL
OPTIONS = {"num_ctx": 32768, "temperature": 0.2}
KEEP_ALIVE = "30m"
MAX_TURNS = 60
BASH_TIMEOUT_S = 60
OUTPUT_LIMIT = 8000

SYSTEM = """You are a coding agent. You work in a workspace directory, \
through tools:
- bash(command): runs `/bin/bash -c command` in the workspace (60 s limit; \
long output is cut); use it to build, run and test the program;
- read_file(path), write_file(path, content), edit_file(path, old, new): \
files in the workspace (paths relative to it). edit_file replaces one \
exact occurrence of `old`.
Call tools to do the work. When the task is complete, answer with a short \
summary and no tool call: that ends the session."""


def _fn(name, desc, props, required):
    return {"type": "function", "function": {
        "name": name, "description": desc,
        "parameters": {"type": "object", "properties": props,
                       "required": required}}}


_S = {"type": "string"}
TOOLS = [
    _fn("bash", "Run a shell command in the workspace; returns its exit "
        "status and output (stdout and stderr).",
        {"command": dict(_S, description="the command")}, ["command"]),
    _fn("read_file", "Read a file of the workspace.",
        {"path": dict(_S, description="path relative to the workspace")}, ["path"]),
    _fn("write_file", "Create or overwrite a file of the workspace.",
        {"path": _S, "content": dict(_S, description="the whole new content")},
        ["path", "content"]),
    _fn("edit_file", "Replace one exact occurrence of `old` by `new` in a file.",
        {"path": _S, "old": _S, "new": _S}, ["path", "old", "new"]),
]


def sandbox_profile(ws):
    tmp = os.path.realpath(os.environ.get("TMPDIR", "/tmp"))
    deny = private_paths()
    q = lambda p: '"%s"' % p.replace("\\", "\\\\").replace('"', '\\"')
    return "\n".join([
        "(version 1)",
        "(allow default)",
        "(deny network*)",
        "(allow network* (local unix-socket))",
        "(deny file-write*)",
        "(allow file-write* (subpath %s) (subpath %s) (subpath \"/private/tmp\")"
        " (literal \"/dev/null\") (literal \"/dev/tty\") (regex #\"^/dev/fd/\"))"
        % (q(os.path.realpath(ws)), q(tmp)),
        "(deny file-read* %s)" % " ".join("(subpath %s)" % q(p) for p in deny),
    ])


def _cut(text):
    if len(text) <= OUTPUT_LIMIT:
        return text
    head, tl = text[:OUTPUT_LIMIT * 3 // 4], text[-OUTPUT_LIMIT // 4:]
    return "%s\n[... %d characters cut ...]\n%s" % (head, len(text) - len(head) - len(tl), tl)


class Tools:
    def __init__(self, ws, bin_dir, check_hook=None):
        self.ws = os.path.realpath(ws)
        self.env = base_env(bin_dir)
        self.profile = sandbox_profile(ws)
        self.check_hook = check_hook

    def after(self, name, a, result):
        """(--check-hook) The hook Claude Code would run after this call,
        its context appended to the result."""
        if not self.check_hook or name not in ("write_file", "edit_file", "bash"):
            return result
        if name == "bash":
            event = {"tool_name": "Bash", "tool_input": {"command": a.get("command", "")},
                     "tool_response": {"stdout": result, "stderr": ""}}
        else:
            event = {"tool_name": "Write" if name == "write_file" else "Edit",
                     "tool_input": {"file_path": os.path.join(self.ws, a.get("path", ""))}}
        event.update(hook_event_name="PostToolUse", cwd=self.ws)
        env = dict(self.env, VOLE_CHECK_HOOK_LOG=self.check_hook[1])
        try:
            r = subprocess.run(["/usr/bin/python3", "-I", self.check_hook[0]], input=json.dumps(event),
                               capture_output=True, text=True, env=env, timeout=60)
            ctx = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"] if r.stdout.strip() else ""
        except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
            ctx = ""
        return result + "\n" + ctx if ctx else result

    def _path(self, p):
        full = os.path.realpath(os.path.join(self.ws, p))
        if full != self.ws and not full.startswith(self.ws + os.sep):
            raise ValueError("%s is outside the workspace" % p)
        return full

    def call(self, name, a):
        try:
            if name == "bash":
                return self.bash(a["command"])
            if name == "read_file":
                with open(self._path(a["path"]), encoding="utf-8", errors="replace") as fh:
                    return _cut(fh.read())
            if name == "write_file":
                p = self._path(a["path"])
                os.makedirs(os.path.dirname(p), exist_ok=True)
                with open(p, "w") as fh:
                    fh.write(a["content"])
                return "wrote %s (%d bytes)" % (a["path"], len(a["content"].encode()))
            if name == "edit_file":
                p = self._path(a["path"])
                with open(p) as fh:
                    text = fh.read()
                n = text.count(a["old"])
                if n != 1:
                    return "error: `old` occurs %d times in %s (it must occur once)" % (n, a["path"])
                with open(p, "w") as fh:
                    fh.write(text.replace(a["old"], a["new"], 1))
                return "edited %s" % a["path"]
            return "error: no tool %r (tools: bash, read_file, write_file, edit_file)" % name
        except KeyError as e:
            return "error: missing argument %s" % e
        except (OSError, ValueError) as e:
            return "error: %s" % e

    def bash(self, cmd):
        p = subprocess.Popen(["/usr/bin/sandbox-exec", "-p", self.profile,
                              "/bin/bash", "-c", cmd],
                             cwd=self.ws, env=self.env, stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             start_new_session=True)
        try:
            out, _ = p.communicate(timeout=BASH_TIMEOUT_S)
            status = "exit %d" % p.returncode
        except subprocess.TimeoutExpired:
            kill_group(p)
            out, _ = p.communicate()
            status = "killed after %d s" % BASH_TIMEOUT_S
        return "[%s]\n%s" % (status, _cut(out.decode("utf-8", "replace")))


def chat(model, messages, timeout):
    body = json.dumps({"model": model, "messages": messages, "tools": TOOLS,
                       "stream": False, "options": OPTIONS,
                       "keep_alive": KEEP_ALIVE}).encode()
    req = urllib.request.Request(URL + "/api/chat", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=max(timeout, 1)) as r:
        return json.loads(r.read())


def run(prompt, ws, bin_dir, model, timeout_s, rdir, check_hook=None):
    tools = Tools(ws, bin_dir, check_hook)
    messages = [{"role": "system", "content": SYSTEM},
                {"role": "user", "content": prompt}]
    tpath = os.path.join(rdir, "transcript.jsonl")
    t0 = time.time()
    turns, calls, kinds = 0, 0, Counter()
    tin, tout, max_prompt = 0, 0, 0
    error = None
    with open(tpath, "w") as tr:
        for m in messages:
            tr.write(json.dumps({"message": m}) + "\n")
        while True:
            left = timeout_s - (time.time() - t0)
            if left <= 0:
                error = "timeout after %ds" % timeout_s
                break
            if turns >= MAX_TURNS:
                error = "max turns (%d)" % MAX_TURNS
                break
            try:
                r = chat(model, messages, left)
            except (urllib.error.URLError, OSError, ValueError) as e:
                error = ("timeout after %ds" % timeout_s
                         if time.time() - t0 >= timeout_s else "ollama: %s" % e)
                break
            turns += 1
            msg = r.get("message") or {}
            pe, ev = r.get("prompt_eval_count") or 0, r.get("eval_count") or 0
            tin, tout = tin + pe, tout + ev
            max_prompt = max(max_prompt, pe)
            stats = {k: r.get(k) for k in ("prompt_eval_count", "eval_count",
                                          "total_duration", "done_reason")}
            out_msg = {"role": "assistant", "content": msg.get("content") or ""}
            if msg.get("tool_calls"):
                out_msg["tool_calls"] = msg["tool_calls"]
            messages.append(out_msg)
            tr.write(json.dumps({"message": msg, "stats": stats}) + "\n")
            tr.flush()
            tcs = msg.get("tool_calls") or []
            if not tcs:
                break
            for tc in tcs:
                fn = tc.get("function") or {}
                name, a = fn.get("name", ""), fn.get("arguments") or {}
                if isinstance(a, str):
                    try:
                        a = json.loads(a)
                    except ValueError:
                        a = {}
                calls += 1
                kinds.update(classify_call(name, a))
                result = tools.after(name, a, tools.call(name, a))
                tm = {"role": "tool", "content": result, "tool_name": name}
                messages.append(tm)
                tr.write(json.dumps({"message": tm}) + "\n")
            tr.flush()
    return {
        "turns": turns,
        "tool_calls": calls,
        "tool_calls_by_kind": dict(sorted(kinds.items())),
        # prompt_eval_count per call: the whole prompt of that call (as
        # observed; comparable with Claude's fresh + cached input)
        "input_tokens": tin,
        "output_tokens": tout,
        "cache_read_tokens": None,
        "max_prompt_tokens": max_prompt,
        "cost_usd": None,
        "permission_denials": 0,
        "wall_s": round(time.time() - t0, 1),
        "model_id": model,
        "error": error,
    }
