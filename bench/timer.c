/* Runs a command several times and prints the fastest wall-clock time in
 * milliseconds: timer RUNS INPUT OUTPUT command [args...]
 * (stdin from INPUT, stdout to OUTPUT; the last run's output is kept). */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/wait.h>

static double now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

int main(int argc, char **argv) {
    if (argc < 5) {
        fprintf(stderr, "usage: timer RUNS INPUT OUTPUT command [args...]\n");
        return 2;
    }
    int runs = atoi(argv[1]);
    double best = -1;
    for (int r = 0; r < runs; r++) {
        double start = now_ms();
        pid_t pid = fork();
        if (pid == 0) {
            int in = open(argv[2], O_RDONLY);
            int out = open(argv[3], O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (in < 0 || out < 0) _exit(127);
            dup2(in, 0);
            dup2(out, 1);
            execv(argv[4], argv + 4);
            _exit(127);
        }
        int status;
        waitpid(pid, &status, 0);
        double elapsed = now_ms() - start;
        if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
            fprintf(stderr, "timer: %s failed\n", argv[4]);
            return 1;
        }
        if (best < 0 || elapsed < best) best = elapsed;
    }
    printf("%.0f\n", best);
    return 0;
}
