#!/usr/bin/env python3
"""A small TextMate tokenizer for testing syntaxes/vole.tmLanguage.json
without node.

It implements the subset of TextMate the grammar uses (match, begin/end,
captures, beginCaptures, endCaptures, contentName, include of #rule,
$self and the grammar's own scope) with Python's re, which agrees with
Oniguruma on every construct the grammar uses (lookarounds, classes,
\\b, $). It reads the same test files as vscode-tmgrammar-test and
writes snapshots in vscode-tmgrammar-snap's format, so the files stay
valid when the npm tools are installed (`npm test`).

    python3 test/tmgrammar.py            # assertions + snapshot comparison
    python3 test/tmgrammar.py --update   # rewrite the snapshots
    python3 test/tmgrammar.py --dump FILE  # print one file's tokens

Assertion files (test/samples/*.test.vl) start with
    // SYNTAX TEST "source.vole" "description"
and carry lines such as
    //  ^^^^^ storage.modifier.convention.vole
    // <--- storage.type.binding.vole
    //   ^ - string.quoted.double.vole
under the source line they describe: every scope listed must be on each
marked character, in order; scopes after `-` must not be.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GRAMMAR = os.path.join(HERE, "..", "syntaxes", "vole.tmLanguage.json")
SAMPLES = os.path.join(HERE, "samples")
SNAPSHOTS = os.path.join(HERE, "snapshots")


class Grammar:
    def __init__(self, path):
        with open(path) as f:
            g = json.load(f)
        self.scope = g["scopeName"]
        self.repo = g.get("repository", {})
        self.root = {"patterns": g["patterns"]}
        self._re = {}
        self._flat = {}

    def regex(self, src):
        r = self._re.get(src)
        if r is None:
            r = re.compile(src)
            self._re[src] = r
        return r

    def resolve(self, rule):
        inc = rule.get("include")
        if inc is None:
            return rule
        if inc in ("$self", "$base", self.scope):
            return self.root
        if inc.startswith("#"):
            return self.repo[inc[1:]]
        raise ValueError("unsupported include " + inc)

    def patterns(self, rule):
        """The match/begin rules reachable from rule's patterns, in order."""
        key = id(rule)
        if key in self._flat:
            return self._flat[key]
        out = []
        seen = set()

        def walk(r):
            r = self.resolve(r)
            if "match" in r or "begin" in r:
                out.append(r)
                return
            if id(r) in seen:
                return
            seen.add(id(r))
            for p in r.get("patterns", []):
                walk(p)

        for p in rule.get("patterns", []):
            walk(p)
        self._flat[key] = out
        return out


def names(n):
    return n.split() if n else []


class Tokenizer:
    def __init__(self, grammar):
        self.g = grammar
        # a frame: (rule, scopes outside the rule, scopes of its content)
        self.stack = [(grammar.root, [grammar.scope], [grammar.scope])]

    def _paint(self, chars, m, base, caps):
        for i in range(m.start(), m.end()):
            chars[i] = list(base)
        if not caps:
            return
        for gi in sorted(caps, key=int):
            gi_n = int(gi)
            if gi_n > m.re.groups or m.start(gi_n) < 0:
                continue
            for i in range(m.start(gi_n), m.end(gi_n)):
                chars[i] = chars[i] + names(caps[gi].get("name"))

    def line(self, text):
        """Tokens of one line (text without its newline) as (start, end, scopes)."""
        src = text + "\n"
        chars = [None] * len(src)
        pos = 0
        stuck = 0
        while pos < len(src):
            rule, outer, inner = self.stack[-1]
            best = None
            if "end" in rule:
                m = self.g.regex(rule["end"]).search(src, pos)
                if m:
                    best = (m.start(), 0, m, None)
            for k, r in enumerate(self.g.patterns(rule)):
                m = self.g.regex(r.get("match") or r["begin"]).search(src, pos)
                if not m:
                    continue
                if m.end() == m.start() and "match" in r:
                    continue
                if best is None or m.start() < best[0]:
                    best = (m.start(), k + 1, m, r)
            if best is None:
                for i in range(pos, len(src)):
                    chars[i] = list(inner)
                break
            start, _, m, r = best
            for i in range(pos, start):
                chars[i] = list(inner)
            if r is None:  # the end of the current begin/end rule
                caps = rule.get("endCaptures") or rule.get("captures")
                self._paint(chars, m, outer + names(rule.get("name")), caps)
                self.stack.pop()
            elif "match" in r:
                self._paint(chars, m, inner + names(r.get("name")), r.get("captures"))
            else:
                scoped = inner + names(r.get("name"))
                caps = r.get("beginCaptures") or r.get("captures")
                self._paint(chars, m, scoped, caps)
                self.stack.append((r, inner, scoped + names(r.get("contentName"))))
            if m.end() == pos:
                stuck += 1
                if stuck > 50:
                    raise RuntimeError("no progress at column %d: %r" % (pos, text))
            else:
                stuck = 0
            pos = m.end()
        # merge equal neighbours; the newline is not a token
        toks = []
        for i, sc in enumerate(chars[: len(text)]):
            if toks and toks[-1][2] == sc:
                toks[-1][1] = i + 1
            else:
                toks.append([i, i + 1, sc])
        return [tuple(t) for t in toks]


