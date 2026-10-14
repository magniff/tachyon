# Generates the large tests (06, 07) with fixed seeds.
import random

def rand_num(r):
    k = r.random()
    if k < 0.6:
        return str(r.randint(-100, 1000))
    if k < 0.8:
        return str(r.randint(-10**6, 10**6))
    if k < 0.95:
        return str(r.randint(-2**63, 2**63 - 1))
    return r.choice(['0', '-1', '9223372036854775807', '-9223372036854775808', '0000', '-0'])

def expression(r, size, bad_rate, ops=('+', '-', '*', '*', '/', '%', 'swap')):
    toks = []
    depth = 0
    for _ in range(size):
        if depth >= 2 and r.random() < 0.55:
            toks.append(r.choice(ops))
            if toks[-1] != 'swap':
                depth -= 1
        elif depth >= 1 and r.random() < 0.1:
            toks.append('dup')
            depth += 1
        else:
            toks.append(rand_num(r))
            depth += 1
    while depth > 1:
        toks.append(r.choice([o for o in ops if o != 'swap']))
        depth -= 1
    if r.random() < bad_rate:
        k = r.random()
        pos = r.randint(0, len(toks))
        if k < 0.3:
            toks.insert(pos, r.choice(['+5', '--1', '1.5', 'x', 'DUP', 'dupe', '1-', '*/']))
        elif k < 0.6:
            toks.insert(pos, r.choice(['+', '-', 'swap', 'dup']))
        elif k < 0.8:
            toks.insert(pos, '0')
            toks.insert(pos + 1, r.choice(['/', '%']))
        else:
            toks.insert(pos, rand_num(r))
    sep = '  ' if r.random() < 0.1 else ' '
    return sep.join(toks)

r = random.Random(6)
with open('06.in', 'w') as f:
    for _ in range(8000):
        f.write(expression(r, r.randint(1, 40), 0.3) + '\n')

r = random.Random(7)
with open('07.in', 'w') as f:
    # Deep stacks: many pushes, then the operators.
    for k in range(3):
        n = 10000
        nums = [str(r.randint(-1000, 1000)) for _ in range(n)]
        ops = [r.choice(['+', '-', '*']) for _ in range(n - 1)]
        f.write(' '.join(nums + ops) + '\n')
    f.write(' '.join(['1'] + ['dup', '+'] * 70) + '\n')
    f.write(' '.join(['3'] + ['dup', '*'] * 50) + '\n')
    for _ in range(110):
        f.write(expression(r, r.randint(500, 2000), 0.5, ('+', '-', '*', 'swap')) + '\n')
