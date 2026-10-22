#!/usr/bin/env python3
"""(0.17, agent eval) Prompt-cache audit of Claude Code runs, with no model cost.

    python3 tests/agent-eval/lib/cacheaudit.py DIR... [--json] [--md OUT] [--runs] [--partial]
    python3 tests/agent-eval/lib/cacheaudit.py --selftest

Each DIR is searched for run directories (a transcript.jsonl, usually with
result.json; laid out SET/TASK/MODEL/COND/repN). For every model request of
the main thread (one assistant message id; several stream lines share one id
and are counted once; lines with parent_tool_use_id set are a subagent's and
are counted apart) it takes the usage block: input_tokens (fresh),
cache_creation_input_tokens, cache_read_input_tokens.

A request k > 1 is classified as
  growth  its cache read covers the whole previous prompt (read_k >=
          read_{k-1} + creation_{k-1} + fresh_{k-1} - SLACK) and its creation
          is about the size of what was appended since request k-1;
  break   the read fell short of the previous prompt (the prefix changed or
          expired): the tokens that had to be written again are the break's
          cost; the cause named is what preceded it (compaction, an idle gap
          over the cache TTL, an image, a tool result over BIG_RESULT chars, a
          hook output, a model change) or "unknown";
  oversize  the read is whole but the creation exceeds the estimated new
          content by more than 1.5x + 4000 tokens: content the transcript does
          not show (hook additionalContext, a Stop-hook reason, a background
          task's notification) or an estimate error.
Request 1's creation is the initial prompt (system prompt, tools, CLAUDE.md,
the task prompt); its read is the part another run on this machine had
already cached.

Growth is attributed to what was appended since the previous request: the
previous assistant message (thinking, by Claude Code's thinking_tokens
estimate; text and tool calls) and each tool result, by the kind of the call
that produced it (volec guide, volec query, other volec commands,
builds and runs, shell reads, other shell, Read, Edit/Write, Grep/Glob), hook
text (a PreToolUse block's stderr shown in the tool result; additionalContext
and Stop reasons from hook-output.jsonl when the run has one, estimated from
check-hook.jsonl otherwise), permission denials and background-task
notifications. Text is estimated at CHARS_PER_TOKEN characters a token plus
RESULT_OVERHEAD a tool result (the transcript has no per-block token
counts; the constants are fitted, see below); the estimates are then scaled to
the request's real creation count, so every bucket sums to the measured
total. "unattributed" is creation with nothing visible to attribute it to.

Prices are base-input multiples: 5-minute write 1.25x, 1-hour write 2x, read
0.1x (vendor prompt-caching docs; .claude/briefs/research/delivery.md §1.5).
"""

import json
import os
import statistics
import sys
import tempfile
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from toolkinds import classify_call
except Exception:  # (standalone use) a minimal classifier
    def classify_call(tool, args):
        if tool == "Bash":
            cmd = (args or {}).get("command", "")
            if "volec" in cmd:
                for sub in ("guide", "query", "edit", "refactor", "check", "fix"):
                    if "volec " + sub in cmd:
                        return ["volec:" + sub]
                return ["volec:build"]
            return ["shell:?"]
        return ["file:" + tool]

# Fitted on the 0.16 baseline (7,045 growth requests, least squares of the
# measured creation on the text appended): tool output, code and the
# assistant's text came to about 2.35 characters a token (chars/4
# under-counted by 1.7x), Claude Code's thinking_tokens estimate to 1.0x of
# the measured count, and each tool result to about 68 tokens more than its
# text (the wrapper and what Claude Code adds to it).
CHARS_PER_TOKEN = 2.35
RESULT_OVERHEAD = 68
SLACK = 64           # tokens of read shortfall still counted as a whole read
BIG_RESULT = 40000   # chars: a tool result this long is named as a break cause
WRITE_5M, WRITE_1H, READ = 1.25, 2.0, 0.1

