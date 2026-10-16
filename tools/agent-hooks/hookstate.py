"""State shared by the agent hooks across calls (0.17): per session, what
the check hook last reported for each program root (its errors, its tests,
the fingerprint of the sources then), which hints were given, the last
queries; the fingerprint of a program's sources; the hint texts
(hints.txt; TACHYON_HINTS=0 turns the hints off); when the session
started. A hook that runs beside another on the same event keeps its
state in a part of its own (`load(event, part)`).

The state is one JSON file per session in $TACHYON_HOOK_STATE, else
$TMPDIR/tachyon-agent-hooks/ (written whole, renamed over: a hook that
loses a race loses an update, never the file). Development tooling only:
Python stdlib, loaded by path by check-after-edit.py, query-first.py and
turn-end.py.
"""
import calendar
import json
import os
import re
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SKIP_DIRS = {".git", "target", "node_modules", ".tachyonc", "__pycache__"}
TEST_EXTS = (".in", ".out", ".exit")


def state_dir():
    d = os.environ.get("TACHYON_HOOK_STATE") or os.path.join(
        os.environ.get("TMPDIR") or "/tmp", "tachyon-agent-hooks")
    try:
        os.makedirs(d, exist_ok=True)
    except OSError:
        return None
    return d


def session_key(event):
    s = (event.get("session_id") or "nosession")
    if event.get("agent_id"):
        s += "-" + str(event.get("agent_id"))
    return re.sub(r"[^\w.-]", "_", s)[:120]


def state_path(d, event, part=None):
    """The state file of a session, or of one hook's part of it (`part`:
    hooks that run on the same event in parallel keep their state apart,
    so that one's save does not undo the other's)."""
    return os.path.join(d, session_key(event) + ("-" + part if part else "") + ".json")


def load(event, part=None):
    d = state_dir()
    if not d:
        return {}
    try:
        with open(state_path(d, event, part)) as fh:
            st = json.load(fh)
            return st if isinstance(st, dict) else {}
    except (OSError, ValueError):
        return {}


def save(event, st, part=None):
    d = state_dir()
    if not d:
        return
    path = state_path(d, event, part)
    tmp = "%s.%d~" % (path, os.getpid())
    try:
        with open(tmp, "w") as fh:
            json.dump(st, fh)
        os.replace(tmp, path)
    except OSError:
        pass


def source_dirs(root):
    """The directories whose .tach files make up root's program: the
    compiler's compiler/src and compiler/std, else the root's directory."""
    root = os.path.abspath(root)
    d = os.path.dirname(root)
    if root.endswith(os.path.join("compiler", "src", "main.tach")):
        return [d, os.path.join(os.path.dirname(d), "std")]
    if root.endswith(os.path.join("compiler", "std", "std.tach")):
        return [d]
    return [d]


def fingerprint(root, limit=5000):
    """A hash of the program's .tach files (path, size, mtime) under its
    source directories, and of its tests (tests/*.in, .out, .exit), and the
    newest mtime among them: (hash, newest)."""
    parts, newest, n = [], 0.0, 0
    for top in source_dirs(root):
        for d, dirs, files in os.walk(top):
            dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS and not x.startswith("."))
            in_tests = os.path.basename(d) == "tests"
            for f in sorted(files):
                if not (f.endswith(".tach") or (in_tests and f.endswith(TEST_EXTS))):
                    continue
                p = os.path.join(d, f)
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                parts.append("%s\t%d\t%d" % (p, st.st_size, st.st_mtime_ns))
                newest = max(newest, st.st_mtime)
                n += 1
                if n >= limit:
                    return digest(parts), newest
            if d.count(os.sep) - top.count(os.sep) >= 6:
                dirs[:] = []
    return digest(parts), newest


def digest(parts):
    import zlib
    text = "\n".join(parts).encode("utf-8", "replace")
    return "%d-%08x-%08x" % (len(parts), zlib.crc32(text), zlib.adler32(text))


def has_tests(root):
    """Whether the program has cases for `tachyonc test`: tests/*.out next
    to its root (not the compiler: its suite is not fast)."""
    root = os.path.abspath(root)
    if "/compiler/src/" in root or "/compiler/std/" in root:
        return False
    d = os.path.join(os.path.dirname(root), "tests")
    try:
        return any(f.endswith(".out") for f in os.listdir(d))
    except OSError:
        return False


_HINTS = None
# (0.17, E3/E7) Every text a hook adds to the agent's context is a factual
# statement with the command in it, never an instruction framed as a
# system message; short, the same words every time (nothing that varies
# from run to run: no times, no ids), so that it costs its tokens once.
DEFAULT_HINTS = {
    "repeat-query": "note: `{TACHYONC} query context {NAME}` prints in one call what show, refs and "
                    "def print about {NAME}: its source, the items it uses, its callers",
    "unfamiliar-construct": "note: `{TACHYONC} guide --find WORDS` prints the guide's lines on WORDS "
                            "(an error's own words work); `{TACHYONC} guide TOPIC#SECTION` prints "
                            "one section",
    "rewritten": "note hook.query-first: `{FROM}` ran as `{TO}`: {WHY}",
    "rewritten-first": "note hook.query-first: shell reads of large .tach files are answered with "
                       "the matching query (sed -n, head, tail: `query text`; cat: `query items`; "
                       "grep: `query refs` or `query grep`), each command of a line on its own, "
                       "the others as typed; `{FROM}` ran as `{TO}`: {WHY}",
    "rewritten-also": "note hook.query-first: also `{FROM}` ran as `{TO}`: {WHY}",
    "repeat-lookup": "note: `{WHAT}` printed the same text at shell call {N} of this session",
}
# The hints proper (E3): TACHYON_HINTS=0 turns these off; the other texts
# (a rewrite's note, a repeat lookup's) have switches of their own.
HINT_KEYS = ("repeat-query", "unfamiliar-construct")


def hints_on():
    return os.environ.get("TACHYON_HINTS", "1") != "0"


def text(key, **values):
    """The text KEY of hints.txt (`KEY: TEXT` lines), its {NAME}s filled
    in; the built-in text when the file lacks it."""
    global _HINTS
    if _HINTS is None:
        _HINTS = dict(DEFAULT_HINTS)
        try:
            with open(os.path.join(HERE, "hints.txt")) as fh:
                for line in fh:
                    m = re.match(r"^([\w.-]+):\s*(.*\S)\s*$", line)
                    if m and not line.startswith("#"):
                        _HINTS[m.group(1)] = m.group(2)
        except OSError:
            pass
    out = _HINTS.get(key, "")
    for k, v in values.items():
        out = out.replace("{%s}" % k, str(v))
    return out


def hint(key, **values):
    """The hint KEY (text()), or "" when hints are off (TACHYON_HINTS=0)."""
    if key in HINT_KEYS and not hints_on():
        return ""
    return text(key, **values)


def session_start(event):
    """When the session began (seconds since the epoch): the first
    timestamp in its transcript; None when it cannot be told."""
    path = event.get("transcript_path")
    if not path:
        return None
    try:
        with open(path) as fh:
            for _ in range(30):
                line = fh.readline()
                if not line:
                    break
                m = re.search(r'"timestamp"\s*:\s*"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.\d+)?(Z|[+-]\d\d:?\d\d)?"', line)
                if m:
                    t = time.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")
                    return calendar.timegm(t) if m.group(2) in (None, "Z") else time.mktime(t)
    except OSError:
        return None
    try:
        st = os.stat(path)
        return getattr(st, "st_birthtime", None)
    except OSError:
        return None
