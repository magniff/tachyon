#!/usr/bin/env python3
# Writes the hidden test inputs of 18-api-refactor (fixed seeds); the
# expected outputs come from the reference solution:
#   for f in NN.in: ./prog < NN.in > NN.out
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))


def write(name, text):
    with open(os.path.join(HERE, name + ".in"), "w", newline="") as fh:
        fh.write(text)


def random_map(rng, h, w, boxes, goals, tele_pairs, wall_rate=0.15):
    grid = [["#"] * w for _ in range(h)]
    for r in range(1, h - 1):
        for c in range(1, w - 1):
            grid[r][c] = "#" if rng.random() < wall_rate else "."
    free = [(r, c) for r in range(1, h - 1) for c in range(1, w - 1) if grid[r][c] == "."]
    rng.shuffle(free)
    k = 0
    r, c = free[k]; k += 1
    grid[r][c] = "@"
    for _ in range(tele_pairs * 2):
        r, c = free[k]; k += 1
        grid[r][c] = "T"
    for _ in range(boxes):
        r, c = free[k]; k += 1
        grid[r][c] = "$"
    for _ in range(goals):
        r, c = free[k]; k += 1
        grid[r][c] = "*" if rng.random() < 0.2 else "G"
    return ["".join(row) for row in grid]


def random_commands(rng, n, h, w, show_rate=0.002):
    cmds = []
    marks = 0
    for _ in range(n):
        x = rng.random()
        if x < 0.55:
            d = rng.choice("NSEW")
            k = rng.random()
            if k < 0.5:
                cmds.append(d)
            elif k < 0.97:
                cmds.append("%s %d" % (d, rng.randint(1, 8)))
            elif k < 0.98:
                cmds.append("%s 0" % d)
            elif k < 0.99:
                cmds.append("%s 1 2" % d)
            else:
                cmds.append("%s  %d" % (d, rng.randint(1, 3)))
        elif x < 0.65:
            cmds.append("UNDO" if rng.random() < 0.5 else "UNDO %d" % rng.randint(1, 6))
        elif x < 0.70:
            cmds.append("WHERE")
        elif x < 0.73:
            cmds.append("BOXES")
        elif x < 0.76:
            cmds.append("MARK")
            marks += 1
        elif x < 0.77:
            cmds.append("MARKS")
        elif x < 0.84:
            if rng.random() < 0.95:
                cmds.append("DIST %d %d" % (rng.randrange(h), rng.randrange(w)))
            else:
                cmds.append("DIST %d %d" % (rng.randrange(h + 3), rng.randrange(w + 3)))
        elif x < 0.89:
            cmds.append("GOTO %d" % rng.randint(0, marks + 1))
        elif x < 0.91:
            cmds.append("HISTORY")
        elif x < 0.94:
            cmds.append("STATUS")
        elif x < 0.94 + show_rate:
            cmds.append("SHOW")
        elif x < 0.955:
            cmds.append("# note %d" % rng.randint(0, 99))
        elif x < 0.96:
            cmds.append("")
        elif x < 0.965:
            cmds.append(rng.choice(["JUMP", "n", "Undo", "WHERE 1", "STATUS x", "GOTO", "DIST 1"]))
        elif x < 0.967:
            cmds.append("RESET")
            marks = 0
        else:
            cmds.append(rng.choice("NSEW") + " " + str(rng.randint(1, 3)))
    return cmds


def build(rng, h, w, boxes, goals, tele, n, crlf=False, show_rate=0.002):
    m = random_map(rng, h, w, boxes, goals, tele)
    cmds = random_commands(rng, n, h, w, show_rate)
    nl = "\r\n" if crlf else "\n"
    return nl.join(m + ["---"] + cmds) + nl


def main():
    # 01: the example of task.md
    write("01", """#######
#@.$.G#
#.T#T.#
#..*..#
#######
---
WHERE
E 3
STATUS
SHOW
W
S
MARK
N 2
UNDO 2
BOXES
DIST 3 5
GOTO 1
GOTO 4
MARKS
FOO bar
E x
""")
    # 02-08: one load error each, and a good map with no commands.
    write("02", "---\nWHERE\n")
    write("03", "#####\n#@..#\n#####\nWHERE\n")
    write("04", "#####\n#@.$#\n#.G.##\n#####\n---\nWHERE\n")
    write("05", "#####\n#@.$#\n#.Gx#\n#####\n---\nWHERE\n")
    write("06", "######\n#@.$.#\n#.G.@#\n#..@.#\n######\n---\nWHERE\n")
    write("07", "#####\n#..$#\n#.G.#\n#####\n---\nSTATUS\n"
          "#####\n#@..#\n#####\n---\n")
    write("08", "#######\n#@T.$G#\n#.T.T.#\n#######\n---\nWHERE\n")
    # 09: every command with its errors, by hand.
    write("09", """#########
#@.$..T.#
#.##.#..#
#.$..G..#
#T.#*.#.#
#########
---
STATUS
E 2
E 2
E
E
WHERE
SHOW
UNDO 3
WHERE
BOXES
UNDO 100
UNDO
HISTORY
S 4
WHERE
W 9
WHERE
MARK
MARKS
DIST 1 7
DIST 4 1
DIST 0 0
DIST 1 1
DIST 9 1
DIST 1 99
DIST 1
DIST a b
GOTO 1
GOTO 0
GOTO 2
GOTO x
GOTO 1 2
N 0
N -1
N 1234567890
N 1 1
UNDO 0
UNDO x
RESET 1
RESET
STATUS
MARKS
UNDO
  E   2
WHERE
# a comment
#E 5

S 2
E 3
N
SHOW
BOXES
STATUS
HISTORY
BOGUS
w
""")
    # 10: \\r\\n line ends, a solved level, an empty box list
    write("10", "#####\r\n#@.G#\r\n#.$.#\r\n#####\r\n---\r\nBOXES\r\nS\r\nE\r\nN\r\nBOXES\r\n"
          "STATUS\r\nSHOW\r\nUNDO 9\r\nSHOW\r\n")
    write("11", "####\r\n#@.#\r\n####\r\n---\r\nBOXES\r\nE 5\r\nSTATUS\r\nSHOW\r\nW\r\n")
    # 12-14: generated
    rng = random.Random(1801)
    write("12", build(rng, 12, 16, 8, 8, 2, 400, show_rate=0.02))
    rng = random.Random(1802)
    write("13", build(rng, 40, 60, 70, 60, 6, 20000))
    rng = random.Random(1803)
    write("14", build(rng, 60, 60, 120, 100, 10, 25000, crlf=True))


main()
