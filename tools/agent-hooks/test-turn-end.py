#!/usr/bin/env python3
"""Cases for the turn-end hook (turn-end.py, a Stop hook): when it checks,
what it tells the agent (a blocked stop, once per state of the sources),
and its latency. A fake compiler stands in for tachyonc. Development
tooling only.

usage: python3 -I tools/agent-hooks/test-turn-end.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
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


tmp = os.path.realpath(tempfile.mkdtemp())
try:
    prog = os.path.join(tmp, "ws")
    write(os.path.join(prog, "main.tach"), "fn main() {}\n")
    old = time.time() - 3600
    os.utime(os.path.join(prog, "main.tach"), (old, old))
    transcript = os.path.join(tmp, "t.jsonl")
    write(transcript, json.dumps({"type": "user", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z",
                                                                            time.gmtime(time.time() - 60))}) + "\n")
    fdir = os.path.join(tmp, "fake")
    fake = os.path.join(fdir, "tachyonc")
    write(fake, "#!/bin/sh\nif [ \"$1\" = test ]; then cat '%s/test.out'; exit 0; fi\n"
                "cat '%s/check.out' >&2\n[ -s '%s/check.out' ] && exit 1\nexit 0\n" % (fdir, fdir, fdir))
    os.chmod(fake, 0o755)

    def fake_says(check=(), test=""):
        write(os.path.join(fdir, "check.out"), "".join(json.dumps(d) + "\n" for d in check))
        write(os.path.join(fdir, "test.out"), test)
    err = {"kind": "diagnostic", "severity": "error", "code": "type error", "file": "main.tach", "line": 2,
           "col": 5, "message": "undefined variable 'q'", "help": [], "notes": [], "try": []}
    state = os.path.join(tmp, "state")
    log = os.path.join(tmp, "hook.jsonl")

    def hook(script, event, **env):
        e = dict(os.environ, TACHYON_CHECK_COMPILER=fake, TACHYON_HOOK_STATE=state, TACHYON_CHECK_HOOK_LOG=log,
                 **env)
        t0 = time.time()
        r = subprocess.run([sys.executable, "-I", os.path.join(HERE, script)], input=json.dumps(event),
                           capture_output=True, text=True, env=e)
        return r.returncode, r.stdout, (time.time() - t0) * 1000

    stop = {"hook_event_name": "Stop", "session_id": "te", "cwd": prog, "transcript_path": transcript,
            "stop_hook_active": False}

    def reason(out):
        return json.loads(out).get("reason") if out else None
    fake_says([err])
    st, out, _ = hook("turn-end.py", stop)
    case("nothing changed this session: silent", (st, out), (0, ""))
    write(os.path.join(prog, "main.tach"), "fn main() {\n    let x = q;\n}\n")
    st, out, ms = hook("turn-end.py", stop)
    case("written by the shell, never checked: blocked once", (st, json.loads(out).get("decision") if out else None),
         (0, "block"))
    case("the reason", reason(out),
         "turn-end: unchecked changes in main.tach: 1 error\ntachyonc check main.tach: 1 error\n"
         "main.tach:2:5: error[type error] undefined variable 'q'")
    case("the same state: not twice", hook("turn-end.py", dict(stop, stop_hook_active=True))[1], "")
    print(f"note: the turn-end hook with a check takes {ms:.0f} ms (a fake compiler)")

    # The check hook saw a clean check: nothing at turn end.
    edit = {"hook_event_name": "PostToolUse", "tool_name": "Edit", "session_id": "te", "cwd": prog,
            "tool_input": {"file_path": os.path.join(prog, "main.tach")}}
    write(os.path.join(prog, "main.tach"), "fn main() {\n}\n")
    fake_says([])
    hook("check-after-edit.py", edit)
    st, out, ms = hook("turn-end.py", stop)
    case("checked clean after the last change: silent", out, "")
    print(f"note: the turn-end hook with nothing to do takes {ms:.0f} ms")

    # An edit the check hook reported errors on, left so: one reminder.
    write(os.path.join(prog, "main.tach"), "fn main() {\n    let x = q;\n}\n")
    fake_says([err])
    hook("check-after-edit.py", edit)
    case("errors left after an edit: one reminder", (reason(hook("turn-end.py", stop)[1]) or "").split("\n")[0],
         "turn-end: unchecked changes in main.tach: 1 error")
    case("and not twice", hook("turn-end.py", stop)[1], "")

    # Tests: the turn end runs them when the check hook's debounce left
    # the last sources untested; failing ones block once.
    write(os.path.join(prog, "tests", "a.in"), "")
    write(os.path.join(prog, "tests", "a.out"), "1\n")
    write(os.path.join(prog, "main.tach"), "fn main() {\n}\n")
    fake_says([], "test main.tach: 0 passed, 1 failed (tests/, 0.01 s)\nFAIL a: stdout differs at line 1 "
                  "(1 line expected, 0 printed)\n  - 1\n  + (end of output)\n")
    st, out, _ = hook("turn-end.py", stop)
    case("failing tests at turn end", (reason(out) or "").split("\n"),
         ["turn-end: unchecked changes in main.tach: 1 failing test",
          "tachyonc test main.tach: 0 passed, 1 failed", "FAIL a: stdout differs at line 1 (1 line expected, 0 printed)",
          "  - 1", "  + (end of output)"])
    case("failing tests: once", hook("turn-end.py", stop)[1], "")
    write(os.path.join(prog, "main.tach"), "fn main() {\n\n}\n")
    case("TACHYON_CHECK_TESTS=0: check only, clean", hook("turn-end.py", stop, TACHYON_CHECK_TESTS="0")[1], "")
    write(os.path.join(prog, "main.tach"), "fn main() {\n\n\n}\n")
    case("TACHYON_TURN_END=0: off", hook("turn-end.py", stop, TACHYON_TURN_END="0")[1], "")
    with open(log) as fh:
        kinds = [json.loads(x)["kind"] for x in fh]
    case("logged", kinds.count("turn-end") >= 4, True)

    # A root the session touched elsewhere (a worktree, through `cd`) is
    # checked too, though the event's directory is another.
    other = os.path.join(tmp, "elsewhere")
    os.makedirs(other)
    write(os.path.join(prog, "main.tach"), "fn main() {\n    let x = q;\n}\n")
    fake_says([err])
    hook("check-after-edit.py", {"hook_event_name": "PostToolUse", "tool_name": "Bash", "session_id": "te",
                                 "cwd": other, "tool_input": {"command": f"cd {prog} && tachyonc edit delete f"},
                                 "tool_response": {"stdout": "deleted crate::f\tmain.tach\t-1 lines\n"}})
    out = hook("turn-end.py", dict(stop, cwd=other))[1]
    case("a root touched through cd", (reason(out) or "").split("\n")[0].endswith("main.tach: 1 error"), True)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("total", "ok" if FAILED == 0 else f"{FAILED} failed")
sys.exit(1 if FAILED else 0)
