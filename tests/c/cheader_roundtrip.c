/* The C side of tests/run/cheader_roundtrip.tach, through the header
   tachyonc --emit-header makes for it. */
#include <stdio.h>
#include <stddef.h>
#include "roundtrip.h"

static double c_cb(int32_t x) { return x + 0.5; }

int c_drive(void) {
    Shape c = {.tag = Shape_Circle_TAG, .u.Circle = {2.0}};
    Shape r = {.tag = Shape_Rect_TAG, .u.Rect = {3.0, 4.0}};
    Shape e = {.tag = Shape_Empty_TAG};
    printf("area %.1f %.1f %.1f\n", area(c), area(r), area(e));
    Vec2 v = make(1.5f, -2.0f);
    printf("make %.1f %.1f\n", v.x, v.y);
    Packed p = {1, 1000};
    Pack2 q = {2, 5000000000ULL};
    Aligned a = {7};
    printf("packed %lld\n", (long long)packed_sum(p, q, a));
    printf("color %d\n", color_code(Color_Blue, Small_B));
    Tagged t1 = {.One = {Tagged_One_TAG, -9}};
    Tagged t2 = {.Two = {Tagged_Two_TAG, 100, 5}};
    printf("tagged %lld %lld\n", (long long)tagged_value(t1), (long long)tagged_value(t2));
    U u;
    u.i = 12345;
    printf("union %lld\n", (long long)union_bits(u));
    Holder h2 = {{1.0f, 2.0f}, {1, 2, 3}, NULL, NULL, twice};
    Holder h1 = {{10.0f, 0.0f}, {4, 5, 6}, &h2, NULL, c_cb};
    printf("walk %.1f\n", walk(&h1));
    Shape m = make_shape(1);
    printf("shape %d %.1f\n", m.tag, m.u.Rect._0);
    bump();
    bump();
    printf("limit %d\n", LIMIT);
    return 42;
}
