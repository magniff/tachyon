#!/usr/bin/env python3
# Writes the hidden test inputs of 14-ast-pass (fixed seeds); the expected
# outputs come from the reference solution:
#   for f in tests/*.in; do ./prog < $f > ${f%.in}.out; done
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))


def write(name, text, crlf=False):
    if crlf:
        text = text.replace("\n", "\r\n")
    with open(os.path.join(HERE, name + ".in"), "w", newline="") as f:
        f.write(text)


# 01: run, no while: scoping, shadowing, else-if chains, short circuits.
write("01", """#!run
# scoping and shadowing
let x = 10;
let y = 3;
print x / y, x % y, -x / y, -x % y, x / -y, x % -y;
{
    let x = x * 2;      # a new x, from the outer one
    print x;
    x = x + 1;
    y = y + 1;          # the outer y
    print x, y;
}
print x, y;
let x = 7;              # a second let in the same scope
print x;
if x < 5 {
    print 1;
} else if x < 8 {
    let z = 100;
    print 2, z;
} else {
    print 3;
}
print !x, !0, -(-x), !!x;
print 0 && undefined_name, 1 || undefined_name;
print 2 && 3, 0 || 0, 5 || 0, 1 < 2 == 1, 3 != 3;
print 9223372036854775807 + 1, 2 - 3 - 4, 2 * 3 + 4 * 5, (2 + 3) * 4;
""")

# 02: run, while loops.
write("02", """#!run
# Fibonacci numbers
let a = 0;
let b = 1;
let i = 0;
while i < 15 {
    let t = a + b;
    a = b;
    b = t;
    i = i + 1;
}
print a, b, i;
# primes below 60 by trial division
let n = 2;
while n < 60 {
    let d = 2;
    let prime = 1;
    while d * d <= n && prime {
        if n % d == 0 {
            prime = 0;
        }
        d = d + 1;
    }
    if prime {
        print n;
    }
    n = n + 1;
}
# gcd and a nested table
let p = 1071;
let q = 462;
while q != 0 {
    let r = p % q;
    p = q;
    q = r;
}
print p;
let row = 1;
while row <= 4 {
    let col = 1;
    let acc = 0;
    while col <= row {
        acc = acc * 10 + col;
        col = col + 1;
    }
    print row, acc;
    row = row + 1;
}
# a body's let is new on every pass
let k = 0;
while k < 3 {
    let fresh = 5;
    fresh = fresh + k;
    print fresh;
    k = k + 1;
}
while 0 {
    print 999;
}
print k;
""")

# 03: run, runtime errors after output, inside loops.
write("03", """#!run
let total = 0;
let i = 1;
while i <= 5 {
    total = total + 100 / (5 - i + 1);
    print i, total;
    i = i + 1;
}
let j = 3;
while j >= 0 {
    {
        let inner = 12;
        print inner /
            j;
    }
    j = j - 1;
}
print 12345;
""")

# 04: dump, nothing to fold: the shape of every statement.
write("04", """#!dump
let x = 1;
let y = x + 2 * x;
y = -y;
print x, y, !(x < y), x && y || !x;
if x == y {
    print 1;
} else if x > y {
    print 2;
    {
        let z = y;
    }
} else {
    while y < 10 {
        y = y + x;
        if y % 2 { print y; }
    }
}
if y {}
while x <= 3 {
}
{ }
{ print x; { print y; } }
""")

# 05: dump, folding.
write("05", """#!dump
let a = 1 + 2 * 3;
let b = (1 + 2) * a;
let c = a + 1 + 2;
let d = 1 + 2 + a;
let e = -5;
let f = -(2 - 7);
let g = !0 + !7 + !(3 < 2);
print 7 / 2, -7 / 2, 7 % -2, -7 % 2, 10 / 0, 10 % (3 - 3), 0 / 5;
print 9223372036854775807 + 1, -9223372036854775807 - 1, (-9223372036854775807 - 1) / -1, (-9223372036854775807 - 1) % -1;
print 3037000500 * 3037000500, -(-9223372036854775807 - 1);
print 0 && a, 0 && a / 0, 2 && 0, 2 && 3, 1 && a, a && 0, a && 1;
print 1 || a, -3 || a / 0, 0 || 0, 0 || 4, 0 || a, a || 1;
print a * 0, a - a, 0 + a, a / 1;
print (2 < 3) + (3 <= 3) + (4 > 5) + (6 >= 6) + (1 == 1) + (1 != 1);
print !(1 && (2 < 1 || 5 == 5)), -(-(-(4))), !!!0;
print ((a + (2 * 3)) * (10 - 4 / 2)) - (b % (7 - 7));
a = (100 - 1) / (5 + 6) * a;
""")

