# Generates the large tests (08, 09) with fixed seeds.
import random

def zipf_text(seed, nwords, vocab):
    r = random.Random(seed)
    words = []
    for i in range(vocab):
        n = r.randint(1, 12)
        words.append(''.join(r.choice('abcdefghijklmnopqrstuvwxyz') for _ in range(n)))
    weights = [1.0 / (i + 1) for i in range(vocab)]
    picks = r.choices(words, weights, k=nwords)
    seps = [' ', ' ', ' ', ', ', '. ', '\n', ' -- ', '; ', '42 ', "'s "]
    out = []
    for w in picks:
        if r.random() < 0.1:
            w = w.capitalize()
        elif r.random() < 0.02:
            w = w.upper()
        out.append(w)
        out.append(r.choice(seps))
    return ''.join(out)

with open('08.in', 'w') as f:
    f.write('2000\n')
    f.write(zipf_text(8, 100000, 50000))

# Every word distinct-ish: 3-letter words, each appearing a few times.
r = random.Random(9)
words = [a + b + c for a in 'abcdefghijklmnopqrstuvwxyz' for b in 'abcdefghijklmnopqrstuvwxyz' for c in 'abcdefghijklmnopqrstuvwxyz']
picks = []
for w in words:
    picks.extend([w] * r.randint(1, 8))
r.shuffle(picks)
with open('09.in', 'w') as f:
    f.write('100000\n')
    for i in range(0, len(picks), 20):
        f.write(' '.join(picks[i:i + 20]) + '\n')
