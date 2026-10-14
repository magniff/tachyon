#!/usr/bin/env python3
"""How agents worked on tachyon: every shell command, search and file read
from the development transcripts, classified by what it was for, so that
the common ones can become compiler queries (see docs/agents.md).

usage: tools/agent-tool-usage.py TRANSCRIPT_DIR [--csv OUT.csv]
       tools/agent-tool-usage.py --hook-log .git/agent-tools.jsonl

TRANSCRIPT_DIR holds the session transcripts (*.jsonl, subagents/ too).
Prints a markdown report on stdout. Development tooling only: not part of
the build, and nothing in the bootstrap depends on it.
"""
import csv
import json
import os
import re
import shlex
import sys
import types
from collections import Counter, defaultdict

# (0.15) tachyonc through copies (target/tc0) and shell variables ($T):
# tools/agent-hooks/tachyonc_cmd.py, shared with the hooks.
tc = types.ModuleType("tachyonc_cmd")
tc.__file__ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "agent-hooks", "tachyonc_cmd.py")
with open(tc.__file__) as _fh:
    exec(compile(_fh.read(), tc.__file__, "exec"), tc.__dict__)

SOURCE_HINT = re.compile(r"\.tach\b|compiler/src|compiler/std|tests/run|examples/|bench/")

# What a source-inspecting command was for, and the compiler query that
# would answer it directly.
CATEGORIES = [
    ("find-definition", "where is NAME defined",
     "tachyonc query def NAME (file:line, signature)"),
    ("find-references", "who uses NAME",
     "tachyonc query refs NAME / callers NAME"),
    ("list-items", "what does this module or file contain",
     "tachyonc query items MODULE (signatures, no bodies)"),
    ("show-item", "show the source of a function or type by name",
     "tachyonc query show NAME (the item's source, with its doc comment)"),
    ("read-range", "show lines N..M of a file",
     "tachyonc query show NAME (the item's source)"),
    ("extract-section", "a section of a document between two markers",
     "(docs: tachyonc doc TOPIC)"),
    ("count", "how many matches or lines",
     "tachyonc query refs --count / --stats"),
    ("mechanical-edit", "a rename or rewrite with sed/perl/python",
     "tachyonc refactor rename / fix-* rewrites"),
    ("check-output", "inspect what the compiler emitted (IR, asm)",
     "--emit-ir / --emit-mir / -S, with filters by function"),
    ("other-source", "other reads of source",
     ""),
]
CAT_INDEX = {c[0]: c for c in CATEGORIES}

DEF_WORDS = re.compile(r"\b(fn|struct|enum|const|static|trait|impl|type|mod|union)\b")


HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n.*?\n\s*\1\s*(\n|$)", re.S)


def split_segments(command):
    """The simple commands of a shell command line (pipes, ;, &&, ||),
    here-documents left out (their lines are data, not commands)."""
    command = HEREDOC.sub("<<HEREDOC\n", command)
    parts = re.split(r"\|\||&&|;|\||\n", command)
    return [p.strip() for p in parts if p.strip()]


def program_of(segment):
    try:
        words = shlex.split(segment, posix=True)
    except ValueError:
        words = segment.split()
    while words and ("=" in words[0] and not words[0].startswith("-")):
        words = words[1:]  # VAR=value prefixes
    if not words:
        return "", []
    prog = os.path.basename(words[0])
    if prog in ("time", "env", "nice", "command"):
        return program_of(" ".join(words[1:]))
    return prog, words[1:]


