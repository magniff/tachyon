"""Shared helpers: paths, meta.toml, processes, test comparison."""

import json
import os
import re
import shutil
import signal
import subprocess
import time

EVAL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_ROOT = os.path.dirname(os.path.dirname(EVAL_DIR))
DEFAULT_TASKS_DIR = os.path.join(EVAL_DIR, "tasks")
DEFAULT_RESULTS_DIR = os.path.join(EVAL_DIR, "results")
PROMPTS_DIR = os.path.join(EVAL_DIR, "prompts")

TACH_CONDS = ("bare", "guide", "tools", "both")
ALL_CONDS = TACH_CONDS + ("rust",)
KINDS = ("write", "fix", "extend", "refactor", "perf")

TACH_BUILD = ["tachyonc", "main.tach", "-o", "prog"]
RUST_BUILD = ["rustc", "-O", "--edition", "2021", "main.rs", "-o", "prog"]
BUILD_TIMEOUT_S = 300

# The environment every agent and every build sees: nothing from the
# caller's shell but the basics, PATH = the run's bin dir + the system.
SYSTEM_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"


def private_paths():
    """What no agent may read: this repository (the main checkout too, when
    this is a worktree: its docs and compiler source would be a guide
    the conditions do not give) and ~/.claude (this machine's sessions and
    memory)."""
    paths = [os.path.realpath(REPO_ROOT)]
    g = os.path.join(REPO_ROOT, ".git")
    if os.path.isfile(g):
        with open(g) as fh:
            gd = fh.read().strip().split("gitdir:", 1)[-1].strip()
        gd = os.path.join(REPO_ROOT, gd)
        common = gd
        cf = os.path.join(gd, "commondir")
        if os.path.isfile(cf):
            with open(cf) as fh:
                common = os.path.join(gd, fh.read().strip())
        main = os.path.dirname(os.path.realpath(common))
        if main not in paths:
            paths.append(main)
    paths.append(os.path.realpath(os.path.expanduser("~/.claude")))
    return paths


def lang_of(cond):
    return "rust" if cond == "rust" else "tach"


def base_env(bin_dir):
    env = {
        "HOME": os.environ.get("HOME", ""),
        "USER": os.environ.get("USER", ""),
        "LOGNAME": os.environ.get("LOGNAME", os.environ.get("USER", "")),
        "PATH": bin_dir + ":" + SYSTEM_PATH,
        "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
        "LANG": "en_US.UTF-8",
        "TERM": "dumb",
        "SHELL": "/bin/zsh",
    }
    return env


# ---------------------------------------------------------------- meta.toml

_KV = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$')


def _strip_comment(v):
    out, q = [], None
    for ch in v:
        if q:
            out.append(ch)
            if ch == q:
                q = None
        elif ch in "\"'":
            q = ch
            out.append(ch)
        elif ch == "#":
            break
        else:
            out.append(ch)
    return "".join(out).strip()


def parse_toml(text):
    """The subset meta.toml uses: top-level `key = value` lines with
    strings, integers, floats and booleans (Python 3.9 has no tomllib)."""
    out = {}
    for n, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        m = _KV.match(s)
        if not m:
            raise ValueError("line %d: not 'key = value': %s" % (n, s))
        k, v = m.group(1), _strip_comment(m.group(2))
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            out[k] = json.loads(v) if v[0] == '"' else v[1:-1]
        elif v in ("true", "false"):
            out[k] = v == "true"
        else:
            try:
                out[k] = int(v.replace("_", ""))
            except ValueError:
                out[k] = float(v)
    return out


# ---------------------------------------------------------------- tasks

