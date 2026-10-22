#include <stdio.h>
#include <stdlib.h>
/* bench/iterchain.vl in C: each kernel a fold over the vector with
   its closures as small functions the compiler inlines (the nearest C
   has to a chain of adapters) */
typedef struct { const long *s; long pos, len; } SliceIter;
static inline SliceIter iter(const long *s, long n) { SliceIter it = { s, 0, n }; return it; }

#define FOLD(it, acc, x, body) \
    for (long k_ = (it).pos; k_ < (it).len; k_++) { long x = (it).s[k_]; body; }

static inline int is_even(long x) { return (x & 1) == 0; }
static inline long sq_plus(long x, long r) { return x * x + r; }
static inline long mul_plus(long a, long b, long r) { return a * b + r; }
static inline long xor_r(long x, long r) { return x ^ r; }
static inline long desc(const long *a, const long *b) { return *b < *a ? -1 : *b > *a; }

static __attribute__((noinline)) long filter_map_sum(const long *v, long n, long r) {
    SliceIter it = iter(v, n);
    long acc = 0;
    FOLD(it, acc, x, if (is_even(x)) acc += sq_plus(x, r));
    return acc;
}
static __attribute__((noinline)) long dot(const long *v, long nv, const long *w, long nw, long r) {
    SliceIter a = iter(v, nv), b = iter(w, nw);
    long n = a.len - a.pos < b.len - b.pos ? a.len - a.pos : b.len - b.pos, acc = 0;
    for (long k = 0; k < n; k++) acc += mul_plus(a.s[a.pos + k], b.s[b.pos + k], r);
    return acc;
}
static __attribute__((noinline)) long enumerate_sum(const long *v, long n, long r) {
    SliceIter it = iter(v, n);
    long len = it.len - it.pos, acc = 0;
    for (long k = 0; k < len; k++) acc += mul_plus(k, it.s[it.pos + k], r);
    return acc;
}
static __attribute__((noinline)) long max_count(const long *v, long n, long r) {
    SliceIter it = iter(v, n);
    int some = 0;
    long best = 0, count = 0;
    FOLD(it, best, x, { long y = xor_r(x, r); if (!some || y > best) best = y; some = 1; });
    FOLD(it, count, x, if (x > r) count++);
    return best + count;
}
static __attribute__((noinline)) long take_loop(const long *v, long len, long n) {
    SliceIter it = iter(v, len);
    long left = n, t = 0;
    for (;;) {
        if (left == 0) break;
        left--;
        if (it.pos >= it.len) break;
        t += it.s[it.pos++];
    }
    return t;
}
static inline void sift_down(long *s, long start, long end) {
    long root = start;
    for (;;) {
        long child = 2 * root + 1;
        if (child >= end) return;
        if (child + 1 < end && desc(&s[child], &s[child + 1]) < 0) child++;
        if (desc(&s[root], &s[child]) >= 0) return;
        long t = s[root]; s[root] = s[child]; s[child] = t;
        root = child;
    }
}
static __attribute__((noinline)) void sort_by_desc(long *s, long n) {
    long start = n / 2;
    while (start > 0) { start--; sift_down(s, start, n); }
    long end = n;
    while (end > 1) {
        end--;
        long top = s[0]; s[0] = s[end]; s[end] = top;
        sift_down(s, 0, end);
    }
}
static __attribute__((noinline)) long collect_sort(const long *v, long m, long r) {
    long cap = 0, len = 0, *u = 0;
    SliceIter it = iter(v, m);
    FOLD(it, u, x, {
        if (len == cap) { cap = cap ? 2 * cap : 4; u = realloc(u, cap * sizeof(long)); }
        u[len++] = xor_r(x, r);
    });
    sort_by_desc(u, len);
    long res = u[0] - u[m - 1] + u[m / 2];
    free(u);
    return res;
}
int main(void) {
    long n = 1048576, reps = 200;
    long *v = malloc(n * sizeof(long)), *w = malloc(n * sizeof(long));
    for (long i = 0; i < n; i++) {
        v[i] = i * 2654435761L % 1000003 % 1001 - 500;
        w[i] = i % 17 - 8;
    }
    long c1 = 0, c2 = 0, c3 = 0, c4 = 0, c5 = 0, c6 = 0;
    for (long r = 0; r < reps; r++) {
        c1 += filter_map_sum(v, n, r);
        c2 += dot(v, n, w, n, r);
        c3 += enumerate_sum(v, n, r);
        c4 += max_count(v, n, r * 4999);
        c5 += take_loop(v, n, n - r);
    }
    for (long r = 0; r < 10; r++) c6 += collect_sort(v, 65536, r);
    printf("%ld %ld %ld %ld %ld %ld\n", c1, c2, c3, c4, c5, c6);
    free(v); free(w);
    return 0;
}
