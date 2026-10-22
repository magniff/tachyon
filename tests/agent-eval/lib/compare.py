"""(0.17) `run.py compare`: new runs against a baseline round, per task.

    run.py compare --baseline DIR... --new DIR... [--pairs NEW=BASE,...] [--md FILE]

For every model and pair of conditions (NEW from the new runs, BASE from
the baseline; `NEW=new:BASE` takes BASE from the new runs too, for a
control cell run again), per task: successes, the medians of input
tokens, turns, cost and output tokens, the baseline cell's interquartile
range (a difference inside it is noise, whatever its direction), and the
ratio new/base. Across tasks: the median ratio and a paired test, the
exact Wilcoxon signed-rank test on the per-task log ratios (success is at
the ceiling, so McNemar is moot; costs are compared paired by task).
Then the anatomy's means per run: verify calls, guide calls, `query
context` calls, denials, distinct errors and the name/API class, repair
calls per error, edit failures, hook blocks and escapes.

Without --pairs: every new condition against every baseline condition of
the same kind (programs, compiler tasks)."""

import json
import math
import os
import statistics
from collections import defaultdict
from itertools import product

from lib.conds import is_compiler
from lib.report import _fmt, _iqr, _med, load, table


def spread(xs):
    """The interquartile range with 4 or more runs; with 2-3, the range."""
    xs = [x for x in xs if x is not None]
    if len(xs) >= 4:
        return _iqr(xs)
    if len(xs) >= 2:
        return min(xs), max(xs)
    return None


def wilcoxon_exact(diffs):
    """Two-sided exact p of the Wilcoxon signed-rank test (zeros dropped,
    average ranks for ties; enumeration, n <= 22)."""
    d = [x for x in diffs if abs(x) > 1e-12]
    n = len(d)
    if n == 0:
        return None, 1.0
    order = sorted(range(n), key=lambda i: abs(d[i]))
    ranks = [0.0] * n
    i = 0
    while i < n:
        j = i
        while j + 1 < n and abs(abs(d[order[j + 1]]) - abs(d[order[i]])) < 1e-12:
            j += 1
        for k in range(i, j + 1):
            ranks[order[k]] = (i + j) / 2.0 + 1
        i = j + 1
    w_plus = sum(r for r, x in zip(ranks, d) if x > 0)
    total = sum(ranks)
    if n > 22:  # normal approximation
        mu = total / 2.0
        sd = math.sqrt(n * (n + 1) * (2 * n + 1) / 24.0)
        z = (w_plus - mu) / sd if sd else 0.0
        return w_plus, min(1.0, math.erfc(abs(z) / math.sqrt(2)))
    # the distribution of W+ over the 2^n sign patterns, by dynamic programming
    scale = 2
    dist = {0: 1}
    for r in ranks:
        rr = int(round(r * scale))
        nd = defaultdict(int)
        for s, c in dist.items():
            nd[s] += c
            nd[s + rr] += c
        dist = nd
    obs = int(round(w_plus * scale))
    mean = int(round(total * scale)) / 2.0
    dev = abs(obs - mean)
    extreme = sum(c for s, c in dist.items() if abs(s - mean) >= dev - 1e-9)
    return w_plus, min(1.0, extreme / float(2 ** n))


def _an(r, path, default=0):
    a = r.get("anatomy") or {}
    for k in path:
        if not isinstance(a, dict):
            return default
        a = a.get(k)
    return a if a is not None else default


def _calls(r, pred):
    return sum(n for k, n in (r.get("tool_calls_by_kind") or {}).items() if pred(k))


VERIFY_KINDS = ("run", "rustc", "volec:build", "volec:check", "volec:test", "suite",
                "compiler:build", "shell:cmp", "shell:diff")

EXTRA = [
    ("verify calls", lambda r: _calls(r, lambda k: k in VERIFY_KINDS)),
    ("guide calls", lambda r: _calls(r, lambda k: k == "volec:guide")),
    ("query context", lambda r: sum(1 for t in (_an(r, ["sequence"], []) or [])
                                    if t == "query:context")),
    ("denials", lambda r: r.get("permission_denials") or 0),
    ("errors", lambda r: sum((_an(r, ["classes"], {}) or {}).values())),
    ("name/API errors", lambda r: (_an(r, ["classes"], {}) or {}).get("name", 0)),
    ("repair calls/error", lambda r: _an(r, ["repair", "calls_per_error"], None)),
    ("edit failures", lambda r: _an(r, ["edit_recovery", "failures"], 0)),
    ("hook blocks", lambda r: (r.get("query_hook") or {}).get("blocked")),
    ("escapes", lambda r: (r.get("query_hook") or {}).get("escapes")),
]


def _mean(xs):
    xs = [x for x in xs if x is not None]
    return statistics.mean(xs) if xs else None


def cells(results):
    by = defaultdict(list)
    for r in results:
        by[(r["model"], r["cond"], r["task"])].append(r)
    return by


