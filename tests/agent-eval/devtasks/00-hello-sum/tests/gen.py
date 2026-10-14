# Generates the hidden tests: python3 gen.py (writes NN.in / NN.out here).
import os, random

here = os.path.dirname(os.path.abspath(__file__))
rng = random.Random(7)
cases = [
    "3\n-5\n10\n",
    "",
    "42",
    "1\n\n2\n\n\n3\n",
    "-9000000000\n-1\n",
    "\n".join(str(rng.randint(-10**6, 10**6)) for _ in range(30000)) + "\n",
]
for i, inp in enumerate(cases, 1):
    total = sum(int(l) for l in inp.split("\n") if l.strip())
    with open(os.path.join(here, "%02d.in" % i), "w") as f:
        f.write(inp)
    with open(os.path.join(here, "%02d.out" % i), "w") as f:
        f.write("%d\n" % total)
