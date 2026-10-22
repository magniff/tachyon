"""(0.17) The self-check before a round: can an agent build, run, test
and write in its workspace, inside the sandbox it will have?

The 0.16 round lost its first compiler-task pass (48 runs) to `mktemp`
failing in the sandbox: no agent could run tests/run.sh. Nothing in the
harness noticed; the agents worked around it or gave up. The self-check
runs the same operations before any run and stops the round when one
fails.

Per kind of workspace the round needs (`tach`, `rust` program tasks;
`compiler` tasks), set up exactly as a run sets it up (lib/runner.py,
lib/ctasks.py), with a probe program (or the task's tree) and
`selfcheck.sh`, which runs each probe and writes `ok NAME` or `FAIL NAME:
why` lines to `selfcheck.out`:

- `offline` (no model, free): selfcheck.sh under sandbox-exec with an
  approximation of Claude Code's box (writes only in the workspace and a
  private temp directory that $TMPDIR names; the per-user temp directory,
  this repository and ~/.claude closed);
- `hosted` (the default for the Claude backend; one short session per
  kind, Haiku, about a cent): the agent is told to run selfcheck.sh, then
  the build and run commands one at a time, to write a file with the Write
  tool, then a list of command forms that the 0.16 round saw refused
  (`&&`, `$?`, `$VAR`, a loop, a heredoc, `$(...)`, `cd`, a pipe, ...).
  The probes in selfcheck.out and the build, run and Write calls are
  required; the forms are measured: which of them the permission layer
  still refuses with this allowlist (`refusals` in selfcheck.json, also
  in runs.jsonl). Real sandbox, real permissions, real hooks.

`run.py run` runs it first (`--selfcheck auto|hosted|offline|none`); the
result is `OUT/selfcheck.json`, reused for 12 hours when nothing it
depends on changed. `run.py selfcheck` runs it alone."""

import hashlib
import json
import os
import shutil
import subprocess
import time

from lib import anatomy, claude_backend
from lib.common import (DEFAULT_RESULTS_DIR, EVAL_DIR, REPO_ROOT, base_env, install_hooks,
                        install_mktemp_shim, private_paths, run_proc, write_json)

TACH_PROBE = """use std::{Scanner, read_stdin_in};

// The self-check's probe: the sum of the integers on stdin.
fn main(gpa: Gpa) -> i32 {
    let input = read_stdin_in(gpa).unwrap();
    defer input.free();
    let mut sc = Scanner::new(input.as_slice());
    let mut t = 0;
    while let Ok(n) = sc.next_int() {
        t += n;
    }
    println(f"{t}");
    0
}
"""

RUST_PROBE = """use std::io::Read;

// The self-check's probe: the sum of the integers on stdin.
fn main() {
    let mut s = String::new();
    std::io::stdin().read_to_string(&mut s).unwrap();
    let t: i64 = s.split_whitespace().filter_map(|w| w.parse::<i64>().ok()).sum();
    println!("{}", t);
}
"""

SCRIPT_HEAD = r"""#!/bin/sh
# (agent eval) the self-check's probes; one line each into selfcheck.out
out=selfcheck.out
: > "$out"
probe() {
    name=$1; shift
    if res=$("$@" 2>&1); then
        echo "ok $name" >> "$out"
    else
        echo "FAIL $name: $(printf '%s' "$res" | tail -n 2 | tr '\n' ' ' | cut -c1-220)" >> "$out"
    fi
}
probe write-ws sh -c 'echo x > probe-write.txt && rm probe-write.txt'
probe tmpdir-write sh -c 'f="${TMPDIR:-/tmp}/eval-sc-$$"; echo x > "$f" && rm "$f"'
probe mktemp sh -c 'f=$(mktemp) && rm "$f"'
probe mktemp-d sh -c 'd=$(mktemp -d) && rmdir "$d"'
probe python3 python3 -c 'print(1)'
probe git git status --short
"""

SCRIPT_TACH = r"""probe version volec --version
probe build volec main.vl -o prog
probe run sh -c 'test "$(printf "1 2 3\n" | ./prog)" = 6'
probe check volec check main.vl
probe guide sh -c 'volec guide > /dev/null'
"""

SCRIPT_RUST = r"""probe version rustc --version
probe build rustc -O --edition 2021 main.rs -o prog
probe run sh -c 'test "$(printf "1 2 3\n" | ./prog)" = 6'
"""

SCRIPT_TEST = r"""probe test-command sh -c 'volec test --help > /dev/null'
"""

