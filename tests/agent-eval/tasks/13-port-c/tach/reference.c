/*
 * lzss: a small LZSS compressor and decompressor.
 *
 * Reads all of stdin. The first line (up to the first '\n', a trailing
 * '\r' removed) is the mode, `compress` or `decompress`; the rest of
 * stdin (everything after that '\n', byte for byte) is the input.
 *
 *   compress:   the input is raw data. Prints a stats line, then the
 *               compressed stream in lowercase hex, 32 bytes per line.
 *   decompress: the input is a stream in hex (whitespace ignored).
 *               Prints a stats line, then the data, byte for byte.
 *
 * Every problem prints one line starting with "error: "; the exit
 * status is always 0.
 *
 * The stream:
 *   bytes 0-1   magic 'L' 'Z'
 *   byte  2     version, 1
 *   bytes 3-6   the data's length, uint32 little-endian
 *   bytes 7-10  the data's CRC-32, uint32 little-endian
 *   then groups of up to 8 tokens, each group led by a flag byte whose
 *   bit i (least significant first) says what token i of the group is:
 *     0: a literal, one byte;
 *     1: a match, two bytes b0 b1: distance - 1 is the 12-bit value
 *        b0 | (b1 >> 4) << 8, length - 3 is b1 & 15. The match copies
 *        `length` bytes starting `distance` bytes back in the output
 *        (the copy may overlap what it is writing).
 *   The last group may be short; its unused flag bits are 0. Decoding
 *   stops when the output has the stored length: any bytes left over
 *   are an error. Empty data has no groups at all.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define WINDOW_SIZE 4096 /* distances 1..4096 */
#define WINDOW_MASK (WINDOW_SIZE - 1)
#define MIN_MATCH 3
#define MAX_MATCH 18
#define HASH_BITS 13
#define HASH_SIZE (1 << HASH_BITS)
#define MAX_CHAIN 64 /* candidates looked at per position */
#define HEADER_SIZE 11

/* ---- growable byte buffer ---- */

typedef struct {
    unsigned char *data;
    size_t len, cap;
} Bytes;

static void bytes_push(Bytes *b, unsigned char c) {
    if (b->len == b->cap) {
        b->cap = b->cap ? b->cap * 2 : 256;
        b->data = realloc(b->data, b->cap);
        if (!b->data) {
            fputs("out of memory\n", stderr);
            exit(1);
        }
    }
    b->data[b->len++] = c;
}

static void put_u32le(Bytes *b, uint32_t v) {
    for (int i = 0; i < 4; i++) {
        bytes_push(b, (unsigned char)(v >> (8 * i)));
    }
}