SOURCES = ["assistant", "thinking", "guide", "query", "volec-other",
           "build-run", "shell-read", "shell-other", "file-read", "file-edit",
           "file-search", "hook-block", "hook-context", "hook-stop",
           "denial", "task-notify", "unattributed"]


def est_tokens(text):
    return len(text) / CHARS_PER_TOKEN


def result_text(block):
    c = block.get("content")
    if isinstance(c, str):
        return c, False
    out, image = [], False
    for x in c or []:
        if x.get("type") == "text":
            out.append(x.get("text") or "")
        elif x.get("type") == "image":
            image = True
            out.append("x" * 6400)  # ~1.6k tokens an image, a rough guess
    return "\n".join(out), image


def call_source(name, inp):
    if name == "Read":
        return "file-read"
    if name in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        return "file-edit"
    if name in ("Grep", "Glob"):
        return "file-search"
    if name != "Bash":
        return "shell-other"
    kinds = classify_call(name, inp)
    if "volec:guide" in kinds or "volec:explain" in kinds:
        return "guide"
    if "volec:query" in kinds:
        return "query"
    if any(k.startswith("volec:") and k != "volec:build" for k in kinds):
        return "volec-other"
    if any(k in ("volec:build", "run", "rustc", "compiler:build", "suite",
                 "compiler:gate") for k in kinds):
        return "build-run"
    if any(k.startswith("shell:") and k[6:] in ("cat", "head", "tail", "sed", "grep",
                                                "rg", "awk", "nl", "wc", "less")
           for k in kinds):
        return "shell-read"
    return "shell-other"


def hook_context_text(rec):
    """The text a hook-output.jsonl record put in the model's context."""
    out = (rec.get("stdout") or "").strip()
    if rec.get("exit") == 2:
        return "", "hook-block"  # its stderr is already in the tool result
    if not out:
        return "", None
    try:
        d = json.loads(out)
    except ValueError:
        return out, "hook-context"
    if d.get("decision") == "block":
        return d.get("reason") or "", "hook-stop"
    hso = d.get("hookSpecificOutput") or {}
    return (hso.get("additionalContext") or d.get("systemMessage") or ""), "hook-context"


def load_jsonl(path):
    out = []
    try:
        with open(path, "rb") as fh:
            for raw in fh:
                try:
                    out.append(json.loads(raw))
                except ValueError:
                    pass
    except OSError:
        pass
    return out


