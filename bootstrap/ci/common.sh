# What bootstrap/linux-check.sh and bootstrap/aarch64-linux-check.sh share
# (sourced; POSIX sh): their images, built only when their recipe changed;
# the tree they check; the CPUs they get; stopping their container.
#
# The caller sets ROOT, and calls die() on errors.

# Builds docker image <image> for <platform> from <dockerfile>, whose
# build context is the given files (and nothing else), unless the image
# was built from that same recipe already (a label on it holds the
# checksum of the Dockerfile and the files) and REBUILD_IMAGE is not 1. The
# base image is pinned by the digest of its manifest for the platform: the
# legacy builder takes a multi-platform tag for the machine's own platform
# once that one is stored (as the other Linux check stores it).
ensure_image() { # <image> <platform> <dockerfile> [context files...]
    ei_image=$1 ei_platform=$2 ei_dockerfile=$3
    shift 3
    ei_recipe=$(cat "$ei_dockerfile" "$@" | cksum | awk '{ print $1 "-" $2 }')
    ei_have=$(docker image inspect -f '{{ index .Config.Labels "vole.recipe" }}' "$ei_image" 2>/dev/null || true)
    if [ "$ei_have" = "$ei_recipe" ] && [ "${REBUILD_IMAGE:-0}" != 1 ]; then
        echo "==> the image $ei_image ($ei_platform) is up to date" >&2
        return 0
    fi
    echo "==> building the image $ei_image ($ei_platform)" >&2
    ei_base=$(docker manifest inspect debian:bookworm-slim | awk -v arch="${ei_platform#linux/}" '
        /"digest"/ { d = $2; gsub(/[",]/, "", d) }
        /"architecture"/ { a = $2; gsub(/[",]/, "", a); if (a == arch && !found) { print d; found = 1 } }')
    [ -n "$ei_base" ] || die "no $ei_platform manifest of debian:bookworm-slim"
    # (a context of its own: only the files the Dockerfile copies)
    ei_ctx=$(mktemp -d "${TMPDIR:-/tmp}/vole-image.XXXXXX")
    [ $# -eq 0 ] || cp "$@" "$ei_ctx/"
    if ! docker build --quiet --platform "$ei_platform" --build-arg BASE="debian@$ei_base" \
        --label "vole.recipe=$ei_recipe" -t "$ei_image" -f "$ei_dockerfile" "$ei_ctx" >/dev/null; then
        rm -rf "$ei_ctx"
        die "docker build of $ei_image failed"
    fi
    rm -rf "$ei_ctx"
}

# Puts the tree to check in <dir>/src: a clone of the repository (HEAD and
# the tags) or, if WORKTREE is 1, the working tree (tracked and untracked
# files, not ignored ones) over it; committed on top of HEAD when <commit>
# is 1 (for a container that clones it again).
snapshot() { # <dir> <commit>
    git clone --quiet --no-local "$ROOT" "$1/src"
    [ "${WORKTREE:-0}" = 1 ] || return 0
    echo "==> snapshotting the working tree" >&2
    (cd "$1/src" && git ls-files -z | xargs -0 rm -f)
    (cd "$ROOT" && git ls-files --cached --others --exclude-standard \
        | while IFS= read -r f; do [ -e "$f" ] && printf '%s\n' "$f"; done) >"$1/files"
    (cd "$ROOT" && tar -c -f - -T "$1/files") | (cd "$1/src" && tar -x -f -)
    [ "$2" = 1 ] || return 0
    (cd "$1/src" && git add -A \
        && git -c user.name=snapshot -c user.email=snapshot@localhost \
            commit --quiet --allow-empty -m "working tree snapshot")
}

# CPUS, at most what docker has (its VM's CPUs, with colima: `colima start
# --cpu N`).
clamp_cpus() {
    cc_have=$(docker info --format '{{.NCPU}}' 2>/dev/null || echo "")
    case "$cc_have" in ''|*[!0-9]*) return 0 ;; esac
    if [ "$CPUS" -gt "$cc_have" ]; then
        echo "==> docker has $cc_have CPUs: the container gets $cc_have, not $CPUS (colima start --cpu N gives it more)" >&2
        CPUS=$cc_have
    fi
}

# The container's name, and its removal however the script ends (an
# interrupted `docker run` may leave its container running).
CONTAINER="vole-check-$$-$(date +%s)"
stop_container() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
