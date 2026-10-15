/* The same program in C, for comparing speed: the same generator, edges,
 * sort order (weight, then u, then v), union-find and output.
 *
 *     cc -O2 examples/algorithms/kruskal/reference.c -o kruskal-c && ./kruskal-c
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

typedef struct { int64_t w; int32_t u, v; } Edge;

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

static int cmp_edge(const void *pa, const void *pb) {
    const Edge *a = pa, *b = pb;
    if (a->w != b->w) return a->w < b->w ? -1 : 1;
    if (a->u != b->u) return a->u < b->u ? -1 : 1;
    return (a->v > b->v) - (a->v < b->v);
}

static int32_t *parent, *size;

static int64_t find(int64_t x) {
    while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
    }
    return x;
}

int main(void) {
    int64_t n = 200000, m = 1000000;
    Edge *edges = malloc(sizeof(Edge) * m);
    state = 7 | 1;
    for (int64_t i = 0; i < m; i++) {
        int32_t u = (int32_t)below(n), v = (int32_t)below(n);
        edges[i] = (Edge){1 + below(1000000), u, v};
    }

    struct timespec t0, t1;
    timespec_get(&t0, TIME_UTC);
    qsort(edges, m, sizeof(Edge), cmp_edge);
    parent = malloc(sizeof(int32_t) * n);
    size = malloc(sizeof(int32_t) * n);
    for (int64_t i = 0; i < n; i++) {
        parent[i] = (int32_t)i;
        size[i] = 1;
    }
    int64_t taken = 0, sets = n, weight = 0, heaviest = 0;
    for (int64_t i = 0; i < m && taken < n - 1; i++) {
        int64_t a = find(edges[i].u), b = find(edges[i].v);
        if (a == b) continue;
        if (size[a] < size[b]) { int64_t t = a; a = b; b = t; }
        parent[b] = (int32_t)a;
        size[a] += size[b];
        sets--;
        taken++;
        weight += edges[i].w;
        heaviest = edges[i].w;
    }
    timespec_get(&t1, TIME_UTC);

    printf("spanning forest: %lld edges, %lld components\n", (long long)taken, (long long)sets);
    printf("total weight %lld, heaviest edge %lld\n", (long long)weight, (long long)heaviest);
    fprintf(stderr, "kruskal on %lld edges: %lld ms\n", (long long)m,
            (long long)((t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000));
    return 0;
}
