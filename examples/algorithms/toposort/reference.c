/* The random-DAG part of the program in C, for comparing speed: the same
 * generator, graph (CSR) and Kahn's algorithm, timed the same way.
 *
 *     cc -O2 examples/algorithms/toposort/reference.c -o toposort-c && ./toposort-c
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

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
    int64_t n = 1000000, m = 4000000;
    int64_t *rank = malloc(sizeof(int64_t) * n);
    int32_t *from = malloc(sizeof(int32_t) * m), *to = malloc(sizeof(int32_t) * m);
    state = 99 | 1;
    for (int64_t i = 0; i < n; i++) rank[i] = i;
    for (int64_t i = 1; i < n; i++) {
        int64_t j = below(i + 1), t = rank[i];
        rank[i] = rank[j];
        rank[j] = t;
    }
    for (int64_t k = 0; k < m;) {
        int64_t a = below(n), b = below(n);
        if (a == b) continue;
        if (rank[a] < rank[b]) { from[k] = (int32_t)a; to[k] = (int32_t)b; }
        else { from[k] = (int32_t)b; to[k] = (int32_t)a; }
        k++;
    }
    int64_t *start = calloc(n + 1, sizeof(int64_t)), *fill = calloc(n, sizeof(int64_t));
    int32_t *targets = malloc(sizeof(int32_t) * m);
    for (int64_t k = 0; k < m; k++) start[from[k] + 1]++;
    for (int64_t v = 0; v < n; v++) start[v + 1] += start[v];
    for (int64_t k = 0; k < m; k++) targets[start[from[k]] + fill[from[k]]++] = to[k];

    struct timespec t0, t1;
    timespec_get(&t0, TIME_UTC);
    int32_t *indegree = calloc(n, sizeof(int32_t)), *order = malloc(sizeof(int32_t) * n);
    int64_t len = 0;
    for (int64_t k = 0; k < m; k++) indegree[targets[k]]++;
    for (int64_t v = 0; v < n; v++)
        if (indegree[v] == 0) order[len++] = (int32_t)v;
    for (int64_t head = 0; head < len; head++) {
        int64_t v = order[head];
        for (int64_t k = start[v]; k < start[v + 1]; k++)
            if (--indegree[targets[k]] == 0) order[len++] = targets[k];
    }
    timespec_get(&t1, TIME_UTC);

    printf("sorted: %lld nodes, first %d, last %d\n", (long long)len, order[0], order[len - 1]);
    fprintf(stderr, "kahn on %lld nodes: %lld ms\n", (long long)n,
            (long long)((t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000));
    return 0;
}
