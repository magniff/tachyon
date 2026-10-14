#!/bin/sh
# The aarch64-linux host (0.11). The bootstrap chain cannot run there (the
# Rust seed and the releases before 0.11 have no aarch64-linux backend), so
# the compiler for it is cross-built and then checked natively:
#
#   1. here (aarch64-macos, x86_64-macos or x86_64-linux):
#      bootstrap/bootstrap.sh --host aarch64-linux runs the chain and
#      cross-compiles HEAD's compiler for aarch64-linux, an object;
#   2. in a linux/arm64 container (bootstrap/ci/linux-aarch64.Dockerfile;
#      native on Apple silicon, e.g. with colima): that object is linked,
#      the compiler builds itself, which must give the same object again
#      (its output does not depend on the host), and again (the fixpoint);
#      then its test suite runs, with the checks asked for below.
#
# usage: bootstrap/aarch64-linux-check.sh [--worktree] [checks] [bootstrap options]
#
#   --worktree     check the working tree (tracked and untracked files, not
#                  ignored ones) instead of HEAD; combine with --dev before
#                  the release tags exist
#   --all-levels   run the test suite at -O0, -O1 and -O2 (else at the
#                  default level)
#   --fuzz=N       also run N random programs in each mode of the
#                  generator (tests/fuzz/run.sh)
#   --abi=N        also run N C interoperability programs (tests/abi/run.sh),
#                  plain, through import and through --emit-header, and
#                  check the layout of imported system headers
#   --objcheck     also check the compiler's objects against cc -c
#                  (tests/objcheck.sh)
#   --debugger     also check debug information with gdb (tests/debug.sh)
#
# Other options go to bootstrap.sh, e.g. --dev.

set -eu
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=tachyon-check:linux-aarch64
PLATFORM=linux/arm64
WORKTREE=0
ALL_LEVELS=0
FUZZ=0
ABI=0
OBJCHECK=0
DEBUGGER=0

die() {
    echo "aarch64-linux-check: error: $*" >&2
    exit 1
}

quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}
rest=""
for arg in "$@"; do
    case "$arg" in
        --worktree) WORKTREE=1; rest="$rest --worktree" ;;
        --dev) WORKTREE=1; rest="$rest --dev" ;;
        --all-levels) ALL_LEVELS=1 ;;
        --fuzz=*) FUZZ=${arg#--fuzz=} ;;
        --abi=*) ABI=${arg#--abi=} ;;
        --objcheck) OBJCHECK=1 ;;
        --debugger) DEBUGGER=1 ;;
        -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) rest="$rest $(quote "$arg")" ;;
    esac
done
eval "set -- $rest"

command -v docker >/dev/null 2>&1 || die "docker not found"
command -v git >/dev/null 2>&1 || die "git not found"

echo "==> the chain here, and the compiler cross-built for aarch64-linux" >&2
sh "$ROOT/bootstrap/bootstrap.sh" --host aarch64-linux "$@"
OBJECT="$ROOT/target/aarch64-linux/tachyonc.o"
[ -f "$OBJECT" ] || die "bootstrap.sh left no $OBJECT"

