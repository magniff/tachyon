/* bench/std: 1,000,000 random f64 (in [0, 1e6)) written with
   snprintf("%.17g") into one buffer, a space after each (enough digits
   to read back, not the shortest: its text differs from Rust's and
   tachyon's, so the harness does not compare it). Prints the length and
   the FNV-1a hash. */
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
    size_t n = 1000000, len = 0;
    uint64_t st = 0x9E3779B97F4A7C15ull;
    char *out = malloc(n * 32);
    for (size_t i = 0; i < n; i++) {
        double x = (double)(next(&st) >> 11) * (1.0 / 9007199254740992.0) * 1e6;
        len += snprintf(out + len, 32, "%.17g ", x);
    }
    uint64_t h = 0xcbf29ce484222325ull;
    for (size_t i = 0; i < len; i++) h = (h ^ (uint8_t)out[i]) * 0x100000001b3ull;
    printf("%zu %llu\n", len, (unsigned long long)h);
    return 0;
}
