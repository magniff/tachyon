"""`run.py check-tasks`: the validity checks of the format spec, one line
per task.

(0.17) Also, for the program tasks:

- lints of both reference solutions: vole `volec fmt --check`,
  `lint --max-lines 1000`, `query unused` and `fix --dry-run` clean; Rust
  `rustfmt --check` and `rustc -D warnings` clean (`--no-lint` skips);
- variants: `variants/LANG-NAME.patch` (`diff -ruN a b` against
  solution/LANG/) is a second correct, idiomatic solution written another
  way (struct-like enum variants in Rust, one-line items, an iterator, a
  scratch copy left in the workspace); it must build and pass every test
  and the check, so that check.sh tests the task and not one way of
  writing it (0.16: 18-api-refactor's check failed correct Rust);
- the prompts: every ```tach block of prompts/*.md compiles (the
  rust-pairs condition's examples)."""

import glob
import os
import re
import shutil
import subprocess
import tempfile

from lib.common import EVAL_DIR, KINDS, base_env, load_tasks, run_proc
from lib.ctasks import check_ctask
from lib.grade import grade_dir, prepare_bins

ID_RE = re.compile(r"^\d\d-[a-z0-9]+(-[a-z0-9]+)*$")


def _sources(d, ext):
    if not os.path.isdir(d):
        return set()
    return {os.path.splitext(f)[0] for f in os.listdir(d) if f.endswith(ext)}


def check_task(task, bins, scratch):
    problems, notes = [], []
    if not ID_RE.match(task.id):
        problems.append("id is not NN-name")
    if task.kind not in KINDS:
        problems.append("kind %r is not one of %s" % (task.kind, "|".join(KINDS)))
    for f in ("task.md", "tach", "rust", "solution/tach", "solution/rust", "tests"):
        if not os.path.exists(os.path.join(task.path, f)):
            problems.append("missing %s" % f)
    if problems:
        return problems, notes
    tests = task.tests()
    if not 6 <= len(tests) <= 15:
        problems.append("%d hidden tests (want 6-15)" % len(tests))
    for name, inp, outp in tests:
        if not os.path.isfile(outp):
            problems.append("tests/%s.out missing" % name)
        elif os.path.getsize(inp) >= 1 << 20:
            problems.append("tests/%s.in is over 1 MB" % name)
    if problems:
        return problems, notes
    if task.check and not os.path.isfile(task.check_path()):
        problems.append("check %s missing" % task.check)
    # twins: the same module files in both languages
    for a, b in (("tach", "rust"), ("solution/tach", "solution/rust")):
        ta = _sources(os.path.join(task.path, a), ".vl")
        rb = _sources(os.path.join(task.path, b), ".rs")
        if ta != rb and (ta or task.kind != "write"):
            problems.append("%s and %s are not twins: %s vs %s"
                            % (a, b, sorted(ta), sorted(rb)))
    for lang, ext in (("tach", "main.vl"), ("rust", "main.rs")):
        if not os.path.isfile(os.path.join(task.path, "solution", lang, ext)):
            problems.append("solution/%s/%s missing" % (lang, ext))
    if problems:
        return problems, notes

    for lang in ("tach", "rust"):
        g = grade_dir(task, lang, os.path.join(task.path, "solution", lang),
                      os.path.join(scratch, task.id, "sol-" + lang), bins[lang])
        if not g["build_ok"]:
            problems.append("solution/%s does not build: %s"
                            % (lang, g["build_log"].strip().splitlines()[-1:]))
            continue
        bad = [t["name"] + " (" + t["note"] + ")" for t in g["tests"] if not t["ok"]]
        if bad:
            problems.append("solution/%s fails %s" % (lang, ", ".join(bad)))
        if g["check_ok"] is False:
            problems.append("solution/%s fails the check: %s" % (lang, g["check_msg"]))
        slowest = max((t["s"] for t in g["tests"]), default=0.0)
        notes.append("%s %d/%d max %.2fs" % (lang, g["tests_passed"],
                                             g["tests_total"], slowest))
        if slowest > task.test_timeout_s / 2:
            problems.append("solution/%s takes %.2fs on a test, over half the "
                            "%.0fs limit" % (lang, slowest, task.test_timeout_s))

        start = os.path.join(task.path, lang)
        gs = grade_dir(task, lang, start,
                       os.path.join(scratch, task.id, "start-" + lang), bins[lang])
        must_build = task.meta.get("starter_builds", task.kind != "write")
        if must_build and not gs["build_ok"]:
            problems.append("starter %s/ does not build (meta: starter_builds)" % lang)
        if not must_build and gs["build_ok"] and task.kind != "write":
            problems.append("starter %s/ builds, meta says starter_builds = false" % lang)
        if gs["success"]:
            problems.append("starter %s/ already passes every test and check" % lang)
        elif gs["build_ok"]:
            notes.append("starter-%s %d/%d" % (lang, gs["tests_passed"], gs["tests_total"]))
    for v in sorted(glob.glob(os.path.join(task.path, "variants", "*.patch"))):
        name = os.path.basename(v)[:-6]
        lang = name.split("-", 1)[0]
        if lang not in ("tach", "rust"):
            problems.append("variant %s: the name is LANG-NAME.patch, LANG tach or rust" % name)
            continue
        vdir = os.path.join(scratch, task.id, "variant-src-" + name)
        if os.path.exists(vdir):
            shutil.rmtree(vdir)
        shutil.copytree(os.path.join(task.path, "solution", lang), vdir)
        r = subprocess.run(["patch", "-p1", "-s", "-i", v], cwd=vdir, capture_output=True,
                           text=True)
        if r.returncode != 0:
            problems.append("variant %s does not apply: %s" % (name, (r.stdout + r.stderr)[-200:]))
            continue
        g = grade_dir(task, lang, vdir, os.path.join(scratch, task.id, "variant-" + name),
                      bins[lang])
        if not g["success"]:
            why = ("does not build" if not g["build_ok"] else
                   "fails the check: " + g["check_msg"] if g["check_ok"] is False else
                   "fails %d tests" % (g["tests_total"] - g["tests_passed"]))
            problems.append("variant %s %s" % (name, why))
        else:
            notes.append("variant %s ok" % name)
    return problems, notes


