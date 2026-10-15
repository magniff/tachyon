"""State shared by the agent hooks across calls (0.17): per session, what
the check hook last reported for each program root (its errors, its tests,
the fingerprint of the sources then), which hints were given, the last
queries; the fingerprint of a program's sources; the hint texts
(hints.txt); when the session started.

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


def load(event):
    d = state_dir()
    if not d:
        return {}
    try:
        with open(os.path.join(d, session_key(event) + ".json")) as fh:
            st = json.load(fh)
            return st if isinstance(st, dict) else {}
    except (OSError, ValueError):
        return {}


def save(event, st):
    d = state_dir()
    if not d:
        return
    path = os.path.join(d, session_key(event) + ".json")
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
DEFAULT_HINTS = {
    "repeat-query": "hint: one call gives what show, refs and def gave about {NAME}: its source, "
                    "what it calls and its callers: `{TACHYONC} query context {NAME}`",
    "unfamiliar-construct": "hint: before writing a construct you are unsure of, `{TACHYONC} guide "
                            "--find WORDS` (the error's words) or `{TACHYONC} guide TOPIC#SECTION` "
                            "prints the lines on it",
}


def hint(key, **values):
    """The hint KEY of hints.txt (`KEY: TEXT` lines; written by the guide's
    work, kept as it is), its {NAME}s filled in; the built-in text when the
    file lacks it."""
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
    text = _HINTS.get(key, "")
    for k, v in values.items():
        text = text.replace("{%s}" % k, v)
    return text


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
