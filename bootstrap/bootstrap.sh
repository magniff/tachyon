#!/bin/sh
# Builds the tachyon compiler from nothing but git, a Rust toolchain and a C
# compiler, release by release, following bootstrap/releases.toml:
#
#   1. the seed: the frozen Rust compiler, from the seed/ directory of the
#      `seed` tag, built with cargo;
#   2. every release, in order: built by the previous step's compiler, then
#      by itself; the two emitted outputs must be identical (the fixpoint),
#      and the release's own test suite must pass;
#   3. HEAD (or the working tree), the same way, built by the last release.
#
# Everything is built for the host, which is detected first; each release
# lists the hosts it supports. Only the host's tools are required: git,
# cargo, a C compiler (cc, or $CC) and POSIX utilities.
#
# Built steps are cached under target/bootstrap/<host>/, so a rerun only
# redoes HEAD. The final compiler is copied to target/tachyonc, where
# tests/run.sh looks for it.
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
#                      the chain for Intel Macs, run under Rosetta)
#   --seed-bin PATH    use this seed binary instead of building one
#   --cache DIR        the cache directory (default: target/bootstrap)
#   --clean            empty the cache first
#   --out PATH         also copy the final compiler here
#
# See docs/releases.md.

set -eu
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST="$ROOT/bootstrap/releases.toml"
CACHE="$ROOT/target/bootstrap"
WORKTREE=0
DEV=0
UNTIL=""
HOST=""
SEED_BIN=""
CLEAN=0
OUT=""

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
        -h|--help) sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option '$1' (see --help)" ;;
    esac
    shift
done

# ---- The host ----

# The host as a tachyon target name.
if [ -z "$HOST" ]; then
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) HOST=aarch64-macos ;;
        Darwin-x86_64) HOST=x86_64-macos ;;
        Linux-x86_64) HOST=x86_64-linux ;;
        *) die "unsupported host: $(uname -s) $(uname -m). tachyon builds on aarch64-macos (Apple silicon), x86_64-macos and x86_64-linux; another host needs a release with a backend for it (see docs/releases.md)." ;;
    esac
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
trap 'rm -rf "$WORK"' EXIT INT TERM

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

# ---- Git ----

cd "$ROOT"
git rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not a git repository"
CACHE="$CACHE/$HOST"
if [ $CLEAN -eq 1 ]; then
    step "cleaning $CACHE"
    rm -rf "$CACHE"
fi
mkdir -p "$CACHE"

tag_commit() { # <tag>: its commit, or nothing when the tag does not exist
    git rev-parse -q --verify "refs/tags/$1^{commit}" 2>/dev/null || true
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
        *)
            die "unknown compiler interface '$cw_cli' (bootstrap.sh needs to learn it)"
            ;;
    esac
}

# Builds the compiler in <tree>/<compiler> with <builder>, checks the
# fixpoint and runs the tree's test suite; leaves <dir>/tachyonc and sets
# TEST_TOTAL.
build_and_check() { # <name> <tree> <compiler> <root> <cli> <tests> <builder_cli> <builder_bin> <builder_name> <dir>
    bc_name=$1 bc_tree=$2 bc_src="$2/$3" bc_root=$4 bc_cli=$5 bc_tests=$6
    bc_builder_cli=$7 bc_builder_bin=$8 bc_builder_name=$9 bc_dir=${10}
    mkdir -p "$bc_dir"
    step "$bc_name: building with $bc_builder_name"
    compile_with "$bc_builder_cli" "$bc_builder_bin" "$bc_src" "$bc_root" "$bc_dir/build1"
    step "$bc_name: building with itself, twice"
    compile_with "$bc_cli" "$bc_dir/build1" "$bc_src" "$bc_root" "$bc_dir/build2"
    compile_with "$bc_cli" "$bc_dir/build2" "$bc_src" "$bc_root" "$bc_dir/build3"
    cmp -s "$bc_dir/build2.$CW_EMITTED" "$bc_dir/build3.$CW_EMITTED" \
        || die "$bc_name: no fixpoint: $bc_dir/build2.$CW_EMITTED and build3.$CW_EMITTED differ (its output depends on how it was built)"
    cp "$bc_dir/build2" "$bc_dir/tachyonc"
    step "$bc_name: running its test suite ($bc_tests)"
    if ! (cd "$bc_tree" && "./$bc_tests" -c "$bc_dir/tachyonc" -t "$HOST") >"$bc_dir/tests.log" 2>&1; then
        tail -40 "$bc_dir/tests.log" >&2
        die "$bc_name: test suite failed (log: $bc_dir/tests.log)"
    fi
    TEST_TOTAL=$(awk '$1 == "total" { print $2 " passed, " $3 " xfail" }' "$bc_dir/tests.log")
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
    [ -d "$seed_cache/tree" ] || extract "$seed_commit" "$seed_cache/tree"
    build_seed "$seed_cache/tree" "$seed_cache" "tag '$SEED_TAG'"
elif [ $DEV -eq 1 ]; then
    build_seed "$ROOT" "$CACHE/seed-worktree" "the working tree (--dev)"
else
    die "tag '$SEED_TAG' not found; fetch the tags (git fetch --tags), or use --dev before it exists"
fi

# ---- The releases ----

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
    if [ -f "$dir/ok" ]; then
        step "$version: $tag ($short), built and tested before (cached)"
        TEST_TOTAL=$(cat "$dir/ok")
    else
        extract "$commit" "$dir/tree"
        build_and_check "$version" "$dir/tree" "$compiler" "$root" "$cli" "$tests" \
            "$PREV_CLI" "$PREV_BIN" "$PREV_NAME" "$dir" </dev/null
        echo "$TEST_TOTAL" >"$dir/ok"
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
    head_dir="$CACHE/head"
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
        "$PREV_CLI" "$PREV_BIN" "$PREV_NAME" "$head_dir"
    note "head     $head_desc, built by $PREV_NAME, fixpoint ok, tests: $TEST_TOTAL"
    FINAL="$head_dir/tachyonc"
    mkdir -p "$ROOT/target"
    cp "$FINAL" "$ROOT/target/tachyonc"
fi

[ -z "$OUT" ] || cp "$FINAL" "$OUT"

echo
echo "tachyon bootstrap on $HOST:"
cat "$SUMMARY"
if [ $STOPPED -eq 0 ]; then
    echo "compiler: $ROOT/target/tachyonc ($("$FINAL" --version))${OUT:+, also $OUT}"
else
    echo "compiler: $FINAL ($("$FINAL" --version))${OUT:+, also $OUT}"
fi
