// bench/std: read a 256 MB file of text lines (made by read_lines.vl
// --make) with getline into one buffer. Prints what read_lines.vl
// prints.
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    FILE *f = fopen(argv[argc - 1], "r");
    if (!f) return 1;
    char *line = NULL;
    size_t cap = 0;
    long long lines = 0, bytes = 0, first = 0;
    ssize_t n;
    while ((n = getline(&line, &cap, f)) > 0) {
        lines++;
        bytes += n;
        first += (unsigned char)line[0];
    }
    printf("%lld %lld %lld\n", lines, bytes, first);
    free(line);
    fclose(f);
    return 0;
}
