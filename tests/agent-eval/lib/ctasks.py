"""Compiler tasks (ctasks/, 0.16): a change to tachyon's own compiler, made
in a copy of the repository at a fixed commit, graded by building it and
running a part of its test suite plus the task's own checks.

A task is `ctasks/NN-name/`:

- `meta.toml`: `kind` (optimize|refactor|fix|feature), `title`,
  `timeout_s` (default 3600), `base` (the commit the task is made from,
  a ref: "v0.16.0"), `base_fallback` (the commit used while `base` does
  not exist, for validating the task before that release), `suite` (the
  tests/run.sh filters the grading runs, comma-separated; every one must
  pass), optional `same_output` (comma-separated corpus paths for
  `tachyonc same-output STARTER`: the outputs of the graded compiler and
  the starter's must be identical), optional `grade_timeout_s`;
- `task.md`: what the agent is asked (the prompt's last part);
- `README.md`: for people: the change, the grading, the reference;
- `starter.patch` (optional): applied to the base to make the starting
  point (a planted bug); `solution.patch`: the reference solution,
  applied on top of the starter (both `git diff` output, -p1);
- `hidden/` (optional): files copied over the graded tree before it is
  built (hidden regression tests, `tests/run/eval_*.tach`);
- `grade.sh` (optional): run last, in the graded tree's root, with
  `TACHYONC` (the graded compiler), `EVAL_STARTER_TACHYONC` (the
  starter's compiler), `EVAL_STARTER_TREE` (the starter's source, built)
  and `EVAL_TASK` (the task directory); exit status
  non-zero with a one-line reason on stderr when it fails.

The workspace (`setup_workspace`): `git archive` of the base, the
starter patch, `bootstrap/eval-build.sh` (lib/eval-build.sh: the
build bootstrap.sh does for HEAD, from `target/builder/tachyonc`, the
release that builds the base, since the copy has no tags or cache), the
starter's compiler in `target/tachyonc` (and `target/tools/tachyonc` for
compiler-tools), AGENTS.md for the condition, CLAUDE.md and .claude/
removed (the prompt carries AGENTS.md), `git init` with one commit."""

import json
import os
import re
import shutil
import subprocess
import tempfile
import threading

from lib.common import (COMPILER_CONDS, EVAL_DIR, REPO_ROOT, base_env, copy_tree,
                        parse_toml, run_proc, tail)

CTASKS_DIR = os.path.join(EVAL_DIR, "ctasks")
C_KINDS = ("optimize", "refactor", "fix", "feature")
EVAL_BUILD = os.path.join(EVAL_DIR, "lib", "eval-build.sh")
BUILD_TIMEOUT_S = 900


class CTask:
    is_compiler = True

    def __init__(self, path):
        self.path = path
        self.id = os.path.basename(path)
        with open(os.path.join(path, "meta.toml")) as fh:
            self.meta = parse_toml(fh.read())
        self.kind = self.meta.get("kind", "fix")
        self.title = self.meta.get("title", self.id)
        self.timeout_s = int(self.meta.get("timeout_s", 3600))
        self.grade_timeout_s = int(self.meta.get("grade_timeout_s", 1800))
        self.base = self.meta.get("base")
        self.base_fallback = self.meta.get("base_fallback")
        self.suite = [f.strip() for f in str(self.meta.get("suite", "")).split(",") if f.strip()]
        self.same_output = [c.strip() for c in str(self.meta.get("same_output", "")).split(",")
                            if c.strip()]
        self.check = "grade.sh" if os.path.isfile(os.path.join(path, "grade.sh")) else None

    def text(self):
        with open(os.path.join(self.path, "task.md")) as fh:
            return fh.read()

    def patch(self, name):
        p = os.path.join(self.path, name)
        return p if os.path.isfile(p) else None

    def tests(self):  # (the program tasks' interface: none here)
        return []


def is_ctask_dir(d):
    return os.path.isfile(os.path.join(d, "meta.toml")) and \
        os.path.isfile(os.path.join(d, "solution.patch"))


# ---------------------------------------------------------------- git

def git(args, cwd=REPO_ROOT, check=True, **kw):
    return subprocess.run(["git"] + args, cwd=cwd, check=check,
                          capture_output=True, **kw)


