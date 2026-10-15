#!/usr/bin/env python3
"""Cases for the query-first hook (query-first.py): what it blocks, what it
lets through, what it suggests and logs. Development tooling only.

usage: python3 -I tools/agent-hooks/test-query-first.py
"""
import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile

STATE = tempfile.mkdtemp()
os.environ["TACHYON_HOOK_STATE"] = STATE

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("query_first", os.path.join(HERE, "query-first.py"))
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

LOGGED = []
hook.log = lambda gd, record: LOGGED.append({**hook.IDENT, **record})
hook.query_ready = lambda gd, cwd: True
hook.git_dir = lambda cwd: "/nonexistent"


OUT = [""]


def run(event):
    """The hook on event: (exit status, stderr, the records it logged); its
    stdout in OUT[0]."""
    LOGGED.clear()
    stdin, stderr, stdout = sys.stdin, sys.stderr, sys.stdout
    sys.stdin, sys.stderr, sys.stdout = io.StringIO(json.dumps(event)), io.StringIO(), io.StringIO()
    try:
        status = hook.main()
        err = sys.stderr.getvalue()
        OUT[0] = sys.stdout.getvalue()
    finally:
        sys.stdin, sys.stderr, sys.stdout = stdin, stderr, stdout
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
st, err = blocked("sed -n '120,180p' examples/loops.tach")
case("read sed -n example program", "try: tachyonc query text examples/loops.tach:120-180\n" in err, True)
st, err = blocked("head -40 bench/calc.tach")
case("read head program", "try: tachyonc query text bench/calc.tach:1-40\n" in err, True)
st, err = blocked("cat examples/main.tach")
case("read cat", "tachyonc query show examples/main.tach" in err, True)
case("read a program outside tests", blocked("cat /home/u/proj/src/main.tach")[0], True)

# (0.14) Test data under tests/ (cases, fixtures, eval tasks): read freely, logged.
st, err, recs = bash("sed -n '120,180p' tests/run/loops.tach")
case("read test case", (st, [r["kind"] for r in recs]), (0, ["read-fixture"]))
case("read head fixture", blocked("head -40 tests/refactor/patch/calc.tach")[0], False)
case("read cat fixture", blocked("cat tests/refactor/patch/main.tach")[0], False)
case("read eval task data", blocked("cat tests/agent-eval/tasks/07-fix-bugs/tach/main.tach")[0], False)
case("grep eval task data", blocked("grep -n 'fn main' tests/agent-eval/tasks/*/tach/*.tach")[0], False)
case("grep -r test cases", blocked("grep -rn 'EXPECT' tests/run")[0], False)
case("read fixture after cd", blocked("cd tests/agent-eval/tasks/02-rpn && cat tach/main.tach")[0], False)
case("read absolute fixture", blocked("cat " + os.path.join(os.path.dirname(os.path.dirname(HERE)),
                                                            "tests/run/loops.tach"))[0], False)
case("fixture and source: blocked", blocked("cat tests/run/a.tach compiler/src/main.tach")[0], True)
case("cd tests, then source", blocked("cd tests && cat ../compiler/src/main.tach")[0], True)

case("grep of text suggests query grep",
     "query grep 'no definition'" in blocked("grep -rn 'no definition' compiler/src")[1], True)
case("grep of a name suggests refs and grep",
     "query refs run_gvn | tachyonc query grep run_gvn" in blocked("grep -rn run_gvn compiler/src")[1], True)
case("read docs",blocked("grep -n edit docs/refactor.md")[0], False)
# (0.14) Alternatives and regexes are never glued into one name.
case("grep of alternatives: one query each",
     blocked("grep -n 'cmd_add\\|qty' compiler/src/a.tach")[1].split("\n")[1],
     "try: tachyonc query refs cmd_add qty | tachyonc query grep cmd_add | tachyonc query grep qty")
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

# 0.15: tachyonc through a copy, a shell variable, the tools binary.
st, err, recs = bash("T=target/tc0; $T edit patch clamp --old a --new b", "PostToolUse",
                     "patched crate::range::clamp\tcompiler/src/range.tach\t+1 -1 lines\n")
case("tool through $T", [(r["kind"], r["tool"], r["written"], r.get("via")) for r in recs],
     [("tool-result", "edit", True, "target/tc0")])
case("query through ${T}", [(r["kind"], r.get("via")) for r in bash("T=target/tc0 && ${T} query show f")[2]],
     [("query", "target/tc0")])
case("query through an unassigned $TC", [r.get("via") for r in bash('"$TC" query refs f')[2]], ["$VAR"])
case("query through a copy", [r.get("via") for r in bash("target/tc-new query def f --json")[2]],
     ["target/tc-new"])
case("query through the tools binary", [r.get("via") for r in bash("target/tools/tachyonc query show f")[2]],
     [None])
case("not tachyonc: tclsh, $X ls", [r["kind"] for r in bash("tclsh query.tcl; $X ls; tcpdump -i en0")[2]], [])
case("query inside $(...)", [r["kind"] for r in bash("n=$(tachyonc query refs f --count)")[2]], ["query"])

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
case("a script written by cat, then run: not a python rewrite (0.17)", blocked(
    "cat > /tmp/x/t.py <<'EOF'\nopen('compiler/src/a.tach', 'w').write('x')\nEOF\npython3 -I /tmp/x/t.py")[0], False)
