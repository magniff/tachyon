#!/bin/sh
# Builds the tachyon compiler from nothing but git, a Rust toolchain and a C
# compiler, release by release, following bootstrap/releases.toml:
#
#   1. the seed: the frozen Rust compiler, from the seed/ directory of the
#      `seed` tag, built with cargo;
#   2. every release, in order: built by the previous step's compiler, then
#      by itself; the two emitted outputs must be identical (the fixpoint),
#      and the release's own test suite must pass (by default only the
#      last release's: see --history);
#   3. HEAD (or the working tree), the same way, built by the last release.
#
# Everything is built for the host, which is detected first; each release
# lists the hosts it supports. Only the host's tools are required: git,
# cargo, a C compiler (cc, or $CC) and POSIX utilities.
#
# Built steps are cached under target/bootstrap/<host>/, by tag and
# commit, so a rerun only redoes HEAD (and what --history full asks for
# that the cache lacks). The final compiler is copied to target/tachyonc,
# where tests/run.sh looks for it, and (0.15), when its test suite ran and
# passed, to target/tools/tachyonc: the binary agents query and edit with,
# which their own builds of target/tachyonc do not replace. (0.14) In a linked git worktree the
# releases come from the main checkout's cache (or $TACHYON_BOOTSTRAP_CACHE),
# so a fresh worktree builds only HEAD; HEAD itself is always built in the
# worktree's own target/bootstrap. (0.18.1) Runs from several worktrees
# share that cache safely: an entry is written under a lock (<entry>.lock,
# a directory: mkdir is atomic), built in <entry>.building and renamed into
# place once its fixpoint (and suite) passed, so no run sees a half-built
# entry or deletes another's; a run waits for the lock, and takes it over
# when its holder is gone (or after TACHYON_BOOTSTRAP_LOCK_STALE minutes,
# default 120).
#
# usage: bootstrap/bootstrap.sh [options]
#
#   --worktree         step 3 uses the working tree instead of HEAD
#   --until VERSION    stop after this release (skip later ones and HEAD)
#   --dev              for testing before the tags exist: a missing `seed`
#                      tag means the seed comes from the working tree,
#                      releases whose tag is missing are skipped, and step 3
#                      uses the working tree
#   --host HOST        build for HOST instead of the detected host (on
#                      Apple silicon, --host x86_64-macos builds and tests
#                      the chain for Intel Macs, run under Rosetta);
#                      --host aarch64-linux (0.11) runs the chain here and
#                      then cross-builds HEAD's compiler for aarch64-linux,
#                      as an object to link there (see
#                      bootstrap/aarch64-linux-check.sh)
#   --seed-bin PATH    use this seed binary instead of building one
#   --cache DIR        the cache directory for the releases (default:
#                      $TACHYON_BOOTSTRAP_CACHE, else the main checkout's
#                      target/bootstrap in a linked worktree, else
#                      target/bootstrap)
#   --clean            empty the cache first (and use this checkout's own)
#   --out PATH         also copy the final compiler here
#   --history MODE     (0.11) what is checked of the releases before HEAD:
#                      `fast` (the default) builds each and checks its
#                      fixpoint, but runs the test suite of the last one
#                      only; `full` runs every release's suite too, an
#                      occasional complete replay (with --clean: from
#                      nothing). A result in the cache counts for both
#                      when it holds what the mode asks for.
#   --no-head-tests    (0.11) build HEAD and check its fixpoint, but leave
#                      its test suite to the caller (bootstrap/gate.sh runs
#                      it at every level)
#
# See docs/releases.md.

set -eu
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST="$ROOT/bootstrap/releases.toml"
CACHE=
LOCAL_CACHE="$ROOT/target/bootstrap"
WORKTREE=0
DEV=0
UNTIL=""
HOST=""
SEED_BIN=""
CLEAN=0
OUT=""
HISTORY=fast
RUN_HEAD_TESTS=1

die() {
    echo "bootstrap: error: $*" >&2
    exit 1
}

