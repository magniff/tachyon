/* C side of tests/run/abi_c_structs.vl: functions taking and returning
   aggregates by value, and calling vole functions that do, to check that
   vole follows the C convention for every kind of aggregate. */
#include <stdint.h>

typedef struct { uint8_t a, b, c; } I8x3;
typedef struct { int32_t a, b, c; } I32x3;
typedef struct { int64_t a, b; } I64x2;
typedef struct { int64_t a, b, c; } I64x3;
typedef struct { float x, y; } F32x2;
typedef struct { float x, y, z; } F32x3;
typedef struct { double a, b, c, d; } F64x4;
typedef struct { double x; int32_t n; } Mixed;
typedef struct { int32_t n; float x; } MixedF;
/* A #[repr(C)] enum with fields: an int tag, then a union of structs. */
typedef struct { int32_t tag; double value; } Tagged;
typedef struct { const int64_t *ptr; uint64_t len; } Slice;

I8x3 c_i8x3(I8x3 v, int k) { I8x3 r = { v.a + k, v.b + k, v.c + k }; return r; }
I32x3 c_i32x3(I32x3 v) { I32x3 r = { v.c, v.b * 2, v.a }; return r; }
I64x2 c_i64x2(I64x2 v, I64x2 w) { I64x2 r = { v.a + w.b, v.b - w.a }; return r; }
I64x3 c_i64x3(I64x3 v) { I64x3 r = { v.a * 10, v.b * 10, v.c * 10 }; return r; }
F32x2 c_f32x2(F32x2 v) { F32x2 r = { v.y, v.x + 0.5f }; return r; }
F32x3 c_f32x3(F32x3 v, float k) { F32x3 r = { v.x * k, v.y * k, v.z * k }; return r; }
F64x4 c_f64x4(F64x4 v) { F64x4 r = { v.d, v.c, v.b, v.a }; return r; }
Mixed c_mixed(Mixed v) { Mixed r = { v.x * 2, v.n + 1 }; return r; }
MixedF c_mixedf(MixedF v) { MixedF r = { v.n * 3, v.x - 1 }; return r; }
Tagged c_tagged(Tagged v) { Tagged r = { v.tag + 1, v.value / 2 }; return r; }

int64_t c_slice_sum(Slice s) {
    int64_t total = 0;
    for (uint64_t i = 0; i < s.len; i++) total += s.ptr[i];
    return total;
}

/* Registers run out: the later aggregates go on the stack. */
double c_many(F64x4 a, F32x3 b, Mixed c, I64x2 d, I64x2 e, I64x2 f, I64x2 g, I32x3 h,
              F32x2 i, double j, I8x3 k) {
    return a.a + a.d + b.z + c.x + c.n + d.a + e.b + f.a + g.b + h.c + i.y + j + k.c;
}

/* Calls vole back with aggregates. */
typedef Mixed (*MixedFn)(Mixed, F32x3, I8x3);
double c_call_back(MixedFn f) {
    Mixed m = { 1.5, 7 };
    F32x3 v = { 1, 2, 3 };
    I8x3 b = { 4, 5, 6 };
    Mixed r = f(m, v, b);
    return r.x + r.n;
}

typedef F64x4 (*BigFn)(I64x3, F64x4);
double c_call_big(BigFn f) {
    I64x3 a = { 1, 2, 3 };
    F64x4 b = { 0.5, 0.25, 0.125, 0.0625 };
    F64x4 r = f(a, b);
    return r.a + r.b + r.c + r.d;
}
