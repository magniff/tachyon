// errno is a C macro (a function call on every system, by another name
// on each), which vole's C import does not give: this reads it.
#include <errno.h>

int sha256sum_errno(void) { return errno; }
