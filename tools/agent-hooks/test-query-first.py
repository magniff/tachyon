#!/usr/bin/env python3
"""Cases for the query-first hook (query-first.py): what it blocks, what it
lets through, what it suggests and logs. Development tooling only.

usage: python3 -I tools/agent-hooks/test-query-first.py
"""
import importlib.util
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("query_first", os.path.join(HERE, "query-first.py"))
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

LOGGED = []
hook.log = lambda gd, record: LOGGED.append(record)
hook.query_ready = lambda gd, cwd: True
hook.git_dir = lambda cwd: "/nonexistent"


def run(event):
    """The hook on event: (exit status, stderr, the records it logged)."""
    LOGGED.clear()
    stdin, stderr = sys.stdin, sys.stderr
    sys.stdin, sys.stderr = io.StringIO(json.dumps(event)), io.StringIO()
    try:
        status = hook.main()
        err = sys.stderr.getvalue()
    finally:
        sys.stdin, sys.stderr = stdin, stderr
    return status, err, list(LOGGED)


def bash(command, phase="PreToolUse", stdout=""):
    return run({"hook_event_name": phase, "tool_name": "Bash", "cwd": HERE,
                "tool_input": {"command": command},
                "tool_response": {"stdout": stdout, "stderr": ""}})


FAILED = 0


def case(name, got, want):
    global FAILED
    if got == want:
        print(f"pass {name}")
    else:
        FAILED += 1
        print(f"FAIL {name}:\n    want {want!r}\n    got  {got!r}")


def blocked(command):
    status, err, _ = bash(command)
    return status == 2, err


# Reading source: blocked with the query; other files are not.
st, err = blocked("sed -n '120,180p' compiler/src/gvn.tach")
case("read sed -n", (st, "query show compiler/src/gvn.tach:120" in err), (True, True))
case("read grep", blocked("grep -n 'fn run_gvn' compiler/src/gvn.tach")[0], True)
case("read docs", blocked("grep -n edit docs/refactor.md")[0], False)
case("read escape", blocked("sed -n '1,9p' compiler/src/gvn.tach  # no-query: the use lines")[0], False)

# Rewriting compiler source in place: blocked, with `edit patch`.
st, err = blocked("sed -i '' '1615s/a < b/a <= b/' compiler/src/range.tach")
case("sed -i line", (st, err.splitlines()[0] if err else ""),
     (True, "blocked hook.edit-tool: sed -i rewriting compiler source (compiler/src/range.tach)"))
case("sed -i line suggestion",
     "try: tachyonc edit patch compiler/src/range.tach:1615 --old 'a < b' --new 'a <= b' |" in err, True)
case("sed -i two lines", len(err.splitlines()), 2)
st, err = blocked("sed -i 's/x.*y/z/g' compiler/src/a.tach compiler/src/b.tach")
case("sed -i regex", (st, "edit patch compiler/src/a.tach:LINE --old 'TEXT' --new 'TEXT'" in err), (True, True))
case("sed -Ei", blocked("sed -Ei.bak 's/a/b/' compiler/std/vec.tach")[0], True)
case("perl -pi", blocked("perl -pi -e 's/foo/bar/' compiler/std/vec.tach")[0], True)
case("perl -0pi", blocked("perl -0pi -e 's/foo/bar/' ./compiler/src/x.tach")[0], True)
case("python heredoc", blocked(
    "python3 - <<'EOF'\np = 'compiler/src/range.tach'\ns = open(p).read()\nassert OLD in s\n"
    "open(p, 'w').write(s.replace(OLD, NEW))\nEOF")[0], True)
case("python -c", blocked(
    "python3 -c \"import pathlib; p = pathlib.Path('compiler/src/edit.tach'); "
    "p.write_text(p.read_text().replace('a', 'b'))\"")[0], True)
