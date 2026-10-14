#!/usr/bin/env python3
"""Agent harness hook (0.15): `tachyonc check` after every change to
tachyon source, its errors appended to the agent's own tool result, so
that the agent does not spend a call on it (docs/tool-gaps-014.md, gap 3:
124 eval calls and 21 dev calls ran `check` straight after a Write or
Edit).

Registered in .claude/settings.json for PostToolUse (Write, Edit,
MultiEdit, Bash), and by the agent eval with `run.py run --check-hook`.
Reads the hook event (JSON) on stdin; prints, when the program has
errors, a PostToolUse `additionalContext`:

    tachyonc check main.tach: 2 errors
    main.tach:4:18: error[type error] expected 'i64', got '[u8]'
    main.tach:5:5: error[type error] undefined variable 'prinln' | help: did you mean 'println'?

at most 10 errors (the edited file's first), then `(N more: tachyonc
check ROOT)`. A clean program prints nothing.

- When: a Write, Edit or MultiEdit of a `.tach` file; a Bash call whose
  `tachyonc edit|refactor|fix|rewrite|undo` wrote (its summary line; not
  `--dry-run`), through any copy or variable (tachyonc_cmd.py).
- The root: under a checkout's compiler/src, compiler/src/main.tach; under
  compiler/std, compiler/std/std.tach; else the nearest main.tach in the
  file's directory or above it (not above the checkout), else the file
  itself when it has `fn main`; for a Bash call, its `--root R` or last
  `.tach` operand, else `check`'s default.
- The compiler: $TACHYON_CHECK_COMPILER; the checkout's
  target/tools/tachyonc (bootstrap/bootstrap.sh --dev, a passing build),
  then target/tachyonc; then `tachyonc` on PATH (the eval's bin/). For a
  Bash call, the binary it ran when that is a path.
- How: `tachyonc check --json ROOT` in the event's directory (one JSON
  object per diagnostic, docs/query.md); a compiler without --json is run
  without it, its short lines parsed.
- Logged as `check-hook` records (root, errors, their codes,
  milliseconds): into $TACHYON_CHECK_HOOK_LOG when set (the agent eval),
  else the query-first hook's log (.git/agent-tools.jsonl).

TACHYON_CHECK_HOOK=0 turns it off. Development tooling only.
"""
import json
import os
import re
import sys
import time
import types

HERE = os.path.dirname(os.path.abspath(__file__))
MAX_SHOWN = 10
TIMEOUT = 30
WRITES = ("edit", "refactor", "fix", "rewrite", "undo")
SHORT = re.compile(r"^(?P<file>.+?):(?P<line>\d+):(?P<col>\d+): (?P<sev>\w+)\[(?P<code>[^\]]*)\] (?P<rest>.*)$")


def _load(name, file):
    """A module next to this file, by path (not importlib.util: its imports
    alone take 40 ms, and the hook runs after every edit)."""
    mod = types.ModuleType(name)
    mod.__file__ = os.path.join(HERE, file)
    with open(mod.__file__) as fh:
        exec(compile(fh.read(), mod.__file__, "exec"), mod.__dict__)
    return mod


def which(name):
    for d in os.environ.get("PATH", "").split(os.pathsep):
        p = os.path.join(d, name)
        if d and os.access(p, os.X_OK) and not os.path.isdir(p):
            return p
    return None


tc = _load("tachyonc_cmd", "tachyonc_cmd.py")
qf = None  # query-first.py, for its log; loaded when a record is written


def checkout_root(path):
    """The checkout (a directory with `.git`) holding path, or None."""
    d = os.path.abspath(path)
    while True:
        if os.path.exists(os.path.join(d, ".git")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def root_of(path):
    """The program root to check after a change to the .tach file path."""
    p = os.path.abspath(path)
    top = checkout_root(os.path.dirname(p))
    if top:
        for sub, root in (("compiler/src/", "compiler/src/main.tach"), ("compiler/std/", "compiler/std/std.tach")):
            if p.startswith(os.path.join(top, sub)) and os.path.exists(os.path.join(top, root)):
                return os.path.join(top, root)
    d = os.path.dirname(p)
    for _ in range(8):
        cand = os.path.join(d, "main.tach")
        if os.path.exists(cand):
            return cand
        if d == top or os.path.dirname(d) == d:
            break
        d = os.path.dirname(d)
    try:
        with open(p, errors="replace") as fh:
            if re.search(r"^\s*(pub\s+)?fn\s+main\s*\(", fh.read(), re.M):
                return p
    except OSError:
        pass
    return None


def compiler_for(where, ran=None):
    """The tachyonc to check with: the one the agent ran (a path), the
    override, the checkout's tools binary or build, the one on PATH."""
    if ran and os.sep in ran:
        p = ran if os.path.isabs(ran) else os.path.join(where, ran)
        if os.access(p, os.X_OK):
            return p
    env = os.environ.get("TACHYON_CHECK_COMPILER")
    if env and os.access(env, os.X_OK):
        return env
    top = checkout_root(where)
    if top:
        for rel in ("target/tools/tachyonc", "target/tachyonc"):
            p = os.path.join(top, rel)
            if os.access(p, os.X_OK):
                return p
    return which("tachyonc")


def run_check(compiler, root, cwd):
    """The diagnostics of `check` on root (None: check's default), as
    dicts with the keys of --json; None when check could not run."""
    import subprocess  # (here: the hook's no-op path stays cheaper)

    def run(args):
        try:
            return subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=TIMEOUT)
        except (OSError, subprocess.TimeoutExpired):
            return None
    tail = [os.path.relpath(root, cwd) if root and root.startswith(cwd + os.sep) else root] if root else []
    r = run([compiler, "check", "--json"] + tail)
    if r is None:
        return None
    if "--json" in r.stderr and "unknown option" in r.stderr:  # (a compiler before 0.15)
        r = run([compiler, "check"] + tail)
        if r is None:
            return None
        return [d for d in map(parse_short, (r.stdout + r.stderr).splitlines()) if d]
    if r.returncode not in (0, 1):
        return None
    diags = []
    for line in (r.stderr + r.stdout).splitlines():
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if isinstance(d, dict) and d.get("kind") == "diagnostic":
            diags.append(d)
    return diags


