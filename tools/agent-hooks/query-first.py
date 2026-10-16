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
  Source is the compiler's (compiler/src, compiler/std) and any program
  being worked on (examples/, bench/, a .tach elsewhere); a .tach under a
  tests/ directory (a test case, a refactoring fixture, an agent-eval
  task's data) is read freely, and logged as `read-fixture` (0.14).
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

(0.17) Each simple command of a line is judged on its own, in the
directory its `cd`s lead to, with `$VAR`s assigned on the line expanded;
the message names the command that reads. A whole file under 300 lines
is read freely with cat, head, tail, sed -n (`read-small`); a .tach file
outside any program's module tree (not a main.tach, not declared by a
`mod` line, not under compiler/, examples/, bench/) is not source
(`read-scratch`). A blocked record logs its `try:` commands. Python is
judged by the script it runs, not by a here-document written to a file.
After a Bash call (PostToolUse): a `# no-query:` reason that wants line
numbers for the Edit tool is answered (`edit insert --after NAME`, `query
def NAME`); the `repeat-query` hint of hints.txt after the third show,
refs, def or callers in a row on related items, once a session, not once
`query context` ran, never with TACHYON_HINTS=0 (state: hookstate.py,
its `query` part).

(0.17, E6) TACHYON_QUERY_MODE=rewrite: a read whose query is not in doubt
(`sed -n 'A,Bp'`, `head`, `tail -n N`, `cat`, `grep` of one name) runs as
that query (PreToolUse `updatedInput` with permission `allow`, the
`rewritten` note of hints.txt beside its result), logged as `rewritten`;
any other read is blocked as in the default mode (`block`), and so is
every write.

(n8) In rewrite mode each reading command of a line is replaced by its
query where it stands, the line's other commands, separators and pipes
kept as typed (rewrite_parts, translate): on the compiler tasks of
iteration 3 every blocked line had 2-16 commands, and the reads in them
were grep of texts or alternatives (-i, -r, `DIR/*.tach`, `^use`), sed -n,
head, cat (`cat F | head`). grep becomes `query grep TEXT...` (or `query
refs` of one name); a read it cannot translate blocks the line, the
message naming every blocked read with its `try:` and the reads that will
run as queries on the retry, so one retry clears the line. A file that is
not there is left as typed (nothing is read).
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

class _LazyState:
    """hookstate.py (0.17: the hints, the last queries), loaded at its
    first use; a stand-in without hints when the copy of the hooks lacks
    it."""

    def __getattr__(self, name):
        global hs
        mod = types.ModuleType("hookstate")
        mod.__file__ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hookstate.py")
        try:
            with open(mod.__file__) as fh:
                exec(compile(fh.read(), mod.__file__, "exec"), mod.__dict__)
            hs = mod
        except OSError:
            hs = types.SimpleNamespace(load=lambda event, part=None: {},
                                       save=lambda event, st, part=None: None,
                                       hint=lambda key, **v: "", text=lambda key, **v: "")
        return getattr(hs, name)


hs = _LazyState()

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


SMALL_READERS = {"cat", "head", "tail", "sed", "nl", "less", "more"}
SMALL_LINES = 300


def source_reads(command, cwd=None, fixtures=None, small=None, scratch=None):
    """(program, words, segment, [(operand, full path or None)]) of each
    simple command reading .tach source. (0.17) Each command is judged on
    its own, in the directory its `cd`s lead to, with `$VAR`s assigned on
    the line expanded; a command that reads only test data is added to
    `fixtures`, one that reads only files outside any program's module tree
    (a probe, a scratch copy) to `scratch`, one that reads whole small
    files (cat, head, sed -n ... of files under SMALL_LINES lines) to
    `small`; none of those is blocked."""
    found = []
    cwd = cwd or os.getcwd()
    for idx, (seg, words, here, assigns) in enumerate(tc.located(command, cwd)):
        if not seg.strip() or seg.strip()[:1] == "#":
            continue
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
        files = []
        for a in file_args(prog, args):
            e = tc.expand(a, assigns)
            if not reads_source(a):
                continue
            files.append((a, os.path.normpath(os.path.join(here, e)) if e is not None else None))
        if not files:
            continue
        kinds = [file_kind(f, cwd, tc.expand(a, assigns)) for a, f in files]
        if all(k == "fixture" for k in kinds):
            if fixtures is not None:
                fixtures.append((prog, args))
            continue
        if all(k in ("fixture", "scratch") for k in kinds):
            if scratch is not None:
                scratch.append((prog, args))
            continue
        if prog in SMALL_READERS and all(k != "source" or (f and lines_of(f) < SMALL_LINES)
                                         for k, (_, f) in zip(kinds, files)):
            if small is not None:
                small.append((prog, args))
            continue
        found.append(Read(prog, args, seg, [x for k, x in zip(kinds, files) if k == "source"], idx))
    return found


class Read(tuple):
    """A read of source: (program, words, segment, [(operand, full path)]),
    and `idx`, the index of its command in tc.located(command)."""

    def __new__(cls, prog, args, seg, files, idx):
        t = tuple.__new__(cls, (prog, args, seg, files))
        t.idx = idx
        return t


def file_kind(full, cwd, typed=None):
    """`fixture` (under a tests/ directory of the checkout), `scratch` (a
    temporary or build directory: target/, /tmp, as the path reads inside
    its checkout, or as typed outside any; or a .tach file outside any
    program's module tree), else `source`. An operand whose path is not
    known (a variable set in an earlier call) is source."""
    if full is None:
        return "source"
    if fixture(full, "", cwd):
        return "fixture"
    top = checkout_of(os.path.dirname(full))[0]
    shown = os.path.relpath(full, top) if top else (typed or full)
    if SCRATCH.search(shown) or not is_program_source(full):
        return "scratch"
    return "source"


