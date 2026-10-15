/* 0.16: a C file tachyonc compiles and links (tests/run/link_c_files.tach);
   it calls libm, which tachyonc adds on Linux when C files are linked. */
#include <math.h>

double helper_hypot(double a, double b) {
    return sqrt(a * a + b * b);
}
