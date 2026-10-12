#include <stdio.h>
#include <stdlib.h>
#define N 400
static void sweep(const double *src, double *dst) {
    for (long i = 1; i < N - 1; i++)
        for (long j = 1; j < N - 1; j++) {
            long k = i * N + j;
            dst[k] = 0.25 * (src[k - 1] + src[k + 1] + src[k - N] + src[k + N]);
        }
}
int main(void) {
    double *a = calloc(N * N, 8), *b = calloc(N * N, 8);
    for (long i = 0; i < N; i++) {
        a[i * N] = 100.0;
        b[i * N] = 100.0;
    }
    for (int t = 0; t < 100; t++) {
        sweep(a, b);
        sweep(b, a);
    }
    double total = 0.0;
    for (long k = 0; k < N * N; k++) total += a[k];
    printf("%.6f\n", total);
    return 0;
}
