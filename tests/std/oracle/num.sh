#!/bin/sh
# std::num's checks against Rust (0.20, A6): tools/numtables/gen.tach
# makes the tables checked in; num_check.tach (tachyon's std) and
# num_oracle.rs (Rust's std) print the same hashes, chunk by chunk, of
#   - {} {:?} {:e} of N f64 (raw bits, near 1, integers, short decimals),
#     each read back and checked to be the shortest;
#   - parse::<f64> and parse::<f32> of N generated texts (also against
#     C's strtod and strtof);
#   - Display and parse of N i64;
# and with --full, {} {:?} {:e} of every f32 (2^32, read back too), in
# parallel. Any `FAIL` line or differing hash fails.
#
# usage: tests/std/oracle/num.sh [-c COMPILER] [-n N] [--full]
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TC=$ROOT/target/tachyonc
N=2000000
FULL=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) TC=$2; shift 2 ;;
        -n) N=$2; shift 2 ;;
        --full) FULL=1; shift ;;
        *) echo "usage: $0 [-c COMPILER] [-n N] [--full]" >&2; exit 2 ;;
    esac
done
W=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-num.XXXXXX")
trap 'rm -rf "$W"' EXIT
fail=0
"$TC" "$ROOT/tools/numtables/gen.tach" -O2 -o "$W/gen" >/dev/null
"$W/gen" >"$W/tables.tach"
if cmp -s "$W/tables.tach" "$ROOT/compiler/std/num/tables.tach"; then
    echo "ok tables: compiler/std/num/tables.tach is gen.tach's"
else
    echo "FAIL tables: compiler/std/num/tables.tach differs from gen.tach's output"; fail=1
fi
"$TC" "$ROOT/tests/std/oracle/num_check.tach" -O2 -o "$W/check" >/dev/null
if ! command -v rustc >/dev/null 2>&1; then
    echo "note: no rustc: only the tables are checked"; exit $fail
fi
rustc -O -C codegen-units=1 "$ROOT/tests/std/oracle/num_oracle.rs" -o "$W/oracle"
for mode in "f64 11" "parse 7" "ints 3"; do
    set -- $mode
    "$W/check" "$1" "$2" "$N" >"$W/t"
    "$W/oracle" "$1" "$2" "$N" >"$W/r"
    if cmp -s "$W/t" "$W/r" && ! grep -q FAIL "$W/t"; then
        echo "ok $1: $N values as Rust's"
    else
        echo "FAIL $1: differs from Rust's (or a FAIL line)"; grep FAIL "$W/t" | head -5; fail=1
    fi
done
if [ $FULL = 1 ]; then
    STEP=268435456
    i=0
    while [ $i -lt 16 ]; do
        "$W/check" f32 $((i * STEP)) $(((i + 1) * STEP)) >"$W/f.$i" &
        i=$((i + 1))
    done
    "$W/oracle" f32 0 4294967296 >"$W/f.r"
    wait
    i=0
    : >"$W/f.t"
    while [ $i -lt 16 ]; do cat "$W/f.$i" >>"$W/f.t"; i=$((i + 1)); done
    if cmp -s "$W/f.t" "$W/f.r" && ! grep -q FAIL "$W/f.t"; then
        echo "ok f32: every f32 as Rust's, and read back"
    else
        echo "FAIL f32: differs from Rust's (or a FAIL line)"; grep FAIL "$W/f.t" | head -5; fail=1
    fi
fi
exit $fail
