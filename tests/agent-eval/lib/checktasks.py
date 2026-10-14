"""`run.py check-tasks`: the validity checks of the format spec, one line
per task."""

import os
import re
import shutil
import tempfile

from lib.common import KINDS, load_tasks
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
        ta = _sources(os.path.join(task.path, a), ".tach")
        rb = _sources(os.path.join(task.path, b), ".rs")
        if ta != rb and (ta or task.kind != "write"):
            problems.append("%s and %s are not twins: %s vs %s"
                            % (a, b, sorted(ta), sorted(rb)))
    for lang, ext in (("tach", "main.tach"), ("rust", "main.rs")):
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
    return problems, notes


def main(args):
    tasks = load_tasks(args.tasks_dir, args.tasks or None)
    root = tempfile.mkdtemp(prefix="tachyon-eval-check-")
    bins = prepare_bins(root, args.tachyonc)
    if not os.path.exists(os.path.join(bins["rust"], "rustc")):
        print("error: rustc not found")
        return 1
    bad = 0
    for t in tasks:
        problems, notes = check_task(t, bins, os.path.join(root, "work"))
        if problems:
            bad += 1
            print("FAIL %s: %s" % (t.id, "; ".join(problems)))
        else:
            print("ok   %s %s: %s" % (t.id, t.kind, ", ".join(notes)))
    print("%d task(s), %d with problems" % (len(tasks), bad))
    shutil.rmtree(root, ignore_errors=True)
    return 1 if bad else 0
