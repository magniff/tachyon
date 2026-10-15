/* The integer part of the program in C, for comparing speed: the same
 * generator, workload and cache, and a hash table built as std's HashMap
 * is (open addressing, linear probing, removed slots marked, the same
 * hash, growth at 3/4 full).
 *
 *     cc -O2 examples/algorithms/lru-cache/reference.c -o lru-c && ./lru-c
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

enum { FREE, FULL, GONE };

typedef struct { int64_t *keys; int32_t *values; uint8_t *states; int64_t cap, len, used; } Map;
typedef struct { int64_t key, value; int32_t prev, next; } Node;
typedef struct {
    int64_t capacity, count, hits, misses, evictions;
    Map slots;
    Node *nodes;
    int32_t head, tail;
} Cache;

static uint64_t hash(uint64_t x) {
    uint64_t z = x + 0x9e3779b97f4a7c15ULL;
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    return z ^ (z >> 31);
}

static int64_t slot_of(Map *m, int64_t key) {
    if (m->cap == 0) return -1;
    int64_t mask = m->cap - 1, i = (int64_t)(hash((uint64_t)key) & (uint64_t)mask);
    for (;;) {
        if (m->states[i] == FREE) return -1;
        if (m->states[i] == FULL && m->keys[i] == key) return i;
        i = (i + 1) & mask;
    }
}

static void place(Map *m, int64_t key, int32_t value) {
    int64_t mask = m->cap - 1, j = (int64_t)(hash((uint64_t)key) & (uint64_t)mask);
    while (m->states[j] == FULL) j = (j + 1) & mask;
    if (m->states[j] == FREE) m->used++;
    m->states[j] = FULL;
    m->keys[j] = key;
    m->values[j] = value;
}

static void rehash(Map *m) {
    Map old = *m;
    int64_t cap = old.cap == 0 ? 8 : old.cap * 2;
    while (m->len * 2 > cap) cap *= 2;
    m->keys = malloc(sizeof(int64_t) * cap);
    m->values = malloc(sizeof(int32_t) * cap);
    m->states = calloc(cap, 1);
    m->cap = cap;
    m->used = 0;
    for (int64_t i = 0; i < old.cap; i++)
        if (old.states[i] == FULL) place(m, old.keys[i], old.values[i]);
    free(old.keys);
    free(old.values);
    free(old.states);
}

static void insert(Map *m, int64_t key, int32_t value) {
    if ((m->used + 1) * 4 > m->cap * 3) rehash(m);
    place(m, key, value);
    m->len++;
}

static void map_remove(Map *m, int64_t key) {
    int64_t i = slot_of(m, key);
    if (i >= 0) {
        m->states[i] = GONE;
        m->len--;
    }
}

static void unlink_node(Cache *c, int32_t i) {
    int32_t prev = c->nodes[i].prev, next = c->nodes[i].next;
    if (prev == -1) c->head = next; else c->nodes[prev].next = next;
    if (next == -1) c->tail = prev; else c->nodes[next].prev = prev;
}

static void push_front(Cache *c, int32_t i) {
    c->nodes[i].prev = -1;
    c->nodes[i].next = c->head;
    if (c->head != -1) c->nodes[c->head].prev = i;
    c->head = i;
    if (c->tail == -1) c->tail = i;
}

static int get(Cache *c, int64_t key, int64_t *value) {
    int64_t s = slot_of(&c->slots, key);
    if (s < 0) {
        c->misses++;
        return 0;
    }
    int32_t i = c->slots.values[s];
    c->hits++;
    if (i != c->head) {
        unlink_node(c, i);
        push_front(c, i);
    }
    *value = c->nodes[i].value;
    return 1;
}

static void put(Cache *c, int64_t key, int64_t value) {   /* key is new */
    int32_t i;
    if (c->count < c->capacity) {
        i = (int32_t)c->count++;
    } else {
        i = c->tail;
        unlink_node(c, i);
        map_remove(&c->slots, c->nodes[i].key);
        c->evictions++;
    }
    c->nodes[i] = (Node){key, value, -1, -1};
    insert(&c->slots, key, i);
    push_front(c, i);
}

static uint64_t state;

static uint64_t next(void) {
    uint64_t x = state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    state = x;
    return x * 0x2545F4914F6CDD1DULL;
}

static int64_t below(int64_t n) { return (int64_t)((next() >> 33) % (uint64_t)n); }

int main(void) {
    struct timespec t0, t1;
    timespec_get(&t0, TIME_UTC);
    int64_t capacities[] = {1000, 10000, 100000};
    for (int k = 0; k < 3; k++) {
        Cache c = {capacities[k], 0, 0, 0, 0, {0}, malloc(sizeof(Node) * capacities[k]), -1, -1};
        int64_t sum = 0;
        state = 2026 | 1;
        for (int64_t r = 0; r < 4000000; r++) {
            int64_t bits = below(21), key = below((int64_t)1 << bits), value;
            if (!get(&c, key, &value)) {
                value = (int64_t)(hash((uint64_t)key) % 1000);
                put(&c, key, value);
            }
            sum += value;
        }
        printf("capacity %6lld: hit rate %.2f%%, %7lld evictions, sum %lld\n", (long long)c.capacity,
               c.hits * 100.0 / (c.hits + c.misses), (long long)c.evictions, (long long)sum);
        free(c.nodes);
        free(c.slots.keys);
        free(c.slots.values);
        free(c.slots.states);
    }
    timespec_get(&t1, TIME_UTC);
    fprintf(stderr, "lru: 12000000 requests in %lld ms\n",
            (long long)((t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000));
    return 0;
}
