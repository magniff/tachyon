#!/usr/bin/env python3
"""Agent harness hook (testing mode): tachyon source is read through
`tachyonc query`, not grep/sed/head/cat/awk, and every exception is
recorded with its reason.

Registered in .claude/settings.json for PreToolUse (Bash, Read, Grep) and
PostToolUse (Bash). Reads the hook event (JSON) on stdin.

- A shell command that reads .tach source with grep, rg, sed -n, head,
  tail, cat, awk, less or more is blocked (exit status 2; the message on
  stderr goes back to the agent) with the query that answers it, unless it
  carries `# no-query: <reason>`: then it runs, and the reason is logged.
- `tachyonc query ...` calls are logged, with their outcome.
- Read and Grep calls on .tach files are logged, not blocked (Edit needs
  a prior Read).

The log is .git/agent-tools.jsonl in the main checkout, shared by every
worktree; tools/agent-tool-usage.py --hook-log summarizes it. Enforcement
starts only once the compiler answers `query` (marker
.git/agent-query-ready); TACHYON_QUERY_ENFORCE=0 turns blocking off.
Development tooling only: not part of the build.
"""
import json
import os
import re
import shlex
import subprocess
import sys
import time

READERS = {"grep", "rg", "egrep", "fgrep", "sed", "head", "tail", "cat", "awk", "less", "more"}
SOURCE = re.compile(r"(\.tach\b|compiler/src\b|compiler/std\b)")
HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n.*?\n\s*\1\s*(\n|$)", re.S)
ESCAPE = re.compile(r"#\s*no-query:\s*(.+)")


def git_dir(cwd):
    try:
        out = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                             cwd=cwd, capture_output=True, text=True, timeout=5)
        return out.stdout.strip() or None
    except Exception:
        return None


def log(gd, record):
    if not gd:
        return
    record["time"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    try:
        with open(os.path.join(gd, "agent-tools.jsonl"), "a") as fh:
            fh.write(json.dumps(record) + "\n")
    except OSError:
        pass


def query_ready(gd, cwd):
    if os.environ.get("TACHYON_QUERY_ENFORCE") == "0" or not gd:
        return False
    marker = os.path.join(gd, "agent-query-ready")
    if os.path.exists(marker):
        return True
    compiler = os.path.join(cwd, "target", "tachyonc")
    root = os.path.join(cwd, "compiler", "src", "main.tach")
    if not (os.path.exists(compiler) and os.path.exists(root)):
        return False
    try:
        r = subprocess.run([compiler, "query", "def", "main", root],
                           capture_output=True, text=True, timeout=10)
    except Exception:
        return False
    if r.returncode == 0 and r.stdout.strip():
        open(marker, "w").close()
        return True
    return False


def source_reads(command):
    """(program, words) of each simple command reading .tach source."""
    body = HEREDOC.sub("<<HEREDOC\n", command)
    found = []
    for seg in re.split(r"\|\||&&|;|\||\n", body):
        seg = seg.strip()
        if not seg or "#" == seg[:1]:
            continue
        try:
            words = shlex.split(seg, comments=True)
        except ValueError:
            words = seg.split()
        while words and "=" in words[0] and not words[0].startswith("-"):
            words = words[1:]
        if not words:
            continue
        prog = os.path.basename(words[0])
        if prog not in READERS:
            continue
        args = words[1:]
        if prog == "sed" and any(a.startswith("-i") for a in args):
            continue  # an edit, not a read (logged as such)
        if prog == "cat" and (">" in seg):
            continue  # writing a file
        if any(SOURCE.search(a) for a in args if not a.startswith("-")):
            found.append((prog, args))
    return found


def suggestion(prog, args):
    pattern = next((a for a in args if not a.startswith("-")), "")
    m = re.search(r"\b(?:fn|struct|enum|trait|const|static|type|mod)\s+(\w+)", pattern)
    if m:
        return f"tachyonc query show {m.group(1)}   (or: query def {m.group(1)})"
    if prog in ("grep", "rg", "egrep", "fgrep"):
        word = re.sub(r"[^\w:.]", "", pattern) or "NAME"
        return f"tachyonc query refs {word}   (or: query def / show {word})"
    return "tachyonc query show NAME   (one item's source), or: tachyonc query items MODULE   (what a module contains)"


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    cwd = event.get("cwd") or os.getcwd()
    gd = git_dir(cwd)
    phase = event.get("hook_event_name", "")
    tool = event.get("tool_name", "")
    inp = event.get("tool_input") or {}
    session = (event.get("session_id") or "")[:8]
    agent = os.path.basename(event.get("transcript_path") or "")[:20]

    if tool == "Bash":
        command = inp.get("command", "")
        if phase == "PostToolUse":
            if "tachyonc query" in command or "tachyonc\" query" in command:
                resp = event.get("tool_response") or {}
                out = (resp.get("stdout") or "") if isinstance(resp, dict) else str(resp)
                err = (resp.get("stderr") or "") if isinstance(resp, dict) else ""
                log(gd, {"kind": "query-result", "session": session, "agent": agent,
                         "command": command[:300], "out_lines": out.count("\n"),
                         "out_bytes": len(out), "stderr": err[:300]})
            return 0
        if "tachyonc query" in command or "tachyonc\" query" in command:
            log(gd, {"kind": "query", "session": session, "agent": agent, "command": command[:300]})
        reads = source_reads(command)
        if not reads:
            if re.search(r"\bsed\s+-i|\bperl\s+-p", command) and SOURCE.search(command):
                log(gd, {"kind": "edit", "session": session, "agent": agent, "command": command[:300]})
            return 0
        esc = ESCAPE.search(command)
        if esc:
            log(gd, {"kind": "escape", "session": session, "agent": agent,
                     "reason": esc.group(1).strip()[:300], "command": command[:300]})
            return 0
        if not query_ready(gd, cwd):
            log(gd, {"kind": "read-unenforced", "session": session, "agent": agent, "command": command[:300]})
            return 0
        prog, args = reads[0]
        log(gd, {"kind": "blocked", "session": session, "agent": agent,
                 "program": prog, "command": command[:300]})
        sys.stderr.write(
            "Reading tachyon source with %s is disabled (testing the compiler's query commands).\n"
            "Use instead:  %s\n"
            "Root defaults to compiler/src/main.tach; see docs/query.md.\n"
            "If query cannot answer what you need, rerun the command with a trailing\n"
            "  # no-query: <why query was not enough, specifically>\n"
            "and it will run; the reason is recorded to improve the tool.\n" % (prog, suggestion(prog, args)))
        return 2

    if tool in ("Read", "Grep") and phase == "PreToolUse":
        target = inp.get("file_path") or inp.get("path") or ""
        pattern = inp.get("pattern", "")
        if SOURCE.search(target) or (tool == "Grep" and SOURCE.search(inp.get("glob", "") + inp.get("type", ""))):
            log(gd, {"kind": tool.lower(), "session": session, "agent": agent,
                     "target": target[:200], "pattern": pattern[:120],
                     "offset": inp.get("offset"), "limit": inp.get("limit")})
    return 0


if __name__ == "__main__":
    sys.exit(main())
