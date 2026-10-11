#include <stdio.h>
static long steps(unsigned long n) {
    long count = 0;
    while (n != 1) { if (n % 2 == 0) n = n / 2; else n = 3 * n + 1; count++; }
    return count;
}
int main(void) {
    long best = 0; unsigned long best_start = 1;
    for (unsigned long start = 1; start < 3000000; start++) {
        long s = steps(start);
        if (s > best) { best = s; best_start = start; }
    }
    printf("%lu %ld\n", best_start, best);
    return 0;
}
