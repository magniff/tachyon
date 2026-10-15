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
HOOKS_DIR = os.path.join(REPO_ROOT, "tools", "agent-hooks")

TACH_CONDS = ("bare", "guide", "tools", "both")
PROGRAM_CONDS = TACH_CONDS + ("rust",)
# (0.16) the compiler tasks' conditions: AGENTS.md with the tools table and
# the hooks, or without them (lib/ctasks.py)
COMPILER_CONDS = ("compiler-tools", "compiler-plain")
# (0.17) every base condition, in report order; a condition is
# BASE[+hook][+test] (lib/conds.py)
ALL_CONDS = ("bare", "guide", "tools", "both", "guide-core", "tools-core", "both-core",
             "rust-pairs", "rust", "compiler-tools", "compiler-plain", "compiler-tools-core")
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


def cond_key(cond):
    """Report order of a condition name (base, then modifiers)."""
    base, _, mods = cond.partition("+")
    return (ALL_CONDS.index(base) if base in ALL_CONDS else 99, mods)


# macOS mktemp without a template ignores $TMPDIR (and so does -t): it
# makes the file in the per-user temp directory (/var/folders/...), which the
# agent's sandbox does not let it write. The repository's scripts call it so
# (compiler/std/embed.sh, compiler/guide/embed.sh, and tests/run.sh through
# `embed.sh -c`), so every agent's bin directory has this shim: no template,
# one in $TMPDIR (the sandbox's own temp directory inside Claude Code).
MKTEMP_SHIM = r"""#!/bin/sh
# (agent eval) mktemp in $TMPDIR: a template there when none is given, and
# (0.17) for -t PREFIX, which macOS puts in the per-user temp directory
# whatever $TMPDIR says (the sandbox forbids it); a template given as an
# argument is used as it is.
flags=""; prefix=""
while [ $# -gt 0 ]; do
    case "$1" in
        --) shift; break ;;
        -t) shift; prefix=$1 ;;
        -*t) flags="$flags ${1%t}"; shift; prefix=$1 ;;
        -t*) prefix=${1#-t} ;;
        -*) flags="$flags $1" ;;
        *) break ;;
    esac
    shift
done
if [ $# -gt 0 ]; then
    exec /usr/bin/mktemp $flags "$@"
fi
exec /usr/bin/mktemp $flags "${TMPDIR:-/tmp}/${prefix:-tmp}.XXXXXXXXXX"
"""


def install_mktemp_shim(bin_dir):
    p = os.path.join(bin_dir, "mktemp")
    with open(p, "w") as fh:
        fh.write(MKTEMP_SHIM)
    os.chmod(p, 0o755)
    return p


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
    is_compiler = False

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


# The task sets `--set` names (0.16): every directory holds NN-name/ tasks.
TASK_SETS = {
    "programs": ("tasks",),
    "compiler": ("ctasks",),
    "all": ("tasks", "ctasks"),
    "dev": ("devtasks",),
}


def task_dirs(tasks_dir=None, task_set=None):
    """The task directories: --tasks-dir (comma-separated) or --set."""
    if task_set:
        if task_set not in TASK_SETS:
            raise SystemExit("--set is one of %s, got %r" % (", ".join(TASK_SETS), task_set))
        return [os.path.join(EVAL_DIR, d) for d in TASK_SETS[task_set]]
    return [d for d in (tasks_dir or DEFAULT_TASKS_DIR).split(",") if d]


