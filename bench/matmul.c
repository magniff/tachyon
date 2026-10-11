#include <stdio.h>
#include <stdlib.h>
#define N 300
static double *at(double *m, long i, long j) { return &m[i * N + j]; }
static void multiply(double *a, double *b, double *c) {
    for (long i = 0; i < N; i++)
        for (long j = 0; j < N; j++) {
            double sum = 0.0;
            for (long k = 0; k < N; k++) sum += *at(a, i, k) * *at(b, k, j);
            *at(c, i, j) = sum;
        }
}
int main(void) {
    double *a = malloc(N * N * 8), *b = malloc(N * N * 8), *c = malloc(N * N * 8);
    for (long i = 0; i < N; i++)
        for (long j = 0; j < N; j++) {
            *at(a, i, j) = (double)(i + j) / (double)N;
            *at(b, i, j) = (double)(i - j) / (double)N;
        }
    double total = 0.0;
    for (int r = 0; r < 3; r++) { multiply(a, b, c); total += *at(c, N / 2, N / 3); }
    printf("%.6f\n", total);
    return 0;
}
