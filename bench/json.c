#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
typedef struct { unsigned char *ptr; long len, cap; uint64_t state; } Gen;
static uint64_t next(Gen *g) {
    g->state = g->state * 6364136223846793005ULL + 1442695040888963407ULL;
    return g->state >> 33;
}
static void push(Gen *g, unsigned char c) {
    if (g->len == g->cap) {
        g->cap = g->cap == 0 ? 4 : g->cap * 2;
        g->ptr = realloc(g->ptr, g->cap);
    }
    g->ptr[g->len++] = c;
}
static void gen_number(Gen *g) {
    long v = (long)(next(g) % 200000) - 100000;
    if (v < 0) { push(g, '-'); v = -v; }
    unsigned char digits[20];
    int n = 0;
    for (;;) {
        digits[n++] = '0' + v % 10;
        v = v / 10;
        if (v == 0) break;
    }
    while (n > 0) push(g, digits[--n]);
}
static void gen_string(Gen *g) {
    push(g, '"');
    uint64_t len = next(g) % 12;
    for (uint64_t i = 0; i < len; i++) {
        uint64_t r = next(g) % 32;
        if (r == 0) { push(g, '\\'); push(g, '"'); }
        else if (r == 1) { push(g, '\\'); push(g, 'n'); }
        else push(g, 'a' + r % 26);
    }
    push(g, '"');
}
static void gen_literal(Gen *g, const char *w) {
    for (; *w; w++) push(g, *w);
}
static void gen_value(Gen *g, long depth) {
    uint64_t r = depth >= 6 ? next(g) % 6 : next(g) % 10;
    if (r <= 1 || r == 5) gen_number(g);
    else if (r <= 3) gen_string(g);
    else if (r == 4) {
        uint64_t k = next(g) % 3;
        gen_literal(g, k == 0 ? "true" : k == 1 ? "false" : "null");
    } else if (r <= 7) {
        push(g, '[');
        uint64_t n = next(g) % 6;
        for (uint64_t i = 0; i < n; i++) {
            if (i > 0) { push(g, ','); push(g, ' '); }
            gen_value(g, depth + 1);
        }
        push(g, ']');
    } else {
        push(g, '{');
        uint64_t n = next(g) % 6;
        for (uint64_t i = 0; i < n; i++) {
            if (i > 0) { push(g, ','); push(g, ' '); }
            gen_string(g);
            push(g, ':'); push(g, ' ');
            gen_value(g, depth + 1);
        }
        push(g, '}');
    }
}

typedef struct {
    const unsigned char *s; long len, pos;
    long values, numbers, sum, strings, chars, literals, arrays, objects, max_depth;
} Parser;
static unsigned char peek(Parser *p) { return p->pos < p->len ? p->s[p->pos] : 0; }
static void skip_space(Parser *p) {
    while (p->pos < p->len) {
        unsigned char c = p->s[p->pos];
        if (c == ' ' || c == '\n' || c == '\t' || c == '\r') p->pos++;
        else break;
    }
}
static int parse_string(Parser *p) {
    p->pos++;
    for (;;) {
        if (p->pos >= p->len) return 0;
        unsigned char c = p->s[p->pos++];
        if (c == '"') { p->strings++; return 1; }
        if (c == '\\') {
            if (p->pos >= p->len) return 0;
            p->pos++;
        }
        p->chars++;
    }
}
static int parse_number(Parser *p) {
    int negative = 0;
    if (peek(p) == '-') { negative = 1; p->pos++; }
    long start = p->pos, v = 0;
    while (p->pos < p->len) {
        unsigned char c = p->s[p->pos];
        if (c < '0' || c > '9') break;
        v = v * 10 + (c - '0');
        p->pos++;
    }
    if (p->pos == start) return 0;
    p->numbers++;
    p->sum += negative ? -v : v;
    return 1;
}
static int parse_literal(Parser *p, const char *w) {
    for (; *w; w++) {
        if (peek(p) != (unsigned char)*w) return 0;
        p->pos++;
    }
    p->literals++;
    return 1;
}
static int parse_value(Parser *p, long depth) {
    if (depth > p->max_depth) p->max_depth = depth;
    skip_space(p);
    unsigned char c = peek(p);
    if (c == '[') {
        p->arrays++;
        p->pos++;
        skip_space(p);
        if (peek(p) == ']') { p->pos++; return 1; }
        for (;;) {
            if (!parse_value(p, depth + 1)) return 0;
            skip_space(p);
            unsigned char d = peek(p);
            p->pos++;
            if (d == ']') return 1;
            if (d != ',') return 0;
        }
    }
    if (c == '{') {
        p->objects++;
        p->pos++;
        skip_space(p);
        if (peek(p) == '}') { p->pos++; return 1; }
        for (;;) {
            skip_space(p);
            if (peek(p) != '"' || !parse_string(p)) return 0;
            skip_space(p);
            if (peek(p) != ':') return 0;
            p->pos++;
            if (!parse_value(p, depth + 1)) return 0;
            skip_space(p);
            unsigned char d = peek(p);
            p->pos++;
            if (d == '}') return 1;
            if (d != ',') return 0;
        }
    }
    if (c == '"') return parse_string(p);
    if (c == '-' || (c >= '0' && c <= '9')) return parse_number(p);
    if (c == 't') return parse_literal(p, "true");
    if (c == 'f') return parse_literal(p, "false");
    if (c == 'n') return parse_literal(p, "null");
    return 0;
}
int main(void) {
    Gen g = { 0, 0, 0, 12345 };
    while (g.len < 24000000) {
        gen_value(&g, 0);
        push(&g, '\n');
    }
    Parser p = { g.ptr, g.len, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    for (;;) {
        skip_space(&p);
        if (p.pos >= p.len) break;
        if (!parse_value(&p, 1)) { printf("error at %ld\n", p.pos); return 1; }
        p.values++;
    }
    printf("%ld bytes, %ld values\n", p.len, p.values);
    printf("%ld numbers (sum %ld), %ld strings (%ld chars), %ld literals\n",
           p.numbers, p.sum, p.strings, p.chars, p.literals);
    printf("%ld arrays, %ld objects, depth %ld\n", p.arrays, p.objects, p.max_depth);
    free(g.ptr);
    return 0;
}