SCRIPT_COMPILER = r"""probe version target/volec --version
probe check target/volec check
probe embed sh compiler/std/embed.sh -c
probe eval-build sh bootstrap/eval-build.sh --quick
probe suite sh tests/run.sh -c target/volec arith_i64_basic
probe tools-query sh -c 'test ! -x target/tools/volec || target/tools/volec query items crate > /dev/null'
"""

SCRIPT_COMPILER_TEST = r"""probe test-command sh -c 'target/tools/volec test --help > /dev/null'
"""

# Optional probes: reported, never stop a round.
OPTIONAL = {"git", "guide", "tools-query"}

# Command forms the 0.16 round saw refused, one Bash call each in the
# hosted session; measured, not required. (name, command per kind)
FORMS = [
    ("chain &&", {"tach": "volec main.vl -o prog && ./prog < in.txt",
                  "rust": "rustc -O --edition 2021 main.rs -o prog && ./prog < in.txt",
                  "compiler": "target/volec --version && git status --short"}),
    ("status $?", {"*": "./prog < in.txt; echo \"rc=$?\"",
                   "compiler": "target/volec --version; echo \"rc=$?\""}),
    ("variable", {"*": "X=in.txt; cat $X"}),
    ("$TMPDIR redirect", {"*": "printf '1 2\\n' > $TMPDIR/eval-sc-probe.txt"}),
    ("loop", {"*": "for f in in.txt; do wc -c $f; done"}),
    ("heredoc", {"*": "cat > heredoc.txt <<'EOF'\nhello\nEOF"}),
    ("subst $(...)", {"*": "echo $(wc -l < in.txt)"}),
    ("pipe", {"*": "printf '4 5\\n' | ./prog",
              "compiler": "git status --short | head -3"}),
    ("awk $1", {"*": "seq 1 3 | awk '{s += $1} END {print s}'"}),
    ("python3 -c", {"*": "python3 -c 'print(6)'"}),
    ("perl", {"*": "perl -e 'print 1'"}),
    ("other ./binary", {"tach": "cp prog prog2 && ./prog2 < in.txt",
                        "rust": "cp prog prog2 && ./prog2 < in.txt",
                        "compiler": "./target/volec --version"}),
    ("sed -i", {"*": "sed -i '' 's/x/y/' written.txt"}),
    # last: Claude's Bash keeps the directory a `cd` moves to
    ("cd chain", {"*": "cd sub && ls"}),
]

PROMPT = """This is a harness self-check, not a programming task. Do exactly
the following, in order, and nothing else. If a step is refused or fails,
do not retry it and do not work around it: go on with the next step.

1. Run `sh selfcheck.sh` with the Bash tool.
%(build)s
3. With the Write tool, create the file `written.txt` in the current
   directory containing the single line `x`.
4. With the Write tool, create the file `%(tmpfile)s` containing `x`.
5. Run each of the following commands with the Bash tool, exactly as
   written (character for character), one Bash call per command:

%(forms)s

Then answer with the single word DONE."""


def kinds_needed(jobs):
    kinds = []
    for t, c, _ in jobs:
        from lib.conds import Cond
        k = Cond(c).lang
        if k not in kinds:
            kinds.append(k)
    return kinds


def _fingerprint(kinds, ctx, conds_needing):
    h = hashlib.sha256()
    h.update(json.dumps([kinds, sorted(claude_backend.ALLOW), claude_backend.ALLOW_PATTERNS,
                         conds_needing, ctx.get("versions"), sorted(ctx.get("ctasks") or {})],
                        sort_keys=True, default=str).encode())
    return h.hexdigest()[:16]


def script_for(kind, test=False):
    s = SCRIPT_HEAD.replace("probe python3", "probe mktemp-t sh -c 'f=$(mktemp -t evalsc) "
                            "&& rm \"$f\"'\nprobe python3")
    if kind == "tach":
        s += SCRIPT_TACH + (SCRIPT_TEST if test else "")
    elif kind == "rust":
        s += SCRIPT_RUST
    else:
        s += SCRIPT_COMPILER + (SCRIPT_COMPILER_TEST if test else "")
    return s + 'echo DONE >> "$out"\n'


