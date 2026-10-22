"""(0.18) The post-task debrief (`+debrief`) and its report.

After a run's task is over (pass or fail), the same session gets one more
message (prompts/debrief.md): what in the language confused it, which
diagnostics helped or misled, what it would change, and three ratings
out of 5 (readability, ease of getting it correct, confidence in the
result). The Rust condition is asked the same about Rust, the baseline.

How it is kept apart from the task (lib/claude_backend.py): the prompt
goes in on stdin (stream-json), so the debrief is a second user message
of the same session, its cache warm (one request, mostly cache reads);
its events go to debrief.jsonl, not transcript.jsonl, so every task
metric (turns, tokens, cost, anatomy) is the task's alone; its cost is
the session's total after it minus the task's (result.json's
`debrief.cost_usd`). The workspace is snapshotted when the task's turn
ends and put back after the debrief, before the grading, so nothing the
agent does in the debrief can change the grade.

    run.py debrief RUNDIR... [--md FILE] [--quotes N]

groups the answers by theme (keywords, no model), the ratings per model
and condition, the diagnostic codes named, and lists every answer per
task."""

import json
import os
import re
import shutil
import statistics
import subprocess
import sys
from collections import Counter, defaultdict

from lib.common import PROMPTS_DIR

FIELDS = ("CONFUSING", "DIAGNOSTICS", "CHANGE")
RATINGS = ("READABILITY", "EASE", "CONFIDENCE")


def prompt_for(cond):
    """The debrief's text for a condition (lib/conds.Cond)."""
    lang = {"rust": "Rust", "compiler": "vole and its tools (volec)"}.get(
        cond.lang, "vole")
    with open(os.path.join(PROMPTS_DIR, "debrief.md")) as fh:
        return fh.read().strip().replace("@LANG@", lang)


# ---------------------------------------------------------------- workspace

def snapshot(ws, snap):
    """A copy of the workspace as the task left it (APFS clones on macOS)."""
    if os.path.exists(snap):
        shutil.rmtree(snap)
    if sys.platform == "darwin":
        p = subprocess.run(["cp", "-cR", ws, snap], capture_output=True)
        if p.returncode == 0:
            return
        shutil.rmtree(snap, ignore_errors=True)
    shutil.copytree(ws, snap, symlinks=True)


def restore(ws, snap):
    """The workspace back as the task left it (after the leftover processes
    were killed): whatever the debrief turn did to it is undone."""
    shutil.rmtree(ws, ignore_errors=True)
    os.rename(snap, ws)


# ---------------------------------------------------------------- parsing

_LABEL = re.compile(r"^[\s>*_#-]*(%s)[\s*_]*:[\s*_]*" % "|".join(FIELDS + RATINGS),
                    re.M | re.I)
_RATING = re.compile(r"(\d(?:\.\d+)?)\s*(?:/|out of)\s*5")


def parse_answer(text):
    """{FIELD: text, RATING: number or None} from an answer in the asked form
    (labels in any case, with markdown emphasis); fields not found are None."""
    out = {k: None for k in FIELDS + RATINGS}
    if not text:
        return out
    marks = [(m.start(), m.end(), m.group(1).upper()) for m in _LABEL.finditer(text)]
    for i, (_, end, label) in enumerate(marks):
        stop = marks[i + 1][0] if i + 1 < len(marks) else len(text)
        val = text[end:stop].strip()
        if label in RATINGS:
            m = _RATING.search(val) or re.match(r"(\d(?:\.\d+)?)\b", val)
            out[label] = float(m.group(1)) if m and 0 <= float(m.group(1)) <= 5 else None
        elif out[label] is None:
            out[label] = val
    return out


# ---------------------------------------------------------------- themes

