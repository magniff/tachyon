/* bench/std term_feed, C half: the terminal's inner loop with mbrtowc and
   wcwidth per code point (no graphemes: a code point of width > 0 is a
   cluster). A printable-ASCII run adds its length to cells and clusters;
   a C0 control or DEL adds 1 to controls. */
#include "text_gen.h"
#include <locale.h>
#include <wchar.h>

static uint64_t feed(const unsigned char *s, size_t n) {
    uint64_t cells = 0, clusters = 0, controls = 0;
    mbstate_t st;
    memset(&st, 0, sizeof st);
    size_t i = 0;
    while (i < n) {
        unsigned char b = s[i];
        if (b >= 0x20 && b < 0x7F) {
            size_t j = i + 1;
            while (j < n && s[j] >= 0x20 && s[j] < 0x7F) j++;
            cells += j - i;
            clusters += j - i;
            i = j;
        } else if (b < 0x80) {
            controls++;
            i++;
        } else {
            wchar_t wc;
            size_t k = mbrtowc(&wc, (const char *)s + i, n - i, &st);
            if (k == (size_t)-1 || k == (size_t)-2) { memset(&st, 0, sizeof st); i++; continue; }
            int w = wcwidth(wc);
            if (w > 0) { cells += (uint64_t)w; clusters++; }
            i += k;
        }
    }
    return cells + (clusters << 20) + (controls << 40);
}

int main(void) {
    if (!setlocale(LC_ALL, "en_US.UTF-8")) { fprintf(stderr, "no en_US.UTF-8 locale\n"); return 1; }
    static const int kinds[] = {0, 2, 3};
    tg_run("term_feed", kinds, 3, feed);
    return 0;
}
