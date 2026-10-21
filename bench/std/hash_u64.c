/* bench/std: a hand-written hash table of u64 to u64 (open addressing,
   linear probing, splitmix64's finalizer, load 3/4), 2,000,000 inserts
   of random u64, then 2,000,000 lookups (half hits). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint64_t next(uint64_t *s) {
    uint64_t x = *s;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *s = x;
    return x;
}

static uint64_t mix64(uint64_t x) {
    uint64_t z = x + 0x9e3779b97f4a7c15ull;
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ull;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebull;
    return z ^ (z >> 31);
}

typedef struct { uint64_t *keys, *vals; uint8_t *used; size_t cap, len; } Map;

static void put(Map *m, uint64_t k, uint64_t v);

static void grow(Map *m) {
    Map n = { 0 };
    n.cap = m->cap ? m->cap * 2 : 16;
    n.keys = malloc(n.cap * 8); n.vals = malloc(n.cap * 8); n.used = calloc(n.cap, 1);
    for (size_t i = 0; i < m->cap; i++) if (m->used[i]) put(&n, m->keys[i], m->vals[i]);
    free(m->keys); free(m->vals); free(m->used);
    *m = n;
}

static void put(Map *m, uint64_t k, uint64_t v) {
    if ((m->len + 1) * 4 > m->cap * 3) grow(m);
    size_t i = mix64(k) & (m->cap - 1);
    while (m->used[i]) {
        if (m->keys[i] == k) { m->vals[i] = v; return; }
        i = (i + 1) & (m->cap - 1);
    }
    m->used[i] = 1; m->keys[i] = k; m->vals[i] = v; m->len++;
}

static int get(const Map *m, uint64_t k, uint64_t *v) {
    size_t i = mix64(k) & (m->cap - 1);
    while (m->used[i]) {
        if (m->keys[i] == k) { *v = m->vals[i]; return 1; }
        i = (i + 1) & (m->cap - 1);
    }
    return 0;
}

int main(void) {
    size_t n = 2000000;
    uint64_t st = 0x9E3779B97F4A7C15ull;
    uint64_t *keys = malloc(n * 8);
    Map m = { 0 };
    for (size_t i = 0; i < n; i++) { keys[i] = next(&st); put(&m, keys[i], i); }
    uint64_t found = 0, sum = 0, v;
    for (size_t i = 0; i < n; i++) {
        uint64_t k = i % 2 == 0 ? keys[i] : next(&st);
        if (get(&m, k, &v)) { found++; sum += v; }
    }
    printf("%llu %llu %zu\n", (unsigned long long)found, (unsigned long long)sum, m.len);
    return 0;
}