def rev(ref):
    r = git(["rev-parse", "-q", "--verify", ref + "^{commit}"], check=False, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def resolve_base(task, override=None):
    """(the ref used, its commit): --base, else meta `base`, else
    `base_fallback`."""
    tried = []
    for ref in (override, task.base, task.base_fallback):
        if not ref:
            continue
        sha = rev(ref)
        if sha:
            return ref, sha
        tried.append(ref)
    raise SystemExit("%s: none of the base commits exists: %s" % (task.id, ", ".join(tried)))


def detect_host():
    import platform
    s, m = platform.system(), platform.machine()
    return {("Darwin", "arm64"): "aarch64-macos", ("Darwin", "x86_64"): "x86_64-macos",
            ("Linux", "x86_64"): "x86_64-linux", ("Linux", "aarch64"): "aarch64-linux"
            }.get((s, m), "unsupported")


def main_checkout():
    r = git(["rev-parse", "--path-format=absolute", "--git-common-dir"], check=False, text=True)
    common = r.stdout.strip()
    return os.path.dirname(common) if common else REPO_ROOT


def builder_for(sha, override=None):
    """The compiler that builds the base: the `built_by` release of the last
    [[release]] in the base's bootstrap/releases.toml, from a bootstrap
    cache (this checkout's, the main checkout's, $TACHYON_BOOTSTRAP_CACHE)."""
    if override:
        if not os.access(override, os.X_OK):
            raise SystemExit("--builder %s is not an executable" % override)
        return os.path.abspath(override)
    text = git(["show", sha + ":bootstrap/releases.toml"], text=True).stdout
    releases, cur = [], None
    for line in text.splitlines():
        s = line.strip()
        if s == "[[release]]":
            cur = {}
            releases.append(cur)
        elif s.startswith("["):
            cur = None
        elif cur is not None and "=" in s and not s.startswith("#"):
            k, v = s.split("=", 1)
            cur[k.strip()] = v.strip().strip('"')
    if not releases:
        raise SystemExit("no [[release]] in releases.toml at %s" % sha[:12])
    by = releases[-1].get("built_by")
    tag = next((r.get("tag") for r in releases if r.get("version") == by), "v" + by)
    tsha = rev(tag)
    if not tsha:
        raise SystemExit("the builder release %s (tag %s) is not tagged here; pass --builder"
                         % (by, tag))
    host = detect_host()
    caches = [os.environ.get("TACHYON_BOOTSTRAP_CACHE"),
              os.path.join(REPO_ROOT, "target", "bootstrap"),
              os.path.join(main_checkout(), "target", "bootstrap")]
    for c in caches:
        if not c:
            continue
        p = os.path.join(c, host, "%s-%s" % (tag, tsha[:12]), "tachyonc")
        if os.access(p, os.X_OK):
            return p
    raise SystemExit("no bootstrap cache holds %s (%s); run bootstrap/bootstrap.sh, "
                     "or pass --builder" % (tag, tsha[:12]))


# ---------------------------------------------------------------- trees

def apply_patch(tree, patch):
    r = subprocess.run(["git", "apply", "--whitespace=nowarn", "-p1", patch], cwd=tree,
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("%s does not apply: %s" % (os.path.basename(patch),
                                                      tail(r.stderr, 400).strip()))


def make_tree(task, sha, dest, solution=False):
    """The base at `sha` extracted into dest, the starter patch applied
    (and the reference solution's, with solution=True)."""
    if os.path.exists(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    a = subprocess.Popen(["git", "archive", "--format=tar", sha], cwd=REPO_ROOT,
                         stdout=subprocess.PIPE)
    subprocess.run(["tar", "-x", "-C", dest], stdin=a.stdout, check=True)
    a.stdout.close()
    if a.wait() != 0:
        raise RuntimeError("git archive %s failed" % sha[:12])
    for name in (("starter.patch", "solution.patch") if solution else ("starter.patch",)):
        p = task.patch(name)
        if p:
            apply_patch(dest, p)
    install_build_script(dest)


def install_build_script(tree):
    d = os.path.join(tree, "bootstrap")
    os.makedirs(d, exist_ok=True)
    dst = os.path.join(d, "eval-build.sh")
    shutil.copyfile(EVAL_BUILD, dst)
    os.chmod(dst, 0o755)


def build(tree, builder, quick=False):
    """bootstrap/eval-build.sh in tree (the harness's copy) with `builder`:
    (ok, log, seconds)."""
    install_build_script(tree)
    env = base_env("/nonexistent")
    env["EVAL_BUILDER"] = builder
    argv = ["/bin/sh", "bootstrap/eval-build.sh"] + (["--quick"] if quick else [])
    rc, out, err, secs = run_proc(argv, tree, env, BUILD_TIMEOUT_S)
    ok = rc == 0 and os.access(os.path.join(tree, "target", "tachyonc"), os.X_OK)
    return ok, tail(out + err, 3000), secs


_tree_lock = threading.Lock()


def built_tree(task, sha, builder, cache_root, solution=False):
    """A built tree of the starter (or the reference solution), cached under
    cache_root: its path (target/tachyonc inside)."""
    which = "solution" if solution else "starter"
    d = os.path.join(cache_root, "ctask-trees", task.id, sha[:12], which)
    with _tree_lock:
        if os.access(os.path.join(d, "target", "tachyonc"), os.X_OK) and \
                os.path.isfile(os.path.join(d, ".built")):
            return d
        make_tree(task, sha, d, solution=solution)
        ok, log, _ = build(d, builder)
        if not ok:
            raise RuntimeError("the %s of %s does not build: %s" % (which, task.id, log[-600:]))
        open(os.path.join(d, ".built"), "w").close()
        return d


# ---------------------------------------------------------------- AGENTS.md

PLAIN_READ = """## Reading and changing the source

Read the source with your file tools (Read, Grep, Glob) or the shell
(grep, sed, cat), and change it with Edit and Write. Use `tachyonc` to
build and test: `target/tachyonc check` (the front end's errors, one per
line), compiling programs, `tests/run.sh`.
"""


def agents_md(tree, cond):
    """AGENTS.md for the condition: as it is for compiler-tools; for
    compiler-plain, without the tools table ("Read source through the
    compiler", the hooks and the feedback line): file tools and the shell."""
    with open(os.path.join(tree, "AGENTS.md")) as fh:
        text = fh.read()
    if cond == "compiler-tools":
        return text
    m = re.search(r"^## Read source through the compiler\n.*?(?=^## )", text, re.S | re.M)
    if not m:
        raise RuntimeError("AGENTS.md has no '## Read source through the compiler' section")
    text = text[:m.start()] + PLAIN_READ + "\n" + text[m.end():]
    # the inner loop's mentions of the hook and the tools binary
    text = re.sub(r"the check hook's errors \(or (`target/tachyonc check`)\s+when the hook is "
                  r"not there\)", r"\1", text)
    text = re.sub(r";\s+when its suite passes it is also\s+`target/tools/tachyonc`, the binary "
                  r"to query and edit with;", ";", text)
    left = [w for w in PLAIN_FORBIDDEN if w in text]
    if left:
        raise RuntimeError("AGENTS.md for compiler-plain still names the tools: %s (update "
                           "ctasks.agents_md for this AGENTS.md)" % ", ".join(left))
    return text


# What the compiler-plain AGENTS.md must not mention.
PLAIN_FORBIDDEN = ("tachyonc query", "query show", "edit patch", "tachyonc refactor", "hook",
                   "target/tools/tachyonc", "agent-feedback", "no-query")


# ---------------------------------------------------------------- workspace

def setup_workspace(task, cond, sha, ws, builder, starter_tree, env):
    """The agent's copy of the repository (see the module's comment)."""
    make_tree(task, sha, ws)
    for gone in ("CLAUDE.md", ".claude"):
        p = os.path.join(ws, gone)
        if os.path.isdir(p):
            shutil.rmtree(p)
        elif os.path.exists(p):
            os.remove(p)
    text = agents_md(ws, cond)
    with open(os.path.join(ws, "AGENTS.md"), "w") as fh:
        fh.write(text)
    tgt = os.path.join(ws, "target")
    os.makedirs(os.path.join(tgt, "builder"), exist_ok=True)
    shutil.copy2(builder, os.path.join(tgt, "builder", "tachyonc"))
    shutil.copy2(os.path.join(starter_tree, "target", "tachyonc"), os.path.join(tgt, "tachyonc"))
    if cond == "compiler-tools":
        os.makedirs(os.path.join(tgt, "tools"), exist_ok=True)
        shutil.copy2(os.path.join(starter_tree, "target", "tachyonc"),
                     os.path.join(tgt, "tools", "tachyonc"))
    e = dict(env, GIT_AUTHOR_NAME="eval", GIT_AUTHOR_EMAIL="eval@localhost",
             GIT_COMMITTER_NAME="eval", GIT_COMMITTER_EMAIL="eval@localhost")
    for argv in (["git", "init", "-q"],
                 ["git", "config", "user.name", "eval"],
                 ["git", "config", "user.email", "eval@localhost"]):
        subprocess.run(argv, cwd=ws, env=e, check=True, capture_output=True)
    os.makedirs(os.path.join(ws, ".git", "info"), exist_ok=True)
    with open(os.path.join(ws, ".git", "info", "exclude"), "a") as fh:
        fh.write("/target/\n")
    subprocess.run(["git", "add", "-A"], cwd=ws, env=e, check=True, capture_output=True)
    subprocess.run(["git", "commit", "-q", "-m", "starter"], cwd=ws, env=e, check=True,
                   capture_output=True)
    if cond == "compiler-tools":
        # the query-first hook enforces once the compiler answers queries
        open(os.path.join(ws, ".git", "agent-query-ready"), "w").close()


def workspace_changes(ws, dest):
    """The agent's changes against the starter commit (target/ left out),
    as a patch at dest; (files changed, lines added, lines removed)."""
    env = dict(os.environ, GIT_INDEX_FILE=os.path.join(tempfile.mkdtemp(), "index"))
    subprocess.run(["git", "read-tree", "HEAD"], cwd=ws, env=env, capture_output=True)
    subprocess.run(["git", "add", "-A", "."], cwd=ws, env=env, capture_output=True)
    diff = subprocess.run(["git", "diff", "--cached", "--binary", "HEAD"], cwd=ws, env=env,
                          capture_output=True).stdout
    stat = subprocess.run(["git", "diff", "--cached", "--numstat", "HEAD"], cwd=ws, env=env,
                          capture_output=True, text=True).stdout
    with open(dest, "wb") as fh:
        fh.write(diff)
    files = adds = dels = 0
    for line in stat.splitlines():
        parts = line.split("\t")
        if len(parts) >= 3:
            files += 1
            adds += int(parts[0]) if parts[0].isdigit() else 0
            dels += int(parts[1]) if parts[1].isdigit() else 0
    shutil.rmtree(os.path.dirname(env["GIT_INDEX_FILE"]), ignore_errors=True)
    return files, adds, dels


# ---------------------------------------------------------------- grading

def _suite_failures(text):
    return [line.split(":", 1)[0].split(" ", 1)[1] for line in text.splitlines()
            if line.startswith(("FAIL ", "XPASS ")) and " " in line][:20]


def grade(task, src, scratch, builder, starter_compiler):
    """Grades the tree in `src` in a copy at `scratch`: the hidden files
    over it, the build (with the fixpoint), every suite filter, same-output
    against the starter, grade.sh. Returns a dict (success, steps...)."""
    if os.path.exists(scratch):
        shutil.rmtree(scratch)
    copy_tree(src, scratch, skip=(".git", "target"))
    hidden = os.path.join(task.path, "hidden")
    if os.path.isdir(hidden):
        copy_tree(hidden, scratch)
    os.makedirs(os.path.join(scratch, "target"), exist_ok=True)
    ok, log, secs = build(scratch, builder)
    g = {"build_ok": ok, "build_log": "" if ok else log[-1500:], "build_s": round(secs, 1),
         "suite": [], "same_output_ok": None, "same_output_msg": "",
         "check_ok": None, "check_msg": ""}
    steps = [ok]
    env = base_env("/nonexistent")
    tc = os.path.join(scratch, "target", "tachyonc")
    if ok:
        for f in task.suite:
            rc, out, err, s = run_proc(["/bin/sh", "tests/run.sh", "-c", tc, f], scratch, env,
                                       task.grade_timeout_s)
            text = (out + err).decode("utf-8", "replace")
            totals = re.search(r"^\s*total\s+(\d+)\s+(\d+)\s+(\d+)", text, re.M)
            entry = {"filter": f, "ok": rc == 0, "s": round(s, 1),
                     "passed": int(totals.group(1)) if totals else 0,
                     "failed": int(totals.group(3)) if totals else None,
                     "fails": _suite_failures(text)}
            if rc == 2:
                entry["note"] = "no cases match"
            elif rc is None:
                entry["note"] = "timeout"
            elif rc != 0 and not totals:
                # tests/run.sh stopped before running a case (a stale
                # generated file, a missing tool): its first lines say why
                entry["note"] = "stopped before the cases"
                entry["head"] = "\n".join(text.strip().splitlines()[:8])[:800]
            g["suite"].append(entry)
            steps.append(entry["ok"])
        if task.same_output:
            argv = [tc, "same-output", starter_compiler]
            for c in task.same_output:
                argv += ["--corpus", c]
            rc, out, err, s = run_proc(argv, scratch, env, task.grade_timeout_s)
            g["same_output_ok"] = rc == 0
            g["same_output_s"] = round(s, 1)
            g["same_output_msg"] = tail(out + err, 600).strip()
            steps.append(rc == 0)
        if task.check:
            e = dict(env, TACHYONC=tc, EVAL_STARTER_TACHYONC=starter_compiler,
                     EVAL_STARTER_TREE=os.path.dirname(os.path.dirname(starter_compiler)),
                     EVAL_TASK=task.path)
            rc, out, err, s = run_proc(["/bin/sh", os.path.join(task.path, task.check)],
                                       scratch, e, task.grade_timeout_s)
            g["check_ok"] = rc == 0
            g["check_msg"] = tail(err or out, 600).strip()
            steps.append(rc == 0)
    else:
        steps += [False] * (len(task.suite) + bool(task.same_output) + bool(task.check))
    g["tests_passed"] = sum(1 for s in steps if s)
    g["tests_total"] = len(steps)
    g["success"] = all(steps)
    return g


# ---------------------------------------------------------------- check-tasks

def check_ctask(task, base_override, builder_override, root):
    """(problems, notes): the starter builds and fails the grading, the
    reference solution passes it."""
    problems, notes = [], []
    if task.kind not in C_KINDS:
        problems.append("kind %r is not one of %s" % (task.kind, "|".join(C_KINDS)))
    if not re.match(r"^\d\d-[a-z0-9]+(-[a-z0-9]+)*$", task.id):
        problems.append("id is not NN-name")
    for f in ("task.md", "README.md", "solution.patch"):
        if not os.path.isfile(os.path.join(task.path, f)):
            problems.append("missing %s" % f)
    if not task.suite:
        problems.append("meta.toml: no `suite` filters")
    if problems:
        return problems, notes
    try:
        ref, sha = resolve_base(task, base_override)
        builder = builder_for(sha, builder_override)
    except SystemExit as e:
        return [str(e)], notes
    notes.append("base %s (%s)" % (ref, sha[:12]))
    try:
        st = built_tree(task, sha, builder, root)
    except (RuntimeError, subprocess.CalledProcessError) as e:
        return ["starter: %s" % e], notes
    for cond in COMPILER_CONDS:
        try:
            agents_md(st, cond)
        except RuntimeError as e:
            problems.append(str(e))
    starter_tc = os.path.join(st, "target", "tachyonc")
    try:
        sol = os.path.join(root, "work", task.id, "solution-src")
        make_tree(task, sha, sol, solution=True)
    except RuntimeError as e:
        return problems + ["solution: %s" % e], notes
    gs = grade(task, sol, os.path.join(root, "work", task.id, "solution"), builder, starter_tc)
    if not gs["success"]:
        problems.append("the reference solution fails: %s" % summary(gs))
    else:
        notes.append("solution passes (%s)" % summary(gs))
    gst = grade(task, st, os.path.join(root, "work", task.id, "starter"), builder, starter_tc)
    if gst["success"]:
        problems.append("the starter already passes the grading")
    else:
        notes.append("starter fails (%s)" % summary(gst))
    return problems, notes


def summary(g):
    if not g["build_ok"]:
        return "build: " + (g["build_log"].strip().splitlines() or ["?"])[-1][:200]
    parts = []
    for s in g["suite"]:
        parts.append("%s %s%s" % (s["filter"], "ok" if s["ok"] else "FAIL",
                                  "" if s["ok"] else " " + ",".join(s["fails"][:3])
                                  + (" (" + s["note"] + ")" if s.get("note") else "")
                                  + (": " + s["head"].splitlines()[0][:120]
                                     if s.get("head") else "")))
    if g["same_output_ok"] is not None:
        parts.append("same-output " + ("ok" if g["same_output_ok"] else "DIFFERS"))
    if g["check_ok"] is not None:
        parts.append("grade.sh " + ("ok" if g["check_ok"] else "FAIL: " + g["check_msg"][-200:]))
    return "; ".join(parts)


# ---------------------------------------------------------------- regrade

def regrade_main(args):
    """run.py regrade RUNDIR...: grades finished compiler-task runs again
    from what they kept, without the agent: the starter tree (built, cached
    under --ws-root) with the run's changes.patch applied, graded as `run`
    grades it. grade.json is replaced and result.json's grading fields are
    updated (the old ones kept as `regraded_from`). --only-stopped picks the
    runs where a suite filter stopped before running any case."""
    from lib.common import load_tasks, write_json
    tasks = {t.id: t for t in load_tasks(None, None, "compiler")}
    ws_root = os.path.abspath(args.ws_root or os.path.join(
        os.environ.get("TMPDIR", "/tmp"), "tachyon-eval", "regrade"))
    os.makedirs(ws_root, exist_ok=True)
    runs = []
    for top in args.rundirs:
        for root, _, files in os.walk(top):
            if "result.json" in files and "changes.patch" in files:
                runs.append(root)
    infos = {}
    n = 0
    for rdir in sorted(runs):
        with open(os.path.join(rdir, "result.json")) as fh:
            res = json.load(fh)
        task = tasks.get(res["task"])
        if not task or res.get("lang") != "compiler":
            continue
        gpath = os.path.join(rdir, "grade.json")
        old = json.load(open(gpath)) if os.path.exists(gpath) else {}
        if args.only_stopped and not any(
                not s.get("ok") and s.get("failed") is None and s.get("note") != "timeout"
                for s in old.get("suite", [])):
            continue
        if task.id not in infos:
            sha = res.get("base_commit") or resolve_base(task)[1]
            builder = builder_for(sha, args.builder)
            infos[task.id] = (sha, builder, built_tree(task, sha, builder, ws_root))
        sha, builder, st = infos[task.id]
        tree = os.path.join(ws_root, "regrade-tree")
        if os.path.exists(tree):
            shutil.rmtree(tree)
        copy_tree(st, tree, skip=("target",))
        patch = os.path.join(rdir, "changes.patch")
        if os.path.getsize(patch):
            r = subprocess.run(["git", "apply", "--binary", "--whitespace=nowarn",
                                os.path.abspath(patch)], cwd=tree, capture_output=True,
                               text=True)
            if r.returncode != 0:
                print("skip %s: changes.patch does not apply: %s" % (rdir, r.stderr.strip()[:200]))
                continue
        g = grade(task, tree, os.path.join(ws_root, "regrade-grade"), builder,
                  os.path.join(st, "target", "tachyonc"))
        write_json(gpath, g)
        prev = {k: res.get(k) for k in ("success", "tests_passed", "tests_total", "build_ok",
                                         "check_ok", "same_output_ok", "grade_summary")}
        res.update({"success": g["success"], "tests_passed": g["tests_passed"],
                    "tests_total": g["tests_total"], "build_ok": g["build_ok"],
                    "check_ok": g.get("check_ok"), "same_output_ok": g.get("same_output_ok"),
                    "grade_summary": summary(g), "regraded_from": prev})
        write_json(os.path.join(rdir, "result.json"), res)
        n += 1
        print("%s %s -> %s: %s" % (rdir, "OK" if prev["success"] else "FAIL",
                                   "OK" if g["success"] else "FAIL", res["grade_summary"]))
    print("regraded %d run(s)" % n)
    return 0