def prepare(kind, ctx, root, test=False):
    """The kind's workspace under root, as a run makes it, with the probes.
    (ws, bin_dir, hooks for the session: (check_hook, query_hook))."""
    from lib import ctasks, runner
    from lib.common import load_tasks
    base = os.path.join(root, kind)
    if kind in ("tach", "rust"):
        dev = load_tasks(None, ["00-hello-sum"], "dev")[0]
        ws, bin_dir = runner.program_workspace(ctx, dev, kind, base)
        for f in os.listdir(ws):
            if f.endswith((".vl", ".rs")):
                os.remove(os.path.join(ws, f))
        with open(os.path.join(ws, "main.vl" if kind == "tach" else "main.rs"), "w") as fh:
            fh.write(TACH_PROBE if kind == "tach" else RUST_PROBE)
        hooks = ((ctx["hooks"]["check"], os.path.join(base, "check-hook.jsonl"))
                 if kind == "tach" else None, None)
    else:
        if not ctx.get("ctasks"):
            raise SystemExit("self-check: no compiler task in the round")
        tid, info = sorted(ctx["ctasks"].items())[0]
        task = load_tasks(None, [tid], "compiler")[0]
        if os.path.exists(base):
            shutil.rmtree(base)
        ws, bin_dir = os.path.join(base, "ws"), os.path.join(base, "bin")
        os.makedirs(bin_dir)
        install_mktemp_shim(bin_dir)
        ctasks.setup_workspace(task, "compiler-tools", info["sha"], ws, info["builder"],
                               info["starter"], base_env(bin_dir),
                               tools_volec=ctx.get("tools_volec"))
        hooks = ((ctx["hooks"]["check"], os.path.join(base, "check-hook.jsonl")),
                 ctx["hooks"]["query"])
    with open(os.path.join(ws, "in.txt"), "w") as fh:
        fh.write("1 2 3\n")
    os.makedirs(os.path.join(ws, "sub"), exist_ok=True)
    with open(os.path.join(ws, "sub", "keep.txt"), "w") as fh:
        fh.write("x\n")
    with open(os.path.join(ws, "selfcheck.sh"), "w") as fh:
        fh.write(script_for(kind, test))
    return ws, bin_dir, hooks


def parse_out(ws):
    path = os.path.join(ws, "selfcheck.out")
    probes, done = {}, False
    if os.path.exists(path):
        with open(path) as fh:
            for line in fh:
                line = line.rstrip("\n")
                if line == "DONE":
                    done = True
                elif line.startswith("ok "):
                    probes[line[3:]] = "ok"
                elif line.startswith("FAIL "):
                    name, _, why = line[5:].partition(":")
                    probes[name] = "FAIL:" + why.strip()
    return probes, done


def sandbox_profile(ws, tmp):
    """An approximation of Claude Code's sandbox for the offline check:
    writes only in the workspace, the given temp directory and /dev; the
    per-user temp directory, this repository and ~/.claude closed."""
    q = lambda p: '"%s"' % p.replace("\\", "\\\\").replace('"', '\\"')
    return "\n".join([
        "(version 1)",
        "(allow default)",
        "(deny network*)",
        "(allow network* (local unix-socket))",
        "(deny file-write*)",
        "(allow file-write* (subpath %s) (subpath %s) (literal \"/dev/null\")"
        " (literal \"/dev/tty\") (regex #\"^/dev/fd/\"))"
        % (q(os.path.realpath(ws)), q(os.path.realpath(tmp))),
        "(deny file-read* %s)" % " ".join("(subpath %s)" % q(p) for p in private_paths()),
    ])


def offline(kind, ws, bin_dir, root):
    tmp = os.path.join("/tmp", "claude-%d" % os.getuid(), "eval-selfcheck-%d" % os.getpid())
    os.makedirs(tmp, exist_ok=True)
    env = claude_backend.env(bin_dir)
    env["TMPDIR"] = tmp + "/"
    rc, out, err, secs = run_proc(["/usr/bin/sandbox-exec", "-p", sandbox_profile(ws, tmp),
                                   "/bin/sh", "selfcheck.sh"], ws, env, 900)
    shutil.rmtree(tmp, ignore_errors=True)
    probes, done = parse_out(ws)
    return {"probes": probes, "done": done, "secs": round(secs, 1),
            "stderr": (err or b"").decode("utf-8", "replace")[-400:] if rc else ""}


