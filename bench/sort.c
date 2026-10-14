#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
/* std::sort's heapsort, for integers and for records by key */
typedef struct { long key, id; } Rec;
static long rec_cmp(const Rec *a, const Rec *b) {
    if (a->key < b->key) return -1;
    if (a->key > b->key) return 1;
    if (a->id < b->id) return -1;
    if (a->id > b->id) return 1;
    return 0;
}
static void sift_down_long(long *s, long start, long end) {
    long root = start;
    for (;;) {
        long child = 2 * root + 1;
        if (child >= end) return;
        if (child + 1 < end && s[child] < s[child + 1]) child++;
        if (!(s[root] < s[child])) return;
        long t = s[root]; s[root] = s[child]; s[child] = t;
        root = child;
    }
}
static void sort_long(long *s, long n) {
    long start = n / 2;
    while (start > 0) { start--; sift_down_long(s, start, n); }
    long end = n;
    while (end > 1) {
        end--;
        long top = s[0]; s[0] = s[end]; s[end] = top;
        sift_down_long(s, 0, end);
    }
}
static void sift_down_rec(Rec *s, long start, long end) {
    long root = start;
    for (;;) {
        long child = 2 * root + 1;
        if (child >= end) return;
        if (child + 1 < end && rec_cmp(&s[child], &s[child + 1]) < 0) child++;
        if (!(rec_cmp(&s[root], &s[child]) < 0)) return;
        Rec t = s[root]; s[root] = s[child]; s[child] = t;
        root = child;
    }
}
static void sort_rec(Rec *s, long n) {
    long start = n / 2;
    while (start > 0) { start--; sift_down_rec(s, start, n); }
    long end = n;
    while (end > 1) {
        end--;
        Rec top = s[0]; s[0] = s[end]; s[end] = top;
        sift_down_rec(s, 0, end);
    }
}
static uint64_t next(uint64_t *state) {
    *state = *state * 6364136223846793005ULL + 1442695040888963407ULL;
    return *state >> 17;
}
int main(void) {
    uint64_t state = 42;
    long n = 1000000;
    long *s = malloc(n * sizeof(long));
    for (long i = 0; i < n; i++) s[i] = (long)next(&state);
    sort_long(s, n);
    uint64_t sum = 0;
    int sorted = 1;
    for (long i = 0; i < n; i++) {
        sum = sum * 31 + (uint64_t)s[i];
        if (i > 0 && s[i - 1] > s[i]) sorted = 0;
    }
    printf("%d %lu\n", sorted, (unsigned long)sum);
    long m = 200000;
    Rec *t = malloc(m * sizeof(Rec));
    for (long i = 0; i < m; i++) { t[i].key = (long)(next(&state) % 1000); t[i].id = i; }
    sort_rec(t, m);
    uint64_t sum2 = 0;
    for (long i = 0; i < m; i++) sum2 = sum2 * 31 + (uint64_t)(t[i].key * 1000003 + t[i].id);
    printf("%lu\n", (unsigned long)sum2);
    free(s);
    free(t);
    return 0;
}
