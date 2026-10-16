#!/usr/bin/env python3
"""Agent harness hook (0.15): `tachyonc check` after every change to
tachyon source, its errors appended to the agent's own tool result, so
that the agent does not spend a call on it (docs/tool-gaps-014.md, gap 3:
124 eval calls and 21 dev calls ran `check` straight after a Write or
Edit).

Registered in .claude/settings.json for PostToolUse (Write, Edit,
MultiEdit, Bash), and by the agent eval with `run.py run --check-hook`
(0.17: tools/agent-hooks/settings-eval.json, per condition).
Reads the hook event (JSON) on stdin; prints, when the program has
errors, a PostToolUse `additionalContext`:

    tachyonc check main.tach: 2 errors
    main.tach:4:18: error[type error] expected 'i64', got '[u8]'
    main.tach:5:5: error[type error] undefined variable 'prinln' | help: did you mean 'println'?

at most 10 errors (the edited file's first), then `(N more: tachyonc
check ROOT)`. A clean program prints nothing. (0.17) The `try:` commands
of the errors that one `tachyonc fix` run applies to all of them (`fix
--only unsafe`, `alloc016`, `imports`, `pub`) come right after the head,
once each, with how many errors they answer:

    tachyonc check main.tach: 3 errors
    try: tachyonc fix --only unsafe main.tach   (3 of the errors)

and the compiler is run under the name the agent can type (`tachyonc` when
it is the one on PATH, else its path from the event's directory), so the
`try:` lines it prints run as they are.

- When: a Write, Edit or MultiEdit of a `.tach` file; a Bash call whose
  `tachyonc edit|refactor|fix|rewrite|undo` wrote (its summary line; not
  `--dry-run`), through any copy or variable (tachyonc_cmd.py).
- The root: under a checkout's compiler/src or compiler/std,
  compiler/src/main.tach (0.17: check reads std's edited files); else the nearest main.tach in the
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

(0.17; docs/query.md, "The agent hooks")
- A Bash call runs where its `cd`s lead (`cd WORKTREE && tachyonc edit
  ...`: WORKTREE's root and compiler); a shell command that writes a
  .tach file (`> f.tach`, `tee`, `cp`, `mv`) is a change too.
- The delta: after this session's first check of a root (hookstate.py
  keeps the last error set per root), `N errors (a new, b fixed, c as
  before)` and only the new errors; `0 errors (N fixed)` when it became
  clean.
- The tests: after a clean check of a program with tests/*.out, `tachyonc
  test ROOT --full` (not again within DEBOUNCE_S, never again for one
  slower than SLOW_MS; turn-end.py runs what was left), its counts and
  the newly failing cases. TACHYON_CHECK_TESTS=0 leaves them out.
- The hint `unfamiliar-construct` of hints.txt, once a session, when the
  same error is made twice or an error's help names the guide
  (TACHYON_HINTS=0: never).

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
# (0.17) The tests: each case at most CASE_TIMEOUT s, all of them
# TEST_TIMEOUT s; slower than SLOW_MS, not run after each edit again; not
# again within DEBOUNCE_S of the last run (the turn-end hook runs them).
CASE_TIMEOUT = 2
TEST_TIMEOUT = 15
SLOW_MS = 8000
DEBOUNCE_S = int(os.environ.get("TACHYON_TEST_DEBOUNCE") or 20)
TEST_CHARS = 1500
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
class _LazyState:
    """hookstate.py, loaded at its first use (a call that checks nothing
    does not pay for it); a stand-in when the copy of the hooks lacks it
    (as the agent eval's did before 0.17: no state, so no delta, no tests,
    no hints)."""

    def __getattr__(self, name):
        global hs
        try:
            hs = _load("hookstate", "hookstate.py")
        except OSError:
            hs = types.SimpleNamespace(load=lambda event: {}, save=lambda event, st: None,
                                       fingerprint=lambda root: ("", 0.0), has_tests=lambda root: False,
                                       hint=lambda key, **v: "", session_start=lambda event: None)
        return getattr(hs, name)


hs = _LazyState()
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
        # (0.17: std's files are checked through the compiler's root, which
        # `check` then reads std from when they differ from the built-in
        # std; std.tach as a root defines std twice)
        for sub, root in (("compiler/src/", "compiler/src/main.tach"), ("compiler/std/", "compiler/src/main.tach"),
                          ("compiler/std/", "compiler/std/std.tach")):
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


def compiler_for(where, ran=None, root=None):
    """The tachyonc to check with: the one the agent ran (a path), the
    override, the checkout's tools binary or build, the one on PATH.
    (0.17) For a program outside the compiler's own source (a test case,
    an example), target/tachyonc when it is newer than target/tools/tachyonc:
    a compiler just rebuilt from changed source checks the programs written
    for that change (the tools binary, older, reports what was fixed)."""
    if ran and os.sep in ran:
        p = ran if os.path.isabs(ran) else os.path.join(where, ran)
        if os.access(p, os.X_OK):
            return p
    env = os.environ.get("TACHYON_CHECK_COMPILER")
    if env and os.access(env, os.X_OK):
        return env
    top = checkout_root(where)
    if top:
        tools, build = (os.path.join(top, rel) for rel in ("target/tools/tachyonc", "target/tachyonc"))
        own = root and os.path.abspath(root).startswith(os.path.join(top, "compiler") + os.sep)
        if root and not own and os.access(build, os.X_OK) and os.access(tools, os.X_OK):
            try:
                if os.path.getmtime(build) > os.path.getmtime(tools):
                    return build
            except OSError:
                pass
        for p in (tools, build):
            if os.access(p, os.X_OK):
                return p
    return which("tachyonc")


def run_check(compiler, root, cwd):
    """The diagnostics of `check` on root (None: check's default), as
    dicts with the keys of --json; None when check could not run."""
    import subprocess  # (here: the hook's no-op path stays cheaper)

    shown = typed_name(compiler, cwd)

    def run(args):
        try:
            return subprocess.run([shown] + args[1:], executable=args[0], cwd=cwd, capture_output=True,
                                  text=True, timeout=TIMEOUT)
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


def typed_name(compiler, cwd):
    """The compiler as the agent would type it: `tachyonc` when that is the
    one on PATH, else its path from cwd when under it, else its path."""
    on_path = which("tachyonc")
    if on_path and os.path.realpath(on_path) == os.path.realpath(compiler):
        return "tachyonc"
    full = os.path.abspath(compiler)
    if full.startswith(cwd + os.sep):
        return os.path.relpath(full, cwd)
    return compiler


FIX = re.compile(r"^\S*tachyonc\S* fix\b")


def fix_commands(errors):
    """The `tachyonc fix ...` commands of the errors' try: lines, each with
    how many errors name it, in order of first appearance."""
    seen = {}
    for d in errors:
        for t in d.get("try") or []:
            if FIX.match(t):
                seen[t] = seen.get(t, 0) + 1
    return list(seen.items())


def line_of(d, summarized=()):
    """A diagnostic in check's one-line form (its `try:` lines but those in
    `summarized`, the fix commands printed once after the head)."""
    pos = f"{d['file']}:{d['line']}:{d['col']}: " if d.get("file") else ""
    text = f"{pos}{d.get('severity', 'error')}[{d.get('code', '')}] {d.get('message', '')}"
    for h in d.get("help") or []:
        text += " | help: " + h
    for n in d.get("notes") or []:
        text += " | note: " + n
    for t in d.get("try") or []:
        if t not in summarized:
            text += " | try: " + t
    return text


def fix_lines(errors):
    """The fix commands of the errors, once each, as `try:` lines after the
    head (with how many of the errors they answer), and the set of them."""
    n = len(errors)
    fixes = fix_commands(errors)
    return ([f"try: {cmd}   ({'the error' if n == 1 else 'all of them' if k == n else f'{k} of the errors'})"
             for cmd, k in fixes], {cmd for cmd, _ in fixes})


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
    fl, fixes = fix_lines(errors)
    lines += fl
    lines += [line_of(d, fixes) for d in errors[:MAX_SHOWN]]
    if n > MAX_SHOWN:
        lines.append(f"({n - MAX_SHOWN} more: tachyonc check{' ' + root_shown if root_shown else ''})")
    return "\n".join(lines)


WRITE_SUMMARY = re.compile(r"^(undid|patched|replaced|inserted|deleted|fixed|renamed|moved|rewrote|"
                           r"added|removed|changed|made|split|script|wrapped|formatted)\b.*\t", re.M)
# (0.17) A shell command writing a .tach file: `> f.tach`, `>> f.tach`,
# `tee [-a] f.tach`, `cp|mv ... f.tach`.
REDIRECT = re.compile(r"(?:^|[\s;])(?:\d?>>?|&>>?)\s*([^\s;|&<>]+\.tach)\b")


def shell_writes(command, cwd):
    """[(path, directory)] of the .tach files a shell command writes."""
    found = []
    for seg, words, here, assigns in tc.located(command, cwd):
        for m in REDIRECT.finditer(tc.HEREDOC.sub("<<HEREDOC\n", seg)):
            found.append((m.group(1), here, assigns))
        if words and words[0] in ("tee", "cp", "mv") and words[-1].endswith(".tach") and len(words) > 1:
            found.append((words[-1], here, assigns))
    out = []
    for path, here, assigns in found:
        path = tc.expand(path.strip("'\""), assigns)
        if path:
            out.append((os.path.normpath(os.path.join(here, path)), here))
    return out


REDIR = re.compile(r"^\d*(?:<<?<?|>>?|&>>?)$")


def operands(words):
    """words without redirections: `edit replace f < new.tach` reads
    new.tach as its stdin, it is not the root (0.17 validation round: the
    snippet was checked alone and its names reported as errors)."""
    out, skip = [], False
    for w in words:
        if skip:
            skip = False
        elif REDIR.match(w):
            skip = True
        elif not re.match(r"^\d*(?:<|>|&>)", w):
            out.append(w)
    return out


def trigger(event):
    """(file edited or None, root or None, compiler the agent ran or None,
    the directory the change was made from) when the event changed tachyon
    source; None otherwise. For a Bash call the directory follows its
    `cd`s (0.17: `cd WORKTREE && tachyonc edit ...` is WORKTREE's)."""
    tool = event.get("tool_name", "")
    inp = event.get("tool_input") or {}
    cwd = os.path.abspath(event.get("cwd") or os.getcwd())
    if tool in ("Write", "Edit", "MultiEdit"):
        path = inp.get("file_path") or ""
        if not path.endswith(".tach"):
            return None
        root = root_of(path)
        return (path, root, None, cwd) if root else None
    if tool == "Bash":
        command = inp.get("command", "")
        resp = event.get("tool_response") or {}
        out = (resp.get("stdout") or "") if isinstance(resp, dict) else str(resp)
        for sub, words, path, _, here in tc.calls_at(command, cwd):
            if sub not in WRITES or "--dry-run" in words:
                continue
            if not WRITE_SUMMARY.search(out):
                return None
            root = None
            for i, w in enumerate(words):
                if w == "--root" and i + 1 < len(words):
                    root = words[i + 1]
                elif w.startswith("--root="):
                    root = w[7:]
            ops = operands(words)
            if root is None and ops and ops[-1].endswith(".tach") and "new-file" not in ops:
                root = ops[-1]
            return (None, root, path or None, here)
        for path, here in shell_writes(command, cwd):
            if os.path.exists(path):
                root = root_of(path)
                if root:
                    return (path, root, None, here)
    return None


def default_root(cwd):
    """The root `check` takes in cwd when none is given: the tree's
    compiler, else main.tach."""
    for rel in ("compiler/src/main.tach", "main.tach"):
        p = os.path.join(cwd, rel)
        if os.path.exists(p):
            return p
    return None


def error_key(d):
    """An error as the delta compares it: its file's name, code and
    message (not its line: lines move as the file is edited)."""
    return "%s|%s|%s" % (os.path.basename(d.get("file") or ""), d.get("code") or "", d.get("message") or "")


def delta_report(errors, before, root_shown, edited):
    """(0.17) The check's context when an earlier check of the same root in
    this session is known (`before`: its error keys): the counts and what
    changed (`2 errors (1 new, 2 fixed, 1 as before)`), then only the new
    errors; `0 errors (2 fixed)` when the program became clean; nothing
    when it was and is clean."""
    if before is None:
        return report(errors, root_shown, edited)
    left = {}
    for k in before:
        left[k] = left.get(k, 0) + 1
    new = []
    for d in errors:
        k = error_key(d)
        if left.get(k, 0) > 0:
            left[k] -= 1
        else:
            new.append(d)
    fixed = sum(left.values())
    same = len(errors) - len(new)
    n = len(errors)
    where = " " + root_shown if root_shown else ""
    if n == 0:
        return f"tachyonc check{where}: 0 errors ({fixed} fixed)" if fixed else ""
    parts = []
    if new:
        parts.append(f"{len(new)} new")
    if fixed:
        parts.append(f"{fixed} fixed")
    if same:
        parts.append(f"{same} as before")
    lines = [f"tachyonc check{where}: {n} error{'s' if n != 1 else ''} ({', '.join(parts)})"]
    # the fix commands once, counted over all the errors (one fix run
    # answers them all), then the new errors without them
    fl, _ = fix_lines(errors)
    lines += fl
    shown = report(new, root_shown, edited).split("\n")[1:] if new else []
    lines += [x for x in shown if not x.startswith(("(", "try: "))]
    if len(new) > MAX_SHOWN:
        lines.append(f"({len(new) - MAX_SHOWN} more new: tachyonc check{where})")
    return "\n".join(lines)


def run_tests(compiler, root, cwd):
    """`tachyonc test ROOT --full` (0.17): {"passed", "failed": [names],
    "blocks": {name: text}, "ms", "build": False when it did not build}, or
    None when the compiler has no test command; {"slow": True} past
    TEST_TIMEOUT."""
    import subprocess
    t0 = time.time()
    try:
        r = subprocess.run([compiler, "test", root, "--full", "--timeout", str(CASE_TIMEOUT)], cwd=cwd,
                           capture_output=True, text=True, timeout=TEST_TIMEOUT)
    except subprocess.TimeoutExpired:
        return {"slow": True, "ms": int((time.time() - t0) * 1000)}
    except OSError:
        return None
    ms = int((time.time() - t0) * 1000)
    lines = r.stdout.splitlines()
    if not lines:
        return None
    m = re.match(r"^test .*?: (\d+) passed(?:, (\d+) failed)? \(", lines[0])
    if not m:
        if re.match(r"^test .*: (does not build|builds; no tests)", lines[0]):
            return {"passed": 0, "failed": [], "blocks": {}, "ms": ms,
                    "build": "does not build" not in lines[0], "text": "\n".join(lines[:12])}
        return None
    failed, blocks, cur = [], {}, None
    for line in lines[1:]:
        f = re.match(r"^FAIL (\S+?):", line)
        if f:
            cur = f.group(1)
            failed.append(cur)
            blocks[cur] = [line]
        elif cur and line.startswith("  "):
            blocks[cur].append(line)
        else:
            cur = None
    return {"passed": int(m.group(1)), "failed": failed, "ms": ms, "build": True,
            "blocks": {k: "\n".join(v) for k, v in blocks.items()}}


def test_report(cur, before, root_shown):
    """The tests' line for the agent, and the failures that are new since
    the last run in this session (all of them the first time), within
    TEST_CHARS."""
    where = " " + root_shown if root_shown else ""
    if not cur.get("build", True) or "text" in cur:
        return cur.get("text", "")
    failed = cur["failed"]
    head = f"tachyonc test{where}: {cur['passed']} passed" + (f", {len(failed)} failed" if failed else "")
    show = failed
    if before is not None and "failed" in before:
        was = set(before["failed"])
        new = [n for n in failed if n not in was]
        fixed = [n for n in before["failed"] if n not in failed]
        parts = []
        if new:
            parts.append(f"{len(new)} newly failing")
        if fixed:
            parts.append(f"{len(fixed)} fixed: " + ", ".join(fixed[:5]) + (", ..." if len(fixed) > 5 else ""))
        same = [n for n in failed if n in was]
        if same:
            parts.append("failing as before: " + ", ".join(same[:5]) + (", ..." if len(same) > 5 else ""))
        if parts:
            head += " (" + "; ".join(parts) + ")"
        show = new
    out = [head]
    size = len(head)
    for k, n in enumerate(show):
        b = cur["blocks"].get(n, "FAIL " + n)
        if k > 0 and size + len(b) > TEST_CHARS:
            out.append(f"({len(show) - k} more: tachyonc test{where})")
            break
        out.append(b)
        size += len(b)
    return "\n".join(out)


def run_dir_for(root, cwd):
    """(0.17) Where check runs: cwd, unless root is in another checkout than
    cwd (a worktree's file edited from a session in the main checkout, or
    the other way): then root's checkout, because `tachyonc check` reads
    std's files (compiler/std) from the directory it runs in, and their
    paths and try: lines are relative to it."""
    if not root:
        return cwd
    top = checkout_root(os.path.dirname(os.path.abspath(root)))
    if not top or checkout_root(cwd) == top:
        return cwd
    return top


def root_shown(root, cwd, run_dir):
    """root as the report names it: from cwd; from run_dir with `(in DIR)`
    when check ran elsewhere (the errors' paths are from there too)."""
    if not root:
        return ""
    if run_dir != cwd:
        where = os.path.relpath(run_dir, cwd) if run_dir.startswith(cwd + os.sep) else run_dir
        return f"{os.path.relpath(root, run_dir)} (in {where})"
    return os.path.relpath(root, cwd) if root.startswith(cwd + os.sep) else root


def verify(event, st, compiler, root, cwd, edited, at_turn_end=False):
    """Checks root (None: check's default in cwd), compares with this
    session's last check of it, runs its tests when they exist, are fast
    and are due; updates the session state st. (text for the agent, the
    record for the log) or None when check could not run."""
    t0 = time.time()
    run_dir = run_dir_for(root, cwd)
    diags = run_check(compiler, root, run_dir)
    ms = int((time.time() - t0) * 1000)
    if diags is None:
        return None
    key_root = root or default_root(cwd)
    shown = root_shown(root, cwd, run_dir)
    errors = [d for d in diags if d.get("severity") == "error"]
    roots = st.setdefault("roots", {})
    key = key_root or ("check@" + cwd)
    prev = roots.get(key) or {}
    keys = [error_key(d) for d in errors]
    text = report(errors, shown, edited) if at_turn_end else delta_report(errors, prev.get("errors"), shown, edited)
    texts = [text] if text else []
    entry = {"errors": keys, "time": time.time(), "root": key_root}
    fp = hs.fingerprint(key_root)[0] if key_root else ""
    entry["fp"] = fp
    # hint: the same mistake made twice, or an error that names a guide topic
    seen = st.setdefault("seen", {})
    hinted = st.setdefault("hinted", [])
    new_keys = set(keys) - set(prev.get("errors") or [])
    for d in errors:
        k = error_key(d)
        if k in new_keys:
            seen[k] = seen.get(k, 0) + 1
            if (seen[k] >= 2 or any("guide " in h for h in d.get("help") or [])) and \
                    "unfamiliar-construct" not in hinted:
                note = hs.hint("unfamiliar-construct", TACHYONC=tachyonc_shown(compiler, run_dir))
                if note:  # ("" when TACHYON_HINTS=0)
                    hinted.append("unfamiliar-construct")
                    texts.append(note)
            new_keys.discard(k)
    rec = {"kind": "check-hook", "tool": event.get("tool_name") or event.get("hook_event_name"),
           "root": shown[-120:], "errors": len(errors),
           "codes": sorted({d.get("code") or "" for d in errors}), "ms": ms}
    if prev.get("errors") is not None:
        rec["new"] = len([k for k in keys if k not in (prev.get("errors") or [])])
    last = prev.get("tests")
    if last:
        entry["tests"] = last
    if prev.get("slow"):
        entry["slow"] = True
    if not errors and key_root and os.environ.get("TACHYON_CHECK_TESTS", "1") != "0" \
            and hs.has_tests(key_root) and not prev.get("slow") and (not last or last.get("fp") != fp):
        due = at_turn_end or not last or time.time() - last.get("time", 0) >= DEBOUNCE_S \
            or bool(prev.get("errors"))
        if due:
            cur = run_tests(compiler, key_root, run_dir)
            if cur is not None:
                rec["test_ms"] = cur.get("ms", 0)
                if cur.get("slow") or cur.get("ms", 0) > SLOW_MS:
                    entry["slow"] = True
                    texts.append(f"tachyonc test{' ' + shown if shown else ''}: took over {SLOW_MS // 1000} s; "
                                 "not run after each edit (run tachyonc test)")
                if not cur.get("slow"):
                    texts.append(test_report(cur, last, shown))
                    entry["tests"] = {"fp": fp, "time": time.time(), "failed": cur.get("failed", []),
                                      "passed": cur.get("passed", 0)}
                    rec["tests_failed"] = len(cur.get("failed", []))
                    rec["tests_passed"] = cur.get("passed", 0)
    roots[key] = entry
    return "\n".join(t for t in texts if t), rec


def tachyonc_shown(compiler, cwd):
    """The compiler as the agent would type it."""
    if not compiler:
        return "tachyonc"
    if compiler.startswith(cwd + os.sep):
        return os.path.relpath(compiler, cwd)
    return "tachyonc" if os.path.basename(compiler) == "tachyonc" and which("tachyonc") == compiler \
        else compiler


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
    edited, root, ran, cwd = found
    if root and not os.path.isabs(root):
        root = os.path.normpath(os.path.join(cwd, root))
    if ran and os.sep in ran and not os.path.isabs(ran):
        ran = os.path.join(cwd, ran)
    compiler = compiler_for(cwd if not edited else os.path.dirname(os.path.abspath(edited)), ran, root)
    if not compiler:
        return 0
    st = hs.load(event)
    got = verify(event, st, compiler, root, cwd, edited)
    if got is None:
        return 0
    text, rec = got
    hs.save(event, st)
    record(event, cwd, rec)
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
