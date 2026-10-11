#!/usr/bin/env bash
# Builds the tachyon compiler from nothing but git, a Rust toolchain and
# clang, release by release, following bootstrap/releases.toml:
#
#   1. stage0: the frozen Rust compiler, from the stage0/ directory of the
#      first release's tag, built with cargo;
#   2. every release, in order: built by the previous step's compiler, then
#      by itself; the two emitted outputs must be identical (the fixpoint),
#      and the release's own test suite must pass;
#   3. HEAD (or the working tree), the same way, built by the last release.
#
# Built releases are cached under target/bootstrap/<tag>-<commit>, so a rerun
# only redoes HEAD. The final compiler is copied to target/tachyonc, where
# tests/run.sh looks for it.
#
# usage: bootstrap/bootstrap.sh [options]
#
#   --worktree         step 3 uses the working tree instead of HEAD
#   --until VERSION    stop after this release (skip later ones and HEAD)
#   --dev              for testing before the release tags exist: releases
#                      whose tag is missing are skipped, stage0 is built from
#                      the working tree, and step 3 uses the working tree
#   --stage0-bin PATH  use this stage0 binary instead of building one
#   --cache DIR        the cache directory (default: target/bootstrap)
#   --clean            empty the cache first
#   --out PATH         also copy the final compiler here
#
# See docs/releases.md.

set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/bootstrap/releases.toml"
CACHE="$ROOT/target/bootstrap"
WORKTREE=0
DEV=0
UNTIL=""
STAGE0_BIN=""
CLEAN=0
OUT=""

die() {
    echo "bootstrap: error: $*" >&2
    exit 1
}

