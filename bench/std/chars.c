/* bench/std chars, C half: a decode loop by hand (valid input): the count
   of code points plus their sum. */
#include "text_gen.h"

static uint64_t chars(const unsigned char *s, size_t n) {
    uint64_t count = 0, total = 0;
    size_t i = 0;
    while (i < n) {
        uint32_t b = s[i], c;
        if (b < 0x80) { c = b; i += 1; }
        else if (b < 0xE0) { c = ((b & 0x1F) << 6) | (s[i + 1] & 0x3F); i += 2; }
        else if (b < 0xF0) { c = ((b & 0x0F) << 12) | ((s[i + 1] & 0x3F) << 6) | (s[i + 2] & 0x3F); i += 3; }
        else { c = ((b & 0x07) << 18) | ((s[i + 1] & 0x3F) << 12) | ((s[i + 2] & 0x3F) << 6) | (s[i + 3] & 0x3F); i += 4; }
        count++;
        total += c;
    }
    return count + total;
}

int main(void) {
    static const int kinds[] = {0, 4};
    tg_run("chars", kinds, 2, chars);
    return 0;
}
