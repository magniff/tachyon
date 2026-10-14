# Generates the large tests (06, 07) with fixed seeds.
import base64
import random

def text(r, n):
    k = r.random()
    if k < 0.6:
        return bytes(r.randint(32, 126) for _ in range(n))
    if k < 0.8:
        return ''.join(r.choice(['a', 'b', ' ', 'é', '✓', 'Z', '0']) for _ in range(n)).encode()
    return bytes(r.choice([b for b in range(1, 256) if b != 10]) for _ in range(n))

def corrupt(r, s):
    if not s:
        return 'A'
    s = list(s)
    k = r.random()
    i = r.randrange(len(s))
    if k < 0.3:
        s[i] = r.choice(['-', '_', ' ', '*', '=', '.'])
    elif k < 0.5:
        del s[i]
    elif k < 0.7:
        s.append('=')
    elif k < 0.85 and s[-1] == '=':
        # non-zero padding bits
        j = len(s) - (2 if s[-2] != '=' else 3)
        v = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'.index(s[j])
        s[j] = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'[v | 1]
    else:
        s.insert(i, 'A')
    return ''.join(s)

r = random.Random(6)
lines = []
for _ in range(9000):
    n = r.choice([0, 1, 2, 3, r.randint(4, 30), r.randint(30, 80)])
    t = text(r, n)
    k = r.random()
    if k < 0.45:
        lines.append(b'enc ' + t)
    elif k < 0.85:
        lines.append(b'dec ' + base64.b64encode(t))
    else:
        lines.append(b'dec ' + corrupt(r, base64.b64encode(t).decode()).encode())
with open('06.in', 'wb') as f:
    f.write(b'\n'.join(lines) + b'\n')

r = random.Random(7)
lines = []
big = bytes(r.randint(32, 126) for _ in range(120000))
lines.append(b'enc ' + big)
lines.append(b'dec ' + base64.b64encode(big))
binary = bytes(r.randint(0, 255) for _ in range(60000))
lines.append(b'dec ' + base64.b64encode(binary))
lines.append(b'dec ' + base64.b64encode(big[:90000]) + b'=')
lines.append(b'dec ' + base64.b64encode(big[:90001])[:-1] + b'A')
with open('07.in', 'wb') as f:
    f.write(b'\n'.join(lines) + b'\n')
