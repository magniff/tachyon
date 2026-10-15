/* The same coder in C, for comparing speed: the same text, tree (ties
 * broken the same way), canonical codes, bit writer and table decoder.
 *
 *     cc -O2 examples/algorithms/huffman/reference.c -o huffman-c && ./huffman-c
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static uint64_t state;

static uint64_t next(void) {
    uint64_t x = state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    state = x;
    return x * 0x2545F4914F6CDD1DULL;
}

static int64_t range(int64_t lo, int64_t hi) {
    return lo + (int64_t)((next() >> 33) % (uint64_t)(hi - lo + 1));
}

static int64_t now_ns(void) {
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    return (int64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}

static const char *WORDS[] = {"the", "of", "and", "to", "a", "in", "is", "that", "it", "was", "for", "on",
                              "with", "as", "his", "they", "be", "at", "one", "have", "this", "from",
                              "huffman", "code"};

int main(void) {
    int64_t size = 4 << 20, n = 0, last = 23;
    uint8_t *text = malloc(size + 64);
    state = 2026 | 1;
    while (n < size) {
        int64_t words = range(3, 12);
        for (int64_t k = 0; k < words; k++) {
            int64_t i = range(0, last), j = range(0, last);
            const char *w = WORDS[i < j ? i : j];
            size_t len = strlen(w);
            if (k == 0) {
                text[n++] = (uint8_t)(w[0] - 32);
                memcpy(text + n, w + 1, len - 1);
                n += len - 1;
            } else {
                text[n++] = ' ';
                memcpy(text + n, w, len);
                n += len;
            }
        }
        memcpy(text + n, range(0, 3) == 0 ? ",\n" : ". ", 2);
        n += 2;
    }
    n = size;

    /* The tree: merge the two lightest live subtrees (by weight, then
     * node number) until one is left; a linear scan, as there are few. */
    int64_t t0 = now_ns();
    int64_t freq[256] = {0}, weight[512], left[512], right[512], lengths[256] = {0};
    int live[512] = {0}, nodes = 256;
    for (int64_t i = 0; i < n; i++) freq[text[i]]++;
    for (int b = 0; b < 256; b++) {
        weight[b] = freq[b];
        left[b] = right[b] = -1;
        live[b] = freq[b] > 0;
    }
    for (;;) {
        int a = -1, b = -1;
        for (int k = 0; k < nodes; k++) {
            if (!live[k]) continue;
            if (a < 0 || weight[k] < weight[a]) { b = a; a = k; }
            else if (b < 0 || weight[k] < weight[b]) b = k;
        }
        if (b < 0) break;
        live[a] = live[b] = 0;
        weight[nodes] = weight[a] + weight[b];
        left[nodes] = a;
        right[nodes] = b;
        live[nodes++] = 1;
    }
    int64_t stack[1024][2], sp = 0, max_len = 0;
    stack[sp][0] = nodes - 1;
    stack[sp++][1] = 0;
    while (sp > 0) {
        sp--;
        int64_t node = stack[sp][0], depth = stack[sp][1];
        if (left[node] < 0) {
            lengths[node] = depth;
        } else {
            stack[sp][0] = left[node], stack[sp++][1] = depth + 1;
            stack[sp][0] = right[node], stack[sp++][1] = depth + 1;
        }
    }
    uint64_t code[256] = {0}, next_code = 0;
    int64_t prev = 0;
    for (int64_t len = 1; len <= 64; len++) {
        for (int b = 0; b < 256; b++) {
            if (lengths[b] != len) continue;
            next_code <<= len - prev;
            code[b] = next_code++;
            prev = len;
            max_len = len;
        }
    }
    int64_t t1 = now_ns();

    uint8_t *out = malloc(n);
    int64_t pos = 0, bits = 0;
    uint64_t acc = 0;
    for (int64_t i = 0; i < n; i++) {
        acc = acc << lengths[text[i]] | code[text[i]];
        bits += lengths[text[i]];
        while (bits >= 8) {
            bits -= 8;
            out[pos++] = (uint8_t)(acc >> bits);
        }
    }
    if (bits > 0) out[pos++] = (uint8_t)(acc << (8 - bits));
    int64_t t2 = now_ns();

    uint32_t *table = calloc((size_t)1 << max_len, sizeof(uint32_t));
    for (int b = 0; b < 256; b++) {
        if (lengths[b] == 0) continue;
        uint64_t first = code[b] << (max_len - lengths[b]);
        for (uint64_t k = first; k < first + ((uint64_t)1 << (max_len - lengths[b])); k++)
            table[k] = (uint32_t)(b | lengths[b] << 8);
    }
    uint8_t *back = malloc(n);
    uint64_t mask = ((uint64_t)1 << max_len) - 1;
    int64_t have = 0, in = 0;
    acc = 0;
    for (int64_t i = 0; i < n; i++) {
        while (have <= 56) {
            acc = acc << 8 | (in < pos ? out[in] : 0);
            in++;
            have += 8;
        }
        uint32_t e = table[(acc >> (have - max_len)) & mask];
        back[i] = (uint8_t)e;
        have -= e >> 8;
    }
    int64_t t3 = now_ns();

    uint64_t h = 0xcbf29ce484222325ULL;
    for (int64_t i = 0; i < pos; i++) h = (h ^ out[i]) * 0x100000001b3ULL;
    printf("encoded: %lld bytes, checksum %llx, %s\n", (long long)pos, (unsigned long long)h,
           memcmp(back, text, n) == 0 ? "decoded == input" : "MISMATCH");
    double mb = n / 1e6;
    fprintf(stderr, "count + tree + codes: %6.2f ms\n", (t1 - t0) / 1e6);
    fprintf(stderr, "encode: %6.2f ms, %5.0f MB/s\n", (t2 - t1) / 1e6, mb * 1e9 / (t2 - t1));
    fprintf(stderr, "decode: %6.2f ms, %5.0f MB/s\n", (t3 - t2) / 1e6, mb * 1e9 / (t3 - t2));
    return 0;
}
