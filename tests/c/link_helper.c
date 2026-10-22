/* 0.16: a C file volec compiles and links (tests/run/link_c_files.vl);
   it calls libm, which volec adds on Linux when C files are linked. */
#include <math.h>

double helper_hypot(double a, double b) {
    return sqrt(a * a + b * b);
}