static uint32_t get_u32le(const unsigned char *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

/* ---- CRC-32 (the zlib one: reflected, polynomial 0xEDB88320) ---- */

static uint32_t crc_table[256];

static void crc_init(void) {
    for (uint32_t n = 0; n < 256; n++) {
        uint32_t c = n;
        for (int k = 0; k < 8; k++) {
            c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        }
        crc_table[n] = c;
    }
}

static uint32_t crc32(const unsigned char *p, size_t n) {
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; i++) {
        c = crc_table[(c ^ p[i]) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFFu;
}

/* ---- the match finder: hash chains over the last WINDOW_SIZE positions ---- */

static int head[HASH_SIZE];   /* newest position with this hash, or -1 */
static int prev[WINDOW_SIZE]; /* prev[p & WINDOW_MASK]: the position before p in p's chain */

/* The hash of the 3 bytes at p: a multiplicative hash, 32-bit wrapping. */
static unsigned hash3(const unsigned char *p) {
    uint32_t v = ((uint32_t)p[0] << 16) | ((uint32_t)p[1] << 8) | p[2];
    return (uint32_t)(v * 2654435761u) >> (32 - HASH_BITS);
}

/* Adds position pos to its chain; positions with fewer than MIN_MATCH
 * bytes left are not added. */
static void insert(const unsigned char *data, size_t n, size_t pos) {
    if (pos + MIN_MATCH > n) {
        return;
    }
    unsigned h = hash3(data + pos);
    prev[pos & WINDOW_MASK] = head[h];
    head[h] = (int)pos;
}

/* The longest match for the bytes at pos among the chain's candidates,
 * newest first, at most MAX_CHAIN of them and none more than WINDOW_SIZE
 * back. A candidate replaces the best so far only when strictly longer,
 * so among equally long matches the nearest wins. Sets *dist (0 when no
 * match of MIN_MATCH bytes) and returns the length (0 likewise). */
static int find_match(const unsigned char *data, size_t n, size_t pos, int *dist) {
    *dist = 0;
    if (pos + MIN_MATCH > n) {
        return 0;
    }
    int max = MAX_MATCH;
    if (n - pos < (size_t)max) {
        max = (int)(n - pos);
    }
    int best = 0;
    int cand = head[hash3(data + pos)];
    for (int chain = 0; cand >= 0 && chain < MAX_CHAIN; chain++) {
        size_t d = pos - (size_t)cand;
        if (d > WINDOW_SIZE) {
            break;
        }
        int len = 0;
        while (len < max && data[cand + len] == data[pos + len]) {
            len++;
        }
        if (len > best) {
            best = len;
            *dist = (int)d;
            if (len == max) {
                break;
            }
        }
        cand = prev[cand & WINDOW_MASK];
    }
    if (best < MIN_MATCH) {
        *dist = 0;
        return 0;
    }
    return best;
}

/* ---- compress ---- */

typedef struct {
    Bytes out;
    size_t flag_at; /* index of the current group's flag byte */
    int nbits;      /* tokens in the current group so far */
    size_t literals, matches;
} Writer;

static void start_token(Writer *w, int is_match) {
    if (w->nbits == 8 || w->out.len == HEADER_SIZE) {
        w->flag_at = w->out.len;
        bytes_push(&w->out, 0);
        w->nbits = 0;
    }
    if (is_match) {
        w->out.data[w->flag_at] |= (unsigned char)(1u << w->nbits);
    }
    w->nbits++;
}

static void emit_literal(Writer *w, unsigned char c) {
    start_token(w, 0);
    bytes_push(&w->out, c);
    w->literals++;
}

static void emit_match(Writer *w, int dist, int len) {
    unsigned d = (unsigned)(dist - 1);
    start_token(w, 1);
    bytes_push(&w->out, (unsigned char)(d & 0xFF));
    bytes_push(&w->out, (unsigned char)(((d >> 8) << 4) | (unsigned)(len - MIN_MATCH)));
    w->matches++;
}

/* Greedy parsing with one step of lazy evaluation: before taking a match
 * at pos, look at pos + 1; if the match there is strictly longer, emit
 * the byte at pos as a literal and decide again at pos + 1. */
static void compress(const unsigned char *data, size_t n) {
    Writer w;
    memset(&w, 0, sizeof w);
    for (int i = 0; i < HASH_SIZE; i++) {
        head[i] = -1;
    }
    bytes_push(&w.out, 'L');
    bytes_push(&w.out, 'Z');
    bytes_push(&w.out, 1);
    put_u32le(&w.out, (uint32_t)n);
    put_u32le(&w.out, crc32(data, n));

    size_t inserted = 0; /* positions below this are in the chains */
    size_t pos = 0;
    while (pos < n) {
        while (inserted < pos) {
            insert(data, n, inserted++);
        }
        int dist, len = find_match(data, n, pos, &dist);
        if (len > 0 && pos + 1 < n) {
            while (inserted < pos + 1) {
                insert(data, n, inserted++);
            }
            int dist2, len2 = find_match(data, n, pos + 1, &dist2);
            if (len2 > len) {
                emit_literal(&w, data[pos]);
                pos++;
                continue;
            }
        }
        if (len > 0) {
            emit_match(&w, dist, len);
            pos += (size_t)len;
        } else {
            emit_literal(&w, data[pos]);
            pos++;
        }
    }

    printf("compressed %zu -> %zu bytes (%zu literals, %zu matches), crc32 %08x\n",
           n, w.out.len, w.literals, w.matches, (unsigned)crc32(data, n));
    static const char digits[] = "0123456789abcdef";
    for (size_t i = 0; i < w.out.len; i++) {
        unsigned char c = w.out.data[i];
        putchar(digits[c >> 4]);
        putchar(digits[c & 15]);
        if (i % 32 == 31 || i + 1 == w.out.len) {
            putchar('\n');
        }
    }
    free(w.out.data);
}

/* ---- decompress ---- */

static int hex_value(int c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* Hex text to bytes; whitespace (space, tab, CR, LF) is skipped. Returns
 * 0, or prints the error and returns -1. */
static int unhex(const unsigned char *text, size_t n, Bytes *out) {
    int high = -1;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = text[i];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            continue;
        }
        int v = hex_value(c);
        if (v < 0) {
            printf("error: bad hex character at offset %zu\n", i);
            return -1;
        }
        if (high < 0) {
            high = v;
        } else {
            bytes_push(out, (unsigned char)(high << 4 | v));
            high = -1;
        }
    }
    if (high >= 0) {
        printf("error: odd number of hex digits\n");
        return -1;
    }
    return 0;
}

static void decompress(const unsigned char *text, size_t text_len) {
    Bytes in = {0}, out = {0};
    if (unhex(text, text_len, &in) < 0) {
        goto done;
    }
    const unsigned char *s = in.data;
    size_t n = in.len;
    if (n < HEADER_SIZE) {
        printf("error: truncated header\n");
        goto done;
    }
    if (s[0] != 'L' || s[1] != 'Z' || s[2] != 1) {
        printf("error: bad magic\n");
        goto done;
    }
    uint32_t size = get_u32le(s + 3);
    uint32_t stored_crc = get_u32le(s + 7);

    size_t p = HEADER_SIZE;
    unsigned flags = 0;
    int nbits = 0;
    while (out.len < size) {
        if (nbits == 0) {
            if (p >= n) {
                printf("error: truncated stream at byte %zu\n", p);
                goto done;
            }
            flags = s[p++];
            nbits = 8;
        }
        int is_match = flags & 1;
        flags >>= 1;
        nbits--;
        if (!is_match) {
            if (p >= n) {
                printf("error: truncated stream at byte %zu\n", p);
                goto done;
            }
            bytes_push(&out, s[p++]);
            continue;
        }
        if (p + 2 > n) {
            printf("error: truncated stream at byte %zu\n", p);
            goto done;
        }
        unsigned dist = ((unsigned)s[p] | (unsigned)(s[p + 1] >> 4) << 8) + 1;
        unsigned len = (unsigned)(s[p + 1] & 15) + MIN_MATCH;
        if (dist > out.len) {
            printf("error: bad distance %u at byte %zu\n", dist, p);
            goto done;
        }
        if (out.len + len > size) {
            printf("error: match overruns the data at byte %zu\n", p);
            goto done;
        }
        p += 2;
        for (unsigned k = 0; k < len; k++) {
            bytes_push(&out, out.data[out.len - dist]);
        }
    }
    if (p < n) {
        printf("error: %zu trailing bytes\n", n - p);
        goto done;
    }
    uint32_t crc = crc32(out.data, out.len);
    if (crc != stored_crc) {
        printf("error: crc mismatch: stored %08x, computed %08x\n",
               (unsigned)stored_crc, (unsigned)crc);
        goto done;
    }
    printf("decompressed %zu -> %zu bytes, crc32 %08x\n", n, out.len, (unsigned)crc);
    fwrite(out.data, 1, out.len, stdout);
done:
    free(in.data);
    free(out.data);
}

/* ---- main ---- */

int main(void) {
    Bytes input = {0};
    int ch;
    while ((ch = getchar()) != EOF) {
        bytes_push(&input, (unsigned char)ch);
    }
    size_t nl = 0;
    while (nl < input.len && input.data[nl] != '\n') {
        nl++;
    }
    size_t mode_len = nl;
    if (mode_len > 0 && input.data[mode_len - 1] == '\r') {
        mode_len--;
    }
    size_t rest = nl < input.len ? nl + 1 : input.len;
    const unsigned char *body = input.data + rest;
    size_t body_len = input.len - rest;

    crc_init();
    if (mode_len == 8 && memcmp(input.data, "compress", 8) == 0) {
        compress(body, body_len);
    } else if (mode_len == 10 && memcmp(input.data, "decompress", 10) == 0) {
        decompress(body, body_len);
    } else {
        printf("error: unknown mode\n");
    }
    free(input.data);
    return 0;
}