def lint_solution(task, lang, bins, scratch):
    """(0.17) The reference solution's lints: [problem]."""
    src = os.path.join(task.path, "solution", lang)
    out = []
    if lang == "tach":
        env = base_env(bins["tach"])
        cmds = [("fmt --check", ["volec", "fmt", "--check", "main.vl"], None),
                ("lint", ["volec", "lint", "--max-lines", "1000", "main.vl"], None),
                ("query unused", ["volec", "query", "unused", "--root", "main.vl"],
                 "nothing unused"),
                ("fix --dry-run", ["volec", "fix", "--dry-run", "--root", "main.vl"],
                 "nothing to fix")]
        for name, argv, want in cmds:
            rc, o, e, _ = run_proc(argv, src, env, 120)
            text = (o + e).decode("utf-8", "replace")
            if rc != 0 or (want and want not in text):
                out.append("solution/tach %s: %s" % (name, text.strip().splitlines()[:1]))
        return out
    rustfmt = shutil.which("rustfmt")
    if rustfmt:
        r = subprocess.run([rustfmt, "--check", "--edition", "2021", "main.rs"], cwd=src,
                           capture_output=True, text=True)
        if r.returncode != 0:
            out.append("solution/rust is not rustfmt-clean (%d diffs; rustfmt --edition 2021 "
                       "main.rs)" % r.stdout.count("Diff in"))
    tmp = os.path.join(scratch, task.id, "rmeta")
    os.makedirs(tmp, exist_ok=True)
    env = base_env(bins["rust"])
    env["TMPDIR"] = tmp
    rc, o, e, _ = run_proc(["rustc", "--edition", "2021", "-D", "warnings", "--emit=metadata",
                            "--out-dir", tmp, "main.rs"], src, env, 300)
    if rc != 0:
        first = [l for l in e.decode("utf-8", "replace").splitlines() if l.startswith("error")]
        out.append("solution/rust has warnings: %s" % (first[:1] or ["rustc failed"])[0][:160])
    return out


def check_prompts(bins, scratch):
    """(0.17) Every ```tach block of prompts/*.md compiles: [problem]."""
    out = []
    for md in sorted(glob.glob(os.path.join(EVAL_DIR, "prompts", "*.md"))):
        with open(md) as fh:
            text = fh.read()
        blocks = re.findall(r"^```tach\n(.*?)^```", text, re.S | re.M)
        for i, b in enumerate(blocks):
            d = os.path.join(scratch, "prompts", "%s-%d" % (os.path.basename(md)[:-3], i))
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "main.vl"), "w") as fh:
                fh.write(b)
            rc, o, e, _ = run_proc(["volec", "main.vl", "-o", "prog"], d,
                                   base_env(bins["tach"]), 120)
            if rc != 0:
                out.append("%s block %d does not build: %s" % (
                    os.path.basename(md), i + 1,
                    (o + e).decode("utf-8", "replace").strip().splitlines()[:1]))
    return out


def main(args):
    tasks = load_tasks(args.tasks_dir, args.tasks or None, args.set)
    root = tempfile.mkdtemp(prefix="vole-eval-check-")
    bins = None
    if any(not t.is_compiler for t in tasks):
        bins = prepare_bins(root, args.volec)
        if not os.path.exists(os.path.join(bins["rust"], "rustc")):
            print("error: rustc not found")
            return 1
    bad = 0
    for t in tasks:
        if t.is_compiler:
            # (0.16) a compiler task: the starter fails the grading, the
            # reference solution passes it (lib/ctasks.py)
            problems, notes = check_ctask(t, args.base, args.builder, root)
        else:
            problems, notes = check_task(t, bins, os.path.join(root, "work"))
            if not getattr(args, "no_lint", False):
                for lang in ("tach", "rust"):
                    problems += lint_solution(t, lang, bins, os.path.join(root, "work"))
        if problems:
            bad += 1
            print("FAIL %s: %s" % (t.id, "; ".join(problems)))
        else:
            print("ok   %s %s: %s" % (t.id, t.kind, ", ".join(notes)))
    if bins and not args.tasks:
        pp = check_prompts(bins, os.path.join(root, "work"))
        if pp:
            bad += 1
            print("FAIL prompts: %s" % "; ".join(pp))
        else:
            print("ok   prompts: every tach block builds")
    print("%d task(s), %d with problems" % (len(tasks), bad))
    if args.keep:
        print("kept: %s" % root)
    else:
        shutil.rmtree(root, ignore_errors=True)
    return 1 if bad else 0