def classify(prog, args, segment, description):
    text = segment
    if prog in ("grep", "rg", "egrep"):
        if "-c" in args or "--count" in args:
            return "count"
        pattern = next((a for a in args if not a.startswith("-")), "")
        context = any(re.match(r"-[ABC]\d*$", a) or a in ("-A", "-B", "-C") for a in args)
        if (DEF_WORDS.search(pattern) or "^fn" in pattern) and context:
            return "show-item"
        if DEF_WORDS.search(pattern) or "^fn" in pattern or "^pub fn" in pattern:
            if re.search(r"\^(pub )?\(?fn|\^\(pub \)\?fn|\^\s*(pub )?(fn|struct|enum)", pattern) and not re.search(r"\w{3,}", pattern.replace("fn", "").replace("pub", "").replace("struct", "").replace("enum", "")):
                return "list-items"
            return "find-definition"
        if re.search(r"^\^?#+", pattern) or pattern.startswith("^#"):
            return "extract-section"
        return "find-references"
    if prog == "sed":
        if "-i" in args or any(a.startswith("-i") for a in args):
            return "mechanical-edit"
        if "-n" in args:
            return "read-range"
        return "mechanical-edit"
    if prog == "perl":
        return "mechanical-edit" if any(a.startswith("-p") or a.startswith("-i") for a in args) else "other-source"
    if prog == "awk":
        prog_text = " ".join(args)
        if re.search(r"/[^/]+/\s*,\s*/", prog_text) or "p=1" in prog_text:
            return "extract-section"
        if "NR" in prog_text:
            return "read-range"
        return "other-source"
    if prog in ("head", "tail", "cat", "less", "more"):
        return "read-range"
    if prog == "wc":
        return "count"
    if prog in ("python3", "python"):
        return "mechanical-edit" if re.search(r"write|replace|sub\(", text) else "other-source"
    if prog == "tachyonc" or "tachyonc" in prog:
        if re.search(r"--emit-(ir|mir|asm)|-S\b|--print", text):
            return "check-output"
    return None


def iter_transcripts(root):
    for dirpath, _, files in os.walk(root):
        for f in files:
            if f.endswith(".jsonl"):
                yield os.path.join(dirpath, f)


def hook_report(path):
    """Summary of the query-first hook's log (tools/agent-hooks/query-first.py):
    how often agents used `tachyonc query`, were blocked, or went around it,
    and why."""
    recs = []
    with open(path, errors="replace") as fh:
        for line in fh:
            try:
                recs.append(json.loads(line))
            except ValueError:
                pass
    kinds = Counter(r.get("kind") for r in recs)
    print("## The query-first hook\n")
    print("| event | count |\n|---|---|")
    for k in ("query", "query-result", "blocked", "escape", "feedback", "read", "grep", "edit", "write", "multiedit",
              "read-unenforced", "tool-result", "edit-blocked", "edit-escape"):
        if kinds.get(k):
            print(f"| {k} | {kinds[k]} |")
    subs = Counter()
    for r in recs:
        if r.get("kind") == "query":
            m = re.search(r"query\s+(\w+)", r.get("command", ""))
            if m:
                subs[m.group(1)] += 1
    if subs:
        print("\nQueries by command: " + ", ".join(f"`{k}` {v}" for k, v in subs.most_common()))
    empty = [r for r in recs if r.get("kind") == "query-result" and (r.get("out_lines", 0) == 0 or r.get("stderr"))]
    if empty:
        print(f"\nQueries that answered nothing or failed: {len(empty)}\n")
        for r in empty[:15]:
            print(f"- `{r.get('command','')[:100]}` {r.get('stderr','')[:100]}")
    fb = [r for r in recs if r.get("kind") == "feedback"]
    if fb:
        print(f"\n## Feedback on the tools ({len(fb)})\n")
        for r in fb:
            print(f"- **{r.get('tool','')}**: {r.get('message','')}")
    esc = [r for r in recs if r.get("kind") == "escape"]
    if esc:
        print(f"\n## Where query was not enough ({len(esc)})\n")
        for r in esc:
            print(f"- {r.get('reason','')}  \n  `{r.get('command','')[:120]}`")
    edit_report(recs)


def path_kind(path):
    """What a file is: compiler (its source: compiler/src, compiler/std),
    tests (fixtures), docs, scratch (target/, /tmp) or other."""
    if SCRATCH.search(path):
        return "scratch"
    if re.search(r"(^|/)compiler/(src|std)/", path):
        return "compiler"
    if re.search(r"(^|/)tests/", path):
        return "tests"
    if path.endswith(".md") or re.search(r"(^|/)docs/", path):
        return "docs"
    return "other"


SCRATCH = re.compile(r"(^|/)(target|tmp|private/tmp|var/folders)/")
PATHS = re.compile(r"[\w./~*-]*\.(?:tach|md|t)\b")


def edit_report(recs):
    """Edits to existing compiler source by the tools, against shell
    rewrites and the Edit and Write tools; the other edits apart."""
    counted = Counter()   # how -> edits of existing compiler source
    per_agent = defaultdict(Counter)  # who -> how -> edits
    by_tool = Counter()
    other = Counter()     # what -> edits not counted
    reasons = []
    for r in recs:
        kind = r.get("kind")
        before = Counter(counted)
        tally_edit(r, kind, counted, by_tool, other, reasons)
        for how, n in (counted - before).items():
            per_agent[agent_key(r)][how] += n
    print_edit_report(counted, by_tool, other, reasons, per_agent)


