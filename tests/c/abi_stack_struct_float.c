/* The C side of tests/run/abi_stack_struct_float.tach. */
#include <stdint.h>

typedef struct { double d; int32_t i; } Mixed;

double t_after_stack(int64_t a, int64_t b, int64_t c, int64_t d, int64_t e, int64_t f, Mixed m, double x);

double c_call(void) {
    Mixed m = {2.5, 7};
    return t_after_stack(1, 2, 3, 4, 5, 6, m, 0.25);
}
