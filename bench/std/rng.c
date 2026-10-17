/* bench/std rng (0.20, A7): xoshiro256++ (the reference C code) seeded by
 * splitmix64, 10^9 next(), then 10^8 draws in [0, n) for n from 1 to 1024
 * by Lemire's method (unsigned __int128): rng.tach's algorithm in C. */
#include <stdint.h>
#include <stdio.h>

static inline uint64_t rotl(const uint64_t x, int k) { return (x << k) | (x >> (64 - k)); }

static uint64_t s[4];

static inline uint64_t next(void) {
    const uint64_t result = rotl(s[0] + s[3], 23) + s[0];
    const uint64_t t = s[1] << 17;
    s[2] ^= s[0];
    s[3] ^= s[1];
    s[1] ^= s[2];
    s[0] ^= s[3];
    s[2] ^= t;
    s[3] = rotl(s[3], 45);
    return result;
}

static uint64_t splitmix64(uint64_t *x) {
    uint64_t z = (*x += 0x9e3779b97f4a7c15);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) * 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

static inline uint64_t below(uint64_t n) {
    unsigned __int128 m = (unsigned __int128)next() * n;
    if ((uint64_t)m < n) {
        uint64_t t = (0 - n) % n;
        while ((uint64_t)m < t) m = (unsigned __int128)next() * n;
    }
    return (uint64_t)(m >> 64);
}

int main(void) {
    uint64_t st = 20201016;
    for (int i = 0; i < 4; i++) s[i] = splitmix64(&st);
    uint64_t sum = 0;
    for (long i = 0; i < 1000000000; i++) sum += next();
    uint64_t sum2 = 0;
    for (uint64_t i = 0; i < 100000000; i++) sum2 += below((i & 1023) + 1);
    printf("%llu %llu\n", (unsigned long long)sum, (unsigned long long)sum2);
    return 0;
}
