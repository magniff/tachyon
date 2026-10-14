# Generates the hidden tests: python3 gen.py (writes NN.in / NN.out here).
import os, random

here = os.path.dirname(os.path.abspath(__file__))
rng = random.Random(11)
cases = [
    "-7\n-3\n-12\n",
    "5\n1\n9\n",
    "0",
    "-1",
    "\n4\n\n-4\n",
    "\n".join(str(rng.randint(-10**6, -1)) for _ in range(30000)) + "\n",
]
for i, inp in enumerate(cases, 1):
    best = max(int(l) for l in inp.split("\n") if l.strip())
    with open(os.path.join(here, "%02d.in" % i), "w") as f:
        f.write(inp)
    with open(os.path.join(here, "%02d.out" % i), "w") as f:
        f.write("%d\n" % best)
