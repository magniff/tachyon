"""Builds a workspace with the fixed command, runs the hidden tests and
check.sh: the grading of the format spec."""

import filecmp
import os
import shutil
import subprocess

from lib.common import (BUILD_TIMEOUT_S, RUST_BUILD, TACH_BUILD, base_env,
                        copy_tree, normalise, run_proc, tail)


def prepare_bins(root, tachyonc):
    """bin-tach/tachyonc (a copy, so the frozen binary is readable from the
    agents' sandbox even when the original sits in the repo) and
    bin-rust/rustc (a link to the toolchain's own rustc, not rustup's
    proxy). Returns {"tach": dir, "rust": dir}."""
    bins = {"tach": os.path.join(root, "bin-tach"),
            "rust": os.path.join(root, "bin-rust")}
    os.makedirs(bins["tach"], exist_ok=True)
    os.makedirs(bins["rust"], exist_ok=True)
    tc = os.path.join(bins["tach"], "tachyonc")
    # (0.17 iterations) a copy that differs from --tachyonc is replaced
    if not os.path.exists(tc) or not filecmp.cmp(tc, tachyonc, shallow=False):
        if not os.path.isfile(tachyonc):
            raise SystemExit("no tachyon compiler at %s (--tachyonc PATH)"
                             % tachyonc)
        shutil.copy2(tachyonc, tc + ".tmp")
        os.replace(tc + ".tmp", tc)
    rc = os.path.join(bins["rust"], "rustc")
    if not os.path.lexists(rc):
        real = rustc_path()
        if real:
            os.symlink(real, rc)
    return bins


def rustc_path():
    rustc = shutil.which("rustc")
    if not rustc:
        return None
    try:
        sysroot = subprocess.run([rustc, "--print", "sysroot"],
                                 capture_output=True, text=True,
                                 timeout=60).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return rustc
    p = os.path.join(sysroot, "bin", "rustc")
    return p if os.path.isfile(p) else rustc


def tool_version(bin_dir, lang):
    argv = ["tachyonc", "--version"] if lang == "tach" else ["rustc", "--version"]
    rc, out, err, _ = run_proc(argv, bin_dir, base_env(bin_dir), 60)
    return (out or err).decode("utf-8", "replace").strip().splitlines()[0] \
        if (out or err) else "?"


def build(lang, cwd, bin_dir):
    argv = TACH_BUILD if lang == "tach" else RUST_BUILD
    rc, out, err, secs = run_proc(argv, cwd, base_env(bin_dir),
                                  BUILD_TIMEOUT_S)
    ok = rc == 0 and os.path.isfile(os.path.join(cwd, "prog"))
    return ok, tail(out + err), secs


def run_tests(task, cwd, bin_dir):
    """[(name, passed, seconds, note)] for every hidden test."""
    env = base_env(bin_dir)
    prog = os.path.join(cwd, "prog")
    # macOS scans a new binary on its first exec (1-2 s): do that once
    # here, outside the timed tests.
    run_proc([prog], cwd, env, 30, stdin_bytes=b"")
    res = []
    for name, inp, outp in task.tests():
        with open(outp, "rb") as fh:
            want = normalise(fh.read())
        rc, out, err, secs = run_proc([prog], cwd, env, task.test_timeout_s,
                                      stdin_path=inp)
        retried = ""
        if rc is None:
            # (0.16) once more: with 8 agents building and running programs,
            # a test of a 0.5 s program stalled past 2.5 s (several 16-perf-tight
            # runs whose programs take 0.2-0.6 s alone); a slow program times
            # out twice
            rc, out, err, secs = run_proc([prog], cwd, env, task.test_timeout_s,
                                          stdin_path=inp)
            retried = " (after a timeout, retried)"
        if rc is None:
            res.append((name, False, secs, "timeout" + (", twice" if retried else "")))
        elif rc != 0:
            res.append((name, False, secs, "exit %d: %s" % (rc, tail(err, 200)) + retried))
        elif normalise(out) != want:
            res.append((name, False, secs, "wrong output" + retried))
        else:
            res.append((name, True, secs, retried.strip()))
    return res


def run_check(task, cwd, bin_dir, lang):
    path = task.check_path()
    if not path:
        return True, ""
    env = base_env(bin_dir)
    env["EVAL_LANG"] = lang
    rc, out, err, _ = run_proc(["/bin/sh", path], cwd, env, 120)
    return rc == 0, tail(err or out, 400).strip()


def grade_dir(task, lang, src, scratch, bin_dir):
    """Grades the program in `src` in a fresh copy at `scratch` (the
    agent's own `prog` and leftovers do not count). Returns a dict."""
    if os.path.exists(scratch):
        shutil.rmtree(scratch)
    copy_tree(src, scratch, skip=(".git", "prog"))
    ok, log, build_s = build(lang, scratch, bin_dir)
    g = {"build_ok": ok, "build_log": log if not ok else "",
         "build_s": round(build_s, 2), "tests": [], "tests_passed": 0,
         "tests_total": len(task.tests()), "check_ok": None,
         "check_msg": ""}
    if ok:
        tests = run_tests(task, scratch, bin_dir)
        g["tests"] = [{"name": n, "ok": p, "s": round(s, 3), "note": note}
                      for n, p, s, note in tests]
        g["tests_passed"] = sum(1 for t in tests if t[1])
    if task.check:
        g["check_ok"], g["check_msg"] = run_check(task, scratch, bin_dir, lang)
    g["success"] = bool(ok and g["tests_passed"] == g["tests_total"]
                        and g["check_ok"] is not False)
    return g
