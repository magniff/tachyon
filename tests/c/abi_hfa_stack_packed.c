/* The C side of tests/run/abi_hfa_stack_packed.vl. */
#include <stdint.h>

typedef struct { float a, b, c; } F3;
typedef struct { float a; } F1;

double c_take(F3 a, F3 b, F3 c, F1 d, F3 e, float f, int32_t g) {
    return a.a + b.b + c.a * 10 + c.b * 100 + c.c * 1000 + d.a * 10000
        + e.a * 1e5 + e.c * 1e6 + f * 1e7 + g * 1e8;
}

double t_take(F3 a, F3 b, F3 c, F1 d, F3 e, float f, int32_t g);

double c_call(void) {
    F3 a = {1, 2, 3}, b = {4, 5, 6}, c = {0.5, 0.25, 0.125}, e = {3, 0, 4};
    F1 d = {2};
    return t_take(a, b, c, d, e, 5, 6);
}
