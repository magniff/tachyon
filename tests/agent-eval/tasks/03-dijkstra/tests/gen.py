# Generates tests 04 and 06-10 with fixed seeds.
import random

def write(name, n, edges, queries):
    with open(name, 'w') as f:
        f.write('%d %d %d\n' % (n, len(edges), len(queries)))
        f.write(''.join('%d %d %d\n' % e for e in edges))
        f.write(''.join('%d %d\n' % q for q in queries))

# 04: a long chain of heavy edges: lengths beyond 2^32.
n = 5000
edges = [(i, i + 1, 1000000000) for i in range(n - 1)]
random.Random(4).shuffle(edges)
write('04.in', n, edges, [(0, n - 1), (n - 1, 0), (17, 4321), (2500, 2500), (0, 1)])

# 05: small random graphs with many parallel paths.
r = random.Random(5)
n = 30
edges = [(r.randrange(n), r.randrange(n), r.randint(0, 20)) for _ in range(120)]
write('05.in', n, edges, [(r.randrange(n), r.randrange(n)) for _ in range(50)])

# 06: a trap for "first time reached is final": a cheap long detour.
n = 200
edges = []
for i in range(n - 1):
    edges.append((i, i + 1, 1))
    edges.append((0, i + 1, 1000 - i))
r = random.Random(6)
r.shuffle(edges)
write('06.in', n, edges, [(0, t) for t in range(0, n, 7)] + [(5, 0), (5, 199)])

# 07: large sparse graph, small weights, 50 queries from different sources.
r = random.Random(7)
n = 50000
edges = []
for i in range(1, n):
    edges.append((r.randrange(max(0, i - 50), i), i, r.randint(0, 99)))
for _ in range(10000):
    edges.append((r.randrange(n), r.randrange(n), r.randint(0, 99)))
r.shuffle(edges)
write('07.in', n, edges, [(r.randrange(n), r.randrange(n)) for _ in range(50)])

# 08: dense medium graph, large weights.
r = random.Random(8)
n = 2000
edges = [(r.randrange(n), r.randrange(n), r.randint(0, 1000000000)) for _ in range(45000)]
write('08.in', n, edges, [(r.randrange(n), r.randrange(n)) for _ in range(50)])

# 09: a 150x150 grid, weights 0 and 1, edges both ways.
r = random.Random(9)
side = 150
n = side * side
edges = []
for y in range(side):
    for x in range(side):
        u = y * side + x
        if x + 1 < side:
            edges.append((u, u + 1, r.randint(0, 1)))
            edges.append((u + 1, u, r.randint(0, 1)))
        if y + 1 < side and r.random() < 0.5:
            edges.append((u, u + side, r.randint(0, 1)))
r.shuffle(edges)
write('09.in', n, edges, [(r.randrange(n), r.randrange(n)) for _ in range(40)])

# 10: two components; many queries cross between them (unreachable).
r = random.Random(10)
n = 20000
half = n // 2
edges = []
for _ in range(40000):
    a = r.randrange(half)
    b = r.randrange(half)
    off = 0 if r.random() < 0.5 else half
    edges.append((a + off, b + off, r.randint(1, 1000)))
queries = []
for _ in range(50):
    queries.append((r.randrange(n), r.randrange(n)))
write('10.in', n, edges, queries)
