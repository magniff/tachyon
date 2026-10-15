/* The same search in C, for comparing speed: the same generator, graph,
 * heap (one int64 per entry: dist << 32 | node) and checksum.
 *
 *     cc -O2 examples/algorithms/dijkstra/reference.c -o dijkstra-c && ./dijkstra-c
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

static int64_t range(int64_t lo, int64_t hi) {
    return lo + (int64_t)((next() >> 33) % (uint64_t)(hi - lo + 1));
}

int main(void) {
    int64_t w = 1000, h = 1000, n = w * h, m = 0;
    int64_t *start = malloc(sizeof(int64_t) * (n + 1));
    int32_t *targets = malloc(sizeof(int32_t) * 4 * n);
    int32_t *weights = malloc(sizeof(int32_t) * 4 * n);
    int dr[] = {0, 1, 0, -1}, dc[] = {1, 0, -1, 0};
    state = 42 | 1;
    for (int64_t r = 0; r < h; r++) {
        for (int64_t c = 0; c < w; c++) {
            start[r * w + c] = m;
            for (int k = 0; k < 4; k++) {
                int64_t nr = r + dr[k], nc = c + dc[k];
                if (nr >= 0 && nr < h && nc >= 0 && nc < w) {
                    targets[m] = (int32_t)(nr * w + nc);
                    weights[m] = (int32_t)range(1, 9);
                    m++;
                }
            }
        }
    }
    start[n] = m;

    struct timespec t0, t1;
    timespec_get(&t0, TIME_UTC);
    int64_t *dist = malloc(sizeof(int64_t) * n);
    int32_t *prev = malloc(sizeof(int32_t) * n);
    for (int64_t i = 0; i < n; i++) {
        dist[i] = INT64_MAX;
        prev[i] = -1;
    }
    int64_t *heap = malloc(sizeof(int64_t) * m), len = 0;
    dist[0] = 0;
    heap[len++] = 0;
    while (len > 0) {
        int64_t e = heap[0], last = heap[--len];
        if (len > 0) {                          /* sift `last` down */
            int64_t i = 0;
            for (;;) {
                int64_t child = 2 * i + 1;
                if (child >= len) break;
                if (child + 1 < len && heap[child + 1] < heap[child]) child++;
                if (last <= heap[child]) break;
                heap[i] = heap[child];
                i = child;
            }
            heap[i] = last;
        }
        int64_t dv = e >> 32, v = e & 0xffffffff;
        if (dv > dist[v]) continue;
        for (int64_t k = start[v]; k < start[v + 1]; k++) {
            int64_t u = targets[k], nd = dv + weights[k];
            if (nd < dist[u]) {
                dist[u] = nd;
                prev[u] = (int32_t)v;
                int64_t x = nd << 32 | u, i = len++;
                while (i > 0) {                 /* sift up */
                    int64_t parent = (i - 1) / 2;
                    if (heap[parent] <= x) break;
                    heap[i] = heap[parent];
                    i = parent;
                }
                heap[i] = x;
            }
        }
    }
    timespec_get(&t1, TIME_UTC);

    uint64_t checksum = 0;
    for (int64_t i = 0; i < n; i++) checksum = (checksum ^ (uint64_t)dist[i]) * 0x100000001B3ULL;
    printf("corner to corner: %lld\nchecksum of the distances: %llx\n",
           (long long)dist[n - 1], (unsigned long long)checksum);
    fprintf(stderr, "dijkstra on %lld nodes: %lld ms\n", (long long)n,
            (long long)((t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000));
    return 0;
}
