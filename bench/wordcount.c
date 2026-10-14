#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
/* An open-addressing map (linear probing) from words to counts, with
 * std::HashMap's get, insert and growth. */
typedef struct { const unsigned char *ptr; long len; } Word;
typedef struct { Word *keys; long *values; unsigned char *states; long cap, len, used; } Map;
enum { FREE = 0, FULL = 1 };
static uint64_t hash(Word w) {
    uint64_t h = 14695981039346656037ULL;
    for (long i = 0; i < w.len; i++) h = (h ^ w.ptr[i]) * 1099511628211ULL;
    return h;
}
static int eq(Word a, Word b) {
    if (a.len != b.len) return 0;
    for (long i = 0; i < a.len; i++) if (a.ptr[i] != b.ptr[i]) return 0;
    return 1;
}
static int less(Word a, Word b) {
    long n = a.len < b.len ? a.len : b.len;
    for (long i = 0; i < n; i++) if (a.ptr[i] != b.ptr[i]) return a.ptr[i] < b.ptr[i];
    return a.len < b.len;
}
static long slot_of(Map *m, Word key) {
    if (m->cap == 0) return -1;
    long mask = m->cap - 1;
    long i = (long)(hash(key) & (uint64_t)mask);
    for (;;) {
        if (m->states[i] == FREE) return -1;
        if (m->states[i] == FULL && eq(m->keys[i], key)) return i;
        i = (i + 1) & mask;
    }
}
static int get(Map *m, Word key, long *value) {
    long i = slot_of(m, key);
    if (i < 0) return 0;
    *value = m->values[i];
    return 1;
}
static void rehash(Map *m) {
    long old_cap = m->cap;
    Word *old_keys = m->keys;
    long *old_values = m->values;
    unsigned char *old_states = m->states;
    long cap = old_cap == 0 ? 8 : old_cap * 2;
    while (m->len * 2 > cap) cap *= 2;
    m->keys = malloc(cap * sizeof(Word));
    m->values = malloc(cap * sizeof(long));
    m->states = malloc(cap);
    for (long i = 0; i < cap; i++) m->states[i] = FREE;
    m->cap = cap;
    m->used = m->len;
    long mask = cap - 1;
    for (long i = 0; i < old_cap; i++) {
        if (old_states[i] != FULL) continue;
        long j = (long)(hash(old_keys[i]) & (uint64_t)mask);
        while (m->states[j] == FULL) j = (j + 1) & mask;
        m->states[j] = FULL;
        m->keys[j] = old_keys[i];
        m->values[j] = old_values[i];
    }
    if (old_cap > 0) { free(old_keys); free(old_values); free(old_states); }
}
static void insert(Map *m, Word key, long value) {
    long i = slot_of(m, key);
    if (i >= 0) { m->values[i] = value; return; }
    if ((m->used + 1) * 4 > m->cap * 3) rehash(m);
    long mask = m->cap - 1;
    long j = (long)(hash(key) & (uint64_t)mask);
    while (m->states[j] == FULL) j = (j + 1) & mask;
    if (m->states[j] == FREE) m->used++;
    m->states[j] = FULL;
    m->keys[j] = key;
    m->values[j] = value;
    m->len++;
}
static uint64_t next(uint64_t *state) {
    *state = *state * 6364136223846793005ULL + 1442695040888963407ULL;
    return *state >> 33;
}
static int is_letter(unsigned char c) { return c >= 'a' && c <= 'z'; }
int main(void) {
    long cap = 16, n = 0;
    unsigned char *text = malloc(cap);
    uint64_t state = 7;
    long words = 3000000;
    for (long w = 0; w < words; w++) {
        uint64_t a = next(&state) % 4096;
        uint64_t b = next(&state) % 4096;
        uint64_t id = a * b / 64;
        for (;;) {
            if (n == cap) { cap *= 2; text = realloc(text, cap); }
            text[n++] = 'a' + id % 26;
            id = id / 26;
            if (id == 0) break;
        }
        if (n == cap) { cap *= 2; text = realloc(text, cap); }
        text[n++] = w % 12 == 11 ? '\n' : ' ';
    }
    Map counts = {0};
    long total = 0, i = 0;
    while (i < n) {
        while (i < n && !is_letter(text[i])) i++;
        long start = i;
        while (i < n && is_letter(text[i])) i++;
        if (i > start) {
            Word w = { text + start, i - start };
            long c = 0;
            get(&counts, w, &c);
            insert(&counts, w, c + 1);
            total++;
        }
    }
    Word best = { (const unsigned char *)"", 0 };
    long best_count = 0;
    uint64_t checksum = 0;
    for (long slot = 0; slot < counts.cap; slot++) {
        if (counts.states[slot] != FULL) continue;
        Word w = counts.keys[slot];
        long c = 0;
        get(&counts, w, &c);
        checksum += (uint64_t)c * hash(w);
        if (c > best_count || (c == best_count && less(w, best))) { best = w; best_count = c; }
    }
    printf("%ld words, %ld distinct, checksum %lu\n", total, counts.len, (unsigned long)checksum);
    printf("most frequent: %.*s (%ld)\n", (int)best.len, best.ptr, best_count);
    free(counts.keys); free(counts.values); free(counts.states);
    free(text);
    return 0;
}
