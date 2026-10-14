#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
/* std::sort's introsort (0.14), for integers and for records by key:
 * quicksort around the median of three, insertion sort for runs of up to
 * 24, heapsort below 2 log2(n) levels of partitions */
typedef struct { long key, id; } Rec;
static long rec_cmp(const Rec *a, const Rec *b) {
    if (a->key < b->key) return -1;
    if (a->key > b->key) return 1;
    if (a->id < b->id) return -1;
    if (a->id > b->id) return 1;
    return 0;
}
#define LONG_LT(a, b) ((a) < (b))
#define REC_LT(a, b) (rec_cmp(&(a), &(b)) < 0)
#define INTROSORT(NAME, T, LT) \
static void NAME##_sift_down(T *s, long start, long end) { \
    long root = start; \
    for (;;) { \
        long child = 2 * root + 1; \
        if (child >= end) return; \
        if (child + 1 < end && LT(s[child], s[child + 1])) child++; \
        if (!LT(s[root], s[child])) return; \
        T t = s[root]; s[root] = s[child]; s[child] = t; \
        root = child; \
    } \
} \
static void NAME##_heapsort(T *s, long n) { \
    long start = n / 2; \
    while (start > 0) { start--; NAME##_sift_down(s, start, n); } \
    long end = n; \
    while (end > 1) { \
        end--; \
        T top = s[0]; s[0] = s[end]; s[end] = top; \
        NAME##_sift_down(s, 0, end); \
    } \
} \
static void NAME##_swap(T *s, long i, long j) { T t = s[i]; s[i] = s[j]; s[j] = t; } \
static void NAME##_quicksort(T *s, long lo, long hi, long depth) { \
    while (hi - lo > 24) { \
        if (depth == 0) { NAME##_heapsort(s + lo, hi - lo); return; } \
        depth--; \
        long mid = lo + (hi - lo) / 2; \
        if (LT(s[mid], s[lo])) NAME##_swap(s, mid, lo); \
        if (LT(s[hi - 1], s[mid])) { \
            NAME##_swap(s, hi - 1, mid); \
            if (LT(s[mid], s[lo])) NAME##_swap(s, mid, lo); \
        } \
        NAME##_swap(s, lo, mid); \
        T pivot = s[lo]; \
        long i = lo, j = hi; \
        for (;;) { \
            i++; \
            while (i < hi && LT(s[i], pivot)) i++; \
            j--; \
            while (j > lo && LT(pivot, s[j])) j--; \
            if (i >= j) break; \
            NAME##_swap(s, i, j); \
        } \
        NAME##_swap(s, lo, j); \
        if (j - lo < hi - j - 1) { NAME##_quicksort(s, lo, j, depth); lo = j + 1; } \
        else { NAME##_quicksort(s, j + 1, hi, depth); hi = j; } \
    } \
    for (long i = lo + 1; i < hi; i++) { \
        T x = s[i]; \
        long j = i; \
        while (j > lo && LT(x, s[j - 1])) { s[j] = s[j - 1]; j--; } \
        s[j] = x; \
    } \
} \
static void NAME(T *s, long n) { \
    long depth = 0; \
    for (long k = n; k > 1; k /= 2) depth += 2; \
    NAME##_quicksort(s, 0, n, depth); \
}
INTROSORT(sort_long, long, LONG_LT)
INTROSORT(sort_rec, Rec, REC_LT)
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