step() {
    echo "==> $*" >&2
}

# Whether version $1 is older than $2: their dot-separated numbers compared
# as numbers, never as text (0.9.0 is older than 0.10.0). Releases are taken
# in the order of releases.toml, which this checks; nothing here may sort
# versions or tags as strings.
version_lt() { # <a> <b>
    awk -v a="$1" -v b="$2" 'BEGIN {
        na = split(a, x, "."); nb = split(b, y, ".")
        n = na > nb ? na : nb
        for (i = 1; i <= n; i++) {
            if (x[i] + 0 < y[i] + 0) exit 0
            if (x[i] + 0 > y[i] + 0) exit 1
        }
        exit 1
    }'
}
# (a self-check, cheap enough to run every time)
{ version_lt 0.9.0 0.10.0 && ! version_lt 0.10.0 0.9.0 && version_lt 0.10.0 1.0.0 \
    && ! version_lt 0.5.0 0.5.0; } || die "internal error: version_lt compares versions as text"

while [ $# -gt 0 ]; do
    case "$1" in
        --worktree) WORKTREE=1 ;;
        --dev) DEV=1; WORKTREE=1 ;;
        --until) [ $# -ge 2 ] || die "--until needs a version"; UNTIL=$2; shift ;;
        --host) [ $# -ge 2 ] || die "--host needs a host"; HOST=$2; shift ;;
        --seed-bin) [ $# -ge 2 ] || die "--seed-bin needs a path"; SEED_BIN=$2; shift ;;
        --cache) [ $# -ge 2 ] || die "--cache needs a directory"; CACHE=$2; shift ;;
        --clean) CLEAN=1 ;;
        --out) [ $# -ge 2 ] || die "--out needs a path"; OUT=$2; shift ;;
        --history) [ $# -ge 2 ] || die "--history needs fast or full"; HISTORY=$2; shift ;;
        --history=*) HISTORY=${1#--history=} ;;
        --no-head-tests) RUN_HEAD_TESTS=0 ;;
        -h|--help) sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option '$1' (see --help)" ;;
    esac
    shift
done
if [ -z "$CACHE" ] && [ $CLEAN -eq 0 ]; then
    if [ -n "${TACHYON_BOOTSTRAP_CACHE:-}" ]; then
        CACHE=$TACHYON_BOOTSTRAP_CACHE
    else
        # A linked worktree shares the main checkout's releases (keyed by tag
        # and commit, so sharing is safe); HEAD stays local, below.
        common=$(cd "$ROOT" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
        main_root=$(dirname "$common")
        if [ -n "$common" ] && [ "$main_root" != "$ROOT" ] && [ -d "$main_root/target/bootstrap" ]; then
            CACHE="$main_root/target/bootstrap"
        fi
    fi
fi
[ -n "$CACHE" ] || CACHE=$LOCAL_CACHE
case "$HISTORY" in
    fast|full) ;;
    *) die "--history is fast or full, not '$HISTORY'" ;;
esac

# ---- The host ----

# The host as a tachyon target name.
detect_host() {
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) echo aarch64-macos ;;
        Darwin-x86_64) echo x86_64-macos ;;
        Linux-x86_64) echo x86_64-linux ;;
        Linux-aarch64) echo aarch64-linux ;;
        *) echo unsupported ;;
    esac
}
CROSS=""
if [ -z "$HOST" ]; then
    HOST=$(detect_host)
    [ "$HOST" != unsupported ] \
        || die "unsupported host: $(uname -s) $(uname -m). tachyon builds on aarch64-macos (Apple silicon), x86_64-macos and x86_64-linux; another host needs a release with a backend for it (see docs/releases.md)."