def ts_seconds(ts):
    if not ts:
        return None
    import datetime
    try:
        return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def analyze_run(rundir):
    lines = load_jsonl(os.path.join(rundir, "transcript.jsonl"))
    hooks = load_jsonl(os.path.join(rundir, "hook-output.jsonl"))
    checks = [c for c in load_jsonl(os.path.join(rundir, "check-hook.jsonl"))
              if c.get("errors")]
    result = {}
    try:
        with open(os.path.join(rundir, "result.json")) as fh:
            result = json.load(fh)
    except (OSError, ValueError):
        pass
    hook_by_id, stops = defaultdict(list), []
    for h in hooks:
        text, kind = hook_context_text(h)
        if not text:
            continue
        if kind == "hook-stop" or not h.get("tool_use_id"):
            stops.append((kind or "hook-context", text))
        else:
            hook_by_id[h["tool_use_id"]].append((kind, text))

    # requests in order; per request the content appended after it
    reqs, by_id, sub = [], {}, {}
    cur = None
    tool_names = {}
    think_est = 0
    model = None
    for d in lines:
        t = d.get("type")
        if t == "system" and d.get("subtype") == "thinking_tokens":
            think_est = d.get("estimated_tokens") or think_est
            continue
        if t == "system" and d.get("subtype") == "compact_boundary":
            if cur is not None:
                cur["events"].append("compaction")
            continue
        if t == "system" and d.get("subtype") == "task_notification":
            if cur is not None:
                cur["new"]["task-notify"] += est_tokens(
                    (d.get("summary") or "") + (d.get("output_file") or "") + " " * 200)
            continue
        if t == "assistant":
            m = d.get("message") or {}
            mid = m.get("id")
            if d.get("parent_tool_use_id"):
                if mid and m.get("usage") and mid not in sub:
                    sub[mid] = m["usage"]
                continue
            if not mid:
                continue
            if mid not in by_id:
                u = m.get("usage") or {}
                cc = u.get("cache_creation") or {}
                r = {"id": mid, "ts": ts_seconds(d.get("timestamp")),
                     "fresh": u.get("input_tokens") or 0,
                     "create": u.get("cache_creation_input_tokens") or 0,
                     "read": u.get("cache_read_input_tokens") or 0,
                     "create_1h": cc.get("ephemeral_1h_input_tokens") or 0,
                     "model": m.get("model"),
                     "new": Counter(), "events": [], "max_result": 0,
                     "think_est": 0, "last_ts": None, "tool_uses": 0,
                     "results": 0}
                if model and m.get("model") and m.get("model") != model:
                    r["events"].append("model change")
                model = m.get("model") or model
                by_id[mid] = r
                reqs.append(r)
                cur = r
            r = by_id[mid]
            r["last_ts"] = ts_seconds(d.get("timestamp")) or r["last_ts"]
            for c in m.get("content") or []:
                ct = c.get("type")
                if ct == "thinking":
                    r["new"]["thinking"] += max(think_est, est_tokens(c.get("thinking") or ""))
                    think_est = 0
                elif ct == "text":
                    r["new"]["assistant"] += est_tokens(c.get("text") or "")
                elif ct == "tool_use":
                    r["tool_uses"] += 1
                    tool_names[c.get("id")] = (c.get("name"), c.get("input") or {})
                    r["new"]["assistant"] += est_tokens(json.dumps(c.get("input") or {})) + 10
        elif t == "user":
            if d.get("parent_tool_use_id") or cur is None:
                continue
            m = d.get("message") or {}
            content = m.get("content")
            if isinstance(content, str):
                cur["new"]["shell-other"] += est_tokens(content)
                continue
            for b in content or []:
                if b.get("type") == "text":
                    txt = b.get("text") or ""
                    cur["new"]["hook-context" if "<system-reminder>" in txt
                               else "shell-other"] += est_tokens(txt)
                    continue
                if b.get("type") != "tool_result":
                    continue
                txt, image = result_text(b)
                if image:
                    cur["events"].append("image")
                cur["max_result"] = max(cur["max_result"], len(txt))
                cur["results"] += 1
                tid = b.get("tool_use_id")
                name, inp = tool_names.get(tid, ("?", {}))
                if "hook error" in txt[:300] or "blocked hook" in txt[:600]:
                    src = "hook-block"
                elif "Permission for this tool use was denied" in txt or \
                        "requires approval" in txt[:400]:
                    src = "denial"
                else:
                    src = call_source(name, inp)
                cur["new"][src] += est_tokens(txt) + RESULT_OVERHEAD
                for kind, htxt in hook_by_id.get(tid, ()):
                    cur["new"][kind] += est_tokens(htxt) + 20
                    cur["events"].append("hook output")
                if not hooks and checks and name in ("Edit", "Write", "MultiEdit"):
                    # 0.16: check-hook.jsonl has counts, not text; match in order
                    path = (inp.get("file_path") or "")
                    if path.endswith(".vl") and checks:
                        c = checks[0]
                        if c.get("tool") == name and c.get("root", "x").split("/")[-1] \
                                in path:
                            checks.pop(0)
                            n = min(c.get("errors") or 0, 10)
                            cur["new"]["hook-context"] += (60 + 110 * n) / CHARS_PER_TOKEN
                            cur["events"].append("hook output")
    # Stop-hook reasons: after a text-only message that is followed by another
    stop_slots = [r for r in reqs[:-1] if r["tool_uses"] == 0]
    for (kind, text), r in zip(stops, stop_slots):
        r["new"][kind] += est_tokens(text) + 20
        r["events"].append("hook output")

    ttl = 3600 if any(r["create_1h"] for r in reqs) else 300
    turns = []
    totals = Counter()
    split = Counter()
    for k, r in enumerate(reqs):
        turn = {"n": k + 1, "fresh": r["fresh"], "create": r["create"], "read": r["read"]}
        totals["fresh"] += r["fresh"]
        totals["create"] += r["create"]
        totals["read"] += r["read"]
        totals["create_1h"] += r["create_1h"]
        if k == 0:
            turn["class"] = "initial"
            split["initial"] += r["create"]
            totals["initial_read"] = r["read"]
            turns.append(turn)
            continue
        p = reqs[k - 1]
        prev_prompt = p["read"] + p["create"] + p["fresh"]
        new = p["new"]
        est = sum(new.values())
        turn["est_new"] = round(est)
        turn["new"] = {k: round(v) for k, v in new.items() if v}
        turn["results"] = p["results"]
        shortfall = prev_prompt - r["read"]
        if shortfall > SLACK:
            turn["class"] = "break"
            causes = list(dict.fromkeys(p["events"]))
            prompt_now = r["read"] + r["create"] + r["fresh"]
            if prompt_now < prev_prompt * 0.7 and "compaction" not in causes:
                causes.append("compaction (prompt shrank)")
            if r["ts"] and p["last_ts"] and r["ts"] - p["last_ts"] > ttl:
                causes.append("idle %ds > TTL" % (r["ts"] - p["last_ts"]))
            if p["max_result"] > BIG_RESULT:
                causes.append("tool result %d chars" % p["max_result"])
            turn["causes"] = causes or ["unknown"]
            turn["lost"] = shortfall
            # the part of the creation that re-writes the lost prefix
            rebuilt = min(r["create"], shortfall)
            split["break"] += rebuilt
            growth = r["create"] - rebuilt
        else:
            growth = r["create"]
            if r["create"] > 1.5 * est + 4000:
                turn["class"] = "oversize"
                turn["causes"] = list(dict.fromkeys(p["events"])) or ["unknown"]
            else:
                turn["class"] = "growth"
        # attribute growth to the appended content, scaled to the measured count
        if growth > 0:
            if est > 0:
                scale = min(1.0, growth / est)
                for s, v in new.items():
                    split[s] += v * scale
                split["unattributed"] += max(0.0, growth - est)
            else:
                split["unattributed"] += growth
        totals["est_new"] += est
        totals["growth_create"] += growth
        turns.append(turn)
    inp = totals["fresh"] + totals["create"] + totals["read"]
    breaks = [t for t in turns if t["class"] == "break"]
    oversize = [t for t in turns if t["class"] == "oversize"]
    rel = os.path.normpath(rundir).split(os.sep)
    info = {
        "dir": rundir,
        "set": result.get("set") or (rel[-5] if len(rel) >= 5 else "?"),
        "task": rel[-4] if len(rel) >= 4 else "?",
        "model": result.get("model") or (rel[-3].replace("-", ":", 1) if len(rel) >= 3
                                         else "?"),
        "finished": bool(result),
        "cond": result.get("cond") or (rel[-2] if len(rel) >= 2 else "?"),
        "requests": len(reqs),
        "initial_create": reqs[0]["create"] if reqs else 0,
        "initial_read": reqs[0]["read"] if reqs else 0,
        "fresh": totals["fresh"], "create": totals["create"], "read": totals["read"],
        "input": inp,
        "read_share": totals["read"] / inp if inp else 0.0,
        "ttl": "1h" if ttl == 3600 else "5m",
        "breaks": len(breaks),
        "break_causes": Counter(c for t in breaks for c in t["causes"]),
        "oversize": len(oversize),
        "oversize_causes": Counter(c for t in oversize for c in t["causes"]),
        "split": {k: round(v) for k, v in split.items()},
        "est_over_measured": (totals["est_new"] / totals["growth_create"]
                              if totals["growth_create"] else None),
        "subagent_requests": len(sub),
        "subagent_create": sum((u.get("cache_creation_input_tokens") or 0)
                               for u in sub.values()),
        "turns": turns,
    }
    # cost in base-input-token equivalents
    w = WRITE_1H if ttl == 3600 else WRITE_5M
    info["cost_equiv"] = totals["fresh"] + w * totals["create"] + READ * totals["read"]
    info["cost_equiv_5m"] = totals["fresh"] + WRITE_5M * totals["create"] + READ * totals["read"]
    return info


