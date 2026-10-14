# Generates tests 07-09 with fixed seeds.
import random

def write(name, intervals, queries):
    with open(name, 'w') as f:
        f.write('%d\n' % len(intervals))
        f.write(''.join('%d %d\n' % iv for iv in intervals))
        f.write('%d\n' % len(queries))
        f.write(''.join(q + '\n' for q in queries))

def queries(r, count, lo, hi, maxlen):
    out = []
    for _ in range(count):
        k = r.random()
        a = r.randint(lo, hi)
        b = min(hi, a + r.randint(0, maxlen))
        if k < 0.35:
            out.append('point %d' % a)
        elif k < 0.65:
            out.append('cover %d %d' % (a, b))
        else:
            out.append('count %d %d' % (a, b))
    return out

# 07: small coordinates, checked by brute force.
r = random.Random(7)
ivs = []
for _ in range(60):
    a = r.randint(-100, 100)
    ivs.append((a, a + r.randint(0, 8)))
write('07.in', ivs, queries(r, 300, -110, 110, 30))

# 08: many mostly disjoint intervals over the whole range.
r = random.Random(8)
ivs = []
for _ in range(20000):
    a = r.randint(-10**9, 10**9 - 100000)
    ivs.append((a, a + r.randint(0, 50000)))
write('08.in', ivs, queries(r, 20000, -10**9, 10**9, 10**8))

# 09: heavy overlap and nesting, touching intervals, repeats.
r = random.Random(9)
ivs = []
for _ in range(30000):
    k = r.random()
    if k < 0.5:
        a = r.randint(-10**6, 10**6)
        ivs.append((a, a + r.randint(0, 20)))
    elif k < 0.8 and ivs:
        p = r.choice(ivs)
        ivs.append((p[1] + 1, p[1] + 1 + r.randint(0, 30)))
    elif k < 0.9 and ivs:
        ivs.append(r.choice(ivs))
    else:
        a = r.randint(-10**6, 10**6)
        ivs.append((a, a + r.randint(0, 3000)))
write('09.in', ivs, queries(r, 25000, -10**6 - 100, 10**6 + 100, 5000))
