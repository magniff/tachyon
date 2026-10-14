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
  edit/refactor/fix/rewrite/undo` calls with whether they wrote. (0.15)
  tachyonc is recognised through copies (`target/tc0`,
  `target/tools/tachyonc`) and shell variables (`T=...; $T query`), by
  tachyonc_cmd.py; such a record says `via` what it ran.
- Read and Grep calls on .tach files are logged, not blocked (Edit needs
  a prior Read); Edit and Write calls on .tach files are logged (whether
  the file existed), never blocked.

Commands are split at `;`, `|`, `&&` and newlines outside quotes, so a
path inside a quoted script or message is not a command's file; a write
is judged by the files it writes (sed's file operands, the paths Python
opens for writing), never by every path the command names, and nothing
under target/ or a temporary directory is compiler source (0.12).

The log is .git/agent-tools.jsonl in the main checkout, shared by every
worktree (found without running git: up to a `.git`, and from a
worktree's `.git` file to its common directory); every record carries
who made it: the session, the harness's agent id and transcript when the
event has them, and the checkout (a parallel agent's worktree).
tools/agent-tool-usage.py --hook-log summarizes it. Enforcement
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
import types

# (0.15) tachyonc through copies and shell variables: tachyonc_cmd.py, next
# to this file, loaded by path (`python3 -I` leaves this directory out of
# sys.path; importlib.util would cost 40 ms of imports on every call).
tc = types.ModuleType("tachyonc_cmd")
tc.__file__ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tachyonc_cmd.py")
with open(tc.__file__) as _fh:
    exec(compile(_fh.read(), tc.__file__, "exec"), tc.__dict__)

READERS = {"grep", "rg", "egrep", "fgrep", "sed", "head", "tail", "cat", "awk", "less", "more"}
SOURCE = re.compile(r"(\.tach\b|compiler/src\b|compiler/std\b)")
HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n.*?\n\s*\1\s*(\n|$)", re.S)
ESCAPE = re.compile(r"#\s*no-(?:query|tool):\s*(.+)")
# A .tach file of the compiler's own source (not a test, a doc, a copy).
COMPILER_TACH = re.compile(r"((?:[\w.~-]+/)*compiler/(?:src|std)/[\w./*-]*\.tach)\b")
SCRATCH = re.compile(r"(^|/)(target|tmp|private/tmp|var/folders)/")
TOOL_SUBS = ("edit", "refactor", "fix", "rewrite", "undo")
SUMMARY = re.compile(r"^(undid|patched|replaced|inserted|deleted|fixed|renamed|moved|rewrote|"
                     r"added|removed|changed|made|split|script)\b.*\t", re.M)


def checkout_of(cwd):
    """(checkout root, shared git directory) of the checkout holding cwd,
    found without running git (a harness guard may refuse git inside a
    worktree): up from cwd to a `.git`; a worktree's `.git` is a file
    naming its git directory, whose `commondir` names the shared one."""
    d = os.path.abspath(cwd or os.getcwd())
    while True:
        g = os.path.join(d, ".git")
        if os.path.isdir(g):
            return d, g
        if os.path.isfile(g):
            try:
                with open(g) as fh:
                    text = fh.read().strip()
            except OSError:
                return d, None
            if not text.startswith("gitdir:"):
                return d, None
            gd = text[len("gitdir:"):].strip()
            if not os.path.isabs(gd):
                gd = os.path.normpath(os.path.join(d, gd))
            try:
                with open(os.path.join(gd, "commondir")) as fh:
                    common = fh.read().strip()
                if not os.path.isabs(common):
                    common = os.path.normpath(os.path.join(gd, common))
                return d, common
            except OSError:
                return d, gd
        parent = os.path.dirname(d)
        if parent == d:
            return None, None
        d = parent


def git_dir(cwd):
    return checkout_of(cwd)[1]


# Who is working: logged with every record, so that parallel agents (one
# session, one transcript, each in a worktree of its own) are told apart.
IDENT = {}


def identity(event, cwd):
    """The fields that identify the agent of a hook event: its session, its
    agent id and transcript when the harness gives them, and the checkout
    it works in (the worktree of a parallel agent)."""
    ident = {"session": (event.get("session_id") or "")[:8],
             "agent": os.path.basename(event.get("transcript_path") or "")[:20]}
    if event.get("agent_id"):
        ident["agent_id"] = str(event.get("agent_id"))[:40]
    if event.get("agent_type"):
        ident["agent_type"] = str(event.get("agent_type"))[:40]
    root = checkout_of(cwd)[0]
    if root:
        ident["worktree"] = root[-120:]
    return ident


def log(gd, record):
    if not gd:
        return
    for k, v in IDENT.items():
        record.setdefault(k, v)
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


def segments(command):
    """The simple commands of a command line: split at `;`, `|`, `&`, `||`,
    `&&` and newlines outside quotes, comments (`# ...`) and here-document
    bodies left out; so a `;` or a path inside a quoted string (a sed
    script, a commit message) does not start a command."""
    body = HEREDOC.sub("<<HEREDOC\n", command)
    out, cur, quote, i = [], [], None, 0
    while i < len(body):
        c = body[i]
        if quote:
            cur.append(c)
            if c == "\\" and quote == '"' and i + 1 < len(body):
                cur.append(body[i + 1])
                i += 1
            elif c == quote:
                quote = None
        elif c == "\\" and i + 1 < len(body):
            cur.append(c + body[i + 1])
            i += 1
        elif c in "'\"":
            quote = c
            cur.append(c)
        elif c == "#" and (not cur or cur[-1] in " \t"):
            while i < len(body) and body[i] != "\n":
                i += 1
            continue
        elif c == "&" and ((cur and cur[-1] == ">") or body[i + 1:i + 2] == ">"):
            cur.append(c)  # (2>&1, &>)
        elif c in ";|&\n":
            out.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return [seg.strip() for seg in out if seg.strip()]


def source_reads(command):
    """(program, words) of each simple command reading .tach source."""
    found = []
    for seg in segments(command):
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
        args = without_outputs(words[1:])
        if prog == "sed" and any(a.startswith("-i") for a in args):
            continue  # an edit, not a read (logged as such)
        if prog == "cat" and (">" in seg):
            continue  # writing a file
        if any(reads_source(a) for a in file_args(prog, args)):
            found.append((prog, args))
    return found


def without_outputs(args):
    """The words of a command without its output redirections (`> x.tach`,
    `2>/dev/null`): a file written is not read."""
    out, skip = [], False
    for a in args:
        if skip:
            skip = False
            continue
        m = re.match(r"^(\d*|&)>>?(&\d*)?(.*)$", a)
        if m:
            skip = not m.group(3) and not m.group(2)
            continue
        out.append(a)
    return out


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
    """A .tach file, or a directory of them that grep -r would read; not a
    scratch file (target/, /tmp: a generated program, a copy)."""
    if SCRATCH.search(path):
        return False
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


def in_place_operands(prog, args):
    """The files of an in-place sed or perl, and sed's script: the script
    (the first operand, unless given with -e or -f; perl's with -e) is not
    a file, nor the suffix of macOS's `sed -i ''`."""
    operands, script, skip, given = [], "", False, False
    for i, a in enumerate(args):
        if skip:
            skip = False
            continue
        if a in ("-e", "-f", "--expression", "--file"):
            skip, given = True, True
            if i + 1 < len(args) and not script:
                script = args[i + 1]
            continue
        if a == "-i" and prog == "sed" and i + 1 < len(args) and (args[i + 1] == "" or args[i + 1].startswith(".")):
            skip = True
            continue
        if a.startswith("-") or not a:
            continue
        operands.append(a)
    if prog == "sed" and not given and operands:
        script, operands = operands[0], operands[1:]
    return operands, script


def source_rewrites(command):
    """(program, files, script) of each part of command that rewrites
    compiler source in place: sed -i, perl -i, or Python writing a file
    (its script is usually a here-document, so all of command counts)."""
    found = []
    scratch_cwd = False
    for seg in segments(command):
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
        if prog == "cd" and args:
            # (relative paths after `cd target/x` are a scratch copy's)
            scratch_cwd = bool(SCRATCH.search(args[0].rstrip("/") + "/"))
            continue
        if prog in ("sed", "perl") and in_place(prog, args):
            operands, script = in_place_operands(prog, args)
            files = [a for a in operands if compiler_paths(a) and not (scratch_cwd and not a.startswith("/"))]
            if files:
                found.append(("sed -i" if prog == "sed" else "perl -pi", files, script))
    if re.search(r"\bpython[\d.]*\b", command) and re.search(r"\.write\(|write_text\(|write_bytes\(", command):
        targets = python_targets(command)
        if targets is None:
            files = compiler_paths(command)
        else:
            files = [f for t in targets for f in compiler_paths(t)]
        if files and not (scratch_cwd and not any(f.startswith("/") for f in files)):
            found.append(("python", files, ""))
    return found


def python_targets(command):
    """The files a Python script in command opens for writing: the
    literal paths of `open(PATH, 'w'|'a'|...)` and `Path(PATH).write_text`,
    or of a variable assigned one; None when a write's file cannot be told
    (then every compiler path named counts)."""
    targets, unknown = [], False

    def literal_of(name):
        m = re.search(r"\b%s\s*=\s*(?:[\w.]*Path\(\s*)?(?:r|b|f)?(['\"])(.+?)\1" % re.escape(name), command)
        return m.group(2) if m else None

    for m in re.finditer(r"\bopen\(\s*([^,()]+?)\s*,\s*(?:mode\s*=\s*)?(?:r|b)?(['\"])([^'\"]*)\2", command):
        if not re.search(r"[wax+]", m.group(3)):
            continue
        arg = m.group(1).strip()
        lit = re.match(r"^(?:r|b|f)?(['\"])(.*)\1$", arg)
        path = lit.group(2) if lit else (literal_of(arg) if re.match(r"^\w+$", arg) else None)
        if path is None:
            unknown = True
        else:
            targets.append(path)
    for m in re.finditer(r"(?:\b[\w.]*Path\(\s*(?:r|b|f)?(['\"])(.+?)\1\s*\)|\b(\w+))\.write_(?:text|bytes)\(", command):
        path = m.group(2) if m.group(2) else literal_of(m.group(3))
        if path is None:
            unknown = True
        else:
            targets.append(path)
    return None if unknown else targets


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


GREP_ANY = "tachyonc query grep TEXT [--comments|--strings|--code] | tachyonc query items MODULE --comments"
NAME = re.compile(r"\w+(?:(?:::|\.)\w+)*")


def grep_patterns(prog, args, first):
    """The patterns of a grep: each `-e P` (or `--regexp=P`), else the first
    operand; each split into its alternatives (`a\\|b`, `a|b`)."""
    pats = [args[i + 1] for i, a in enumerate(args[:-1]) if a in ("-e", "--regexp")]
    pats += [a.split("=", 1)[1] for a in args if a.startswith("--regexp=")]
    if not pats:
        pats = [first]
    fixed = prog == "fgrep" or any(a in ("-F", "--fixed-strings") or
                                   (re.match(r"^-[a-zA-Z]+$", a) and "F" in a) for a in args)
    out = []
    for p in pats:
        out += [p] if fixed else [x for x in re.split(r"\\\||\|", p) if x]
    return out, fixed


def grep_suggestion(prog, args, first):
    """(0.13: query grep, a literal search with each hit's item and whether
    it is in code, a comment or a string; 0.14: a regex or several
    alternatives are never glued into one name.) A name is suggested to
    `query refs` (which takes several) and to `query grep`, one call each;
    a regex to `query grep` of its longest literal run."""
    alts, fixed = grep_patterns(prog, args, first)
    if not alts:
        return GREP_ANY
    unescaped = [re.sub(r"\\([^\w])", r"\1", a) for a in alts]
    # (`\bname\b`, `\<name\>`, `^name`: a name; `\w`, `\s`, `.*` are not)
    names = [re.sub(r"^(\\b|\\<|\^)|(\\b|\\>|\$)$", "", a) for a in alts]
    if all(NAME.fullmatch(n) for n in names):
        if len(names) > 4:
            return f"tachyonc query refs {' '.join(names)} | {GREP_ANY}"
        greps = " | ".join(f"tachyonc query grep {n}" for n in names)
        return f"tachyonc query refs {' '.join(names)} | {greps}"
    ere = prog in ("egrep", "rg") or any(re.match(r"^-[a-zA-Z]*[EP]", a) for a in args)
    special = r"[\[\]*()+?{}^$\\]|\.\*" if ere else r"[\[\]*^$\\]|\.\*"
    literal = [u for u in unescaped if fixed or not re.search(special, u)]
    if len(literal) == len(alts) and len(alts) <= 4:
        return " | ".join(f"tachyonc query grep {shlex.quote(u)}" for u in literal)
    # A regex: its longest literal run, for query grep to narrow it.
    runs = []
    for a in alts:
        a = re.sub(r"\\[bBwWsSdD<>]|\[[^\]]*\]|[.*+?{}()^$|\\]", " ", a)
        runs += [r for r in re.split(r"\s+", a) if len(r) >= 3]
    if runs:
        best = max(runs, key=len)
        return f"tachyonc query grep {shlex.quote(best)} | {GREP_ANY}"
    return GREP_ANY


def suggestion(prog, args):
    pattern = next((a for a in args if not a.startswith("-")), "")
    m = re.search(r"\b(?:fn|struct|enum|trait|const|static|type|mod)\s+(\w+)", pattern)
    if m:
        return f"tachyonc query show {m.group(1)}"
    files = [a for a in file_args(prog, args) if a.endswith(".tach")]
    compiler = bool(files) and bool(compiler_paths(files[0]))
    # `sed -n 'N,Mp' FILE`: the item holding line N, or the lines
    m = re.match(r"^(\d+)(?:,(\d+))?p$", pattern)
    if prog == "sed" and m and files:
        a, b = m.group(1), m.group(2) or m.group(1)
        text = f"tachyonc query text {files[0]}:{a}-{b}"
        return f"tachyonc query show {files[0]}:{a} | {text}" if compiler else text
    if prog in ("grep", "rg", "egrep", "fgrep"):
        return grep_suggestion(prog, args, pattern)
    if files and prog == "head":
        n = next((args[i + 1] for i, a in enumerate(args[:-1]) if a == "-n"), None) \
            or next((a[1:] for a in args if re.match(r"^-\d+$", a)), "10")
        text = f"tachyonc query text {files[0]}:1-{n}"
        return f"tachyonc query show MODULE::header | MODULE::use | {text}" if compiler else text
    if files and prog == "cat":
        return f"tachyonc query show {files[0]} (a whole small file) | tachyonc query text {files[0]}:A-B"
    if files:
        if not compiler:
            return f"tachyonc query text {files[0]}:A-B"
        return f"tachyonc query stats {files[0]} | tachyonc query show FILE:LINE | tachyonc query text {files[0]}:A-B"
    return "tachyonc query show NAME | tachyonc query items MODULE | tachyonc query text FILE:A-B"


def via(calls):
    """{"via": PATH} when the tachyonc run was not plain `tachyonc` (a copy,
    a shell variable): the record says how the agent ran it."""
    paths = sorted({c[2] or "$VAR" for c in calls if os.path.basename(c[2]) != "tachyonc"})
    return {"via": " ".join(paths)[:120]} if paths else {}


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    cwd = event.get("cwd") or os.getcwd()
    gd = git_dir(cwd)
    IDENT.update(identity(event, cwd))
    phase = event.get("hook_event_name", "")
    tool = event.get("tool_name", "")
    inp = event.get("tool_input") or {}

    if tool == "Bash":
        command = inp.get("command", "")
        calls = tc.calls(command)
        if phase == "PostToolUse":
            resp = event.get("tool_response") or {}
            out = (resp.get("stdout") or "") if isinstance(resp, dict) else str(resp)
            err = (resp.get("stderr") or "") if isinstance(resp, dict) else ""
            if any(c[0] == "query" for c in calls):
                log(gd, {"kind": "query-result", **via(calls),
                         "command": command[:300], "out_lines": out.count("\n"),
                         "out_bytes": len(out), "stderr": err[:300]})
            tool_call = next((c for c in calls if c[0] in TOOL_SUBS), None)
            if tool_call:
                # (written: a summary line; not a dry run's diff, not a refusal)
                written = bool(SUMMARY.search(out)) and "--dry-run" not in command
                log(gd, {"kind": "tool-result", "tool": tool_call[0], **via(calls),
                         "command": command[:300], "written": written,
                         "compiler": tool_target(command), "stderr": err[:300]})
            return 0
        if any(c[0] == "query" for c in calls):
            log(gd, {"kind": "query", **via(calls), "command": command[:300]})
        rewrites = source_rewrites(command)
        if rewrites:
            prog, files, script = rewrites[0]
            esc = ESCAPE.search(command)
            if esc:
                log(gd, {"kind": "edit-escape", "program": prog,
                         "files": files[:5], "reason": esc.group(1).strip()[:300], "command": command[:300]})
                return 0
            if not query_ready(gd, cwd):
                log(gd, {"kind": "edit", "program": prog,
                         "files": files[:5], "command": command[:300]})
                return 0
            log(gd, {"kind": "edit-blocked", "program": prog,
                     "files": files[:5], "command": command[:300]})
            sys.stderr.write("blocked hook.edit-tool: %s rewriting compiler source (%s)\n"
                             "try: %s | override: append '# no-tool: <why the tools are not enough>'\n"
                             % (prog, files[0], edit_suggestion(prog, files, script)))
            return 2
        reads = source_reads(command)
        if not reads:
            return 0
        esc = ESCAPE.search(command)
        if esc:
            log(gd, {"kind": "escape",
                     "reason": esc.group(1).strip()[:300], "command": command[:300]})
            return 0
        if not query_ready(gd, cwd):
            log(gd, {"kind": "read-unenforced", "command": command[:300]})
            return 0
        prog, args = reads[0]
        log(gd, {"kind": "blocked",
                 "program": prog, "command": command[:300]})
        sys.stderr.write("blocked hook.query-first: %s on .tach source\n"
                         "try: %s | override: append '# no-query: <why query is not enough>'\n"
                         % (prog, suggestion(prog, args)))
        return 2

    if tool in ("Edit", "Write", "MultiEdit") and phase == "PreToolUse":
        target = inp.get("file_path") or ""
        if target.endswith(".tach"):
            log(gd, {"kind": tool.lower(), "target": target[:200],
                     "existed": os.path.exists(target),
                     "bytes": len(inp.get("new_string") or inp.get("content") or "")})
        return 0
    if tool in ("Read", "Grep") and phase == "PreToolUse":
        target = inp.get("file_path") or inp.get("path") or ""
        pattern = inp.get("pattern", "")
        if SOURCE.search(target) or (tool == "Grep" and SOURCE.search(inp.get("glob", "") + inp.get("type", ""))):
            log(gd, {"kind": tool.lower(),
                     "target": target[:200], "pattern": pattern[:120],
                     "offset": inp.get("offset"), "limit": inp.get("limit")})
    return 0


if __name__ == "__main__":
    sys.exit(main())