def find_runs(paths):
    out = []
    for p in paths:
        for root, dirs, files in os.walk(p):
            if "transcript.jsonl" in files:
                out.append(root)
                dirs[:] = []
            dirs.sort()
    return sorted(out)


def med(xs):
    return statistics.median(xs) if xs else 0


def aggregate(runs):
    groups = defaultdict(list)
    for r in runs:
        if r["requests"] == 0:
            continue
        groups[(r["set"], r["model"], r["cond"])].append(r)
    rows = []
    for key in sorted(groups):
        rs = groups[key]
        tot_in = sum(r["input"] for r in rs)
        tot_cr = sum(r["create"] for r in rs)
        split = Counter()
        for r in rs:
            split.update(r["split"])
        causes = Counter()
        for r in rs:
            causes.update(r["break_causes"])
        rows.append({
            "set": key[0], "model": key[1], "cond": key[2], "runs": len(rs),
            "requests_med": med([r["requests"] for r in rs]),
            "read_share": sum(r["read"] for r in rs) / tot_in if tot_in else 0,
            "create_med": med([r["create"] for r in rs]),
            "initial_med": med([r["split"].get("initial", 0) for r in rs]),
            "split_share": {k: v / tot_cr for k, v in split.items()} if tot_cr else {},
            "split_per_run": {k: v / len(rs) for k, v in split.items()},
            "breaks_per_run": sum(r["breaks"] for r in rs) / len(rs),
            "oversize_per_run": sum(r["oversize"] for r in rs) / len(rs),
            "break_causes": dict(causes),
            "cost_equiv_med": med([r["cost_equiv"] for r in rs]),
        })
    return rows


