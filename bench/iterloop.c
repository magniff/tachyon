#include <stdio.h>
#include <stdlib.h>
/* bench/iterloop.vl: the kernels of the iterator chains, as loops */
static __attribute__((noinline)) long filter_map_sum(const long *s, long n, long r) {
    long t = 0;
    for (long k = 0; k < n; k++) {
        long x = s[k];
        if ((x & 1) == 0) t += x * x + r;
    }
    return t;
}
static __attribute__((noinline)) long dot(const long *a, long na, const long *b, long nb, long r) {
    long n = na < nb ? na : nb, t = 0;
    for (long k = 0; k < n; k++) t += a[k] * b[k] + r;
    return t;
}
static __attribute__((noinline)) long enumerate_sum(const long *s, long n, long r) {
    long t = 0;
    for (long k = 0; k < n; k++) t += k * s[k] + r;
    return t;
}
static __attribute__((noinline)) long max_count(const long *s, long n, long r) {
    long m = s[0] ^ r, c = 0;
    for (long k = 1; k < n; k++) { long x = s[k] ^ r; if (x > m) m = x; }
    for (long k = 0; k < n; k++) if (s[k] > r) c++;
    return m + c;
}
static __attribute__((noinline)) long take_loop(const long *s, long len, long n) {
    long m = n < len ? n : len, t = 0;
    for (long k = 0; k < m; k++) t += s[k];
    return t;
}
static void sift_down(long *s, long start, long end) {
    long root = start;
    for (;;) {
        long child = 2 * root + 1;
        if (child >= end) return;
        if (child + 1 < end && s[child + 1] < s[child]) child++;
        if (s[child] >= s[root]) return;
        long t = s[root]; s[root] = s[child]; s[child] = t;
        root = child;
    }
}
static __attribute__((noinline)) void sort_desc(long *s, long n) {
    long start = n / 2;
    while (start > 0) { start--; sift_down(s, start, n); }
    long end = n;
    while (end > 1) {
        end--;
        long top = s[0]; s[0] = s[end]; s[end] = top;
        sift_down(s, 0, end);
    }
}
static __attribute__((noinline)) long collect_sort(const long *s, long m, long r) {
    long *u = malloc(m * sizeof(long));
    for (long k = 0; k < m; k++) u[k] = s[k] ^ r;
    sort_desc(u, m);
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
