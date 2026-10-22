/* C side of tests/run/c_interop.vl: globals read and written from both
   sides, calls of extern "C" vole functions by name, #[repr(C)] layouts
   checked against C's. */
#include <stddef.h>
#include <stdint.h>

int64_t c_counter = 40;
double c_scale = 2.5;
extern int64_t t_total;                 /* defined in vole */
int64_t t_square(int64_t x);            /* defined in vole */
int32_t t_classify(int32_t shape_tag);  /* defined in vole */

int64_t c_bump(void) { return ++c_counter; }
int64_t c_read_total(void) { return t_total; }
void c_add_total(int64_t k) { t_total += k; }
int64_t c_call_square(int64_t x) { return t_square(x) + 1; }

typedef enum { Red, Green = 10, Blue } Color;
Color c_next_color(Color c) { return c == Red ? Green : c == Green ? Blue : Red; }

typedef struct {
    int32_t tag;
    union { struct { double r; } circle; struct { double w, h; } rect; } u;
} Shape;
double c_area(Shape s) {
    return s.tag == 0 ? 3.0 * s.u.circle.r * s.u.circle.r : s.tag == 1 ? s.u.rect.w * s.u.rect.h : 0.0;
}
Shape c_square_shape(double side) { Shape s; s.tag = 1; s.u.rect.w = side; s.u.rect.h = side; return s; }

typedef union { int64_t i; double d; uint8_t bytes[8]; } Bits;
int64_t c_bits_of(Bits b) { return b.i; }

typedef struct __attribute__((packed)) { uint8_t a; int32_t b; uint16_t c; } Packed;
typedef struct __attribute__((aligned(16))) { int32_t x; } Aligned;
typedef struct { uint8_t a; Aligned b; uint8_t c; } HoldsAligned;
int64_t c_layout(int which) {
    switch (which) {
    case 0: return sizeof(Packed) * 100 + offsetof(Packed, b) * 10 + offsetof(Packed, c);
    case 1: return sizeof(Aligned) * 100 + _Alignof(Aligned);
    case 2: return sizeof(HoldsAligned) * 100 + offsetof(HoldsAligned, c);
    case 3: return sizeof(Shape) * 100 + offsetof(Shape, u);
    default: return sizeof(Bits);
    }
}
int64_t c_packed_sum(Packed p) { return p.a + p.b + p.c; }
