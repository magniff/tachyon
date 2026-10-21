#!/bin/sh
# The headless benchmark: parse + grid throughput of voltty against
# alacritty_terminal 0.26 (the oracle's `bench`), on vtebench-like
# workloads (bench/workloads.tach), fed in 64 KiB chunks to a 120x40
# terminal with 10,000 lines of scrollback. The two run in turns, ROUNDS
# times, and the best of each is kept, so a busy machine slows both alike.
#
# usage: examples/voltty/core/bench/run.sh [-c TACHYONC] [-m MIB] [-r ROUNDS]
#   prints a table: workload, MiB/s of each, voltty / alacritty
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
TC="$ROOT/target/tachyonc"
MIB=32
ROUNDS=3
while [ $# -gt 0 ]; do
    case "$1" in
        -c) TC=$2; shift 2 ;;
        -m) MIB=$2; shift 2 ;;
        -r) ROUNDS=$2; shift 2 ;;
        *) sed -n '2,11p' "$0" >&2; exit 2 ;;
    esac
done
W=$(mktemp -d "${TMPDIR:-/tmp}/voltty-bench.XXXXXX")
trap 'rm -rf "$W"' EXIT
"$TC" -O2 "$HERE/../main.tach" -o "$W/voltty" >/dev/null
"$TC" -O2 "$HERE/workloads.tach" -o "$W/workloads" >/dev/null
(cd "$HERE/../oracle" && cargo build --release --offline --quiet)
ORACLE="$HERE/../oracle/target/release/voltty-oracle"
KINDS="ascii sgr cjk region motion"
for k in $KINDS; do
    "$W/workloads" "$k" "$MIB" >"$W/$k.vt"
done
r=0
while [ "$r" -lt "$ROUNDS" ]; do
    for k in $KINDS; do
        "$ORACLE" bench -n 1 "$W/$k.vt" | awk -v k="$k" '{ print "alacritty", k, $(NF-1) }' >>"$W/results"
        "$W/voltty" --bench -n 1 "$W/$k.vt" | awk -v k="$k" '{ print "voltty", k, $(NF-1) }' >>"$W/results"
    done
    r=$((r + 1))
done
echo "parse + grid, $MIB MiB per workload, best of $ROUNDS ($(uptime | sed 's/.*load/load/'))"
awk -v kinds="$KINDS" '
    { if ($3 > best[$1, $2]) best[$1, $2] = $3 }
    END {
        printf "  %-8s %12s %12s %8s\n", "workload", "voltty", "alacritty", "ratio"
        n = split(kinds, ks, " ")
        for (i = 1; i <= n; i++) {
            k = ks[i]
            printf "  %-8s %8d MiB/s %6d MiB/s %7.2fx\n", k, best["voltty", k], best["alacritty", k], best["voltty", k] / best["alacritty", k]
        }
    }' "$W/results"
