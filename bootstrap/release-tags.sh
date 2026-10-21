#!/bin/sh
# Prints the tags of the releases in bootstrap/releases.toml, oldest first,
# in the file's order (bootstrap.sh checks that it is the order of the
# versions, compared as numbers). Scripts take releases from here and never
# sort versions or tags as text: v0.10.0 comes after v0.9.0.
#
# usage: bootstrap/release-tags.sh [--bins | --head FIELD]
#
#   --bins        (0.21) each tag and its compiler's name (`bin`; for 0.24's
#                 rename), `TAG BIN` per line
#   --head FIELD  (0.21) a field of [head]: bin, ext, root, compiler
#
# A release without `bin` or `ext` is one up to 0.23: tachyonc and .tach.
M="$(dirname "$0")/releases.toml"
case "${1:-}" in
    --bins)
        awk -F'"' '
            function flush() { if (tag != "") print tag " " (bin != "" ? bin : "tachyonc"); tag = ""; bin = "" }   # (up to 0.23)
            /^\[\[release\]\]/ { flush(); r = 1; next }
            /^\[(seed|head)\]/ { flush(); r = 0; next }
            r && /^tag[ \t]*=/ { tag = $2 }
            r && /^bin[ \t]*=/ { bin = $2 }
            END { flush() }' "$M" ;;
    --head)
        [ $# -ge 2 ] || { echo "usage: bootstrap/release-tags.sh --head FIELD" >&2; exit 2; }
        awk -F'"' -v f="$2" '
            /^\[head\]/ { h = 1; next }
            /^\[/ { h = 0 }
            h && $1 ~ "^" f "[ \t]*=" { v = $2 }
            END {
                if (v == "" && f == "bin") v = "tachyonc"   # (up to 0.23)
                if (v == "" && f == "ext") v = ".tach"      # (up to 0.23)
                print v
            }' "$M" ;;
    "")
        awk -F'"' '/^\[\[release\]\]/ { r = 1 } /^\[(seed|head)\]/ { r = 0 } r && /^tag[ \t]*=/ { print $2 }' "$M" ;;
    *) echo "usage: bootstrap/release-tags.sh [--bins | --head FIELD]" >&2; exit 2 ;;
esac
