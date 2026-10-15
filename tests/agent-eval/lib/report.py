"""`run.py report`: Markdown tables from result.json files, and a compact
JSON of them all."""

import json
import os
import statistics
import time
from collections import Counter, defaultdict

from lib.common import cond_key
from lib.conds import is_compiler
from lib.toolkinds import is_plain_code_access, is_tach_tool


def load(rundirs, with_anatomy=True):
    """Every result.json under the directories; (0.17) runs from before
    the anatomy get it computed from their transcripts (not written)."""
    out = []
    for d in rundirs:
        for root, _dirs, files in os.walk(d):
            if "result.json" in files:
                with open(os.path.join(root, "result.json")) as fh:
                    r = json.load(fh)
                if with_anatomy and not r.get("anatomy") and "transcript.jsonl" in files:
                    from lib.anatomy import safe_for_run
                    r["anatomy"] = safe_for_run(root, r)
                out.append(r)
    out.sort(key=lambda r: (r["task"], r["model"], cond_key(r["cond"]), r["rep"]))
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
    conds = sorted({r["cond"] for r in results}, key=cond_key)
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

    md += compiler_section(results)
    md += anatomy_sections(results)

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


def _ratio(a, b):
    return "-" if a is None or not b else "%.2f" % (float(a) / b)


def _sum(xs):
    xs = [x for x in xs if x is not None]
    return sum(xs) if xs else None


def compiler_section(results):
    """(0.16) The compiler tasks: compiler-tools against compiler-plain, per
    model and per task; how the tools and hooks were used; why runs failed."""
    rs_all = [r for r in results if r.get("lang") == "compiler"]
    if not rs_all:
        return []
    models = sorted({r["model"] for r in rs_all})
    tasks = sorted({r["task"] for r in rs_all})
    conds = sorted({r["cond"] for r in rs_all if is_compiler(r["cond"])}, key=cond_key)
    by = defaultdict(list)
    for r in rs_all:
        by[(r["model"], r["cond"])].append(r)
        by[(r["model"], r["cond"], r["task"])].append(r)
    md = ["## Compiler tasks: tools against plain", "",
          "Changes to tachyon's own compiler in a copy of the repository "
          "(tests/agent-eval/ctasks/). `compiler-tools`: AGENTS.md as it is, "
          "with the query-first and check hooks; `compiler-plain`: AGENTS.md "
          "without the tools table, no hooks (file tools and the shell; "
          "tachyonc to build and test). A run succeeds when the compiler "
          "builds (fixpoint), the task's test filters, same-output and "
          "grade.sh pass. Medians per run; cost is the list price.", ""]
    rows = []
    for m in models:
        med = {}
        for c in conds:
            rs = by.get((m, c), [])
            if not rs:
                continue
            succ = sum(1 for r in rs if r["success"])
            med[c] = {k: _med([r.get(k) for r in rs]) for k in
                      ("input_tokens", "output_tokens", "turns", "tool_calls", "wall_s",
                       "cost_usd")}
            rows.append([m, c, len(rs), "%s (%d/%d)" % (_pct(succ, len(rs)), succ, len(rs)),
                         _fmt(med[c]["input_tokens"]), _fmt(med[c]["output_tokens"]),
                         _fmt(med[c]["turns"]), _fmt(med[c]["tool_calls"]),
                         _fmt(med[c]["wall_s"], "s"),
                         "$%.2f" % med[c]["cost_usd"] if med[c]["cost_usd"] is not None else "-",
                         "$%.2f" % _sum([r.get("cost_usd") for r in rs])
                         if _sum([r.get("cost_usd") for r in rs]) is not None else "-"])
        for tc in [c for c in med if c != "compiler-plain"]:
            if "compiler-plain" not in med:
                break
            t, p = med[tc], med["compiler-plain"]
            rows.append([m, "%s / plain" % tc.replace("compiler-", ""), "", "",
                         _ratio(t["input_tokens"], p["input_tokens"]),
                         _ratio(t["output_tokens"], p["output_tokens"]),
                         _ratio(t["turns"], p["turns"]), _ratio(t["tool_calls"], p["tool_calls"]),
                         _ratio(t["wall_s"], p["wall_s"]), _ratio(t["cost_usd"], p["cost_usd"]),
                         ""])
    md += [table(["model", "cond", "runs", "success", "input tok", "output tok", "turns",
                  "tool calls", "wall", "cost", "total cost"], rows), ""]

    md += ["Per task: successes/runs, median input tokens, median wall time.", ""]
    head = ["task", "kind"]
    cols = [(m, c) for m in models for c in conds]
    short = lambda m: m.split(":", 1)[1] if ":" in m else m
    head += ["%s %s" % (short(m), c.replace("compiler-", "")) for m, c in cols]
    rows = []
    for t in tasks:
        kind = next(r["kind"] for r in rs_all if r["task"] == t)
        row = [t, kind]
        for m, c in cols:
            rs = by.get((m, c, t), [])
            row.append("%d/%d, %s, %s" % (sum(1 for r in rs if r["success"]), len(rs),
                                          _fmt(_med([r.get("input_tokens") for r in rs])),
                                          _fmt(_med([r.get("wall_s") for r in rs]), "s"))
                       if rs else "-")
        rows.append(row)
    md += [table(head, rows), ""]

    md += ["How the code was read and changed, means per run: the tachyonc tools "
           "(query, edit, refactor, check, fix, ...), the file tools and shell "
           "reads, compiler builds and test-suite runs; with the tools, the "
           "query-first hook's blocks and `# no-query`/`# no-tool` escapes, and "
           "the check hook's checks (with errors).", ""]
    rows = []
    for m in models:
        for c in conds:
            rs = by.get((m, c), [])
            if not rs:
                continue
            tach = plain = builds = suites = 0
            subs = Counter()
            for r in rs:
                for k, n in (r.get("tool_calls_by_kind") or {}).items():
                    if is_tach_tool(k):
                        tach += n
                        subs[k[9:]] += n
                    elif is_plain_code_access(k):
                        plain += n
                    elif k == "compiler:build":
                        builds += n
                    elif k == "suite":
                        suites += n
            n = float(len(rs))
            qh = [r.get("query_hook") or {} for r in rs]
            ch = [r.get("check_hook") or {} for r in rs]
            hooks = "-"
            if c.startswith("compiler-tools"):
                hooks = "%.1f / %.1f / %.1f (%.1f)" % (
                    sum(q.get("blocked", 0) for q in qh) / n,
                    sum(q.get("escapes", 0) for q in qh) / n,
                    sum(x.get("checks", 0) for x in ch) / n,
                    sum(x.get("with_errors", 0) for x in ch) / n)
            rows.append([m, c, len(rs), "%.1f" % (tach / n), "%.1f" % (plain / n),
                         _pct(tach, tach + plain), "%.1f" % (builds / n), "%.1f" % (suites / n),
                         hooks, ", ".join("%s %d" % kv for kv in subs.most_common(4)) or "-"])
    md += [table(["model", "cond", "runs", "tachyonc tools", "plain reads/edits", "share",
                  "builds", "suite runs", "blocked / escapes / checks (errors)",
                  "top subcommands (total)"], rows), ""]

    fails = Counter()
    for r in rs_all:
        if r["success"]:
            continue
        g = r.get("grade_summary") or ""
        if r.get("build_ok") is False:
            why = "build"
        elif "FAIL" in g.split("grade.sh")[0]:
            why = "tests"
        elif r.get("same_output_ok") is False:
            why = "same-output"
        elif r.get("check_ok") is False:
            why = "grade.sh"
        else:
            why = "other"
        if r.get("error"):
            why += " (" + r["error"].split(":")[0][:30] + ")"
        fails[(r["model"], r["cond"], why)] += 1
    if fails:
        md += ["Failed runs by the first grading step that failed.", ""]
        md += [table(["model", "cond", "failed at", "runs"],
                     [[m, c, w, k] for (m, c, w), k in sorted(fails.items())]), ""]
    return md


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


