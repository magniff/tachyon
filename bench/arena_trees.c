#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
/* arena_trees: binarytrees with its nodes in arenas (bench/arena_trees.tach). */
typedef struct { char *base; long used, limit, total; } Arena;
typedef struct Node { struct Node *left, *right; } Node;
#define CHUNK (1L << 20)
__attribute__((noinline, cold)) static void *refill(Arena *s, long size, long align) {
    long need = size + align + 8;
    long bytes = need > CHUNK ? need : CHUNK;
    char *chunk = malloc(bytes);
    if (!chunk) return chunk;
    *(char **)chunk = s->base;
    s->base = chunk;
    s->limit = bytes;
    s->total += bytes;
    long at = ((((intptr_t)chunk) + 8 + align - 1) & -align) - (intptr_t)chunk;
    s->used = at + size;
    return chunk + at;
}
static inline void *arena_alloc(Arena *s, long size, long align) {
    long at = (s->used + align - 1) & -align;
    if (at + size <= s->limit) { s->used = at + size; return s->base + at; }
    void *p = refill(s, size, align);
    if (!p) abort();
    return p;
}
static void arena_free(Arena *s) {
    char *c = s->base;
    while (c) { char *next = *(char **)c; free(c); c = next; }
    s->base = NULL; s->used = s->limit = s->total = 0;
}
static void arena_reset(Arena *s) {
    if (!s->base) return;
    if (*(char **)s->base) {
        long total = s->total;
        arena_free(s);
        char *chunk = malloc(total);
        *(char **)chunk = NULL;
        s->base = chunk; s->limit = total; s->total = total;
    }
    s->used = 8;
}
static Node *make(Arena *a, long depth) {
    Node *n = arena_alloc(a, sizeof(Node), 8);
    if (depth > 0) {
        Node *l = make(a, depth - 1);
        Node *r = make(a, depth - 1);
        n->left = l;
        n->right = r;
    } else {
        n->left = NULL;
        n->right = NULL;
    }
    return n;
}
static long check(Node *n) {
    if (n->left == NULL) return 1;
    return 1 + check(n->left) + check(n->right);
}
int main(void) {
    long min_depth = 4, max_depth = 16, stretch = max_depth + 1;
    Arena a = {0}, long_arena = {0};
    Node *t = make(&a, stretch);
    printf("stretch tree of depth %ld\t check: %ld\n", stretch, check(t));
    arena_reset(&a);
    Node *long_lived = make(&long_arena, max_depth);
    for (long depth = min_depth; depth <= max_depth; depth += 2) {
        long iterations = 1L << (max_depth - depth + min_depth);
        long sum = 0;
        for (long i = 0; i < iterations; i++) {
            Node *t = make(&a, depth);
            sum += check(t);
            arena_reset(&a);
        }
        printf("%ld\t trees of depth %ld\t check: %ld\n", iterations, depth, sum);
    }
    printf("long lived tree of depth %ld\t check: %ld\n", max_depth, check(long_lived));
    arena_free(&a);
    arena_free(&long_arena);
    return 0;
}
