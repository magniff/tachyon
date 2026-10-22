#!/usr/bin/env python3
"""Cases for the check hook (check-after-edit.py): when it runs, which root
and compiler it picks, what it tells the agent, and the shared volec
recogniser (volec_cmd.py). A fake compiler stands in for volec; one
case runs target/volec when it has --json. Development tooling only.

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


# The recogniser: volec by name, copy, variable.
case("calls: plain", [c[0] for c in tc.calls("volec query show f; volec main.vl -o p")],
     ["query", "build"])
case("calls: variable and copy", [(c[0], c[2]) for c in tc.calls("T=target/tc0; $T edit patch f; target/tools/volec check")],
     [("edit", "target/tc0"), ("check", "target/tools/volec")])
case("calls: export, braces, quotes", [(c[0], c[2]) for c in tc.calls('export TC=./volec-old && "${TC}" fix --only imports')],
     [("fix", "./volec-old")])
case("calls: not volec", tc.calls("tclsh run.tcl; tcpdump -i en0; $EDITOR x; echo volec query"), [])
case("calls: unassigned variable", [c[0] for c in tc.calls("$T refactor rename a b")], ["refactor"])
case("calls: in a heredoc body, no", tc.calls("cat > x.sh <<'EOF'\nvolec query show f\nEOF"), [])
case("program_name", [tc.program_name(s, a) for a in [{}] for s in ("T=bin/tc1", "$T query x", "ls -l")],
     ["", "volec", "ls"])

# When it runs.
tmp = tempfile.mkdtemp()
try:
    prog = os.path.join(tmp, "prog")
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() {}\n")
    write(os.path.join(prog, "util.vl"), "pub fn f() {}\n")
    write(os.path.join(prog, "notes.md"))
    t = hook.trigger({"tool_name": "Write", "tool_input": {"file_path": os.path.join(prog, "util.vl")}})[:3]
    case("Write of a module: its main.vl", t, (os.path.join(prog, "util.vl"), os.path.join(prog, "main.vl"), None))
    case("Write of a doc: nothing", hook.trigger({"tool_name": "Write", "tool_input": {"file_path": os.path.join(prog, "notes.md")}}), None)
    case("Read: nothing", hook.trigger({"tool_name": "Read", "tool_input": {"file_path": os.path.join(prog, "main.vl")}}), None)

    def bash(command, stdout):
        t = hook.trigger({"tool_name": "Bash", "tool_input": {"command": command},
                          "tool_response": {"stdout": stdout, "stderr": ""}})
        return t[:3] if t else t
    case("edit that wrote", bash("volec edit patch f --old a --new b", "patched crate::f\tmain.vl\t+1 -1 lines\n"),
         (None, None, "volec"))
    case("edit through $T, with a root", bash("T=../tc0; $T refactor rename f g --root p/main.vl",
                                              "renamed crate::f\tmain.vl\t+1 -1 lines\n"), (None, "p/main.vl", "../tc0"))
    case("edit refused: nothing", bash("volec edit patch f --old a --new q", ""), None)
    case("dry run: nothing", bash("volec edit patch f --old a --new b --dry-run", "--- a/main.vl\n"), None)
    case("a query: nothing", bash("volec query show f", "fn f() {}\n"), None)
    case("stdin from a .vl file is not the root", bash("volec edit replace f < /tmp/x/new.vl",
                                                         "replaced crate::f\tmain.vl\t+1 -1 lines\n"), (None, None, "volec"))
    case("stdin without a space is not the root", bash("volec edit insert --after f <new.vl",
                                                        "inserted crate::g\tmain.vl\t+3 -0 lines\n"), (None, None, "volec"))
    case("a root before a redirect still counts", bash("volec fix --only imports t/main.vl > log.txt",
                                                       "fixed imports\tt/main.vl\t+1 -0 lines\n")[1], "t/main.vl")
    case("last .vl operand is the root", bash("volec fix --only imports t/main.vl", "fixed imports\tt/main.vl\t+1 -0 lines\n")[1],
         "t/main.vl")

    # The root.
    top = os.path.join(tmp, "repo")
    os.makedirs(os.path.join(top, ".git"))
    write(os.path.join(top, "compiler", "src", "main.vl"))
    write(os.path.join(top, "compiler", "src", "front", "x.vl"))
    write(os.path.join(top, "compiler", "std", "std.vl"))
    write(os.path.join(top, "compiler", "std", "iter.vl"))
    write(os.path.join(top, "tests", "run", "loop.vl"), "fn main() {\n}\n")
    write(os.path.join(top, "tests", "run", "frag.vl"), "fn helper() {}\n")
    write(os.path.join(top, "tests", "run", "multi", "main.vl"))
    write(os.path.join(top, "tests", "run", "multi", "a", "b.vl"))
    case("root: compiler source", hook.root_of(os.path.join(top, "compiler", "src", "front", "x.vl")),
         os.path.join(top, "compiler", "src", "main.vl"))
    case("root: std, through the compiler's root", hook.root_of(os.path.join(top, "compiler", "std", "iter.vl")),
         os.path.join(top, "compiler", "src", "main.vl"))
    case("root: a one-file program", hook.root_of(os.path.join(top, "tests", "run", "loop.vl")),
         os.path.join(top, "tests", "run", "loop.vl"))
    case("root: a fragment, none", hook.root_of(os.path.join(top, "tests", "run", "frag.vl")), None)
    case("root: two levels up", hook.root_of(os.path.join(top, "tests", "run", "multi", "a", "b.vl")),
         os.path.join(top, "tests", "run", "multi", "main.vl"))

    # The compiler: the tools binary first, then the build.
    os.makedirs(os.path.join(top, "target", "tools"))
    for rel in ("target/volec", "target/tools/volec"):
        write(os.path.join(top, rel), "#!/bin/sh\n")
        os.chmod(os.path.join(top, rel), 0o755)
    saved = os.environ.pop("VOLE_CHECK_COMPILER", None)
    case("compiler: target/tools first", hook.compiler_for(os.path.join(top, "compiler", "src")),
         os.path.join(top, "target", "tools", "volec"))
    case("compiler: the one the agent ran", hook.compiler_for(top, "target/volec"),
         os.path.join(top, "target", "volec"))
    # (0.17) A program's check: target/volec when newer (just rebuilt);
    # the compiler's own source: still the tools binary.
    t = time.time()
    os.utime(os.path.join(top, "target", "tools", "volec"), (t - 100, t - 100))
    os.utime(os.path.join(top, "target", "volec"), (t, t))
    case("compiler: a newer build for a test program",
         hook.compiler_for(os.path.join(top, "tests", "run"), None, os.path.join(top, "tests", "run", "loop.vl")),
         os.path.join(top, "target", "volec"))
    case("compiler: the tools binary for the compiler's source",
         hook.compiler_for(os.path.join(top, "compiler", "src"), None, os.path.join(top, "compiler", "src", "main.vl")),
         os.path.join(top, "target", "tools", "volec"))
    os.utime(os.path.join(top, "target", "volec"), (t - 200, t - 200))
    case("compiler: an older build is not taken",
         hook.compiler_for(os.path.join(top, "tests", "run"), None, os.path.join(top, "tests", "run", "loop.vl")),
         os.path.join(top, "target", "tools", "volec"))

    # The report: errors only, the edited file's first, at most 10.
    many = [diag("other.vl", i, f"e{i}") for i in range(1, 12)] + [diag("util.vl", 3, "mine", help=["did you mean 'g'?"])]
    text = hook.report(many, "main.vl", os.path.join(prog, "util.vl"))
    lines = text.split("\n")
    case("report: head", lines[0], "volec check main.vl: 12 errors")
    case("report: edited file first", lines[1], "util.vl:3:5: error[type error] mine | help: did you mean 'g'?")
    case("report: capped", (len(lines), lines[-1]), (12, "(2 more: volec check main.vl)"))
    case("report: clean is silent", hook.report([diag("a.vl", 1, "w", sev="warning")], "main.vl", None), "")
    # (0.17) One `fix` command for the errors it answers, after the head.
    u = [dict(diag("main.vl", i, "calling a C function is unsafe", code="unsafe"),
              **{"try": ["volec fix --only unsafe main.vl"]}) for i in (2, 5)]
    a = dict(diag("main.vl", 7, "allocation is explicit: pass an allocator (try: Vec::new_in(gpa))"),
             **{"try": ["volec fix --only alloc016 main.vl"]})
    lines = hook.report(u + [a, diag("main.vl", 9, "bad")], "main.vl", None).split("\n")
    case("report: fix commands after the head", lines[:3],
         ["volec check main.vl: 4 errors",
          "try: volec fix --only unsafe main.vl   (2 of the errors)",
          "try: volec fix --only alloc016 main.vl   (1 of the errors)"])
    case("report: one fix for all", hook.report(u, "main.vl", None).split("\n")[1],
         "try: volec fix --only unsafe main.vl   (all of them)")
    # (0.18) `fix --suggested` first, named once, never run by the hook
    sg = [dict(diag("main.vl", i, "undefined variable 'totl'"),
               **{"try": ["volec fix --suggested main.vl"]}) for i in (3, 8)]
    lines = hook.report(u + sg + [diag("main.vl", 9, "bad")], "main.vl", None).split("\n")
    case("report: fix --suggested first", lines[:3],
         ["volec check main.vl: 5 errors",
          "try: volec fix --suggested main.vl   (2 of the errors: their exact fixes, one checked edit)",
          "try: volec fix --only unsafe main.vl   (2 of the errors)"])
    case("report: fix --suggested not on its errors", lines[5],
         "main.vl:3:5: error[type error] undefined variable 'totl'")
    case("report: other try lines stay on their error", hook.fix_commands(
        [dict(diag("m.vl", 1, "x"), **{"try": ["use std::HashMap;", "target/tools/volec fix --only imports m.vl"]})]),
         [("target/tools/volec fix --only imports m.vl", 1)])
    case("typed name: under cwd", hook.typed_name(os.path.join(tmp, "bin", "volec"), tmp),
         os.path.join("bin", "volec"))
    case("short line parsed", hook.parse_short("m.vl:2:7: error[type error] bad | help: try x"),
         {"severity": "error", "code": "type error", "file": "m.vl", "line": 2, "col": 7, "message": "bad",
          "help": ["try x"], "notes": [], "try": []})


    # End to end, with a fake compiler printing check --json's lines.
    fake = os.path.join(tmp, "fake-volec")
    write(fake + ".out", json.dumps(diag("util.vl", 1, "undefined variable 'q'")) + "\n")
    write(fake, "#!/bin/sh\ncat '%s.out' >&2\nexit 1\n" % fake)
    os.chmod(fake, 0o755)
    old = os.path.join(tmp, "old-volec")
    write(old, "#!/bin/sh\nfor a; do [ \"$a\" = --json ] && { echo \"error check.usage: unknown option '--json'\" >&2; exit 2; }; done\n"
               "echo \"util.vl:1:5: error[type error] undefined variable 'q'\" >&2\nexit 1\n")
    os.chmod(old, 0o755)
    log = os.path.join(tmp, "hook.jsonl")

    def run(event, compiler, state=None):
        """The hook on event: (exit status, stdout); a state directory of
        its own unless one is given (no earlier check to compare with)."""
        env = dict(os.environ, VOLE_CHECK_COMPILER=compiler, VOLE_CHECK_HOOK_LOG=log,
                   VOLE_HOOK_STATE=state or tempfile.mkdtemp(dir=tmp))
        r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "check-after-edit.py")],
                           input=json.dumps(event), capture_output=True, text=True, env=env)
        return r.returncode, r.stdout
    ev = {"hook_event_name": "PostToolUse", "tool_name": "Edit", "cwd": prog,
          "tool_input": {"file_path": os.path.join(prog, "util.vl")}}
    st, out = run(ev, fake)
    ctx = json.loads(out)["hookSpecificOutput"]["additionalContext"] if out else ""
    case("end to end: context", (st, ctx),
         (0, "volec check main.vl: 1 error\nutil.vl:1:5: error[type error] undefined variable 'q'"))
    st, out2 = run(ev, old)
    case("end to end: a compiler without --json", json.loads(out2)["hookSpecificOutput"]["additionalContext"] if out2 else "", ctx)
    with open(log) as fh:
        recs = [json.loads(x) for x in fh]
    case("logged", [(r["kind"], r["errors"], r["codes"]) for r in recs],
         [("check-hook", 1, ["type error"])] * 2)
    st, out = run(dict(ev, hook_event_name="PreToolUse"), fake)
    case("PreToolUse: nothing", (st, out), (0, ""))
    env_off = dict(os.environ, VOLE_CHECK_HOOK="0", VOLE_CHECK_COMPILER=fake)
    r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "check-after-edit.py")], input=json.dumps(ev),
                       capture_output=True, text=True, env=env_off)
    case("VOLE_CHECK_HOOK=0: off", r.stdout, "")

    # (0.17) The directory a Bash call runs in follows its cds; a shell
    # command writing a .vl file is a change too.
    elsewhere = os.path.join(tmp, "elsewhere")
    os.makedirs(elsewhere)

    def bash_at(cwd, command, stdout=""):
        return hook.trigger({"tool_name": "Bash", "cwd": cwd, "tool_input": {"command": command},
                             "tool_response": {"stdout": stdout, "stderr": ""}})
    wrote = "patched crate::f\tmain.vl\t+1 -1 lines\n"
    case("cd then edit: the edit's directory", bash_at(elsewhere, f"cd {prog} && volec edit patch f --old a --new b", wrote),
         (None, None, "volec", prog))
    case("cd through a variable", bash_at(elsewhere, f"W={prog}; cd $W && target/volec edit delete f", wrote),
         (None, None, "target/volec", prog))
    case("cd relative, then a root", bash_at(tmp, "cd prog && volec fix --root main.vl", "fixed imports\tmain.vl\t+1 -0 lines\n"),
         (None, "main.vl", "volec", prog))
    case("cd to an unknown place: where it was", bash_at(elsewhere, "cd $X && volec edit delete f", wrote)[3], elsewhere)
    case("heredoc write of a .vl", bash_at(prog, "cat > util.vl <<'EOF'\npub fn f() {}\nEOF"),
         (os.path.join(prog, "util.vl"), os.path.join(prog, "main.vl"), None, prog))
    case("cp onto a .vl", bash_at(elsewhere, f"cd {prog}; cp /x/u.vl util.vl")[:2],
         (os.path.join(prog, "util.vl"), os.path.join(prog, "main.vl")))
    case("a .vl read is not a write", bash_at(prog, "cat util.vl > /dev/null"), None)

    # (0.17) The delta: what changed since this session's last check of the
    # root; the tests when the program has them; the hint.
    fdir = os.path.join(tmp, "fake2")
    os.makedirs(fdir)
    fake2 = os.path.join(fdir, "volec")
    write(fake2, "#!/bin/sh\nif [ \"$1\" = test ]; then cat '%s/test.out'; exit $(cat '%s/test.rc'); fi\n"
                 "cat '%s/check.out' >&2\n[ -s '%s/check.out' ] && exit 1\nexit 0\n" % (fdir, fdir, fdir, fdir))
    os.chmod(fake2, 0o755)

    def fake_says(check=(), test=None, rc=0):
        write(os.path.join(fdir, "check.out"), "".join(json.dumps(d) + "\n" for d in check))
        write(os.path.join(fdir, "test.out"), test or "")
        write(os.path.join(fdir, "test.rc"), str(rc))
    state = tempfile.mkdtemp(dir=tmp)
    ev = {"hook_event_name": "PostToolUse", "tool_name": "Edit", "cwd": prog, "session_id": "delta",
          "tool_input": {"file_path": os.path.join(prog, "main.vl")}}
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() {}\n")

    def ctx_of(out):
        return json.loads(out)["hookSpecificOutput"]["additionalContext"] if out else ""
    a = diag("main.vl", 3, "undefined variable 'q'")
    b = diag("main.vl", 7, "expected 'i64', got '[u8]'")
    fake_says([a])
    case("delta: the first check lists all", ctx_of(run(ev, fake2, state)[1]),
         "volec check main.vl: 1 error\nmain.vl:3:5: error[type error] undefined variable 'q'")
    fake_says([dict(a, line=4), b])
    case("delta: only the new one listed", ctx_of(run(ev, fake2, state)[1]),
         "volec check main.vl: 2 errors (1 new, 1 as before)\nmain.vl:7:5: error[type error] expected 'i64', got '[u8]'")
    fake_says([b])
    case("delta: one fixed", ctx_of(run(ev, fake2, state)[1]), "volec check main.vl: 1 error (1 fixed, 1 as before)")
    fake_says([])
    case("delta: clean again", ctx_of(run(ev, fake2, state)[1]), "volec check main.vl: 0 errors (1 fixed)")
    case("delta: clean and clean is silent", run(ev, fake2, state)[1], "")
    fake_says([b])
    got = ctx_of(run(ev, fake2, state)[1])
    case("hint: the same mistake twice", got.split("\n")[-1],
         hook.hs.hint("unfamiliar-construct", VOLEC=fake2))
    fake_says([])
    run(ev, fake2, state)
    fake_says([b])
    case("hint: once a session", "guide --find" in ctx_of(run(ev, fake2, state)[1]), False)
    # (E3) VOLE_HINTS=0: the same mistake twice, no hint
    off = dict(ev, session_id="delta-nohints")
    os.environ["VOLE_HINTS"] = "0"
    for says in ([b], [], [b]):
        fake_says(says)
        got = ctx_of(run(off, fake2, state)[1])
    del os.environ["VOLE_HINTS"]
    case("hint: off with VOLE_HINTS=0", (got.startswith("volec check main.vl: 1 error"),
                                             "guide --find" in got), (True, False))

    # (0.18.1) The exact fixes, applied: errors whose try: names `fix
    # --suggested` make the hook run it (a fake: `fix` writes fixed.out's
    # lines and a mark; check then prints after.out), check again, and say
    # what it fixed (each error with its help) before what is left.
    fdir3 = os.path.join(tmp, "fake3")
    os.makedirs(fdir3)
    fake3 = os.path.join(fdir3, "volec")
    write(fake3, "#!/bin/sh\nd='%s'\nif [ \"$1\" = fix ]; then echo \"$@\" >>\"$d/fix.calls\"; cat \"$d/fixed.out\"; "
                 "[ -s \"$d/fixed.out\" ] && : >\"$d/mark\"; exit 0; fi\n"
                 "if [ -f \"$d/mark\" ]; then cat \"$d/after.out\" >&2; [ -s \"$d/after.out\" ] && exit 1; exit 0; fi\n"
                 "cat \"$d/check.out\" >&2\n[ -s \"$d/check.out\" ] && exit 1\nexit 0\n" % fdir3)
    os.chmod(fake3, 0o755)
    sug = "volec fix --suggested main.vl"
    typo = dict(diag("main.vl", 2, "undefined variable 'prinln'", help=["did you mean 'println'?"]), **{"try": [sug]})
    nouse = dict(diag("main.vl", 3, "undefined variable 'is_digit'", help=["add `use std::is_digit;`"]), **{"try": [sug]})
    other = diag("main.vl", 4, "expected '[u8]', got 'i64'")

    def fake3_says(check, fixed, after):
        for f in ("mark", "fix.calls"):
            if os.path.exists(os.path.join(fdir3, f)):
                os.remove(os.path.join(fdir3, f))
        write(os.path.join(fdir3, "check.out"), "".join(json.dumps(d) + "\n" for d in check))
        write(os.path.join(fdir3, "fixed.out"), "".join(json.dumps({"kind": "output", "fields": f}) + "\n" for f in fixed))
        write(os.path.join(fdir3, "after.out"), "".join(json.dumps(d) + "\n" for d in after))

    def fix_calls():
        p = os.path.join(fdir3, "fix.calls")
        return open(p).read().split("\n")[0] if os.path.exists(p) else ""
    head = ("volec fix --suggested main.vl, run by the hook (volec undo takes it back; positions as before it; "
            "main.vl changed: read it again before an Edit):")
    fake3_says([typo, nouse, other], [["fixed 1 missing import, 1 suggested fix", "main.vl", "+3 -1 lines"]],
               [dict(other, line=6)])
    got = ctx_of(run(ev, fake3)[1])
    case("hook fix: applied, then what is left", (fix_calls(), got),
         ("fix --suggested --json main.vl",
          head + "\nfixed main.vl:2:5: undefined variable 'prinln' | did you mean 'println'?"
          "\nfixed main.vl:3:5: undefined variable 'is_digit' | add `use std::is_digit;`"
          "\nvolec check main.vl: 1 error\nmain.vl:6:5: error[type error] expected '[u8]', got 'i64'"))
    fake3_says([typo], [["fixed 1 suggested fix", "main.vl", "+1 -1 lines"]], [])
    case("hook fix: all fixed, clean", ctx_of(run(ev, fake3)[1]),
         head + "\nfixed main.vl:2:5: undefined variable 'prinln' | did you mean 'println'?\nvolec check main.vl: 0 errors")
    fake3_says([other], [["fixed 1 suggested fix", "main.vl", "+1 -1 lines"]], [])
    case("hook fix: not without an exact fix", (ctx_of(run(ev, fake3)[1]), fix_calls()),
         ("volec check main.vl: 1 error\nmain.vl:4:5: error[type error] expected '[u8]', got 'i64'", ""))
    fake3_says([typo], [], [])
    case("hook fix: refused or nothing done, named as before", ctx_of(run(ev, fake3)[1]),
         "volec check main.vl: 1 error\ntry: volec fix --suggested main.vl   (the error: their exact fixes, "
         "one checked edit)\nmain.vl:2:5: error[type error] undefined variable 'prinln' | help: did you mean 'println'?")
    fake3_says([typo], [["fixed 1 suggested fix", "main.vl", "+1 -1 lines"]], [])
    os.environ["VOLE_HOOK_FIX"] = "0"
    got = ctx_of(run(ev, fake3)[1])
    del os.environ["VOLE_HOOK_FIX"]
    case("hook fix: VOLE_HOOK_FIX=0 applies nothing", (fix_calls(), got.split("\n")[1]),
         ("", "try: volec fix --suggested main.vl   (the error: their exact fixes, one checked edit)"))
    # (0.19) A test case meant to fail (`// ERROR:` lines) is left as it
    # is: its fixes are named, not applied.
    write(os.path.join(prog, "main.vl"), "// ERROR: undefined variable 'prinln'\nfn main() {}\n")
    fake3_says([typo], [["fixed 1 suggested fix", "main.vl", "+1 -1 lines"]], [])
    got = ctx_of(run(ev, fake3)[1])
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() {}\n")
    case("hook fix: not in an ERROR test case", (fix_calls(), got.split("\n")[1]),
         ("", "try: volec fix --suggested main.vl   (the error: their exact fixes, one checked edit)"))
    with open(log) as fh:
        recs = [json.loads(x) for x in fh if x.strip()]
    case("hook fix: logged", [r.get("hook_fixed") for r in recs if "hook_fixed" in r][:2], [2, 1])

    # (0.17) A worktree's file edited from a session in the main checkout:
    # the worktree's root and compiler, check run in the worktree (check
    # reads compiler/std from the directory it runs in), its paths from
    # there, said with `(in DIR)`.
    main = os.path.join(tmp, "main")
    os.makedirs(os.path.join(main, ".git"))
    wt = os.path.join(main, ".claude", "worktrees", "w")
    for t in (main, wt):
        write(os.path.join(t, "compiler", "src", "main.vl"), "fn main() {}\n")
        write(os.path.join(t, "compiler", "std", "io.vl"), "pub fn f() {}\n")
    write(os.path.join(wt, ".git"), "gitdir: " + os.path.join(main, ".git", "worktrees", "w") + "\n")
    for t, who in ((main, "main"), (wt, "worktree")):
        c = os.path.join(t, "target", "tools", "volec")
        write(c, "#!/bin/sh\nprintf '{\"kind\":\"diagnostic\",\"severity\":\"error\",\"code\":\"type error\","
                 "\"file\":\"compiler/std/io.vl\",\"line\":1,\"col\":5,\"message\":\"%s compiler in %%s\","
                 "\"help\":[],\"notes\":[],\"try\":[]}\\n' \"$(pwd -P)\" >&2\nexit 1\n" % who)
        os.chmod(c, 0o755)
    saved_cc = os.environ.pop("VOLE_CHECK_COMPILER", None)
    for t, other, name in ((wt, main, "worktree edited from the main checkout"),
                           (main, wt, "main checkout edited from a worktree")):
        xev = {"hook_event_name": "PostToolUse", "tool_name": "Edit", "cwd": other, "session_id": "xtree",
              "tool_input": {"file_path": os.path.join(t, "compiler", "std", "io.vl")}}
        env = dict(os.environ, VOLE_CHECK_HOOK_LOG=log, VOLE_HOOK_STATE=tempfile.mkdtemp(dir=tmp))
        r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "check-after-edit.py")],
                           input=json.dumps(xev), capture_output=True, text=True, env=env)
        where = os.path.relpath(t, other) if t.startswith(other + os.sep) else t
        who = "worktree" if t == wt else "main"
        case(name, ctx_of(r.stdout),
             f"volec check compiler/src/main.vl (in {where}): 1 error\n"
             f"compiler/std/io.vl:1:5: error[type error] {who} compiler in {os.path.realpath(t)}")
    case("same checkout: runs in cwd", hook.run_dir_for(os.path.join(wt, "compiler", "src", "main.vl"),
                                                        os.path.join(wt, "compiler")), os.path.join(wt, "compiler"))
    if saved_cc is not None:
        os.environ["VOLE_CHECK_COMPILER"] = saved_cc

    # Tests: run after a clean check when tests/ has cases, the new
    # failures shown, not again within the debounce.
    write(os.path.join(prog, "tests", "a.in"), "1\n")
    write(os.path.join(prog, "tests", "a.out"), "1\n")
    state = tempfile.mkdtemp(dir=tmp)
    fake_says([], "test main.vl: 2 passed (tests/, 0.02 s)\n")
    case("tests: after a clean check", ctx_of(run(ev, fake2, state)[1]), "volec test main.vl: 2 passed")
    fail_b = ("test main.vl: 1 passed, 1 failed (tests/, 0.02 s)\nFAIL b: stdout differs at line 1 (1 line expected, "
              "1 printed)\n  - 2\n  + 3\n(outputs: /tmp/x/NAME.got, NAME.err)\n")
    fake_says([], fail_b, 1)
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() { }\n")
    case("tests: not again within the debounce", run(ev, fake2, state)[1], "")
    os.environ["VOLE_TEST_DEBOUNCE"] = "0"
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() {  }\n")
    case("tests: a new failure, its difference", ctx_of(run(ev, fake2, state)[1]),
         "volec test main.vl: 1 passed, 1 failed (1 newly failing)\nFAIL b: stdout differs at line 1 "
         "(1 line expected, 1 printed)\n  - 2\n  + 3")
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() {   }\n")
    case("tests: as before, one line", ctx_of(run(ev, fake2, state)[1]),
         "volec test main.vl: 1 passed, 1 failed (failing as before: b)")
    case("tests: sources unchanged, not rerun", run(ev, fake2, state)[1], "")
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() {    }\n")
    fake_says([], "test main.vl: 2 passed (tests/, 0.02 s)\n")
    case("tests: fixed", ctx_of(run(ev, fake2, state)[1]), "volec test main.vl: 2 passed (1 fixed: b)")
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() {     }\n")
    os.environ["VOLE_CHECK_TESTS"] = "0"
    case("tests: VOLE_CHECK_TESTS=0", run(ev, fake2, state)[1], "")
    del os.environ["VOLE_CHECK_TESTS"]
    del os.environ["VOLE_TEST_DEBOUNCE"]
    shutil.rmtree(os.path.join(prog, "tests"))

    # The real compiler, when it has --json (0.15): a clean program is
    # silent, an error is reported; and the latency on a cache hit.
    real = os.path.join(REPO, "target", "volec")
    probe = subprocess.run([real, "check", "--json", "/nonexistent.vl"], capture_output=True, text=True) \
        if os.access(real, os.X_OK) else None
    if probe is not None and "unknown option" not in probe.stderr:
        write(os.path.join(prog, "main.vl"), "fn main() {\n    let x: i64 = 1;\n    let y = x + 1;\n}\n")
        os.remove(os.path.join(prog, "util.vl"))
        ev2 = dict(ev, tool_input={"file_path": os.path.join(prog, "main.vl")})
        case("real: clean is silent", run(ev2, real), (0, ""))
        write(os.path.join(prog, "main.vl"), "fn main() {\n    let x: i64 = q;\n}\n")
        st, out = run(ev2, real)
        case("real: the error", json.loads(out)["hookSpecificOutput"]["additionalContext"] if out else "",
             "volec check main.vl: 1 error\nmain.vl:2:18: error[type error] undefined variable 'q'")
        # (0.18.1) the hook applies the exact fix: the file is changed
        write(os.path.join(prog, "main.vl"), "fn main() {\n    prinln(\"x\");\n    let y = 1 + \"a\";\n}\n")
        got = ctx_of(run(ev2, real)[1])
        with open(os.path.join(prog, "main.vl")) as fh:
            now = fh.read()
        case("real: the hook's exact fix", (got.split("\n")[1:], "println(\"x\")" in now),
             (["fixed main.vl:2:5: undefined variable 'prinln' | did you mean 'println'?",
               "volec check main.vl: 1 error",
               "main.vl:3:13: error[type error] expected '[u8]', got 'i64'"], True))
        write(os.path.join(prog, "main.vl"), "fn main() {\n    let x: i64 = q;\n}\n")
        ms = []
        for _ in range(5):
            t0 = time.time()
            run(ev2, real)
            ms.append((time.time() - t0) * 1000)
        print(f"note: the hook on a cache hit takes {sorted(ms)[2]:.0f} ms (median of 5, Python's start included)")
        # (0.17) With tests: the real `volec test` after a clean check.
        if "volec test" in subprocess.run([real, "test", "--help"], capture_output=True, text=True).stdout:
            write(os.path.join(prog, "main.vl"), "use std::println;\n\nfn main() {\n    println(\"1\");\n}\n")
            write(os.path.join(prog, "tests", "one.out"), "1\n")
            write(os.path.join(prog, "tests", "two.in"), "x\n")
            write(os.path.join(prog, "tests", "two.out"), "2\n")
            os.environ["VOLE_TEST_DEBOUNCE"] = "0"
            st, out = run(ev2, real)
            case("real: the tests' summary", json.loads(out)["hookSpecificOutput"]["additionalContext"] if out else "",
                 "volec test main.vl: 1 passed, 1 failed\nFAIL two: stdout differs at line 1 (1 line expected, "
                 "1 printed)\n  - 2\n  + 1")
            ms = []
            for k in range(5):
                write(os.path.join(prog, "main.vl"), "use std::println;\n\nfn main() {\n    println(\"1\");\n}\n" + "\n" * k)
                t0 = time.time()
                run(ev2, real)
                ms.append((time.time() - t0) * 1000)
            print(f"note: the hook with check, build and 2 tests takes {sorted(ms)[2]:.0f} ms (median of 5)")
            del os.environ["VOLE_TEST_DEBOUNCE"]
        else:
            print("skip real tests: target/volec has no test command")
    else:
        print("skip real: target/volec has no --json")
    if saved is not None:
        os.environ["VOLE_CHECK_COMPILER"] = saved
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("total", "ok" if FAILED == 0 else f"{FAILED} failed")
sys.exit(1 if FAILED else 0)
