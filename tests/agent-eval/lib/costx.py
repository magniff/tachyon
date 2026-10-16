"""(0.18) `run.py costx`: cells against Rust, the 0.17 iterations' measure,
with the errors by family.

    run.py costx --rust DIR[:COND]... --cell LABEL=DIR[:COND][,DIR[:COND]]... \
        [--tasks 01,03] [--models claude:haiku] [--md FILE]

A cell is the runs under its directories (of condition COND when given;
`X+debrief` is taken as `X`'s twin). Per model and task: the median cost
over the Rust cell's median for the same task and model (cost x Rust),
the same with the tier-free cost (Haiku 5.5 bills a request at 5x when
its prompt is over 100k tokens; the tier-free cost re-prices those at the
base rate, as .claude/briefs/research/haiku-15.md fitted), median turns
and successes; per cell the geometric mean of both ratios over the tasks
it shares with Rust, median turns, success, median peak context and
requests over 100k. Then the distinct compile errors per run by family:
0.17's `own.*` (and Rust's borrow-checker errors, the baseline), 0.18's
`contract.*`, `test.*`, `distinct.*`, then the anatomy's classes; and the
codes of the new families one by one. These are the friction signal of
value semantics and contracts."""

import json
import math
import os
import statistics
import sys
from collections import Counter, defaultdict

from lib.conds import without_debrief

RATES = {  # $/MTok: input, cache write (1h), cache read, output; tier (threshold, multiplier)
    "haiku": ((0.10, 0.20, 0.01, 0.50), (100000, 5.0)),
    "sonnet": ((2.0, 4.0, 0.20, 10.0), None),
}
NEW_FAMILIES = ("own", "contract", "test", "distinct")
CLASSES = ("name", "type", "match", "syntax", "unsafe", "alloc", "effects", "other")
FAMILIES = NEW_FAMILIES + CLASSES


def run_metrics(rundir, r):
    """Peak context, requests over 100k and the tier-free cost of a run,
    from its transcript (the 0.17 iterations' ctxcost.py)."""
    p = os.path.join(rundir, "transcript.jsonl")
    out = {"peak": None, "over100k": None, "tierfree": r.get("cost_usd")}
    if not os.path.isfile(p):
        return out
    reqs, order = {}, []
    with open(p) as fh:
        for line in fh:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if e.get("type") != "assistant":
                continue
            m = e.get("message", {})
            u = m.get("usage") or {}
            if m.get("id") not in reqs:
                order.append(m.get("id"))
            reqs[m.get("id")] = u
    us = [reqs[i] for i in order]
    if not us:
        return out
    ctx = [u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
           + u.get("cache_read_input_tokens", 0) for u in us]
    out["peak"] = max(ctx)
    out["over100k"] = sum(1 for c in ctx if c > 100000)
    rates, tier = RATES["haiku" if "haiku" in (r.get("model") or "") else "sonnet"]
    cost = r.get("cost_usd")
    if tier is None or not cost:
        return out
    total_out = r.get("output_tokens") or 0
    w = [us[i + 1].get("cache_creation_input_tokens", 0) for i in range(len(us) - 1)]
    w.append(max(us[-1].get("output_tokens", 0), 1))
    sw = float(sum(w)) or 1.0
    base = tiered = 0.0
    for u, c, wi in zip(us, ctx, w):
        x = (u.get("input_tokens", 0) * rates[0] + u.get("cache_creation_input_tokens", 0)
             * rates[1] + u.get("cache_read_input_tokens", 0) * rates[2]
             + total_out * wi / sw * rates[3]) / 1e6
        base += x
        tiered += x * (tier[1] if c > tier[0] else 1.0)
    out["tierfree"] = cost * base / tiered if tiered else cost
    return out


def family(e):
    """An anatomy error's family: the code's prefix for the new ones, else
    its class (Rust's borrow-checker codes are class `own`)."""
    code = e.get("code") or ""
    pre = code.split(".", 1)[0] if "." in code else ""
    if pre in NEW_FAMILIES:
        return pre
    cls = e.get("class") or "other"
    return cls if cls in FAMILIES else "other"


def load_spec(spec, tasks, models):
    d, _, cond = spec.partition(":")
    runs = []
    for root, _, files in os.walk(d):
        if "result.json" not in files:
            continue
        with open(os.path.join(root, "result.json")) as fh:
            r = json.load(fh)
        if r.get("dry_run") or r.get("cost_usd") is None:
            continue
        if cond and without_debrief(r["cond"]) != without_debrief(cond):
            continue
        if tasks and not any(r["task"].startswith(t) for t in tasks):
            continue
        if models and r["model"] not in models:
            continue
        r["_dir"] = root
        r.update(run_metrics(root, r))
        runs.append(r)
    return runs


def errors_of(r):
    an = r.get("anatomy")
    if not an:
        from lib.anatomy import safe_for_run
        an = safe_for_run(r["_dir"], r) or {}
    return an.get("errors") or []