# (name, pattern): a keyword grouping, no model. Patterns are searched in
# one field's text, case-insensitively; an answer counts once per theme.
THEMES = [
    ("moves / ownership", r"\bmov(e|ed|es|ing)\b|ownership|\bown\.|\bowned\b|use after move"),
    ("references & / &mut / borrows", r"&mut|&\s?T\b|\breferences?\b|\bborrow"),
    ("drops / free / defer", r"\bdrop|\bfree\b|\bdefer\b|destructor"),
    ("views / slices", r"\bviews?\b|\bslices?\b|as_slice|as_mut_slice|\[u8\]|\[T\]"),
    ("raw pointers *T", r"raw pointer|\*T\b|\*Self|pointer"),
    ("allocators / gpa / _in", r"\bgpa\b|allocator|_in\b|new_in|explicit alloc"),
    ("text: no String/char, [u8], Buf", r"\bString\b|\bchar\b|&str|\bBuf\b|\btext\b|strings?\b"),
    ("self written out (self: &T)", r"self:\s|explicit self|\bself\b"),
    ("std API / names / prelude", r"\bstd\b|prelude|standard library|\bAPI\b|method name|Scanner|HashMap|get_or_insert"),
    ("indexing / get / set / len", r"\bv\.get|\.set\(|\bget\(|indexing|\.len\b|len\(\)"),
    ("integers / usize / wrapping", r"\busize\b|\bi64\b|wrap|overflow|integer|cast|\bas\b i"),
    ("f-strings / printing / macros", r"f-string|f\"|println|format|macro"),
    ("modules / use / imports", r"\bmod\b|\buse\b|import|module"),
    ("traits / generics / impl", r"\btraits?\b|generic|\bimpl\b|Display|Ord\b"),
    ("closures / iterators", r"closure|iterator|\.iter\(|\.map\(|collect"),
    ("match / enums / patterns", r"\bmatch\b|\benums?\b|pattern|exhaustive"),
    ("unsafe", r"\bunsafe\b"),
    ("contracts (requires/ensures)", r"\bcontracts?\b|\brequires\b|\bensures\b|invariant|contract\."),
    ("tests (#[test], volec test)", r"#\[test\]|\btests?\b|volec test|test\."),
    ("distinct types", r"\bdistinct\b|newtype|distinct\."),
    ("lifetimes (Rust)", r"lifetime|'a\b|borrow checker|borrowck"),
    ("guide / docs / lookup", r"\bguide\b|docs?\b|documentation|--find|lookup"),
    ("diagnostic: helpful", r"help(ed|ful)|clear|precise|try:|suggest|pointed"),
    ("diagnostic: misleading", r"mislead|confus|wrong|unclear|cryptic|vague|unhelpful|noisy"),
    ("nothing / none", r"^\s*\"?(nothing|none|n/a)\b"),
]
_THEMES = [(n, re.compile(p, re.I | re.M)) for n, p in THEMES]
CODE = re.compile(r"\b((?:own|contract|test|distinct|edit|query|fix|patch|unsafe|alloc)"
                  r"\.[a-z][a-z0-9_-]*|E0\d{3})\b")


def themes_of(text):
    return [n for n, p in _THEMES if text and p.search(text)]


def quote(text, theme, width=170):
    """The sentence of text that matches the theme, cut to width."""
    pat = dict(_THEMES)[theme]
    for sent in re.split(r"(?<=[.;!?])\s+", text):
        if pat.search(sent):
            s = " ".join(sent.split())
            return s if len(s) <= width else s[:width - 3] + "..."
    s = " ".join(text.split())
    return s[:width]


# ---------------------------------------------------------------- report

def load(dirs):
    runs = []
    for d in dirs:
        for root, _, files in os.walk(d):
            if "result.json" not in files:
                continue
            with open(os.path.join(root, "result.json")) as fh:
                r = json.load(fh)
            db = r.get("debrief")
            if not db or r.get("dry_run"):
                continue
            r["_dir"] = root
            r["_parsed"] = parse_answer(db.get("answer"))
            runs.append(r)
    runs.sort(key=lambda r: (r["task"], r["model"], r["cond"], r.get("rep", 0)))
    return runs


def _cell(r):
    return "%s %s" % (r["model"].split(":")[-1], r["cond"])


