#include <stdio.h>
#include <stdlib.h>
typedef struct Node { struct Node *left, *right; } Node;
static Node *make(long depth) {
    Node *n = malloc(sizeof(Node));
    if (depth > 0) {
        Node *l = make(depth - 1);
        Node *r = make(depth - 1);
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
static void release(Node *n) {
    if (n->left != NULL) { release(n->left); release(n->right); }
    free(n);
}
int main(void) {
    long min_depth = 4, max_depth = 16, stretch = max_depth + 1;
    Node *t = make(stretch);
    printf("stretch tree of depth %ld\t check: %ld\n", stretch, check(t));
    release(t);
    Node *long_lived = make(max_depth);
    for (long depth = min_depth; depth <= max_depth; depth += 2) {
        long iterations = 1L << (max_depth - depth + min_depth);
        long sum = 0;
        for (long i = 0; i < iterations; i++) {
            Node *t = make(depth);
            sum += check(t);
            release(t);
        }
        printf("%ld\t trees of depth %ld\t check: %ld\n", iterations, depth, sum);
    }
    printf("long lived tree of depth %ld\t check: %ld\n", max_depth, check(long_lived));
    release(long_lived);
    return 0;
}