def parse_short(line):
    m = SHORT.match(line)
    if not m:
        return None
    parts = m.group("rest").split(" | ")
    return {"severity": m.group("sev"), "code": m.group("code"), "file": m.group("file"),
            "line": int(m.group("line")), "col": int(m.group("col")), "message": parts[0],
            "help": [p[6:] for p in parts[1:] if p.startswith("help: ")],
            "notes": [p[6:] for p in parts[1:] if p.startswith("note: ")],
            "try": [p[5:] for p in parts[1:] if p.startswith("try: ")]}


def line_of(d):
    """A diagnostic in check's one-line form."""
    pos = f"{d['file']}:{d['line']}:{d['col']}: " if d.get("file") else ""
    text = f"{pos}{d.get('severity', 'error')}[{d.get('code', '')}] {d.get('message', '')}"
    for h in d.get("help") or []:
        text += " | help: " + h
    for n in d.get("notes") or []:
        text += " | note: " + n
    for t in d.get("try") or []:
        text += " | try: " + t
    return text


def report(diags, root_shown, edited):
    """The context for the agent: nothing when clean."""
    errors = [d for d in diags if d.get("severity") == "error"]
    if not errors:
        return ""
    if edited:
        edited = os.path.abspath(edited)
        errors.sort(key=lambda d: not (d.get("file") and edited.endswith(os.sep + os.path.normpath(d["file"]))
                                       or os.path.abspath(d.get("file") or "") == edited))
    n = len(errors)
    lines = [f"tachyonc check{' ' + root_shown if root_shown else ''}: {n} error{'s' if n != 1 else ''}"]
    lines += [line_of(d) for d in errors[:MAX_SHOWN]]
    if n > MAX_SHOWN:
        lines.append(f"({n - MAX_SHOWN} more: tachyonc check{' ' + root_shown if root_shown else ''})")
    return "\n".join(lines)


def trigger(event):
    """(file edited or None, root or None, compiler the agent ran or None)
    when the event changed tachyon source; None otherwise."""
    tool = event.get("tool_name", "")
    inp = event.get("tool_input") or {}
    if tool in ("Write", "Edit", "MultiEdit"):
        path = inp.get("file_path") or ""
        if not path.endswith(".tach"):
            return None
        root = root_of(path)
        return (path, root, None) if root else None
    if tool == "Bash":
        command = inp.get("command", "")
        resp = event.get("tool_response") or {}
        out = (resp.get("stdout") or "") if isinstance(resp, dict) else str(resp)
        for sub, words, path, _ in tc.calls(command):
            if sub not in WRITES or "--dry-run" in words:
                continue
            if not re.search(r"^(undid|patched|replaced|inserted|deleted|fixed|renamed|moved|rewrote|"
                             r"added|removed|changed|made|split|script|wrapped|formatted)\b.*\t", out, re.M):
                return None
            root = None
            for i, w in enumerate(words):
                if w == "--root" and i + 1 < len(words):
                    root = words[i + 1]
                elif w.startswith("--root="):
                    root = w[7:]
            if root is None and words and words[-1].endswith(".tach") and "new-file" not in words:
                root = words[-1]
            return (None, root, path or None)
    return None


def main():
    if os.environ.get("TACHYON_CHECK_HOOK") == "0":
        return 0
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    if event.get("hook_event_name", "PostToolUse") != "PostToolUse":
        return 0
    found = trigger(event)
    if not found:
        return 0
    edited, root, ran = found
    cwd = os.path.abspath(event.get("cwd") or os.getcwd())
    if root and not os.path.isabs(root):
        root = os.path.join(cwd, root)
    compiler = compiler_for(cwd if not edited else os.path.dirname(os.path.abspath(edited)), ran)
    if not compiler:
        return 0
    t0 = time.time()
    diags = run_check(compiler, root, cwd)
    ms = int((time.time() - t0) * 1000)
    if diags is None:
        return 0
    shown = (os.path.relpath(root, cwd) if root.startswith(cwd + os.sep) else root) if root else ""
    text = report(diags, shown or "", edited)
    errors = [d for d in diags if d.get("severity") == "error"]
    record(event, cwd, {"kind": "check-hook", "tool": event.get("tool_name"), "root": shown[-120:],
                        "errors": len(errors), "codes": sorted({d.get("code") or "" for d in errors}),
                        "ms": ms})
    if text:
        json.dump({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": text}},
                  sys.stdout)
    return 0


def record(event, cwd, rec):
    """Into $TACHYON_CHECK_HOOK_LOG (the agent eval's, one JSON line per
    check), else the query-first hook's log with who made it; best effort."""
    global qf
    path = os.environ.get("TACHYON_CHECK_HOOK_LOG")
    if path:
        rec["time"] = time.strftime("%Y-%m-%dT%H:%M:%S")
        try:
            with open(path, "a") as fh:
                fh.write(json.dumps(rec) + "\n")
        except OSError:
            pass
        return
    try:
        if qf is None:
            qf = _load("query_first", "query-first.py")
        gd = qf.git_dir(cwd)
        qf.IDENT.update(qf.identity(event, cwd))
        qf.log(gd, rec)
    except Exception:
        pass


if __name__ == "__main__":
    sys.exit(main())