fi
# aarch64-linux (0.11): no release before 0.11, nor the seed (Rust and
# Cranelift, pinned), runs there, so the chain cannot start on it. It runs
# on another host, and HEAD's compiler is then cross-compiled for
# aarch64-linux; its output does not depend on the host it runs on.
if [ "$HOST" = aarch64-linux ]; then
    build_host=$(detect_host)
    case "$build_host" in
        aarch64-macos|x86_64-macos|x86_64-linux) ;;
        *) die "the chain cannot run on aarch64-linux (the seed and the releases before 0.11 have no aarch64-linux backend). Run bootstrap/bootstrap.sh --host aarch64-linux on aarch64-macos, x86_64-macos or x86_64-linux, which cross-builds the compiler for aarch64-linux, then finish on aarch64-linux as bootstrap/aarch64-linux-check.sh does (see docs/releases.md)." ;;
    esac
    CROSS=aarch64-linux
    HOST=$build_host
    [ -z "$UNTIL" ] || die "--host aarch64-linux cross-builds HEAD: it does not combine with --until"
fi
# The seed's name for it, and how the C compiler links for it.
case "$HOST" in
    aarch64-macos) SEED_TARGET=macos-aarch64; LINK_FLAGS="-arch arm64" ;;
    x86_64-macos) SEED_TARGET=macos-x86_64; LINK_FLAGS="-arch x86_64" ;;
    x86_64-linux) SEED_TARGET=linux-x86_64; LINK_FLAGS="" ;;
    *) die "unknown host '$HOST' (expected aarch64-macos, x86_64-macos or x86_64-linux)" ;;
esac
CC=${CC:-cc}
export CC

# Every missing tool, at once.
missing=""
need() { # <tool> <why>
    command -v "$1" >/dev/null 2>&1 || missing="$missing
  $1: $2"
}
need git "releases are read from git tags"
need tar "release trees are extracted with git archive | tar"
need awk "the manifest is read with awk"
need cmp "the fixpoint compares the emitted assembly or objects"
need "$CC" "the C compiler assembles and links tachyon's output (set CC to use another)"
if [ -z "$SEED_BIN" ]; then
    need cargo "the seed is the Rust compiler; install Rust with rustup (https://rustup.rs)"
fi
[ -z "$missing" ] || die "missing tools on $HOST:$missing"

# ---- The manifest ----

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-bootstrap.XXXXXX")
HELD_LOCK=""
trap 'rm -rf "$WORK" $HELD_LOCK' EXIT
trap 'exit 130' INT TERM

# One line per entry, fields separated by '|' (hosts comma-separated):
#   seed|<tag>|<dir>
#   release|<version>|<tag>|<compiler>|<built_by>|<cli>|<tests>|<hosts>|<root>
#   head|<compiler>|<cli>|<tests>|<hosts>|<root>
[ -f "$MANIFEST" ] || die "missing $MANIFEST"
awk '
    function flush() {
        if (section == "seed")
            print "seed|" v["tag"] "|" v["dir"]
        if (section == "release")
            print "release|" v["version"] "|" v["tag"] "|" v["compiler"] "|" v["built_by"] "|" v["cli"] "|" v["tests"] "|" v["hosts"] "|" v["root"]
        if (section == "head")
            print "head|" v["compiler"] "|" v["cli"] "|" v["tests"] "|" v["hosts"] "|" v["root"]
        split("", v)
    }
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    /^\[seed\]/ { flush(); section = "seed"; next }
    /^\[\[release\]\]/ { flush(); section = "release"; next }
    /^\[head\]/ { flush(); section = "head"; next }
    /^[A-Za-z_]+[ \t]*=/ {
        key = $0; sub(/[ \t]*=.*/, "", key)
        value = $0; sub(/^[^=]*=[ \t]*/, "", value)
        if (key != "summary") gsub(/[\[\]" \t]/, "", value)
        v[key] = value
        next
    }
    { print "bad|" NR ": " $0 }
    END { flush() }
' "$MANIFEST" >"$WORK/manifest"

bad=$(grep '^bad|' "$WORK/manifest" | head -1 | cut -d'|' -f2-) || true
[ -z "$bad" ] || die "cannot parse $MANIFEST, line $bad"
grep '^release|' "$WORK/manifest" >"$WORK/releases" || die "$MANIFEST lists no release"
grep -q '^seed|' "$WORK/manifest" || die "$MANIFEST has no [seed] section"
grep -q '^head|' "$WORK/manifest" || die "$MANIFEST has no [head] section"
IFS='|' read -r _ SEED_TAG SEED_DIR <<EOF
$(grep '^seed|' "$WORK/manifest")
EOF
IFS='|' read -r _ HEAD_COMPILER HEAD_CLI HEAD_TESTS HEAD_HOSTS HEAD_ROOT <<EOF
$(grep '^head|' "$WORK/manifest")
EOF
if [ -n "$UNTIL" ] && ! grep -q "^release|$UNTIL|" "$WORK/releases"; then
    die "no release $UNTIL in $MANIFEST"
fi

check_host() { # <what> <comma-separated hosts>
    case ",$2," in
        *",$HOST,"*) ;;
        *) die "$1 supports $2, not this host ($HOST). Bootstrapping here needs a release with a backend for $HOST." ;;
    esac
}

