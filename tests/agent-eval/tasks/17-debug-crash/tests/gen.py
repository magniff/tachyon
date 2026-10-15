#!/usr/bin/env python3
# Writes the hidden test inputs of 17-debug-crash (fixed seeds); the
# expected outputs come from the reference solution. Run from this
# directory.
import random
import zlib

TESTS = {}

# 01: the first example of task.md.
TESTS["01"] = """\
# requests per service
SPAN 30
TOP 2
10 api 120
12 db 7
15 api 80
20 api 1500
21 db 13
41 db 3
40 api 9
55 api -40
62 db 2000000
NOTE disk near full on db
"""

# 02: comments, blank lines, tabs, CRLF, every kind of bad line.
TESTS["02"] = (
    "# a comment\r\n"
    "\r\n"
    "   # an indented comment\n"
    "\t\n"
    "5\tweb\t10\r\n"
    "  6   web    -20   \n"
    "7 web\n"
    "7 web 1 2\n"
    "x web 3\n"
    "8 web 3x\n"
    "-1 web 4\n"
    "9 web -\n"
    "9 web 1234567890123456789\n"
    "9 web --5\n"
    "4 web 100\n"
    "9 mail 0\n"
    "9 web 000123\n"
    "SPAN\n"
    "SPAN 0\n"
    "SPAN -3\n"
    "SPAN 10 20\n"
    "WIDTH x\n"
    "TOP -1\n"
    "span 5\n"
    "SPAN 100\n"
    "WIDTH 12\n"
    "TOP 0\n"
    "NOTE\n"
    "NOTE  a   b\tc  \r\n"
    "10 #web 7\n"
)

# 03: the ranking: ties broken by the first event, TOP over the number of
# keys, negative and large sums with digit groups.
lines = ["SPAN 1000", "TOP 9"]
t = 0
for key, vals in [("k1", [5, 5]), ("k2", [10]), ("k3", [-1000, -2345]),
                  ("k4", [3, 7]), ("k5", [999999999, 999999999, 2]),
                  ("k6", [-999]), ("k7", [0])]:
    for v in vals:
        t += 3
        lines.append("%d %s %d" % (t, key, v))
lines.append("%d k2 0" % (t + 1))
TESTS["03"] = "\n".join(lines) + "\n"

# 04: SPAN 1 (only the last instant is recent), equal times, medians of
# an even count, negative medians truncated toward zero.
TESTS["04"] = """\
SPAN 1
TOP 1
1 a 1
1 b -3
2 a 2
2 b -4
5 a 7
5 a 7
5 a 7
9 a -1
9 a -2
9 b -5
9 b -6
9 c 4
9 c 5
9 c 6
9 c 8
NOTE short words only here
"""

# 05: a key with no recent events (the example's second part).
TESTS["05"] = """\
SPAN 10
WIDTH 16
5 old 1
6 old 2
30 new 5
31 new 6
40 new 7
NOTE the old key went quiet
"""

# 06: many quiet keys, wrapped; the only recent one is the last.
lines = ["SPAN 5", "WIDTH 18"]
for i in range(30):
    lines.append("%d host-%d %d" % (i, i, i * 7 - 50))
lines.append("100 last 1")
TESTS["06"] = "\n".join(lines) + "\n"

# 07: two keys with the same hash and length.
TESTS["07"] = """\
TOP 3
1 Aa 10
2 BB 20
3 Aa 30
4 C# 1
5 BB 40
6 AaAa 1
7 BBBB 2
"""


def colliding(n_blocks, rng):
    return "".join(rng.choice(["Aa", "BB"]) for _ in range(n_blocks))


# 08: families of colliding keys among ordinary ones.
rng = random.Random(8)
keys = []
for fam in range(6):
    prefix = "svc%d-" % fam
    family = set()
    while len(family) < 8:
        family.add(prefix + colliding(4, rng))
    keys += sorted(family)
for i in range(40):
    keys.append("plain%d" % i)
lines = ["SPAN 400", "TOP 10", "WIDTH 30"]
t = 0
for i in range(600):
    t += rng.randint(0, 2)
    lines.append("%d %s %d" % (t, rng.choice(keys), rng.randint(-100, 1000)))
for k in keys:  # every key recent
    lines.append("%d %s %d" % (t, k, rng.randint(0, 50)))
TESTS["08"] = "\n".join(lines) + "\n"

# 09: a note word longer than the width, and one exactly as long.
TESTS["09"] = """\
WIDTH 10
1 x 1
NOTE see https://example.com/status/page for details
NOTE exactly10c then x
NOTE a b c d e f g h i j k
"""

# 10: WIDTH 1, quiet keys longer than the width.
TESTS["10"] = """\
WIDTH 1
SPAN 2
1 alpha 1
2 b 2
5 gamma 3
NOTE a bb c
"""


def big(seed, n_keys, n_lines, quiet_every, long_words, vmax, keybits):
    rng = random.Random(seed)
    keys = []
    for i in range(n_keys):
        if i % 50 == 0:
            keys.append("grp%d-%s" % (i // 50 % 7, colliding(3, rng)))
        else:
            keys.append("k%x" % rng.randint(0, 1 << keybits))
    keys = list(dict.fromkeys(keys))
    out = ["SPAN %d" % rng.randint(500, 3000), "TOP 25",
           "WIDTH %d" % rng.randint(20, 70)]
    t = 0
    for i in range(n_lines):
        r = rng.random()
        if r < 0.002:
            out.append("# comment %d" % i)
        elif r < 0.004:
            out.append("%d bad" % t)
        elif r < 0.006:
            words = []
            for _ in range(rng.randint(1, 12)):
                if long_words and rng.random() < 0.05:
                    words.append("x" * rng.randint(70, 90))
                else:
                    words.append("w%d" % rng.randint(0, 999))
            out.append("NOTE " + " ".join(words))
        else:
            t += rng.randint(0, 3)
            k = keys[rng.randrange(len(keys))]
            # some keys only early on, so they go quiet
            if quiet_every and zlib.crc32(k.encode()) % quiet_every == 0 and t > 20000:
                k = keys[0]
            out.append("%d %s %d" % (t, k, rng.randint(-vmax // 1000, vmax)))
    return "\n".join(out) + "\n"


# 11, 12: large inputs, 600-900 KB.
TESTS["11"] = big(11, 9000, 24000, 3, True, 10 ** 9, 40)
TESTS["12"] = big(12, 12000, 45000, 0, False, 9999, 28)

for name, text in TESTS.items():
    with open(name + ".in", "w", newline="") as f:
        f.write(text)
