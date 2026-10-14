# Generates the large tests (06, 07) with fixed seeds.
import random

def name(r):
    n = r.randint(1, 10)
    return ''.join(r.choice('abcdefghijklmnopqrstuvwxyz0123456789_') for _ in range(n))

def amount(r):
    k = r.random()
    if k < 0.7:
        return str(r.randint(1, 1000))
    if k < 0.9:
        return str(r.randint(1, 10**9))
    if k < 0.95:
        return str(r.randint(1, 10**12 - 1))
    return r.choice(['0', '1234567890123', 'x1', '-3', '00042'])

def commands(r, count, names, reports):
    out = []
    for i in range(count):
        k = r.random()
        if k < 0.15:
            out.append('open ' + r.choice(names))
        elif k < 0.40:
            out.append('deposit %s %s' % (r.choice(names), amount(r)))
        elif k < 0.55:
            out.append('withdraw %s %s' % (r.choice(names), amount(r)))
        elif k < 0.85:
            a = r.choice(names)
            b = a if r.random() < 0.03 else r.choice(names)
            out.append('transfer %s %s %s' % (a, b, amount(r)))
        elif k < 0.90:
            out.append('close ' + r.choice(names))
        elif k < 0.97:
            out.append('balance ' + r.choice(names))
        elif k < 0.98:
            out.append(r.choice(['', '   ', 'audit', 'open', 'deposit x', 'open Bad', 'report now']))
        else:
            out.append(' ' * r.randint(0, 2) + r.choice(['open', 'deposit', 'balance']) + '  ' + r.choice(names) + ('  5' if r.random() < 0.5 else ''))
    for _ in range(reports):
        out.insert(r.randint(0, len(out)), 'report')
    return out

r = random.Random(6)
names = list({name(r) for _ in range(3000)})
names.sort()
r.shuffle(names)
cmds = ['open ' + n for n in names[:2000]] + commands(r, 30000, names, 3) + ['report']
with open('06.in', 'w') as f:
    f.write('\n'.join(cmds) + '\n')

# Many accounts: 20000 opened, money moved around, a final report.
r = random.Random(7)
names = sorted({name(r) + str(i) for i in range(20000)})
r.shuffle(names)
cmds = ['open ' + n for n in names]
cmds += ['deposit %s %d' % (n, r.randint(1, 10**6)) for n in names[:10000]]
for _ in range(8000):
    cmds.append('transfer %s %s %d' % (r.choice(names), r.choice(names), r.randint(1, 10**6)))
cmds.append('report')
with open('07.in', 'w') as f:
    f.write('\n'.join(cmds) + '\n')