def tokenize(grammar, text):
    t = Tokenizer(grammar)
    return [(line, t.line(line)) for line in text.split("\n")]


def snapshot(grammar, text):
    out = []
    for line, toks in tokenize(grammar, text):
        out.append(">" + line)
        for s, e, sc in toks:
            out.append("#" + " " * s + "^" * (e - s) + " " + " ".join(sc))
    return "\n".join(out) + "\n"


ASSERT = re.compile(r"^(\s*//)(\s*)(\^+|<~*-+)\s+(.*)$")


def check_assertions(grammar, path):
    with open(path) as f:
        text = f.read()
    lines = text.split("\n")
    if not lines[0].startswith("// SYNTAX TEST"):
        return []
    fails = []
    last_src = None
    for n, (line, toks) in enumerate(tokenize(grammar, text)):
        m = ASSERT.match(line) if n > 0 else None
        if not m:
            last_src = (n, line, toks)
            continue
        if last_src is None:
            continue
        sn, sline, stoks = last_src
        marks = m.group(3)
        if marks.startswith("<"):
            skip = marks.count("~")
            cols = range(skip, skip + marks.count("-"))
        else:
            first = len(m.group(1)) + len(m.group(2))
            cols = range(first, first + len(marks))
        words = m.group(4).split()
        cut = words.index("-") if "-" in words else len(words)
        want, avoid = words[:cut], words[cut + 1:]
        for c in cols:
            sc = next((t[2] for t in stoks if t[0] <= c < t[1]), None)
            where = "%s:%d:%d" % (os.path.relpath(path), sn + 1, c + 1)
            if sc is None:
                fails.append("%s: no token (line is %d long)" % (where, len(sline)))
                continue
            it = iter(sc)
            if not all(w in it for w in want):
                fails.append("%s: want %s, got %s" % (where, " ".join(want), " ".join(sc)))
            bad = [a for a in avoid if a in sc]
            if bad:
                fails.append("%s: must not have %s, got %s" % (where, " ".join(bad), " ".join(sc)))
    return fails


def main(argv):
    grammar = Grammar(GRAMMAR)
    if argv[:1] == ["--dump"]:
        with open(argv[1]) as f:
            sys.stdout.write(snapshot(grammar, f.read()))
        return 0
    update = "--update" in argv
    files = sorted(f for f in os.listdir(SAMPLES) if f.endswith(".vl"))
    fails = []
    asserts = 0
    for f in files:
        path = os.path.join(SAMPLES, f)
        fl = check_assertions(grammar, path)
        asserts += 1
        fails += fl
        with open(path) as fh:
            snap = snapshot(grammar, fh.read())
        sp = os.path.join(SNAPSHOTS, f + ".snap")
        if update or not os.path.exists(sp):
            with open(sp, "w") as fh:
                fh.write(snap)
        else:
            with open(sp) as fh:
                old = fh.read()
            if old != snap:
                a, b = old.split("\n"), snap.split("\n")
                k = next(i for i in range(min(len(a), len(b))) if a[i] != b[i]) if any(
                    x != y for x, y in zip(a, b)) else min(len(a), len(b))
                fails.append("%s: snapshot differs at line %d:\n  was: %s\n  now: %s"
                             % (os.path.relpath(sp), k + 1, a[k] if k < len(a) else "",
                                b[k] if k < len(b) else ""))
    for f in fails:
        print(f)
    print("%d files, %d failures%s" % (len(files), len(fails), " (snapshots updated)" if update else ""))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
