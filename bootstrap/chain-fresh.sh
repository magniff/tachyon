#!/bin/sh
# (0.25) The chain rebuilt from nothing, trusting no binary built before:
# bootstrap.sh into an empty cache of its own (--clean --cache), so the
# seed is built again by cargo from the `seed` tag and every release again
# from its tag's tree (git archive), each by the one before; then what
# each release's compiler emitted for itself (build2.o, or build2.s up to
# 0.6: the fixpoint's output) is compared, by SHA-256, with the record in
# bootstrap/chain-hashes/<host>.txt and with the shared cache's entry.
# A difference means that a cached or recorded compiler is not what its
# tag's source and its builder make today. HEAD is not built here (the
# gate's chain step builds it, from the last release).
#
# usage: bootstrap/chain-fresh.sh [-w DIR] [--history fast|full]
#        bootstrap/chain-fresh.sh --record [CACHE]
#
#   -w DIR       the fresh cache (default target/chain-fresh; emptied)
#   --history    bootstrap.sh's: fast (the default) checks every release's
#                fixpoint and the last one's suite; full runs every suite
#   --record     write the record from CACHE (default: the shared cache,
#                as bootstrap.sh finds it), building nothing; a release
#                adds its line when it is tagged
set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
W="$ROOT/target/chain-fresh"
HISTORY=fast
RECORD=0
FROM=""
while [ $# -gt 0 ]; do
    case "$1" in
        -w) W=$2; shift 2 ;;
        --history) HISTORY=$2; shift 2 ;;
        --record) RECORD=1; shift; [ $# -gt 0 ] && { FROM=$1; shift; } ;;
        -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) HOST=aarch64-macos ;;
    Darwin-x86_64) HOST=x86_64-macos ;;
    Linux-x86_64) HOST=x86_64-linux ;;
    *) echo "chain-fresh: the chain does not start on $(uname -s) $(uname -m)"; exit 77 ;;
esac
REC="$ROOT/bootstrap/chain-hashes/$HOST.txt"

# The shared cache, as bootstrap.sh finds it.
shared_cache() {
    if [ -n "${VOLE_BOOTSTRAP_CACHE:-}" ]; then
        echo "$VOLE_BOOTSTRAP_CACHE"
        return
    fi
    common=$(cd "$ROOT" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    if [ -n "$common" ] && [ -d "$(dirname "$common")/target/bootstrap" ]; then
        echo "$(dirname "$common")/target/bootstrap"
    else
        echo "$ROOT/target/bootstrap"
    fi
}

# <cache> <tag>: the file the release's compiler emitted for itself.
emitted() {
    for e in "$1/$HOST/$2"-*/build2.o "$1/$HOST/$2"-*/build2.s; do
        [ -f "$e" ] && { echo "$e"; return; }
    done
}

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

TAGS=""
for t in $(sh "$ROOT/bootstrap/release-tags.sh"); do
    git -C "$ROOT" rev-parse -q --verify "refs/tags/$t^{commit}" >/dev/null 2>&1 && TAGS="$TAGS $t"
done
LAST=$(echo $TAGS | awk '{ print $NF }')
[ -n "$LAST" ] || { echo "chain-fresh: no release is tagged"; exit 77; }

if [ $RECORD -eq 1 ]; then
    [ -n "$FROM" ] || FROM=$(shared_cache)
    mkdir -p "$(dirname "$REC")"
    {
        echo "# (0.25) SHA-256 of what each release's compiler emits for itself on $HOST"
        echo "# (its fixpoint output, build2.o or build2.s); bootstrap/chain-fresh.sh"
        echo "# rebuilds the chain from the seed and compares. tag, hash, file"
        for t in $TAGS; do
            e=$(emitted "$FROM" "$t")
            [ -n "$e" ] || { echo "chain-fresh: $t is not built in $FROM" >&2; exit 1; }
            echo "$t $(sha "$e") $(basename "$e")"
        done
    } >"$REC.new" && mv "$REC.new" "$REC"
    echo "chain-fresh: recorded $(grep -c '^v' "$REC") releases from $FROM in $REC"
    exit 0
fi

rm -rf "$W"
mkdir -p "$W"
echo "chain-fresh: the seed and every release up to $LAST, from their tags, into $W"
sh "$ROOT/bootstrap/bootstrap.sh" --cache "$W" --clean --until "${LAST#v}" --history "$HISTORY" </dev/null \
    >"$W/bootstrap.log" 2>&1 || { tail -30 "$W/bootstrap.log"; echo "chain-fresh: the fresh chain failed (log: $W/bootstrap.log)"; exit 1; }
SHARED=$(shared_cache)
FAILED=0
n=0
for t in $TAGS; do
    e=$(emitted "$W" "$t")
    [ -n "$e" ] || { echo "FAIL $t: not built by the fresh chain"; FAILED=1; continue; }
    h=$(sha "$e")
    n=$((n + 1))
    r=$(awk -v t="$t" '$1 == t { print $2 }' "$REC" 2>/dev/null)
    if [ -z "$r" ]; then
        echo "FAIL $t: no record in $REC (bootstrap/chain-fresh.sh --record, when the release is tagged)"
        FAILED=1
    elif [ "$r" != "$h" ]; then
        echo "FAIL $t: rebuilt from its tag, it emits $h, the record says $r"
        FAILED=1
    fi
    c=$(emitted "$SHARED" "$t")
    if [ -n "$c" ] && [ "$(sha "$c")" != "$h" ]; then
        echo "FAIL $t: the shared cache's compiler ($c) emits other bytes than the fresh one"
        FAILED=1
    fi
done
grep -h '^  ' "$W/bootstrap.log" | sed -n '/seed/,$p' | head -40
[ $FAILED -eq 0 ] || { echo "chain-fresh: the rebuilt chain differs (kept in $W)"; exit 1; }
echo "chain-fresh: $n releases rebuilt from the seed, each the same bytes as recorded and as cached"
