#!/bin/sh
# Downloads the Unicode Character Database files that tools/unicode/gen.vl
# reads, at the version pinned in tools/unicode/ucd.lock, into a cache
# outside the tree, and checks each against its SHA-256 in the lock.
#
# usage: tools/unicode/fetch.sh [--lock]
#
#   (no option)  download what is missing, then check every file
#   --lock       (only when moving to a new Unicode version) download the
#                files the lock names at the version on its first line and
#                rewrite the lock's sums from what was downloaded
#
# The cache: $VOLE_UCD_CACHE, else $HOME/.cache/vole/ucd; the files
# go to CACHE/VERSION/, flat (auxiliary/ and emoji/ dropped). Prints the
# directory on success. Needs curl and shasum (macOS) or sha256sum.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
lock="$here/ucd.lock"
version=$(awk '$1 == "version" { print $2 }' "$lock")
cache=${VOLE_UCD_CACHE:-$HOME/.cache/vole/ucd}
dir="$cache/$version"
mkdir -p "$dir"

sum() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{ print $1 }'
    else shasum -a 256 "$1" | awk '{ print $1 }'; fi
}

relock=0
[ "${1:-}" = "--lock" ] && relock=1

tmp=$(mktemp "$lock.XXXXXX")
trap 'rm -f "$tmp"' EXIT
bad=0
# Lines of the lock: `version V`, then `file PATH SHA256` (PATH under
# https://www.unicode.org/Public/V/).
while read -r kind path want; do
    case "$kind" in
        file) ;;
        *) printf '%s %s%s\n' "$kind" "$path" "${want:+ $want}" >>"$tmp"; continue ;;
    esac
    name=$(basename "$path")
    if [ ! -s "$dir/$name" ] || [ $relock = 1 ]; then
        curl -fsSL "https://www.unicode.org/Public/$version/$path" -o "$dir/$name.part"
        mv "$dir/$name.part" "$dir/$name"
    fi
    got=$(sum "$dir/$name")
    if [ $relock = 1 ]; then
        want=$got
    elif [ "$got" != "$want" ]; then
        echo "error ucd.sum: $dir/$name has SHA-256 $got, the lock says $want" >&2
        echo "try: rm $dir/$name && tools/unicode/fetch.sh" >&2
        bad=1
    fi
    printf 'file %s %s\n' "$path" "$want" >>"$tmp"
done <"$lock"
[ $bad = 0 ] || exit 1
if [ $relock = 1 ]; then mv "$tmp" "$lock"; fi
echo "$dir"