def load_tasks(tasks_dir, names=None, task_set=None):
    """The tasks of the directories (a program task, or a compiler task
    when it has solution.patch: lib/ctasks.py), by id; `names` picks."""
    from lib.ctasks import CTask, is_ctask_dir
    found = {}
    for td in task_dirs(tasks_dir, task_set):
        if not os.path.isdir(td):
            raise SystemExit("no tasks directory: %s" % td)
        for d in sorted(os.listdir(td)):
            path = os.path.join(td, d)
            if not os.path.isfile(os.path.join(path, "meta.toml")):
                continue
            if d in found:
                raise SystemExit("task %s is in two directories" % d)
            found[d] = path
    ids = sorted(found)
    if names:
        missing = [n for n in names if n not in ids]
        if missing:
            raise SystemExit("unknown task(s): %s (have: %s)"
                             % (", ".join(missing), ", ".join(ids)))
        ids = [i for i in ids if i in names]
    return [CTask(found[i]) if is_ctask_dir(found[i]) else Task(found[i]) for i in ids]


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
    """Copies src's contents into dst (created; merged into what is there),
    leaving out `skip` names."""
    os.makedirs(dst, exist_ok=True)
    if not os.path.isdir(src):
        return
    for name in os.listdir(src):
        if name in skip:
            continue
        s, d = os.path.join(src, name), os.path.join(dst, name)
        try:
            if os.path.isdir(s) and not os.path.islink(s):
                shutil.copytree(s, d, symlinks=True, dirs_exist_ok=True)
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


def install_hooks(ws_root):
    """The agent hooks (tools/agent-hooks/: check-after-edit.py,
    query-first.py, turn-end.py, the modules and files they load:
    tachyonc_cmd.py, hookstate.py, hints.txt, settings-eval.json; every file
    but the tests) and (0.17) lib/hook-tee.py
    copied out of the repository, which the agent's sandbox cannot read:
    {"check": path, "query": path, "tee": path, "dir": the copies}."""
    d = os.path.join(ws_root, "hooks")
    os.makedirs(d, exist_ok=True)
    for f in sorted(os.listdir(HOOKS_DIR)):
        # the scripts and what they read (hints.txt, settings), not their tests
        if os.path.isfile(os.path.join(HOOKS_DIR, f)) and not f.startswith("test-"):
            shutil.copyfile(os.path.join(HOOKS_DIR, f), os.path.join(d, f))
    shutil.copyfile(os.path.join(EVAL_DIR, "lib", "hook-tee.py"), os.path.join(d, "hook-tee.py"))
    return {"check": os.path.join(d, "check-after-edit.py"),
            "query": os.path.join(d, "query-first.py"),
            "turn_end": os.path.join(d, "turn-end.py"),
            "tee": os.path.join(d, "hook-tee.py"), "dir": d}


_HOOK_PATH = re.compile(r"""(?:["']?\$\{?CLAUDE_PROJECT_DIR\}?["']?/)?(?:\./)?"""
                        r"""tools/agent-hooks/([\w.-]+\.py)""")


def eval_settings_hooks(path, hooks_dir, key, python="/usr/bin/python3 -I", mods=(), query=False):
    """(0.17) The hooks of a condition in tools/agent-hooks/settings-eval.json
    (the repository's hook settings for the eval: `conditions[key]`, e.g.
    `hook+test`), each command's @HOOKS@ the copies' directory (hooks_dir,
    lib/common.install_hooks) and @PYTHON@ `python`. None when the file
    does not exist; an error when it lacks the condition or a file it lists
    was not copied. (A file with a top-level `hooks`, the first draft's
    form, is read with its tools/agent-hooks/ paths pointed at the copies.)
    (E3, E5, E6) mods: the condition's modifiers of the file's `modifiers`
    (+rewrite, +nohints, +note): their `add` conditions' hooks too, their
    `env` in front of every command; query: the query-first hook from the
    file's `query` condition too (instead of the harness's own entry), so
    that it gets the modifiers' environment."""
    if not os.path.isfile(path):
        return None
    with open(path) as fh:
        data = json.load(fh)
    if "conditions" not in data:
        if mods:
            raise SystemExit("%s has no `conditions` (modifiers %s need them)" % (path, ", ".join(mods)))
        hooks_list = [data.get("hooks") or {}]
        sub = lambda c: _HOOK_PATH.sub(lambda m: shlex_quote(os.path.join(hooks_dir, m.group(1))), c)
    else:
        known = data.get("modifiers") or {}
        bad = [m for m in mods if m not in known]
        if bad:
            raise SystemExit("%s has no modifier %s (it has %s)"
                             % (path, ", ".join(bad), ", ".join(sorted(known))))
        keys = ([key] if key else []) + (["query"] if query else [])
        for m in mods:
            keys += [k for k in known[m].get("add") or [] if k not in keys]
        for k in keys:
            if k not in data["conditions"]:
                raise SystemExit("%s has no condition %r (it has %s)"
                                 % (path, k, ", ".join(sorted(data["conditions"]))))
        missing = [f for f in data.get("files") or []
                   if not os.path.isfile(os.path.join(hooks_dir, f))]
        if missing:
            raise SystemExit("hooks directory %s lacks %s (install_hooks)" % (hooks_dir,
                                                                             ", ".join(missing)))
        hooks_list = [data["conditions"][k] for k in keys]
        env = {}
        for m in mods:
            env.update(known[m].get("env") or {})
        prefix = "".join("%s=%s " % (k, shlex_quote(str(v))) for k, v in sorted(env.items()))
        sub = lambda c: prefix + c.replace("@HOOKS@", shlex_quote(hooks_dir)).replace("@PYTHON@", python)
    out = {}
    for hooks in hooks_list:
        for ev, entries in hooks.items():
            new = out.setdefault(ev, [])
            for e in entries:
                e = dict(e)
                hs = []
                for h in e.get("hooks") or []:
                    h = dict(h)
                    if h.get("command"):
                        h["command"] = sub(h["command"])
                    hs.append(h)
                e["hooks"] = hs
                new.append(e)
    return out


