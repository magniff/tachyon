/* The same searches in C, for comparing speed: the same generator, text,
 * patterns and algorithms (memcmp for the window comparisons).
 *
 *     cc -O2 examples/algorithms/string-search/reference.c -o search-c && ./search-c
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

static int64_t naive(const uint8_t *t, int64_t n, const uint8_t *p, int64_t m) {
    int64_t count = 0;
    for (int64_t i = 0; i + m <= n; i++)
        if (t[i] == p[0] && memcmp(t + i, p, m) == 0) count++;
    return count;
}

static int64_t kmp(const uint8_t *t, int64_t n, const uint8_t *p, int64_t m) {
    int64_t *fail = calloc(m, sizeof(int64_t)), k = 0, count = 0;
    for (int64_t j = 1; j < m; j++) {
        while (k > 0 && p[j] != p[k]) k = fail[k - 1];
        if (p[j] == p[k]) k++;
        fail[j] = k;
    }
    k = 0;
    for (int64_t i = 0; i < n; i++) {
        while (k > 0 && t[i] != p[k]) k = fail[k - 1];
        if (t[i] == p[k]) k++;
        if (k == m) {
            count++;
            k = fail[m - 1];
        }
    }
    free(fail);
    return count;
}

static int64_t horspool(const uint8_t *t, int64_t n, const uint8_t *p, int64_t m) {
    int64_t shift[256], count = 0;
    for (int b = 0; b < 256; b++) shift[b] = m;
    for (int64_t j = 0; j < m - 1; j++) shift[p[j]] = m - 1 - j;
    for (int64_t i = 0; i + m <= n; i += shift[t[i + m - 1]])
        if (t[i + m - 1] == p[m - 1] && memcmp(t + i, p, m - 1) == 0) count++;
    return count;
}

int main(void) {
    int64_t size = 16 << 20, len = 0;
    uint8_t *text = malloc(size + 16);
    state = 2026 | 1;
    while (len < size) {
        int64_t w = range(1, 8);
        for (int64_t k = 0; k < w; k++) text[len++] = (uint8_t)('a' + range(0, 7));
        text[len++] = ' ';
    }
    const char *patterns[] = {"bad", "face", "hhhh", "a bad", "decade", "cabbage"};
    int np = sizeof patterns / sizeof patterns[0];
    int64_t (*search[3])(const uint8_t *, int64_t, const uint8_t *, int64_t) = {naive, kmp, horspool};
    const char *names[] = {"naive", "kmp", "horspool"};
    int64_t ns[3] = {0, 0, 0};
    for (int i = 0; i < np; i++) {
        const uint8_t *p = (const uint8_t *)patterns[i];
        int64_t m = (int64_t)strlen(patterns[i]), counts[3];
        for (int k = 0; k < 3; k++) {
            int64_t t0 = now_ns();
            counts[k] = search[k](text, size, p, m);
            ns[k] += now_ns() - t0;
        }
        printf("%-12s %8lld%s\n", patterns[i], (long long)counts[0],
               counts[1] == counts[0] && counts[2] == counts[0] ? "" : "  MISMATCH");
    }
    for (int k = 0; k < 3; k++) {
        double ms = ns[k] / 1e6;
        fprintf(stderr, "%-9s %6.1f ms  %6.0f MB/s\n", names[k], ms, size * np / 1e6 / ms * 1000.0);
    }
    return 0;
}
