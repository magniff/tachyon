/* btree_u64 (0.20): 1M inserts of random u64 keys, 1M lookups (half of
 * them hits), and 1000 range scans of about 1000 pairs each, in a
 * hand-written B-tree of Rust's shape (11 pairs a node, parent links,
 * linear search in a node, splits at Rust's split points); no removal,
 * which this benchmark does not do. */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <stddef.h>

#define CAP 11

typedef struct Node {
    struct Node *parent;
    int parent_idx, len;
    uint64_t keys[CAP], vals[CAP];
    struct Node *edges[CAP + 1]; /* internal nodes only */
} Node;

typedef struct { Node *root; int height; long len; } Tree;

static Node *node_new(int internal) {
    Node *n = malloc(internal ? sizeof(Node) : offsetof(Node, edges));
    n->parent = 0;
    n->parent_idx = 0;
    n->len = 0;
    return n;
}

static void set_edge(Node *n, int i, Node *c) { n->edges[i] = c; c->parent = n; c->parent_idx = i; }

static void insert_fit(Node *n, int at, uint64_t k, uint64_t v, Node *right) {
    for (int j = n->len; j > at; j--) { n->keys[j] = n->keys[j - 1]; n->vals[j] = n->vals[j - 1]; }
    if (right) {
        for (int j = n->len + 1; j > at + 1; j--) set_edge(n, j, n->edges[j - 1]);
        set_edge(n, at + 1, right);
    }
    n->keys[at] = k;
    n->vals[at] = v;
    n->len++;
}

static void splitpoint(int at, int *mid, int *place) {
    if (at < 5) { *mid = 4; *place = -1; }
    else if (at == 5) { *mid = 5; *place = -1; }
    else if (at == 6) { *mid = 5; *place = 0; }
    else { *mid = 6; *place = at - 7; }
}

/* Inserts (k, v), and child `right` after edge `at` when internal. */
static void insert_rec(Tree *t, Node *n, int h, int at, uint64_t k, uint64_t v, Node *right) {
    for (;;) {
        if (n->len < CAP) { insert_fit(n, at, k, v, right); return; }
        int mid, place;
        splitpoint(at, &mid, &place);
        Node *r = node_new(h > 0);
        int rl = n->len - mid - 1;
        for (int j = 0; j < rl; j++) { r->keys[j] = n->keys[mid + 1 + j]; r->vals[j] = n->vals[mid + 1 + j]; }
        if (h > 0) for (int j = 0; j <= rl; j++) set_edge(r, j, n->edges[mid + 1 + j]);
        r->len = rl;
        n->len = mid;
        uint64_t mk = n->keys[mid], mv = n->vals[mid];
        if (place < 0) insert_fit(n, at, k, v, right); else insert_fit(r, place, k, v, right);
        Node *p = n->parent;
        if (!p) {
            Node *root = node_new(1);
            root->keys[0] = mk;
            root->vals[0] = mv;
            root->len = 1;
            set_edge(root, 0, n);
            set_edge(root, 1, r);
            t->root = root;
            t->height = h + 1;
            return;
        }
        at = n->parent_idx;
        n = p;
        h++;
        k = mk;
        v = mv;
        right = r;
    }
}

static void insert(Tree *t, uint64_t k, uint64_t v) {
    if (!t->root) { t->root = node_new(0); t->height = 0; }
    Node *n = t->root;
    int h = t->height;
    for (;;) {
        int i = 0;
        while (i < n->len && k > n->keys[i]) i++;
        if (i < n->len && k == n->keys[i]) { n->vals[i] = v; return; }
        if (h == 0) { insert_rec(t, n, 0, i, k, v, 0); t->len++; return; }
        n = n->edges[i];
        h--;
    }
}

static uint64_t *get(Tree *t, uint64_t k) {
    Node *n = t->root;
    int h = t->height;
    for (;;) {
        int i = 0;
        while (i < n->len && k > n->keys[i]) i++;
        if (i < n->len && k == n->keys[i]) return &n->vals[i];
        if (h == 0) return 0;
        n = n->edges[i];
        h--;
    }
}

/* The leaf edge before the first key >= b. */
static void lower_edge(Tree *t, uint64_t b, Node **node, int *idx) {
    Node *n = t->root;
    int h = t->height;
    for (;;) {
        int i = 0;
        while (i < n->len && b > n->keys[i]) i++;
        if (h == 0) { *node = n; *idx = i; return; }
        n = n->edges[i];
        h--;
    }
}

static void range_sum(Tree *t, uint64_t lo, uint64_t hi, long *count, uint64_t *sum) {
    Node *f, *b;
    int fi, bi;
    lower_edge(t, lo, &f, &fi);
    lower_edge(t, hi, &b, &bi);
    int h = 0;
    while (!(f == b && fi == bi)) {
        /* the pair after edge (f, fi): up while at a node's end */
        while (fi >= f->len) { fi = f->parent_idx; f = f->parent; h++; }
        (*count)++;
        *sum += f->vals[fi];
        /* the leaf edge after it */
        if (h == 0) fi++;
        else {
            f = f->edges[fi + 1];
            while (--h > 0) f = f->edges[0];
            f = h == 0 && f->len >= 0 ? f : f;
            fi = 0;
        }
    }
}

static uint64_t xorshift(uint64_t *x) {
    uint64_t v = *x;
    v ^= v << 13;
    v ^= v >> 7;
    v ^= v << 17;
    *x = v;
    return v;
}

int main(void) {
    long n = 1000000, hits = 0, scanned = 0;
    Tree t = {0, 0, 0};
    uint64_t x = 0x9e3779b97f4a7c15ull, y = x, sum = 0, ssum = 0;
    for (long i = 0; i < n; i++) insert(&t, xorshift(&x), (uint64_t)i);
    for (long i = 0; i < n; i++) {
        uint64_t k = i % 2 == 0 ? xorshift(&y) : xorshift(&x);
        uint64_t *v = get(&t, k);
        if (v) { sum += *v; hits++; }
    }
    for (int r = 0; r < 1000; r++) {
        uint64_t lo = xorshift(&x) >> 1;
        range_sum(&t, lo, lo + (1ull << 54), &scanned, &ssum);
    }
    printf("%ld %ld %llu %ld %llu\n", t.len, hits, (unsigned long long)sum, scanned, (unsigned long long)ssum);
    return 0;
}
