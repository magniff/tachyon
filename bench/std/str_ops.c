// bench/std: the str_ops loop by hand in C (memchr for the line and the
// fields, a trim, a decimal parse, memmem-like search for "ab"): 2,000,000
// CSV-like lines, three times. Prints what str_ops.vl prints.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint64_t next(uint64_t *s) {
    uint64_t x = *s;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *s = x;
    return x;
}

static int is_space(unsigned char c) { return c == ' ' || (c >= 9 && c <= 13); }

static void trim(const char **a, const char **b) {
    while (*a < *b && is_space((unsigned char)**a)) (*a)++;
    while (*b > *a && is_space((unsigned char)(*b)[-1])) (*b)--;
}

int main(void) {
    long n = 2000000;
    uint64_t st = 0x9E3779B97F4A7C15ull;
    char *text = malloc((size_t)n * 32);
    size_t len = 0;
    const char *letters = "abcde";
    for (long i = 0; i < n; i++) {
        uint64_t r = next(&st);
        len += (size_t)sprintf(text + len, "k%llu, %lld , ", (unsigned long long)(r % 1000),
            (long long)((int64_t)(r >> 10) % 100000 - 50000));
        uint64_t l = 3 + (r >> 40) % 6;
        for (uint64_t j = 0; j < l; j++) text[len++] = letters[(r >> (j * 3)) % 5];
        text[len++] = '\n';
    }
    long lines = 0, ab = 0, k1 = 0;
    int64_t sum = 0;
    for (int pass = 0; pass < 3; pass++) {
        const char *p = text, *end = text + len;
        while (p < end) {
            const char *nl = memchr(p, '\n', (size_t)(end - p));
            const char *le = nl ? nl : end;
            const char *c1 = memchr(p, ',', (size_t)(le - p));
            const char *c2 = memchr(c1 + 1, ',', (size_t)(le - c1 - 1));
            const char *ka = p, *kb = c1;
            const char *na = c1 + 1, *nb = c2;
            trim(&na, &nb);
            int64_t v = 0;
            int neg = 0, ok = na < nb;
            const char *q = na;
            if (q < nb && (*q == '-' || *q == '+')) { neg = *q == '-'; q++; }
            if (q == nb) ok = 0;
            for (; q < nb; q++) {
                if (*q < '0' || *q > '9') { ok = 0; break; }
                v = v * 10 + (*q - '0');
            }
            const char *wa = c2 + 1, *wb = le;
            trim(&wa, &wb);
            lines++;
            sum += ok ? (neg ? -v : v) : 0;
            for (const char *w = wa; w + 1 < wb; w++) {
                if (w[0] == 'a' && w[1] == 'b') { ab++; break; }
            }
            if (kb - ka >= 2 && ka[0] == 'k' && ka[1] == '1') k1++;
            p = le + 1;
        }
    }
    printf("%ld %lld %ld %ld\n", lines, (long long)sum, ab, k1);
    return 0;
}
