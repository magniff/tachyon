#!/bin/bash
# tachyon.sh — compile a .tach file to an ELF binary
#
# Usage: ./tachyon.sh program.tach [-o output] [--keep] [--no-libc]
#
# Default (with libc):
#   1. tachyon  program.tach → program.asm
#   2. nasm     program.asm  → program.o
#   3. gcc      program.o    → program       (links libc, crt provides _start)
#
# With --no-libc (freestanding):
#   3. ld       program.o    → program       (our own _start, raw syscalls only)


cargo b -r

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

die() { echo -e "${RED}error:${NC} $*" >&2; exit 1; }

# --- Parse args ---
INPUT=""
OUTPUT=""
KEEP_ASM=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)        shift; OUTPUT="$1" ;;
        --keep)    KEEP_ASM=1 ;;
        -*)        die "unknown option '$1'" ;;
        *)         [[ -n "$INPUT" ]] && die "multiple input files"
                   INPUT="$1" ;;
    esac
    shift
done

[[ -z "$INPUT" ]] && die "usage: tachyon.sh <input.tach> [-o output] [--keep]"
[[ -f "$INPUT" ]] || die "file not found: $INPUT"

# --- Derive paths ---
STEM="${INPUT%.tach}"
ASM="${STEM}.asm"
OBJ="${STEM}.o"
BIN="${OUTPUT:-$STEM}"

# --- Find the compiler ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TACHYON="${SCRIPT_DIR}/target/release/tachyon"
if [[ ! -x "$TACHYON" ]]; then
    TACHYON="${SCRIPT_DIR}/target/debug/tachyon"
fi
if [[ ! -x "$TACHYON" ]]; then
    echo -e "${CYAN}building tachyon compiler...${NC}" >&2
    (cd "$SCRIPT_DIR" && cargo build --release 2>&1) || die "cargo build failed"
    TACHYON="${SCRIPT_DIR}/target/release/tachyon"
fi

echo -e "${CYAN}[1/3]${NC} tachyon  ${INPUT} → ${ASM}" >&2
"$TACHYON" --input "$INPUT" --output "$ASM" || die "compilation failed"

# --- Assemble ---
command -v nasm >/dev/null 2>&1 || die "nasm not found — install with: sudo apt install nasm"
echo -e "${CYAN}[2/3]${NC} nasm     ${ASM} → ${OBJ}" >&2
nasm -f elf64 -o "$OBJ" "$ASM" || die "assembly failed"

# --- Link ---
command -v gcc >/dev/null 2>&1 || die "gcc not found — install with: sudo apt install gcc"
echo -e "${CYAN}[3/3]${NC} gcc      ${OBJ} → ${BIN}  (libc)" >&2
gcc -o "$BIN" "$OBJ" -no-pie -lc -lm || die "linking failed"

# --- Cleanup ---
rm -f "$OBJ"
if [[ $KEEP_ASM -eq 0 ]]; then rm -f "$ASM"; fi

echo -e "${GREEN}done:${NC} ${BIN}" >&2
