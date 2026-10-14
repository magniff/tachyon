#!/usr/bin/env python3
# Writes the generated hidden test inputs of 09-extend-calc (fixed seeds);
# the expected outputs come from the reference solution. Expressions whose
# intermediate values leave +-2^62 are thrown away, so no test overflows.
import random

LIMIT = 1 << 62

class Bad(Exception):
    pass

def tdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q

def check(v):
    if abs(v) > LIMIT:
        raise Bad()
    return v

def gen_expr(rng, names, depth):
    # returns (text, value or None for an error)
    if depth <= 0 or rng.random() < 0.25:
        r = rng.random()
        if names and r < 0.45:
            n = rng.choice(names)
            return n
        if r < 0.46:
            return "undefined_" + str(rng.randint(0, 3))
        return str(rng.randint(0, 1000))
    r = rng.random()
    if r < 0.12:
        return "-" + gen_expr(rng, names, depth - 1)
    if r < 0.22:
        return "(" + gen_expr(rng, names, depth - 1) + ")"
    op = rng.choice(["+", "-", "*", "/", "%", "+", "-", "<", "<=", ">", ">=", "==", "!="])
    sp = rng.choice(["", " "])
    return gen_expr(rng, names, depth - 1) + sp + op + sp + gen_expr(rng, names, depth - 1)

# A small evaluator with the task's grammar, to filter out overflow.
def tokenize(s):
    toks = []
    i = 0
    while i < len(s):
        c = s[i]
        if c in " \t":
            i += 1
        elif c.isdigit():
            j = i
            while j < len(s) and s[j].isdigit():
                j += 1
            toks.append(("num", int(s[i:j])))
            i = j
        elif c.isalpha() or c == "_":
            j = i
            while j < len(s) and (s[j].isalnum() or s[j] == "_"):
                j += 1
            toks.append(("name", s[i:j]))
            i = j
        elif s[i:i + 2] in ("<=", ">=", "==", "!="):
            toks.append((s[i:i + 2], None))
            i += 2
        else:
            toks.append((c, None))
            i += 1
    toks.append(("end", None))
    return toks

class Ev:
    def __init__(self, toks, env):
        self.t, self.p, self.env = toks, 0, env
    def peek(self):
        return self.t[self.p][0]
    def next(self):
        tok = self.t[self.p]
        self.p += 1
        return tok
    def binary(self, sub, ops):
        a = sub()
        while self.peek() in ops:
            op = self.next()[0]
            b = sub()
            a = None if a is None or b is None else self.apply(op, a, b)
        return a
    def apply(self, op, a, b):
        if op in "/%" and b == 0:
            return None
        return check({
            "+": lambda: a + b, "-": lambda: a - b, "*": lambda: a * b,
            "/": lambda: tdiv(a, b), "%": lambda: a - tdiv(a, b) * b,
            "<": lambda: int(a < b), "<=": lambda: int(a <= b), ">": lambda: int(a > b),
            ">=": lambda: int(a >= b), "==": lambda: int(a == b), "!=": lambda: int(a != b),
        }[op]())
    def expr(self):
        return self.binary(self.rel, ("==", "!="))
    def rel(self):
        return self.binary(self.add, ("<", "<=", ">", ">="))
    def add(self):
        return self.binary(self.term, ("+", "-"))
    def term(self):
        return self.binary(self.unary, ("*", "/", "%"))
    def unary(self):
        if self.peek() == "-":
            self.next()
            v = self.unary()
            return None if v is None else -v
        kind, val = self.next()
        if kind == "num":
            return val
        if kind == "name":
            return self.env.get(val)
        v = self.expr()
        self.next()
        return v

def big(seed, nlines, depth):
    rng = random.Random(seed)
    env = {}
    names = []
    out = []
    while len(out) < nlines:
        e = gen_expr(rng, names, rng.randint(1, depth))
        try:
            v = Ev(tokenize(e), env).expr()
        except Bad:
            continue
        r = rng.random()
        if r < 0.35:
            name = rng.choice(names) if names and rng.random() < 0.4 else rng.choice("abcdefghxyz") + str(rng.randint(0, 40))
            out.append("let " + name + " = " + e)
            if v is not None:
                env[name] = v
                if name not in names:
                    names.append(name)
        else:
            out.append(e)
        if rng.random() < 0.02:
            out.append(rng.choice(["", "# note", "   ", "1 +", "let = 4", "(" + e]))
    return "\n".join(out) + "\n"

open("09.in", "w").write(big(9, 20000, 7))
open("10.in", "w").write(big(10, 400, 4))

# 11: deep nesting
deep = []
deep.append("(" * 300 + "1" + ")" * 300)
deep.append("-" * 301 + "5")
deep.append("- " * 200 + "(" * 150 + "2 * -3" + ")" * 150)
deep.append("let v = " + " + ".join(str(i) for i in range(1, 3001)))
deep.append(" - ".join(["v"] * 1000))
deep.append("(" * 200 + "1")
open("11.in", "w").write("\n".join(deep) + "\n")