def hosted(kind, ws, bin_dir, hooks, model, rdir, ctx):
    tmpfile = "/tmp/claude-%d/eval-selfcheck-%d.txt" % (os.getuid(), os.getpid())
    forms = [(name, cmds.get(kind, cmds.get("*"))) for name, cmds in FORMS]
    forms = [(n, c) for n, c in forms if c]
    build = {"tach": "2. Run `volec main.vl -o prog`, then (a second Bash call) "
                     "`./prog < in.txt`.",
             "rust": "2. Run `rustc -O --edition 2021 main.rs -o prog`, then (a second Bash "
                     "call) `./prog < in.txt`.",
             "compiler": "2. Run `target/volec --version`, then (a second Bash call) "
                         "`tests/run.sh arith_i64_basic`."}[kind]
    prompt = PROMPT % {"build": build, "tmpfile": tmpfile,
                       "forms": "\n".join("```\n%s\n```" % c for _, c in forms)}
    os.makedirs(rdir, exist_ok=True)
    with open(os.path.join(rdir, "prompt.md"), "w") as fh:
        fh.write(prompt)
    check_hook, query_hook = hooks
    agent = claude_backend.run(prompt, ws, bin_dir, model, 900, rdir, check_hook=check_hook,
                               query_hook=query_hook, tee=ctx["hooks"]["tee"])
    probes, done = parse_out(ws)
    calls, _, _ = anatomy.load(rdir)
    by_cmd = {}
    for c in calls:
        cmd = (c["input"].get("command") or "").strip()
        if cmd:
            by_cmd.setdefault(cmd, c)
    def status(cmd):
        c = by_cmd.get(cmd.strip())
        if c is None:
            return "not run"
        return "denied" if c["denied"] else ("error" if c["is_error"] else "ran")
    steps = {}
    b = {"tach": ("volec main.vl -o prog", "./prog < in.txt"),
         "rust": ("rustc -O --edition 2021 main.rs -o prog", "./prog < in.txt"),
         "compiler": ("target/volec --version", "tests/run.sh arith_i64_basic")}[kind]
    steps["agent-build"] = status(b[0])
    steps["agent-run"] = status(b[1])
    steps["agent-selfcheck"] = status("sh selfcheck.sh")
    writes = [c for c in calls if c["tool"] == "Write"]
    w_ws = [c for c in writes if c["input"].get("file_path", "").endswith("written.txt")]
    w_tmp = [c for c in writes if c["input"].get("file_path", "") == tmpfile]
    steps["write-ws"] = ("denied" if w_ws and w_ws[0]["denied"] else
                         "ran" if w_ws and not w_ws[0]["is_error"] else
                         "error" if w_ws else "not run")
    steps["write-tmp"] = ("denied" if w_tmp and w_tmp[0]["denied"] else
                          "ran" if w_tmp and not w_tmp[0]["is_error"] else
                          "error" if w_tmp else "not run")
    refusals = {n: status(c) for n, c in forms}
    return {"probes": probes, "done": done, "steps": steps, "refusals": refusals,
            "cost_usd": agent.get("cost_usd"), "turns": agent.get("turns"),
            "permission_denials": agent.get("permission_denials"),
            "error": agent.get("error")}


def judge(kind, r, hosted_mode):
    failed = []
    if not r["done"]:
        failed.append("%s: selfcheck.sh did not finish%s" % (
            kind, " (" + r.get("stderr", "")[:160] + ")" if r.get("stderr") else ""))
    for name, st in sorted(r["probes"].items()):
        if st != "ok" and name not in OPTIONAL:
            failed.append("%s %s: %s" % (kind, name, st[5:][:200]))
    if hosted_mode:
        for step in ("agent-build", "agent-run", "agent-selfcheck", "write-ws"):
            st = r["steps"].get(step)
            # a build or run that ran and failed is a probe's business;
            # refused or never run is the sandbox's or the session's
            if st in ("denied", "not run"):
                failed.append("%s %s: %s" % (kind, step, st))
    return failed


def run_checks(ctx, kinds, mode, model, out_dir, test=False):
    root = os.path.join(ctx["ws_root"], "selfcheck")
    os.makedirs(root, exist_ok=True)
    report = {"time": time.strftime("%Y-%m-%dT%H:%M:%S"), "mode": mode, "kinds": {},
              "failed": [], "refusals": {}}
    for kind in kinds:
        ws, bin_dir, hooks = prepare(kind, ctx, root, test)
        r = offline(kind, ws, bin_dir, root)
        failed = judge(kind, r, False)
        entry = {"offline": r}
        if mode == "hosted" and not failed:
            ws, bin_dir, hooks = prepare(kind, ctx, root, test)
            h = hosted(kind, ws, bin_dir, hooks, model.split(":", 1)[-1],
                       os.path.join(out_dir, "selfcheck-" + kind), ctx)
            entry["hosted"] = h
            failed += judge(kind, h, True)
            report["refusals"][kind] = h["refusals"]
        report["kinds"][kind] = entry
        report["failed"] += failed
    report["ok"] = not report["failed"]
    return report


