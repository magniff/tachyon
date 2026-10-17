/* (0.19 T3) A C program calling tachyon code that has no main
   (tests/run/arch_detect_lib.tach): its detects fill std's word at the
   first one. */
#include <stdio.h>

unsigned crc_checked(void);
int words_agree(void);
int twice(int x);

int main(void) {
    printf("crc %u, agree %d, twice %d\n", crc_checked(), words_agree(), twice(21));
    return 0;
}
