#!/usr/bin/env python3
"""Writes the hidden test inputs NN.in for 10-refactor-rename.

The expected outputs NN.out come from the Rust reference solution:
    for f in NN.in: ../solution/rust/prog < f > f.out
Fixed seeds: running this again gives the same files.
"""
import random

CASES = {}

CASES[1] = """\
ADD 1 2 The Hobbit
ADD 2 1 Dune
JOIN 7 Ann Lee
LEND 7 1 0
LEND 7 2 3
REPORT STOCK
RETURN 7 1 20
REPORT MEMBERS
PAY 7 100
REPORT SUMMARY
"""

# Errors: usage, bad numbers, unknown commands and reports, missing ids.
CASES[2] = """\
FOO 1 2
add 1 2 lower case
ADD 1
ADD x 2 Title
ADD 1 -2 Title
ADD 1 0 Title
ADD 1 2 Title
JOIN 5
JOIN 5x Bob
JOIN 5 Bob
JOIN 5 Robert
LEND 5 1
LEND 6 1 0
LEND 5 9 0
LEND 5 1 day
RETURN 5 1 3
RETURN 5 1
PAY 5
PAY 9 100
PAY 5 abc
REPORT
REPORT stock
REPORT OVERDUE
REPORT OVERDUE soon
REPORT LOANS
REPORT STOCK
"""

# The fee schedule at its edges: on time, first late day, the end of the
# low rate, the cap.
fee = ["ADD 1 20 Fees and Fines", "JOIN 1 Payer"]
for i, held in enumerate([0, 14, 15, 21, 22, 40, 47, 48, 49, 200]):
    fee.append("JOIN %d Member %d" % (10 + i, i))
    fee.append("LEND %d 1 100" % (10 + i))
fee.append("REPORT OVERDUE 100")
fee.append("REPORT OVERDUE 114")
fee.append("REPORT OVERDUE 115")
fee.append("REPORT OVERDUE 160")
for i, held in enumerate([0, 14, 15, 21, 22, 40, 47, 48, 49, 200]):
    fee.append("RETURN %d 1 %d" % (10 + i, 100 + held))
fee.append("REPORT MEMBERS")
fee.append("REPORT SUMMARY")
CASES[3] = "\n".join(fee) + "\n"

# The loan limit and the debt limit: owing exactly 10.00 may borrow, 10.25
# may not; paying more than owed pays what is owed.
CASES[4] = """\
ADD 1 10 Ten Copies
JOIN 1 Ann
LEND 1 1 0
LEND 1 1 0
LEND 1 1 0
LEND 1 1 0
RETURN 1 1 35
LEND 1 1 36
RETURN 1 1 50
REPORT MEMBERS
JOIN 2 Ben
LEND 2 1 0
RETURN 2 1 34
LEND 2 1 40
RETURN 2 1 61
REPORT MEMBERS
LEND 2 1 61
RETURN 2 1 76
LEND 2 1 90
PAY 2 25
LEND 2 1 90
PAY 2 5000
PAY 2 1
REPORT MEMBERS
REPORT SUMMARY
"""

# Empty library; every report with nothing in it.
CASES[5] = """\
REPORT STOCK
REPORT MEMBERS
REPORT OVERDUE 0
REPORT SUMMARY
"""

# Restocking, the last copy, several loans of one title returned oldest
# first, a return before the loan day.
CASES[6] = """\
ADD 3 1 Moby Dick
LEND 1 3 0
JOIN 1 Ishmael
JOIN 2 Ahab
LEND 1 3 0
LEND 2 3 1
ADD 3 2 ignored title
LEND 2 3 2
LEND 2 3 30
REPORT STOCK
REPORT OVERDUE 31
RETURN 2 3 40
REPORT OVERDUE 40
RETURN 2 3 10
RETURN 2 3 10
RETURN 1 3 0
REPORT STOCK
REPORT MEMBERS
"""

# Comments, blank lines, CRLF line ends, runs of spaces, titles with
# inner spaces kept, no final newline.
CASES[7] = ("# a comment\r\n\r\n   \r\n"
            "ADD   4   2   War  and   Peace  \r\n"
            "JOIN 9    Leo   T.\r\n"
            "  LEND 9 4 5\r\n"
            "#LEND 9 4 5\r\n"
            "REPORT    STOCK\r\n"
            "REPORT MEMBERS\r\n"
            "REPORT OVERDUE 30")


def big(seed, books, members, commands):
    rng = random.Random(seed)
    words = ["Night", "Garden", "River", "Glass", "Iron", "Silent", "Red",
             "House", "Winter", "Song", "Last", "City", "Sea", "Stone"]
    first = ["Ann", "Ben", "Cleo", "Dov", "Eva", "Femi", "Gus", "Hana"]
    out = []
    book_ids = rng.sample(range(1, 10 * books), books)
    member_ids = rng.sample(range(1, 10 * members), members)
    for b in book_ids:
        title = " ".join(rng.choice(words) for _ in range(rng.randint(1, 4)))
        out.append("ADD %d %d %s" % (b, rng.randint(1, 3), title))
    for m in member_ids:
        out.append("JOIN %d %s %d" % (m, rng.choice(first), rng.randint(1, 99)))
    held = []
    day = 0
    for _ in range(commands):
        day += rng.choice([0, 0, 0, 1, 1, 2, 5])
        r = rng.random()
        if r < 0.40:
            m = rng.choice(member_ids)
            b = rng.choice(book_ids)
            out.append("LEND %d %d %d" % (m, b, day))
            held.append((m, b))
        elif r < 0.75 and held:
            m, b = held.pop(rng.randrange(len(held)))
            out.append("RETURN %d %d %d" % (m, b, day))
        elif r < 0.85:
            out.append("PAY %d %d" % (rng.choice(member_ids), rng.randint(1, 2000)))
        elif r < 0.90:
            out.append("ADD %d %d more" % (rng.choice(book_ids), rng.randint(1, 2)))
        elif r < 0.9001:
            out.append("REPORT OVERDUE %d" % day)
        elif r < 0.9998:
            out.append("REPORT SUMMARY")
        else:
            out.append(rng.choice(["REPORT STOCK", "REPORT MEMBERS"]))
    out.append("REPORT STOCK")
    out.append("REPORT MEMBERS")
    out.append("REPORT OVERDUE %d" % day)
    out.append("REPORT SUMMARY")
    return "\n".join(out) + "\n"


CASES[8] = big(8, 40, 15, 2000)
CASES[9] = big(9, 3000, 1500, 25000)

for n, text in CASES.items():
    with open("%02d.in" % n, "w", newline="") as f:
        f.write(text)
