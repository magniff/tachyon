/* bench/std width, C half: mbrtowc and wcwidth per code point in the
   en_US.UTF-8 locale (a negative wcwidth counts 0). */
#include "text_gen.h"
#include <locale.h>
#include <wchar.h>

static uint64_t width(const unsigned char *s, size_t n) {
    mbstate_t st;
    memset(&st, 0, sizeof st);
    uint64_t total = 0;
    size_t i = 0;
    while (i < n) {
        wchar_t wc;
        size_t k = mbrtowc(&wc, (const char *)s + i, n - i, &st);
        if (k == (size_t)-1 || k == (size_t)-2) { memset(&st, 0, sizeof st); i++; continue; }
        if (k == 0) k = 1;
        int w = wcwidth(wc);
        if (w > 0) total += (uint64_t)w;
        i += k;
    }
    return total;
}

int main(void) {
    if (!setlocale(LC_ALL, "en_US.UTF-8")) { fprintf(stderr, "no en_US.UTF-8 locale\n"); return 1; }
    static const int kinds[] = {0, 2};
    tg_run("width", kinds, 2, width);
    return 0;
}