def compare_pair(model, newc, basec, new_by, base_by, tasks):
    rows, logs = [], {"input_tokens": [], "turns": [], "cost_usd": []}
    tot = {"new_ok": 0, "new_n": 0, "base_ok": 0, "base_n": 0}
    noise = 0
    for t in tasks:
        nr, br = new_by.get((model, newc, t), []), base_by.get((model, basec, t), [])
        if not nr or not br:
            continue
        tot["new_ok"] += sum(1 for r in nr if r["success"])
        tot["new_n"] += len(nr)
        tot["base_ok"] += sum(1 for r in br if r["success"])
        tot["base_n"] += len(br)
        bi = [r.get("input_tokens") for r in br]
        mb, mn = _med(bi), _med([r.get("input_tokens") for r in nr])
        iq = spread(bi)
        inside = bool(iq and mn is not None and iq[0] <= mn <= iq[1])
        noise += inside
        for k in logs:
            a, b = _med([r.get(k) for r in nr]), _med([r.get(k) for r in br])
            if a and b:
                logs[k].append(math.log(float(a) / b))
        rows.append([t, "%d/%d" % (sum(1 for r in br if r["success"]), len(br)),
                     "%d/%d" % (sum(1 for r in nr if r["success"]), len(nr)),
                     _fmt(mb) + (" [%s-%s]" % (_fmt(iq[0]), _fmt(iq[1])) if iq else ""),
                     _fmt(mn), "%.2f%s" % (mn / float(mb), " ~" if inside else "")
                     if mb and mn else "-",
                     "%s -> %s" % (_fmt(_med([r.get("turns") for r in br])),
                                   _fmt(_med([r.get("turns") for r in nr]))),
                     "$%.3f -> $%.3f" % (_med([r.get("cost_usd") for r in br]) or 0,
                                         _med([r.get("cost_usd") for r in nr]) or 0)])
    summary = {"tasks": len(rows), "within_iqr": noise}
    summary.update(tot)
    for k, ls in logs.items():
        if ls:
            w, p = wilcoxon_exact(ls)
            summary[k] = {"median_ratio": round(math.exp(statistics.median(ls)), 3),
                          "p": round(p, 4), "n": len(ls)}
    ex = {}
    for name, f in EXTRA:
        a = _mean([f(r) for t in tasks for r in new_by.get((model, newc, t), [])])
        b = _mean([f(r) for t in tasks for r in base_by.get((model, basec, t), [])])
        ex[name] = (b, a)
    summary["extra"] = ex
    return rows, summary


def build(base_results, new_results, pairs):
    base_by, new_by = cells(base_results), cells(new_results)
    models = sorted({r["model"] for r in new_results})
    md = ["# Agent eval: new runs against the baseline", "",
          "Baseline: %d runs; new: %d runs. Per task: successes, median input tokens "
          "(baseline IQR in brackets, its range with under 4 runs; `~` marks a new median inside it: noise), the "
          "ratio new/base, median turns and cost. Summary: the median of the per-task "
          "ratios and the exact Wilcoxon signed-rank p on the per-task log ratios "
          "(paired by task)." % (len(base_results), len(new_results)), ""]
    out = []
    for m in models:
        for newc, (src, basec) in pairs:
            bb = new_by if src == "new" else base_by
            tasks = sorted({k[2] for k in new_by if k[0] == m and k[1] == newc}
                           & {k[2] for k in bb if k[0] == m and k[1] == basec})
            if not tasks:
                continue
            rows, s = compare_pair(m, newc, basec, new_by, bb, tasks)
            label = "%s: %s against %s%s" % (m, newc, basec, " (new runs)" if src == "new"
                                              else " (baseline)")
            md += ["## " + label, ""]
            md += [table(["task", "base ok", "new ok", "base input [IQR]", "new input",
                          "new/base", "turns", "cost"], rows), ""]
            line = ["success %d/%d -> %d/%d" % (s["base_ok"], s["base_n"], s["new_ok"],
                                                 s["new_n"])]
            for k in ("input_tokens", "turns", "cost_usd"):
                if k in s:
                    line.append("%s x%.2f (p=%.3g, %d tasks)" % (
                        k.replace("_usd", "").replace("_", " "), s[k]["median_ratio"],
                        s[k]["p"], s[k]["n"]))
            line.append("%d of %d tasks inside the baseline IQR" % (s["within_iqr"], s["tasks"]))
            md += ["Summary: " + "; ".join(line) + ".", ""]
            md += [table(["per run (mean)", "base", "new"],
                         [[k, "-" if b is None else "%.2f" % b, "-" if a is None else "%.2f" % a]
                          for k, (b, a) in s["extra"].items()]), ""]
            out.append({"model": m, "new": newc, "base": basec, "base_from": src,
                        "summary": {k: v for k, v in s.items() if k != "extra"},
                        "extra": {k: list(v) for k, v in s["extra"].items()}})
    return "\n".join(md), out


def parse_pairs(text, new_results, base_results):
    if text:
        out = []
        for p in text.split(","):
            if not p.strip():
                continue
            n, _, b = p.partition("=")
            src = "base"
            if b.startswith("new:"):
                src, b = "new", b[4:]
            out.append((n.strip(), (src, b.strip())))
        return out
    nc = sorted({r["cond"] for r in new_results})
    bc = sorted({r["cond"] for r in base_results})
    return [(n, ("base", b)) for n, b in product(nc, bc) if is_compiler(n) == is_compiler(b)]


def main(args):
    base = load(args.baseline)
    new = load(args.new)
    if not base or not new:
        print("no runs (baseline %d, new %d)" % (len(base), len(new)))
        return 1
    pairs = parse_pairs(args.pairs, new, base)
    text, data = build(base, new, pairs)
    if args.md:
        os.makedirs(os.path.dirname(os.path.abspath(args.md)) or ".", exist_ok=True)
        with open(args.md, "w") as fh:
            fh.write(text + "\n")
        with open(os.path.splitext(args.md)[0] + ".json", "w") as fh:
            json.dump(data, fh, indent=1, default=str)
        print("wrote %s (%d comparisons)" % (args.md, len(data)))
    else:
        print(text)
    return 0
