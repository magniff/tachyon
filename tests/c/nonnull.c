#include <stddef.h>
#include "nonnull.h"

long cell_sum(const struct cell *first) {
    long sum = 0;
    for (const struct cell *c = first; c != NULL; c = c->next) {
        sum += c->value;
    }
    return sum;
}

char *name_or_null(int which) {
    return which ? "named" : NULL;
}

void *cell_self(struct cell *c) {
    return c;
}

// Option<NonNull<T>> passes as a nullable pointer.
long count_nonnull(void *a, void *b) {
    return (a != NULL) + (b != NULL);
}

void *pass_through(void *p) {
    return p;
}
