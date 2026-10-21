/* bench/std: hash_churn: 10M operations on a table of u64 keys holding about
 * 100k: the i-th random key inserted, then the key inserted 100k
 * operations before removed. A hand-written table: linear probing, load
 * at most 1/2, removal by backward shifting (no tombstones), the same
 * hash as tachyon's FixedState. */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct { uint64_t k, v; } Entry;
typedef struct { Entry *e; uint8_t *used; uint64_t mask; long len; } Map;

static inline uint64_t hash(uint64_t k) {
    __uint128_t f = (__uint128_t)(k ^ 0x082efa98ec4e6c89ull) * 0xc0ac29b7c97c50ddull;
    return (uint64_t)f ^ (uint64_t)(f >> 64);
}

static void init(Map *m, uint64_t cap) {
    m->e = malloc(cap * sizeof(Entry));
    m->used = calloc(cap, 1);
    m->mask = cap - 1;
    m->len = 0;
}

static void insert(Map *m, uint64_t k, uint64_t v);

static void grow(Map *m) {
    Map n;
    init(&n, (m->mask + 1) * 2);
    for (uint64_t i = 0; i <= m->mask; i++)
        if (m->used[i]) insert(&n, m->e[i].k, m->e[i].v);
    free(m->e);
    free(m->used);
    *m = n;
}

static void insert(Map *m, uint64_t k, uint64_t v) {
    if ((uint64_t)(m->len + 1) * 2 > m->mask + 1) grow(m);
    uint64_t i = hash(k) & m->mask;
    while (m->used[i]) {
        if (m->e[i].k == k) { m->e[i].v = v; return; }
        i = (i + 1) & m->mask;
    }
    m->used[i] = 1;
    m->e[i].k = k;
    m->e[i].v = v;
    m->len++;
}

static int remove_key(Map *m, uint64_t k, uint64_t *v) {
    uint64_t i = hash(k) & m->mask;
    while (m->used[i]) {
        if (m->e[i].k == k) {
            *v = m->e[i].v;
            /* backward shift: move later entries of the run back */
            uint64_t j = i;
            for (;;) {
                j = (j + 1) & m->mask;
                if (!m->used[j]) break;
                uint64_t h = hash(m->e[j].k) & m->mask;
                if (((j - h) & m->mask) >= ((j - i) & m->mask)) {
                    m->e[i] = m->e[j];
                    i = j;
                }
            }
            m->used[i] = 0;
            m->len--;
            return 1;
        }
        i = (i + 1) & m->mask;
    }
    return 0;
}

static uint64_t xorshift(uint64_t *x) {
    uint64_t v = *x;
    v ^= v << 13;
    v ^= v >> 7;
    v ^= v << 17;
    *x = v;
    return v;
}

int main(void) {
    long ops = 10000000, lag = 100000, removed = 0;
    Map m;
    init(&m, 8);
    uint64_t ins = 0x9e3779b97f4a7c15ull, del = ins, sum = 0, v;
    for (long i = 0; i < ops / 2; i++) {
        insert(&m, xorshift(&ins), (uint64_t)i);
        if (i >= lag && remove_key(&m, xorshift(&del), &v)) { removed++; sum += v; }
    }
    printf("%ld %ld %llu\n", m.len, removed, (unsigned long long)sum);
    return 0;
}