prev_version=""
while IFS='|' read -r _ version _ _ _ _ _ hosts _; do
    [ -z "$prev_version" ] || version_lt "$prev_version" "$version" \
        || die "$MANIFEST: release $version comes after $prev_version but is not newer (versions compare by number: 0.9.0 < 0.10.0)"
    prev_version=$version
    check_host "release $version" "$hosts"
    [ "$version" = "$UNTIL" ] && break
done <"$WORK/releases"
[ -n "$UNTIL" ] || check_host "the compiler at HEAD" "$HEAD_HOSTS"
if [ -n "$CROSS" ]; then
    case ",$HEAD_HOSTS," in
        *",$CROSS,"*) ;;
        *) die "the compiler at HEAD supports $HEAD_HOSTS, not $CROSS" ;;
    esac
fi

# ---- Git ----

cd "$ROOT"
git rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not a git repository"
CACHE="$CACHE/$HOST"
LOCAL_CACHE="$LOCAL_CACHE/$HOST"
[ "$CACHE" = "$LOCAL_CACHE" ] || step "releases from the shared cache $CACHE"
mkdir -p "$LOCAL_CACHE"
if [ $CLEAN -eq 1 ]; then
    step "cleaning $CACHE"
    rm -rf "$CACHE"
fi
mkdir -p "$CACHE"

tag_commit() { # <tag>: its commit, or nothing when the tag does not exist
    git rev-parse -q --verify "refs/tags/$1^{commit}" 2>/dev/null || true
}

# (0.18.1) The lock on a shared-cache entry <dir>: the directory
# <dir>.lock, made by mkdir (atomic), with the holder's pid in it; one at a
# time (HELD_LOCK, removed on exit). A lock whose holder is gone (this
# host's processes) or older than the stale limit is taken over: renamed
# away first, so two waiters cannot both break it.
LOCK_STALE=${TACHYON_BOOTSTRAP_LOCK_STALE:-120}
lock() { # <dir>
    lk_waited=0
    while ! mkdir "$1.lock" 2>/dev/null; do
        lk_pid=$(cat "$1.lock/pid" 2>/dev/null || true)
        lk_stale=0
        if [ -n "$lk_pid" ] && ! kill -0 "$lk_pid" 2>/dev/null; then
            lk_stale=1
        elif [ -n "$(find "$1.lock" -prune -mmin +"$LOCK_STALE" 2>/dev/null)" ]; then
            lk_stale=1
        fi
        if [ $lk_stale -eq 1 ]; then
            if mv "$1.lock" "$1.lock.stale.$$" 2>/dev/null; then
                step "taking over the stale lock $1.lock (holder ${lk_pid:-unknown})"
                rm -rf "$1.lock.stale.$$"
            fi
            continue
        fi
        if [ $lk_waited -eq 0 ]; then
            step "waiting for another bootstrap.sh (pid ${lk_pid:-?}) building $(basename "$1")"
            lk_waited=1
        fi
        sleep 2
    done
    echo $$ >"$1.lock/pid"
    HELD_LOCK=$1.lock
}
unlock() { # <dir>
    rm -rf "$1.lock"
    HELD_LOCK=""
}
# Puts the finished <dir>.building in place of <dir> (under the lock): the
# rename is atomic, and an unfinished old entry is moved aside first.
publish() { # <dir>
    if [ -e "$1" ]; then
        rm -rf "$1.old"
        mv "$1" "$1.old"
    fi
    mv "$1.building" "$1"
    rm -rf "$1.old"
}

