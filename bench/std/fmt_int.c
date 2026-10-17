/* bench/std: 10,000,000 random i64 (random magnitude and sign) with
   snprintf("%lld") into one buffer, a space after each, emptied every 64
   KB. Prints the length written and the FNV-1a hash. */
#include <stdint.h>
#include <stdio.h>

static uint64_t next(uint64_t *s) {
    uint64_t x = *s;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *s = x;
    return x;
}

static char out[1 << 17];

int main(void) {
    size_t n = 10000000, len = 0, total = 0;
    uint64_t st = 0x9E3779B97F4A7C15ull, h = 0xcbf29ce484222325ull;
    for (size_t i = 0; i < n; i++) {
        uint64_t r = next(&st);
        int64_t v = (int64_t)(r >> (r & 63));
        if (r & 64) v = (int64_t)(0 - (uint64_t)v);
        len += snprintf(out + len, 32, "%lld ", (long long)v);
        if (len > 65536) {
            for (size_t k = 0; k < len; k++) h = (h ^ (uint8_t)out[k]) * 0x100000001b3ull;
            total += len;
            len = 0;
        }
    }
    for (size_t k = 0; k < len; k++) h = (h ^ (uint8_t)out[k]) * 0x100000001b3ull;
    total += len;
    printf("%zu %llu\n", total, (unsigned long long)h);
    return 0;
}
