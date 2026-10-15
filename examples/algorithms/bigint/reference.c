/* The same arithmetic in C, for comparing speed: base 10^9 limbs, the
 * schoolbook kernel with carries every 16 rows, Karatsuba from 96 limbs,
 * Fibonacci by fast doubling, and a 5000 x 5000-limb product.
 *
 *     cc -O2 examples/algorithms/bigint/reference.c -o bigint-c && ./bigint-c
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define BASE 1000000000ULL
#define KARATSUBA_MIN 96

typedef struct { uint32_t *d; int64_t n; } Big;   /* n limbs, no zero on top */

static void mul_schoolbook(const uint32_t *a, int64_t na, const uint32_t *b, int64_t nb, uint32_t *r) {
    uint64_t *acc = calloc(na + nb, sizeof(uint64_t));
    for (int64_t i = 0; i < na;) {
        int64_t end = i + 16 < na ? i + 16 : na;
        for (int64_t row = i; row < end; row++) {
            uint64_t ai = a[row];
            for (int64_t j = 0; j < nb; j++) acc[row + j] += ai * b[j];
        }
        uint64_t carry = 0;
        for (int64_t k = i; k < na + nb; k++) {
            uint64_t cur = acc[k] + carry;
            acc[k] = cur % BASE;
            carry = cur / BASE;
            if (carry == 0 && k >= end + nb) break;
        }
        i = end;
    }
    for (int64_t k = 0; k < na + nb; k++) r[k] = (uint32_t)acc[k];
    free(acc);
}

static void add_at(uint32_t *r, const uint32_t *x, int64_t nx, int64_t off) {
    uint32_t carry = 0;
    int64_t k = off;
    for (int64_t i = 0; i < nx; i++, k++) {
        uint32_t s = r[k] + x[i] + carry;
        carry = s >= BASE;
        r[k] = carry ? s - BASE : s;
    }
    for (; carry; k++) {
        uint32_t s = r[k] + 1;
        if (s == BASE) r[k] = 0; else { r[k] = s; carry = 0; }
    }
}

static void sub_from(uint32_t *r, const uint32_t *x, int64_t nx) {
    uint32_t borrow = 0;
    int64_t k = 0;
    for (; k < nx; k++) {
        uint32_t sub = x[k] + borrow;
        if (r[k] >= sub) { r[k] -= sub; borrow = 0; } else { r[k] = r[k] + BASE - sub; borrow = 1; }
    }
    for (; borrow; k++) {
        if (r[k] > 0) { r[k]--; borrow = 0; } else r[k] = BASE - 1;
    }
}

static int64_t trim(const uint32_t *x, int64_t n) {
    while (n > 0 && x[n - 1] == 0) n--;
    return n;
}

static void mul_karatsuba(const uint32_t *a, int64_t na, const uint32_t *b, int64_t nb, uint32_t *r) {
    if (na < nb) { mul_karatsuba(b, nb, a, na, r); return; }
    if (nb < KARATSUBA_MIN) { mul_schoolbook(a, na, b, nb, r); return; }
    if (2 * nb <= na) {
        uint32_t *p = malloc(sizeof(uint32_t) * 2 * nb);
        for (int64_t off = 0; off < na;) {
            int64_t end = off + nb < na ? off + nb : na;
            memset(p, 0, sizeof(uint32_t) * 2 * nb);
            mul_karatsuba(a + off, end - off, b, nb, p);
            add_at(r, p, trim(p, 2 * nb), off);
            off = end;
        }
        free(p);
        return;
    }
    int64_t m = na / 2;
    mul_karatsuba(a, m, b, m, r);
    mul_karatsuba(a + m, na - m, b + m, nb - m, r + 2 * m);
    int64_t nsa = na - m + 1, nsb = (m > nb - m ? m : nb - m) + 1;
    uint32_t *sa = calloc(nsa, 4), *sb = calloc(nsb, 4), *p = calloc(nsa + nsb, 4);
    add_at(sa, a, m, 0);
    add_at(sa, a + m, na - m, 0);
    add_at(sb, b, m, 0);
    add_at(sb, b + m, nb - m, 0);
    mul_karatsuba(sa, nsa, sb, nsb, p);
    sub_from(p, r, 2 * m);
    sub_from(p, r + 2 * m, na + nb - 2 * m);
    add_at(r, p, trim(p, nsa + nsb), m);
    free(sa);
    free(sb);
    free(p);
}

