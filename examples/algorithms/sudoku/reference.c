/* The timed part of the example in C, for comparing speed: the same
 * puzzles, generator, disguises, search and checksum (it prints the same
 * line). Popcount is the compiler's builtin, a single instruction.
 *
 *     cc -O2 examples/algorithms/sudoku/reference.c -o sudoku-c && ./sudoku-c
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

typedef struct { uint8_t cells[81]; uint64_t rows[9], cols[9], boxes[9]; } Sudoku;
typedef struct { Sudoku grid, first; int64_t found, limit, nodes; } Search;

static int box_of(int i) { return (i / 27) * 3 + (i % 9) / 3; }

static uint64_t candidates(const Sudoku *s, int i) {
    return 0x1ff & ~(s->rows[i / 9] | s->cols[i % 9] | s->boxes[box_of(i)]);
}

static void place(Sudoku *s, int i, int d) {
    uint64_t bit = 1ull << (d - 1);
    s->cells[i] = (uint8_t)d;
    s->rows[i / 9] |= bit;
    s->cols[i % 9] |= bit;
    s->boxes[box_of(i)] |= bit;
}

static void clear(Sudoku *s, int i) {
    uint64_t bit = ~(1ull << (s->cells[i] - 1));
    s->cells[i] = 0;
    s->rows[i / 9] &= bit;
    s->cols[i % 9] &= bit;
    s->boxes[box_of(i)] &= bit;
}

static void fill(Search *s) {
    s->nodes++;
    int best = -1, best_count = 10;
    uint64_t best_mask = 0;
    for (int i = 0; i < 81; i++) {
        if (s->grid.cells[i]) continue;
        uint64_t m = candidates(&s->grid, i);
        int n = __builtin_popcountll(m);
        if (n < best_count) {
            best = i;
            best_count = n;
            best_mask = m;
            if (n <= 1) break;
        }
    }
    if (best == -1) {
        if (s->found == 0) s->first = s->grid;
        s->found++;
        return;
    }
    for (uint64_t m = best_mask; m && s->found < s->limit;) {
        uint64_t bit = m & (0 - m);
        m ^= bit;
        place(&s->grid, best, __builtin_popcountll(bit - 1) + 1);
        fill(s);
        clear(&s->grid, best);
    }
}

static uint64_t state = 2026;

static uint64_t next(void) {
    uint64_t x = state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    state = x;
    return x * 0x2545F4914F6CDD1DULL;
}

static void shuffle(int64_t *p, int n) {
    for (int i = 0; i < n; i++) p[i] = i;
    for (int i = 1; i < n; i++) {
        int64_t j = (int64_t)((next() >> 33) % (uint64_t)(i + 1)), t = p[i];
        p[i] = p[j];
        p[j] = t;
    }
}

static Sudoku disguise(const Sudoku *p) {
    int64_t digits[9], row_of[9], col_of[9], *maps[2] = {row_of, col_of};
    shuffle(digits, 9);
    for (int k = 0; k < 2; k++) {
        int64_t bands[3];
        shuffle(bands, 3);
        for (int b = 0; b < 3; b++) {
            int64_t inner[3];
            shuffle(inner, 3);
            for (int j = 0; j < 3; j++) maps[k][b * 3 + j] = bands[b] * 3 + inner[j];
        }
    }
    Sudoku out;
    memset(&out, 0, sizeof out);
    for (int r = 0; r < 9; r++)
        for (int c = 0; c < 9; c++) {
            int d = p->cells[row_of[r] * 9 + col_of[c]];
            if (d) place(&out, r * 9 + c, (int)digits[d - 1] + 1);
        }
    return out;
}

static const char *PUZZLES[7] = {
    "8..........36......7..9.2...5...7.......457.....1...3...1....68..85...1..9....4..",
    "4.....8.5.3..........7......2.....6.....8.4......1.......6.3.7.5..2.....1.4......",
    "52...6.........7.13...........4..8..6......5...........418.........3..2...87.....",
    "6.....8.3.4.7.................5.4.7.3..2.....1.6.......2.....5.....8.6......1....",
    "48.3............71.2.......7.5....6....2..8.............1.76...3.....4......5....",
    "....14....3....2...7..........9...3.6.1.............8.2.....1.4....5.6.....7.8...",
    "53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79",
};

int main(void) {
    Sudoku puzzles[7];
    for (int k = 0; k < 7; k++) {
        memset(&puzzles[k], 0, sizeof(Sudoku));
        for (int i = 0; i < 81; i++)
            if (PUZZLES[k][i] != '.') place(&puzzles[k], i, PUZZLES[k][i] - '0');
    }
    int count = 70;
    uint64_t checksum = 0;
    int64_t nodes = 0;
    struct timespec t0, t1;
    timespec_get(&t0, TIME_UTC);
    for (int k = 0; k < count; k++) {
        Search s;
        s.grid = disguise(&puzzles[k % 7]);
        s.found = 0;
        s.limit = 1;
        s.nodes = 0;
        fill(&s);
        nodes += s.nodes;
        for (int i = 0; i < 81; i++) checksum = checksum * 31 + s.first.cells[i];
    }
    timespec_get(&t1, TIME_UTC);
    printf("%d disguised puzzles: %lld nodes, checksum %llx\n", count, (long long)nodes,
           (unsigned long long)checksum);
    fprintf(stderr, "sudoku: %d puzzles in %lld ms\n", count,
            (long long)((t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000));
    return 0;
}
