/* ring.c: the C half of the c-mixed-build example. */
#include <stdlib.h>

#include "ring.h"
/* The vole program's own header, written by
 * `volec --emit-header main.vl -o main.h`: it declares on_evict and
 * the EVICTIONS static, which main.vl defines. */
#include "main.h"

Ring *ring_new(size_t cap) {
    if (cap == 0) return NULL;
    Ring *r = malloc(sizeof *r);
    if (!r) return NULL;
    r->items = calloc(cap, sizeof *r->items);
    if (!r->items) {
        free(r);
        return NULL;
    }
    r->cap = cap;
    r->head = 0;
    r->len = 0;
    r->pushed = 0;
    return r;
}

void ring_free(Ring *r) {
    if (!r) return;
    free(r->items);
    free(r);
}

void ring_push(Ring *r, int64_t value) {
    if (r->len == r->cap) {
        int64_t oldest = r->items[r->head];
        r->head = (r->head + 1) % r->cap;
        r->len--;
        EVICTIONS++;           /* a vole static */
        on_evict(oldest);      /* a vole function */
    }
    r->items[(r->head + r->len) % r->cap] = value;
    r->len++;
    r->pushed++;
}

int64_t ring_get(const Ring *r, size_t i) {
    return r->items[(r->head + i) % r->cap];
}

size_t ring_each(const Ring *r, ring_visit visit, void *ctx) {
    size_t i = 0;
    while (i < r->len) {
        int stop = visit(ring_get(r, i), ctx);
        i++;
        if (stop) break;
    }
    return i;
}

uint32_t fnv1a(const uint8_t *data, size_t n) {
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < n; i++) {
        h ^= data[i];
        h *= 16777619u;
    }
    return h;
}