static Big mul(Big x, Big y) {
    Big r = {calloc(x.n + y.n + 1, 4), x.n + y.n};
    mul_karatsuba(x.d, x.n, y.d, y.n, r.d);
    r.n = trim(r.d, r.n);
    return r;
}

static Big add(Big x, Big y) {
    int64_t n = (x.n > y.n ? x.n : y.n) + 1;
    Big r = {calloc(n, 4), n};
    add_at(r.d, x.d, x.n, 0);
    add_at(r.d, y.d, y.n, 0);
    r.n = trim(r.d, n);
    return r;
}

static Big sub(Big x, Big y) {   /* x >= y */
    Big r = {malloc(4 * (x.n + 1)), x.n};
    memcpy(r.d, x.d, 4 * x.n);
    sub_from(r.d, y.d, y.n);
    r.n = trim(r.d, r.n);
    return r;
}

static Big fib(int64_t n) {
    Big a = {calloc(1, 4), 0}, b = {calloc(1, 4), 1};
    b.d[0] = 1;
    int bit = 62;
    while (bit >= 0 && ((n >> bit) & 1) == 0) bit--;
    for (; bit >= 0; bit--) {
        Big twice = add(b, b), diff = sub(twice, a), sa = mul(a, a), sb = mul(b, b);
        Big even = mul(a, diff), odd = add(sa, sb);
        free(twice.d); free(diff.d); free(sa.d); free(sb.d); free(a.d); free(b.d);
        if ((n >> bit) & 1) { a = odd; b = add(even, odd); free(even.d); }
        else { a = even; b = odd; }
    }
    free(b.d);
    return a;
}

static uint64_t state = 2026 | 1;
static uint64_t next(void) {
    uint64_t x = state;
    x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
    state = x;
    return x * 0x2545F4914F6CDD1DULL;
}

static double now_ms(void) {
    struct timespec t;
    timespec_get(&t, TIME_UTC);
    return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}

int main(void) {
    double t0 = now_ms();
    Big f = fib(1000000);
    double t1 = now_ms();
    int64_t top = f.d[f.n - 1], digits = 9 * (f.n - 1), sum = 0;
    while (top > 0) { digits++; top /= 10; }
    for (int64_t i = 0; i < f.n; i++) for (uint32_t x = f.d[i]; x; x /= 10) sum += x % 10;
    printf("F(1000000): %lld digits, digit sum %lld\n", (long long)digits, (long long)sum);
    fprintf(stderr, "F(1000000) by fast doubling: %.1f ms\n", t1 - t0);

    int64_t n = 5000;
    Big x = {malloc(4 * n), n}, y = {malloc(4 * n), n};
    for (int64_t i = 0; i < n; i++) x.d[i] = (next() >> 32) % BASE;
    for (int64_t i = 0; i < n; i++) y.d[i] = (next() >> 32) % BASE;
    uint32_t *slow = calloc(2 * n, 4);
    double t2 = now_ms();
    mul_schoolbook(x.d, n, y.d, n, slow);
    double t3 = now_ms();
    Big fast = mul(x, y);
    double t4 = now_ms();
    printf("equal: %d\n", memcmp(slow, fast.d, 4 * fast.n) == 0);
    fprintf(stderr, "%lld x %lld limbs: schoolbook %.1f ms, karatsuba %.1f ms\n",
            (long long)n, (long long)n, t3 - t2, t4 - t3);
    return 0;
}
