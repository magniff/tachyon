#!/bin/sh
# The tests of voltty's core (examples/voltty/core) against its oracle,
# alacritty_terminal 0.26.0 (examples/voltty/core/oracle):
#
#   build        voltty and the generator (tests/voltty/gen.tach) at -O2
#   regress/N    each reduced case of regress/: N.script through voltty
#                gives the oracle's dump, N.dump (recorded)
#   seeds        each line of seeds.txt: the generator's script for the
#                seed, its dumps' cksum as the oracle's (recorded)
#   oracle       with cargo (offline: the crates in ~/.cargo), the
#                differential fuzzer: generated scripts (grammar, corpus
#                mutations, invalid input, random chunking and resizes) run
#                by both, the dumps compared; a difference is reduced
#                (gen --reduce) and kept in DIR. Without cargo: skipped.
#
# usage: tests/voltty/run.sh [-c COMPILER] [-n SCRIPTS] [-s SECONDS] [-f FIRST]
#                            [-k DIR] [-u]
#   -n SCRIPTS   oracle scripts (default 20; each 20 terminals)
#   -s SECONDS   instead, as many as fit in SECONDS (the gate: 60)
#   -f FIRST     the first seed (default: from the time, so runs differ)
#   -k DIR       where reduced differences go (default tests/voltty/failures)
#   -u           rewrite seeds.txt and regress/*.dump from the oracle
#
# Prints `pass NAME` or `FAIL NAME` for each, then `voltty: ...`; exits 1
# when one failed. POSIX sh.
set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HERE="$ROOT/tests/voltty"
CORE="$ROOT/examples/voltty/core"
COMPILER="$ROOT/target/tachyonc"
SCRIPTS=20
SECONDS_LIMIT=""
FIRST=""
KEEP="$HERE/failures"
UPDATE=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -n) SCRIPTS=$2; shift 2 ;;
        -s) SECONDS_LIMIT=$2; shift 2 ;;
        -f) FIRST=$2; shift 2 ;;
        -k) KEEP=$2; shift 2 ;;
        -u) UPDATE=1; shift ;;
        *) sed -n '2,28p' "$0" >&2; exit 2 ;;
    esac
done
W=$(mktemp -d "${TMPDIR:-/tmp}/voltty-test.XXXXXX")
trap 'rm -rf "$W"' EXIT
failed=0
pass() { echo "pass $1"; }
fail() { echo "FAIL $1"; [ $# -gt 1 ] && echo "    $2"; failed=1; }

if "$COMPILER" -O2 "$CORE/main.tach" -o "$W/voltty" >"$W/build.log" 2>&1 \
    && "$COMPILER" -O2 "$HERE/gen.tach" -o "$W/gen" >>"$W/build.log" 2>&1; then
    pass build
else
    fail build "$(head -5 "$W/build.log")"
    exit 1
fi

ORACLE=""
if command -v cargo >/dev/null 2>&1 \
    && (cd "$CORE/oracle" && cargo build --release --offline --quiet) >"$W/cargo.log" 2>&1; then
    ORACLE="$CORE/oracle/target/release/voltty-oracle"
fi

if [ "$UPDATE" = 1 ]; then
    [ -n "$ORACLE" ] || { echo "voltty: -u needs the oracle (cargo)" >&2; exit 2; }
    for s in "$HERE"/regress/*.script; do
        "$ORACLE" script <"$s" >"${s%.script}.dump"
    done
    {
        sed -n '1,2p' "$HERE/seeds.txt"
        grep -v '^#' "$HERE/seeds.txt" | while read -r seed cases _; do
            "$W/gen" "$seed" "$cases" >"$W/s.script"
            echo "$seed $cases $("$ORACLE" script <"$W/s.script" | cksum | awk '{ print $1, $2 }')"
        done
    } >"$W/seeds.txt"
    mv "$W/seeds.txt" "$HERE/seeds.txt"
    echo "voltty: updated regress/*.dump and seeds.txt"
fi

for s in "$HERE"/regress/*.script; do
    name=${s##*/}
    name=${name%.script}
    if "$W/voltty" --script <"$s" >"$W/r.out" 2>&1 && cmp -s "$W/r.out" "${s%.script}.dump"; then
        pass "regress/$name"
    else
        fail "regress/$name" "$(diff "${s%.script}.dump" "$W/r.out" | head -6 | tr '\n' ' ')"
    fi
done

bad=""
while read -r seed cases sum size; do
    case "$seed" in '#'*|'') continue ;; esac
    "$W/gen" "$seed" "$cases" >"$W/s.script"
    got=$("$W/voltty" --script <"$W/s.script" | cksum | awk '{ print $1, $2 }')
    [ "$got" = "$sum $size" ] || bad="$bad $seed"
done <"$HERE/seeds.txt"
if [ -z "$bad" ]; then pass seeds; else fail seeds "seeds$bad differ from the oracle's dumps (run: $W/gen SEED 10 | voltty --script)"; fi

if [ -z "$ORACLE" ]; then
    echo "skip oracle (no cargo, or the oracle does not build offline)"
else
    [ -n "$FIRST" ] || FIRST=$(( $(date +%s) % 1000000 ))
    t0=$(date +%s)
    n=0
    diffs=0
    seed=$FIRST
    while :; do
        if [ -n "$SECONDS_LIMIT" ]; then
            [ $(( $(date +%s) - t0 )) -lt "$SECONDS_LIMIT" ] || break
        else
            [ "$n" -lt "$SCRIPTS" ] || break
        fi
        "$W/gen" "$seed" 20 >"$W/f.script"
        "$W/voltty" --script <"$W/f.script" >"$W/f.a" 2>&1
        "$ORACLE" script <"$W/f.script" >"$W/f.b" 2>&1
        if ! cmp -s "$W/f.a" "$W/f.b"; then
            diffs=$((diffs + 1))
            mkdir -p "$KEEP"
            "$W/gen" --reduce "$W/f.script" "$W/voltty" "$ORACLE" >"$KEEP/seed-$seed.script" 2>/dev/null
            echo "    seed $seed differs: reduced to $KEEP/seed-$seed.script"
        fi
        n=$((n + 1))
        seed=$((seed + 1))
    done
    if [ "$diffs" = 0 ]; then
        pass "oracle ($n scripts from seed $FIRST)"
    else
        fail "oracle" "$diffs of $n scripts from seed $FIRST differ"
    fi
fi
[ "$failed" = 0 ] && echo "voltty: all passed" || echo "voltty: failures above"
exit "$failed"