GROUPS = [("initial", ["initial"]), ("assist", ["assistant", "thinking"]),
          ("guide", ["guide"]), ("query", ["query", "volec-other"]),
          ("build", ["build-run"]), ("reads", ["file-read", "shell-read", "file-search"]),
          ("edits", ["file-edit"]), ("hooks", ["hook-block", "hook-context", "hook-stop"]),
          ("other", ["shell-other", "denial", "task-notify", "unattributed"]),
          ("breaks", ["break"])]


def md_table(rows):
    head = ("| set | model | cond | runs | req | read % | creation/run | " +
            " | ".join(g for g, _ in GROUPS) + " | breaks/run |")
    out = [head, "|" + "---|" * (head.count("|") - 1)]
    for r in rows:
        sh = r["split_share"]
        cells = ["%.0f" % (100 * sum(sh.get(k, 0) for k in ks)) for _, ks in GROUPS]
        out.append("| %s | %s | %s | %d | %d | %.1f | %s | %s | %.2f |" % (
            r["set"], r["model"].replace("claude:", ""), r["cond"], r["runs"],
            r["requests_med"], 100 * r["read_share"], "%.1fk" % (r["create_med"] / 1000),
            " | ".join(cells), r["breaks_per_run"]))
    return "\n".join(out)


def overall(runs):
    runs = [r for r in runs if r["requests"]]
    tot = Counter()
    split = Counter()
    causes, ocauses = Counter(), Counter()
    for r in runs:
        for k in ("fresh", "create", "read", "input"):
            tot[k] += r[k]
        split.update(r["split"])
        causes.update(r["break_causes"])
        ocauses.update(r["oversize_causes"])
    n = len(runs) or 1
    return {
        "runs": len(runs),
        "read_share": tot["read"] / tot["input"] if tot["input"] else 0,
        "create_share": tot["create"] / tot["input"] if tot["input"] else 0,
        "create_med": med([r["create"] for r in runs]),
        "create_mean": tot["create"] / n,
        "split_per_run": {k: v / n for k, v in split.most_common()},
        "breaks_per_run": sum(r["breaks"] for r in runs) / n,
        "runs_with_break": sum(1 for r in runs if r["breaks"]),
        "break_causes": dict(causes),
        "oversize_per_run": sum(r["oversize"] for r in runs) / n,
        "oversize_causes": dict(ocauses),
        "ttl": dict(Counter(r["ttl"] for r in runs)),
        "subagent_requests": sum(r["subagent_requests"] for r in runs),
    }


