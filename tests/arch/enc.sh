#!/bin/sh
# The x86-64 encoder against the system assembler, byte for byte (0.19,
# docs/design/arch.md §6.8): tests/arch/enc_x86.s holds every instruction
# of compiler/arch/insn_x86.def, and the AVX moves the back end writes,
# with low and high registers (VEX.R, X, B and vvvv), both vector widths
# (VEX.L), every class's operand order and memory operands with each
# addressing form (written by tools/arch/x86_families.py --write). It is
# assembled by the compiler (`tachyonc assemble`) and by cc, for
# x86_64-macos (Mach-O) and x86_64-linux (ELF), and the two disassemblies
# must be the same. Nothing is run: x86-64 is not executed in 0.19. Every
# mnemonic of insn_x86.def must appear in the corpus (else the corpus is
# stale: rerun the script). Skipped when cc cannot assemble for x86-64.
#
# usage: tests/arch/enc.sh [-c COMPILER] [-o DIR]
set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
COMPILER="$ROOT/target/tachyonc"
OUT="$ROOT/target/arch-enc"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -o) OUT=$2; shift 2 ;;
        *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
mkdir -p "$OUT"
CORPUS="$ROOT/tests/arch/enc_x86.s"
status=0

# The corpus covers the table.
missing=$(grep -v '^[[:space:]]*#' "$ROOT/compiler/arch/insn_x86.def" | grep -v '^[[:space:]]*$' \
    | sed 's/ |.*//' | while read -r mn; do
        grep -q "^    $mn " "$CORPUS" || echo "$mn"
    done)
if [ -n "$missing" ]; then
    echo "enc: not in tests/arch/enc_x86.s (run tools/arch/x86_families.py --write):" $missing
    status=1
fi

for t in x86_64-macos x86_64-linux; do
    case $t in
        x86_64-macos) ct=x86_64-apple-macos ;;
        *) ct=x86_64-linux-gnu ;;
    esac
    if ! cc -target "$ct" -c "$CORPUS" -o "$OUT/$t.cc.o" 2>"$OUT/$t.cc.log"; then
        echo "enc: skipped $t: cc does not assemble for it ($(head -1 "$OUT/$t.cc.log"))"
        continue
    fi
    if ! "$COMPILER" assemble --target "$t" "$CORPUS" -o "$OUT/$t.o" >"$OUT/$t.log" 2>&1; then
        echo "enc: FAIL $t: $(head -3 "$OUT/$t.log")"
        status=1
        continue
    fi
    objdump -d --no-leading-addr "$OUT/$t.o" | sed -n -e '/^</p' -e '/^ /p' >"$OUT/$t.ours"
    objdump -d --no-leading-addr "$OUT/$t.cc.o" | sed -n -e '/^</p' -e '/^ /p' >"$OUT/$t.theirs"
    n=$(grep -c '^ ' "$OUT/$t.theirs")
    if [ "$n" -lt 1000 ] || ! cmp -s "$OUT/$t.ours" "$OUT/$t.theirs"; then
        echo "enc: FAIL $t: the encodings differ from cc's (< ours, > cc's):"
        diff "$OUT/$t.ours" "$OUT/$t.theirs" | head -20
        status=1
        continue
    fi
    echo "enc: $t: $n instructions, the same bytes as cc's"
done
[ $status = 0 ] && echo "enc: ok"
exit $status
