"""`run.py report`: Markdown tables from result.json files, and a compact
JSON of them all."""

import json
import os
import statistics
import time
from collections import Counter, defaultdict

from lib.common import ALL_CONDS
from lib.toolkinds import is_plain_code_access, is_tach_tool


def load(rundirs):
    out = []
    for d in rundirs:
        for root, _dirs, files in os.walk(d):
            if "result.json" in files:
                with open(os.path.join(root, "result.json")) as fh:
                    out.append(json.load(fh))
    out.sort(key=lambda r: (r["task"], r["model"], ALL_CONDS.index(r["cond"])
                            if r["cond"] in ALL_CONDS else 9, r["rep"]))
    return out


def _med(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def _fmt(x, unit=""):
    if x is None:
        return "-"
    if x >= 10000:
        return "%.0fk%s" % (x / 1000.0, unit)
    if isinstance(x, float) and x != int(x):
        return "%.1f%s" % (x, unit)
    return "%d%s" % (int(x), unit)


def _pct(a, b):
    return "-" if not b else "%.0f%%" % (100.0 * a / b)


def table(head, rows):
    lines = ["| " + " | ".join(head) + " |",
             "|" + "|".join("---" for _ in head) + "|"]
    lines += ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]
    return "\n".join(lines)


def build(results, rundirs):
    models = sorted({r["model"] for r in results})
    conds = [c for c in ALL_CONDS if any(r["cond"] == c for r in results)]
    tasks = sorted({r["task"] for r in results})
    by = defaultdict(list)
    for r in results:
        by[(r["model"], r["cond"])].append(r)
    md = ["# Agent eval report", "",
          "Generated %s by `tests/agent-eval/run.py report` from %d runs "
          "(%s)." % (time.strftime("%Y-%m-%d"), len(results),
                     ", ".join(os.path.basename(os.path.normpath(d)) for d in rundirs)),
          ""]
    comp = sorted({r.get("compiler") for r in results if r.get("compiler")})
    if comp:
        md += ["Compilers: " + "; ".join("`%s`" % c for c in comp) + ".", ""]

    md += ["## Success rate and mean test score", "",
           "A run succeeds when the program builds with the fixed command, "
           "passes every hidden test and the structural check; the score is "
           "the share of hidden tests passed (0 when it does not build). "
           "Cell: success rate / mean score (runs).", ""]
    rows = []
    for m in models:
        row = [m]
        for c in conds:
            rs = by.get((m, c), [])
            if not rs:
                row.append("-")
                continue
            succ = sum(1 for r in rs if r["success"])
            score = statistics.mean(
                (r["tests_passed"] / r["tests_total"]) if r["tests_total"] else 0
                for r in rs)
            row.append("%s / %.0f%% (%d)" % (_pct(succ, len(rs)), 100 * score, len(rs)))
        rows.append(row)
    md += [table(["model"] + conds, rows), ""]

    md += ["## Cost per run (medians)", "",
           "Input tokens count every prompt token the model read (for Claude: "
           "fresh, cache writes and cache reads; for Ollama: prompt_eval_count, "
           "the whole prompt of each call), summed over the run's model calls.", ""]
    rows = []
    for m in models:
        for c in conds:
            rs = by.get((m, c), [])
            if not rs:
                continue
            cost = [r.get("cost_usd") for r in rs if r.get("cost_usd") is not None]
            rows.append([m, c, len(rs), _fmt(_med([r.get("input_tokens") for r in rs])),
                         _fmt(_med([r.get("output_tokens") for r in rs])),
                         _fmt(_med([r.get("turns") for r in rs])),
                         _fmt(_med([r.get("tool_calls") for r in rs])),
                         _fmt(_med([r.get("wall_s") for r in rs]), "s"),
                         "$%.3f" % statistics.median(cost) if cost else "-"])
    md += [table(["model", "cond", "runs", "input tok", "output tok", "turns",
                  "tool calls", "wall", "cost (list)"], rows), ""]

    md += ["## Per task", "", "Successes / runs.", ""]
    cols = [(m, c) for m in models for c in conds if by.get((m, c))]
    rows = []
    for t in tasks:
        kind = next(r["kind"] for r in results if r["task"] == t)
        row = [t, kind]
        for m, c in cols:
            rs = [r for r in by[(m, c)] if r["task"] == t]
            row.append("%d/%d" % (sum(1 for r in rs if r["success"]), len(rs)) if rs else "-")
        rows.append(row)
    short = lambda m: m.split(":", 1)[1] if ":" in m else m
    md += [table(["task", "kind"] + ["%s %s" % (short(m), c) for m, c in cols], rows), ""]

    md += ["## tachyonc tools", "",
           "Per run, means: calls of the tachyonc tools (query, edit, refactor, "
           "check, fix, explain, undo, ...), `tachyonc guide` calls, and reading "
           "or editing code without them (the file tools Read/Edit/Write/Grep/"
           "Glob, or cat/sed/grep/head/tail/... in the shell). Share = tachyonc "
           "tools / (tachyonc tools + the rest).", ""]
    rows = []
    for m in models:
        for c in conds:
            if c == "rust" or not by.get((m, c)):
                continue
            rs = by[(m, c)]
            tach = plain = guide = 0
            subs = Counter()
            for r in rs:
                for k, n in (r.get("tool_calls_by_kind") or {}).items():
                    if is_tach_tool(k):
                        tach += n
                        subs[k[9:]] += n
                    elif k == "tachyonc:guide":
                        guide += n
                    elif is_plain_code_access(k):
                        plain += n
            n = float(len(rs))
            top = ", ".join("%s %d" % kv for kv in subs.most_common(5)) or "-"
            rows.append([m, c, len(rs), "%.1f" % (tach / n), "%.1f" % (guide / n),
                         "%.1f" % (plain / n), _pct(tach, tach + plain), top])
    md += [table(["model", "cond", "runs", "tachyonc tools", "guide", "plain reads/edits",
                  "share", "top subcommands (total)"], rows), ""]

    errs = Counter()
    denials = Counter()
    for r in results:
        if r.get("error"):
            errs[(r["model"], r["cond"], r["error"].split(":")[0][:40])] += 1
        if r.get("permission_denials"):
            denials[(r["model"], r["cond"])] += r["permission_denials"]
    if errs or denials:
        md += ["## Errors and permission denials", ""]
        rows = [[m, c, e, n] for (m, c, e), n in sorted(errs.items())]
        rows += [[m, c, "permission denials", n] for (m, c), n in sorted(denials.items())]
        md += [table(["model", "cond", "what", "count"], rows), ""]
    return "\n".join(md)


COMPACT_DROP = ("permission_denied", "agent_env")


def main(args):
    results = load(args.rundirs)
    if not results:
        print("no result.json under %s" % ", ".join(args.rundirs))
        return 1
    text = build(results, args.rundirs)
    if args.md:
        os.makedirs(os.path.dirname(os.path.abspath(args.md)) or ".", exist_ok=True)
        with open(args.md, "w") as fh:
            fh.write(text + "\n")
        jpath = os.path.splitext(args.md)[0] + ".json"
        compact = [{k: v for k, v in r.items() if k not in COMPACT_DROP} for r in results]
        with open(jpath, "w") as fh:
            fh.write("[\n" + ",\n".join(json.dumps(r, sort_keys=True) for r in compact)
                     + "\n]\n")
        print("wrote %s and %s (%d runs)" % (args.md, jpath, len(results)))
    else:
        print(text)
    return 0
