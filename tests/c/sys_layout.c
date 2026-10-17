/* The C side of tests/run/sys_layout.tach (0.20): the layouts and constants
 * std's OS layer (compiler/std/sys/) writes by hand, from the system's
 * headers, by name. */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stddef.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define K(name, value) if (strcmp(key, name) == 0) return (long)(value)

long sys_layout_c(const char *key) {
    K("sizeof stat", sizeof(struct stat));
    K("stat.st_dev", offsetof(struct stat, st_dev));
    K("stat.st_ino", offsetof(struct stat, st_ino));
    K("stat.st_mode", offsetof(struct stat, st_mode));
    K("stat.st_nlink", offsetof(struct stat, st_nlink));
    K("stat.st_uid", offsetof(struct stat, st_uid));
    K("stat.st_gid", offsetof(struct stat, st_gid));
    K("stat.st_rdev", offsetof(struct stat, st_rdev));
    K("stat.st_size", offsetof(struct stat, st_size));
    K("stat.st_blocks", offsetof(struct stat, st_blocks));
    K("stat.st_blksize", offsetof(struct stat, st_blksize));
#ifdef __APPLE__
    K("stat.st_atime", offsetof(struct stat, st_atimespec));
    K("stat.st_mtime", offsetof(struct stat, st_mtimespec));
    K("stat.st_ctime", offsetof(struct stat, st_ctimespec));
#else
    K("stat.st_atime", offsetof(struct stat, st_atim));
    K("stat.st_mtime", offsetof(struct stat, st_mtim));
    K("stat.st_ctime", offsetof(struct stat, st_ctim));
#endif
    K("sizeof stat.st_mode", sizeof(((struct stat *)0)->st_mode));
    K("sizeof stat.st_nlink", sizeof(((struct stat *)0)->st_nlink));
    K("sizeof stat.st_dev", sizeof(((struct stat *)0)->st_dev));
    K("sizeof stat.st_blksize", sizeof(((struct stat *)0)->st_blksize));
    K("dirent.d_ino", offsetof(struct dirent, d_ino));
    K("dirent.d_type", offsetof(struct dirent, d_type));
    K("dirent.d_name", offsetof(struct dirent, d_name));
    K("sizeof dirent.d_name", sizeof(((struct dirent *)0)->d_name));
    K("sizeof timespec", sizeof(struct timespec));
    K("timespec.tv_nsec", offsetof(struct timespec, tv_nsec));
    K("sizeof winsize", sizeof(struct winsize));
    K("winsize.ws_col", offsetof(struct winsize, ws_col));
    K("winsize.ws_ypixel", offsetof(struct winsize, ws_ypixel));
    K("sizeof pollfd", sizeof(struct pollfd));
    K("pollfd.events", offsetof(struct pollfd, events));
    K("pollfd.revents", offsetof(struct pollfd, revents));
    K("sizeof termios", sizeof(struct termios));
    K("sizeof posix_spawn_file_actions_t", sizeof(posix_spawn_file_actions_t));
    K("O_RDONLY", O_RDONLY);
    K("O_WRONLY", O_WRONLY);
    K("O_RDWR", O_RDWR);
    K("O_CREAT", O_CREAT);
    K("O_TRUNC", O_TRUNC);
    K("O_APPEND", O_APPEND);
    K("O_EXCL", O_EXCL);
    K("O_NONBLOCK", O_NONBLOCK);
    K("O_CLOEXEC", O_CLOEXEC);
    K("O_NOCTTY", O_NOCTTY);
    K("O_DIRECTORY", O_DIRECTORY);
    K("F_GETFD", F_GETFD);
    K("F_SETFD", F_SETFD);
    K("F_GETFL", F_GETFL);
    K("F_SETFL", F_SETFL);
    K("FD_CLOEXEC", FD_CLOEXEC);
    K("SEEK_SET", SEEK_SET);
    K("SEEK_CUR", SEEK_CUR);
    K("SEEK_END", SEEK_END);
    K("EPERM", EPERM);
    K("ENOENT", ENOENT);
    K("ESRCH", ESRCH);
    K("EINTR", EINTR);
    K("EIO", EIO);
    K("EBADF", EBADF);
    K("ECHILD", ECHILD);
    K("ENOMEM", ENOMEM);
    K("EACCES", EACCES);
    K("EEXIST", EEXIST);
    K("EXDEV", EXDEV);
    K("ENOTDIR", ENOTDIR);
    K("EISDIR", EISDIR);
    K("EINVAL", EINVAL);
    K("ENOSPC", ENOSPC);
    K("EROFS", EROFS);
    K("EPIPE", EPIPE);
    K("EAGAIN", EAGAIN);
    K("ENOTEMPTY", ENOTEMPTY);
    K("ETIMEDOUT", ETIMEDOUT);
    K("ENOSYS", ENOSYS);
    K("ENOTSUP", ENOTSUP);
    K("ENAMETOOLONG", ENAMETOOLONG);
    K("ELOOP", ELOOP);
    K("CLOCK_REALTIME", CLOCK_REALTIME);
    K("CLOCK_MONOTONIC", CLOCK_MONOTONIC);
    K("PATH_MAX", PATH_MAX);
    K("SIGHUP", SIGHUP);
    K("SIGINT", SIGINT);
    K("SIGKILL", SIGKILL);
    K("SIGTERM", SIGTERM);
    K("SIGCHLD", SIGCHLD);
    K("WNOHANG", WNOHANG);
    K("TIOCSWINSZ", TIOCSWINSZ);
    K("TIOCGWINSZ", TIOCGWINSZ);
    K("TIOCSCTTY", TIOCSCTTY);
    K("TCSANOW", TCSANOW);
    K("POLLIN", POLLIN);
    K("POLLPRI", POLLPRI);
    K("POLLOUT", POLLOUT);
    K("POLLERR", POLLERR);
    K("POLLHUP", POLLHUP);
    K("POLLNVAL", POLLNVAL);
    K("DT_UNKNOWN", DT_UNKNOWN);
    K("DT_FIFO", DT_FIFO);
    K("DT_CHR", DT_CHR);
    K("DT_DIR", DT_DIR);
    K("DT_BLK", DT_BLK);
    K("DT_REG", DT_REG);
    K("DT_LNK", DT_LNK);
    K("DT_SOCK", DT_SOCK);
    K("S_IFMT", S_IFMT);
    K("S_IFDIR", S_IFDIR);
    K("S_IFREG", S_IFREG);
    K("S_IFLNK", S_IFLNK);
    return -999999;
}
