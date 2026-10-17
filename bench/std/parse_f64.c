/* bench/std: parse 1,000,000 float texts `d.ddddddddddddddddeX` (17 random
   digits, the exponent in [-300, 300]) with strtod, the texts made first,
   in one buffer, five times. Prints the count and the FNV-1a hash of the bits read. */
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

int main(void) {
    size_t n = 1000000, len = 0;
    uint64_t st = 0x9E3779B97F4A7C15ull;
    char *text = malloc(n * 32);
    for (size_t i = 0; i < n; i++) {
        uint64_t m = next(&st) % 100000000000000000ull;
        char d[17];
        for (int k = 0; k < 17; k++) { d[16 - k] = '0' + m % 10; m /= 10; }
        text[len++] = d[0];
        text[len++] = '.';
        memcpy(text + len, d + 1, 16);
        len += 16;
        long e = (long)(next(&st) % 601) - 300;
        len += sprintf(text + len, "e%ld ", e);
    }
    text[len] = 0;
    uint64_t h = 0xcbf29ce484222325ull;
    size_t count = 0;
    for (int pass = 0; pass < 5; pass++) {
    char *p = text;
    while (*p) {
        char *end;
        double v = strtod(p, &end);
        uint64_t bits;
        memcpy(&bits, &v, 8);
        h = (h ^ bits) * 0x100000001b3ull;
        count++;
        p = end + 1;
    }
    }
    printf("%zu %llu\n", count, (unsigned long long)h);
    return 0;
}
