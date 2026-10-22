#include <stdio.h>
#include <stdint.h>
/* vole never contracts a * b + c into a fused multiply-add */
#pragma STDC FP_CONTRACT OFF
int main(void) {
    long n = 2400, inside = 0;
    uint64_t hash = 14695981039346656037ULL;
    for (long y = 0; y < n; y++) {
        double ci = 2.0 * (double)y / (double)n - 1.0;
        uint64_t bits = 0;
        for (long x = 0; x < n; x++) {
            double cr = 2.0 * (double)x / (double)n - 1.5;
            double zr = 0, zi = 0, tr = 0, ti = 0;
            long i = 0;
            while (i < 50 && tr + ti <= 4.0) {
                zi = 2.0 * zr * zi + ci;
                zr = tr - ti + cr;
                tr = zr * zr;
                ti = zi * zi;
                i++;
            }
            bits = bits << 1;
            if (tr + ti <= 4.0) { bits = bits | 1; inside++; }
            if (x % 8 == 7) { hash = (hash ^ bits) * 1099511628211ULL; bits = 0; }
        }
    }
    printf("%ld %lu\n", inside, (unsigned long)hash);
    return 0;
}