# 06: dump, dead branches.
write("06", """#!dump
let x = 4;
if 1 { print 1; }
if 0 { print 2; }
if 0 { print 3; } else { print 4; let y = 5; }
if 2 - 2 { print 5; } else if 1 < 0 { print 6; } else if 3 { print 7; } else { print 8; }
if 0 { print 9; } else if 0 { print 10; }
if 0 { print 11; } else if x { print 12; } else { print 13; }
if x { print 14; } else if 1 { print 15; } else { print 16; }
if x { print 17; } else if 0 { print 18; }
if x { print 19; } else if 0 { print 20; } else { print 21; }
if x { print 22; } else if 0 { print 23; } else if x > 2 { print 24; }
if x { } else if 1 { }
while 0 { print 25; }
while 1 < 0 || 0 { print 26; }
while x > 0 && 1 {
    x = x - 1;
    if 1 + 1 == 2 {
        if 0 { print 27; } else { print x * (2 + 2); }
    }
    while 0 && x { print 28; }
}
{
    if 1 {
        if 1 { if 0 { print 29; } }
    }
}
if 0 || 0 {
    while 1 { print 30; }
} else {
    print 31;
}
print 1 + 1 * 2;
""")

# 07: run, branches that are never taken hold errors that must not happen.
write("07", """#!run
let x = 5;
if 0 { print 1 / 0; }
if 0 { print nope; } else if 1 { print x; } else { print 1 % 0; }
print 0 && 1 / 0, 1 || 1 / 0, 0 && missing, 7 || missing;
while 0 { print 1 / 0; }
if 1 - 1 { x = nope; }
print x * 2;
let n = 4;
let acc = 1;
while 1 {
    acc = acc * 10;
    print n, acc;
    n = n - 1;
    acc = acc + 100 / n;
}
print 777;
""")

# 08: a syntax error, run mode: nothing runs.
write("08", """#!run
let x = 1;
print x;
while x < 3 {
    x = x + 1;
}
print x @ 2;
""")

# 09: a syntax error in a while, dump mode: nothing is dumped.
write("09", """#!dump
let x = 1;
while x < 3 {
    x = x + 1;
}
while x < 10
    print x;
""")

# 13: run with \\r\\n line ends, comments, an undefined variable in a loop.
write("13", """#!run
# counts down, with comments everywhere
let n = 3;   # three
while n > 0 { # loop
    print n; # each
    n = n - 1;
}
let s = 0;
{
    let t = 1;
    while t <= 100 { s = s + t; t = t + 1; }
}
print s;
while s > 5000 {
    print s;
    s = s - 1;
    t = 0;
}
""", crlf=True)


# ---- generated programs ----

