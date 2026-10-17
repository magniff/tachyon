/* bench/std's text benchmarks' input, C half: text_gen.tach's five kinds
   of text, byte for byte, and the same benchmark loop (`KIND SUM` on
   stdout, `NAME KIND: MB/s` on stderr). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define TG_SIZE (16 * 1024 * 1024)

typedef struct { unsigned char *p; size_t len, cap; } tg_buf;

static void tg_push(tg_buf *b, unsigned char c) {
    if (b->len == b->cap) { b->cap = b->cap ? b->cap * 2 : 1 << 20; b->p = realloc(b->p, b->cap); }
    b->p[b->len++] = c;
}
static void tg_str(tg_buf *b, const char *s) { while (*s) tg_push(b, (unsigned char)*s++); }
static uint64_t tg_next(uint64_t *s) {
    uint64_t x = *s; x ^= x << 13; x ^= x >> 7; x ^= x << 17; *s = x; return x;
}
static void tg_put(tg_buf *b, uint32_t cp) {
    if (cp < 0x80) tg_push(b, (unsigned char)cp);
    else if (cp < 0x800) { tg_push(b, 0xc0 | (cp >> 6)); tg_push(b, 0x80 | (cp & 0x3f)); }
    else if (cp < 0x10000) { tg_push(b, 0xe0 | (cp >> 12)); tg_push(b, 0x80 | ((cp >> 6) & 0x3f)); tg_push(b, 0x80 | (cp & 0x3f)); }
    else { tg_push(b, 0xf0 | (cp >> 18)); tg_push(b, 0x80 | ((cp >> 12) & 0x3f)); tg_push(b, 0x80 | ((cp >> 6) & 0x3f)); tg_push(b, 0x80 | (cp & 0x3f)); }
}
static void tg_word(tg_buf *b, uint64_t x) {
    uint64_t n = 1 + (x >> 8) % 9;
    for (uint64_t i = 0; i < n; i++) tg_push(b, (unsigned char)(97 + (x >> (12 + i * 5)) % 26));
}
static const uint32_t TG_ACCENTED[16] = {0xe9, 0xe8, 0xea, 0xe0, 0xe7, 0xf4, 0xfb, 0xe4, 0xf6, 0xfc, 0xdf, 0xc9, 0xef, 0xee, 0xf9, 0x153};
static void tg_latin_word(tg_buf *b, uint64_t x) {
    uint64_t n = 2 + (x >> 8) % 9;
    for (uint64_t i = 0; i < n; i++) {
        uint64_t y = x >> (12 + i * 5);
        if (y % 6 == 0) tg_put(b, TG_ACCENTED[(y >> 1) % 16]);
        else tg_push(b, (unsigned char)(97 + y % 26));
    }
}
static const uint32_t TG_CJK_PUNCT[6] = {0x3001, 0x3002, 0xff0c, 0xff01, 0x300c, 0x300d};
static void tg_cjk_run(tg_buf *b, uint64_t *s, uint64_t x) {
    uint64_t n = 4 + (x >> 8) % 20;
    for (uint64_t i = 0; i < n; i++) tg_put(b, (uint32_t)(0x4e00 + tg_next(s) % 0x5200));
    tg_put(b, TG_CJK_PUNCT[(x >> 16) % 6]);
}
static const uint32_t TG_EMOJI[26] = {
    0x1f600, 0, 0x1f680, 0, 0x2764, 0xfe0f, 0, 0x1f44d, 0x1f3fd, 0, 0x1f468, 0x200d, 0x1f469,
    0x200d, 0x1f467, 0, 0x1f1eb, 0x1f1f7, 0, 0x33, 0xfe0f, 0x20e3, 0, 0x1f9d1, 0x200d, 0x1f4bb};
static const int TG_EMOJI_STARTS[7] = {0, 2, 4, 7, 10, 16, 19};
static void tg_emoji(tg_buf *b, uint64_t x) {
    int k = (int)((x >> 8) % 8);
    if (k == 7) { tg_put(b, (uint32_t)(0x1f600 + (x >> 16) % 0x50)); return; }
    int i = k == 6 ? 23 : TG_EMOJI_STARTS[k];
    while (i < 26 && TG_EMOJI[i] != 0) tg_put(b, TG_EMOJI[i++]);
}
static const char *tg_kind_name(int k) {
    static const char *names[5] = {"source", "latin", "cjk", "emoji", "mixed"};
    return names[k];
}
static tg_buf tg_make(int k) {
    tg_buf b = {0, 0, 0};
    uint64_t s = 0x9e3779b97f4a7c15ULL ^ (((uint64_t)k + 1) * 0x2545f4914f6cdd1dULL);
    size_t col = 0;
    while (b.len < TG_SIZE) {
        uint64_t x = tg_next(&s);
        size_t start = b.len;
        if (k == 0) {
            uint64_t t = x % 10;
            if (t < 6) tg_word(&b, x);
            else if (t == 6) tg_str(&b, "(x, 1);");
            else if (t == 7) tg_str(&b, "{ }");
            else if (t == 8) tg_str(&b, "= 0");
            else { tg_str(&b, "\n    "); col = 0; }
        } else if (k == 1) {
            tg_latin_word(&b, x);
        } else if (k == 2) {
            tg_cjk_run(&b, &s, x);
        } else if (k == 3) {
            if (x % 4 == 0) tg_emoji(&b, x); else tg_word(&b, x);
        } else {
            uint64_t t = x % 100;
            if (t < 50) tg_word(&b, x);
            else if (t < 62) tg_latin_word(&b, x);
            else if (t < 68) { for (uint64_t i = 0; i < 3 + (x >> 8) % 6; i++) tg_put(&b, (uint32_t)(0x430 + (x >> (12 + i * 5)) % 32)); }
            else if (t < 72) { for (uint64_t i = 0; i < 3 + (x >> 8) % 6; i++) tg_put(&b, (uint32_t)(0x3b1 + (x >> (12 + i * 5)) % 25)); }
            else if (t < 80) tg_cjk_run(&b, &s, x);
            else if (t < 85) {
                tg_put(&b, (uint32_t)(0xac00 + (x >> 8) % 11172));
                tg_put(&b, (uint32_t)(0x1100 + (x >> 24) % 19));
                tg_put(&b, (uint32_t)(0x1161 + (x >> 32) % 21));
                tg_put(&b, (uint32_t)(0x11a8 + (x >> 40) % 27));
            } else if (t < 90) {
                tg_put(&b, (uint32_t)(0x915 + (x >> 8) % 32));
                tg_put(&b, 0x94d);
                tg_put(&b, (uint32_t)(0x915 + (x >> 16) % 32));
                tg_put(&b, (uint32_t)(0x93e + (x >> 24) % 10));
            } else if (t < 95) {
                tg_push(&b, 'e');
                tg_put(&b, (uint32_t)(0x300 + (x >> 8) % 0x30));
            } else tg_emoji(&b, x);
        }
        col += b.len - start;
        if (k != 0) {
            if (col > 60 + (size_t)((x >> 56) % 20)) { tg_push(&b, '\n'); col = 0; }
            else if (k != 2) tg_push(&b, ' ');
        } else if (col > 0) tg_push(&b, ' ');
    }
    tg_str(&b, "\n\n\n\n");
    return b;
}
static double tg_now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}
static void tg_run(const char *name, const int *kinds, int nkinds, uint64_t (*op)(const unsigned char *, size_t)) {
    for (int j = 0; j < nkinds; j++) {
        tg_buf b = tg_make(kinds[j]);
        uint64_t sum = 0;
        double best = 1e30;
        for (int r = 0; r < 10; r++) {
            double t = tg_now();
            uint64_t x = op(b.p, b.len - (size_t)(r % 4));
            double dt = tg_now() - t;
            sum += x;
            if (dt < best) best = dt;
        }
        printf("%s %llu\n", tg_kind_name(kinds[j]), (unsigned long long)sum);
        fprintf(stderr, "%s %s: %.0f MB/s\n", name, tg_kind_name(kinds[j]), (double)b.len / best / 1e6);
        free(b.p);
    }
}
