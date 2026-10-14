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
hook.log = lambda gd, record: LOGGED.append({**hook.IDENT, **record})
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
st, err = blocked("sed -n '120,180p' tests/run/loops.tach")
case("read sed -n test file", "try: tachyonc query text tests/run/loops.tach:120-180 |" in err, True)
st, err = blocked("head -40 tests/refactor/patch/calc.tach")
case("read head test file", "try: tachyonc query text tests/refactor/patch/calc.tach:1-40 |" in err, True)
st, err = blocked("head -n 30 compiler/src/gvn.tach")
case("read head compiler", "MODULE::header" in err and "query text compiler/src/gvn.tach:1-30" in err, True)
st, err = blocked("cat tests/refactor/patch/main.tach")
case("read cat", "tachyonc query show tests/refactor/patch/main.tach" in err, True)
case("grep of text suggests query grep",
     "query grep 'no definition'" in blocked("grep -rn 'no definition' compiler/src")[1], True)
case("grep of a name suggests refs and grep",
     "query refs run_gvn | tachyonc query grep run_gvn" in blocked("grep -rn run_gvn compiler/src")[1], True)
case("read docs",blocked("grep -n edit docs/refactor.md")[0], False)
# (0.14) Alternatives and regexes are never glued into one name.
case("grep of alternatives: one query each",
     blocked("grep -n 'cmd_add\\|qty' compiler/src/a.tach")[1].split("\n")[1],
     "try: tachyonc query refs cmd_add qty | tachyonc query grep cmd_add | tachyonc query grep qty"
     " | override: append '# no-query: <why query is not enough>'")
case("grep -E of alternatives",
     "query refs Item calc | tachyonc query grep Item | tachyonc query grep calc"
     in blocked("grep -En 'Item|calc' compiler/src/a.tach")[1], True)
case("grep -e twice", "query refs a_b c_d |" in blocked("grep -e a_b -e c_d compiler/src/a.tach")[1], True)
case("grep of a word-bounded name", "query refs qty | tachyonc query grep qty"
     in blocked("grep -n '\\bqty\\b' compiler/src/a.tach")[1], True)
case("grep of a regex: its longest literal, not a glued name",
     "query grep total_qty | " in blocked("grep -n 'total_qty.*(self' compiler/src/a.tach")[1]
     and "total_qtyself" not in blocked("grep -n 'total_qty.*(self' compiler/src/a.tach")[1], True)
case("grep of texts with alternatives", "query grep 'no root' | tachyonc query grep 'bad root'"
     in blocked("grep -rn 'no root\\|bad root' compiler/src")[1], True)
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

# 0.12: writes are judged by the files written, not by every path named.
case("python writes a doc naming source", blocked(
    "python3 - <<'EOF'\nopen('compiler/README.md', 'w').write('see compiler/std/std.tach')\nEOF")[0], False)
case("python writes a scratch helper", blocked(
    "python3 - <<'EOF'\np = '/private/tmp/claude-1/scratchpad/h.py'\n"
    "open(p, 'w').write(\"run('compiler/src/main.tach')\")\nEOF")[0], False)
case("python writes source, variable", blocked(
    "python3 - <<'EOF'\nsrc = 'compiler/src/a.tach'\nopen(src, 'w').write('x')\nEOF")[0], True)
case("python write, file unknown", blocked(
    "python3 -c \"import sys; open(sys.argv[1], 'w').write('x')\" compiler/src/a.tach")[0], True)
st, err, recs = bash("sed -i '' 's/a/b/' target/patch.txt && target/tachyonc edit patch "
                     "compiler/src/a.tach < target/patch.txt")
case("sed -i scratch input, no edit logged", (st, [r["kind"] for r in recs]), (0, []))
case("sed -i after cd into scratch", blocked("cd target/copy && sed -i 's/a/b/' compiler/src/x.tach")[0], False)
case("sed -i docs quoting a read", blocked(
    "sed -i '' \"s|grep x|sed -n '120,180p' compiler/src/gvn.tach; cat compiler/src/a.tach|\" docs/query.md")[0],
     False)
case("awk generating a program", blocked("awk -f tests/fuzz/gendiv.awk > target/fuzz/x.tach")[0], False)
case("grep of a generated program", blocked("grep -c add target/fuzz/x.tach")[0], False)
case("read with 2>&1", blocked("grep -n fn compiler/src/a.tach 2>&1")[0], True)

# 0.12: the checkout and its shared git directory, without git; who logs.
import tempfile
with tempfile.TemporaryDirectory() as tmp:
    tmp = os.path.realpath(tmp)
    main = os.path.join(tmp, "main")
    common = os.path.join(main, ".git")
    wt_git = os.path.join(common, "worktrees", "a")
    wt = os.path.join(tmp, "wt", "a")
    os.makedirs(wt_git)
    os.makedirs(os.path.join(wt, "compiler", "src"))
    with open(os.path.join(wt, ".git"), "w") as fh:
        fh.write("gitdir: " + wt_git + "\n")
    with open(os.path.join(wt_git, "commondir"), "w") as fh:
        fh.write("../..\n")
    case("checkout of main", hook.checkout_of(main), (main, common))
    case("checkout of a worktree", hook.checkout_of(os.path.join(wt, "compiler", "src")), (wt, common))
    case("checkout of nothing", hook.checkout_of("/"), (None, None))
    st, err, recs = run({"hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": wt,
                         "session_id": "s123456789", "transcript_path": "/x/t.jsonl", "agent_id": "agent-7",
                         "tool_input": {"command": "target/tachyonc query show f"}})
    case("identity", [(r.get("session"), r.get("agent_id"), r.get("worktree")) for r in recs],
         [("s1234567", "agent-7", wt)])
    # tools/agent-feedback, from a worktree: into the shared log, no git run.
    import subprocess
    feedback = os.path.join(os.path.dirname(HERE), "agent-feedback")
    env = dict(os.environ, PATH="/usr/bin:/bin:" + os.path.dirname(sys.executable))
    out = subprocess.run([feedback, "query", "a note"], cwd=os.path.join(wt, "compiler"), env=env,
                         capture_output=True, text=True)
    with open(os.path.join(common, "agent-tools.jsonl")) as fh:
        rec = json.loads(fh.readline())
    case("agent-feedback in a worktree", (out.stdout.strip(), rec["tool"], rec["message"], rec["worktree"]),
         ("recorded", "query", "a note", wt))

print("total", "ok" if FAILED == 0 else f"{FAILED} failed")
sys.exit(1 if FAILED else 0)
