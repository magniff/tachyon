#!/bin/sh
# Checks the bootstrap chain on a fresh x86-64 Linux: builds a minimal
# container image (bootstrap/ci/linux-x86_64.Dockerfile; only when it
# changed), clones the repository inside it, and runs
# bootstrap/bootstrap.sh there. Needs only docker (on Apple silicon, e.g.
# colima with Rosetta: x86-64 containers run through --platform
# linux/amd64).
#
# usage: bootstrap/linux-check.sh [--worktree] [checks] [bootstrap options]
#
#   --worktree     check the working tree (tracked and untracked files, not
#                  ignored ones) instead of HEAD; combine with --dev before
#                  the release tags exist
#   --seed-tests   also run the seed's own test suite (cargo test)
#   --all-levels   also run the final compiler's test suite at -O0, -O1, -O2
#   --fuzz=N       also run N random programs in each mode of the generator
#                  (tests/fuzz/run.sh), the seed as a third oracle in one
#   --abi=N        also run N C interoperability programs (tests/abi/run.sh),
#                  plain, through import and through --emit-header, and
#                  check the layout of imported system headers
#   --bench        also run the benchmarks (bench/run.sh)
#   --objcheck     also check the compiler's objects against cc -c
#                  (tests/objcheck.sh)
#   --debugger     also check debug information with gdb (tests/debug.sh)
#   --cpus N       the container's CPUs (default 8, at most docker's)
#   --fresh        without the cache: the chain's built releases are kept
#                  in a docker volume (tachyon-bootstrap-x86_64-linux),
#                  by tag and commit as bootstrap.sh caches them, so a
#                  rerun rebuilds only HEAD; --fresh builds everything
#                  (with --history full: a complete replay)
#   --rebuild-image  rebuild the image even if its recipe is unchanged
#                  (for a newer base image)
#
# Other options go to bootstrap.sh, e.g. --dev or --history full. After the
# chain, the md5 example is checked against md5sum; the checks run at once
# (bootstrap/gate.sh --inside), with one table at the end.

set -eu
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=tachyon-bootstrap:linux-x86_64
PLATFORM=linux/amd64
VOLUME=tachyon-bootstrap-x86_64-linux
WORKTREE=0
SEED_TESTS=0
ALL_LEVELS=0
FUZZ=0
ABI=0
BENCH=0
OBJCHECK=0
DEBUGGER=0
CPUS=8
FRESH=0
REBUILD_IMAGE=0

die() {
    echo "linux-check: error: $*" >&2
    exit 1
}
. "$ROOT/bootstrap/ci/common.sh"

# Its own options, anywhere; the others are kept, in order, for bootstrap.sh.
quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}
rest=""
want_cpus=0
for arg in "$@"; do
    if [ $want_cpus -eq 1 ]; then CPUS=$arg; want_cpus=0; continue; fi
    case "$arg" in
        --worktree) WORKTREE=1 ;;
        --seed-tests) SEED_TESTS=1 ;;
        --all-levels) ALL_LEVELS=1 ;;
        --fuzz=*) FUZZ=${arg#--fuzz=} ;;
        --abi=*) ABI=${arg#--abi=} ;;
        --bench) BENCH=1 ;;
        --objcheck) OBJCHECK=1 ;;
        --debugger) DEBUGGER=1 ;;
        --cpus) want_cpus=1 ;;
        --cpus=*) CPUS=${arg#--cpus=} ;;
        --fresh) FRESH=1 ;;
        --rebuild-image) REBUILD_IMAGE=1 ;;
        -h|--help) sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) rest="$rest $(quote "$arg")" ;;
    esac
done
eval "set -- $rest"
case "$CPUS" in ''|*[!0-9]*|0) die "--cpus needs a number" ;; esac

command -v docker >/dev/null 2>&1 || die "docker not found"
command -v git >/dev/null 2>&1 || die "git not found"
docker info >/dev/null 2>&1 || die "docker is not running (with colima: colima start)"
clamp_cpus

ensure_image "$IMAGE" "$PLATFORM" "$ROOT/bootstrap/ci/linux-x86_64.Dockerfile" \
    "$ROOT/seed/rust-toolchain.toml" "$ROOT/seed/Cargo.toml" "$ROOT/seed/Cargo.lock"

SNAP=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-linux-check.XXXXXX")
trap 'stop_container; rm -rf "$SNAP"' EXIT
trap 'exit 130' INT TERM

# The repository to clone in the container: HEAD and the tags, or the
# working tree committed on top of HEAD in a throwaway copy.
snapshot "$SNAP" 1

CACHE_MOUNT=""
[ $FRESH -eq 1 ] || CACHE_MOUNT="-v $VOLUME:/cache"

