/* bench/std: word count, 4,000,000 pseudo-random words counted in a
   hand-written table keyed by (pointer, length) into the text (open
   addressing, linear probing, FNV-1a, load 3/4). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint64_t next(uint64_t *s) {
    uint64_t x = *s;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *s = x;
    return x;
}

static uint64_t fnv(const uint8_t *p, size_t n) {
    uint64_t h = 0xcbf29ce484222325ull;
    for (size_t i = 0; i < n; i++) h = (h ^ p[i]) * 0x100000001b3ull;
    return h;
}

typedef struct { const uint8_t *p; size_t n; uint64_t c; } Slot;
typedef struct { Slot *s; size_t cap, len; } Map;

static Slot *find(Map *m, const uint8_t *p, size_t n) {
    size_t i = fnv(p, n) & (m->cap - 1);
    while (m->s[i].p) {
        if (m->s[i].n == n && memcmp(m->s[i].p, p, n) == 0) return &m->s[i];
        i = (i + 1) & (m->cap - 1);
    }
    return &m->s[i];
}

static void grow(Map *m) {
    Map n = { calloc(m->cap * 2, sizeof(Slot)), m->cap * 2, m->len };
    for (size_t i = 0; i < m->cap; i++)
        if (m->s[i].p) *find(&n, m->s[i].p, m->s[i].n) = m->s[i];
    free(m->s);
    *m = n;
}

int main(void) {
    size_t words = 4000000;
    uint64_t st = 0x9E3779B97F4A7C15ull;
    uint8_t *text = malloc(words * 8);
    size_t len = 0;
    for (size_t w = 0; w < words; w++) {
        uint64_t a = next(&st) % 4096, b = next(&st) % 4096, id = a * b / 64;
        do { text[len++] = 'a' + id % 26; id /= 26; } while (id);
        text[len++] = ' ';
    }
    Map m = { calloc(16, sizeof(Slot)), 16, 0 };
    uint64_t total = 0;
    for (size_t i = 0; i < len;) {
        size_t start = i;
        while (text[i] != ' ') i++;
        Slot *s = find(&m, text + start, i - start);
        if (!s->p) {
            if ((m.len + 1) * 4 > m.cap * 3) { grow(&m); s = find(&m, text + start, i - start); }
            s->p = text + start; s->n = i - start; m.len++;
        }
        s->c++;
        total++;
        i++;
    }
    uint64_t squares = 0;
    for (size_t i = 0; i < m.cap; i++) if (m.s[i].p) squares += m.s[i].c * m.s[i].c;
    printf("%zu %llu %llu\n", m.len, (unsigned long long)total, (unsigned long long)squares);
    return 0;
}
