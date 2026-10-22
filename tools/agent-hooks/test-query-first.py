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
os.environ["VOLE_HOOK_STATE"] = STATE

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("query_first", os.path.join(HERE, "query-first.py"))
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

LOGGED = []
hook.log = lambda gd, record: LOGGED.append({**hook.IDENT, **record})
hook.query_ready = lambda gd, cwd: True
hook.git_dir = lambda cwd: "/nonexistent"

# (0.18.1) The tree these cases run in is their checkout even when it has
# no .git of its own: a release's tree as bootstrap.sh extracts it (`git
# archive`, under the target/ of another checkout or of none), where the
# hook would otherwise take every file for a scratch copy.
TREE = os.path.dirname(os.path.dirname(HERE))
_checkout_of = hook.checkout_of


def checkout_of(cwd):
    top, gd = _checkout_of(cwd)
    d = os.path.abspath(cwd or os.getcwd())
    if (d + "/").startswith(TREE + "/"):
        return TREE, gd
    return top, gd


hook.checkout_of = checkout_of


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
st, err = blocked("sed -n '120,180p' compiler/src/gvn.vl")
case("read sed -n", (st, "query show compiler/src/gvn.vl:120" in err), (True, True))
case("read grep", blocked("grep -n 'fn run_gvn' compiler/src/gvn.vl")[0], True)
st, err = blocked("sed -n '120,180p' examples/loops.vl")
case("read sed -n example program", "try: volec query text examples/loops.vl:120-180\n" in err, True)
st, err = blocked("head -40 bench/calc.vl")
case("read head program", "try: volec query text bench/calc.vl:1-40\n" in err, True)
st, err = blocked("cat examples/main.vl")
case("read cat", "volec query show examples/main.vl" in err, True)
case("read a program outside tests", blocked("cat /home/u/proj/src/main.vl")[0], True)

# (0.14) Test data under tests/ (cases, fixtures, eval tasks): read freely, logged.
st, err, recs = bash("sed -n '120,180p' tests/run/loops.vl")
case("read test case", (st, [r["kind"] for r in recs]), (0, ["read-fixture"]))
case("read head fixture", blocked("head -40 tests/refactor/patch/calc.vl")[0], False)
case("read cat fixture", blocked("cat tests/refactor/patch/main.vl")[0], False)
case("read eval task data", blocked("cat tests/agent-eval/tasks/07-fix-bugs/tach/main.vl")[0], False)
case("grep eval task data", blocked("grep -n 'fn main' tests/agent-eval/tasks/*/tach/*.vl")[0], False)
case("grep -r test cases", blocked("grep -rn 'EXPECT' tests/run")[0], False)
case("read fixture after cd", blocked("cd tests/agent-eval/tasks/02-rpn && cat tach/main.vl")[0], False)
case("read absolute fixture", blocked("cat " + os.path.join(os.path.dirname(os.path.dirname(HERE)),
                                                            "tests/run/loops.vl"))[0], False)
case("fixture and source: blocked", blocked("cat tests/run/a.vl compiler/src/main.vl")[0], True)
case("cd tests, then source", blocked("cd tests && cat ../compiler/src/main.vl")[0], True)

case("grep of text suggests query grep",
     "query grep 'no definition'" in blocked("grep -rn 'no definition' compiler/src")[1], True)
case("grep of a name suggests refs and grep",
     "query refs run_gvn | volec query grep run_gvn" in blocked("grep -rn run_gvn compiler/src")[1], True)
case("read docs",blocked("grep -n edit docs/refactor.md")[0], False)
# (0.14) Alternatives and regexes are never glued into one name.
case("grep of alternatives: one query each",
     blocked("grep -n 'cmd_add\\|qty' compiler/src/a.vl")[1].split("\n")[1],
     "try: volec query refs cmd_add qty | volec query grep cmd_add | volec query grep qty")
case("grep -E of alternatives",
     "query refs Item calc | volec query grep Item | volec query grep calc"
     in blocked("grep -En 'Item|calc' compiler/src/a.vl")[1], True)
case("grep -e twice", "query refs a_b c_d |" in blocked("grep -e a_b -e c_d compiler/src/a.vl")[1], True)
case("grep of a word-bounded name", "query refs qty | volec query grep qty"
     in blocked("grep -n '\\bqty\\b' compiler/src/a.vl")[1], True)
case("grep of a regex: its longest literal, not a glued name",
     "query grep total_qty | " in blocked("grep -n 'total_qty.*(self' compiler/src/a.vl")[1]
     and "total_qtyself" not in blocked("grep -n 'total_qty.*(self' compiler/src/a.vl")[1], True)
case("grep of texts with alternatives", "query grep 'no root' | volec query grep 'bad root'"
     in blocked("grep -rn 'no root\\|bad root' compiler/src")[1], True)
case("read escape", blocked("sed -n '1,9p' compiler/src/gvn.vl  # no-query: the use lines")[0], False)

