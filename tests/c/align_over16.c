// C half of tests/run/align_over16.vl: structs aligned above 16, passed
// to and from vole by value and by pointer.
#include <stdint.h>

struct __attribute__((aligned(64))) A64 { long x; long y; };
struct __attribute__((aligned(32))) A32 { double d; int i; };

long vole_take_a64(long a, struct A64 s, long b);
struct A64 vole_make_a64(long x);

static int misaligned(const void *p, uintptr_t align) {
    return ((uintptr_t)p & (align - 1)) != 0;
}

long c_take_a64(long a, long b, long c, long d, long e, long f, long g, struct A64 s, long h) {
    return a + b + c + d + e + f + g + s.x * 3 + s.y * 5 + h * 7;
}

long c_take_a32(struct A32 s, double k) {
    return (long)(s.d * k) + s.i;
}

struct A64 c_make_a64(long x) {
    struct A64 s = { x, -x };
    return s;
}

long c_check_ptr(const struct A64 *p) {
    return misaligned(p, 64) ? -1 : p->x + p->y;
}

long c_call_vole(long x) {
    struct A64 s = vole_make_a64(x);
    if (misaligned(&s, 64)) {
        return -1;
    }
    return vole_take_a64(1, s, 2);
}