def print_text(runs, rows, show_runs):
    o = overall(runs)
    print("runs %d; read share %.1f%%; creation share %.1f%%; creation/run median %.0f "
          "mean %.0f; breaks/run %.2f (%d runs with a break); oversize/run %.2f; ttl %s"
          % (o["runs"], 100 * o["read_share"], 100 * o["create_share"], o["create_med"],
             o["create_mean"], o["breaks_per_run"], o["runs_with_break"],
             o["oversize_per_run"], o["ttl"]))
    print("creation per run by source (tokens; text sources estimated at %.2f chars/token"
          " and scaled to the measured creation):" % CHARS_PER_TOKEN)
    for k, v in o["split_per_run"].items():
        print("  %-15s %8.0f" % (k, v))
    print("break causes:", o["break_causes"] or "none")
    print("oversize causes:", o["oversize_causes"] or "none")
    print()
    print(md_table(rows))
    if show_runs:
        for r in runs:
            print("\n%s  req %d read %.1f%% create %d breaks %d oversize %d est/measured %s"
                  % (r["dir"], r["requests"], 100 * r["read_share"], r["create"],
                     r["breaks"], r["oversize"],
                     "%.2f" % r["est_over_measured"] if r["est_over_measured"] else "-"))
            for t in r["turns"]:
                if t["class"] != "growth":
                    print("   turn %3d %-8s create %6d read %7d est_new %6s %s"
                          % (t["n"], t["class"], t["create"], t["read"],
                             t.get("est_new", "-"), ", ".join(t.get("causes", []))))