def agent_key(r):
    """Who made a record: the harness's agent id, else the checkout (a
    parallel agent's worktree), else the session (0.11's records)."""
    if r.get("agent_id"):
        return r["agent_id"]
    if r.get("worktree"):
        return os.path.basename(r["worktree"].rstrip("/")) or r["worktree"]
    return "session " + (r.get("session") or "?")


def tally_edit(r, kind, counted, by_tool, other, reasons):
    """Counts record r (of kind) in the edit report's tallies."""
    if True:
        if kind == "tool-result":
            if not r.get("written"):
                other["tool dry runs, plans and refusals (nothing written)"] += 1
            elif r.get("compiler"):
                counted["tools"] += 1
                by_tool[r.get("tool", "?")] += 1
            else:
                other["tool edits of test or scratch programs"] += 1
        elif kind in ("edit", "edit-escape") and "command" in r:
            # (a shell rewrite: sed -i, perl -pi, python; it ran)
            command = r.get("command", "")
            files = r.get("files") or PATHS.findall(command)
            # (relative to the directory a `cd` went to)
            cd = re.findall(r"\bcd\s+(\S+)", command)
            if cd and not r.get("files"):
                files = [f if f.startswith("/") else cd[-1].rstrip("/") + "/" + f for f in files]
            kinds = {path_kind(f) for f in files} or {"other"}
            if "compiler" in kinds:
                counted["shell"] += 1
                if kind == "edit-escape":
                    reasons.append(r)
            else:
                other["shell rewrites of " + sorted(kinds)[0]] += 1
        elif kind == "edit-blocked":
            other["shell rewrites blocked (nothing written)"] += 1
        elif kind in ("edit", "multiedit", "write") and "target" in r:
            k = path_kind(r.get("target", ""))
            existed = r.get("existed", True if kind != "write" else None)
            if k == "compiler" and existed:
                counted["Edit" if kind != "write" else "Write"] += 1
            elif k == "compiler" and existed is None:
                other["Write of compiler source, before existence was logged"] += 1
            elif k == "compiler":
                other["new compiler files (Write)"] += 1
            else:
                other[f"{kind.capitalize()} of {k}"] += 1