def _med(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def _mean(xs):
    xs = [x for x in xs if x is not None]
    return statistics.mean(xs) if xs else None


def _f(x, fmt="%.2f"):
    return "-" if x is None else fmt % x


def report(runs, quotes=3):
    out = []
    w = out.append
    asked = [r for r in runs if r["debrief"].get("sent")]
    answered = [r for r in asked if r["debrief"].get("answer")]
    cells = sorted({_cell(r) for r in runs})
    w("# Debrief report\n")
    w("%d runs with +debrief, %d asked, %d answered (a run that timed out is not asked). "
      "Themes are keyword groups over each field (lib/debrief.py THEMES), counted once per "
      "answer; a theme's share is of the cell's answers.\n" % (len(runs), len(asked),
                                                                len(answered)))
    # cost
    w("## Cost of the debrief\n")
    w("| cell | answered | median words | median debrief cost | debrief / task cost "
      "(median) | tool calls in debriefs |")
    w("|---|---|---|---|---|---|")
    for c in cells:
        rs = [r for r in asked if _cell(r) == c]
        ratios = [r["debrief"].get("cost_usd") / r["cost_usd"] for r in rs
                  if r["debrief"].get("cost_usd") is not None and r.get("cost_usd")]
        w("| %s | %d/%d | %s | %s | %s | %d |" % (
            c, sum(1 for r in rs if r["debrief"].get("answer")), len(rs),
            _f(_med([r["debrief"].get("words") for r in rs]), "%.0f"),
            _f(_med([r["debrief"].get("cost_usd") for r in rs]), "$%.4f"),
            _f(_med(ratios), "%.3f"),
            sum(r["debrief"].get("tool_calls") or 0 for r in rs)))
    # ratings
    w("\n## Ratings (out of 5; mean, with the passed runs' mean and the failed runs' "
      "in brackets)\n")
    w("| cell | n | readability | ease | confidence | confidence: passed / failed |")
    w("|---|---|---|---|---|---|")
    for c in cells:
        rs = [r for r in answered if _cell(r) == c]
        p = [r for r in rs if r.get("success")]
        f = [r for r in rs if not r.get("success")]
        conf = lambda xs: _mean([r["_parsed"]["CONFIDENCE"] for r in xs])
        w("| %s | %d | %s | %s | %s | %s / %s |" % (
            c, len(rs), _f(_mean([r["_parsed"]["READABILITY"] for r in rs])),
            _f(_mean([r["_parsed"]["EASE"] for r in rs])), _f(conf(rs)),
            _f(conf(p)), _f(conf(f))))
    w("\nPer task (mean readability / ease / confidence):\n")
    tasks = sorted({r["task"] for r in answered})
    w("| task | " + " | ".join(cells) + " |")
    w("|---|" + "---|" * len(cells))
    for t in tasks:
        row = []
        for c in cells:
            rs = [r for r in answered if r["task"] == t and _cell(r) == c]
            row.append("-" if not rs else "%s / %s / %s" % tuple(
                _f(_mean([r["_parsed"][k] for r in rs]), "%.1f") for k in RATINGS))
        w("| %s | %s |" % (t, " | ".join(row)))
    # themes
    for field in FIELDS:
        w("\n## %s: themes\n" % field.capitalize())
        hits = defaultdict(lambda: defaultdict(list))  # theme -> cell -> runs
        for r in answered:
            for th in themes_of(r["_parsed"][field] or ""):
                hits[th][_cell(r)].append(r)
        n_by = Counter(_cell(r) for r in answered)
        order = sorted(hits, key=lambda th: -sum(len(v) for v in hits[th].values()))
        w("| theme | " + " | ".join(cells) + " |")
        w("|---|" + "---|" * len(cells))
        for th in order:
            w("| %s | %s |" % (th, " | ".join(
                "%d (%.0f%%)" % (len(hits[th][c]), 100.0 * len(hits[th][c]) / n_by[c])
                if hits[th][c] else "-" for c in cells)))
        if quotes:
            w("")
            for th in order:
                w("- **%s**" % th)
                for c in cells:
                    for r in hits[th][c][:quotes]:
                        w("  - %s, %s rep%s: \"%s\"" % (c, r["task"], r.get("rep"),
                                                      quote(r["_parsed"][field], th)))
    # codes
    codes = defaultdict(Counter)
    for r in answered:
        for m in CODE.finditer(r["debrief"].get("answer") or ""):
            codes[_cell(r)][m.group(1)] += 1
    w("\n## Diagnostic codes the answers name\n")
    for c in cells:
        if codes[c]:
            w("- %s: %s" % (c, ", ".join("`%s` %d" % kv for kv in codes[c].most_common(15))))
    if not any(codes.values()):
        w("(none)")
    # unparsed
    bad = [r for r in answered if all(r["_parsed"][k] is None for k in FIELDS)]
    if bad:
        w("\n%d answers not in the asked form (listed raw below).\n" % len(bad))
    # raw
    w("\n## The answers, per task\n")
    for t in sorted({r["task"] for r in runs}):
        w("### %s\n" % t)
        for r in [r for r in runs if r["task"] == t]:
            db = r["debrief"]
            w("**%s rep%s** (%s, %s/%s tests, %s turns; debrief %s words, %s)\n" % (
                _cell(r), r.get("rep"), "passed" if r.get("success") else "FAILED",
                r.get("tests_passed"), r.get("tests_total"), r.get("turns"),
                db.get("words"), _f(db.get("cost_usd"), "$%.4f")))
            if db.get("answer"):
                w("\n".join("> " + line for line in db["answer"].splitlines()) + "\n")
            else:
                w("> (no answer: %s)\n" % db.get("error"))
    return "\n".join(out) + "\n"


def main(args):
    runs = load(args.rundirs)
    if not runs:
        print("no run with a debrief under %s" % " ".join(args.rundirs), file=sys.stderr)
        return 1
    text = report(runs, args.quotes)
    if args.md:
        with open(args.md, "w") as fh:
            fh.write(text)
        print("wrote %s (%d runs)" % (args.md, len(runs)))
    else:
        sys.stdout.write(text)
    return 0