def shlex_quote(s):
    import shlex
    return shlex.quote(s)


def install_check_hook(ws_root):
    return install_hooks(ws_root)["check"]


def query_hook_summary(log_path):
    """result.json's query_hook (compiler-tools): what the query-first hook
    logged in the workspace's .git/agent-tools.jsonl, by record kind
    (query, blocked, escape, edit, edit-blocked, edit-escape, ...), the
    escapes' reasons, and the check hook's records counted apart."""
    kinds, reasons = {}, []
    try:
        with open(log_path) as fh:
            for line in fh:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                k = r.get("kind") or "?"
                kinds[k] = kinds.get(k, 0) + 1
                if k in ("escape", "edit-escape") and r.get("reason"):
                    reasons.append(str(r.get("reason"))[:160])
    except OSError:
        return None
    return {"kinds": kinds, "blocked": kinds.get("blocked", 0) + kinds.get("edit-blocked", 0),
            "escapes": kinds.get("escape", 0) + kinds.get("edit-escape", 0),
            "escape_reasons": reasons[:20]}


def check_hook_summary(log_path):
    """result.json's check_hook: what the hook did in a run (its log, one
    JSON line per check)."""
    recs = []
    try:
        with open(log_path) as fh:
            for line in fh:
                try:
                    recs.append(json.loads(line))
                except ValueError:
                    pass
    except OSError:
        pass
    codes = {}
    for r in recs:
        for c in r.get("codes") or []:
            codes[c] = codes.get(c, 0) + 1
    ms = sorted(r.get("ms") or 0 for r in recs)
    return {"checks": len(recs),
            "with_errors": sum(1 for r in recs if r.get("errors")),
            "errors": sum(r.get("errors") or 0 for r in recs),
            "codes": codes,
            "ms_median": ms[len(ms) // 2] if ms else None}


def final_check(ws, env):
    """`tachyonc check --json` on the finished workspace: its errors by code
    (None when the compiler has no --json, before 0.15)."""
    rc, out, err, _ = run_proc(["tachyonc", "check", "--json"], ws, env, 60)
    if rc not in (0, 1) or b"unknown option" in err:
        return None
    codes = {}
    n = 0
    for line in (err + out).decode("utf-8", "replace").splitlines():
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if isinstance(d, dict) and d.get("kind") == "diagnostic" and d.get("severity") == "error":
            n += 1
            codes[d.get("code") or ""] = codes.get(d.get("code") or "", 0) + 1
    return {"errors": n, "codes": codes}
