/* bench/std: sort 5,000,000 random u64 (xorshift64): qsort, or with
   STABLE mergesort (BSD libc; qsort where there is none). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint64_t next(uint64_t *s) {
    uint64_t x = *s;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *s = x;
    return x;
}

static int cmp(const void *a, const void *b) {
    uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b;
    return x < y ? -1 : x > y;
}

int main(void) {
    size_t n = 5000000;
    uint64_t st = 0x9E3779B97F4A7C15ull;
    uint64_t *v = malloc(n * sizeof *v);
    for (size_t i = 0; i < n; i++) v[i] = next(&st);
#if defined(STABLE) && defined(__APPLE__)
    mergesort(v, n, sizeof *v, cmp);
#else
    qsort(v, n, sizeof *v, cmp);
#endif
    uint64_t sum = 0;
    for (size_t i = 0; i < n; i++) sum = sum * 31 + v[i];
    printf("%llu\n", (unsigned long long)sum);
    free(v);
    return 0;
}
