#!/bin/sh
# bench/gpu (0.22, docs/design/gpu.md §5): the CPU cost of encoding 10,000
# draws with a bind group change every 10 into one render pass, on Metal:
#
#   objc         draws.m, clang -O2 (the baseline)
#   vole      draws.vl, std::gpu with its contracts (goal: within 10%
#                of objc, faster than wgpu)
#   vole-hal  draws_hal.vl, std::gpu::hal::metal directly: the
#                difference from vole is what the contracts cost (goal:
#                under 3%)
#   wgpu         wgpu/ (Rust, wgpu 30.0.1, built offline from ~/.cargo's
#                cache; skipped when it does not build)
#
# Each program prints the median and the minimum of 60 encodings; the
# programs run ROUNDS times in turn, and the table has the median of
# their medians and the least minimum, in microseconds.
#
# usage: bench/gpu/run.sh [-c COMPILER] [-r ROUNDS]

set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
COMPILER="$ROOT/target/volec"
ROUNDS=5
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -r) ROUNDS=$2; shift 2 ;;
        *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
[ "$(uname -s)-$(uname -m)" = "Darwin-arm64" ] || { echo "bench/gpu: Metal needs macOS on arm64"; exit 0; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-gpubench.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
B="$ROOT/bench/gpu"
clang -O2 -fobjc-arc "$B/draws.m" -framework Metal -framework Foundation -o "$WORK/objc" || exit 1
"$COMPILER" -O2 "$B/draws.vl" -l objc -o "$WORK/vole" >/dev/null 2>&1 || exit 1
"$COMPILER" -O2 "$B/draws_hal.vl" -l objc -o "$WORK/vole-hal" >/dev/null 2>&1 || exit 1
progs="objc vole vole-hal"
if command -v cargo >/dev/null 2>&1 &&
   CARGO_TARGET_DIR="$WORK/cargo" cargo build -q --release --offline --manifest-path "$B/wgpu/Cargo.toml" >"$WORK/cargo.log" 2>&1; then
    cp "$WORK/cargo/release/wgpu-draws" "$WORK/wgpu"
    progs="$progs wgpu"
else
    echo "(wgpu: did not build offline; see cargo build --offline)"
fi
r=0
while [ $r -lt "$ROUNDS" ]; do
    for p in $progs; do
        "$WORK/$p" | sed -n 's/.*median \([0-9]*\) us, min \([0-9]*\) us.*/\1 \2/p' | sed "s/^/$p /" >>"$WORK/runs"
    done
    r=$((r + 1))
done
echo "10000 draws, a bind group every 10 ($ROUNDS rounds; load: $(uptime | sed 's/.*load averages*: //'))"
printf "  %-12s %10s %10s %8s\n" program median min vs-objc
base=$(awk '$1 == "objc" { print $2 }' "$WORK/runs" | sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }')
for p in $progs; do
    med=$(awk -v p="$p" '$1 == p { print $2 }' "$WORK/runs" | sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }')
    min=$(awk -v p="$p" '$1 == p { print $3 }' "$WORK/runs" | sort -n | head -1)
    printf "  %-12s %10s %10s %7.2fx\n" "$p" "$med" "$min" "$(echo "$med $base" | awk '{ print $1 / $2 }')"
done
