#!/bin/sh
# (0.21.1) std's core, the sections of std every program reads (lexed,
# parsed and checked even for a hello world), stays small: 0.20 had 660 KB
# of its 750 KB there, unnoticed, through names std's modules share
# (compiler/std/index.awk). Run by tests/run.sh.
#
# usage: tests/std/core_sections.sh [MAX_BYTES]
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# (104 KB in 0.21.1: room for std's own growth, not for its modules')
MAX=${1:-131072}
report=$(sh "$ROOT/compiler/std/embed.sh" --core) || { echo "error: compiler/std/embed.sh --core failed" >&2; exit 1; }
bytes=$(printf '%s\n' "$report" | awk '/^core:/ { print $6 }')
summary=$(printf '%s\n' "$report" | tail -1 | sed 's/^core: //')
if [ -z "$bytes" ] || [ "$bytes" -gt "$MAX" ]; then
    echo "error std.core: $summary, more than $MAX: every program reads them" >&2
    echo "help: the biggest, each with the section and the name that pull it in:" >&2
    printf '%s\n' "$report" | grep -v '^core:' | sort -t'	' -k2 -n -r | head -8 | sed 's/^/  /' >&2
    echo "try: compiler/std/embed.sh --core   (all of them; a section is lazy when its title is in index.awk's LAZY)" >&2
    exit 1
fi
echo "std.core: $summary (at most $MAX)"
