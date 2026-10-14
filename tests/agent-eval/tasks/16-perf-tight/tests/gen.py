#!/usr/bin/env python3
# Writes the hidden test inputs of 16-perf-tight (each one line: h w q p
# dmax seed); the expected outputs come from the reference solution
# (solution/rust): `../prog < NN.in > NN.out`.
TESTS = [
    "5 6 5 25 4 1",                          # the example in task.md
    "1 1 1 0 0 0",                           # one open cell, d = 0
    "1 1 3 100 5 9",                         # one wall: every answer 0
    "50 50 1000 30 0 77",                    # dmax = 0: answers 0 or 1
    "1 2000 200000 10 30 5",                 # one row
    "2000 1 200000 10 30 6",                 # one column
    "2000 2000 200000 100 30 3",             # all walls
    "2000 2000 200000 0 30 2026",            # no walls: full diamonds
    "2000 2000 200000 10 30 7",              # large, few walls
    "2000 2000 200000 30 30 99",             # large, near the percolation edge
    "2000 2000 200000 20 30 1000000000000000000",  # the largest seed
    "1500 2000 200000 5 30 31337",           # large, rectangular
]

for i, t in enumerate(TESTS, 1):
    with open("%02d.in" % i, "w") as f:
        f.write(t + "\n")