case("python worktree path", blocked(
    "cd /x/.claude/worktrees/a && python3 -c \"p='/x/.claude/worktrees/a/compiler/src/edit.tach'; "
    "s=open(p).read(); open(p,'w').write(s)\"")[0], True)

# Not compiler source, or not a rewrite: let through.
case("sed -i test fixture", blocked("sed -i 's/a/b/' tests/run/loops.tach")[0], False)
case("sed -i docs", blocked("sed -i '' 's/a/b/' docs/refactor.md AGENTS.md")[0], False)
case("sed -i scratch copy", blocked("sed -i 's/a/b/' target/scratch/compiler/src/x.tach")[0], False)
case("sed -i tmp copy", blocked("sed -i 's/a/b/' /tmp/w/compiler/src/x.tach")[0], False)
case("python writes a test", blocked(
    "python3 - <<'EOF'\np = 'tests/refactor/patch.t'\nopen(p, 'w').write('x')\nEOF")[0], False)
case("python reads source", blocked("python3 tools/agent-tool-usage.py compiler/src/main.tach")[0], False)
case("sed -n is a read", blocked("sed -n 's/a/b/p' docs/x.md")[0], False)
case("tachyonc edit patch", blocked(
    "target/tachyonc edit patch compiler/src/range.tach:1615 --old 'a < b' --new 'a <= b'")[0], False)

# The escapes: `# no-tool:`, and the older `# no-query:`; the reason is logged.
st, err, recs = bash("sed -i 's/[a-z]*_old/new/' compiler/src/*.tach  # no-tool: a regex over every file")
case("escape no-tool", (st, [r["kind"] for r in recs], recs[0].get("reason") if recs else None),
     (0, ["edit-escape"], "a regex over every file"))
st, err, recs = bash("perl -pi -e 's/a/b/' compiler/src/x.tach  # no-query: merge conflict markers")
case("escape no-query", (st, [r["kind"] for r in recs]), (0, ["edit-escape"]))

# Edit and Write: never blocked, logged with whether the file existed.
for tool, inp in (("Edit", {"file_path": os.path.join(HERE, "query-first.py").replace(".py", ".tach"),
                            "old_string": "a", "new_string": "b"}),
                  ("Write", {"file_path": "/nonexistent/compiler/src/new.tach", "content": "fn f() {}\n"})):
    st, err, recs = run({"hook_event_name": "PreToolUse", "tool_name": tool, "cwd": HERE, "tool_input": inp})
    case(f"{tool} not blocked", (st, [r["kind"] for r in recs], recs[0]["existed"] if recs else None),
         (0, [tool.lower()], False))

# The tools' results: whether they wrote, and on what.
st, err, recs = bash("target/tachyonc edit patch clamp --old a --new b", "PostToolUse",
                     "patched crate::range::clamp\tcompiler/src/range.tach\t+1 -1 lines\n")
case("tool written", [(r["kind"], r["tool"], r["written"], r["compiler"]) for r in recs],
     [("tool-result", "edit", True, True)])
st, err, recs = bash("target/tachyonc edit patch clamp --old a --new b --dry-run", "PostToolUse",
                     "--- a/compiler/src/range.tach\n+++ b/compiler/src/range.tach\n")
case("tool dry run", [r["written"] for r in recs], [False])
st, err, recs = bash("target/tachyonc refactor rename f g --root tests/refactor/edits/main.tach", "PostToolUse",
                     "renamed crate::f\tmain.tach\t+1 -1 lines\n")
case("tool on a test program", [(r["written"], r["compiler"]) for r in recs], [(True, False)])
st, err, recs = bash("target/tachyonc undo", "PostToolUse", "undid patched crate::a\tcompiler/src/a.tach\t+1 -1 lines\n")
case("tool undo", [(r["tool"], r["written"], r["compiler"]) for r in recs], [("undo", True, True)])

print("total", "ok" if FAILED == 0 else f"{FAILED} failed")
sys.exit(1 if FAILED else 0)
