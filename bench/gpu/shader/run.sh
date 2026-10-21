#!/bin/sh
# The shader compiler's translation bench (docs/design/gpu.md §5: "WGSL ->
# MSL: no slower than naga"): wgslc and naga 29 translate the same
# corpus, WGSL to MSL with bounds checks, N times each; the median per
# file and their sum. The corpus: tests/wgsl/cases (those that translate),
# wgpu's own shaders from the cargo registry when it has them, and
# large.wgsl, made here (cells_fs.wgsl's functions, 100 times over).
# naga is built offline from the registry (bench/gpu/shader/naga); without
# cargo or the crate, only wgslc runs.
#
# usage: bench/gpu/shader/run.sh [-c COMPILER] [-n N]
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
COMPILER="$ROOT/target/tachyonc"
N=200
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -n) N=$2; shift 2 ;;
        *) echo "usage: $0 [-c COMPILER] [-n N]" >&2; exit 2 ;;
    esac
done
WORK=$(mktemp -d "${TMPDIR:-/tmp}/shaderbench.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
"$COMPILER" "$ROOT/tools/wgslc/main.tach" -O2 -o "$WORK/wgslc" >/dev/null || exit 1
mkdir "$WORK/corpus"
for f in "$ROOT"/tests/wgsl/cases/*.wgsl; do
    case "$(basename "$f")" in err_*) continue ;; esac
    cp "$f" "$WORK/corpus/"
done
REG="$HOME/.cargo/registry/src"
for p in wgpu-hal-29.0.4/examples/halmark/shader.wgsl wgpu-29.0.4/src/util/blit.wgsl; do
    for d in "$REG"/*/; do
        [ -f "$d$p" ] && cp "$d$p" "$WORK/corpus/wgpu_$(basename "$(dirname "$p")").wgsl" && break
    done
done
# large.wgsl: the fragment stage's helpers renamed 100 times, an entry
# point calling them all
awk -v n=100 '
    /^fn deco\(/ { grab = 1 }
    grab { body = body $0 "\n" }
    grab && /^}$/ { grab = 0 }
    /^(struct U|@group\(0\) @binding\(0\))/ { head = head $0 "\n"; inu = /struct U/ }
    inu && !/^struct U/ { head = head $0 "\n"; if ($0 ~ /^}$/) inu = 0 }
    END {
        printf "%s\n", head
        for (i = 0; i < n; i++) { b = body; gsub(/fn deco\(/, "fn deco" i "(", b); print b }
        print "@group(0) @binding(1) var<storage, read_write> out: array<f32>;"
        print "@compute @workgroup_size(64)"
        print "fn main(@builtin(global_invocation_id) id: vec3<u32>) {"
        print "    var acc = 0.0;"
        for (i = 0; i < n; i++) print "    acc += deco" i "(id.x & 31u, i32(id.y), i32(id.x));"
        print "    out[id.x] = acc;"
        print "}"
    }' "$ROOT/tests/wgsl/cases/cells_fs.wgsl" >"$WORK/corpus/large.wgsl"
"$WORK/wgslc" check "$WORK/corpus/large.wgsl" || exit 1
NAGA=""
if command -v cargo >/dev/null 2>&1; then
    if (cd "$HERE/naga" && CARGO_TARGET_DIR="$WORK/cargo" cargo build --release --offline -q) >"$WORK/naga.build" 2>&1; then
        NAGA="$WORK/cargo/release/nagabench"
    else
        echo "naga: not built offline ($(tail -1 "$WORK/naga.build"))"
    fi
fi
echo "wgslc (median of $N, WGSL to MSL):"
"$WORK/wgslc" bench -n "$N" "$WORK"/corpus/*.wgsl | sed "s|$WORK/corpus/||"
if [ -n "$NAGA" ]; then
    echo "naga 29.0.4 (median of $N, WGSL to MSL):"
    "$NAGA" -n "$N" "$WORK"/corpus/*.wgsl 2>/dev/null | sed "s|$WORK/corpus/||"
fi
