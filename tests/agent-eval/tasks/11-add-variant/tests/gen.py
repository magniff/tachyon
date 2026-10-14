#!/usr/bin/env python3
"""Writes the hidden test inputs NN.in for 11-add-variant.

The expected outputs NN.out come from the Rust reference solution:
    ../solution/rust/prog < NN.in > NN.out
Fixed seeds: running this again gives the same files.
"""
import random

CASES = {}

# The example of task.md: pick at several depths, with a listing.
CASES[1] = """\
.list
push 10
push 20
push 30
pick 0      ; like dup
pick 2      ; the 10
add
print
pick 1
print
"""

# Sum of squares 1..n with pick reading the loop variable, and a
# fibonacci loop with pick in place of over.
CASES[2] = """\
.list
; sum of i*i for i = 10 down to 1
    push 10     ; n
    push 0      ; acc
square:
    pick 1
    pick 2
    mul
    add         ; n acc+n*n
    swap
    push 1
    sub
    swap        ; n-1 acc
    pick 1
    jz done
    jmp square
done:
    print
    pop
; fibonacci below 1000
    push 0
    push 1
fib:
    pick 1
    print
    swap
    pick 1
    add
    pick 1
    push 1000
    lt
    jz end
    jmp fib
end:
    halt
"""

# pick needs n+1 values: pick 2 on two values is an underflow.
CASES[3] = """\
push 1
push 2
pick 1
pick 1
pop
pop
pick 2
print
"""

# Where jumps meet, the depth is checked; pick on a path that is short.
CASES[4] = """\
    push 0
    jz short
    push 5
    push 6
    jmp join
short:
    push 7
    push 8
join:
    pick 1
    print
    print
    print
    pick 0
"""

# A bad depth.
CASES[5] = """\
; negative depths are refused
push 1
pick -1
"""

# Not a number: labels are not depths.
CASES[6] = """\
top:
push 1
pick top
"""

# A missing operand, line counted with comments and blank lines.
CASES[7] = """\
; header

push 3

pick
"""

# An extra operand.
CASES[8] = """\
push 3
pick 0 0
"""

# The deepest pick: 63 values, pick 62 copies the bottom one; then one more
# pick goes past the depth limit.
deep = ["push %d" % (i * 7 + 1) for i in range(63)]
deep += ["pick 62", "print", "pick 62", "print"]
CASES[9] = "\n".join(deep) + "\n"
deep = ["push %d" % i for i in range(64)] + ["pick 0"]
CASES[10] = "\n".join(deep) + "\n"

# A loop that never ends: out of steps, with picks counted as stack steps.
CASES[11] = """\
push 1
loop:
pick 0
add
jmp loop
"""

# Division by zero after picks; the machine's stack at that point.
CASES[12] = """\
push 9
push 0
pick 1
pick 1
div
"""


def big(seed, n):
    """A long straight-line program: random pushes, picks, arithmetic and
    prints, with the depth kept between 1 and 64."""
    rng = random.Random(seed)
    lines = [".list"] if n < 2000 else []
    depth = 0
    for _ in range(n):
        r = rng.random()
        if depth < 2 or (r < 0.15 and depth < 64):
            lines.append("push %d" % rng.randint(-1000, 1000))
            depth += 1
        elif r < 0.55 and depth < 64:
            lines.append("pick %d" % rng.randrange(depth))
            depth += 1
        elif r < 0.75:
            lines.append(rng.choice(["add", "sub", "mul", "lt", "eq"]))
            depth -= 1
        elif r < 0.85:
            lines.append(rng.choice(["swap", "over" if depth < 64 else "swap"]))
            depth += 1 if lines[-1] == "over" else 0
        elif r < 0.95:
            lines.append("print")
            depth -= 1
        else:
            lines.append("pop")
            depth -= 1
    lines.append("halt")
    return "\n".join(lines) + "\n"


CASES[13] = big(13, 400)
CASES[14] = big(14, 60000)

for k, text in CASES.items():
    with open("%02d.in" % k, "w") as f:
        f.write(text)