# Rewriting compiler source in place: blocked, with `edit patch`.
st, err = blocked("sed -i '' '1615s/a < b/a <= b/' compiler/src/range.vl")
case("sed -i line", (st, err.splitlines()[0] if err else ""),
     (True, "blocked hook.edit-tool: sed -i rewriting compiler source (compiler/src/range.vl)"))
case("sed -i line suggestion",
     "try: volec edit patch compiler/src/range.vl:1615 --old 'a < b' --new 'a <= b' |" in err, True)
case("sed -i two lines", len(err.splitlines()), 2)
st, err = blocked("sed -i 's/x.*y/z/g' compiler/src/a.vl compiler/src/b.vl")
case("sed -i regex", (st, "edit patch compiler/src/a.vl:LINE --old 'TEXT' --new 'TEXT'" in err), (True, True))
case("sed -Ei", blocked("sed -Ei.bak 's/a/b/' compiler/std/vec.vl")[0], True)
case("perl -pi", blocked("perl -pi -e 's/foo/bar/' compiler/std/vec.vl")[0], True)
case("perl -0pi", blocked("perl -0pi -e 's/foo/bar/' ./compiler/src/x.vl")[0], True)
case("python heredoc", blocked(
    "python3 - <<'EOF'\np = 'compiler/src/range.vl'\ns = open(p).read()\nassert OLD in s\n"
    "open(p, 'w').write(s.replace(OLD, NEW))\nEOF")[0], True)
case("python -c", blocked(
    "python3 -c \"import pathlib; p = pathlib.Path('compiler/src/edit.vl'); "
    "p.write_text(p.read_text().replace('a', 'b'))\"")[0], True)
case("python worktree path", blocked(
    "cd /x/.claude/worktrees/a && python3 -c \"p='/x/.claude/worktrees/a/compiler/src/edit.vl'; "
    "s=open(p).read(); open(p,'w').write(s)\"")[0], True)

# Not compiler source, or not a rewrite: let through.
# (0.18.1) A whole-file sed: every line's, --all, one per file; a regex
# (\\b, -E) or a & in the replacement: the general form; BSD's -i ''.
st, err = blocked("sed -i '' 's/old_name/new_name/g' compiler/src/a.vl compiler/src/b.vl")
case("sed -i whole files", err.splitlines()[1].split(" | ")[0] if err else "",
     "try: volec edit patch compiler/src/a.vl --old old_name --new new_name --all ; "
     "volec edit patch compiler/src/b.vl --old old_name --new new_name --all")
st, err = blocked("sed -i -E 's/\\bold\\b/new/g' compiler/src/a.vl")
case("sed -i word boundary", "edit patch compiler/src/a.vl:LINE --old 'TEXT' --new 'TEXT'" in err, True)
st, err = blocked("sed -i '' -e '12s/a(b)/a(c)/' compiler/src/a.vl")
case("sed -i -e with a line", "try: volec edit patch compiler/src/a.vl:12 --old 'a(b)' --new 'a(c)'" in err, False)
st, err = blocked("sed -i '' -e '12s/x - 1/x + 1/' compiler/src/a.vl")
case("sed -i -e plain", "try: volec edit patch compiler/src/a.vl:12 --old 'x - 1' --new 'x + 1'" in err, True)
case("sed -i test fixture", blocked("sed -i 's/a/b/' tests/run/loops.vl")[0], False)
case("sed -i docs", blocked("sed -i '' 's/a/b/' docs/refactor.md AGENTS.md")[0], False)
case("sed -i scratch copy", blocked("sed -i 's/a/b/' target/scratch/compiler/src/x.vl")[0], False)
case("sed -i tmp copy", blocked("sed -i 's/a/b/' /tmp/w/compiler/src/x.vl")[0], False)
case("python writes a test", blocked(
    "python3 - <<'EOF'\np = 'tests/refactor/patch.t'\nopen(p, 'w').write('x')\nEOF")[0], False)
case("python reads source", blocked("python3 tools/agent-tool-usage.py compiler/src/main.vl")[0], False)
case("sed -n is a read", blocked("sed -n 's/a/b/p' docs/x.md")[0], False)
case("volec edit patch", blocked(
    "target/volec edit patch compiler/src/range.vl:1615 --old 'a < b' --new 'a <= b'")[0], False)

# The escapes: `# no-tool:`, and the older `# no-query:`; the reason is logged.
st, err, recs = bash("sed -i 's/[a-z]*_old/new/' compiler/src/*.vl  # no-tool: a regex over every file")
case("escape no-tool", (st, [r["kind"] for r in recs], recs[0].get("reason") if recs else None),
     (0, ["edit-escape"], "a regex over every file"))
st, err, recs = bash("perl -pi -e 's/a/b/' compiler/src/x.vl  # no-query: merge conflict markers")
case("escape no-query", (st, [r["kind"] for r in recs]), (0, ["edit-escape"]))

