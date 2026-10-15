/* The same selections in C, for comparing speed: the same values,
 * quickselect and median of medians (on int64_t, not generic), and
 * qsort for the sorted baseline.
 *
 *     cc -O2 examples/algorithms/quickselect/reference.c -o select-c && ./select-c
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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

static int64_t now_ns(void) {
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    return (int64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}

static void swap(int64_t *s, int64_t i, int64_t j) {
    int64_t t = s[i];
    s[i] = s[j];
    s[j] = t;
}

static int64_t quickselect(int64_t *s, int64_t n, int64_t k) {
    int64_t lo = 0, hi = n - 1;
    while (lo < hi) {
        int64_t mid = lo + (hi - lo) / 2;
        if (s[mid] < s[lo]) swap(s, mid, lo);
        if (s[hi] < s[lo]) swap(s, hi, lo);
        if (s[hi] < s[mid]) swap(s, hi, mid);
        int64_t pivot = s[mid], i = lo - 1, j = hi + 1;
        for (;;) {
            do i++; while (s[i] < pivot);
            do j--; while (pivot < s[j]);
            if (i >= j) break;
            swap(s, i, j);
        }
        if (k <= j) hi = j; else lo = j + 1;
    }
    return s[k];
}

static void insertion_sort(int64_t *s, int64_t n) {
    for (int64_t i = 1; i < n; i++) {
        int64_t x = s[i], j = i;
        while (j > 0 && x < s[j - 1]) {
            s[j] = s[j - 1];
            j--;
        }
        s[j] = x;
    }
}

static int64_t median_of_medians(int64_t *w, int64_t n, int64_t k) {
    for (;;) {
        if (n <= 10) {
            insertion_sort(w, n);
            return w[k];
        }
        int64_t groups = n / 5;
        for (int64_t g = 0; g < groups; g++) {
            insertion_sort(w + 5 * g, 5);
            swap(w, g, 5 * g + 2);
        }
        int64_t p = median_of_medians(w, groups, groups / 2);
        int64_t lt = 0, i = 0, gt = n;
        while (i < gt) {
            if (w[i] < p) swap(w, lt++, i++);
            else if (p < w[i]) swap(w, i, --gt);
            else i++;
        }
        if (k < lt) n = lt;
        else if (k < gt) return p;
        else {
            w += gt;
            n -= gt;
            k -= gt;
        }
    }
}

static int cmp(const void *a, const void *b) {
    int64_t x = *(const int64_t *)a, y = *(const int64_t *)b;
    return (x > y) - (x < y);
}

int main(void) {
    int64_t n = 2000000, ks[7], found[3][7];
    int64_t *data = malloc(sizeof(int64_t) * n), *work = malloc(sizeof(int64_t) * n);
    state = 2026 | 1;
    for (int64_t i = 0; i < n; i++) data[i] = range(0, 999999999);
    ks[0] = 0, ks[1] = n / 100, ks[2] = n / 10, ks[3] = n / 2;
    ks[4] = n * 9 / 10, ks[5] = n * 99 / 100, ks[6] = n - 1;
    const char *names[] = {"quickselect", "median of medians", "sort (qsort)"};
    for (int m = 0; m < 3; m++) {
        memcpy(work, data, sizeof(int64_t) * n);
        int64_t t0 = now_ns();
        if (m == 2) qsort(work, n, sizeof(int64_t), cmp);
        for (int r = 0; r < 7; r++)
            found[m][r] = m == 0 ? quickselect(work, n, ks[r])
                        : m == 1 ? median_of_medians(work, n, ks[r]) : work[ks[r]];
        fprintf(stderr, "%-18s %7.2f ms\n", names[m], (now_ns() - t0) / 1e6);
    }
    printf("median %lld, %s\n", (long long)found[0][3],
           memcmp(found[0], found[2], sizeof found[0]) == 0 && memcmp(found[1], found[2], sizeof found[0]) == 0
               ? "agree" : "DISAGREE");
    return 0;
}
