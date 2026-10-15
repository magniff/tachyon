#!/bin/sh
# Builds the compiler of this tree into target/tachyonc, as
# bootstrap/bootstrap.sh --dev does for HEAD: compiled by the previous
# release (target/builder/tachyonc), then by itself twice; the two
# outputs of the self-builds must be identical (the fixpoint).
#
# This copy has no release tags or bootstrap cache, so it stands in for
# bootstrap/bootstrap.sh here (the agent eval's compiler tasks).
#
# usage: bootstrap/eval-build.sh [--quick]
#   --quick   one build by the previous release and one by itself; no
#             fixpoint check (faster; the grading always checks it)
# Environment: EVAL_BUILDER overrides target/builder/tachyonc; CC links.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
QUICK=0
[ "${1:-}" = --quick ] && QUICK=1
BUILDER=${EVAL_BUILDER:-$ROOT/target/builder/tachyonc}
[ -x "$BUILDER" ] || { echo "eval-build: no previous release at $BUILDER" >&2; exit 1; }
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) HOST=aarch64-macos; LINK="-arch arm64" ;;
    Darwin-x86_64) HOST=x86_64-macos; LINK="-arch x86_64" ;;
    Linux-x86_64) HOST=x86_64-linux; LINK="" ;;
    Linux-aarch64) HOST=aarch64-linux; LINK="" ;;
    *) echo "eval-build: unsupported host" >&2; exit 1 ;;
esac
CC=${CC:-cc}
OUT=$ROOT/target/eval-build
mkdir -p "$OUT"
build() { # <compiler> <name>
    echo "==> building with $2" >&2
    "$1" --target "$HOST" compiler/src/main.tach -o "$OUT/$3.o" \
        || { echo "eval-build: $2 failed to compile compiler/src" >&2; exit 1; }
    # shellcheck disable=SC2086
    "$CC" $LINK -o "$OUT/$3" "$OUT/$3.o" -lm \
        || { echo "eval-build: $CC failed to link" >&2; exit 1; }
}
build "$BUILDER" "the previous release" build1
build "$OUT/build1" "itself (build1)" build2
if [ $QUICK -eq 0 ]; then
    build "$OUT/build2" "itself (build2)" build3
    cmp -s "$OUT/build2.o" "$OUT/build3.o" \
        || { echo "eval-build: no fixpoint: build2.o and build3.o differ (the compiler's output depends on how it was built)" >&2; exit 1; }
fi
# a new file, not cp over the old one: macOS SIGKILLs a signed binary overwritten in
# place (0.17 validation round: one agent's target/tachyonc died with 137 on every call)
rm -f "$ROOT/target/tachyonc"
cp "$OUT/build2" "$ROOT/target/tachyonc"
echo "compiler: target/tachyonc ($("$ROOT/target/tachyonc" --version 2>&1 | head -1))" >&2