echo "==> building the image $IMAGE ($PLATFORM)" >&2
# The base image by the digest of its manifest for this platform: the
# legacy builder takes a multi-platform tag for the machine's own platform
# once that one is stored (as the other Linux check stores it).
BASE=$(docker manifest inspect debian:bookworm-slim | awk -v arch="${PLATFORM#linux/}" '
    /"digest"/ { d = $2; gsub(/[",]/, "", d) }
    /"architecture"/ { a = $2; gsub(/[",]/, "", a); if (a == arch && !found) { print d; found = 1 } }')
[ -n "$BASE" ] || die "no $PLATFORM manifest of debian:bookworm-slim"
docker build --quiet --platform "$PLATFORM" --build-arg BASE="debian@$BASE" -t "$IMAGE" \
    -f "$ROOT/bootstrap/ci/linux-aarch64.Dockerfile" "$ROOT/bootstrap/ci" >/dev/null

SNAP=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-aarch64-linux-check.XXXXXX")
trap 'rm -rf "$SNAP"' EXIT INT TERM

# The tree the object was built from: HEAD, or the working tree.
git clone --quiet --no-local "$ROOT" "$SNAP/src"
if [ $WORKTREE -eq 1 ]; then
    echo "==> snapshotting the working tree" >&2
    (cd "$SNAP/src" && git ls-files -z | xargs -0 rm -f)
    (cd "$ROOT" && git ls-files --cached --others --exclude-standard \
        | while IFS= read -r f; do [ -e "$f" ] && printf '%s\n' "$f"; done) >"$SNAP/files"
    (cd "$ROOT" && tar -c -f - -T "$SNAP/files") | (cd "$SNAP/src" && tar -x -f -)
fi
cp "$OBJECT" "$SNAP/tachyonc.o"

echo "==> on aarch64-linux, in the container" >&2
tar -C "$SNAP" -c -f - src tachyonc.o | docker run --rm -i --cpus 4 --platform "$PLATFORM" \
    -e ALL_LEVELS="$ALL_LEVELS" -e FUZZ="$FUZZ" -e ABI="$ABI" -e OBJCHECK="$OBJCHECK" \
    -e DEBUGGER="$DEBUGGER" "$IMAGE" sh -c '
    set -eu
    mkdir /work
    tar -x --no-same-owner -f - -C /work
    cd /work/src
    echo "==> on $(uname -s) $(uname -m): $(cc --version | head -1)" >&2
    mkdir -p target/native
    n=target/native
    cc -o $n/cross /work/tachyonc.o -lm
    echo "cross-built compiler: $($n/cross --version)"
    # Built by itself here: the same object as the cross-compilation, and
    # a fixpoint.
    $n/cross compiler/src/main.tach -o $n/build2.o
    cmp -s /work/tachyonc.o $n/build2.o \
        || { echo "the compiler built here differs from the cross-built one" >&2; exit 1; }
    cc -o $n/build2 $n/build2.o -lm
    $n/build2 compiler/src/main.tach -o $n/build3.o
    cmp -s $n/build2.o $n/build3.o || { echo "no fixpoint on aarch64-linux" >&2; exit 1; }
    cp $n/build2 target/tachyonc
    echo "fixpoint: the cross-built compiler, its build here and that one'"'"'s build emit the same object"
    head -c 3000000 /dev/urandom >/tmp/random
    ./target/tachyonc examples/md5.tach -o /tmp/md5
    got=$(/tmp/md5 </tmp/random)
    want=$(md5sum </tmp/random | cut -d" " -f1)
    [ "$got" = "$want" ] || { echo "md5: tachyon $got, md5sum $want" >&2; exit 1; }
    echo "md5 example: $got, same as md5sum"
    if [ "$ALL_LEVELS" = 1 ]; then
        for level in 0 1 2; do
            echo "==> the test suite at -O$level" >&2
            tests/run.sh -O $level >/tmp/tests.log 2>&1 || { tail -40 /tmp/tests.log; exit 1; }
            tail -1 /tmp/tests.log
        done
    else
        echo "==> the test suite" >&2
        tests/run.sh >/tmp/tests.log 2>&1 || { tail -40 /tmp/tests.log; exit 1; }
        tail -1 /tmp/tests.log
    fi
    if [ "$FUZZ" != 0 ]; then
        for mode in "" -l -g -p -C -N -V; do
            echo "==> $FUZZ random programs ${mode:+(mode $mode)}" >&2
            tests/fuzz/run.sh -n "$FUZZ" $mode -k /tmp/fuzz-failures | tail -1
        done
    fi
    if [ "$OBJCHECK" = 1 ]; then
        echo "==> objects against cc -c" >&2
        tests/objcheck.sh | tail -5
    fi
    if [ "$ABI" -gt 0 ]; then
        echo "==> $ABI C interoperability programs" >&2
        tests/abi/run.sh -n "$ABI" -k /tmp/abi-failures | tail -5
        echo "==> $ABI C interoperability programs, through import" >&2
        tests/abi/run.sh -i -n "$ABI" -k /tmp/abi-failures | tail -5
        echo "==> $ABI C interoperability programs, through --emit-header" >&2
        tests/abi/run.sh -H -n "$ABI" -k /tmp/abi-failures | tail -5
        echo "==> the layout of imported system headers" >&2
        tests/cimport/layout.sh stdio.h stdlib.h string.h math.h time.h \
            fcntl.h unistd.h signal.h sys/stat.h sys/time.h sys/socket.h \
            netinet/in.h dirent.h pthread.h | tail -5
    fi
    if [ "$DEBUGGER" = 1 ]; then
        echo "==> debug information, with gdb" >&2
        tests/debug.sh | tail -5
    fi
'