echo "==> running the chain in the container ($CPUS CPUs${CACHE_MOUNT:+, the cache in the volume $VOLUME})" >&2
# shellcheck disable=SC2086
tar -C "$SNAP" -c -f - src | docker run --rm -i --name "$CONTAINER" --cpus "$CPUS" --platform "$PLATFORM" \
    $CACHE_MOUNT -e CPUS="$CPUS" -e SEED_TESTS="$SEED_TESTS" -e ALL_LEVELS="$ALL_LEVELS" -e FUZZ="$FUZZ" \
    -e ABI="$ABI" -e BENCH="$BENCH" -e OBJCHECK="$OBJCHECK" -e DEBUGGER="$DEBUGGER" "$IMAGE" sh -c '
    set -eu
    mkdir /work
    tar -x --no-same-owner -f - -C /work
    git clone --quiet /work/src /work/tachyon
    cd /work/tachyon
    echo "==> on $(uname -s) $(uname -m): $(cc --version | head -1), $(git --version)" >&2
    # A row of the table bootstrap/gate.sh prints: step, result, seconds, note.
    row() { printf "gate-row\t%s\t%s\t%s\t%s\n" "$@"; }
    if [ -d /cache ]; then
        set -- --cache /cache "$@"
        boot=/cache/x86_64-linux
    else
        boot=target/bootstrap/x86_64-linux
    fi
    # (the suite at every level is a check below)
    [ "$ALL_LEVELS" = 1 ] && set -- --no-head-tests "$@"
    start=$(date +%s)
    if ! sh bootstrap/bootstrap.sh "$@" >/tmp/chain.log 2>&1; then
        tail -40 /tmp/chain.log
        row chain FAIL $(( $(date +%s) - start )) "bootstrap.sh failed"
        echo "--- chain: FAIL"; tail -40 /tmp/chain.log
        exit 1
    fi
    sed -n "/^tachyon bootstrap on/,\$p" /tmp/chain.log
    echo "chain: $(( $(date +%s) - start ))s"
    row chain pass $(( $(date +%s) - start )) "$(awk "/^  head / { sub(/^  head +/, \"\"); print; exit }" /tmp/chain.log)"
    start=$(date +%s)
    head -c 3000000 /dev/urandom >/tmp/random
    ./target/tachyonc examples/md5.tach -o /tmp/md5.o
    cc -o /tmp/md5 /tmp/md5.o -lm
    got=$(/tmp/md5 </tmp/random)
    want=$(md5sum </tmp/random | cut -d" " -f1)
    if [ "$got" != "$want" ]; then
        row md5 FAIL $(( $(date +%s) - start )) "tachyon $got, md5sum $want"
        echo "--- md5: FAIL: tachyon $got, md5sum $want"
        exit 1
    fi
    echo "md5 example: $got, same as md5sum"
    row md5 pass $(( $(date +%s) - start )) "the md5 example agrees with md5sum"
    # The checks, at once.
    steps=""
    [ "$ALL_LEVELS" = 1 ] && steps="$steps,suite-O*"
    [ "$FUZZ" != 0 ] && steps="$steps,fuzz-*"
    [ "$ABI" != 0 ] && steps="$steps,abi-*,layout"
    [ "$OBJCHECK" = 1 ] && steps="$steps,objcheck"
    [ "$DEBUGGER" = 1 ] && steps="$steps,debug"
    status=0
    if [ -n "$steps" ]; then
        seed=$(ls -d "$boot"/seed-*/target/release/tachyon "$boot"/seed-worktree/target/release/tachyon 2>/dev/null | head -1) || true
        echo "==> the checks:$(echo "$steps" | tr "," " ")" >&2
        sh bootstrap/gate.sh --inside -c target/tachyonc -j "$CPUS" --only "${steps#,}" \
            --fuzz "$([ "$FUZZ" = 0 ] && echo 1 || echo "$FUZZ")" --abi "$([ "$ABI" = 0 ] && echo 1 || echo "$ABI")" \
            ${seed:+--seed "$seed"} || status=1
    fi
    if [ "$BENCH" = 1 ]; then
        echo "==> benchmarks" >&2
        # The newest release built here, in the order of releases.toml (tags
        # never sorted as text: v0.10.0 comes after v0.9.0).
        previous=""
        for tag in $(sh bootstrap/release-tags.sh); do
            for p in "$boot"/"$tag"-*/tachyonc; do
                [ -x "$p" ] && previous=$p
            done
        done
        seed=$(ls -d "$boot"/seed-*/target/release/tachyon 2>/dev/null | head -1) || true
        bench/run.sh ${previous:+-p "$previous"} ${seed:+-s "$seed"} -r 3 || status=1
    fi
    if [ "$SEED_TESTS" = 1 ]; then
        echo "==> the seed'"'"'s own tests (cargo test)" >&2
        start=$(date +%s)
        if (cd seed && TACHYON_REQUIRE_RUN=1 cargo test --locked --no-fail-fast) >/tmp/seed-tests.log 2>&1; then
            grep -E "^test result|^  [a-z_/0-9.-]+ +[0-9]+ +[0-9]+ +[0-9]+$" /tmp/seed-tests.log || true
            row seed-tests pass $(( $(date +%s) - start )) "cargo test"
        else
            tail -60 /tmp/seed-tests.log
            echo "the seed'"'"'s tests failed" >&2
            row seed-tests FAIL $(( $(date +%s) - start )) "cargo test"
            status=1
        fi
        echo "seed tests: $(( $(date +%s) - start ))s"
    fi
    exit $status
' sh "$@"
