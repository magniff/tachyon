#!/usr/bin/env python3
"""Cases for the check hook (check-after-edit.py): when it runs, which root
and compiler it picks, what it tells the agent, and the shared tachyonc
recogniser (tachyonc_cmd.py). A fake compiler stands in for tachyonc; one
case runs target/tachyonc when it has --json. Development tooling only.

usage: python3 -I tools/agent-hooks/test-check-after-edit.py
"""
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import types

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))


def load(name, file):
    mod = types.ModuleType(name)
    mod.__file__ = os.path.join(HERE, file)
    with open(mod.__file__) as fh:
        exec(compile(fh.read(), mod.__file__, "exec"), mod.__dict__)
    return mod


hook = load("check_after_edit", "check-after-edit.py")
tc = hook.tc
FAILED = 0


def case(name, got, want):
    global FAILED
    if got == want:
        print(f"pass {name}")
    else:
        FAILED += 1
        print(f"FAIL {name}:\n    want {want!r}\n    got  {got!r}")


def write(path, text=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


def diag(file, line, msg, sev="error", code="type error", help=()):
    return {"kind": "diagnostic", "severity": sev, "code": code, "file": file, "line": line, "col": 5,
            "message": msg, "help": list(help), "notes": [], "try": []}


# The recogniser: tachyonc by name, copy, variable.
case("calls: plain", [c[0] for c in tc.calls("tachyonc query show f; tachyonc main.tach -o p")],
     ["query", "build"])
case("calls: variable and copy", [(c[0], c[2]) for c in tc.calls("T=target/tc0; $T edit patch f; target/tools/tachyonc check")],
     [("edit", "target/tc0"), ("check", "target/tools/tachyonc")])
case("calls: export, braces, quotes", [(c[0], c[2]) for c in tc.calls('export TC=./tachyonc-old && "${TC}" fix --only imports')],
     [("fix", "./tachyonc-old")])
case("calls: not tachyonc", tc.calls("tclsh run.tcl; tcpdump -i en0; $EDITOR x; echo tachyonc query"), [])
case("calls: unassigned variable", [c[0] for c in tc.calls("$T refactor rename a b")], ["refactor"])
case("calls: in a heredoc body, no", tc.calls("cat > x.sh <<'EOF'\ntachyonc query show f\nEOF"), [])
case("program_name", [tc.program_name(s, a) for a in [{}] for s in ("T=bin/tc1", "$T query x", "ls -l")],
     ["", "tachyonc", "ls"])

# When it runs.
tmp = tempfile.mkdtemp()
try:
    prog = os.path.join(tmp, "prog")
    write(os.path.join(prog, "main.tach"), "mod util;\nfn main() {}\n")
    write(os.path.join(prog, "util.tach"), "pub fn f() {}\n")
    write(os.path.join(prog, "notes.md"))
    t = hook.trigger({"tool_name": "Write", "tool_input": {"file_path": os.path.join(prog, "util.tach")}})
    case("Write of a module: its main.tach", t, (os.path.join(prog, "util.tach"), os.path.join(prog, "main.tach"), None))
    case("Write of a doc: nothing", hook.trigger({"tool_name": "Write", "tool_input": {"file_path": os.path.join(prog, "notes.md")}}), None)
    case("Read: nothing", hook.trigger({"tool_name": "Read", "tool_input": {"file_path": os.path.join(prog, "main.tach")}}), None)

    def bash(command, stdout):
        return hook.trigger({"tool_name": "Bash", "tool_input": {"command": command},
                             "tool_response": {"stdout": stdout, "stderr": ""}})
    case("edit that wrote", bash("tachyonc edit patch f --old a --new b", "patched crate::f\tmain.tach\t+1 -1 lines\n"),
         (None, None, "tachyonc"))
    case("edit through $T, with a root", bash("T=../tc0; $T refactor rename f g --root p/main.tach",
                                              "renamed crate::f\tmain.tach\t+1 -1 lines\n"), (None, "p/main.tach", "../tc0"))
    case("edit refused: nothing", bash("tachyonc edit patch f --old a --new q", ""), None)
    case("dry run: nothing", bash("tachyonc edit patch f --old a --new b --dry-run", "--- a/main.tach\n"), None)
    case("a query: nothing", bash("tachyonc query show f", "fn f() {}\n"), None)
    case("last .tach operand is the root", bash("tachyonc fix --only imports t/main.tach", "fixed imports\tt/main.tach\t+1 -0 lines\n")[1],
         "t/main.tach")

    # The root.
    top = os.path.join(tmp, "repo")
    os.makedirs(os.path.join(top, ".git"))
    write(os.path.join(top, "compiler", "src", "main.tach"))
    write(os.path.join(top, "compiler", "src", "front", "x.tach"))
    write(os.path.join(top, "compiler", "std", "std.tach"))
    write(os.path.join(top, "compiler", "std", "iter.tach"))
    write(os.path.join(top, "tests", "run", "loop.tach"), "fn main() {\n}\n")
    write(os.path.join(top, "tests", "run", "frag.tach"), "fn helper() {}\n")
    write(os.path.join(top, "tests", "run", "multi", "main.tach"))
    write(os.path.join(top, "tests", "run", "multi", "a", "b.tach"))
    case("root: compiler source", hook.root_of(os.path.join(top, "compiler", "src", "front", "x.tach")),
         os.path.join(top, "compiler", "src", "main.tach"))
    case("root: std", hook.root_of(os.path.join(top, "compiler", "std", "iter.tach")),
         os.path.join(top, "compiler", "std", "std.tach"))
    case("root: a one-file program", hook.root_of(os.path.join(top, "tests", "run", "loop.tach")),
         os.path.join(top, "tests", "run", "loop.tach"))
    case("root: a fragment, none", hook.root_of(os.path.join(top, "tests", "run", "frag.tach")), None)
    case("root: two levels up", hook.root_of(os.path.join(top, "tests", "run", "multi", "a", "b.tach")),
         os.path.join(top, "tests", "run", "multi", "main.tach"))

    # The compiler: the tools binary first, then the build.
    os.makedirs(os.path.join(top, "target", "tools"))
    for rel in ("target/tachyonc", "target/tools/tachyonc"):
        write(os.path.join(top, rel), "#!/bin/sh\n")
        os.chmod(os.path.join(top, rel), 0o755)
    saved = os.environ.pop("TACHYON_CHECK_COMPILER", None)
    case("compiler: target/tools first", hook.compiler_for(os.path.join(top, "compiler", "src")),
         os.path.join(top, "target", "tools", "tachyonc"))
    case("compiler: the one the agent ran", hook.compiler_for(top, "target/tachyonc"),
         os.path.join(top, "target", "tachyonc"))

    # The report: errors only, the edited file's first, at most 10.
    many = [diag("other.tach", i, f"e{i}") for i in range(1, 12)] + [diag("util.tach", 3, "mine", help=["did you mean 'g'?"])]
    text = hook.report(many, "main.tach", os.path.join(prog, "util.tach"))
    lines = text.split("\n")
    case("report: head", lines[0], "tachyonc check main.tach: 12 errors")
    case("report: edited file first", lines[1], "util.tach:3:5: error[type error] mine | help: did you mean 'g'?")
    case("report: capped", (len(lines), lines[-1]), (12, "(2 more: tachyonc check main.tach)"))
    case("report: clean is silent", hook.report([diag("a.tach", 1, "w", sev="warning")], "main.tach", None), "")
    case("short line parsed", hook.parse_short("m.tach:2:7: error[type error] bad | help: try x"),
         {"severity": "error", "code": "type error", "file": "m.tach", "line": 2, "col": 7, "message": "bad",
          "help": ["try x"], "notes": [], "try": []})

    # End to end, with a fake compiler printing check --json's lines.
    fake = os.path.join(tmp, "fake-tachyonc")
    write(fake + ".out", json.dumps(diag("util.tach", 1, "undefined variable 'q'")) + "\n")
    write(fake, "#!/bin/sh\ncat '%s.out' >&2\nexit 1\n" % fake)
    os.chmod(fake, 0o755)
    old = os.path.join(tmp, "old-tachyonc")
    write(old, "#!/bin/sh\nfor a; do [ \"$a\" = --json ] && { echo \"error check.usage: unknown option '--json'\" >&2; exit 2; }; done\n"
               "echo \"util.tach:1:5: error[type error] undefined variable 'q'\" >&2\nexit 1\n")
    os.chmod(old, 0o755)
    log = os.path.join(tmp, "hook.jsonl")

    def run(event, compiler):
        env = dict(os.environ, TACHYON_CHECK_COMPILER=compiler, TACHYON_CHECK_HOOK_LOG=log)
        r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "check-after-edit.py")],
                           input=json.dumps(event), capture_output=True, text=True, env=env)
        return r.returncode, r.stdout
    ev = {"hook_event_name": "PostToolUse", "tool_name": "Edit", "cwd": prog,
          "tool_input": {"file_path": os.path.join(prog, "util.tach")}}
    st, out = run(ev, fake)
    ctx = json.loads(out)["hookSpecificOutput"]["additionalContext"] if out else ""
    case("end to end: context", (st, ctx),
         (0, "tachyonc check main.tach: 1 error\nutil.tach:1:5: error[type error] undefined variable 'q'"))
    st, out2 = run(ev, old)
    case("end to end: a compiler without --json", json.loads(out2)["hookSpecificOutput"]["additionalContext"] if out2 else "", ctx)
    with open(log) as fh:
        recs = [json.loads(x) for x in fh]
    case("logged", [(r["kind"], r["errors"], r["codes"]) for r in recs],
         [("check-hook", 1, ["type error"])] * 2)
    st, out = run(dict(ev, hook_event_name="PreToolUse"), fake)
    case("PreToolUse: nothing", (st, out), (0, ""))
    env_off = dict(os.environ, TACHYON_CHECK_HOOK="0", TACHYON_CHECK_COMPILER=fake)
    r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "check-after-edit.py")], input=json.dumps(ev),
                       capture_output=True, text=True, env=env_off)
    case("TACHYON_CHECK_HOOK=0: off", r.stdout, "")

    # The real compiler, when it has --json (0.15): a clean program is
    # silent, an error is reported; and the latency on a cache hit.
    real = os.path.join(REPO, "target", "tachyonc")
    probe = subprocess.run([real, "check", "--json", "/nonexistent.tach"], capture_output=True, text=True) \
        if os.access(real, os.X_OK) else None
    if probe is not None and "unknown option" not in probe.stderr:
        write(os.path.join(prog, "main.tach"), "fn main() {\n    let x: i64 = 1;\n    let y = x + 1;\n}\n")
        os.remove(os.path.join(prog, "util.tach"))
        ev2 = dict(ev, tool_input={"file_path": os.path.join(prog, "main.tach")})
        case("real: clean is silent", run(ev2, real), (0, ""))
        write(os.path.join(prog, "main.tach"), "fn main() {\n    let x: i64 = q;\n}\n")
        st, out = run(ev2, real)
        case("real: the error", json.loads(out)["hookSpecificOutput"]["additionalContext"] if out else "",
             "tachyonc check main.tach: 1 error\nmain.tach:2:18: error[type error] undefined variable 'q'")
        ms = []
        for _ in range(5):
            t0 = time.time()
            run(ev2, real)
            ms.append((time.time() - t0) * 1000)
        print(f"note: the hook on a cache hit takes {sorted(ms)[2]:.0f} ms (median of 5, Python's start included)")
    else:
        print("skip real: target/tachyonc has no --json")
    if saved is not None:
        os.environ["TACHYON_CHECK_COMPILER"] = saved
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("total", "ok" if FAILED == 0 else f"{FAILED} failed")
sys.exit(1 if FAILED else 0)