# ---------------------------------------------------------------- (0.17) anatomy


def _mean(xs):
    xs = [x for x in xs if x is not None]
    return statistics.mean(xs) if xs else None


def _iqr(xs):
    xs = sorted(x for x in xs if x is not None)
    if len(xs) < 4:
        return None
    q = statistics.quantiles(xs, n=4)
    return q[0], q[2]


def _f1(x):
    return "-" if x is None else "%.1f" % x


def anatomy_sections(results):
    """Tables from each run's `anatomy` (lib/anatomy.py): turn anatomy,
    error classes, Rust habits, tool n-grams, repair, edit recovery,
    intent erosion, denials by cause."""
    rs = [r for r in results if isinstance(r.get("anatomy"), dict) and "error" not in r["anatomy"]]
    if not rs:
        return []
    by = defaultdict(list)
    for r in rs:
        by[(r["model"], r["cond"])].append(r)
    keys = sorted(by, key=lambda k: (k[0], cond_key(k[1])))
    md = ["## Turn anatomy (0.17)", "",
          "Medians per run (IQR of input tokens in brackets). Prompt: tokens the model "
          "read in one call (fresh + cache write + cache read), the first call and the "
          "median call. Calls by role, means per run: lookup (guide, query, Read, shell "
          "reads), edit (Write/Edit, tachyonc edit/refactor/fix), verify (check, build, "
          "run, test, cmp/diff); first edit: the call number of the first edit (median).", ""]
    rows = []
    for k in keys:
        g = by[k]
        an = [r["anatomy"] for r in g]
        tok = [a.get("tokens") or {} for a in an]
        iq = _iqr([r.get("input_tokens") for r in g])
        cost = [r.get("cost_usd") for r in g if r.get("cost_usd") is not None]
        roles = lambda role: _mean([(a.get("roles") or {}).get(role, 0) for a in an])
        rows.append([k[0], k[1], len(g), _fmt(_med([r.get("turns") for r in g])),
                     _fmt(_med([r.get("output_tokens") for r in g])),
                     _fmt(_med([t.get("fresh") for t in tok])),
                     _fmt(_med([t.get("cache_write") for t in tok])),
                     _fmt(_med([t.get("cache_read") for t in tok])),
                     _fmt(_med([r.get("input_tokens") for r in g]))
                     + (" [%s-%s]" % (_fmt(iq[0]), _fmt(iq[1])) if iq else ""),
                     _fmt(_med([t.get("first_prompt") for t in tok])),
                     _fmt(_med([t.get("median_prompt") for t in tok])),
                     "$%.3f" % statistics.median(cost) if cost else "-",
                     "%s / %s / %s / %s" % (_f1(roles("lookup")), _f1(roles("edit")),
                                           _f1(roles("verify")), _f1(roles("other"))),
                     _fmt(_med([a.get("first_edit_call") for a in an]))])
    md += [table(["model", "cond", "runs", "turns", "output", "fresh in", "cache write",
                  "cache read", "input [IQR]", "first prompt", "prompt/turn", "cost",
                  "lookup / edit / verify / other", "first edit"], rows), ""]

    classes = ["name", "type", "match", "syntax", "unsafe", "alloc", "own", "effects", "other"]
    md += ["## Errors by class (0.17)", "",
           "Distinct compile errors per run (same class and message, names and numbers "
           "masked), from the tool results and the hooks' output (hook-output.jsonl, "
           "0.17 runs); Rust runs from rustc's codes. Cells: mean per run (share of the "
           "condition's errors). Repair: calls from a call that showed errors to the next "
           "clean build, check or checked edit, per error fixed (mean).", ""]
    rows = []
    for k in keys:
        an = [r["anatomy"] for r in by[k]]
        tot = Counter()
        for a in an:
            tot.update(a.get("classes") or {})
        n = float(len(an))
        alls = sum(tot.values())
        rp = [((a.get("repair") or {}).get("calls_per_error")) for a in an]
        rows.append([k[0], k[1], len(an), "%.1f" % (alls / n)]
                    + ["%.1f (%s)" % (tot[c] / n, _pct(tot[c], alls)) if tot[c] else "-"
                       for c in classes] + [_f1(_mean(rp))])
    md += [table(["model", "cond", "runs", "errors/run"] + classes + ["repair calls/error"],
                 rows), ""]

    habits = Counter()
    hb = defaultdict(Counter)
    for k in keys:
        for r in by[k]:
            h = (r["anatomy"].get("habits") or {})
            hb[k].update(h)
            habits.update(h)
    if habits:
        tags = [t for t, _ in habits.most_common(10)]
        md += ["## Rust habits (0.17)", "",
               "Distinct tachyon errors whose message shows a Rust habit, per tag: "
               "total over the condition's runs.", ""]
        rows = [[k[0], k[1], len(by[k])] + [hb[k][t] or "-" for t in tags]
                for k in keys if k[1] != "rust"]
        md += [table(["model", "cond", "runs"] + tags, rows), ""]

    md += ["## Recovery, erosion, denials (0.17)", "",
           "Edit failures (patch.no-match, edit.breaks, an Edit miss) per run, and how "
           "often the next edit succeeded; intent erosion: starter items, test files and "
           "assert-like lines gone at the end (totals); denials per run by primary "
           "cause.", ""]
    rows = []
    for k in keys:
        an = [r["anatomy"] for r in by[k]]
        n = float(len(an))
        er = [a.get("edit_recovery") or {} for a in an]
        fails = sum(e.get("failures", 0) for e in er)
        nok = sum(e.get("next_ok", 0) for e in er)
        nbad = sum(e.get("next_failed", 0) for e in er)
        ero = [a.get("erosion") or {} for a in an]
        den = Counter()
        for a in an:
            den.update((a.get("denials") or {}).get("by_cause") or {})
        rows.append([k[0], k[1], len(an), "%.1f" % (fails / n),
                     _pct(nok, nok + nbad) if nok + nbad else "-",
                     "%d / %d / %d" % (sum(e.get("items_removed") or 0 for e in ero),
                                       sum(e.get("test_files_removed") or 0 for e in ero),
                                       sum(e.get("asserts_removed") or 0 for e in ero)),
                     "%.1f" % (sum(den.values()) / n),
                     ", ".join("%s %d" % kv for kv in den.most_common(5)) or "-"])
    md += [table(["model", "cond", "runs", "edit failures/run", "next edit ok",
                  "items / test files / asserts removed", "denials/run", "denials by cause"],
                 rows), ""]

    md += ["## Tool sequences (0.17)", "",
           "The most frequent three-call sequences per condition (calls as tokens: "
           "Write, Edit, Read, build, run, check, query:show, edit:patch, guide, a "
           "shell command's name), summed over the runs.", ""]
    rows = []
    for k in keys:
        tri = Counter()
        for r in by[k]:
            tri.update((r["anatomy"].get("ngrams") or {}).get("3") or {})
        rows.append([k[0], k[1], "; ".join("%s (%d)" % kv for kv in tri.most_common(4)) or "-"])
    md += [table(["model", "cond", "top trigrams"], rows), ""]
    return md
