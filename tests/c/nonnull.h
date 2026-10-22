// 0.18: clang's nullability qualifiers, as tests/run/nonnull_cimport.vl
// imports them: `_Nonnull` pointers are std::NonNull, the others *T.
#ifndef __clang__
#define _Nonnull
#define _Nullable
#endif

struct cell { long value; struct cell *_Nullable next; };

long cell_sum(const struct cell *_Nonnull first);
char *_Nullable name_or_null(int which);
void *_Nonnull cell_self(struct cell *_Nonnull c);