case("python -c after an echo", blocked(
    "echo hi; python3 -c \"open('compiler/src/a.tach', 'w').write('x')\"")[0], True)
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


# 0.17: each command of a line judged on its own, small files read whole,
# probes and scratch copies are not source, variables and cds followed,
# the try: lines logged; replies after the call (line numbers for Edit,
# the repeat-query hint).
with tempfile.TemporaryDirectory() as tmp:
    tmp = os.path.realpath(tmp)
    repo = os.path.join(tmp, "repo")
    os.makedirs(os.path.join(repo, ".git"))
    os.makedirs(os.path.join(repo, "compiler", "src", "front"))
    big = "".join("fn f%d() {}\n" % i for i in range(400))
    with open(os.path.join(repo, "compiler", "src", "front", "big.tach"), "w") as fh:
        fh.write(big)
    with open(os.path.join(repo, "compiler", "src", "small.tach"), "w") as fh:
        fh.write("fn g() {}\n" * 20)
    prog = os.path.join(tmp, "ws")
    os.makedirs(os.path.join(prog, "scratch"))
    for name, text in (("main.tach", "mod util;\nfn main() {}\n" + big), ("util.tach", big),
                       ("probe.tach", big), ("scratch/diff.tach", big)):
        with open(os.path.join(prog, name), "w") as fh:
            fh.write(text)

    def at(cwd, command, phase="PreToolUse", stdout=""):
        return run({"hook_event_name": phase, "tool_name": "Bash", "cwd": cwd, "session_id": "qf-test",
                    "tool_input": {"command": command}, "tool_response": {"stdout": stdout, "stderr": ""}})
    st, err, recs = at(repo, "ls; cat compiler/src/front/big.tach; echo done")
    case("per command: the reading one named", (st, err.splitlines()[0]),
         (2, "blocked hook.query-first: `cat compiler/src/front/big.tach` (command 2 of 3 on the line; "
             "the others are not blocked) reads .tach source"))
    case("large file: its length and module", err.splitlines()[1].startswith(
        "compiler/src/front/big.tach is 400 lines (a file under 300 is read whole freely): "
        "`tachyonc query items crate::front::big` lists its items"), True)
    case("blocked: the try lines logged", recs[-1].get("try"),
         ["tachyonc query show compiler/src/front/big.tach (a whole small file) | tachyonc query text "
          "compiler/src/front/big.tach:A-B", "tachyonc query items crate::front::big"])
    st, err, recs = at(repo, "cat compiler/src/small.tach")
    case("small file: read whole", (st, [r["kind"] for r in recs]), (0, ["read-small"]))
    case("small file: sed -n", at(repo, "sed -n '1,5p' compiler/src/small.tach")[0], 0)
    case("small file: grep is still a search", at(repo, "grep -n g compiler/src/small.tach")[0], 2)
    case("a query on the line does not excuse a read",
         at(repo, "tachyonc query show f; cat compiler/src/front/big.tach")[0], 2)
    case("a query and ls: not blocked", at(repo, "tachyonc query items crate | head; ls compiler/src")[0], 0)
    case("program: main.tach is source", at(prog, "cat main.tach")[0], 2)
    case("program: a declared module is source", at(prog, "head -350 util.tach")[0], 2)
    st, err, recs = at(prog, "head -6 scratch/diff.tach")
    case("program: a scratch .tach is not", (st, [r["kind"] for r in recs]), (0, ["read-scratch"]))
    case("program: a probe next to main.tach is not", at(prog, "cat probe.tach")[0], 0)
    case("a variable on the line: scratch", at(repo, "S=/private/tmp/x/sp; cat $S/big.tach")[0], 0)
    case("a variable on the line: source", at(tmp, "W=%s; cat $W/compiler/src/front/big.tach" % repo)[0], 2)
    case("cd then a scratch file", at(repo, "cd %s && cat probe.tach" % prog)[0], 0)
    case("cd then source", at(tmp, "cd repo && cat compiler/src/front/big.tach")[0], 2)
    st, err, recs = at(repo, "sed -n '1,9p' compiler/src/front/big.tach  # no-query: need the line number for the Edit tool",
                       "PostToolUse")
    case("escape for Edit's line numbers: the reply", "edit insert --after NAME" in OUT[0]
         and "query def NAME" in OUT[0], True)
    for q in ("tachyonc query show run_gvn", "tachyonc query refs run_gvn"):
        at(repo, q, "PostToolUse", "x\n")
        case("repeat-query: not yet", OUT[0], "")
    at(repo, "tachyonc query def run_gvn", "PostToolUse", "x\n")
    hint = json.loads(OUT[0])["hookSpecificOutput"]["additionalContext"] if OUT[0] else ""
    case("repeat-query: the hint, from hints.txt", hint,
         hook.hs.hint("repeat-query", NAME="run_gvn", TACHYONC="tachyonc"))
    case("repeat-query: the hint names context", "query context run_gvn" in hint, True)
    at(repo, "tachyonc query show run_gvn", "PostToolUse", "x\n")
    case("repeat-query: once per name", OUT[0], "")
shutil.rmtree(STATE, ignore_errors=True)

print("total", "ok" if FAILED == 0 else f"{FAILED} failed")
sys.exit(1 if FAILED else 0)
