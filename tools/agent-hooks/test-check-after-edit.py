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
    t = hook.trigger({"tool_name": "Write", "tool_input": {"file_path": os.path.join(prog, "util.tach")}})[:3]
    case("Write of a module: its main.tach", t, (os.path.join(prog, "util.tach"), os.path.join(prog, "main.tach"), None))
    case("Write of a doc: nothing", hook.trigger({"tool_name": "Write", "tool_input": {"file_path": os.path.join(prog, "notes.md")}}), None)
    case("Read: nothing", hook.trigger({"tool_name": "Read", "tool_input": {"file_path": os.path.join(prog, "main.tach")}}), None)

    def bash(command, stdout):
        t = hook.trigger({"tool_name": "Bash", "tool_input": {"command": command},
                          "tool_response": {"stdout": stdout, "stderr": ""}})
        return t[:3] if t else t
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
    case("root: std, through the compiler's root", hook.root_of(os.path.join(top, "compiler", "std", "iter.tach")),
         os.path.join(top, "compiler", "src", "main.tach"))
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
    # (0.17) One `fix` command for the errors it answers, after the head.
    u = [dict(diag("main.tach", i, "calling a C function is unsafe", code="unsafe"),
              **{"try": ["tachyonc fix --only unsafe main.tach"]}) for i in (2, 5)]
    a = dict(diag("main.tach", 7, "allocation is explicit: pass an allocator (try: Vec::new_in(gpa))"),
             **{"try": ["tachyonc fix --only alloc016 main.tach"]})
    lines = hook.report(u + [a, diag("main.tach", 9, "bad")], "main.tach", None).split("\n")
    case("report: fix commands after the head", lines[:3],
         ["tachyonc check main.tach: 4 errors",
          "try: tachyonc fix --only unsafe main.tach   (2 of the errors)",
          "try: tachyonc fix --only alloc016 main.tach   (1 of the errors)"])
    case("report: one fix for all", hook.report(u, "main.tach", None).split("\n")[1],
         "try: tachyonc fix --only unsafe main.tach   (all of them)")
    case("report: other try lines stay on their error", hook.fix_commands(
        [dict(diag("m.tach", 1, "x"), **{"try": ["use std::HashMap;", "target/tools/tachyonc fix --only imports m.tach"]})]),
         [("target/tools/tachyonc fix --only imports m.tach", 1)])
    case("typed name: under cwd", hook.typed_name(os.path.join(tmp, "bin", "tachyonc"), tmp),
         os.path.join("bin", "tachyonc"))
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

    def run(event, compiler, state=None):
        """The hook on event: (exit status, stdout); a state directory of
        its own unless one is given (no earlier check to compare with)."""
        env = dict(os.environ, TACHYON_CHECK_COMPILER=compiler, TACHYON_CHECK_HOOK_LOG=log,
                   TACHYON_HOOK_STATE=state or tempfile.mkdtemp(dir=tmp))
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

    # (0.17) The directory a Bash call runs in follows its cds; a shell
    # command writing a .tach file is a change too.
    elsewhere = os.path.join(tmp, "elsewhere")
    os.makedirs(elsewhere)

    def bash_at(cwd, command, stdout=""):
        return hook.trigger({"tool_name": "Bash", "cwd": cwd, "tool_input": {"command": command},
                             "tool_response": {"stdout": stdout, "stderr": ""}})
    wrote = "patched crate::f\tmain.tach\t+1 -1 lines\n"
    case("cd then edit: the edit's directory", bash_at(elsewhere, f"cd {prog} && tachyonc edit patch f --old a --new b", wrote),
         (None, None, "tachyonc", prog))
    case("cd through a variable", bash_at(elsewhere, f"W={prog}; cd $W && target/tachyonc edit delete f", wrote),
         (None, None, "target/tachyonc", prog))
    case("cd relative, then a root", bash_at(tmp, "cd prog && tachyonc fix --root main.tach", "fixed imports\tmain.tach\t+1 -0 lines\n"),
         (None, "main.tach", "tachyonc", prog))
    case("cd to an unknown place: where it was", bash_at(elsewhere, "cd $X && tachyonc edit delete f", wrote)[3], elsewhere)
    case("heredoc write of a .tach", bash_at(prog, "cat > util.tach <<'EOF'\npub fn f() {}\nEOF"),
         (os.path.join(prog, "util.tach"), os.path.join(prog, "main.tach"), None, prog))
    case("cp onto a .tach", bash_at(elsewhere, f"cd {prog}; cp /x/u.tach util.tach")[:2],
         (os.path.join(prog, "util.tach"), os.path.join(prog, "main.tach")))
    case("a .tach read is not a write", bash_at(prog, "cat util.tach > /dev/null"), None)

    # (0.17) The delta: what changed since this session's last check of the
    # root; the tests when the program has them; the hint.
    fdir = os.path.join(tmp, "fake2")
    os.makedirs(fdir)
    fake2 = os.path.join(fdir, "tachyonc")
    write(fake2, "#!/bin/sh\nif [ \"$1\" = test ]; then cat '%s/test.out'; exit $(cat '%s/test.rc'); fi\n"
                 "cat '%s/check.out' >&2\n[ -s '%s/check.out' ] && exit 1\nexit 0\n" % (fdir, fdir, fdir, fdir))
    os.chmod(fake2, 0o755)

    def fake_says(check=(), test=None, rc=0):
        write(os.path.join(fdir, "check.out"), "".join(json.dumps(d) + "\n" for d in check))
        write(os.path.join(fdir, "test.out"), test or "")
        write(os.path.join(fdir, "test.rc"), str(rc))
    state = tempfile.mkdtemp(dir=tmp)
    ev = {"hook_event_name": "PostToolUse", "tool_name": "Edit", "cwd": prog, "session_id": "delta",
          "tool_input": {"file_path": os.path.join(prog, "main.tach")}}
    write(os.path.join(prog, "main.tach"), "mod util;\nfn main() {}\n")

    def ctx_of(out):
        return json.loads(out)["hookSpecificOutput"]["additionalContext"] if out else ""
    a = diag("main.tach", 3, "undefined variable 'q'")
    b = diag("main.tach", 7, "expected 'i64', got '[u8]'")
    fake_says([a])
    case("delta: the first check lists all", ctx_of(run(ev, fake2, state)[1]),
         "tachyonc check main.tach: 1 error\nmain.tach:3:5: error[type error] undefined variable 'q'")
    fake_says([dict(a, line=4), b])
    case("delta: only the new one listed", ctx_of(run(ev, fake2, state)[1]),
         "tachyonc check main.tach: 2 errors (1 new, 1 as before)\nmain.tach:7:5: error[type error] expected 'i64', got '[u8]'")
    fake_says([b])
    case("delta: one fixed", ctx_of(run(ev, fake2, state)[1]), "tachyonc check main.tach: 1 error (1 fixed, 1 as before)")
    fake_says([])
    case("delta: clean again", ctx_of(run(ev, fake2, state)[1]), "tachyonc check main.tach: 0 errors (1 fixed)")
    case("delta: clean and clean is silent", run(ev, fake2, state)[1], "")
    fake_says([b])
    got = ctx_of(run(ev, fake2, state)[1])
    case("hint: the same mistake twice", got.split("\n")[-1],
         hook.hs.hint("unfamiliar-construct", TACHYONC=fake2))
    fake_says([])
    run(ev, fake2, state)
    fake_says([b])
    case("hint: once a session", "guide --find" in ctx_of(run(ev, fake2, state)[1]), False)
    # (E3) TACHYON_HINTS=0: the same mistake twice, no hint
    off = dict(ev, session_id="delta-nohints")
    os.environ["TACHYON_HINTS"] = "0"
    for says in ([b], [], [b]):
        fake_says(says)
        got = ctx_of(run(off, fake2, state)[1])
    del os.environ["TACHYON_HINTS"]
    case("hint: off with TACHYON_HINTS=0", (got.startswith("tachyonc check main.tach: 1 error"),
                                             "guide --find" in got), (True, False))

    # (0.17) A worktree's file edited from a session in the main checkout:
    # the worktree's root and compiler, check run in the worktree (check
    # reads compiler/std from the directory it runs in), its paths from
    # there, said with `(in DIR)`.
    main = os.path.join(tmp, "main")
    os.makedirs(os.path.join(main, ".git"))
    wt = os.path.join(main, ".claude", "worktrees", "w")
    for t in (main, wt):
        write(os.path.join(t, "compiler", "src", "main.tach"), "fn main() {}\n")
        write(os.path.join(t, "compiler", "std", "io.tach"), "pub fn f() {}\n")
    write(os.path.join(wt, ".git"), "gitdir: " + os.path.join(main, ".git", "worktrees", "w") + "\n")
    for t, who in ((main, "main"), (wt, "worktree")):
        c = os.path.join(t, "target", "tools", "tachyonc")
        write(c, "#!/bin/sh\nprintf '{\"kind\":\"diagnostic\",\"severity\":\"error\",\"code\":\"type error\","
                 "\"file\":\"compiler/std/io.tach\",\"line\":1,\"col\":5,\"message\":\"%s compiler in %%s\","
                 "\"help\":[],\"notes\":[],\"try\":[]}\\n' \"$(pwd -P)\" >&2\nexit 1\n" % who)
        os.chmod(c, 0o755)
    saved_cc = os.environ.pop("TACHYON_CHECK_COMPILER", None)
    for t, other, name in ((wt, main, "worktree edited from the main checkout"),
                           (main, wt, "main checkout edited from a worktree")):
        xev = {"hook_event_name": "PostToolUse", "tool_name": "Edit", "cwd": other, "session_id": "xtree",
              "tool_input": {"file_path": os.path.join(t, "compiler", "std", "io.tach")}}
        env = dict(os.environ, TACHYON_CHECK_HOOK_LOG=log, TACHYON_HOOK_STATE=tempfile.mkdtemp(dir=tmp))
        r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "check-after-edit.py")],
                           input=json.dumps(xev), capture_output=True, text=True, env=env)
        where = os.path.relpath(t, other) if t.startswith(other + os.sep) else t
        who = "worktree" if t == wt else "main"
        case(name, ctx_of(r.stdout),
             f"tachyonc check compiler/src/main.tach (in {where}): 1 error\n"
             f"compiler/std/io.tach:1:5: error[type error] {who} compiler in {os.path.realpath(t)}")
    case("same checkout: runs in cwd", hook.run_dir_for(os.path.join(wt, "compiler", "src", "main.tach"),
                                                        os.path.join(wt, "compiler")), os.path.join(wt, "compiler"))
    if saved_cc is not None:
        os.environ["TACHYON_CHECK_COMPILER"] = saved_cc

    # Tests: run after a clean check when tests/ has cases, the new
    # failures shown, not again within the debounce.
    write(os.path.join(prog, "tests", "a.in"), "1\n")
    write(os.path.join(prog, "tests", "a.out"), "1\n")
    state = tempfile.mkdtemp(dir=tmp)
    fake_says([], "test main.tach: 2 passed (tests/, 0.02 s)\n")
    case("tests: after a clean check", ctx_of(run(ev, fake2, state)[1]), "tachyonc test main.tach: 2 passed")
    fail_b = ("test main.tach: 1 passed, 1 failed (tests/, 0.02 s)\nFAIL b: stdout differs at line 1 (1 line expected, "
              "1 printed)\n  - 2\n  + 3\n(outputs: /tmp/x/NAME.got, NAME.err)\n")
    fake_says([], fail_b, 1)
    write(os.path.join(prog, "main.tach"), "mod util;\nfn main() { }\n")
    case("tests: not again within the debounce", run(ev, fake2, state)[1], "")
    os.environ["TACHYON_TEST_DEBOUNCE"] = "0"
    write(os.path.join(prog, "main.tach"), "mod util;\nfn main() {  }\n")
    case("tests: a new failure, its difference", ctx_of(run(ev, fake2, state)[1]),
         "tachyonc test main.tach: 1 passed, 1 failed (1 newly failing)\nFAIL b: stdout differs at line 1 "
         "(1 line expected, 1 printed)\n  - 2\n  + 3")
    write(os.path.join(prog, "main.tach"), "mod util;\nfn main() {   }\n")
    case("tests: as before, one line", ctx_of(run(ev, fake2, state)[1]),
         "tachyonc test main.tach: 1 passed, 1 failed (failing as before: b)")
    case("tests: sources unchanged, not rerun", run(ev, fake2, state)[1], "")
    write(os.path.join(prog, "main.tach"), "mod util;\nfn main() {    }\n")
    fake_says([], "test main.tach: 2 passed (tests/, 0.02 s)\n")
    case("tests: fixed", ctx_of(run(ev, fake2, state)[1]), "tachyonc test main.tach: 2 passed (1 fixed: b)")
    write(os.path.join(prog, "main.tach"), "mod util;\nfn main() {     }\n")
    os.environ["TACHYON_CHECK_TESTS"] = "0"
    case("tests: TACHYON_CHECK_TESTS=0", run(ev, fake2, state)[1], "")
    del os.environ["TACHYON_CHECK_TESTS"]
    del os.environ["TACHYON_TEST_DEBOUNCE"]
    shutil.rmtree(os.path.join(prog, "tests"))

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
        # (0.17) With tests: the real `tachyonc test` after a clean check.
        if "tachyonc test" in subprocess.run([real, "test", "--help"], capture_output=True, text=True).stdout:
            write(os.path.join(prog, "main.tach"), "use std::println;\n\nfn main() {\n    println(\"1\");\n}\n")
            write(os.path.join(prog, "tests", "one.out"), "1\n")
            write(os.path.join(prog, "tests", "two.in"), "x\n")
            write(os.path.join(prog, "tests", "two.out"), "2\n")
            os.environ["TACHYON_TEST_DEBOUNCE"] = "0"
            st, out = run(ev2, real)
            case("real: the tests' summary", json.loads(out)["hookSpecificOutput"]["additionalContext"] if out else "",
                 "tachyonc test main.tach: 1 passed, 1 failed\nFAIL two: stdout differs at line 1 (1 line expected, "
                 "1 printed)\n  - 2\n  + 1")
            ms = []
            for k in range(5):
                write(os.path.join(prog, "main.tach"), "use std::println;\n\nfn main() {\n    println(\"1\");\n}\n" + "\n" * k)
                t0 = time.time()
                run(ev2, real)
                ms.append((time.time() - t0) * 1000)
            print(f"note: the hook with check, build and 2 tests takes {sorted(ms)[2]:.0f} ms (median of 5)")
            del os.environ["TACHYON_TEST_DEBOUNCE"]
        else:
            print("skip real tests: target/tachyonc has no test command")
    else:
        print("skip real: target/tachyonc has no --json")
    if saved is not None:
        os.environ["TACHYON_CHECK_COMPILER"] = saved
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("total", "ok" if FAILED == 0 else f"{FAILED} failed")
sys.exit(1 if FAILED else 0)