def is_program_source(full):
    """(0.17) Whether a .tach file belongs to a program: the compiler's
    source and std, examples/ and bench/ of the checkout, a main.tach, a
    file a `mod NAME;` line of its directory (or its parent module's file)
    declares; a directory is. A probe the agent wrote next to the program,
    or in a scratch directory, is not."""
    if not full.endswith(".tach") or os.path.isdir(full) or not os.path.exists(full):
        return True
    if "/compiler/src/" in full or "/compiler/std/" in full:
        return True
    top = checkout_of(os.path.dirname(full))[0]
    if top and re.match(r"^(examples|bench)/", os.path.relpath(full, top)):
        return True
    base = os.path.basename(full)
    if base == "main.tach":
        return True
    d = os.path.dirname(full)
    stem = base[:-5]
    if base == "mod.tach":
        stem, d = os.path.basename(d), os.path.dirname(d)
    decl = re.compile(r"^\s*(?:pub\s+)?mod\s+%s\s*;" % re.escape(stem), re.M)
    cands = []
    try:
        cands = [os.path.join(d, f) for f in sorted(os.listdir(d))[:200] if f.endswith(".tach")]
    except OSError:
        pass
    cands += [os.path.join(d, "mod.tach"), d + ".tach"]
    for c in cands:
        if c == full:
            continue
        try:
            with open(c, errors="replace") as fh:
                if decl.search(fh.read(65536)):
                    return True
        except OSError:
            continue
    return False


def lines_of(path):
    """The number of lines of a file (counted up to SMALL_LINES); a large
    number when it cannot be read."""
    try:
        with open(path, "rb") as fh:
            data = fh.read(SMALL_LINES * 400)
    except OSError:
        return 1 << 30
    n = data.count(b"\n")
    return n if len(data) < SMALL_LINES * 400 else max(n, SMALL_LINES)


def module_of(full):
    """The module a .tach file holds, for `query items`: crate::a::b under
    compiler/src or a program's root directory, std for compiler/std."""
    m = re.search(r"/compiler/(src|std)/(.+)\.tach$", full)
    if m:
        if m.group(1) == "std":
            return "std"
        rel = m.group(2)
    else:
        d = os.path.dirname(full)
        rel = None
        for _ in range(6):
            if os.path.exists(os.path.join(d, "main.tach")):
                rel = os.path.relpath(full, d)[:-5]
                break
            d = os.path.dirname(d)
        if rel is None:
            return None
    parts = [x for x in rel.split("/") if x]
    if parts and parts[-1] in ("main", "mod"):
        parts = parts[:-1]
    return "::".join(["crate"] + parts)


def fixture(path, base, cwd):
    """Whether path (after `cd base`, from cwd) is under a tests/ directory
    of the checkout: a test case, a fixture, an eval task's data."""
    full = os.path.normpath(os.path.join(cwd or os.getcwd(), base, path))
    root = checkout_of(cwd)[0] if cwd else None
    if root and (full + "/").startswith(root.rstrip("/") + "/"):
        full = os.path.relpath(full, root)
    return bool(FIXTURE.search(full))


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


SOURCE_DIRS = re.compile(r"^(\./)?(compiler/src|compiler/std|examples|bench)/?$")
# (0.14) Test data: a case, a fixture, an eval task's program; read freely.
FIXTURE = re.compile(r"(^|/)tests/")


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
    script = python_text(command)
    if script and re.search(r"\.write\(|write_text\(|write_bytes\(", script):
        targets = python_targets(script)
        if targets is None:
            files = compiler_paths(script)
        else:
            files = [f for t in targets for f in compiler_paths(t)]
        if files and not (scratch_cwd and not any(f.startswith("/") for f in files)):
            found.append(("python", files, ""))
    return found


