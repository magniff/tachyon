#!/usr/bin/env python3
"""Agent harness hook (0.17, experiment E5 of the delivery research): a
note when a lookup prints again what it printed earlier in the session.

Registered for PostToolUse on Bash (tools/agent-hooks/settings-eval.json,
condition `note`). A lookup is one tachyonc call per command line of
`guide`, `query`, `explain` or `--help` (through any copy: target/tachyonc,
target/tools/tachyonc, a shell variable; tachyonc_cmd.py). When the same
call (its words after the program) prints the same text (its stdout's
hash) as an earlier one in the session, the call's result gets one line:

    note: `tachyonc guide std` printed the same text at shell call 4 of this session

once per call and session, never again. The call itself is not blocked:
an older tool result may have been cleared from the context, and then
the repeat is how the agent gets it back; the note only says it was
there (a nudge or a context-size problem: the eval tells which). A query
whose answer changed (an edit between) gets no note. Text: hints.txt,
`repeat-lookup`. TACHYON_LOOKUP_NOTE=0 turns it off. State: hookstate.py,
its own part (`lookup`) of the session's state. Development tooling only.
"""
import json
import os
import sys
import types
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
LOOKUPS = ("guide", "query", "explain")
SHOWN = 100


def _load(name, file):
    mod = types.ModuleType(name)
    mod.__file__ = os.path.join(HERE, file)
    with open(mod.__file__) as fh:
        exec(compile(fh.read(), mod.__file__, "exec"), mod.__dict__)
    return mod


def lookup_of(command, tc):
    """(key, what) of a command line that is one lookup, else None: key
    the call's words after the program, what the call as typed (short)."""
    calls = tc.calls(command)
    if len(calls) != 1:
        return None
    sub, words, _, seg = calls[0]
    if sub not in LOOKUPS and "--help" not in words and "-h" not in words:
        return None
    seg = seg.strip()
    what = seg if len(seg) <= SHOWN else seg[:SHOWN - 3] + "..."
    return " ".join(words), what


def note_for(event, st, command, out, tc, hs):
    """The note for this call, or ""; st is updated (the call counted,
    the lookup recorded)."""
    st["n"] = st.get("n", 0) + 1
    got = lookup_of(command, tc)
    if not got or not out.strip():
        return ""
    key, what = got
    h = "%08x-%d" % (zlib.crc32(out.encode("utf-8", "replace")), len(out))
    seen = st.setdefault("seen", {})
    noted = st.setdefault("noted", [])
    prev = seen.get(key)
    if prev and prev.get("h") == h:
        if key in noted:
            return ""
        noted.append(key)
        return hs.text("repeat-lookup", WHAT=what, N=prev.get("n"))
    seen[key] = {"n": st["n"], "h": h}
    if len(seen) > 300:  # (the oldest go first)
        for k in sorted(seen, key=lambda k: seen[k].get("n", 0))[:len(seen) - 300]:
            del seen[k]
    return ""


def main():
    if os.environ.get("TACHYON_LOOKUP_NOTE") == "0":
        return 0
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    if event.get("hook_event_name") != "PostToolUse" or event.get("tool_name") != "Bash":
        return 0
    command = (event.get("tool_input") or {}).get("command") or ""
    resp = event.get("tool_response") or {}
    out = (resp.get("stdout") or "") if isinstance(resp, dict) else str(resp)
    tc = _load("tachyonc_cmd", "tachyonc_cmd.py")
    hs = _load("hookstate", "hookstate.py")
    st = hs.load(event, "lookup")
    note = note_for(event, st, command, out, tc, hs)
    hs.save(event, st, "lookup")
    if note:
        json.dump({"hookSpecificOutput": {"hookEventName": "PostToolUse",
                                          "additionalContext": note}}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
