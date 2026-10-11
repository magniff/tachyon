#!/bin/sh
# Checks the bootstrap chain on a fresh x86-64 Linux: builds a minimal
# container image (bootstrap/ci/linux-x86_64.Dockerfile), clones the
# repository inside it, and runs bootstrap/bootstrap.sh there. Needs only
# docker (on Apple silicon, e.g. colima with Rosetta: x86-64 containers run
# through --platform linux/amd64).
#
# usage: bootstrap/linux-check.sh [--worktree] [--seed-tests] [bootstrap options]
#
#   --worktree     check the working tree (tracked and untracked files, not
#                  ignored ones) instead of HEAD; combine with --dev before
#                  the release tags exist
#   --seed-tests   also run the seed's own test suite (cargo test)
#   --all-levels   also run the final compiler's test suite at -O0, -O1, -O2
#   --fuzz=N       also run N random programs (tests/fuzz/run.sh)
#   --bench        also run the benchmarks (bench/run.sh)
#
# Other options go to bootstrap.sh, e.g. --dev. After the chain, the md5
# example is checked against md5sum.

set -eu
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=tachyon-bootstrap:linux-x86_64
PLATFORM=linux/amd64
WORKTREE=0
SEED_TESTS=0
ALL_LEVELS=0
FUZZ=0
BENCH=0

die() {
    echo "linux-check: error: $*" >&2
    exit 1
}

# Its own options, anywhere; the others are kept, in order, for bootstrap.sh.
quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}
rest=""
for arg in "$@"; do
    case "$arg" in
        --worktree) WORKTREE=1 ;;
        --seed-tests) SEED_TESTS=1 ;;
        --all-levels) ALL_LEVELS=1 ;;
        --fuzz=*) FUZZ=${arg#--fuzz=} ;;
        --bench) BENCH=1 ;;
        -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) rest="$rest $(quote "$arg")" ;;
    esac
done
eval "set -- $rest"

command -v docker >/dev/null 2>&1 || die "docker not found"
command -v git >/dev/null 2>&1 || die "git not found"

echo "==> building the image $IMAGE ($PLATFORM)" >&2
docker build --quiet --platform "$PLATFORM" -t "$IMAGE" \
    -f "$ROOT/bootstrap/ci/linux-x86_64.Dockerfile" "$ROOT/seed" >/dev/null

SNAP=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-linux-check.XXXXXX")
trap 'rm -rf "$SNAP"' EXIT INT TERM

# The repository to clone in the container: HEAD and the tags, or the
# working tree committed on top of HEAD in a throwaway copy.
git clone --quiet --no-local "$ROOT" "$SNAP/src"
if [ $WORKTREE -eq 1 ]; then
    echo "==> snapshotting the working tree" >&2
    (cd "$SNAP/src" && git ls-files -z | xargs -0 rm -f)
    (cd "$ROOT" && git ls-files --cached --others --exclude-standard \
        | while IFS= read -r f; do [ -e "$f" ] && printf '%s\n' "$f"; done) >"$SNAP/files"
    (cd "$ROOT" && tar -c -f - -T "$SNAP/files") | (cd "$SNAP/src" && tar -x -f -)
    (cd "$SNAP/src" && git add -A \
        && git -c user.name=snapshot -c user.email=snapshot@localhost \
            commit --quiet --allow-empty -m "working tree snapshot")
fi

echo "==> running the chain in the container" >&2
tar -C "$SNAP" -c -f - src | docker run --rm -i --platform "$PLATFORM" -e SEED_TESTS="$SEED_TESTS" \
    -e ALL_LEVELS="$ALL_LEVELS" -e FUZZ="$FUZZ" -e BENCH="$BENCH" "$IMAGE" sh -c '
    set -eu
    mkdir /work
    tar -x --no-same-owner -f - -C /work
    git clone --quiet /work/src /work/tachyon
    cd /work/tachyon
    echo "==> on $(uname -s) $(uname -m): $(cc --version | head -1), $(git --version)" >&2
    start=$(date +%s)
    sh bootstrap/bootstrap.sh "$@"
    echo "chain: $(( $(date +%s) - start ))s"
    head -c 3000000 /dev/urandom >/tmp/random
    ./target/tachyonc examples/md5.tach -o /tmp/md5.s
    cc -o /tmp/md5 /tmp/md5.s -lm
    got=$(/tmp/md5 </tmp/random)
    want=$(md5sum </tmp/random | cut -d" " -f1)
    [ "$got" = "$want" ] || { echo "md5: tachyon $got, md5sum $want" >&2; exit 1; }
    echo "md5 example: $got, same as md5sum"
    if [ "$ALL_LEVELS" = 1 ]; then
        for level in 0 1 2; do
            echo "==> the test suite at -O$level" >&2
            tests/run.sh -O $level | tail -1
        done
    fi
    if [ "$FUZZ" != 0 ]; then
        echo "==> $FUZZ random programs" >&2
        tests/fuzz/run.sh -n "$FUZZ" -k /tmp/fuzz-failures | tail -5
    fi
    if [ "$BENCH" = 1 ]; then
        echo "==> benchmarks" >&2
        previous=$(ls -d target/bootstrap/x86_64-linux/v*/tachyonc 2>/dev/null | head -1)
        seed=$(ls -d target/bootstrap/x86_64-linux/seed-*/target/release/tachyon 2>/dev/null | head -1)
        bench/run.sh ${previous:+-p "$previous"} ${seed:+-s "$seed"} -r 3
    fi
    if [ "$SEED_TESTS" = 1 ]; then
        echo "==> the seed'"'"'s own tests (cargo test)" >&2
        start=$(date +%s)
        (cd seed && TACHYON_REQUIRE_RUN=1 cargo test --locked --no-fail-fast) >/tmp/seed-tests.log 2>&1 \
            || { tail -60 /tmp/seed-tests.log; echo "the seed'"'"'s tests failed" >&2; exit 1; }
        grep -E "^test result|^  [a-z_/0-9.-]+ +[0-9]+ +[0-9]+ +[0-9]+$" /tmp/seed-tests.log || true
        echo "seed tests: $(( $(date +%s) - start ))s"
    fi
' sh "$@"
