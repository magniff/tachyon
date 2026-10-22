#!/usr/bin/env python3
"""Agent harness hook (0.17): a check at the end of the agent's turn (a
Claude Code Stop hook), so that a turn does not end on vole source
nobody checked: a file written by a shell command (`cat > main.vl`, a
Python script), or an edit after which errors were left
(docs/research/applying-to-vole.md, item 4: checks once at turn exit).

Registered in .claude/settings.json for Stop, and by the agent eval
(tools/agent-hooks/settings-eval.json). Reads the hook event (JSON) on
stdin. For each program root this session touched (the check hook's
state, hookstate.py) and the one of the event's directory (its
compiler/src/main.vl, else its main.vl):

- nothing when its sources (fingerprint: the .vl files and tests'
  names, sizes and times) are as they were at the last check in this
  session and that check was clean (and its tests, when it has fast ones,
  ran on those sources); nothing when a root never checked has no .vl
  file changed since the session began;
- else `volec check` once (and its fast tests, check-after-edit.py's
  verify), and when there are errors or failing tests the stop is blocked
  once with them as the reason (`{"decision": "block", "reason": ...}`):
  the agent sees `turn-end: unchecked changes in main.vl: 2 errors`
  and the errors; never twice for the same sources (the state records
  the fingerprint it reported on).

VOLE_TURN_END=0 turns it off; VOLE_CHECK_TESTS=0 leaves the tests
out. Logged as `turn-end` records where the check hook logs. Development
tooling only.
"""
import json
import os
import sys
import time
import types

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, file):
    mod = types.ModuleType(name)
    mod.__file__ = os.path.join(HERE, file)
    with open(mod.__file__) as fh:
        exec(compile(fh.read(), mod.__file__, "exec"), mod.__dict__)
    return mod


cae = _load("check_after_edit", "check-after-edit.py")


def candidates(event, st):
    """The roots to look at: the session's, then the event directory's."""
    roots = []
    for key, entry in (st.get("roots") or {}).items():
        r = entry.get("root")
        if r and os.path.exists(r) and r not in roots:
            roots.append(r)
    cwd = os.path.abspath(event.get("cwd") or os.getcwd())
    r = cae.default_root(cwd)
    if r and r not in roots:
        roots.append(r)
    return roots


def needs_check(event, st, root, start):
    """Whether root's sources changed since the last clean check (and test
    run) of this session, and the turn-end hook has not reported on them."""
    entry = (st.get("roots") or {}).get(root)
    fp, newest = cae.hs.fingerprint(root)
    if (st.get("turn_end") or {}).get(root) == fp:
        return False, fp
    if entry is None:
        # (never checked in this session: changed since it began?)
        return (start is None or newest > start), fp
    clean = not entry.get("errors")
    tested = not cae.hs.has_tests(root) or entry.get("slow") or \
        os.environ.get("VOLE_CHECK_TESTS", "1") == "0" or \
        (entry.get("tests") or {}).get("fp") == fp
    return not (entry.get("fp") == fp and clean and tested), fp


def main():
    if os.environ.get("VOLE_TURN_END") == "0" or os.environ.get("VOLE_CHECK_HOOK") == "0":
        return 0
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    if event.get("hook_event_name", "Stop") not in ("Stop", "SubagentStop"):
        return 0
    st = cae.hs.load(event)
    start = cae.hs.session_start(event)
    reports = []
    for root in candidates(event, st):
        need, fp = needs_check(event, st, root, start)
        if not need:
            continue
        cwd = os.path.dirname(root)
        if root.endswith(os.path.join("compiler", "src", "main.vl")):
            cwd = os.path.dirname(os.path.dirname(cwd))
        compiler = cae.compiler_for(cwd)
        if not compiler:
            continue
        t0 = time.time()
        got = cae.verify(event, st, compiler, root, cwd, None, at_turn_end=True)
        if got is None:
            continue
        text, rec = got
        entry = st["roots"].get(root) or {}
        st.setdefault("turn_end", {})[root] = entry.get("fp") or fp
        failing = (entry.get("tests") or {}).get("failed") if (entry.get("tests") or {}).get("fp") == entry.get("fp") else None
        rec = dict(rec, kind="turn-end", ms=int((time.time() - t0) * 1000))
        cae.record(event, cwd, rec)
        if entry.get("errors") or failing:
            n = len(entry.get("errors") or [])
            what = []
            if n:
                what.append(f"{n} error{'s' if n != 1 else ''}")
            if failing:
                what.append(f"{len(failing)} failing test{'s' if len(failing) != 1 else ''}")
            shown = os.path.relpath(root, os.path.abspath(event.get("cwd") or os.getcwd()))
            if shown.startswith(".."):
                shown = root
            reports.append(f"turn-end: unchecked changes in {shown}: {', '.join(what)}\n{text}".rstrip())
    cae.hs.save(event, st)
    if reports:
        json.dump({"decision": "block", "reason": "\n".join(reports)}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
