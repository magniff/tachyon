#include <stdio.h>
static long fannkuch(long n, long *max_flips_out) {
    long perm[16] = {0}, perm1[16] = {0}, count[16] = {0};
    for (long i = 0; i < n; i++) perm1[i] = i;
    long r = n, max_flips = 0, checksum = 0, perm_count = 0;
    for (;;) {
        while (r != 1) { count[r - 1] = r; r--; }
        for (long i = 0; i < n; i++) perm[i] = perm1[i];
        long flips = 0;
        long k = perm[0];
        while (k != 0) {
            long half = (k + 1) >> 1;
            for (long i = 0; i < half; i++) {
                long t = perm[i];
                perm[i] = perm[k - i];
                perm[k - i] = t;
            }
            flips++;
            k = perm[0];
        }
        if (flips > max_flips) max_flips = flips;
        if (perm_count % 2 == 0) checksum += flips; else checksum -= flips;
        for (;;) {
            if (r == n) { *max_flips_out = max_flips; return checksum; }
            long perm0 = perm1[0];
            for (long i = 0; i < r; i++) perm1[i] = perm1[i + 1];
            perm1[r] = perm0;
            count[r]--;
            if (count[r] > 0) break;
            r++;
        }
        perm_count++;
    }
}
int main(void) {
    long n = 10, max_flips;
    long checksum = fannkuch(n, &max_flips);
    printf("%ld\nPfannkuchen(%ld) = %ld\n", checksum, n, max_flips);
    return 0;
}
