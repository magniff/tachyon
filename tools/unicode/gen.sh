#!/bin/sh
# Remakes std's Unicode tables, compiler/std/unicode/tables.tach, from the
# Unicode Character Database at the version tools/unicode/ucd.lock pins
# (0.20): downloads what is missing into the cache (tools/unicode/fetch.sh,
# which checks every file's SHA-256), builds tools/unicode/gen.tach and runs
# it. Then run compiler/std/embed.sh and rebuild the compiler.
#
# usage: tools/unicode/gen.sh [--check] [-c COMPILER]
#
#   --check       write nothing: fail when tables.tach is not what the
#                 generator makes; when the cache does not hold the files,
#                 say so and succeed (the gate runs this; nothing is
#                 downloaded)
#   -c COMPILER   the tachyonc to build the generator with (default:
#                 target/tachyonc)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
COMPILER="$ROOT/target/tachyonc"
CHECK=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK=--check; shift ;;
        -c) COMPILER=$2; shift 2 ;;
        *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
version=$(awk '$1 == "version" { print $2 }' "$ROOT/tools/unicode/ucd.lock")
cache=${TACHYON_UCD_CACHE:-$HOME/.cache/tachyon/ucd}
if [ -n "$CHECK" ]; then
    for f in $(awk '$1 == "file" { print $2 }' "$ROOT/tools/unicode/ucd.lock"); do
        if [ ! -s "$cache/$version/$(basename "$f")" ]; then
            echo "note unicode.no-cache: no Unicode $version files in $cache: tables.tach not checked" >&2
            echo "try: tools/unicode/fetch.sh" >&2
            exit 0
        fi
    done
fi
dir=$("$ROOT/tools/unicode/fetch.sh")
tmp=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-ucd.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
"$COMPILER" -O1 "$ROOT/tools/unicode/gen.tach" -o "$tmp/gen"
"$tmp/gen" $CHECK "$dir" "$ROOT"