class Task:
    def __init__(self, path):
        self.path = path
        self.id = os.path.basename(path)
        with open(os.path.join(path, "meta.toml")) as fh:
            self.meta = parse_toml(fh.read())
        self.kind = self.meta.get("kind", "write")
        self.title = self.meta.get("title", self.id)
        self.timeout_s = int(self.meta.get("timeout_s", 900))
        self.test_timeout_s = float(self.meta.get("test_timeout_s", 10))
        self.check = self.meta.get("check")

    def text(self):
        with open(os.path.join(self.path, "task.md")) as fh:
            return fh.read()

    def tests(self):
        d = os.path.join(self.path, "tests")
        names = sorted(f[:-3] for f in os.listdir(d) if f.endswith(".in"))
        return [(n, os.path.join(d, n + ".in"), os.path.join(d, n + ".out"))
                for n in names]

    def check_path(self):
        return os.path.join(self.path, self.check) if self.check else None


def load_tasks(tasks_dir, names=None):
    if not os.path.isdir(tasks_dir):
        raise SystemExit("no tasks directory: %s" % tasks_dir)
    ids = sorted(d for d in os.listdir(tasks_dir)
                 if os.path.isfile(os.path.join(tasks_dir, d, "meta.toml")))
    if names:
        missing = [n for n in names if n not in ids]
        if missing:
            raise SystemExit("unknown task(s): %s (have: %s)"
                             % (", ".join(missing), ", ".join(ids)))
        ids = [i for i in ids if i in names]
    return [Task(os.path.join(tasks_dir, i)) for i in ids]


# ---------------------------------------------------------------- processes

def run_proc(argv, cwd, env, timeout, stdin_path=None, stdin_bytes=None):
    """Runs argv in its own process group; kills the group on timeout.
    Returns (returncode or None on timeout, stdout bytes, stderr bytes,
    seconds)."""
    t0 = time.time()
    fin = open(stdin_path, "rb") if stdin_path else None
    try:
        p = subprocess.Popen(
            argv, cwd=cwd, env=env,
            stdin=fin if fin else (subprocess.PIPE if stdin_bytes is not None
                                   else subprocess.DEVNULL),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            start_new_session=True)
        try:
            out, err = p.communicate(input=stdin_bytes, timeout=timeout)
            rc = p.returncode
        except subprocess.TimeoutExpired:
            kill_group(p)
            out, err = p.communicate()
            rc = None
    finally:
        if fin:
            fin.close()
    return rc, out, err, time.time() - t0


def kill_group(p):
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


def kill_leftovers(ws):
    """Kills processes still running in the workspace after the agent
    ended (a command its harness moved to the background, a program
    waiting on stdin): they would change files while the run is graded.
    Returns how many were killed."""
    root = os.path.realpath(ws)
    killed = 0
    for _ in range(3):
        try:
            out = subprocess.run(["lsof", "-a", "-d", "cwd", "-F", "pn"],
                                 capture_output=True, text=True, timeout=60).stdout
        except (OSError, subprocess.SubprocessError):
            return killed
        pids, pid = [], None
        for line in out.splitlines():
            if line.startswith("p"):
                pid = int(line[1:])
            elif line.startswith("n") and pid and pid != os.getpid():
                path = os.path.realpath(line[1:])
                if path == root or path.startswith(root + os.sep):
                    pids.append(pid)
        if not pids:
            break
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
                killed += 1
            except (ProcessLookupError, PermissionError):
                pass
        time.sleep(0.5)
    return killed


def normalise(b):
    return b.replace(b"\r\n", b"\n").rstrip()


def copy_tree(src, dst, skip=(".gitkeep",)):
    """Copies src's contents into dst (created), leaving out `skip` names."""
    os.makedirs(dst, exist_ok=True)
    if not os.path.isdir(src):
        return
    for name in os.listdir(src):
        if name in skip:
            continue
        s, d = os.path.join(src, name), os.path.join(dst, name)
        try:
            if os.path.isdir(s) and not os.path.islink(s):
                shutil.copytree(s, d, symlinks=True)
            else:
                shutil.copy2(s, d, follow_symlinks=False)
        except FileNotFoundError:  # a temporary file that went away
            pass


def write_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(obj, fh, indent=1, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, path)


def tail(b, n=2000):
    s = b.decode("utf-8", "replace") if isinstance(b, bytes) else b
    return s if len(s) <= n else "..." + s[-n:]