def _med(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def tables(rust, cells, tasks_order=None):
    out = []
    w = out.append
    models = sorted({r["model"] for rs in [rust] + [c[1] for c in cells] for r in rs})
    for m in models:
        rr = defaultdict(list)
        for r in rust:
            if r["model"] == m:
                rr[r["task"]].append(r)
        w("\n## %s\n" % m)
        w("| cell | tasks | cost x Rust | tier-free x Rust | success | median turns | "
          "median peak ctx | median req >100k |")
        w("|---|---|---|---|---|---|---|---|")
        rs_all = [r for rs in rr.values() for r in rs]
        if rs_all:
            w("| Rust | %d | 1 | 1 | %d/%d | %s | %s | %s |" % (
                len(rr), sum(1 for r in rs_all if r.get("success")), len(rs_all),
                _g(_med([r.get("turns") for r in rs_all])),
                _k(_med([r.get("peak") for r in rs_all])),
                _g(_med([r.get("over100k") for r in rs_all]))))
        per_task = []
        for label, runs in cells:
            by = defaultdict(list)
            for r in runs:
                if r["model"] == m:
                    by[r["task"]].append(r)
            if not by:
                continue
            logs, tlogs = [], []
            for t in sorted(by):
                if not rr.get(t):
                    continue
                rc = _med([r["cost_usd"] for r in rr[t]])
                rt = _med([r["tierfree"] for r in rr[t]])
                x = _med([r["cost_usd"] for r in by[t]])
                xt = _med([r["tierfree"] for r in by[t]])
                if rc and x:
                    logs.append(math.log(x / rc))
                if rt and xt:
                    tlogs.append(math.log(xt / rt))
                per_task.append((t, label, by[t], x / rc if rc and x else None,
                                 xt / rt if rt and xt else None))
            allr = [r for rs in by.values() for r in rs]
            w("| %s | %d | %s | %s | %d/%d | %s | %s | %s |" % (
                label, len(logs), _gm(logs), _gm(tlogs),
                sum(1 for r in allr if r.get("success")), len(allr),
                _g(_med([r.get("turns") for r in allr])),
                _k(_med([r.get("peak") for r in allr])),
                _g(_med([r.get("over100k") for r in allr]))))
        if per_task:
            w("\nPer task:\n")
            w("| task | cell | ok | cost x Rust | tier-free x Rust | turns |")
            w("|---|---|---|---|---|---|")
            for t, label, rs, cx, tx in sorted(per_task, key=lambda x: (x[0], x[1])):
                w("| %s | %s | %d/%d | %s | %s | %s |" % (
                    t, label, sum(1 for r in rs if r.get("success")), len(rs), _f(cx), _f(tx),
                    _g(_med([r.get("turns") for r in rs]))))
        # errors by family
        w("\nDistinct compile errors per run, by family (`own`: 0.17's own.* codes, and "
          "Rust's borrow-checker errors in the Rust row):\n")
        w("| cell | runs | all | " + " | ".join(FAMILIES) + " |")
        w("|---|---|---|" + "---|" * len(FAMILIES))
        codes = defaultdict(Counter)
        for label, runs in [("Rust", rust)] + list(cells):
            rs = [r for r in runs if r["model"] == m]
            if not rs:
                continue
            fam = Counter()
            for r in rs:
                for e in errors_of(r):
                    f = family(e)
                    fam[f] += 1
                    if f in NEW_FAMILIES and label != "Rust":
                        codes[label][e.get("code") or f] += 1
            n = float(len(rs))
            w("| %s | %d | %.2f | %s |" % (label, len(rs), sum(fam.values()) / n,
                                          " | ".join("%.2f" % (fam[f] / n) for f in FAMILIES)))
        if any(codes.values()):
            w("\nThe new families' codes (distinct errors, summed over the runs):\n")
            for label in [c[0] for c in cells]:
                if codes[label]:
                    w("- %s: %s" % (label, ", ".join("`%s` %d" % kv
                                                     for kv in codes[label].most_common(20))))
    return "\n".join(out) + "\n"


def _gm(logs):
    return "%.2f" % math.exp(sum(logs) / len(logs)) if logs else "-"


def _f(x):
    return "-" if x is None else "%.2f" % x


def _g(x):
    return "-" if x is None else "%g" % x


def _k(x):
    return "-" if x is None else "%.0fk" % (x / 1000.0)


def main(args):
    tasks = [t for t in (args.tasks or "").split(",") if t]
    models = [m for m in (args.models or "").split(",") if m]
    rust = [r for s in args.rust for r in load_spec(s, tasks, models)]
    rust = [r for r in rust if r.get("lang") == "rust" or without_debrief(r["cond"]) == "rust"]
    cells = []
    for spec in args.cell:
        label, _, dirs = spec.partition("=")
        runs = [r for d in dirs.split(",") for r in load_spec(d, tasks, models)]
        cells.append((label, runs))
    head = ("# cost x Rust\n\nRust: %s. Cells: %s.\n" % (
        ", ".join(args.rust), "; ".join("%s = %s" % (s.partition("=")[0], s.partition("=")[2])
                                       for s in args.cell)))
    text = head + tables(rust, cells)
    if args.md:
        with open(args.md, "w") as fh:
            fh.write(text)
        print("wrote %s" % args.md)
    else:
        sys.stdout.write(text)
    return 0
