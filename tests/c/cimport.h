/* The C features `import` reads (tests/run/cimport_*.tach). */
#ifndef CIMPORT_H
#define CIMPORT_H

#include <stdint.h>
#include <stddef.h>

/* ---- Constants ---- */

#define CI_INT 42
#define CI_HEX 0xff00u
#define CI_LONG 1234567890123L
#define CI_NEG (-17)
#define CI_SHIFT (1 << 12)
#define CI_EXPR ((CI_INT * 2 + 1) % 50)
#define CI_CAST ((int16_t)70000)
#define CI_SIZE ((size_t)-1)
#define CI_CHAR 'A'
#define CI_DOUBLE 2.5e-3
#define CI_FLOAT 1.5f
#define CI_HEXFLOAT 0x1p-2
#define CI_SIZEOF (sizeof(struct ci_point) * 3)
#define CI_FUNCLIKE(x) ((x) + 1)
#define CI_STRING "not imported"

/* ---- Types ---- */

typedef int ci_int;
typedef ci_int ci_int2;
typedef unsigned long ci_size;

struct ci_point { int32_t x, y; };
typedef struct ci_point ci_point;
typedef struct { double re, im; } ci_complex;

enum ci_color { CI_RED, CI_GREEN = 5, CI_BLUE };
enum ci_signed { CI_LOW = -2, CI_HIGH = 2 };
enum __attribute__((packed)) ci_small { CI_S0, CI_S1 = 200 };
typedef enum { CI_ANON_A = 7, CI_ANON_B } ci_anon_enum;

struct ci_bits {
    unsigned a : 3;
    unsigned b : 5;
    int c : 10;
    uint8_t after;
    unsigned long long wide : 40;
    int tail;
};

/* Small enough for registers: bit-fields in the first eightbyte. */
struct ci_flags {
    unsigned ready : 1;
    unsigned count : 7;
    uint16_t id;
    float weight;
};

struct __attribute__((packed)) ci_packed {
    char c;
    int32_t i;
    int16_t s;
};

struct __attribute__((aligned(32))) ci_aligned32 {
    int32_t v;
};

struct ci_member_aligned {
    char c;
    int32_t i __attribute__((aligned(16)));
};

#pragma pack(push, 2)
struct ci_pack2 {
    char c;
    int64_t l;
    int16_t s;
};
#pragma pack(pop)

struct ci_anon_members {
    int kind;
    union {
        int32_t i;
        float f;
    };
    struct {
        int16_t lo, hi;
    };
};

union ci_union {
    int64_t l;
    double d;
    uint8_t bytes[8];
};

struct ci_outer {
    struct ci_inner { int8_t a; int64_t b; } inner;
    struct ci_inner array[2];
    union ci_union u;
};

/* Fields named with tachyon keywords. */
struct ci_keywords {
    int type;
    int match;
    int fn;
    int in;
    int loop;
};

typedef int (*ci_binop)(int, int);
struct ci_ops {
    ci_binop add;
    int (*mul)(int, int);
    const char *name;
};

/* ---- Functions and variables ---- */

int ci_add(int a, int b);
int ci_mul(int a, int b);
double ci_scale(double x, float factor, ci_int2 times);
ci_point ci_point_add(ci_point a, ci_point b);
ci_complex ci_complex_mul(ci_complex a, ci_complex b);
struct ci_bits ci_bits_make(unsigned a, unsigned b, int c, unsigned long long wide);
int ci_bits_sum(struct ci_bits b);
struct ci_flags ci_flags_make(int count, uint16_t id, float weight);
int ci_flags_check(struct ci_flags f, int count, uint16_t id);
int64_t ci_packed_sum(struct ci_packed p);
int64_t ci_pack2_sum(struct ci_pack2 p);
struct ci_aligned32 ci_aligned32_make(int32_t v);
int32_t ci_aligned32_sum(struct ci_aligned32 a, const struct ci_aligned32 *b);
int ci_apply(ci_binop op, int a, int b);
struct ci_ops ci_get_ops(void);
int ci_sum_ints(int n, ...);
const char *ci_color_name(enum ci_color c);
int ci_signed_value(enum ci_signed s);
int32_t ci_anon_get(struct ci_anon_members *m);
int64_t ci_outer_sum(const struct ci_outer *restrict o);
int ci_keywords_sum(struct ci_keywords k);
int match(int fn);
_Noreturn void ci_exit(int code);
void ci_set_counter(int value) __attribute__((nonnull));

#ifdef __APPLE__
int ci_renamed(int x) __asm__("_ci_real_name");
#else
int ci_renamed(int x) __asm__("ci_real_name");
#endif

extern int ci_counter;
extern const int ci_limit;
extern int ci_table[4];
extern struct ci_point ci_origin;
#define ci_alias_counter ci_counter
#define ci_alias_add ci_add

/* Left out, with a reason. */
static inline int ci_inline(int x) { return x + 1; }
long double ci_long_double(long double x);
__extension__ typedef long long ci_extension_ll;
_Static_assert(sizeof(struct ci_point) == 8, "point");

#endif
