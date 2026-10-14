#!/usr/bin/env python3
# Writes the large hidden test input of 08-fix-compile (fixed seed); the
# expected outputs come from the reference solution.
import random

rng = random.Random(8)
WORDS = ["alpha", "beta", "gamma", "delta", "omega", "kappa", "sigma", "tau", "rho", "phi"]
lines = ["id, name , score,ratio, note,  city"]
for i in range(6000):
    name = " ".join(rng.choice(WORDS) for _ in range(rng.randint(1, 3)))
    score = str(rng.randint(-5000, 99999))
    ratio = "%d.%0*d" % (rng.randint(0, 999), rng.randint(1, 3), rng.randint(0, 99))
    note = rng.choice(["", "ok", "late", "n/a", "12", "-", "x" * rng.randint(1, 30)])
    city = rng.choice(["Oslo", "Lima", "Kyiv", "Pune", "", "Nairobi"])
    fields = [str(i + 1), name, score, ratio, note, city]
    if rng.random() < 0.05:
        fields = fields[:rng.randint(1, 5)]
    sep = rng.choice([",", ", ", " ,", " , "])
    lines.append(sep.join(fields))
    if rng.random() < 0.02:
        lines.append(rng.choice(["", "   ", "\t"]))
open("09.in", "w").write("\n".join(lines) + "\n")
