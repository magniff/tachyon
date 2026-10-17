/* bench/std: parse 10,000,000 decimal i64 texts (random magnitude and
   sign, made first, in one buffer) with strtoll, three times. Prints the count and the
   sum (an out-of-range text counts 0, as the others do). */
#include <errno.h>
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

int main(void) {
    size_t n = 10000000, len = 0;
    uint64_t st = 0x9E3779B97F4A7C15ull;
    char *text = malloc(n * 22 + 1);
    for (size_t i = 0; i < n; i++) {
        uint64_t r = next(&st);
        uint64_t m = r >> (r & 63);
        if (r & 64) text[len++] = '-';
        char d[20];
        int k = 20;
        do { d[--k] = '0' + m % 10; m /= 10; } while (m);
        for (; k < 20; k++) text[len++] = d[k];
        text[len++] = ' ';
    }
    text[len] = 0;
    int64_t sum = 0;
    size_t count = 0;
    for (int pass = 0; pass < 3; pass++) {
    char *p = text;
    while (*p) {
        char *end;
        errno = 0;
        long long v = strtoll(p, &end, 10);
        if (errno == ERANGE) v = 0;
        sum = (int64_t)((uint64_t)sum + (uint64_t)v);
        count++;
        p = end + 1;
    }
    }
    printf("%zu %lld\n", count, (long long)sum);
    return 0;
}
