"""(0.18) `run.py binaudit DIR... [--expect FILE|MD5]`: which compiler each
program run used (the 0.17 iterations' iter/binaudit.py, in the tree).

Per run: the md5 the runner recorded (result.json's tachyonc_md5, 0.18)
and the md5 of `bin-tach/tachyonc` in the workspace root its transcript
names (its cwd), which is what the agent ran (a stale copy there was the
0.17 iterations' shared-root bug). Per (model, condition): the binaries
seen and how many runs each. With --expect, every run must show that md5
both ways (exit 1 otherwise); a root that is gone counts by its record."""

import hashlib
import json
import os
import re
import sys
from collections import Counter, defaultdict

_cache = {}


def md5(path):
    if path not in _cache:
        if not os.path.isfile(path):
            _cache[path] = None
        else:
            h = hashlib.md5()
            with open(path, "rb") as fh:
                h.update(fh.read())
            _cache[path] = h.hexdigest()
    return _cache[path]


def root_of(rdir, res):
    tp = os.path.join(rdir, "transcript.jsonl")
    if os.path.isfile(tp):
        with open(tp) as fh:
            for line in fh:
                if '"cwd"' in line:
                    m = re.search(r'"cwd": ?"([^"]+)"', line)
                    if m:
                        r = re.search(r"(.*/tachyon-eval/[^/]+)/", m.group(1))
                        if r:
                            return r.group(1)
                        break
    return res.get("ws_root")


def main(args):
    want = None
    if args.expect:
        want = md5(args.expect) if os.path.isfile(args.expect) else args.expect
    bad = 0
    for d in args.rundirs:
        cells = defaultdict(Counter)
        for rdir, _, files in os.walk(d):
            if "result.json" not in files:
                continue
            with open(os.path.join(rdir, "result.json")) as fh:
                res = json.load(fh)
            if res.get("dry_run") or res.get("lang") != "tach":
                continue
            root = root_of(rdir, res)
            seen = md5(os.path.join(root, "bin-tach", "tachyonc")) if root else None
            rec = res.get("tachyonc_md5")
            got = seen or rec
            key = "%s (recorded %s)" % ((seen or "root gone")[:8], (rec or "-")[:8])
            cells[(res["model"], res["cond"])][key] += 1
            if want and (got != want or (rec and rec != want)):
                bad += 1
                print("MISMATCH %s: ran %s, recorded %s, want %s" % (
                    os.path.relpath(rdir, d), seen, rec, want))
        for k in sorted(cells):
            print("%s %s %s %s" % (d, k[0], k[1], dict(cells[k])))
    if want:
        print("binaudit: %s" % ("every run used %s" % want[:8] if not bad
                                else "%d runs did not use %s" % (bad, want[:8])))
    return 1 if bad else 0