def before_round(ctx, jobs, args, mode):
    """The check `run.py run` does first; returns the report (ok, failed,
    refusals, path). Reuses OUT/selfcheck.json for 12 h when its
    fingerprint matches."""
    from lib.conds import Cond
    if mode == "auto":
        mode = "hosted" if ctx["backend"] == "claude" else "offline"
    kinds = kinds_needed(jobs)
    test = any(Cond(c).test for _, c, _ in jobs)
    fp = _fingerprint(kinds, ctx, [mode, test])
    path = os.path.join(ctx["out"], "selfcheck.json")
    if os.path.exists(path):
        try:
            with open(path) as fh:
                old = json.load(fh)
            if old.get("ok") and old.get("fingerprint") == fp and time.time() - old.get(
                    "epoch", 0) < 12 * 3600:
                old["path"] = path
                print("self-check: reused %s (%s)" % (path, old["time"]), flush=True)
                return old
        except (OSError, ValueError):
            pass
    print("self-check (%s): %s" % (mode, ", ".join(kinds)), flush=True)
    rep = run_checks(ctx, kinds, mode, getattr(args, "selfcheck_model", "claude:haiku"),
                     ctx["out"], test)
    rep.update({"fingerprint": fp, "epoch": time.time(), "path": path})
    write_json(path, rep)
    summary(rep)
    return rep


def summary(rep):
    for kind, e in rep["kinds"].items():
        for m in ("offline", "hosted"):
            r = e.get(m)
            if not r:
                continue
            bad = [n for n, st in r["probes"].items() if st != "ok"]
            print("self-check %s %s: %d probes, %s%s" % (
                kind, m, len(r["probes"]), "all ok" if not bad else "not ok: " + ", ".join(bad),
                "; steps " + ", ".join("%s %s" % kv for kv in sorted(r["steps"].items()))
                if r.get("steps") else ""), flush=True)
            if r.get("refusals"):
                ref = [n for n, st in r["refusals"].items() if st == "denied"]
                print("  forms refused: %s (of %d)" % (", ".join(ref) or "none",
                                                      len(r["refusals"])), flush=True)
    print("self-check: %s" % ("ok" if rep["ok"] else "FAILED: " + "; ".join(rep["failed"])),
          flush=True)


def main(args):
    """run.py selfcheck: the check alone, for the given kinds."""
    from lib import ctasks
    from lib.common import load_tasks
    from lib.grade import prepare_bins, tool_version
    from lib.runner import parse_model
    backend, _ = parse_model(args.model)
    out = os.path.abspath(args.out or os.path.join(
        DEFAULT_RESULTS_DIR, "selfcheck-" + time.strftime("%Y%m%d-%H%M%S")))
    os.makedirs(out, exist_ok=True)
    ws_root = os.path.realpath(args.ws_root or os.path.join(
        os.environ.get("TMPDIR", "/tmp"), "vole-eval", os.path.basename(out)))
    if ws_root.startswith(os.path.realpath(REPO_ROOT) + os.sep):
        raise SystemExit("workspaces must be outside the repository")
    os.makedirs(ws_root, exist_ok=True)
    bins = prepare_bins(ws_root, os.path.abspath(args.volec))
    ctx = {"backend": backend, "out": out, "ws_root": ws_root, "bins": bins,
           "hooks": install_hooks(ws_root), "tools_volec": None,
           "versions": {"tach": tool_version(bins["tach"], "tach"),
                        "rust": tool_version(bins["rust"], "rust")}, "ctasks": {}}
    kinds = [k for k in args.kinds.split(",") if k]
    if "compiler" in kinds:
        t = load_tasks(None, None, "compiler")[0]
        ref, sha = ctasks.resolve_base(t, args.base)
        builder = ctasks.builder_for(sha, args.builder)
        st = ctasks.built_tree(t, sha, builder, ws_root)
        ctx["ctasks"][t.id] = {"ref": ref, "sha": sha, "builder": builder, "starter": st}
    from lib.conds import parse_list
    test = any(c.test for c in parse_list(args.cond))
    mode = "offline" if args.offline or backend != "claude" else "hosted"
    rep = run_checks(ctx, kinds, mode, args.model, out, test)
    rep["path"] = os.path.join(out, "selfcheck.json")
    write_json(rep["path"], rep)
    summary(rep)
    return 0 if rep["ok"] else 1
