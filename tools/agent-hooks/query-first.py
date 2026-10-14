#!/usr/bin/env python3
"""Agent harness hook (testing mode): tachyon source is read through
`tachyonc query`, not grep/sed/head/cat/awk, and every exception is
recorded with its reason.

Registered in .claude/settings.json for PreToolUse (Bash, Read, Grep,
Edit, Write) and PostToolUse (Bash). Reads the hook event (JSON) on stdin.

- A shell command that reads .tach source with grep, rg, sed -n, head,
  tail, cat, awk, less or more is blocked (exit status 2; the message on
  stderr goes back to the agent) with the query that answers it, unless it
  carries `# no-query: <reason>`: then it runs, and the reason is logged.
- A shell command that rewrites compiler source (a .tach file under
  compiler/src or compiler/std) with `sed -i`, `perl -pi` or Python
  (`.write(`) is blocked with the `tachyonc edit patch` command that
  does it, unless it carries `# no-tool: <reason>` (or `# no-query:`).
  Test fixtures, docs and scratch copies (target/, /tmp) are not
  affected.
- `tachyonc query ...` calls are logged, with their outcome; `tachyonc
  edit/refactor/fix/rewrite/undo` calls with whether they wrote.
- Read and Grep calls on .tach files are logged, not blocked (Edit needs
  a prior Read); Edit and Write calls on .tach files are logged (whether
  the file existed), never blocked.

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
ESCAPE = re.compile(r"#\s*no-(?:query|tool):\s*(.+)")
# A .tach file of the compiler's own source (not a test, a doc, a copy).
COMPILER_TACH = re.compile(r"((?:[\w.~-]+/)*compiler/(?:src|std)/[\w./*-]*\.tach)\b")
SCRATCH = re.compile(r"(^|/)(target|tmp|private/tmp|var/folders)/")
TOOLS = re.compile(r"tachyonc\"?\s+(edit|refactor|fix|rewrite|undo)\b")
SUMMARY = re.compile(r"^(undid|patched|replaced|inserted|deleted|fixed|renamed|moved|rewrote|"
                     r"added|removed|changed|made|split|script)\b.*\t", re.M)


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
        if any(reads_source(a) for a in file_args(prog, args)):
            found.append((prog, args))
    return found


SOURCE_DIRS = re.compile(r"^(\./)?(compiler/src|compiler/std|tests/run|examples|bench)/?$")


def file_args(prog, args):
    """The operands that are files: a grep pattern, a sed or awk script
    (the first operand, unless given with -e/-f) is not one."""
    operands, skip_next, given_script = [], False, False
    for a in args:
        if skip_next:
            skip_next = False
            continue
        if a in ("-e", "-f", "--regexp", "--file"):
            skip_next, given_script = True, True
            continue
        if a in ("-n", "-c") and prog in ("head", "tail"):
            skip_next = True
            continue
        if a in ("-A", "-B", "-C", "-m", "--max-count") and prog in ("grep", "rg", "egrep", "fgrep"):
            skip_next = True
            continue
        if a.startswith("-"):
            continue
        operands.append(a)
    if prog in ("grep", "rg", "egrep", "fgrep", "sed", "awk") and not given_script and operands:
        operands = operands[1:]
    return operands


def reads_source(path):
    """A .tach file, or a directory of them that grep -r would read."""
    return path.endswith(".tach") or bool(SOURCE_DIRS.match(path)) or (
        ("compiler/src" in path or "compiler/std" in path) and not path.endswith((".sh", ".md", ".toml", ".py", ".awk")))


def compiler_paths(text):
    """The compiler source files (.tach under compiler/src or compiler/std)
    named in text; scratch copies (target/, /tmp) left out."""
    return [m for m in COMPILER_TACH.findall(text) if not SCRATCH.search(m)]


def in_place(prog, args):
    """Whether sed or perl edits its files in place."""
    for a in args:
        if a == "--in-place" or a.startswith("--in-place="):
            return True
        if a.startswith("-") and not a.startswith("--") and "i" in a[1:].split(".")[0]:
            return True  # (sed -i, -i.bak, -Ei; perl -i, -pi, -0pi)
    return False


def source_rewrites(command):
    """(program, files, script) of each part of command that rewrites
    compiler source in place: sed -i, perl -i, or Python writing a file
    (its script is usually a here-document, so all of command counts)."""
    found = []
    body = HEREDOC.sub("<<HEREDOC\n", command)
    for seg in re.split(r"\|\||&&|;|\||\n", body):
        seg = seg.strip()
        if not seg or seg.startswith("#"):
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
        args = words[1:]
        if prog in ("sed", "perl") and in_place(prog, args):
            files = [a for a in args if not a.startswith("-") and compiler_paths(a)]
            if files:
                script = ""
                if prog == "sed":
                    rest = [a for a in args if a and not a.startswith("-") and a not in files]
                    script = rest[0] if rest else ""
                found.append(("sed -i" if prog == "sed" else "perl -pi", files, script))
    if re.search(r"\bpython[\d.]*\b", command) and re.search(r"\.write\(|write_text\(|write_bytes\(", command):
        files = compiler_paths(command)
        if files:
            found.append(("python", files, ""))
    return found


def edit_suggestion(prog, files, script):
    """The tachyonc command for a rewrite: `sed -i 'Ns/a/b/' FILE` of plain
    text is `edit patch FILE:N --old a --new b`."""
    f = re.sub(r"^.*?(compiler/(?:src|std)/)", r"\1", files[0])
    m = re.match(r"^(\d+)?s([/|#,])((?:\\.|(?!\2).)*)\2((?:\\.|(?!\2).)*)\2g?$", script or "")
    if prog == "sed -i" and m and not re.search(r"(?<!\\)[\^$*.\[\]+?(){}]", m.group(3)) and "&" not in m.group(4):
        old = re.sub(r"\\(.)", r"\1", m.group(3))
        new = re.sub(r"\\(.)", r"\1", m.group(4))
        target = f"{f}:{m.group(1)}" if m.group(1) else f
        return f"tachyonc edit patch {target} --old {shlex.quote(old)} --new {shlex.quote(new)}"
    return (f"tachyonc edit patch {f}:LINE --old 'TEXT' --new 'TEXT' "
            "(pairs repeat, or come on stdin; docs/refactor.md)")


def tool_target(command):
    """Whether a tachyonc edit/refactor/fix/rewrite/undo command works on
    the compiler's source (the default root), not a test program or a
    scratch copy."""
    roots = re.findall(r"--root[= ]\s*(\S+)", command) + re.findall(r"\s(\S+\.tach)(?=\s|$|;|&|\|)", command)
    dirs = re.findall(r"\bcd\s+(\S+)", command)
    return all(compiler_paths(r) for r in roots) and not any(SCRATCH.search(d + "/") for d in dirs)


def suggestion(prog, args):
    pattern = next((a for a in args if not a.startswith("-")), "")
    m = re.search(r"\b(?:fn|struct|enum|trait|const|static|type|mod)\s+(\w+)", pattern)
    if m:
        return f"tachyonc query show {m.group(1)}"
    files = [a for a in file_args(prog, args) if a.endswith(".tach")]
    # `sed -n 'N,Mp' FILE`: the item holding line N
    m = re.match(r"^(\d+)(,\d+)?p$", pattern)
    if prog == "sed" and m and files:
        return f"tachyonc query show {files[0]}:{m.group(1)}"
    if prog in ("grep", "rg", "egrep", "fgrep"):
        word = re.sub(r"[^\w:.]", "", pattern)
        if word and not re.search(r"\s", pattern):
            return f"tachyonc query refs {word}"
        # (text, not a name: a comment, a string)
        return "tachyonc query items MODULE | tachyonc query show FILE:LINE"
    if files:
        return f"tachyonc query stats {files[0]} | tachyonc query show FILE:LINE"
    return "tachyonc query show NAME | tachyonc query items MODULE"


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
            resp = event.get("tool_response") or {}
            out = (resp.get("stdout") or "") if isinstance(resp, dict) else str(resp)
            err = (resp.get("stderr") or "") if isinstance(resp, dict) else ""
            if "tachyonc query" in command or "tachyonc\" query" in command:
                log(gd, {"kind": "query-result", "session": session, "agent": agent,
                         "command": command[:300], "out_lines": out.count("\n"),
                         "out_bytes": len(out), "stderr": err[:300]})
            m = TOOLS.search(command)
            if m:
                # (written: a summary line; not a dry run's diff, not a refusal)
                written = bool(SUMMARY.search(out)) and "--dry-run" not in command
                log(gd, {"kind": "tool-result", "session": session, "agent": agent, "tool": m.group(1),
                         "command": command[:300], "written": written,
                         "compiler": tool_target(command), "stderr": err[:300]})
            return 0
        if "tachyonc query" in command or "tachyonc\" query" in command:
            log(gd, {"kind": "query", "session": session, "agent": agent, "command": command[:300]})
        rewrites = source_rewrites(command)
        if rewrites:
            prog, files, script = rewrites[0]
            esc = ESCAPE.search(command)
            if esc:
                log(gd, {"kind": "edit-escape", "session": session, "agent": agent, "program": prog,
                         "files": files[:5], "reason": esc.group(1).strip()[:300], "command": command[:300]})
                return 0
            if not query_ready(gd, cwd):
                log(gd, {"kind": "edit", "session": session, "agent": agent, "program": prog,
                         "files": files[:5], "command": command[:300]})
                return 0
            log(gd, {"kind": "edit-blocked", "session": session, "agent": agent, "program": prog,
                     "files": files[:5], "command": command[:300]})
            sys.stderr.write("blocked hook.edit-tool: %s rewriting compiler source (%s)\n"
                             "try: %s | override: append '# no-tool: <why the tools are not enough>'\n"
                             % (prog, files[0], edit_suggestion(prog, files, script)))
            return 2
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
        sys.stderr.write("blocked hook.query-first: %s on .tach source\n"
                         "try: %s | override: append '# no-query: <why query is not enough>'\n"
                         % (prog, suggestion(prog, args)))
        return 2

    if tool in ("Edit", "Write", "MultiEdit") and phase == "PreToolUse":
        target = inp.get("file_path") or ""
        if target.endswith(".tach"):
            log(gd, {"kind": tool.lower(), "session": session, "agent": agent, "target": target[:200],
                     "existed": os.path.exists(target),
                     "bytes": len(inp.get("new_string") or inp.get("content") or "")})
        return 0
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
