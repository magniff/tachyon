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
    case("repeat-query: once a session", OUT[0], "")

    # (E3) The hint at the moment of need: three lookups in a row on
    # related items; once a session; not after `query context`; off with
    # TACHYON_HINTS=0.
    def post(session, command, stdout="x\n"):
        run({"hook_event_name": "PostToolUse", "tool_name": "Bash", "cwd": repo, "session_id": session,
             "tool_input": {"command": command}, "tool_response": {"stdout": stdout, "stderr": ""}})
        return json.loads(OUT[0])["hookSpecificOutput"]["additionalContext"] if OUT[0] else ""
    post("rel-1", "tachyonc query show Lexer")
    post("rel-1", "tachyonc query refs Lexer::next")
    case("related: a type and its method, then the method", post("rel-1", "tachyonc query def next"),
         hook.hs.hint("repeat-query", NAME="Lexer", TACHYONC="tachyonc"))
    case("related: once a session", post("rel-1", "tachyonc query show Lexer"), "")
    post("rel-2", "tachyonc query show alpha")
    post("rel-2", "tachyonc query show beta")
    case("unrelated names: no hint", post("rel-2", "tachyonc query show gamma"), "")
    post("rel-3", "target/tools/tachyonc query show alpha", "fn alpha() { beta(1) }\n")
    post("rel-3", "target/tools/tachyonc query show beta", "fn beta(x: i64) { gamma(x) }\n")
    got = post("rel-3", "target/tools/tachyonc query refs gamma")
    case("related through the answers: a callee's callee", got,
         hook.hs.hint("repeat-query", NAME="alpha", TACHYONC="target/tools/tachyonc"))
    case("the hint is a statement with the command", got.startswith("note: `target/tools/tachyonc query "
                                                                    "context alpha` prints"), True)
    post("rel-4", "tachyonc query context Lexer")
    post("rel-4", "tachyonc query show Lexer")
    post("rel-4", "tachyonc query refs Lexer")
    case("no hint once query context ran", post("rel-4", "tachyonc query def Lexer"), "")
    os.environ["TACHYON_HINTS"] = "0"
    post("rel-5", "tachyonc query show Lexer")
    post("rel-5", "tachyonc query refs Lexer")
    case("TACHYON_HINTS=0: no hint", post("rel-5", "tachyonc query def Lexer"), "")
    del os.environ["TACHYON_HINTS"]

    # (E6) Rewrite mode: an unambiguous read runs as its query (updatedInput,
    # permission allow, a one-line note); anything else is blocked as before.
    tools = os.path.join(repo, "target", "tools")
    os.makedirs(tools)
    pathbin = os.path.join(tmp, "bin")
    os.makedirs(pathbin)
    for d in (tools, pathbin):
        with open(os.path.join(d, "tachyonc"), "w") as fh:
            fh.write("#!/bin/sh\n")
        os.chmod(os.path.join(d, "tachyonc"), 0o755)
    old_path = os.environ.get("PATH", "")
    os.environ["PATH"] = pathbin + ":" + old_path

    def rewritten(cwd, command, session="rw"):
        st, err, recs = run({"hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": cwd,
                             "session_id": session, "tool_input": {"command": command,
                                                                   "description": "d"}})
        if st != 0 or not OUT[0]:
            return st, None, None, recs
        o = json.loads(OUT[0])["hookSpecificOutput"]
        return st, o, o["updatedInput"]["command"], recs
    st, err = blocked("sed -n '120,180p' compiler/src/gvn.tach")
    case("block mode is the default", st, True)
    os.environ["TACHYON_QUERY_MODE"] = "rewrite"
    st, o, cmd, recs = rewritten(repo, "sed -n '120,180p' compiler/src/front/big.tach")
    case("rewrite sed -n: query text", cmd, "target/tools/tachyonc query text compiler/src/front/big.tach:120-180")
    case("rewrite: the shape", (o["hookEventName"], o["permissionDecision"], o["updatedInput"]["description"]),
         ("PreToolUse", "allow", "d"))
    case("rewrite: the first note says what the mode does", o["additionalContext"].startswith(
        "note hook.query-first: shell reads of large .tach files are answered with the matching query "
        "(sed -n, head, tail: `query text`; cat: `query items`; grep: `query refs` or `query grep`), "
        "each command of a line on its own, the others as typed; `sed -n"), True)
    st, o, cmd, recs = rewritten(repo, "sed -n '120,180p' compiler/src/front/big.tach")
    case("rewrite: the note after the first", o["additionalContext"],
         "note hook.query-first: `sed -n '120,180p' compiler/src/front/big.tach` ran as "
         "`target/tools/tachyonc query text compiler/src/front/big.tach:120-180`: "
         "the same lines, each with its number")
    case("rewrite: logged", [(r["kind"], r["to"]) for r in recs if r["kind"] == "rewritten"],
         [("rewritten", cmd)])
    case("rewrite tail -n", rewritten(repo, "tail -n 50 compiler/src/front/big.tach")[2],
         "target/tools/tachyonc query text compiler/src/front/big.tach:351-400")
    case("rewrite head -N, a program on PATH's tachyonc", rewritten(prog, "head -350 util.tach")[2],
         "tachyonc query text util.tach:1-350")
    st, o, cmd, _ = rewritten(repo, "cat compiler/src/front/big.tach")
    case("rewrite cat of a large file: its outline", cmd, "target/tools/tachyonc query items crate::front::big")
    case("rewrite cat: the note says how to read more", "is 400 lines; this is its outline: `query show NAME`"
         in o["additionalContext"], True)
    case("rewrite cat in a program", rewritten(prog, "cat -n util.tach")[2], "tachyonc query items crate::util")
    case("rewrite grep of a name", rewritten(repo, "grep -n f12 compiler/src/front/big.tach")[2],
         "target/tools/tachyonc query refs f12 --in compiler/src/front/big.tach 2>/dev/null || "
         "target/tools/tachyonc query grep f12 --in compiler/src/front/big.tach")
    case("rewrite grep -rnw of a name in the tree", rewritten(repo, "grep -rnw '\\bf12\\b' compiler/src")[2],
         "target/tools/tachyonc query refs f12 2>/dev/null || target/tools/tachyonc query grep f12")
    case("rewrite after cd", rewritten(tmp, "cd repo && sed -n 5,9p compiler/src/front/big.tach")[2],
         "cd repo && tachyonc query text compiler/src/front/big.tach:5-9")
    os.makedirs(os.path.join(repo, "target"), exist_ok=True)
    shutil.copy(os.path.join(tools, "tachyonc"), os.path.join(repo, "target", "tachyonc"))
    post("rw-last", "target/tachyonc query items crate")
    case("rewrite: the tachyonc the agent ran last",
         rewritten(repo, "head -400 compiler/src/front/big.tach", "rw-last")[2],
         "target/tachyonc query text compiler/src/front/big.tach:1-400")
    for amb in ("grep -n 'f1.*' compiler/src/front/big.tach", "grep -c f12 compiler/src/front/big.tach",
                "sed -n '1,5p;9p' compiler/src/front/big.tach", "sed -n '/fn/p' compiler/src/front/big.tach",
                "cat compiler/src/front/big.tach main.tach", "cd $X && cat compiler/src/front/big.tach"):
        case("ambiguous, still blocked: " + amb, rewritten(repo, amb)[0], 2)
    case("writes still blocked in rewrite mode",
         rewritten(repo, "sed -i '' 's/f1/g1/' compiler/src/front/big.tach")[0], 2)

    # (n8) Chained lines: each read of source becomes its query where it
    # stands, every other command, separator and pipe kept as typed. The
    # 26 lines blocked on compiler tasks 21-24 in iteration 3
    # (.claude/briefs/evalruns/iter/03-night017), verbatim, on a tree with
    # their files.
    T = "target/tools/tachyonc"
    BIG = "".join("// line %d\n" % i for i in range(1, 420))
    files = {
        "compiler/src/middle/fold/mod.tach": BIG.replace("// line 87\n", "        Shl => wrap(a, ty),\n"),
        "compiler/src/middle/egraph.tach": BIG,
        "compiler/src/middle/ir/mod.tach": "pub mod cfg;\nuse crate::base::IntVec;\n" + BIG,
        "compiler/src/front/patterns/usefulness.tach": BIG,
        "compiler/std/io.tach": BIG.replace("// line 250\n", "    pub fn next_line(self: *Scanner) -> [u8] {\n"),
        "compiler/std/std.tach": BIG,
    }
    for name, text in files.items():
        os.makedirs(os.path.dirname(os.path.join(repo, name)), exist_ok=True)
        with open(os.path.join(repo, name), "w") as fh:
            fh.write(text)
    ITER3 = [
        "sed -n 1,60p docs/optimizer.md | cut -c1-400; echo ----; grep -n 'Shl\\|Shr\\|shl\\|shr' compiler/src/middle/fold/mod.tach | head -80; wc -l compiler/src/middle/fold/*.tach",
        'cd "$PWD" && git status --short | head; ls compiler/src/middle/ | head -50; grep -rn -i "shl\\|shr" compiler/src/middle/*.tach | head -80',
        'target/tachyonc query show compiler/src/middle/ir/mod.tach 2>&1 | head -5; grep -n "^pub mod\\|^mod\\|^use\\|^import" compiler/src/middle/ir/mod.tach',
        'target/tachyonc query context check_exhaustive 2>&1 | head -50; grep -n "range\\|Range\\|exhaust\\|non-exhaustive" compiler/src/front/patterns/usefulness.tach | head -120',
        'cd "$PWD" && grep -n -i "range\\|int\\|exhaust\\|non-exhaustive\\|wild" compiler/src/front/patterns/usefulness.tach | head -150',
        'cd "$PWD" && git status --short | head; ls; ls compiler/std | head -50; grep -rn "fn trim" compiler/std | head; cat compiler/std/embed.sh | head -40; sed -n 1,80p compiler/src/front/README.md',
        'cd "$PWD" && sed -n 60,120p compiler/std/embed.sh; echo ---; sed -n 90,120p compiler/std/io.tach; echo ---; ls compiler/std; echo ---; grep -n -i "std" compiler/src/front/README.md | sed -n 1,40p; echo ---; cat bootstrap/eval-build.sh | head -40; echo ---; ls tests/run | grep -i std | head -30',
        'cd "$PWD" && cat tests/run/std_text.tach; echo ---; grep -n "^#\\|trim" compiler/guide/std.md | head -60; echo ---; sed -n 1,30p compiler/guide/std.md | head -5; echo ---; grep -n "Some" compiler/std/*.tach | head -5; echo ---; git log --oneline | head -3; ls compiler/src/guide/',
        'cd "$PWD" && sed -n 90,130p compiler/std/io.tach && echo ---- && cat compiler/guide/std.md && echo ---- && sed -n 60,200p compiler/std/embed.sh && echo ---- && grep -n "std" tests/run.sh | head -30 && sed -n 1,40p tests/run.sh && echo ---- && ls tests/run | grep -i \'^std\' ; cat bootstrap/eval-build.sh | head -40',
        'cd "$PWD" && cat tests/run/std_text.tach && echo ---- && target/tachyonc query refs Option::Some 2>/dev/null | head -5; grep -n "Some(\\|None" compiler/std/*.tach | head -20; echo ----; grep -n "fn next_line" -A25 compiler/std/io.tach | head -50',
        'ls compiler/src/middle/ | head -50; grep -n -i "shl\\|shift" docs/optimizer.md | head -20; grep -rn "Shl" compiler/src/middle/*.tach | head -40',
        "sed -n 300,470p compiler/src/middle/fold/mod.tach; target/tachyonc query show shift_amount; target/tachyonc query show wrap_int",
        'ls compiler/src/middle/; grep -rn -i "shl\\|Shl" compiler/src/middle/*.tach | head -60; ls target',
        'cp target/tachyonc target/old-tachyonc; target/tachyonc query refs ir_make --count; target/tachyonc query show emit_ir; ls compiler/src/middle/ir; grep -n "mod \\|^use" compiler/src/middle/ir/mod.tach | head -30',
        'grep -rn "ir_make" compiler/src | head; git status --short | head -40; cat compiler/src/middle/ir/build.tach | head -30',
        "cat compiler/src/front/patterns/usefulness.tach",
        'grep -n -i "range\\|Int\\|fn " compiler/src/front/patterns/usefulness.tach | head -150',
        'grep -n -i "int\\|range\\|fn " compiler/src/front/patterns/usefulness.tach | head -150',
        "sed -n 51,100p compiler/src/front/patterns/usefulness.tach; sed -n 200,525p compiler/src/front/patterns/usefulness.tach",
        'cd compiler/src/front/patterns; grep -n -i "range\\|int\\|fn " usefulness.tach | head -150',
        'cd compiler/src/front/patterns; grep -n -i "range\\|Int\\|fn \\|wild" usefulness.tach | head -200',
        'head -30 compiler/std/embed.sh; grep -rn "fn trim" compiler/std | head; grep -n "trim" compiler/guide/std.md | head',
        "sed -n 95,122p compiler/std/io.tach; sed -n 70,110p compiler/guide/std.md; ls tests/run | grep '^std' | head -3; head -20 tests/run.sh",
        'head -25 tests/run/std_input.tach; ls tests/run | grep -i std_input; grep -n "Some(" compiler/std/io.tach | head -3; sed -n 110,125p compiler/guide/std.md',
        'head -30 compiler/std/embed.sh; grep -rn "fn trim" compiler/std | head; ls compiler/std; grep -n "trim" compiler/guide/std.md | head',
        "sed -n 95,122p compiler/std/io.tach; sed -n 70,110p compiler/guide/std.md; ls tests/run | head -5; head -20 tests/run.sh",
    ]
    os.environ["TACHYON_QUERY_MODE"] = "block"
    case("iteration 3: all 26 lines blocked in block mode", [blk for blk in ITER3 if at(repo, blk)[0] != 2], [])
    os.environ["TACHYON_QUERY_MODE"] = "rewrite"
    got = {}
    for k, line in enumerate(ITER3):
        st, o, cmd, recs = rewritten(repo, line, "iter3-%d" % k)
        got[k] = cmd
        reads = {r[2] for r in hook.source_reads(line, repo)}
        kept = [x for x in hook.tc.segments(line) if x not in reads]
        new_segs = hook.tc.segments(cmd or "")
        it = iter(new_segs)
        case("iteration 3 line %d: one turn, the other commands as typed" % (k + 1),
             (st, bool(cmd), all(x in it for x in kept)), (0, True, True))
    case("iter3: alternatives of texts, the pipe kept", got[0],
         "sed -n 1,60p docs/optimizer.md | cut -c1-400; echo ----; %s query grep Shl Shr shl shr "
         "--in compiler/src/middle/fold/mod.tach --limit 80 | head -80; wc -l compiler/src/middle/fold/*.tach" % T)
    case("iter3: -i, DIR/*.tach, after cd \"$PWD\", head over 60: --limit", got[1],
         'cd "$PWD" && git status --short | head; ls compiler/src/middle/ | head -50; %s query grep shl Shl SHL '
         'shr Shr SHR --in compiler/src/middle --limit 80 | head -80' % T)
    case("iter3: ^KEYWORD: --code --word, the line's own tachyonc", got[2],
         "target/tachyonc query show compiler/src/middle/ir/mod.tach 2>&1 | head -5; target/tachyonc query grep "
         "--word --code 'pub mod' mod use import --in compiler/src/middle/ir/mod.tach")
    case("iter3: grep -r of compiler/std: --in std", "%s query grep 'fn trim' --in std | head;" % T in got[5], True)
    case("iter3: sed -n of std, && kept", got[8].startswith(
        'cd "$PWD" && %s query text compiler/std/io.tach:90-130 && echo ---- && cat compiler/guide/std.md' % T), True)
    case("iter3: one name piped: refs or grep, grouped", "echo ---; { %s query refs Some --in std 2>/dev/null || "
         "%s query grep Some --in std; } | head -5; echo ---" % (T, T) in got[7], True)
    case("iter3: grep -A25 'fn NAME': the lines it prints (the line's own tachyonc)", got[9].endswith(
        "echo ----; target/tachyonc query text compiler/std/io.tach:250-275 | head -50"), True)
    case("iter3: a file that is not there: left as typed", got[14],
         "{ %s query refs ir_make 2>/dev/null || %s query grep ir_make; } | head; git status --short | head -40; "
         "cat compiler/src/middle/ir/build.tach | head -30" % (T, T))
    case("iter3: two sed -n of one file", got[18],
         "%s query text compiler/src/front/patterns/usefulness.tach:51-100; "
         "%s query text compiler/src/front/patterns/usefulness.tach:200-525" % (T, T))
    case("iter3: after cd into the module's directory: --root", got[19],
         "cd compiler/src/front/patterns; %s query grep range Range RANGE int Int INT 'fn ' 'Fn ' 'FN ' "
         "--in usefulness.tach --root %s --limit 150 | head -150"
         % (os.path.join(repo, T), os.path.join(repo, "compiler/src/main.tach")))
    st, o, cmd, recs = rewritten(repo, ITER3[0], "iter3-notes")
    notes = o["additionalContext"].split("\n")
    case("chain: one note line per part", (len(notes), notes[0].startswith("note hook.query-first: shell reads")),
         (1, True))
    st, o, cmd, recs = rewritten(repo, "sed -n 1,5p compiler/src/front/big.tach; grep -n Shl compiler/src/middle/fold/mod.tach",
                                 "iter3-notes")
    case("chain: a further part's note", o["additionalContext"].split("\n")[1],
         "note hook.query-first: also `grep -n Shl compiler/src/middle/fold/mod.tach` ran as `{ %s query refs Shl "
         "--in compiler/src/middle/fold/mod.tach 2>/dev/null || %s query grep Shl --in compiler/src/middle/fold/mod.tach; }`: "
         "`query refs Shl` lists its uses, each with its item; where Shl is no item, `query grep Shl` the lines "
         "holding it" % (T, T))
    case("chain: logged with its parts", [(r["kind"], r["parts"]) for r in recs if r["kind"] == "rewritten"],
         [("rewritten", 2)])

    st, o, cmd, recs = rewritten(repo, "cat compiler/src/front/nothere.tach | head -5", "missing")
    case("a file that is not there, alone: runs as typed", (st, cmd, [r["kind"] for r in recs]),
         (0, None, ["read-missing"]))

    # Pipes and readers folded: cat F | head, tail +N, sed 'A,$p', grep after cat.
    B = "compiler/src/front/big.tach"
    for line, want in (
            ("cat %s | head -30" % B, "%s query text %s:1-30" % (T, B)),
            ("ls; cat %s | tail -n 5 && echo ok" % B, "ls; %s query text %s:396-400 && echo ok" % (T, B)),
            ("cat -n %s | sed -n '10,20p'" % B, "%s query text %s:10-20" % (T, B)),
            ("cat %s | grep -n -w f12 | head -3" % B,
             "{ %s query refs f12 --in %s 2>/dev/null || %s query grep f12 --in %s; } | head -3" % (T, B, T, B)),
            ("tail -n +390 %s" % B, "%s query text %s:390-400" % (T, B)),
            ("sed -n '395,$p' %s" % B, "%s query text %s:395-400" % (T, B)),
            ("grep -n -B1 -A2 'fn f12()' %s" % B, "%s query text %s:12-15" % (T, B)),
            ("grep -nE 'f12|f13' %s 2>/dev/null; echo $?" % B,
             "%s query grep f12 f13 --in %s 2>/dev/null; echo $?" % (T, B)),
            ("grep -rn -e f12 -e 'fn f13' compiler/src; echo done",
             "%s query grep f12 'fn f13'; echo done" % T),
            ("grep -rnE '\\b(f12|f13)\\b' compiler/src | head -3",
             "%s query grep --word f12 f13 | head -3" % T),
            ("grep -n '^fn \\(f12\\|f13\\)(' %s" % B, "%s query grep --code 'fn f12(' 'fn f13(' --in %s" % (T, B)),
            ("grep -n 'fn f12()' -A2 compiler/src/front/*.tach", "%s query text %s:13-15" % (T, B)),
            ("grep -rn 'fn f12()' -A1 compiler/src | head", "%s query text %s:13-14 | head" % (T, B)),
            ("sed -n 1,9p %s | cut -c1-80 | head -3" % B, "%s query text %s:1-9 | cut -c1-80 | head -3" % (T, B)),
            ("grep -n '\\bf12\\b\\|\\bf13\\b' %s" % B, "%s query grep --word f12 f13 --in %s" % (T, B)),
            ("grep -nF 'a.b(' %s" % B, "%s query grep 'a.b(' --in %s" % (T, B)),
            ("grep -n 'Some(' %s" % B, "%s query grep 'Some(' --in %s" % (T, B)),
            ("grep -in f12 %s" % B, "%s query grep f12 F12 --in %s" % (T, B)),
            ("grep -rn f12 --include='*.tach' compiler/src/front",
             "{ %s query refs f12 --in compiler/src/front 2>/dev/null || %s query grep f12 --in compiler/src/front; }"
             % (T, T) if False else
             "%s query refs f12 --in compiler/src/front 2>/dev/null || %s query grep f12 --in compiler/src/front"
             % (T, T)),
    ):
        case("fold: " + line, rewritten(repo, line, "fold")[2], want)

    # Quoting: a text is one quoted word; nothing the agent did not write runs.
    st, o, cmd, _ = rewritten(repo, "grep -nF '$(touch /tmp/x)' %s; echo done" % B, "quote")
    import shlex
    case("quoting: a text with $( ) stays a word", shlex.split(cmd.split(";")[0])[3:4], ["$(touch /tmp/x)"])
    st, o, cmd, _ = rewritten(repo, "grep -n \"it's\" %s" % B, "quote")
    case("quoting: a quote in the text", shlex.split(cmd)[3:4], ["it's"])

    # In doubt: blocked, the parts it could translate named for the retry.
    for amb in ("grep -n 'f1.*' %s; sed -n 1,5p %s" % (B, B),
                "(cd compiler/src && grep -n f12 front/big.tach); grep -n f12 %s" % B,
                "grep -l f12 compiler/src", "grep -v f12 %s" % B, "grep -n f12 %s > /tmp/out" % B,
                "grep -n f12 %s compiler/src/middle/egraph.tach" % B, "grep -n 'f1$' %s" % B,
                "grep -C1 '0()' %s" % B, "grep -n '\\bf12' %s" % B, "rg -n f12 compiler/src",
                "grep -n '^// line' %s" % B, "W=compiler/src; grep -n f12 $W/front/big.tach $Q/x.tach",
                "cat %s | wc -l" % B, "grep -rn f12 compiler/src/*/*.tach",
                # (a program reads the output, or the grep's status: the query's differ)
                "grep -rn f12 compiler/src | wc -l", "grep -rn f12 compiler/src | head | sort",
                "echo $(sed -n 1,5p %s)" % B, "grep -rn f12 compiler/src && echo found",
                "grep -rn -e f12 compiler/src || echo none", "diff <(sed -n 1,5p %s) x" % B):
        case("in doubt, blocked: " + amb, rewritten(repo, amb, "doubt")[0], 2)
    st, err, recs = at(repo, "sed -n 1,5p %s; grep -n 'f1.*' %s; ls" % (B, B))
    case("blocked: the translated parts named", (st, err.splitlines()[0], err.splitlines()[-2]),
         (2, "blocked hook.query-first: `grep -n 'f1.*' compiler/src/front/big.tach` (command 2 of 3 on the line; "
             "the others are not blocked) reads .tach source",
          "the line's other reads of .tach source run as their queries on a retry: `sed -n 1,5p %s` as "
          "`%s query text %s:1-5`" % (B, T, B)))
    case("blocked: logged with what translated", recs[-1].get("translated"), ["%s query text %s:1-5" % (T, B)])
    st, err, recs = at(repo, "grep -n 'f1.*' %s; grep -c f2 %s" % (B, B))
    case("blocked: each blocked read of the line gets its try", err.splitlines()[0:1] + [
        l for l in err.splitlines() if l.startswith("also blocked")],
         ["blocked hook.query-first: `grep -n 'f1.*' compiler/src/front/big.tach` (command 1 of 2 on the line) "
          "reads .tach source",
          "also blocked: `grep -c f2 compiler/src/front/big.tach` (command 2 of 2 on the line); try: "
          "tachyonc query refs f2 | tachyonc query grep f2"])
    del os.environ["TACHYON_QUERY_MODE"]
    os.environ["PATH"] = old_path
shutil.rmtree(STATE, ignore_errors=True)

print("total", "ok" if FAILED == 0 else f"{FAILED} failed")
sys.exit(1 if FAILED else 0)
