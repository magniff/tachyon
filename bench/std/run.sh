#!/bin/sh
# bench/std: std's routines against Rust's std and C (0.20 P0; design
# docs/design/collections-text-io.md §3). Each benchmark NAME is a
# triple, NAME.tach, NAME.rs and NAME.c, making its input in-process from
# the same xorshift64 seed and printing the same checksum; targets.txt
# lists the comparisons and their targets. The harness builds each
# (tachyonc -O2; rustc -C opt-level=3 -C codegen-units=1 -C panic=abort;
# cc -O2), checks the checksums agree, runs each RUNS times (the fastest
# wall-clock time, whole program) and prints a row per comparison:
# tachyon's time, the baseline's, their ratio and the target.
#
# usage: bench/std/run.sh [-c COMPILER] [-r RUNS] [--gate] [NAME...]
#
#   -c COMPILER   the tachyonc to measure (default: target/tachyonc)
#   -r RUNS       runs per program (default 5)
#   --gate        exit 1 when a ratio is above its target by more than 10%
#                 (noise), or a checksum differs
#   NAME...       only these benchmarks (default: every one of targets.txt)
#
# Without rustc, the Rust rows are skipped (said so). Run it on an idle
# machine: `bootstrap/gate.sh --only bench` is where the release measures.

set -eu
LC_ALL=C
export LC_ALL
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/tachyonc"
RUNS=5
GATE=0
CC=${CC:-cc}
NAMES=""
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -r) RUNS=$2; shift 2 ;;
        --gate) GATE=1; shift ;;
        -*) sed -n '13,20p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
        *) NAMES="$NAMES $1"; shift ;;
    esac
done
[ -n "$NAMES" ] || NAMES=$(grep -v '^#' "$HERE/targets.txt" | awk 'NF { print $1 }' | uniq | tr '\n' ' ')
HAVE_RUST=1
command -v rustc >/dev/null 2>&1 || { HAVE_RUST=0; echo "note bench.std: no rustc: the Rust rows are skipped" >&2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-bench-std.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
"$CC" -O2 -o "$WORK/timer" "$ROOT/bench/timer.c"
: >"$WORK/empty"

failed=0
# The fastest of RUNS runs of program $1 (its argument $2, if any), in
# ms; its output in $WORK/$3.out.
measure() {
    if [ -n "$2" ]; then
        printf '#!/bin/sh\nexec "%s" "%s"\n' "$1" "$2" >"$WORK/$3.sh"
        chmod +x "$WORK/$3.sh"
        "$WORK/timer" "$RUNS" "$WORK/empty" "$WORK/$3.out" "$WORK/$3.sh"
    else
        "$WORK/timer" "$RUNS" "$WORK/empty" "$WORK/$3.out" "$1"
    fi
}

printf '%-14s %-10s %10s %10s %7s %7s  %s\n' bench baseline 'tachyon ms' 'base ms' ratio target result
for name in $NAMES; do
    src="$HERE/$name"
    if ! "$COMPILER" -O2 "$src.tach" -o "$WORK/$name.t" >"$WORK/$name.t.log" 2>&1; then
        echo "FAIL $name: tachyonc: $(tail -3 "$WORK/$name.t.log")"; failed=1; continue
    fi
    "$CC" -O2 -o "$WORK/$name.c" "$src.c" >"$WORK/$name.c.log" 2>&1 \
        || { echo "FAIL $name: cc: $(tail -3 "$WORK/$name.c.log")"; failed=1; continue; }
    if [ $HAVE_RUST = 1 ]; then
        (cd "$HERE" && rustc -C opt-level=3 -C codegen-units=1 -C panic=abort "$name.rs" \
            -o "$WORK/$name.r") >"$WORK/$name.r.log" 2>&1 \
            || { echo "FAIL $name: rustc: $(tail -3 "$WORK/$name.r.log")"; failed=1; continue; }
    fi
    t=$(measure "$WORK/$name.t" "" "$name.t")
    grep -v '^#' "$HERE/targets.txt" | awk -v n="$name" '$1 == n' | while read -r _ base target flag; do
        case "$base" in
            c) prog="$WORK/$name.c"; arg="" ;;
            rust) [ $HAVE_RUST = 1 ] || continue; prog="$WORK/$name.r"; arg="" ;;
            rust:*) [ $HAVE_RUST = 1 ] || continue; prog="$WORK/$name.r"; arg=${base#rust:} ;;
        esac
        key=$(echo "$name.$base" | tr ':' '_')
        b=$(measure "$prog" "$arg" "$key")
        result=ok
        if [ "${flag:-}" != nocheck ] && ! cmp -s "$WORK/$name.t.out" "$WORK/$key.out"; then
            result="checksum differs: $(head -1 "$WORK/$name.t.out") / $(head -1 "$WORK/$key.out")"
            echo 1 >"$WORK/failed"
        fi
        ratio=$(awk -v t="$t" -v b="$b" 'BEGIN { printf "%.2f", (b > 0 ? t / b : 0) }')
        if [ "$result" = ok ] && [ "$target" != - ]; then
            if awk -v r="$ratio" -v g="$target" 'BEGIN { exit !(r > g * 1.10) }'; then
                result="above target"
                echo 1 >"$WORK/failed"
            elif awk -v r="$ratio" -v g="$target" 'BEGIN { exit !(r > g) }'; then
                result="above target (within noise)"
            fi
        fi
        printf '%-14s %-10s %10s %10s %7s %7s  %s\n' "$name" "$base" "$t" "$b" "$ratio" "$target" "$result"
    done
done
[ -f "$WORK/failed" ] && failed=1
[ $GATE = 1 ] && [ $failed = 1 ] && exit 1
exit 0