def selftest():
    """A synthetic run: an initial prompt, two growth turns, an idle-gap break."""
    def asst(mid, ts, fresh, create, read, content):
        return {"type": "assistant", "parent_tool_use_id": None, "timestamp": ts,
                "message": {"id": mid, "model": "m",
                            "usage": {"input_tokens": fresh,
                                      "cache_creation_input_tokens": create,
                                      "cache_read_input_tokens": read,
                                      "cache_creation": {"ephemeral_5m_input_tokens": create}},
                            "content": content}}

    def tres(tid, text):
        return {"type": "user", "parent_tool_use_id": None,
                "message": {"content": [{"type": "tool_result", "tool_use_id": tid,
                                         "content": text}]}}
    guide = "g" * 4700      # 2000 tokens at 2.35 chars/token
    query = "q" * 2350      # 1000 tokens
    lines = [
        {"type": "system", "subtype": "init"},
        asst("m1", "2026-01-01T00:00:00Z", 2, 20000, 5000,
             [{"type": "tool_use", "id": "t1", "name": "Bash",
               "input": {"command": "volec guide std"}}]),
        tres("t1", guide),
        # growth: about 2000 tokens of guide plus the call
        asst("m2", "2026-01-01T00:00:10Z", 2, 2100, 25000,
             [{"type": "tool_use", "id": "t2", "name": "Bash",
               "input": {"command": "volec query show main"}}]),
        # a subagent line: ignored
        dict(asst("s1", "2026-01-01T00:00:11Z", 2, 9999, 0, []), parent_tool_use_id="t2"),
        tres("t2", query),
        asst("m3", "2026-01-01T00:00:20Z", 2, 1100, 27100,
             [{"type": "tool_use", "id": "t3", "name": "Read",
               "input": {"file_path": "main.vl"}}]),
        tres("t3", "r" * 400),
        # same id again: counted once
        asst("m3", "2026-01-01T00:00:21Z", 2, 1100, 27100, [{"type": "text", "text": "ok"}]),
        # 10 minutes idle on a 5-minute TTL: the prefix expired
        asst("m4", "2026-01-01T00:10:30Z", 2, 28300, 5000, [{"type": "text", "text": "done"}]),
    ]
    with tempfile.TemporaryDirectory() as d:
        run = os.path.join(d, "set", "task", "claude-x", "cond", "rep1")
        os.makedirs(run)
        with open(os.path.join(run, "transcript.jsonl"), "w") as fh:
            for x in lines:
                fh.write(json.dumps(x) + "\n")
        r = analyze_run(run)
    cls = [t["class"] for t in r["turns"]]
    ok = True

    def check(cond, what):
        nonlocal ok
        print(("ok   " if cond else "FAIL ") + what)
        ok = ok and cond
    check(r["requests"] == 4, "four requests (repeated id once, subagent apart): %d"
          % r["requests"])
    check(r["subagent_requests"] == 1, "one subagent request")
    check(cls == ["initial", "growth", "growth", "break"], "classes %s" % cls)
    check(r["split"]["initial"] == 20000, "initial creation 20000")
    check(1900 <= r["split"].get("guide", 0) <= 2100, "guide growth ~2000: %s"
          % r["split"].get("guide"))
    check(950 <= r["split"].get("query", 0) <= 1100, "query growth ~1000: %s"
          % r["split"].get("query"))
    br = r["turns"][3]
    check(br.get("lost") == 28202 - 5000, "break lost the prefix: %s" % br.get("lost"))
    check(any(c.startswith("idle") for c in br["causes"]), "break cause idle: %s"
          % br["causes"])
    check(r["breaks"] == 1 and r["ttl"] == "5m", "one break, 5m TTL")
    check(abs(r["input"] - (8 + 51500 + 62100)) < 1, "input = fresh + creation + read")
    print("selftest", "passed" if ok else "FAILED")
    return 0 if ok else 1


def main(argv):
    if "--selftest" in argv:
        return selftest()
    args = [a for a in argv if not a.startswith("--")]
    md_out = None
    if "--md" in argv:
        i = argv.index("--md")
        md_out = argv[i + 1]
        args = [a for a in args if a != md_out]
    if not args:
        print(__doc__.split("\n\n")[1])
        return 2
    runs = [analyze_run(d) for d in find_runs(args)]
    if "--partial" not in argv:  # runs still going (or a selfcheck): no result.json
        skipped = [r for r in runs if not r["finished"]]
        runs = [r for r in runs if r["finished"]]
        if skipped:
            print("(%d run dirs without result.json skipped; --partial includes them)"
                  % len(skipped), file=sys.stderr)
    rows = aggregate(runs)
    if "--json" in argv:
        for r in runs:
            r = dict(r)
            if "--runs" not in argv:
                r.pop("turns")
            print(json.dumps(r, default=dict))
        print(json.dumps({"overall": overall(runs), "groups": rows}))
    else:
        print_text(runs, rows, "--runs" in argv)
    if md_out:
        with open(md_out, "w") as fh:
            fh.write(md_table(rows) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