class Gen:
    def __init__(self, seed, fold_bias):
        self.rng = random.Random(seed)
        self.fold_bias = fold_bias
        self.lines = []
        self.counter = 0

    def lit(self):
        r = self.rng.random()
        if r < 0.1:
            return str(self.rng.choice([0, 1, 2]))
        if r < 0.15:
            return str(self.rng.choice([9223372036854775807, 4611686018427387904, 3037000500]))
        return str(self.rng.randint(0, 999))

    def expr(self, names, depth, const=False):
        rng = self.rng
        if depth <= 0 or rng.random() < 0.3:
            if names and not const and rng.random() < 0.6:
                return rng.choice(names)
            return self.lit()
        k = rng.random()
        sub_const = const or rng.random() < self.fold_bias
        if k < 0.12:
            return rng.choice(["-", "!"]) + self.expr(names, depth - 1, sub_const)
        if k < 0.2:
            return "(" + self.expr(names, depth - 1, sub_const) + ")"
        op = rng.choice(["+", "-", "*", "+", "-", "*", "/", "%", "<", "<=", ">",
                         ">=", "==", "!=", "&&", "||"])
        left = self.expr(names, depth - 1, sub_const)
        right = self.expr(names, depth - 1, sub_const)
        if op in ("/", "%"):
            # never by zero: (e * e + 1) is odd, or a literal from 1 to 9
            if rng.random() < 0.5:
                right = "(" + right + " * " + right + " + 1)"
            else:
                right = str(rng.randint(1, 9))
        return "(" + left + " " + op + " " + right + ")"

    def cond_lit(self):
        return self.rng.choice(["0", "1", "2 - 2", "1 < 2", "3 == 4", "0 && x0", "5 || x0", "!0", "!7"])

    def block(self, names, depth, indent, budget):
        rng = self.rng
        local = list(names)
        n = rng.randint(1, budget)
        pad = "    " * indent
        for _ in range(n):
            r = rng.random()
            if r < 0.25:
                self.counter += 1
                v = "v%d" % self.counter
                self.lines.append("%slet %s = %s;" % (pad, v, self.expr(local, 3)))
                local.append(v)
            elif r < 0.5 and local:
                v = rng.choice(local)
                if v.startswith("i"):
                    continue
                self.lines.append("%s%s = %s;" % (pad, v, self.expr(local, 3)))
            elif r < 0.65:
                k = rng.randint(1, 3)
                self.lines.append("%sprint %s;" % (pad, ", ".join(self.expr(local, 3) for _ in range(k))))
            elif r < 0.8 and depth > 0:
                c = self.cond_lit() if rng.random() < 0.4 else self.expr(local, 2)
                self.lines.append("%sif %s {" % (pad, c))
                self.block(local, depth - 1, indent + 1, max(1, budget // 2))
                while rng.random() < 0.4:
                    c = self.cond_lit() if rng.random() < 0.4 else self.expr(local, 2)
                    self.lines.append("%s} else if %s {" % (pad, c))
                    self.block(local, depth - 1, indent + 1, max(1, budget // 2))
                if rng.random() < 0.5:
                    self.lines.append("%s} else {" % pad)
                    self.block(local, depth - 1, indent + 1, max(1, budget // 2))
                self.lines.append("%s}" % pad)
            elif r < 0.9 and depth > 0:
                self.counter += 1
                i = "i%d" % self.counter
                if rng.random() < 0.15:
                    self.lines.append("%swhile %s {" % (pad, rng.choice(["0", "1 > 2", "0 && x0", "4 - 2 * 2"])))
                    self.block(local, depth - 1, indent + 1, max(1, budget // 2))
                    self.lines.append("%s}" % pad)
                    continue
                self.lines.append("%slet %s = 0;" % (pad, i))
                self.lines.append("%swhile %s < %d {" % (pad, i, rng.randint(0, 4)))
                self.block(local + [i], depth - 1, indent + 1, max(1, budget // 2))
                self.lines.append("%s    %s = %s + 1;" % (pad, i, i))
                self.lines.append("%s}" % pad)
                local.append(i)
            else:
                self.lines.append("%s{" % pad)
                self.block(local, depth - 1, indent + 1, max(1, budget // 2))
                self.lines.append("%s}" % pad)

    def program(self, mode, chunks):
        self.lines = ["#!" + mode, "let x0 = 1;"]
        for _ in range(chunks):
            self.block(["x0"], 3, 0, 6)
        return "\n".join(self.lines) + "\n"


# 10: run, a long-running loop (about ten million passes of the body).
write("10", """#!run
# counts the primes below 250000 by trial division, and a checksum
let n = 2;
let count = 0;
let sum = 0;
while n < 250000 {
    let d = 2;
    let prime = 1;
    while d * d <= n && prime {
        if n % d == 0 { prime = 0; }
        d = d + 1;
    }
    if prime && 1 + 1 == 2 {
        count = count + 1;
        sum = (sum * 31 + n) % 1000000007;
    }
    n = n + 1;
}
print count, sum;
let i = 0;
let h = 7;
while i < 1000000 {
    h = h * 6364136223846793005 + 1442695040888963407;
    if (h / 3) % 2 == 0 || 0 { h = h + i; } else { h = h - (2 * 3); }
    i = i + 1;
}
print h;
""")

# 11 and 12: one big generated program, dumped and run.
big = Gen(14001, 0.35).program("dump", 1400)
write("11", big)
write("12", "#!run" + big[len("#!dump"):])

# 14: a smaller generated program, dumped (more folding).
write("14", Gen(14002, 0.6).program("dump", 60))