def print_edit_report(counted, by_tool, other, reasons, per_agent):
    total = sum(counted.values())
    print("\n## Edits to existing compiler source\n")
    print("Compiler source is compiler/src and compiler/std; new files, test "
          "fixtures, docs and scratch programs (target/, /tmp) are apart.\n")
    print("| how | edits |\n|---|---|")
    tools = ", ".join(f"{k} {v}" for k, v in by_tool.most_common())
    print(f"| `tachyonc` edit, refactor, fix, rewrite, undo (written){': ' + tools if tools else ''} | {counted['tools']} |")
    print(f"| shell rewrites run (`sed -i`, `perl -pi`, Python) | {counted['shell']} |")
    print(f"| Edit tool | {counted['Edit']} |")
    print(f"| Write tool, over an existing file | {counted['Write']} |")
    if total:
        print(f"\n**Tool edits: {counted['tools']} of {total}, {100 * counted['tools'] / total:.0f}%** "
              "(the tools against shell rewrites and Edit/Write of existing compiler files).")
    else:
        print("\n**Tool edits: no edits of existing compiler source logged.**")
    if len(per_agent) > 1:
        print("\nPer agent (the harness's agent id, else its worktree, else its session):\n")
        print("| agent | tools | shell | Edit | Write | tool share |\n|---|---|---|---|---|---|")
        for who, c in sorted(per_agent.items(), key=lambda kv: -sum(kv[1].values())):
            n = sum(c.values())
            print(f"| {who} | {c['tools']} | {c['shell']} | {c['Edit']} | {c['Write']} | "
                  f"{100 * c['tools'] / n:.0f}% |")
    if other:
        print("\nNot counted:\n\n| what | count |\n|---|---|")
        for k, v in other.most_common():
            print(f"| {k} | {v} |")
    if reasons:
        print(f"\nWhy the shell (`# no-tool:`), {len(reasons)}:\n")
        for r in reasons[:30]:
            print(f"- {r.get('reason', '')}  \n  `{r.get('command', '')[:120]}`")


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--hook-log":
        hook_report(sys.argv[2])
        return
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    root = sys.argv[1]
    csv_out = sys.argv[sys.argv.index("--csv") + 1] if "--csv" in sys.argv else None
    rows = []
    tool_counts = Counter()
    prog_counts = Counter()
    tach_subs = Counter()
    tach_via = Counter()
    for path in iter_transcripts(root):
        who = "main session" if "subagents" not in path else "agent " + os.path.basename(path)[6:14]
        with open(path, errors="replace") as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                msg = d.get("message") or {}
                content = msg.get("content")
                if d.get("type") != "assistant" or not isinstance(content, list):
                    continue
                for b in content:
                    if b.get("type") != "tool_use":
                        continue
                    name = b.get("name")
                    inp = b.get("input") or {}
                    tool_counts[name] += 1
                    if name == "Bash":
                        cmd = inp.get("command", "")
                        desc = inp.get("description", "")
                        for sub, _, path, _ in tc.calls(cmd):
                            tach_subs[sub] += 1
                            if os.path.basename(path) != "tachyonc":
                                tach_via[path or "$VAR"] += 1
                        assigns = {}
                        for seg in split_segments(cmd):
                            prog, args = program_of(seg)
                            if not prog:
                                continue
                            # (0.15) a copy or a variable running tachyonc
                            if tc.program_name(seg, assigns) == "tachyonc":
                                prog = "tachyonc"
                            prog_counts[prog] += 1
                            if not SOURCE_HINT.search(seg) and prog not in ("tachyonc",) and "tachyonc" not in prog:
                                continue
                            cat = classify(prog, args, seg, desc)
                            if cat:
                                rows.append((who, "Bash:" + prog, cat, seg[:200], desc[:160]))
                    elif name in ("Grep", "Read", "Glob"):
                        target = inp.get("path") or inp.get("file_path") or inp.get("pattern") or ""
                        pattern = inp.get("pattern", "")
                        if not SOURCE_HINT.search(target + " " + pattern) and not target.endswith(".tach"):
                            continue
                        if name == "Read":
                            cat = "read-range"
                        elif name == "Glob":
                            cat = "list-items"
                        else:
                            cat = "find-definition" if DEF_WORDS.search(pattern) else "find-references"
                        rows.append((who, name, cat, (pattern + " " + target)[:200], ""))
    if csv_out:
        with open(csv_out, "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["who", "tool", "category", "command", "description"])
            w.writerows(rows)
    by_cat = defaultdict(list)
    for r in rows:
        by_cat[r[2]].append(r)
    print("## Totals\n")
    print("| tool | calls |\n|---|---|")
    for t, n in tool_counts.most_common(12):
        print(f"| {t} | {n} |")
    print("\nPrograms run from the shell (every simple command of every command line):\n")
    print("| program | runs |\n|---|---|")
    for p, n in prog_counts.most_common(25):
        print(f"| `{p}` | {n} |")
    if tach_subs:
        print("\n`tachyonc` invocations by subcommand (copies and shell variables included"
              f"{': ' + str(sum(tach_via.values())) + ' through ' + ', '.join(f'`{p}`' for p, _ in tach_via.most_common(4)) if tach_via else ''}):\n")
        print("| subcommand | runs |\n|---|---|")
        for sub, n in tach_subs.most_common():
            print(f"| {sub} | {n} |")
    print(f"\n## Reading and editing tachyon source: {len(rows)} operations\n")
    print("| purpose | operations | share | what could answer it |\n|---|---|---|---|")
    for key, what, query in CATEGORIES:
        n = len(by_cat.get(key, []))
        if n:
            print(f"| {key}: {what} | {n} | {100 * n / len(rows):.0f}% | {query} |")
    print("\n## Examples per purpose\n")
    for key, what, _ in CATEGORIES:
        items = by_cat.get(key, [])
        if not items:
            continue
        print(f"### {key}\n")
        seen = set()
        shown = 0
        for who, tool, _, cmd, desc in items:
            sig = (tool, re.sub(r"\d+", "N", cmd)[:60])
            if sig in seen:
                continue
            seen.add(sig)
            line = f"- `{tool}` `{cmd[:110]}`"
            if desc:
                line += f": {desc[:90]}"
            print(line)
            shown += 1
            if shown >= 8:
                break
        print()


if __name__ == "__main__":
    main()
