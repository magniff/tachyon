/* bench/std spawn (0.20): 1000 times, posix_spawn /usr/bin/true with the
 * environment inherited and waitpid, then the number that exited 0 (as
 * spawn.vl). */
#include <spawn.h>
#include <stdio.h>
#include <sys/wait.h>

extern char **environ;

int main(void) {
    char *argv[] = { "/usr/bin/true", NULL };
    int ok = 0;
    for (int i = 0; i < 1000; i++) {
        pid_t pid;
        if (posix_spawn(&pid, argv[0], NULL, NULL, argv, environ) != 0) return 1;
        int status;
        if (waitpid(pid, &status, 0) < 0) return 1;
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) ok++;
    }
    printf("%d\n", ok);
    return 0;
}
