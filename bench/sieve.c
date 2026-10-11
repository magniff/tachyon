#include <stdio.h>
#include <stdlib.h>
static long count_primes(long limit) {
    unsigned char *composite = calloc(limit + 1, 1);
    long count = 0;
    for (long i = 2; i <= limit; i++) {
        if (composite[i] == 0) {
            count++;
            for (long j = i * i; j <= limit; j += i) composite[j] = 1;
        }
    }
    return count;
}
int main(void) { printf("%ld\n", count_primes(30000000)); return 0; }
