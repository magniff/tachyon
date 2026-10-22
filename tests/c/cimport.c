/* The C side of tests/run/cimport_*.vl (declarations in cimport.h). */
#include <stdarg.h>
#include <stdlib.h>
#include "cimport.h"

int ci_counter = 3;
const int ci_limit = 99;
int ci_table[4] = {10, 20, 30, 40};
struct ci_point ci_origin = {-1, -2};

int ci_add(int a, int b) { return a + b; }
int ci_mul(int a, int b) { return a * b; }
double ci_scale(double x, float factor, ci_int2 times) { return x * factor * times; }
ci_point ci_point_add(ci_point a, ci_point b) { ci_point r = {a.x + b.x, a.y + b.y}; return r; }

ci_complex ci_complex_mul(ci_complex a, ci_complex b) {
    ci_complex r = {a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re};
    return r;
}

struct ci_bits ci_bits_make(unsigned a, unsigned b, int c, unsigned long long wide) {
    struct ci_bits r;
    r.a = a;
    r.b = b;
    r.c = c;
    r.after = 77;
    r.wide = wide;
    r.tail = -5;
    return r;
}

int ci_bits_sum(struct ci_bits b) { return (int)(b.a + b.b + b.c + b.after + (int)(b.wide % 1000) + b.tail); }
int64_t ci_packed_sum(struct ci_packed p) { return p.c + p.i + p.s; }
int64_t ci_pack2_sum(struct ci_pack2 p) { return p.c + p.l + p.s; }
int ci_apply(ci_binop op, int a, int b) { return op(a, b); }

struct ci_ops ci_get_ops(void) {
    struct ci_ops ops = {ci_add, ci_mul, "arith"};
    return ops;
}

int ci_sum_ints(int n, ...) {
    va_list ap;
    va_start(ap, n);
    int sum = 0;
    for (int i = 0; i < n; i++) sum += va_arg(ap, int);
    va_end(ap);
    return sum;
}

const char *ci_color_name(enum ci_color c) {
    return c == CI_RED ? "red" : c == CI_GREEN ? "green" : c == CI_BLUE ? "blue" : "?";
}

int ci_signed_value(enum ci_signed s) { return (int)s * 10; }
int32_t ci_anon_get(struct ci_anon_members *m) { return m->kind == 0 ? m->i : m->lo + m->hi; }

int64_t ci_outer_sum(const struct ci_outer *restrict o) {
    return o->inner.a + o->inner.b + o->array[0].a + o->array[1].b + o->u.l;
}

int ci_keywords_sum(struct ci_keywords k) { return k.type + k.match + k.fn + k.in + k.loop; }
int match(int fn) { return fn * 3; }
void ci_exit(int code) { exit(code); }
void ci_set_counter(int value) { ci_counter = value; }
int ci_renamed(int x) { return x * 100; }
long double ci_long_double(long double x) { return x; }

struct ci_flags ci_flags_make(int count, uint16_t id, float weight) {
    struct ci_flags f;
    f.ready = 1;
    f.count = (unsigned)count;
    f.id = id;
    f.weight = weight;
    return f;
}

int ci_flags_check(struct ci_flags f, int count, uint16_t id) {
    return f.ready == 1 && f.count == (unsigned)count && f.id == id && f.weight > 0.0f;
}

struct ci_aligned32 ci_aligned32_make(int32_t v) {
    struct ci_aligned32 a = { v };
    return a;
}

int32_t ci_aligned32_sum(struct ci_aligned32 a, const struct ci_aligned32 *b) {
    if (((unsigned long)b & 31) != 0) {
        return -1;
    }
    return a.v + 10 * b->v;
}
