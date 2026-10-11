#!/bin/bash
# tachyon.sh — build or run a .tach program
#
# Usage:
#   ./tachyon.sh build program.tach [-o output] [--keep]
#   ./tachyon.sh run   program.tach [program args...]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

die() { echo -e "${RED}error:${NC} $*" >&2; exit 1; }

[[ $# -lt 2 ]] && die "usage: tachyon.sh <build|run> <input.tach> [options]"

MODE="$1"
shift

INPUT="$1"
shift

[[ "$MODE" != "build" && "$MODE" != "run" ]] && \
    die "unknown mode '$MODE' (expected build or run)"

[[ -f "$INPUT" ]] || die "file not found: $INPUT"

OUTPUT=""
KEEP_ASM=0
PROGRAM_ARGS=()

# -------------------------------------------------
# BUILD MODE: parse flags
# RUN MODE:   everything is program arguments
# -------------------------------------------------
if [[ "$MODE" == "build" ]]; then
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o)
                shift
                OUTPUT="$1"
                ;;
            --keep)
                KEEP_ASM=1
                ;;
            -*)
                die "unknown option '$1'"
                ;;
            *)
                die "unexpected argument '$1'"
                ;;
        esac
        shift
    done
else
    # run mode → forward all remaining args
    PROGRAM_ARGS=("$@")
fi

# --- Ensure compiler exists ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TACHYON="${SCRIPT_DIR}/target/release/tachyon"

if [[ ! -x "$TACHYON" ]]; then
    echo -e "${CYAN}building tachyon compiler...${NC}" >&2
    (cd "$SCRIPT_DIR" && cargo build --release) || die "cargo build failed"
fi

[[ -x "$TACHYON" ]] || die "tachyon compiler not found"

# Linux: ELF + gcc. macOS: Mach-O x86-64 + clang (Apple Silicon runs it
# under Rosetta 2).
if [[ "$(uname -s)" == "Darwin" ]]; then
    TARGET="macos-x86_64"
    NASM_FORMAT="macho64"
    LINK=(clang -arch x86_64 -Wl,-w)
else
    TARGET="linux-x86_64"
    NASM_FORMAT="elf64"
    LINK=(gcc -no-pie -lc)
fi

command -v nasm >/dev/null 2>&1 || die "nasm not found"
command -v "${LINK[0]}" >/dev/null 2>&1 || die "${LINK[0]} not found"

STEM="$(basename "${INPUT%.tach}")"

if [[ "$MODE" == "build" ]]; then
    ASM="${STEM}.asm"
    OBJ="${STEM}.o"
    BIN="${OUTPUT:-$STEM}"
else
    TMPDIR="$(mktemp -d)"
    ASM="${TMPDIR}/${STEM}.asm"
    OBJ="${TMPDIR}/${STEM}.o"
    BIN="${TMPDIR}/${STEM}.bin"
fi

# --- Compile ---
echo -e "${CYAN}[1/3]${NC} tachyon  ${INPUT} → ${ASM}" >&2
"$TACHYON" --target "$TARGET" --input "$INPUT" --output "$ASM" || die "compilation failed"

# --- Assemble ---
echo -e "${CYAN}[2/3]${NC} nasm     ${ASM} → ${OBJ}" >&2
nasm -f "$NASM_FORMAT" -o "$OBJ" "$ASM" || die "assembly failed"

# --- Link ---
echo -e "${CYAN}[3/3]${NC} ${LINK[0]}  ${OBJ} → ${BIN}  (libc)" >&2
"${LINK[@]}" -o "$BIN" "$OBJ" -lm || die "linking failed"

# --- Run mode ---
if [[ "$MODE" == "run" ]]; then
    echo -e "${GREEN}running:${NC} ${INPUT}" >&2
    # ${a[@]+...}: bash 3.2 (macOS) treats an empty array as unbound under -u.
    STATUS=0
    "$BIN" ${PROGRAM_ARGS[@]+"${PROGRAM_ARGS[@]}"} || STATUS=$?
    rm -rf "$TMPDIR"
    exit $STATUS
fi

# --- Cleanup (build mode only) ---
rm -f "$OBJ"
if [[ $KEEP_ASM -eq 0 ]]; then
    rm -f "$ASM"
fi

echo -e "${GREEN}done:${NC} ${BIN}" >&2