step() {
    echo "==> $*" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --worktree) WORKTREE=1 ;;
        --dev) DEV=1; WORKTREE=1 ;;
        --until) shift; [[ $# -gt 0 ]] || die "--until needs a version"; UNTIL="$1" ;;
        --stage0-bin) shift; [[ $# -gt 0 ]] || die "--stage0-bin needs a path"; STAGE0_BIN="$1" ;;
        --cache) shift; [[ $# -gt 0 ]] || die "--cache needs a directory"; CACHE="$1" ;;
        --clean) CLEAN=1 ;;
        --out) shift; [[ $# -gt 0 ]] || die "--out needs a path"; OUT="$1" ;;
        -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option '$1' (see --help)" ;;
    esac
    shift
done

# ---- The manifest ----

# One line per entry, fields separated by '|' (hosts comma-separated):
#   release|<version>|<tag>|<compiler>|<built_by>|<cli>|<tests>|<hosts>
#   head|<compiler>|<cli>|<tests>|<hosts>
read_manifest() {
    awk '
        function flush() {
            if (section == "release")
                print "release|" v["version"] "|" v["tag"] "|" v["compiler"] "|" v["built_by"] "|" v["cli"] "|" v["tests"] "|" v["hosts"]
            if (section == "head")
                print "head|" v["compiler"] "|" v["cli"] "|" v["tests"] "|" v["hosts"]
            split("", v)
        }
        /^[ \t]*#/ || /^[ \t]*$/ { next }
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
    ' "$MANIFEST"
}

[[ -f "$MANIFEST" ]] || die "missing $MANIFEST"
MANIFEST_LINES="$(read_manifest)"
if grep -q '^bad|' <<<"$MANIFEST_LINES"; then
    die "cannot parse $MANIFEST, line $(grep '^bad|' <<<"$MANIFEST_LINES" | head -1 | cut -d'|' -f2-)"
fi
HEAD_LINE="$(grep '^head|' <<<"$MANIFEST_LINES" || true)"
[[ -n "$HEAD_LINE" ]] || die "$MANIFEST has no [head] section"
grep -q '^release|' <<<"$MANIFEST_LINES" || die "$MANIFEST lists no release"
if [[ -n "$UNTIL" ]] && ! grep -q "^release|$UNTIL|" <<<"$MANIFEST_LINES"; then
    die "no release $UNTIL in $MANIFEST"
fi

# ---- Host and tools ----

HOST="$(uname -s | tr 'A-Z' 'a-z')-$(uname -m)"

check_host() { # <what> <comma-separated hosts>
    case ",$2," in
        *",$HOST,"*) ;;
        *) die "$1 runs on: $2; this host is $HOST. Bootstrapping here needs a release with a backend for $HOST." ;;
    esac
}

while IFS='|' read -r kind version _tag _compiler _built _cli _tests hosts; do
    [[ "$kind" == release ]] && check_host "release $version" "$hosts"
done <<<"$MANIFEST_LINES"
[[ -z "$UNTIL" ]] && check_host "the compiler at HEAD" "$(cut -d'|' -f5 <<<"$HEAD_LINE")"

need_tool() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' not found; $2"
}
need_tool git "releases are read from git tags"
CC_BIN="${CC:-clang}"
need_tool "$CC_BIN" "it assembles and links the compiler's output (set CC to override)"
if [[ -z "$STAGE0_BIN" ]]; then
    need_tool cargo "stage0 is the Rust compiler (install Rust from https://rustup.rs)"
fi

cd "$ROOT"
git rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not a git repository"
if [[ $CLEAN -eq 1 ]]; then
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

# Compiles the .tach files of <src> into the executable <out> with the
# compiler <bin>, invoked through interface <cli> ("stage0" or a release's).
compile_with() { # <cli> <bin> <src> <out>
    local cli="$1" bin="$2" src="$3" out="$4"
    local files=("$src"/*.tach)
    [[ -e "${files[0]}" ]] || die "no .tach files in $src"
    case "$cli" in
        stage0)
            # stage0 compiles one file: the sources together.
            cat "${files[@]}" >"$out.all.tach"
            "$bin" build "$out.all.tach" -o "$out" || die "stage0 failed to compile $src"
            ;;
        tachyonc-v1)
            "$bin" "${files[@]}" -o "$out.s" || die "$bin failed to compile $src"
            "$CC_BIN" -arch arm64 -o "$out" "$out.s" -lm || die "$CC_BIN failed to link $out.s"
            ;;
        *)
            die "unknown compiler interface '$cli' (bootstrap.sh needs to learn it)"
            ;;
    esac
}

# Builds the compiler in <tree>/<compiler> with <builder>, checks the
# fixpoint and runs the tree's test suite; leaves <dir>/tachyonc.
build_and_check() { # <name> <tree> <compiler> <cli> <tests> <builder_cli> <builder_bin> <builder_name> <dir>
    local name="$1" tree="$2" compiler="$3" cli="$4" tests="$5"
    local builder_cli="$6" builder_bin="$7" builder_name="$8" dir="$9"
    local src="$tree/$compiler"
    mkdir -p "$dir"
    step "$name: building with $builder_name"
    compile_with "$builder_cli" "$builder_bin" "$src" "$dir/build1"
    step "$name: building with itself, twice"
    compile_with "$cli" "$dir/build1" "$src" "$dir/build2"
    compile_with "$cli" "$dir/build2" "$src" "$dir/build3"
    cmp -s "$dir/build2.s" "$dir/build3.s" \
        || die "$name: no fixpoint: $dir/build2.s and build3.s differ (its output depends on how it was built)"
    cp "$dir/build2" "$dir/tachyonc"
    step "$name: running its test suite ($tests)"
    (cd "$tree" && CC="$CC_BIN" "./$tests" -c "$dir/tachyonc") >"$dir/tests.log" 2>&1 \
        || { tail -40 "$dir/tests.log" >&2; die "$name: test suite failed (log: $dir/tests.log)"; }
    TEST_TOTAL="$(grep '^  total' "$dir/tests.log" | awk '{print $2 " passed, " $3 " xfail"}')"
}

# ---- stage0 ----

STAGE0=""
# Builds stage0 from <tree>/stage0 (cached in <dir>); sets STAGE0.
build_stage0() { # <tree> <dir> <description>
    if [[ -n "$STAGE0_BIN" ]]; then
        [[ -x "$STAGE0_BIN" ]] || die "--stage0-bin $STAGE0_BIN is not an executable"
        STAGE0="$STAGE0_BIN"
        SUMMARY+=("stage0   given binary $STAGE0_BIN")
        return
    fi
    [[ -f "$1/stage0/Cargo.toml" ]] || die "no stage0/ in $3"
    if [[ ! -x "$2/tachyon" ]]; then
        step "stage0: building the Rust compiler from $3"
        # From inside stage0/, so rustup honours its rust-toolchain.toml.
        (cd "$1/stage0" && cargo build --release --locked --quiet --target-dir "$2/target") \
            || die "cargo build of stage0 ($3) failed"
        cp "$2/target/release/tachyon" "$2/tachyon"
    else
        step "stage0: from $3, cached"
    fi
    STAGE0="$2/tachyon"
    SUMMARY+=("stage0   Rust compiler from $3")
}

# ---- The releases ----

SUMMARY=()
TEST_TOTAL=""
PREV_BIN=""
PREV_CLI=""
PREV_NAME=""
STOPPED=0

while IFS='|' read -r kind version tag compiler built_by cli tests _hosts; do
    [[ "$kind" == release ]] || continue
    commit="$(tag_commit "$tag")"
    if [[ -z "$commit" ]]; then
        [[ $DEV -eq 1 ]] || die "tag '$tag' (release $version) not found; fetch the tags (git fetch --tags), or use --dev before the release is tagged"
        step "$version: tag '$tag' not found, skipped (--dev)"
        SUMMARY+=("$version    $tag not tagged yet: skipped")
        continue
    fi
    dir="$CACHE/$tag-${commit:0:12}"
    if [[ "$built_by" == stage0 ]]; then
        [[ -z "$PREV_NAME" ]] || die "release $version is built by stage0, but it is not the first release"
        [[ -d "$dir/tree" ]] || extract "$commit" "$dir/tree"
        build_stage0 "$dir/tree" "$dir/stage0" "$tag"
        PREV_BIN="$STAGE0"
        PREV_CLI="stage0"
        PREV_NAME="stage0"
    elif [[ "$built_by" != "$PREV_NAME" ]]; then
        die "release $version is built by '$built_by', but the previous step is '${PREV_NAME:-nothing}'"
    fi
    if [[ -f "$dir/ok" ]]; then
        step "$version: $tag (${commit:0:12}), built and tested before (cached)"
        TEST_TOTAL="$(cat "$dir/ok")"
    else
        extract "$commit" "$dir/tree"
        build_and_check "$version" "$dir/tree" "$compiler" "$cli" "$tests" \
            "$PREV_CLI" "$PREV_BIN" "$PREV_NAME" "$dir"
        echo "$TEST_TOTAL" >"$dir/ok"
    fi
    SUMMARY+=("$version    $tag ${commit:0:12}, built by $PREV_NAME, fixpoint ok, tests: $TEST_TOTAL")
    PREV_BIN="$dir/tachyonc"
    PREV_CLI="$cli"
    PREV_NAME="$version"
    if [[ "$version" == "$UNTIL" ]]; then
        STOPPED=1
        break
    fi
done <<<"$MANIFEST_LINES"

FINAL="$PREV_BIN"

# ---- HEAD ----

if [[ $STOPPED -eq 0 ]]; then
    IFS='|' read -r _ head_compiler head_cli head_tests _head_hosts <<<"$HEAD_LINE"
    head_dir="$CACHE/head"
    rm -rf "$head_dir"
    mkdir -p "$head_dir"
    if [[ $WORKTREE -eq 1 ]]; then
        head_desc="the working tree"
        head_tree="$ROOT"
    else
        head_commit="$(git rev-parse HEAD)"
        head_desc="HEAD ${head_commit:0:12}"
        head_tree="$head_dir/tree"
        extract "$head_commit" "$head_tree"
    fi
    if [[ -z "$PREV_NAME" ]]; then
        # No release built yet (--dev before the first tag): stage0 comes
        # from the tree itself.
        build_stage0 "$head_tree" "$CACHE/stage0-worktree" "$head_desc"
        PREV_BIN="$STAGE0"
        PREV_CLI="stage0"
        PREV_NAME="stage0"
    fi
    build_and_check "head" "$head_tree" "$head_compiler" "$head_cli" "$head_tests" \
        "$PREV_CLI" "$PREV_BIN" "$PREV_NAME" "$head_dir"
    SUMMARY+=("head     $head_desc, built by $PREV_NAME, fixpoint ok, tests: $TEST_TOTAL")
    FINAL="$head_dir/tachyonc"
    cp "$FINAL" "$ROOT/target/tachyonc"
fi

[[ -n "$OUT" ]] && cp "$FINAL" "$OUT"

echo
echo "tachyon bootstrap on $HOST:"
for line in "${SUMMARY[@]}"; do
    echo "  $line"
done
if [[ $STOPPED -eq 0 ]]; then
    echo "compiler: $ROOT/target/tachyonc ($("$FINAL" --version))${OUT:+, also $OUT}"
else
    echo "compiler: $FINAL ($("$FINAL" --version))${OUT:+, also $OUT}"
fi