# Extracts the tree of <commit> into <dir> (fresh).
extract() { # <commit> <dir>
    rm -rf "$2"
    mkdir -p "$2"
    git archive --format=tar "$1" | tar -x -C "$2"
}

# ---- Building and checking one compiler ----

# Compiles the compiler in <src> into the executable <out> with the
# compiler <bin>, invoked through interface <cli>, for the host: its root
# file <root> (a module tree, from 0.6), or else all the .tach files of
# <src> (one module).
# (POSIX sh has no local variables: each function uses its own prefix.)
compile_with() { # <cli> <bin> <src> <root> <out>
    cw_cli=$1 cw_bin=$2 cw_src=$3 cw_root=$4 cw_out=$5
    if [ -n "$cw_root" ]; then
        set -- "$cw_src/$cw_root"
        [ -f "$1" ] || die "no root file $cw_root in $cw_src"
        [ "$cw_cli" != seed ] || die "the seed compiles one file: $cw_src is a module tree"
    else
        set -- "$cw_src"/*.tach
        [ -e "$1" ] || die "no .tach files in $cw_src"
    fi
    case "$cw_cli" in
        seed)
            # The seed compiles one file: the sources together.
            cat "$@" >"$cw_out.all.tach"
            "$cw_bin" build --target "$SEED_TARGET" "$cw_out.all.tach" -o "$cw_out" \
                || die "the seed failed to compile $cw_src"
            ;;
        tachyonc-0.1)
            "$cw_bin" --target "$HOST" "$@" -o "$cw_out.s" || die "$cw_bin failed to compile $cw_src"
            # shellcheck disable=SC2086
            "$CC" $LINK_FLAGS -o "$cw_out" "$cw_out.s" -lm || die "$CC failed to link $cw_out.s"
            CW_EMITTED=s
            ;;
        tachyonc-0.7)
            # From 0.7 the compiler writes the object itself; cc links.
            "$cw_bin" --target "$HOST" "$@" -o "$cw_out.o" || die "$cw_bin failed to compile $cw_src"
            # shellcheck disable=SC2086
            "$CC" $LINK_FLAGS -o "$cw_out" "$cw_out.o" -lm || die "$CC failed to link $cw_out.o"
            CW_EMITTED=o
            ;;
        tachyonc-0.9)
            # As 0.7, with --allow-unsafe: the compiler's own source has
            # unsafe operations outside unsafe code until 0.10 (0.9 warns
            # about them).
            "$cw_bin" --target "$HOST" --allow-unsafe "$@" -o "$cw_out.o" || die "$cw_bin failed to compile $cw_src"
            # shellcheck disable=SC2086
            "$CC" $LINK_FLAGS -o "$cw_out" "$cw_out.o" -lm || die "$CC failed to link $cw_out.o"
            CW_EMITTED=o
            ;;
        tachyonc-0.10)
            # As 0.7: the compiler's own source is in unsafe code (0.10
            # has no --allow-unsafe; unsafe operations outside unsafe code
            # are errors).
            "$cw_bin" --target "$HOST" "$@" -o "$cw_out.o" || die "$cw_bin failed to compile $cw_src"
            # shellcheck disable=SC2086
            "$CC" $LINK_FLAGS -o "$cw_out" "$cw_out.o" -lm || die "$CC failed to link $cw_out.o"
            CW_EMITTED=o
            ;;
        *)
            die "unknown compiler interface '$cw_cli' (bootstrap.sh needs to learn it)"
            ;;
    esac
}

# Builds the compiler in <tree>/<compiler> with <builder>, checks the
# fixpoint and, if <run_tests> is 1, runs the tree's test suite; leaves
# <dir>/tachyonc and sets TEST_TOTAL.
build_and_check() { # <name> <tree> <compiler> <root> <cli> <tests> <builder_cli> <builder_bin> <builder_name> <dir> <run_tests>
    bc_name=$1 bc_tree=$2 bc_src="$2/$3" bc_root=$4 bc_cli=$5 bc_tests=$6
    bc_builder_cli=$7 bc_builder_bin=$8 bc_builder_name=$9 bc_dir=${10} bc_run_tests=${11}
    mkdir -p "$bc_dir"
    step "$bc_name: building with $bc_builder_name"
    compile_with "$bc_builder_cli" "$bc_builder_bin" "$bc_src" "$bc_root" "$bc_dir/build1"
    step "$bc_name: building with itself, twice"
    compile_with "$bc_cli" "$bc_dir/build1" "$bc_src" "$bc_root" "$bc_dir/build2"
    compile_with "$bc_cli" "$bc_dir/build2" "$bc_src" "$bc_root" "$bc_dir/build3"
    cmp -s "$bc_dir/build2.$CW_EMITTED" "$bc_dir/build3.$CW_EMITTED" \
        || die "$bc_name: no fixpoint: $bc_dir/build2.$CW_EMITTED and build3.$CW_EMITTED differ (its output depends on how it was built)"
    cp "$bc_dir/build2" "$bc_dir/tachyonc"
    TEST_TOTAL="not run"
    [ "$bc_run_tests" = 1 ] || return 0
    run_suite "$bc_name" "$bc_tree" "$bc_tests" "$bc_dir"
}

# Runs the test suite of the tree <tree> with <dir>/tachyonc; sets
# TEST_TOTAL.
run_suite() { # <name> <tree> <tests> <dir>
    step "$1: running its test suite ($3)"
    if ! (cd "$2" && "./$3" -c "$4/tachyonc" -t "$HOST") >"$4/tests.log" 2>&1; then
        tail -40 "$4/tests.log" >&2
        die "$1: test suite failed (log: $4/tests.log)"
    fi
    TEST_TOTAL=$(awk '$1 == "total" { print $2 " passed, " $3 " xfail" }' "$4/tests.log")
}

SUMMARY="$WORK/summary"
: >"$SUMMARY"
note() {
    echo "  $*" >>"$SUMMARY"
}

# ---- The seed ----

# Builds the seed from <tree>/<SEED_DIR> (cached in <dir>); sets SEED.
build_seed() { # <tree> <dir> <description>
    if [ -n "$SEED_BIN" ]; then
        [ -x "$SEED_BIN" ] || die "--seed-bin $SEED_BIN is not an executable"
        SEED=$SEED_BIN
        note "seed     given binary $SEED_BIN"
        return
    fi
    [ -f "$1/$SEED_DIR/Cargo.toml" ] || die "no $SEED_DIR/ in $3"
    # Always through cargo: its target directory makes an unchanged seed a
    # no-op, and a changed working tree (--dev) is rebuilt. From inside the
    # seed's directory, so rustup honours its rust-toolchain.toml.
    step "seed: building the Rust compiler from $3"
    (cd "$1/$SEED_DIR" && cargo build --release --locked --quiet --target-dir "$2/target") \
        || die "cargo build of the seed ($3) failed"
    SEED="$2/target/release/tachyon"
    note "seed     Rust compiler from $3"
}

seed_commit=$(tag_commit "$SEED_TAG")
if [ -n "$seed_commit" ]; then
    seed_cache="$CACHE/$SEED_TAG-$(echo "$seed_commit" | cut -c1-12)"
    if [ ! -d "$seed_cache/tree" ]; then
        # (under the lock, extracted aside and renamed into place)
        mkdir -p "$seed_cache"
        lock "$seed_cache/tree"
        if [ ! -d "$seed_cache/tree" ]; then
            extract "$seed_commit" "$seed_cache/tree.building"
            mv "$seed_cache/tree.building" "$seed_cache/tree"
        fi
        unlock "$seed_cache/tree"
    fi
    build_seed "$seed_cache/tree" "$seed_cache" "tag '$SEED_TAG'"
elif [ $DEV -eq 1 ]; then
    build_seed "$ROOT" "$LOCAL_CACHE/seed-worktree" "the working tree (--dev)"
else
    die "tag '$SEED_TAG' not found; fetch the tags (git fetch --tags), or use --dev before it exists"
fi

# ---- The releases ----

# The last release of the chain (the one that builds HEAD, or --until's):
# its suite runs whatever the --history.
LAST_RELEASE=""
while IFS='|' read -r _ version tag _; do
    [ -n "$(tag_commit "$tag")" ] && LAST_RELEASE=$version
    [ "$version" = "$UNTIL" ] && break
done <"$WORK/releases"

TEST_TOTAL=""
PREV_BIN=$SEED
PREV_CLI=seed
PREV_NAME=seed
STOPPED=0

while IFS='|' read -r _ version tag compiler built_by cli tests _ root; do
    [ "$built_by" = "$PREV_NAME" ] \
        || die "release $version is built by '$built_by', but the previous step is '$PREV_NAME'"
    commit=$(tag_commit "$tag")
    if [ -z "$commit" ]; then
        [ $DEV -eq 1 ] || die "tag '$tag' (release $version) not found; fetch the tags (git fetch --tags), or use --dev before the release is tagged"
        step "$version: tag '$tag' not found, skipped (--dev)"
        note "$version    $tag not tagged yet: skipped"
        continue
    fi
    short=$(echo "$commit" | cut -c1-12)
    dir="$CACHE/$tag-$short"
    # (In the cache, `ok` holds the result of the release's suite;
    # `fixpoint` says it was built and reached its fixpoint.)
    run_tests=0
    if [ "$HISTORY" = full ] || [ "$version" = "$LAST_RELEASE" ]; then
        run_tests=1
    fi
    # (what the cache holds is read without the lock: `fixpoint` and `ok`
    # appear only once the entry is complete; anything else is decided
    # again under the lock, as another run may have built it meanwhile)
    if [ -f "$dir/ok" ]; then
        step "$version: $tag ($short), built and tested before (cached)"
        TEST_TOTAL=$(cat "$dir/ok")
    elif [ -f "$dir/fixpoint" ] && [ $run_tests -eq 0 ]; then
        step "$version: $tag ($short), built and its fixpoint checked before (cached)"
        TEST_TOTAL="not run (--history fast)"
    else
        lock "$dir"
        if [ -f "$dir/ok" ]; then
            step "$version: $tag ($short), built and tested by another run (cached)"
            TEST_TOTAL=$(cat "$dir/ok")
        elif [ -f "$dir/fixpoint" ] && [ $run_tests -eq 0 ]; then
            step "$version: $tag ($short), built by another run (cached)"
            TEST_TOTAL="not run (--history fast)"
        elif [ -f "$dir/fixpoint" ] && [ -x "$dir/tachyonc" ] && [ -d "$dir/tree" ]; then
            run_suite "$version" "$dir/tree" "$tests" "$dir" </dev/null
            echo "$TEST_TOTAL" >"$dir/ok.new"
            mv "$dir/ok.new" "$dir/ok"
        else
            # (built aside, in <dir>.building, then renamed into place)
            rm -rf "$dir.building"
            extract "$commit" "$dir.building/tree"
            build_and_check "$version" "$dir.building/tree" "$compiler" "$root" "$cli" "$tests" \
                "$PREV_CLI" "$PREV_BIN" "$PREV_NAME" "$dir.building" "$run_tests" </dev/null
            : >"$dir.building/fixpoint"
            if [ $run_tests -eq 1 ]; then
                echo "$TEST_TOTAL" >"$dir.building/ok"
            else
                TEST_TOTAL="not run (--history fast)"
            fi
            publish "$dir"
        fi
        unlock "$dir"
    fi
    note "$version    $tag $short, built by $PREV_NAME, fixpoint ok, tests: $TEST_TOTAL"
    PREV_BIN="$dir/tachyonc"
    PREV_CLI=$cli
    PREV_NAME=$version
    if [ "$version" = "$UNTIL" ]; then
        STOPPED=1
        break
    fi
done <"$WORK/releases"

FINAL=$PREV_BIN

# ---- HEAD ----

if [ $STOPPED -eq 0 ]; then
    head_dir="$LOCAL_CACHE/head"
    rm -rf "$head_dir"
    mkdir -p "$head_dir"
    if [ $WORKTREE -eq 1 ]; then
        head_desc="the working tree"
        head_tree=$ROOT
    else
        head_commit=$(git rev-parse HEAD)
        head_desc="HEAD $(echo "$head_commit" | cut -c1-12)"
        head_tree="$head_dir/tree"
        extract "$head_commit" "$head_tree"
    fi
    build_and_check head "$head_tree" "$HEAD_COMPILER" "$HEAD_ROOT" "$HEAD_CLI" "$HEAD_TESTS" \
        "$PREV_CLI" "$PREV_BIN" "$PREV_NAME" "$head_dir" "$RUN_HEAD_TESTS"
    [ "$RUN_HEAD_TESTS" = 1 ] || TEST_TOTAL="left to the caller (--no-head-tests)"
    note "head     $head_desc, built by $PREV_NAME, fixpoint ok, tests: $TEST_TOTAL"
    FINAL="$head_dir/tachyonc"
    mkdir -p "$ROOT/target"
    cp "$FINAL" "$ROOT/target/tachyonc"
    # (0.15) The tools binary: a compiler that passed its fixpoint and its
    # test suite, for querying and editing while target/tachyonc is under
    # test (an agent's own builds replace that one); replaced by rename, so
    # a query running at that moment keeps its file.
    if [ "$RUN_HEAD_TESTS" = 1 ]; then
        mkdir -p "$ROOT/target/tools"
        cp "$FINAL" "$ROOT/target/tools/tachyonc.new"
        mv -f "$ROOT/target/tools/tachyonc.new" "$ROOT/target/tools/tachyonc"
    fi
fi

if [ -n "$CROSS" ]; then
    # HEAD's compiler, built and tested here, compiles its own source for
    # the other host: the object of the compiler that runs there, which `cc
    # -lm` links there. Built there by itself, it must emit this object
    # again (bootstrap/aarch64-linux-check.sh checks it).
    step "head: cross-compiling itself for $CROSS"
    cross_dir="$LOCAL_CACHE/head/$CROSS"
    mkdir -p "$cross_dir" "$ROOT/target/$CROSS"
    "$FINAL" --target "$CROSS" "$head_tree/$HEAD_COMPILER/$HEAD_ROOT" -o "$cross_dir/tachyonc.o" \
        || die "the cross-compilation for $CROSS failed"
    cp "$cross_dir/tachyonc.o" "$ROOT/target/$CROSS/tachyonc.o"
    note "$CROSS    cross-compiled by head: $ROOT/target/$CROSS/tachyonc.o (link it there: cc -o tachyonc tachyonc.o -lm)"
    FINAL="$cross_dir/tachyonc.o"
fi

[ -z "$OUT" ] || cp "$FINAL" "$OUT"

echo
echo "tachyon bootstrap on $HOST${CROSS:+, for $CROSS}:"
cat "$SUMMARY"
if [ -n "$CROSS" ]; then
    echo "compiler for $CROSS: $ROOT/target/$CROSS/tachyonc.o${OUT:+, also $OUT}; for $HOST: $ROOT/target/tachyonc"
elif [ $STOPPED -eq 0 ]; then
    echo "compiler: $ROOT/target/tachyonc ($("$FINAL" --version))${OUT:+, also $OUT}"
else
    echo "compiler: $FINAL ($("$FINAL" --version))${OUT:+, also $OUT}"
fi