# Edit and Write: never blocked, logged with whether the file existed.
for tool, inp in (("Edit", {"file_path": os.path.join(HERE, "query-first.py").replace(".py", ".vl"),
                            "old_string": "a", "new_string": "b"}),
                  ("Write", {"file_path": "/nonexistent/compiler/src/new.vl", "content": "fn f() {}\n"})):
    st, err, recs = run({"hook_event_name": "PreToolUse", "tool_name": tool, "cwd": HERE, "tool_input": inp})
    case(f"{tool} not blocked", (st, [r["kind"] for r in recs], recs[0]["existed"] if recs else None),
         (0, [tool.lower()], False))

# The tools' results: whether they wrote, and on what.
st, err, recs = bash("target/volec edit patch clamp --old a --new b", "PostToolUse",
                     "patched crate::range::clamp\tcompiler/src/range.vl\t+1 -1 lines\n")
case("tool written", [(r["kind"], r["tool"], r["written"], r["compiler"]) for r in recs],
     [("tool-result", "edit", True, True)])
st, err, recs = bash("target/volec edit patch clamp --old a --new b --dry-run", "PostToolUse",
                     "--- a/compiler/src/range.vl\n+++ b/compiler/src/range.vl\n")
case("tool dry run", [r["written"] for r in recs], [False])
st, err, recs = bash("target/volec refactor rename f g --root tests/refactor/edits/main.vl", "PostToolUse",
                     "renamed crate::f\tmain.vl\t+1 -1 lines\n")
case("tool on a test program", [(r["written"], r["compiler"]) for r in recs], [(True, False)])
st, err, recs = bash("target/volec undo", "PostToolUse", "undid patched crate::a\tcompiler/src/a.vl\t+1 -1 lines\n")
case("tool undo", [(r["tool"], r["written"], r["compiler"]) for r in recs], [("undo", True, True)])

# 0.15: volec through a copy, a shell variable, the tools binary.
st, err, recs = bash("T=target/tc0; $T edit patch clamp --old a --new b", "PostToolUse",
                     "patched crate::range::clamp\tcompiler/src/range.vl\t+1 -1 lines\n")
case("tool through $T", [(r["kind"], r["tool"], r["written"], r.get("via")) for r in recs],
     [("tool-result", "edit", True, "target/tc0")])
case("query through ${T}", [(r["kind"], r.get("via")) for r in bash("T=target/tc0 && ${T} query show f")[2]],
     [("query", "target/tc0")])
case("query through an unassigned $TC", [r.get("via") for r in bash('"$TC" query refs f')[2]], ["$VAR"])
case("query through a copy", [r.get("via") for r in bash("target/tc-new query def f --json")[2]],
     ["target/tc-new"])
case("query through the tools binary", [r.get("via") for r in bash("target/tools/volec query show f")[2]],
     [None])
case("not volec: tclsh, $X ls", [r["kind"] for r in bash("tclsh query.tcl; $X ls; tcpdump -i en0")[2]], [])
case("query inside $(...)", [r["kind"] for r in bash("n=$(volec query refs f --count)")[2]], ["query"])

# 0.12: writes are judged by the files written, not by every path named.
case("python writes a doc naming source", blocked(
    "python3 - <<'EOF'\nopen('compiler/README.md', 'w').write('see compiler/std/std.vl')\nEOF")[0], False)
case("python writes a scratch helper", blocked(
    "python3 - <<'EOF'\np = '/private/tmp/claude-1/scratchpad/h.py'\n"
    "open(p, 'w').write(\"run('compiler/src/main.vl')\")\nEOF")[0], False)
case("python writes source, variable", blocked(
    "python3 - <<'EOF'\nsrc = 'compiler/src/a.vl'\nopen(src, 'w').write('x')\nEOF")[0], True)
case("python write, file unknown", blocked(
    "python3 -c \"import sys; open(sys.argv[1], 'w').write('x')\" compiler/src/a.vl")[0], True)
st, err, recs = bash("sed -i '' 's/a/b/' target/patch.txt && target/volec edit patch "
                     "compiler/src/a.vl < target/patch.txt")
case("sed -i scratch input, no edit logged", (st, [r["kind"] for r in recs]), (0, []))
case("sed -i after cd into scratch", blocked("cd target/copy && sed -i 's/a/b/' compiler/src/x.vl")[0], False)
case("sed -i docs quoting a read", blocked(
    "sed -i '' \"s|grep x|sed -n '120,180p' compiler/src/gvn.vl; cat compiler/src/a.vl|\" docs/query.md")[0],
     False)
case("awk generating a program", blocked("awk -f tests/fuzz/gendiv.awk > target/fuzz/x.vl")[0], False)
case("grep of a generated program", blocked("grep -c add target/fuzz/x.vl")[0], False)
case("a script written by cat, then run: not a python rewrite (0.17)", blocked(
    "cat > /tmp/x/t.py <<'EOF'\nopen('compiler/src/a.vl', 'w').write('x')\nEOF\npython3 -I /tmp/x/t.py")[0], False)
case("python -c after an echo", blocked(
    "echo hi; python3 -c \"open('compiler/src/a.vl', 'w').write('x')\"")[0], True)
