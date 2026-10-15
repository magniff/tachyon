/* The same count in C, for comparing speed: the same masks, the same
 * mirror symmetry, n = 1 to 14.
 *
 *     cc -O2 examples/algorithms/nqueens/reference.c -o nqueens-c && ./nqueens-c
 */
#include <stdint.h>
#include <stdio.h>
#include <time.h>

static int64_t count(uint64_t all, uint64_t cols, uint64_t left, uint64_t right) {
    if (cols == all) return 1;
    uint64_t free = all & ~(cols | left | right);
    int64_t total = 0;
    while (free != 0) {
        uint64_t bit = free & (0 - free);
        free ^= bit;
        total += count(all, cols | bit, (left | bit) << 1, (right | bit) >> 1);
    }
    return total;
}

static int64_t solutions(int n) {
    uint64_t all = (uint64_t)((1ULL << n) - 1);
    int64_t total = 0;
    for (int j = 0; j < n / 2; j++) {
        uint64_t bit = 1ull << j;
        total += count(all, bit, bit << 1, bit >> 1);
    }
    total *= 2;
    if (n % 2 == 1) {
        uint64_t bit = 1ull << (n / 2);
        total += count(all, bit, bit << 1, bit >> 1);
    }
    return total;
}

int main(void) {
    struct timespec t0, t1;
    timespec_get(&t0, TIME_UTC);
    for (int n = 1; n <= 14; n++) printf("%2d %10lld\n", n, (long long)solutions(n));
    timespec_get(&t1, TIME_UTC);
    fprintf(stderr, "n-queens 1..14: %lld ms\n",
            (long long)((t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000));
    return 0;
}
