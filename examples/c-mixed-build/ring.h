/* ring.h: a fixed-size ring buffer of int64_t samples, in C, used from
 * tachyon (main.tach imports this header) and calling back into it. */
#ifndef RING_H
#define RING_H

#include <stddef.h>
#include <stdint.h>

/* The ring's fields are public: tachyon sees this struct as a
 * #[repr(C)] struct with the same fields and reads them. */
typedef struct Ring {
    int64_t *items;   /* cap slots */
    size_t cap;
    size_t head;      /* the slot of the oldest sample */
    size_t len;       /* samples held, at most cap */
    uint64_t pushed;  /* samples ever pushed */
} Ring;

/* A new empty ring of `cap` slots (cap > 0), or NULL. */
Ring *ring_new(size_t cap);
void ring_free(Ring *r);

/* Appends `value`. When the ring is full the oldest sample is dropped
 * first, and the program's on_evict (a tachyon function, see main.h) is
 * told about it. */
void ring_push(Ring *r, int64_t value);

/* The i-th sample, oldest first (0 <= i < len). */
int64_t ring_get(const Ring *r, size_t i);

/* Calls visit(value, ctx) on each sample, oldest first, until it returns
 * nonzero; returns the number of samples visited. `ctx` is passed through
 * untouched: the caller's state, whatever it is. */
typedef int (*ring_visit)(int64_t value, void *ctx);
size_t ring_each(const Ring *r, ring_visit visit, void *ctx);

/* FNV-1a, a small fast hash of n bytes. */
uint32_t fnv1a(const uint8_t *data, size_t n);

#endif
