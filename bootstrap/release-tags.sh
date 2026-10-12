#!/bin/sh
# Prints the tags of the releases in bootstrap/releases.toml, oldest first,
# in the file's order (bootstrap.sh checks that it is the order of the
# versions, compared as numbers). Scripts take releases from here and never
# sort versions or tags as text: v0.10.0 comes after v0.9.0.
#
# usage: bootstrap/release-tags.sh
awk -F'"' '/^\[\[release\]\]/ { r = 1 } /^\[(seed|head)\]/ { r = 0 } r && /^tag[ \t]*=/ { print $2 }' \
    "$(dirname "$0")/releases.toml"