case("read with 2>&1", blocked("grep -n fn compiler/src/a.vl 2>&1")[0], True)

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
                         "tool_input": {"command": "target/volec query show f"}})
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
    with open(os.path.join(repo, "compiler", "src", "front", "big.vl"), "w") as fh:
        fh.write(big)
    with open(os.path.join(repo, "compiler", "src", "small.vl"), "w") as fh:
        fh.write("fn g() {}\n" * 20)
    prog = os.path.join(tmp, "ws")
    os.makedirs(os.path.join(prog, "scratch"))
    for name, text in (("main.vl", "mod util;\nfn main() {}\n" + big), ("util.vl", big),
                       ("probe.vl", big), ("scratch/diff.vl", big)):
        with open(os.path.join(prog, name), "w") as fh:
            fh.write(text)

    def at(cwd, command, phase="PreToolUse", stdout=""):
        return run({"hook_event_name": phase, "tool_name": "Bash", "cwd": cwd, "session_id": "qf-test",
                    "tool_input": {"command": command}, "tool_response": {"stdout": stdout, "stderr": ""}})
    st, err, recs = at(repo, "ls; cat compiler/src/front/big.vl; echo done")
    case("per command: the reading one named", (st, err.splitlines()[0]),
         (2, "blocked hook.query-first: `cat compiler/src/front/big.vl` (command 2 of 3 on the line; "
             "the others are not blocked) reads .vl source"))
    case("large file: its length and module", err.splitlines()[1].startswith(
        "compiler/src/front/big.vl is 400 lines (a file under 300 is read whole freely): "
        "`volec query items crate::front::big` lists its items"), True)
    case("blocked: the try lines logged", recs[-1].get("try"),
         ["volec query show compiler/src/front/big.vl (a whole small file) | volec query text "
          "compiler/src/front/big.vl:A-B", "volec query items crate::front::big"])
    st, err, recs = at(repo, "cat compiler/src/small.vl")
    case("small file: read whole", (st, [r["kind"] for r in recs]), (0, ["read-small"]))
    case("small file: sed -n", at(repo, "sed -n '1,5p' compiler/src/small.vl")[0], 0)
    case("small file: grep is still a search", at(repo, "grep -n g compiler/src/small.vl")[0], 2)
    case("a query on the line does not excuse a read",
         at(repo, "volec query show f; cat compiler/src/front/big.vl")[0], 2)
    case("a query and ls: not blocked", at(repo, "volec query items crate | head; ls compiler/src")[0], 0)
    case("program: main.vl is source", at(prog, "cat main.vl")[0], 2)
    case("program: a declared module is source", at(prog, "head -350 util.vl")[0], 2)
    st, err, recs = at(prog, "head -6 scratch/diff.vl")
    case("program: a scratch .vl is not", (st, [r["kind"] for r in recs]), (0, ["read-scratch"]))
    case("program: a probe next to main.vl is not", at(prog, "cat probe.vl")[0], 0)
    case("a variable on the line: scratch", at(repo, "S=/private/tmp/x/sp; cat $S/big.vl")[0], 0)
    case("a variable on the line: source", at(tmp, "W=%s; cat $W/compiler/src/front/big.vl" % repo)[0], 2)
    case("cd then a scratch file", at(repo, "cd %s && cat probe.vl" % prog)[0], 0)
    case("cd then source", at(tmp, "cd repo && cat compiler/src/front/big.vl")[0], 2)
    st, err, recs = at(repo, "sed -n '1,9p' compiler/src/front/big.vl  # no-query: need the line number for the Edit tool",
                       "PostToolUse")
    case("escape for Edit's line numbers: the reply", "edit insert --after NAME" in OUT[0]
         and "query def NAME" in OUT[0], True)
    for q in ("volec query show run_gvn", "volec query refs run_gvn"):
        at(repo, q, "PostToolUse", "x\n")
        case("repeat-query: not yet", OUT[0], "")
    at(repo, "volec query def run_gvn", "PostToolUse", "x\n")
    hint = json.loads(OUT[0])["hookSpecificOutput"]["additionalContext"] if OUT[0] else ""
    case("repeat-query: the hint, from hints.txt", hint,
         hook.hs.hint("repeat-query", NAME="run_gvn", VOLEC="volec"))
    case("repeat-query: the hint names context", "query context run_gvn" in hint, True)
    at(repo, "volec query show run_gvn", "PostToolUse", "x\n")
    case("repeat-query: once a session", OUT[0], "")

    # (E3) The hint at the moment of need: three lookups in a row on
    # related items; once a session; not after `query context`; off with
    # VOLE_HINTS=0.
    def post(session, command, stdout="x\n"):
        run({"hook_event_name": "PostToolUse", "tool_name": "Bash", "cwd": repo, "session_id": session,
             "tool_input": {"command": command}, "tool_response": {"stdout": stdout, "stderr": ""}})
        return json.loads(OUT[0])["hookSpecificOutput"]["additionalContext"] if OUT[0] else ""
    post("rel-1", "volec query show Lexer")
    post("rel-1", "volec query refs Lexer::next")
    case("related: a type and its method, then the method", post("rel-1", "volec query def next"),
         hook.hs.hint("repeat-query", NAME="Lexer", VOLEC="volec"))
    case("related: once a session", post("rel-1", "volec query show Lexer"), "")
    post("rel-2", "volec query show alpha")
    post("rel-2", "volec query show beta")
    case("unrelated names: no hint", post("rel-2", "volec query show gamma"), "")
    post("rel-3", "target/tools/volec query show alpha", "fn alpha() { beta(1) }\n")
    post("rel-3", "target/tools/volec query show beta", "fn beta(x: i64) { gamma(x) }\n")
    got = post("rel-3", "target/tools/volec query refs gamma")
    case("related through the answers: a callee's callee", got,
         hook.hs.hint("repeat-query", NAME="alpha", VOLEC="target/tools/volec"))
    case("the hint is a statement with the command", got.startswith("note: `target/tools/volec query "
                                                                    "context alpha` prints"), True)
    post("rel-4", "volec query context Lexer")
    post("rel-4", "volec query show Lexer")
    post("rel-4", "volec query refs Lexer")
    case("no hint once query context ran", post("rel-4", "volec query def Lexer"), "")
    os.environ["VOLE_HINTS"] = "0"
    post("rel-5", "volec query show Lexer")
    post("rel-5", "volec query refs Lexer")
    case("VOLE_HINTS=0: no hint", post("rel-5", "volec query def Lexer"), "")
    del os.environ["VOLE_HINTS"]

    # (E6) Rewrite mode: an unambiguous read runs as its query (updatedInput,
    # permission allow, a one-line note); anything else is blocked as before.
    tools = os.path.join(repo, "target", "tools")
    os.makedirs(tools)
    pathbin = os.path.join(tmp, "bin")
    os.makedirs(pathbin)
    for d in (tools, pathbin):
        with open(os.path.join(d, "volec"), "w") as fh:
            fh.write("#!/bin/sh\n")
        os.chmod(os.path.join(d, "volec"), 0o755)
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
    st, err = blocked("sed -n '120,180p' compiler/src/gvn.vl")
    case("block mode is the default", st, True)
    os.environ["VOLE_QUERY_MODE"] = "rewrite"
    st, o, cmd, recs = rewritten(repo, "sed -n '120,180p' compiler/src/front/big.vl")
    case("rewrite sed -n: query text", cmd, "target/tools/volec query text compiler/src/front/big.vl:120-180")
    case("rewrite: the shape", (o["hookEventName"], o["permissionDecision"], o["updatedInput"]["description"]),
         ("PreToolUse", "allow", "d"))
    case("rewrite: the first note says what the mode does", o["additionalContext"].startswith(
        "note hook.query-first: shell reads of large .vl files are answered with the matching query "
        "(sed -n, head, tail: `query text`; cat: `query items`; grep: `query refs` or `query grep`), "
        "each command of a line on its own, the others as typed; `sed -n"), True)
    st, o, cmd, recs = rewritten(repo, "sed -n '120,180p' compiler/src/front/big.vl")
    case("rewrite: the note after the first", o["additionalContext"],
         "note hook.query-first: `sed -n '120,180p' compiler/src/front/big.vl` ran as "
         "`target/tools/volec query text compiler/src/front/big.vl:120-180`: "
         "the same lines, each with its number")
    case("rewrite: logged", [(r["kind"], r["to"]) for r in recs if r["kind"] == "rewritten"],
         [("rewritten", cmd)])
    case("rewrite tail -n", rewritten(repo, "tail -n 50 compiler/src/front/big.vl")[2],
         "target/tools/volec query text compiler/src/front/big.vl:351-400")
    case("rewrite head -N, a program on PATH's volec", rewritten(prog, "head -350 util.vl")[2],
         "volec query text util.vl:1-350")
    st, o, cmd, _ = rewritten(repo, "cat compiler/src/front/big.vl")
    case("rewrite cat of a large file: its outline", cmd, "target/tools/volec query items crate::front::big")
    case("rewrite cat: the note says how to read more", "is 400 lines; this is its outline: `query show NAME`"
         in o["additionalContext"], True)
    case("rewrite cat in a program", rewritten(prog, "cat -n util.vl")[2], "volec query items crate::util")
    case("rewrite grep of a name", rewritten(repo, "grep -n f12 compiler/src/front/big.vl")[2],
         "target/tools/volec query refs f12 --in compiler/src/front/big.vl 2>/dev/null || "
         "target/tools/volec query grep f12 --in compiler/src/front/big.vl")
    case("rewrite grep -rnw of a name in the tree", rewritten(repo, "grep -rnw '\\bf12\\b' compiler/src")[2],
         "target/tools/volec query refs f12 2>/dev/null || target/tools/volec query grep f12")
    case("rewrite after cd", rewritten(tmp, "cd repo && sed -n 5,9p compiler/src/front/big.vl")[2],
         "cd repo && volec query text compiler/src/front/big.vl:5-9")
    os.makedirs(os.path.join(repo, "target"), exist_ok=True)
    shutil.copy(os.path.join(tools, "volec"), os.path.join(repo, "target", "volec"))
    post("rw-last", "target/volec query items crate")
    case("rewrite: the volec the agent ran last",
         rewritten(repo, "head -400 compiler/src/front/big.vl", "rw-last")[2],
         "target/volec query text compiler/src/front/big.vl:1-400")
    for amb in ("grep -n 'f1.*' compiler/src/front/big.vl", "grep -c f12 compiler/src/front/big.vl",
                "sed -n '1,5p;9p' compiler/src/front/big.vl", "sed -n '/fn/p' compiler/src/front/big.vl",
                "cat compiler/src/front/big.vl main.vl", "cd $X && cat compiler/src/front/big.vl"):
        case("ambiguous, still blocked: " + amb, rewritten(repo, amb)[0], 2)
    case("writes still blocked in rewrite mode",
         rewritten(repo, "sed -i '' 's/f1/g1/' compiler/src/front/big.vl")[0], 2)

    # (n8) Chained lines: each read of source becomes its query where it
    # stands, every other command, separator and pipe kept as typed. The
    # 26 lines blocked on compiler tasks 21-24 in iteration 3
    # (.claude/briefs/evalruns/iter/03-night017), verbatim, on a tree with
    # their files.
    T = "target/tools/volec"
    BIG = "".join("// line %d\n" % i for i in range(1, 420))
    files = {
        "compiler/src/middle/fold/mod.vl": BIG.replace("// line 87\n", "        Shl => wrap(a, ty),\n"),
        "compiler/src/middle/egraph.vl": BIG,
        "compiler/src/middle/ir/mod.vl": "pub mod cfg;\nuse crate::base::IntVec;\n" + BIG,
        "compiler/src/front/patterns/usefulness.vl": BIG,
        "compiler/std/io.vl": BIG.replace("// line 250\n", "    pub fn next_line(self: *Scanner) -> [u8] {\n"),
        "compiler/std/std.vl": BIG,
    }
    for name, text in files.items():
        os.makedirs(os.path.dirname(os.path.join(repo, name)), exist_ok=True)
        with open(os.path.join(repo, name), "w") as fh:
            fh.write(text)
    ITER3 = [
        "sed -n 1,60p docs/optimizer.md | cut -c1-400; echo ----; grep -n 'Shl\\|Shr\\|shl\\|shr' compiler/src/middle/fold/mod.vl | head -80; wc -l compiler/src/middle/fold/*.vl",
        'cd "$PWD" && git status --short | head; ls compiler/src/middle/ | head -50; grep -rn -i "shl\\|shr" compiler/src/middle/*.vl | head -80',
        'target/volec query show compiler/src/middle/ir/mod.vl 2>&1 | head -5; grep -n "^pub mod\\|^mod\\|^use\\|^import" compiler/src/middle/ir/mod.vl',
        'target/volec query context check_exhaustive 2>&1 | head -50; grep -n "range\\|Range\\|exhaust\\|non-exhaustive" compiler/src/front/patterns/usefulness.vl | head -120',
        'cd "$PWD" && grep -n -i "range\\|int\\|exhaust\\|non-exhaustive\\|wild" compiler/src/front/patterns/usefulness.vl | head -150',
        'cd "$PWD" && git status --short | head; ls; ls compiler/std | head -50; grep -rn "fn trim" compiler/std | head; cat compiler/std/embed.sh | head -40; sed -n 1,80p compiler/src/front/README.md',
        'cd "$PWD" && sed -n 60,120p compiler/std/embed.sh; echo ---; sed -n 90,120p compiler/std/io.vl; echo ---; ls compiler/std; echo ---; grep -n -i "std" compiler/src/front/README.md | sed -n 1,40p; echo ---; cat bootstrap/eval-build.sh | head -40; echo ---; ls tests/run | grep -i std | head -30',
        'cd "$PWD" && cat tests/run/std_text.vl; echo ---; grep -n "^#\\|trim" compiler/guide/std.md | head -60; echo ---; sed -n 1,30p compiler/guide/std.md | head -5; echo ---; grep -n "Some" compiler/std/*.vl | head -5; echo ---; git log --oneline | head -3; ls compiler/src/guide/',
        'cd "$PWD" && sed -n 90,130p compiler/std/io.vl && echo ---- && cat compiler/guide/std.md && echo ---- && sed -n 60,200p compiler/std/embed.sh && echo ---- && grep -n "std" tests/run.sh | head -30 && sed -n 1,40p tests/run.sh && echo ---- && ls tests/run | grep -i \'^std\' ; cat bootstrap/eval-build.sh | head -40',
        'cd "$PWD" && cat tests/run/std_text.vl && echo ---- && target/volec query refs Option::Some 2>/dev/null | head -5; grep -n "Some(\\|None" compiler/std/*.vl | head -20; echo ----; grep -n "fn next_line" -A25 compiler/std/io.vl | head -50',
        'ls compiler/src/middle/ | head -50; grep -n -i "shl\\|shift" docs/optimizer.md | head -20; grep -rn "Shl" compiler/src/middle/*.vl | head -40',
        "sed -n 300,470p compiler/src/middle/fold/mod.vl; target/volec query show shift_amount; target/volec query show wrap_int",
        'ls compiler/src/middle/; grep -rn -i "shl\\|Shl" compiler/src/middle/*.vl | head -60; ls target',
        'cp target/volec target/old-volec; target/volec query refs ir_make --count; target/volec query show emit_ir; ls compiler/src/middle/ir; grep -n "mod \\|^use" compiler/src/middle/ir/mod.vl | head -30',
        'grep -rn "ir_make" compiler/src | head; git status --short | head -40; cat compiler/src/middle/ir/build.vl | head -30',
        "cat compiler/src/front/patterns/usefulness.vl",
        'grep -n -i "range\\|Int\\|fn " compiler/src/front/patterns/usefulness.vl | head -150',
        'grep -n -i "int\\|range\\|fn " compiler/src/front/patterns/usefulness.vl | head -150',
        "sed -n 51,100p compiler/src/front/patterns/usefulness.vl; sed -n 200,525p compiler/src/front/patterns/usefulness.vl",
        'cd compiler/src/front/patterns; grep -n -i "range\\|int\\|fn " usefulness.vl | head -150',
        'cd compiler/src/front/patterns; grep -n -i "range\\|Int\\|fn \\|wild" usefulness.vl | head -200',
        'head -30 compiler/std/embed.sh; grep -rn "fn trim" compiler/std | head; grep -n "trim" compiler/guide/std.md | head',
        "sed -n 95,122p compiler/std/io.vl; sed -n 70,110p compiler/guide/std.md; ls tests/run | grep '^std' | head -3; head -20 tests/run.sh",
        'head -25 tests/run/std_input.vl; ls tests/run | grep -i std_input; grep -n "Some(" compiler/std/io.vl | head -3; sed -n 110,125p compiler/guide/std.md',
        'head -30 compiler/std/embed.sh; grep -rn "fn trim" compiler/std | head; ls compiler/std; grep -n "trim" compiler/guide/std.md | head',
        "sed -n 95,122p compiler/std/io.vl; sed -n 70,110p compiler/guide/std.md; ls tests/run | head -5; head -20 tests/run.sh",
    ]
    os.environ["VOLE_QUERY_MODE"] = "block"
    case("iteration 3: all 26 lines blocked in block mode", [blk for blk in ITER3 if at(repo, blk)[0] != 2], [])
    os.environ["VOLE_QUERY_MODE"] = "rewrite"
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
         "--in compiler/src/middle/fold/mod.vl --limit 80 | head -80; wc -l compiler/src/middle/fold/*.vl" % T)
    case("iter3: -i, DIR/*.vl, after cd \"$PWD\", head over 60: --limit", got[1],
         'cd "$PWD" && git status --short | head; ls compiler/src/middle/ | head -50; %s query grep shl Shl SHL '
         'shr Shr SHR --in compiler/src/middle --limit 80 | head -80' % T)
    case("iter3: ^KEYWORD: --code --word, the line's own volec", got[2],
         "target/volec query show compiler/src/middle/ir/mod.vl 2>&1 | head -5; target/volec query grep "
         "--word --code 'pub mod' mod use import --in compiler/src/middle/ir/mod.vl")
    case("iter3: grep -r of compiler/std: --in std", "%s query grep 'fn trim' --in std | head;" % T in got[5], True)
    case("iter3: sed -n of std, && kept", got[8].startswith(
        'cd "$PWD" && %s query text compiler/std/io.vl:90-130 && echo ---- && cat compiler/guide/std.md' % T), True)
    case("iter3: one name piped: refs or grep, grouped", "echo ---; { %s query refs Some --in std 2>/dev/null || "
         "%s query grep Some --in std; } | head -5; echo ---" % (T, T) in got[7], True)
    case("iter3: grep -A25 'fn NAME': the lines it prints (the line's own volec)", got[9].endswith(
        "echo ----; target/volec query text compiler/std/io.vl:250-275 | head -50"), True)
    case("iter3: a file that is not there: left as typed", got[14],
         "{ %s query refs ir_make 2>/dev/null || %s query grep ir_make; } | head; git status --short | head -40; "
         "cat compiler/src/middle/ir/build.vl | head -30" % (T, T))
    case("iter3: two sed -n of one file", got[18],
         "%s query text compiler/src/front/patterns/usefulness.vl:51-100; "
         "%s query text compiler/src/front/patterns/usefulness.vl:200-525" % (T, T))
    case("iter3: after cd into the module's directory: --root", got[19],
         "cd compiler/src/front/patterns; %s query grep range Range RANGE int Int INT 'fn ' 'Fn ' 'FN ' "
         "--in usefulness.vl --root %s --limit 150 | head -150"
         % (os.path.join(repo, T), os.path.join(repo, "compiler/src/main.vl")))
    st, o, cmd, recs = rewritten(repo, ITER3[0], "iter3-notes")
    notes = o["additionalContext"].split("\n")
    case("chain: one note line per part", (len(notes), notes[0].startswith("note hook.query-first: shell reads")),
         (1, True))
    st, o, cmd, recs = rewritten(repo, "sed -n 1,5p compiler/src/front/big.vl; grep -n Shl compiler/src/middle/fold/mod.vl",
                                 "iter3-notes")
    case("chain: a further part's note", o["additionalContext"].split("\n")[1],
         "note hook.query-first: also `grep -n Shl compiler/src/middle/fold/mod.vl` ran as `{ %s query refs Shl "
         "--in compiler/src/middle/fold/mod.vl 2>/dev/null || %s query grep Shl --in compiler/src/middle/fold/mod.vl; }`: "
         "`query refs Shl` lists its uses, each with its item; where Shl is no item, `query grep Shl` the lines "
         "holding it" % (T, T))
    case("chain: logged with its parts", [(r["kind"], r["parts"]) for r in recs if r["kind"] == "rewritten"],
         [("rewritten", 2)])

    st, o, cmd, recs = rewritten(repo, "cat compiler/src/front/nothere.vl | head -5", "missing")
    case("a file that is not there, alone: runs as typed", (st, cmd, [r["kind"] for r in recs]),
         (0, None, ["read-missing"]))

    # Pipes and readers folded: cat F | head, tail +N, sed 'A,$p', grep after cat.
    B = "compiler/src/front/big.vl"
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
            ("grep -n 'fn f12()' -A2 compiler/src/front/*.vl", "%s query text %s:13-15" % (T, B)),
            ("grep -rn 'fn f12()' -A1 compiler/src | head", "%s query text %s:13-14 | head" % (T, B)),
            ("sed -n 1,9p %s | cut -c1-80 | head -3" % B, "%s query text %s:1-9 | cut -c1-80 | head -3" % (T, B)),
            ("grep -n '\\bf12\\b\\|\\bf13\\b' %s" % B, "%s query grep --word f12 f13 --in %s" % (T, B)),
            ("grep -nF 'a.b(' %s" % B, "%s query grep 'a.b(' --in %s" % (T, B)),
            ("grep -n 'Some(' %s" % B, "%s query grep 'Some(' --in %s" % (T, B)),
            ("grep -in f12 %s" % B, "%s query grep f12 F12 --in %s" % (T, B)),
            ("grep -rn f12 --include='*.vl' compiler/src/front",
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
                "(cd compiler/src && grep -n f12 front/big.vl); grep -n f12 %s" % B,
                "grep -l f12 compiler/src", "grep -v f12 %s" % B, "grep -n f12 %s > /tmp/out" % B,
                "grep -n f12 %s compiler/src/middle/egraph.vl" % B, "grep -n 'f1$' %s" % B,
                "grep -C1 '0()' %s" % B, "grep -n '\\bf12' %s" % B, "rg -n f12 compiler/src",
                "grep -n '^// line' %s" % B, "W=compiler/src; grep -n f12 $W/front/big.vl $Q/x.vl",
                "cat %s | wc -l" % B, "grep -rn f12 compiler/src/*/*.vl",
                # (a program reads the output, or the grep's status: the query's differ)
                "grep -rn f12 compiler/src | wc -l", "grep -rn f12 compiler/src | head | sort",
                "echo $(sed -n 1,5p %s)" % B, "grep -rn f12 compiler/src && echo found",
                "grep -rn -e f12 compiler/src || echo none", "diff <(sed -n 1,5p %s) x" % B):
        case("in doubt, blocked: " + amb, rewritten(repo, amb, "doubt")[0], 2)
    st, err, recs = at(repo, "sed -n 1,5p %s; grep -n 'f1.*' %s; ls" % (B, B))
    case("blocked: the translated parts named", (st, err.splitlines()[0], err.splitlines()[-2]),
         (2, "blocked hook.query-first: `grep -n 'f1.*' compiler/src/front/big.vl` (command 2 of 3 on the line; "
             "the others are not blocked) reads .vl source",
          "the line's other reads of .vl source run as their queries on a retry: `sed -n 1,5p %s` as "
          "`%s query text %s:1-5`" % (B, T, B)))
    case("blocked: logged with what translated", recs[-1].get("translated"), ["%s query text %s:1-5" % (T, B)])
    st, err, recs = at(repo, "grep -n 'f1.*' %s; grep -c f2 %s" % (B, B))
    case("blocked: each blocked read of the line gets its try", err.splitlines()[0:1] + [
        l for l in err.splitlines() if l.startswith("also blocked")],
         ["blocked hook.query-first: `grep -n 'f1.*' compiler/src/front/big.vl` (command 1 of 2 on the line) "
          "reads .vl source",
          "also blocked: `grep -c f2 compiler/src/front/big.vl` (command 2 of 2 on the line); try: "
          "volec query refs f2 | volec query grep f2"])
    del os.environ["VOLE_QUERY_MODE"]
    os.environ["PATH"] = old_path
shutil.rmtree(STATE, ignore_errors=True)

print("total", "ok" if FAILED == 0 else f"{FAILED} failed")
sys.exit(1 if FAILED else 0)