def python_text(command):
    """(0.17) The Python a command runs, as far as it shows: the
    here-documents given to a python command and its own words (`-c`); a
    here-document written by `cat > x.py` is not run, so a script that
    writes files is not taken for one that runs. "" when no python runs."""
    texts = []
    for m in HEREDOC.finditer(command):
        start = command.rfind("\n", 0, m.start()) + 1
        last = re.split(r"&&|\|\||[;&]", command[start:m.start()])[-1]
        if re.search(r"(^|[\s/])python[\d.]*\b", last) and not re.search(r">\s*\S+\s*$", last.split("<<")[0]):
            texts.append(m.group(0))
    for seg in tc.segments(command):
        words = seg.split()
        while words and "=" in words[0]:
            words = words[1:]
        if words and re.match(r"^(\S*/)?python[\d.]*$", words[0]) or \
                (words[:1] in (["env"], ["time"]) and any(re.match(r"^(\S*/)?python[\d.]*$", w) for w in words[1:3])):
            texts.append(seg)
    return "\n".join(texts)


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
    text is `edit patch FILE:N --old a --new b`; (0.18.1) without a line,
    every line's: `edit patch FILE --old a --new b --all`, one per file
    (at most 3). A regex (`\\b`, `.*`, `[..]`), `&` or several commands:
    the general form."""
    fs = [re.sub(r"^.*?(compiler/(?:src|std)/)", r"\1", f) for f in files]
    f = fs[0]
    m = re.match(r"^(\d+)?s([/|#,])((?:\\.|(?!\2).)*)\2((?:\\.|(?!\2).)*)\2g?$", script or "")
    if prog == "sed -i" and m and not re.search(r"(?<!\\)[\^$*.\[\]+?(){}]|\\[bBwWsSdD<>]", m.group(3)) \
            and "&" not in m.group(4) and not re.search(r"\\[0-9n]", m.group(4)):
        old = re.sub(r"\\(.)", r"\1", m.group(3))
        new = re.sub(r"\\(.)", r"\1", m.group(4))
        pair = f"--old {shlex.quote(old)} --new {shlex.quote(new)}"
        if m.group(1):
            return f"tachyonc edit patch {f}:{m.group(1)} {pair}"
        return " ; ".join(f"tachyonc edit patch {x} {pair} --all" for x in fs[:3])
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


def blocked_message(command, prog, args, seg, files, cwd, others=(), translated=()):
    """(the message for a blocked read, its `try:` commands): which command
    of the line reads source (when the line has several, the others are
    not the problem), how long the file is when it is too long to read
    whole, and complete commands to run instead. (n8) The line's other
    blocked reads (`others`) each get a `try:` too, so that one retry
    clears them all; in rewrite mode the reads it could run as queries
    (`translated`: (part, query, clause)) are named: once the blocked
    ones are changed, the line runs with those as their queries."""
    parts = [s for s in tc.segments(command) if s.strip() and not s.strip().startswith("#")]

    def where(sg):
        what = "`%s`" % (sg if len(sg) <= 120 else sg[:117] + "...")
        if len(parts) > 1:
            what += " (command %d of %d on the line" % (
                next((i + 1 for i, p in enumerate(parts) if p.strip() == sg.strip()), 1), len(parts))
        return what
    what = where(seg)
    if len(parts) > 1:
        what += "; the others are not blocked)" if not others else ")"
    lines = ["blocked hook.query-first: %s reads .tach source" % what]
    tries = [suggestion(prog, args)]
    for arg, full in files[:1]:
        n = lines_of(full) if full else None
        if n is not None and n < (1 << 30):
            mod = module_of(full) or arg
            lines.append("%s is %s lines (a file under %d is read whole freely): `tachyonc query items %s` "
                         "lists its items, `tachyonc query show NAME` one of them, `tachyonc query show %s:LINE` "
                         "the item at a line" % (arg, format(n, ","), SMALL_LINES, mod, arg))
            if mod != arg:
                tries.append("tachyonc query items %s" % mod)
    lines += ["try: %s" % t for t in tries]
    for o in others:
        t = suggestion(o[0], o[1])
        tries.append(t)
        lines.append("also blocked: %s); try: %s" % (where(o[2]), t))
    if translated:
        lines.append("the line's other reads of .tach source run as their queries on a retry: " +
                     "; ".join("`%s` as `%s`" % (p if len(p) <= 80 else p[:77] + "...", q)
                               for p, q, _ in translated))
    lines.append("override: append '# no-query: <why query is not enough>'")
    return "\n".join(lines) + "\n", tries


# (0.17, E6) Rewrite instead of block: TACHYON_QUERY_MODE=rewrite runs a
# read whose query is not in doubt as that query (PreToolUse `updatedInput`,
# with a one-line note beside its result), so the agent loses no turn to a
# refusal; anything else is blocked as before. Writes are always blocked.
def query_mode():
    return "rewrite" if os.environ.get("TACHYON_QUERY_MODE", "block") == "rewrite" else "block"


def tachyonc_for(event, cwd, here, own=()):
    """The tachyonc a rewritten command runs: (n8) the one the line itself
    runs (`own`: paths from cwd), else the one the agent last ran in this
    session, else target/tools/tachyonc, `tachyonc` on PATH,
    target/tachyonc of cwd; as a path that works from `here` (the
    directory the command runs in). None when there is none."""
    def cands():  # (lazily: the session state and PATH cost a few ms)
        yield from own
        last = (hs.load(event, "query") or {}).get("tachyonc")
        if last:
            yield last
        yield os.path.join(cwd, "target", "tools", "tachyonc")
        import shutil
        if shutil.which("tachyonc"):
            yield "tachyonc"
        yield os.path.join(cwd, "target", "tachyonc")
    for c in cands():
        if "/" not in c:
            return c
        full = c if os.path.isabs(c) else os.path.normpath(os.path.join(cwd, c))
        if os.access(full, os.X_OK):
            rel = os.path.relpath(full, here)
            return rel if not rel.startswith("..") else full
    return None


def root_args(full, here):
    """The `--root` a query about file `full` needs when run in `here`:
    none when the program's root is here's (compiler/src/main.tach, or
    main.tach), else `--root ROOT`."""
    if "/compiler/src/" in full or "/compiler/std/" in full:
        top = full.split("/compiler/")[0]
        root = os.path.join(top, "compiler", "src", "main.tach")
    else:
        d, root = os.path.dirname(full), None
        for _ in range(6):
            if os.path.exists(os.path.join(d, "main.tach")):
                root = os.path.join(d, "main.tach")
                break
            d = os.path.dirname(d)
        if root is None:
            return None
    if root in (os.path.join(here, "compiler", "src", "main.tach"), os.path.join(here, "main.tach")):
        return []
    rel = os.path.relpath(root, here)
    return ["--root", rel if not rel.startswith("..") else root]


def rewrite_parts(event, command, cwd, reads):
    """(the line to run instead, or None; [(part, its query, the note's
    clause)] of the reads translated; [the reads not translated]). (n8)
    Each reading command of the line is replaced by its query where it
    stands (translate()), every other command, separator and pipe kept as
    typed: `ls; grep -n x a.tach | head` runs `ls; tachyonc query grep x
    --in a.tach | head`. The line is None when a read has no query that
    is not in doubt (the caller blocks it), or when the directory a read
    runs in is not known (a `cd` of a variable, a `cd` in a subshell)."""
    spans = tc.segment_spans(command)
    located = tc.located(command, cwd)
    if spans is None or len(spans) != len(located) or \
            any(command[s:e] != loc[0] for (s, e), loc in zip(spans, located)):
        return None, [], list(reads)
    # (between commands: the separators; `(`, `)` or a backquote with a cd
    # on the line make the directories of the commands uncertain)
    seps = [command[spans[i][1]:spans[i + 1][0]] for i in range(len(spans) - 1)] + [command[spans[-1][1]:]]
    subshell = any(re.search(r"[()`]", x) for x in seps) or command[:spans[0][0]].strip()
    unsure = None  # (the index of the first command whose directory is not known)
    for i, (_, words, _, assigns) in enumerate(located):
        if words and words[0] in ("cd", "pushd", "popd"):
            target = tc.expand(words[1], assigns) if len(words) == 2 else None
            if subshell or words[0] == "popd" or len(words) != 2 or target is None or target == "-":
                unsure = i
                break
    # (the tachyonc the line itself runs, as a path from cwd)
    own = [p if "/" not in p else os.path.relpath(os.path.join(h, p), cwd)
           for _, _, p, _, h in tc.calls_at(command, cwd)
           if p and not p.startswith("$") and os.path.basename(p).startswith("tachyonc")][:1]
    parts, failed, edits, used = [], [], [], set()
    for r in reads:
        i = r.idx
        if i in used:
            continue
        if all(full and not re.search(r"[*?\[]", full) and not os.path.exists(full) for _, full in r[3]):
            continue  # (a file that is not there: the command fails as typed, nothing is read)
        got = None
        if unsure is None or i < unsure:
            got = translate(event, cwd, r, located, seps, command[:spans[i][0]], i, own)
        if not got:
            failed.append(r)
            continue
        text, why, last = got
        used.update(range(i, last + 1))
        start, end = spans[i][0], spans[last][1]
        if (re.search(r"\|\||&&|;", text) and not text.startswith("{")) and len(spans) > 1:
            text = "{ %s; }" % text
        edits.append((start, end, text))
        parts.append((command[start:end], text, why))
    if failed or not edits:
        return None, parts, failed
    new = command
    for start, end, text in sorted(edits, reverse=True):
        new = new[:start] + text + new[end:]
    return new, parts, failed


REDIRECT_OK = re.compile(r"^(\d?>>?(/dev/null|&\d)|&>/dev/null)$")


def plain_words(prog, args):
    """(args without the harmless redirections, those redirections as
    typed) when a reader's words have no other redirection (an input file,
    an output file), else None."""
    keep, redir, i = [], [], 0
    while i < len(args):
        a = args[i]
        if REDIRECT_OK.match(a):
            redir.append(a)
        elif re.match(r"^\d?>>?$", a) and i + 1 < len(args) and args[i + 1] == "/dev/null":
            redir.append(a + "/dev/null")
            i += 1
        elif re.match(r"^(\d|&)?[<>]", a):
            return None
        else:
            keep.append(a)
        i += 1
    return keep, redir


def translate(event, cwd, read, located, seps, pre, i, own=()):
    """(the query for the reading command located[i] (with the command it
    pipes into, for `cat F | head`), the note's clause, the index of the
    last command replaced) when it is not in doubt, else None:
    - `sed -n 'A,Bp'|'Ap'|'A,$p' F`, `head [-n] N F`, `tail [-n] [+]N F`,
      `cat F | head|tail|sed -n ...`: `query text F:A-B`, the same lines;
    - `cat F` (F over SMALL_LINES lines): `query items MODULE`, its outline;
    - grep (grep_query): `query refs NAME` (one name), `query grep TEXT...`,
      `query text` of the lines `-A`/`-B`/`-C` print."""
    prog, _, _, files = read
    if any(f is None for _, f in files) or (len(files) != 1 and prog not in ("grep", "egrep", "fgrep")):
        return None

    def piped(k):  # (whether command k's output goes into command k + 1)
        return k + 1 < len(located) and seps[k].strip() == "|"
    pipe_next = piped(i)
    # (output read by a command or process substitution (`pre`, the line
    # before the command): a program uses it, not the agent)
    if re.search(r"(\$\(|`|[<>]\()\s*$", pre):
        return None
    got = translate_one(event, cwd, prog, files, located, i, pipe_next, piped, own)
    if not got:
        return None
    text, why, last = got
    # (what reads the query's output: the agent, through head, tail, cut, less;
    # not a program counting or filtering lines (wc, sort, grep), whose result
    # the query's layout would change)
    k = last
    while piped(k):
        w = located[k + 1][1]
        if not w or os.path.basename(w[0]) not in DISPLAY:
            return None
        k += 1
    # (a grep's status tells whether it found anything; a query's does not)
    if prog in ("grep", "egrep", "fgrep") and k == last and k < len(seps) and \
            re.match(r"^\s*(&&|\|\|)", seps[k]):
        return None
    return text, why, last


DISPLAY = {"head", "tail", "cut", "less", "more", "cat"}


def translate_one(event, cwd, prog, files, located, i, pipe_next, piped, own):
    """translate() of the command itself (and of `cat F | READER`)."""
    _, words, here, assigns = located[i]
    while words and "=" in words[0] and not words[0].startswith("-"):
        words = words[1:]
    if not words or os.path.basename(words[0]) != prog:
        return None
    t = tachyonc_for(event, cwd, here, own)
    if not t:
        return None
    t = shlex.quote(t)
    # (the words as typed: source_reads' leave the redirections out)
    pw = plain_words(prog, words[1:])
    if pw is None:
        return None
    args, redir = pw
    tail_redir = (" " + " ".join(redir)) if redir else ""
    if prog == "grep" or prog in ("egrep", "fgrep"):
        got = grep_query(t, prog, args, here, assigns, head_limit(located, i) if pipe_next else None)
        return (got[0] + tail_redir, got[1], i) if got else None
    operands = file_args(prog, args)
    if len(operands) != 1:
        return None
    arg = operands[0]
    e = tc.expand(arg, assigns)
    if e is None or re.search(r"[*?\[]", e):
        return None
    full = os.path.normpath(os.path.join(here, e))
    if not os.path.isfile(full):
        return None
    ops = [a for a in args if a != arg]
    rng = text_range(prog, ops, full)
    last = i
    if prog == "cat" and pipe_next and not redir:
        # `cat F | head -N` (or tail, sed -n, grep): the reader after the pipe, on F
        if any(o != "-n" for o in ops):
            return None
        nwords = located[i + 1][1]
        if not nwords:
            return None
        nprog = os.path.basename(nwords[0])
        npw = plain_words(nprog, nwords[1:])
        if npw is None:
            return None
        nargs, nredir = npw
        tail_redir = (" " + " ".join(nredir)) if nredir else ""
        if nprog in ("grep", "egrep", "fgrep"):
            limit = head_limit(located, i + 1) if piped(i + 1) else None
            got = grep_query(t, nprog, nargs + [e], here, assigns, limit)
            return (got[0] + tail_redir, got[1], i + 1) if got else None
        if nprog not in ("head", "tail", "sed") or file_args(nprog, nargs):
            return None
        rng = text_range(nprog, nargs, full)
        if not rng:
            return None
        last = i + 1
    if rng:
        a, b = rng
        if b < a:
            return None
        return ("%s query text %s%s" % (t, shlex.quote("%s:%d-%d" % (e, a, b)), tail_redir),
                "the same lines, each with its number", last)
    if prog == "cat" and not pipe_next:
        if any(o != "-n" for o in ops):
            return None
        mod = module_of(full)
        ra = root_args(full, here)
        if not mod or ra is None:
            return None
        n_lines = lines_of_all(full)
        new = " ".join([t, "query", "items", mod] + [shlex.quote(x) for x in ra]) + tail_redir
        why = ("%s is %s lines; this is its outline: `query show NAME` prints one item, "
               "`query text %s:A-B` lines" % (arg, format(n_lines, ","), arg))
        return new, why, i
    return None


def text_range(prog, ops, full):
    """(A, B), the lines `sed -n 'A,Bp'`, `head`, `tail` print of file full,
    given the words other than the file; None for any other form."""
    if prog == "sed":
        script = [a for a in ops if a != "-n"]
        m = re.match(r"^(\d+)(?:,(\d+|\$))?p$", script[0]) if len(script) == 1 and "-n" in ops else None
        if not m:
            return None
        b = m.group(2) or m.group(1)
        return int(m.group(1)), (lines_of_all(full) if b == "$" else int(b))
    if prog not in ("head", "tail"):
        return None
    n, plus = None, False
    if not ops:
        n = 10
    elif len(ops) == 2 and ops[0] == "-n" and re.match(r"^\+?\d+$", ops[1]):
        n, plus = int(ops[1].lstrip("+")), ops[1].startswith("+")
    elif len(ops) == 1 and re.match(r"^-n?\+?\d+$", ops[0]):
        n, plus = int(re.sub(r"\D", "", ops[0])), "+" in ops[0]
    if not n:
        return None
    if prog == "head":
        return None if plus else (1, n)
    total = lines_of_all(full)
    return (n, total) if plus else (max(1, total - n + 1), total)


GREP_LETTERS = set("nHhsI")
GREP_LONG = {"--line-number": None, "--with-filename": None, "--no-filename": None, "--no-messages": None,
             "--recursive": "r", "--ignore-case": "i", "--word-regexp": "w", "--fixed-strings": "F",
             "--extended-regexp": "E", "--basic-regexp": None}


def grep_options(prog, args):
    """The options of a grep, or None when one changes what it prints in a
    way no query does (-c, -l, -v, -o, -m, -P, ...): {pats, files, i, w, F,
    E, r, A, B}."""
    o = {"pats": [], "files": [], "i": False, "w": False, "F": prog == "fgrep",
         "E": prog == "egrep", "r": False, "A": 0, "B": 0}
    i, done = 0, False

    def count(v):
        return int(v) if v is not None and v.isdigit() else None
    while i < len(args):
        a = args[i]
        if done or not a.startswith("-") or a == "-":
            o["files"].append(a)
            i += 1
            continue
        if a == "--":
            done = True
        elif a.startswith("--"):
            name, _, val = a.partition("=")
            if name in GREP_LONG:
                if GREP_LONG[name]:
                    o[GREP_LONG[name]] = True
            elif name == "--regexp":
                if not val and i + 1 >= len(args):
                    return None
                o["pats"].append(val if val else args[i + 1])
                i += 0 if val else 1
            elif name == "--include" and val.strip("'\"") == "*.tach":
                pass
            elif name in ("--color", "--colour") and val in ("", "never", "auto"):
                pass
            elif name in ("--after-context", "--before-context", "--context") and count(val) is not None:
                n = count(val)
                if name != "--before-context":
                    o["A"] = n
                if name != "--after-context":
                    o["B"] = n
            else:
                return None
        else:
            m = re.match(r"^-([A-Za-z]+)(\d*)$", a)
            if not m:
                return None
            letters, digits = m.group(1), m.group(2)
            for k, ch in enumerate(letters):
                lastl = k == len(letters) - 1
                if ch in "iwFErR":
                    if digits and lastl:
                        return None
                    o["r" if ch == "R" else ch] = True
                elif ch in GREP_LETTERS:
                    if digits and lastl:
                        return None
                elif ch in "ABC" and lastl:
                    n = count(digits) if digits else None
                    if n is None:
                        n = count(args[i + 1]) if i + 1 < len(args) else None
                        if n is None:
                            return None
                        i += 1
                    if ch != "B":
                        o["A"] = n
                    if ch != "A":
                        o["B"] = n
                elif ch == "e" and lastl and not digits and i + 1 < len(args):
                    o["pats"].append(args[i + 1])
                    i += 1
                else:
                    return None
        i += 1
    if not o["pats"]:
        if not o["files"]:
            return None
        o["pats"] = [o["files"].pop(0)]
    return o


# One group of alternatives with a literal prefix and suffix: `\b(a|b)\b`
# (-E), `^pub fn \(a\|b\)(` (BRE).
GROUP_ERE = re.compile(r"((?:\\.|[^\\()|])*)\(((?:\\.|[^\\()])*)\)((?:\\.|[^\\()|])*)")
GROUP_BRE = re.compile(r"((?:\\[^()|]|[^\\])*)\\\(((?:\\[^()]|[^\\])*)\\\)((?:\\[^()|]|[^\\])*)")


def grep_alternatives(p, ere):
    """The alternatives of a grep pattern (`a\\|b`, -E `a|b`), a group of
    them with a prefix and suffix (`\\b(a|b)\\b`) given each its prefix
    and suffix."""
    m = (GROUP_ERE if ere else GROUP_BRE).fullmatch(p)
    if m:
        inner = re.split(r"\\\||\|" if ere else r"\\\|", m.group(2))
        return [m.group(1) + a + m.group(3) for a in inner]
    return re.split(r"\\\||\|" if ere else r"\\\|", p)


def grep_literal(alt, ere):
    """(text, anchored at ^, word-bounded) of one alternative of a grep
    pattern when it is a literal text (escaped punctuation unescaped, `^`
    first, `\\b`/`\\<`, `\\>` at both ends); None for a regex."""
    anchored = alt.startswith("^")
    if anchored:
        alt = alt[1:]
    wl = alt.startswith(("\\b", "\\<"))
    wr = alt.endswith(("\\b", "\\>")) and not alt.endswith("\\\\b")
    if wl:
        alt = alt[2:]
    if wr:
        alt = alt[:-2]
    if wl != wr:
        return None
    out, i = [], 0
    while i < len(alt):
        c = alt[i]
        if c == "\\":
            if i + 1 >= len(alt):
                return None
            d = alt[i + 1]
            if d.isalnum() or d == "_" or (not ere and d in "(){}+?|<>") or d in "<>":
                return None
            out.append(d)
            i += 2
            continue
        if c in ".[]*$^" or (ere and c in "()+?{}|"):
            return None
        out.append(c)
        i += 1
    text = "".join(out)
    if not text.strip() or text.startswith("-") or "\n" in text:
        return None
    return text, anchored, wl


def case_variants(text):
    """The spellings `grep -i TEXT` finds in code: as typed, lower,
    Capitalized, UPPER."""
    out = []
    for v in (text, text.lower(), text[:1].upper() + text[1:].lower(), text.upper()):
        if v not in out:
            out.append(v)
    return out


QUERY_NAME = re.compile(r"[A-Za-z_]\w*(?:::\w+)*")


def head_limit(located, i):
    """N when the command after located[i] (piped into) is `head -N`
    (`head -n N`, `head`: 10): a grep piped into it prints N lines, so its query
    gets `--limit N` (a query prints a count per file, not its hits, past
    60 of them)."""
    if i + 1 >= len(located):
        return None
    w = located[i + 1][1]
    if not w or w[0] != "head":
        return None
    rng = text_range("head", w[1:], "")
    return rng[1] if rng else None


def grep_query(t, prog, args, here, assigns, limit=None):
    """(the query for a grep, the note's clause) or None:
    - one name (no -i, no context): `query refs NAME --in F || query grep
      NAME --in F` (refs fails where NAME is no item);
    - literal texts, alternatives (`a\\|b`, -E `a|b`, -e, -F): `query grep
      TEXT...` (`--word` for -w or `\\bX\\b`); -i: each text as typed,
      lower, Capitalized and UPPER; `^KW...`: the code lines holding it
      (`--code`, any indentation; texts that are words get `--word`);
    - -A/-B/-C N on one file: `query text` of the lines grep prints (found
      here; at most three runs);
    in F (`--in F`); a directory with -r, `DIR/*.tach` (DIR and its
    subdirectories); compiler/std or a file of it: `--in std` (std is one
    module). Anything else (a regex, -c, -l, -v, several files) is None."""
    o = grep_options(prog, args)
    if o is None or not o["files"] or (len(o["files"]) != 1 and not (o["A"] or o["B"])):
        return None
    lits = []
    for p in o["pats"]:
        alts = p.split("\n") if o["F"] else grep_alternatives(p, o["E"])
        for a in alts:
            if o["F"]:
                if not a or a.startswith("-"):
                    return None
                lits.append((a, False, False))
                continue
            lit = grep_literal(a, o["E"])
            if lit is None:
                return None
            lits.append(lit)
    if not lits:
        return None
    bounded = [w for _, _, w in lits]
    if any(bounded) and not all(bounded):
        return None
    word = o["w"] or all(bounded)
    code = any(a for _, a, _ in lits)
    texts = [x for x, _, _ in lits]
    notes = []
    if code:
        if not all(re.match(r"^[A-Za-z_]", x) for x in texts):
            return None
        texts = [x.rstrip() for x in texts]
        if all(re.fullmatch(r"\w+(?: \w+)*", x) for x in texts):
            word = True
        notes.append("`^`: the code lines holding it, any indentation (`--code`)")
    if o["A"] or o["B"]:
        paths = context_files(o, here, assigns)
        return context_query(t, paths, lits, o) if paths else None
    # the file: as typed (expanded), a directory, DIR/*.tach, std
    arg = o["files"][0]
    e = tc.expand(arg, assigns)
    if e is None:
        return None
    if re.search(r"[*?\[]", e):
        m = re.match(r"^((?:[^*?\[]*/)?)\*\.tach$", e)
        if not m:
            return None
        e = m.group(1).rstrip("/") or "."
        full = os.path.normpath(os.path.join(here, e))
        if not os.path.isdir(full):
            return None
        if not re.search(r"/compiler/std$", full):
            notes.append("`%s/*.tach`: %s and its subdirectories" % (e, e))
    else:
        full = os.path.normpath(os.path.join(here, e))
        if os.path.isdir(full):
            if not o["r"]:
                return None
            e = e.rstrip("/") or "."
        elif not os.path.isfile(full):
            return None
    is_dir = os.path.isdir(full)
    std = re.search(r"/compiler/std(/|$)", full)
    if std:
        notes.append("std's files are one module, `--in std`")
        e = "std"
    ra = root_args(os.path.join(full, "_.tach") if is_dir else full, here)
    if ra is None or e == ".":
        return None
    # (the root's own directory, compiler/src: the whole program, no --in)
    whole = is_dir and not std and (bool(re.search(r"/compiler/src$", full))
                                    or os.path.exists(os.path.join(full, "main.tach")))
    tail = " ".join(shlex.quote(x) for x in ([] if whole else ["--in", e]) + ra)
    if o["i"]:
        texts = [v for x in texts for v in case_variants(x)]
        notes.append("-i: each text as typed, lower, Capitalized, UPPER")
    seen = []
    for x in texts:
        if x not in seen:
            seen.append(x)
    texts = seen
    if len(texts) > 24:
        return None
    if limit and limit > 60:
        # (a query prints a count per file past 60 hits; the head after it asked for N lines)
        tail = (tail + " " if tail else "") + "--limit %d" % limit
    if len(texts) == 1 and not o["i"] and not code and QUERY_NAME.fullmatch(texts[0]):
        name = texts[0]
        sp = " " if tail else ""
        new = "%s query refs %s%s%s 2>/dev/null || %s query grep %s%s%s" % (t, name, sp, tail, t, name, sp, tail)
        why = ("`query refs %s` lists its uses, each with its item; where %s is no item, "
               "`query grep %s` the lines holding it" % (name, name, name))
        return new, why
    flags = (["--word"] if word else []) + (["--code"] if code else [])
    new = " ".join([t, "query", "grep"] + flags + [shlex.quote(x) for x in texts] + ([tail] if tail else []))
    why = "each line holding %s, with its item" % ("one of the texts" if len(texts) > 1 else "the text")
    if notes:
        why += " (" + "; ".join(notes) + ")"
    return new, why


def context_files(o, here, assigns):
    """[(path as typed, full path)] of the files a grep -A/-B/-C reads: its
    operands, globs expanded, directories (with -r) walked for .tach files;
    None when one is not known or not there."""
    import glob
    out = []
    for arg in o["files"]:
        e = tc.expand(arg, assigns)
        if e is None:
            return None
        full = os.path.normpath(os.path.join(here, e))
        if re.search(r"[*?\[]", e):
            got = sorted(glob.glob(full))
            if not got:
                return None
            out += [(os.path.join(os.path.dirname(e), os.path.basename(g)), g) for g in got]
        elif os.path.isdir(full):
            if not o["r"]:
                return None
            for d, dirs, fs in os.walk(full):
                dirs.sort()
                out += [(os.path.join(e.rstrip("/"), os.path.relpath(os.path.join(d, f), full)),
                         os.path.join(d, f)) for f in sorted(fs) if f.endswith(".tach")]
        elif os.path.isfile(full):
            out.append((e, full))
        else:
            return None
        if len(out) > 3000:
            return None
    return out


def context_query(t, paths, lits, o):
    """`query text` of the lines `grep -A/-B/-C` prints of the files, found
    here (at most three runs of lines in all); None when nothing matches."""
    pats = []
    for text, anchored, bounded in lits:
        p = re.escape(text)
        if bounded or o["w"]:
            p = r"(?<!\w)" + p + r"(?!\w)"
        pats.append(("^" if anchored else "") + p)
    rx = re.compile("|".join(pats), re.I if o["i"] else 0)
    found = []
    for e, full in paths:
        try:
            with open(full, errors="replace") as fh:
                lines = fh.read().split("\n")
        except OSError:
            return None
        if lines and lines[-1] == "":
            lines.pop()
        runs = []
        for n, line in enumerate(lines, 1):
            if rx.search(line):
                a, b = max(1, n - o["B"]), min(len(lines), n + o["A"])
                if runs and a <= runs[-1][1] + 1:
                    runs[-1][1] = max(runs[-1][1], b)
                else:
                    runs.append([a, b])
        found += [(e, a, b) for a, b in runs]
        if len(found) > 3:
            return None
    if not found:
        return None
    cmds = ["%s query text %s" % (t, shlex.quote("%s:%d-%d" % (e, a, b))) for e, a, b in found]
    new = cmds[0] if len(cmds) == 1 else "{ %s; }" % "; ".join(cmds)
    return new, "the lines grep printed with its context, each with its number"


def lines_of_all(path):
    try:
        with open(path, "rb") as fh:
            return sum(1 for _ in fh)
    except OSError:
        return 0


LINE_FOR_EDIT = re.compile(r"line\s*(number|no\.?|numbers)?\b.*\b(edit|Edit)|\bfor\s+(the\s+)?Edit\b", re.I)


def post_context(event, command, calls, out_text=""):
    """(0.17) What the agent is told after a Bash call, or "": the reply to
    a `# no-query:` reason that wants line numbers for the Edit tool; the
    repeat-query hint (hints.txt) after three show, refs or def calls in a
    row on related items (repeat_query_hint)."""
    out = []
    esc = ESCAPE.search(command)
    if esc and LINE_FOR_EDIT.search(esc.group(1)):
        out.append("note hook.query-first: no line numbers are needed to change an item: "
                   "`tachyonc edit insert --after NAME < text` adds an item after NAME, "
                   "`tachyonc edit patch NAME --old 'TEXT' --new 'TEXT'` changes lines in it, "
                   "and `tachyonc query def NAME` prints its FILE:LINE")
    note = repeat_query_hint(event, calls, out_text)
    if note:
        out.append(note)
    return "\n".join(out)


QUERY_LOOKUPS = ("show", "refs", "def", "callers")
TRIVIAL_HEADS = {"crate", "std", "self", "super", "Self"}
WORD = re.compile(r"[A-Za-z_]\w{2,}")


def name_parts(name):
    return [p for p in re.split(r"::|\.", name) if p]


def related(a, b):
    """Whether query record b is about an item related to record a's: the
    same name, a name and its type or module (`Foo` and `Foo::bar`), the
    same last part (`ir::emit` and `emit`), or a name a's answer printed."""
    for x in a["args"]:
        px = name_parts(x)
        for y in b["args"]:
            py = name_parts(y)
            if not px or not py:
                continue
            if x == y or px[-1] == py[-1]:
                return True
            short, long_ = (px, py) if len(px) <= len(py) else (py, px)
            if long_[:len(short)] == short and not (len(short) == 1 and short[0] in TRIVIAL_HEADS):
                return True
            if py[-1] in a.get("out", ()):
                return True
    return False


def repeat_query_hint(event, calls, out_text):
    """(0.17, E3) The repeat-query hint, at the moment it applies: after the
    third `query show|refs|def|callers` in a row on related items (related()),
    once a session; never once the session has run `query context`."""
    recs = []
    used_context = False
    for sub, words, path, _ in calls:
        if sub != "query":
            continue
        rest = [w for w in words if not w.startswith("-")]
        if len(rest) >= 2 and rest[1] == "context":
            used_context = True
        if len(rest) >= 3 and rest[1] in QUERY_LOOKUPS:
            names = [n for n in rest[2:] if not n.endswith(".tach") and not re.match(r"^[\d:-]+$", n)
                     and not re.search(r"\.tach:", n)]
            if names:
                recs.append({"args": names[:4], "prog": path or "tachyonc"})
    if not recs and not used_context:
        return ""
    st = hs.load(event, "query")
    if used_context:
        st["used_context"] = True
    if recs:
        # (the names the answer printed: a callee, a caller, a field's type)
        recs[-1]["out"] = sorted(set(WORD.findall(out_text or "")))[:400]
        window = ((st.get("queries") or []) + recs)[-3:]
        st["queries"] = window
    else:
        window = []
    note = ""
    hinted = st.setdefault("hinted", [])
    if len(window) == 3 and "repeat-query" not in hinted and not st.get("used_context") \
            and related(window[0], window[1]) and (related(window[1], window[2]) or related(window[0], window[2])):
        # (the name asked about most; on a tie the first: where it began)
        firsts = [r["args"][0] for r in window]
        name = max(firsts, key=firsts.count)
        note = hs.hint("repeat-query", NAME=name, TACHYONC=window[-1].get("prog") or "tachyonc")
        if note:
            hinted.append("repeat-query")
    hs.save(event, st, "query")
    return note


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
            ran = next((c[2] for c in calls if c[2] and not c[2].startswith("$")), None)
            if ran and not err.startswith("error") and query_mode() == "rewrite":
                st = hs.load(event, "query")
                if st.get("tachyonc") != ran:
                    st["tachyonc"] = ran
                    hs.save(event, st, "query")
            context = post_context(event, command, calls, out)
            if context:
                log(gd, {"kind": "hint", "text": context[:300], "command": command[:300]})
                json.dump({"hookSpecificOutput": {"hookEventName": "PostToolUse",
                                                  "additionalContext": context}}, sys.stdout)
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
        fixtures, small, scratch = [], [], []
        reads = source_reads(command, cwd, fixtures, small, scratch)
        if not reads:
            for kind, got in (("read-small", small), ("read-scratch", scratch), ("read-fixture", fixtures)):
                if got:
                    log(gd, {"kind": kind, "program": got[0][0], "command": command[:300]})
                    break
            return 0
        esc = ESCAPE.search(command)
        if esc:
            log(gd, {"kind": "escape",
                     "reason": esc.group(1).strip()[:300], "command": command[:300]})
            return 0
        if not query_ready(gd, cwd):
            log(gd, {"kind": "read-unenforced", "command": command[:300]})
            return 0
        new, parts, failed = (rewrite_parts(event, command, cwd, reads) if query_mode() == "rewrite"
                              else (None, [], list(reads)))
        if new:
            # (the first rewrite of a session says what the mode does)
            st = hs.load(event, "query")
            first = not st.get("rewrote")
            if first:
                st["rewrote"] = True
                hs.save(event, st, "query")
            notes = []
            for k, (part, to, why) in enumerate(parts):
                shown = part if len(part) <= 120 else part[:117] + "..."
                key = ("rewritten-first" if first else "rewritten") if k == 0 else "rewritten-also"
                notes.append(hs.text(key, FROM=shown, TO=to, WHY=why))
            log(gd, {"kind": "rewritten", "program": reads[0][0], "command": command[:300],
                     "to": new[:300], "parts": len(parts)})
            json.dump({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "allow",
                "permissionDecisionReason": "hook.query-first: a read of .tach source run as its query",
                "updatedInput": dict(inp, command=new), "additionalContext": "\n".join(notes)}}, sys.stdout)
            return 0
        if not failed:
            # (rewrite mode: every read is of a file that is not there; it fails as typed)
            log(gd, {"kind": "read-missing", "program": reads[0][0], "command": command[:300]})
            return 0
        prog, args, seg, files = failed[0]
        message, tries = blocked_message(command, prog, args, seg, files, cwd, failed[1:], parts)
        log(gd, {"kind": "blocked", "program": prog, "command": command[:300],
                 "segment": seg[:200], "try": tries, "reads": len(reads),
                 "translated": [to[:200] for _, to, _ in parts]})
        sys.stderr.write(message)
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
