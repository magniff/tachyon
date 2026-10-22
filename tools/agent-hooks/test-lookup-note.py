#!/usr/bin/env python3
"""Cases for the repeat-lookup note (lookup-note.py, PostToolUse on Bash):
when it notes a repeated lookup, once per call, and what it leaves alone.
The hook runs as Claude Code runs it (a process, the event on stdin).
Development tooling only.

usage: python3 -I tools/agent-hooks/test-lookup-note.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HOOK = os.path.join(HERE, "lookup-note.py")
FAILED = 0


def case(name, got, want):
    global FAILED
    if got == want:
        print(f"pass {name}")
    else:
        FAILED += 1
        print(f"FAIL {name}:\n    want {want!r}\n    got  {got!r}")


STATE = tempfile.mkdtemp()


def call(command, stdout, session="s1", env=None):
    """The note the hook adds after a Bash call, or ""."""
    event = {"hook_event_name": "PostToolUse", "tool_name": "Bash", "session_id": session,
             "cwd": STATE, "tool_input": {"command": command},
             "tool_response": {"stdout": stdout, "stderr": ""}}
    e = dict(os.environ, VOLE_HOOK_STATE=STATE, **(env or {}))
    p = subprocess.run([sys.executable, "-I", HOOK], input=json.dumps(event),
                       capture_output=True, text=True, env=e)
    if p.returncode != 0 or p.stderr:
        return "status %d: %s" % (p.returncode, p.stderr)
    if not p.stdout:
        return ""
    o = json.loads(p.stdout)["hookSpecificOutput"]
    return o["hookEventName"] + ": " + o["additionalContext"]


try:
    STD = "## std\nVec::push ...\n"
    case("first guide std: nothing", call("volec guide std", STD), "")
    case("another command: nothing", call("ls", "a\nb\n"), "")
    case("the same lookup, the same text: the note",
         call("volec guide std", STD),
         "PostToolUse: note: `volec guide std` printed the same text at shell call 1 of this session")
    case("never twice for one call", call("volec guide std", STD), "")
    case("through a copy of the compiler: the same call, noted once already",
         call("target/tools/volec guide std", STD), "")
    case("a section: its own call", call("volec guide std#Vec", "Vec\n"), "")
    case("a section again", call("volec guide std#Vec", "Vec\n"),
         "PostToolUse: note: `volec guide std#Vec` printed the same text at shell call 6 of this session")
    case("a query whose answer changed: nothing",
         (call("volec query show f", "fn f() {}\n"), call("volec query show f", "fn f() { g() }\n")),
         ("", ""))
    case("the changed answer again: the note names its call",
         call("volec query show f", "fn f() { g() }\n"),
         "PostToolUse: note: `volec query show f` printed the same text at shell call 9 of this session")
    case("explain, --help", (call("volec explain E0101", "x\n"), call("volec explain E0101", "x\n"),
                             call("volec edit patch --help", "usage\n"),
                             call("volec edit patch --help", "usage\n")[-32:]),
         ("", "PostToolUse: note: `volec explain E0101` printed the same text at shell call 11 of this session",
          "", "at shell call 13 of this session"))
    case("an edit is no lookup", (call("volec edit patch f --old a --new b", "patched\n"),
                                  call("volec edit patch f --old a --new b", "patched\n")), ("", ""))
    case("two calls on a line: not one lookup",
         (call("volec guide std; volec guide unsafe", "x\n"),
          call("volec guide std; volec guide unsafe", "x\n")), ("", ""))
    case("an empty answer (an error): nothing",
         (call("volec guide nope", ""), call("volec guide nope", "")), ("", ""))
    case("another session: its own", call("volec guide std", STD, session="s2"), "")
    case("VOLE_LOOKUP_NOTE=0: off",
         call("volec guide std", STD, session="s2", env={"VOLE_LOOKUP_NOTE": "0"}), "")
    case("deterministic: no time or id in the text",
         call("volec guide std", STD, session="s2"),
         "PostToolUse: note: `volec guide std` printed the same text at shell call 1 of this session")
finally:
    shutil.rmtree(STATE, ignore_errors=True)

print("total", "ok" if FAILED == 0 else f"{FAILED} failed")
sys.exit(1 if FAILED else 0)
