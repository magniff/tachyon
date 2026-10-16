#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <limits.h>
/* std::BinaryHeap and std::MinHeap (0.18.1): a binary heap in an array,
 * sifted through a hole; pop moves the last element to the root, takes it
 * down to a leaf along the larger child, then up (Rust's BinaryHeap). */
typedef struct { long d, u; } Pair;
#define LONG_ABOVE(a, b) ((a) > (b))
#define PAIR_ABOVE(a, b) ((a).d < (b).d || ((a).d == (b).d && (a).u < (b).u))
#define HEAP(NAME, T, ABOVE) \
typedef struct { T *p; long len, cap; } NAME; \
static void NAME##_sift_up(T *p, long pos) { \
    T x = p[pos]; \
    while (pos > 0) { \
        long parent = (pos - 1) / 2; \
        if (!ABOVE(x, p[parent])) break; \
        p[pos] = p[parent]; \
        pos = parent; \
    } \
    p[pos] = x; \
} \
static void NAME##_push(NAME *h, T x) { \
    if (h->len == h->cap) { \
        h->cap = h->cap ? 2 * h->cap : 4; \
        h->p = realloc(h->p, h->cap * sizeof(T)); \
    } \
    h->p[h->len++] = x; \
    NAME##_sift_up(h->p, h->len - 1); \
} \
static int NAME##_pop(NAME *h, T *out) { \
    if (h->len == 0) return 0; \
    T last = h->p[--h->len]; \
    if (h->len == 0) { *out = last; return 1; } \
    T *p = h->p; \
    long end = h->len, i = 0, child = 1; \
    *out = p[0]; \
    while (child <= end - 2) { \
        child += !ABOVE(p[child], p[child + 1]); \
        p[i] = p[child]; \
        i = child; \
        child = 2 * i + 1; \
    } \
    if (child == end - 1) { p[i] = p[child]; i = child; } \
    p[i] = last; \
    NAME##_sift_up(p, i); \
    return 1; \
}
HEAP(MaxHeap, long, LONG_ABOVE)
HEAP(MinHeap, Pair, PAIR_ABOVE)

static uint64_t state = 42;
static uint64_t next(void) {
    state = state * 6364136223846793005ULL + 1442695040888963407ULL;
    return state >> 17;
}

int main(void) {
    long n = 1000000;
    MaxHeap h = { malloc(n * sizeof(long)), 0, n };
    for (long i = 0; i < n; i++) MaxHeap_push(&h, (long)next());
    uint64_t sum = 0;
    int ordered = 1;
    long last = LONG_MAX, x;
    while (MaxHeap_pop(&h, &x)) {
        sum = sum * 31 + (uint64_t)x;
        if (x > last) ordered = 0;
        last = x;
    }
    printf("%d %lu\n", ordered, (unsigned long)sum);

    MinHeap q = { 0, 0, 0 };
    for (long i = 0; i < 1000; i++) MinHeap_push(&q, (Pair){ (long)(next() % 1000), i });
    uint64_t sum2 = 0;
    int ordered2 = 1;
    long prev = 0;
    for (long r = 0; r < 2000000; r++) {
        Pair t;
        MinHeap_pop(&q, &t);
        if (t.d < prev) ordered2 = 0;
        prev = t.d;
        sum2 = sum2 * 31 + (uint64_t)(t.d + t.u);
        MinHeap_push(&q, (Pair){ t.d + (long)(next() % 1000), (t.u * 7 + r) % 100000 });
        if (r % 2 == 0 && q.len < 200000)
            MinHeap_push(&q, (Pair){ t.d + (long)(next() % 5000), r % 100000 });
    }
    printf("%d %lu %ld\n", ordered2, (unsigned long)sum2, q.len);
    free(h.p);
    free(q.p);
    return 0;
}
