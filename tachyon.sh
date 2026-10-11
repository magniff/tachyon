#!/bin/bash
# tachyon.sh — build or run a .tach program
#
# Usage:
#   ./tachyon.sh build [options] program.tach [-o output] [--keep]
#   ./tachyon.sh run   [options] program.tach [program args...]
#
# Options (before the program):
#   --target <target>   linux-x86_64, macos-x86_64 or macos-aarch64
#                       (default: the host)
#   -O                  optimize
#
# --keep keeps the intermediate object file.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

die() { echo -e "${RED}error:${NC} $*" >&2; exit 1; }

[[ $# -lt 2 ]] && die "usage: tachyon.sh <build|run> [options] <input.tach> [args]"

MODE="$1"
shift

[[ "$MODE" != "build" && "$MODE" != "run" ]] && \
    die "unknown mode '$MODE' (expected build or run)"

TARGET=""
OPT=()
while [[ $# -gt 0 && "$1" == -* ]]; do
    case "$1" in
        --target)
            shift
            TARGET="${1:-}"
            ;;
        -O)
            OPT=(-O)
            ;;
        *)
            die "unknown option '$1'"
            ;;
    esac
    shift
done

[[ $# -ge 1 ]] || die "missing input file"
INPUT="$1"
shift

[[ -f "$INPUT" ]] || die "file not found: $INPUT"

OUTPUT=""
KEEP=0
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
                KEEP=1
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

# Default target: the host. Apple Silicon also runs macos-x86_64 binaries
# under Rosetta 2.
if [[ -z "$TARGET" ]]; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
        if [[ "$(uname -m)" == "arm64" ]]; then
            TARGET="macos-aarch64"
        else
            TARGET="macos-x86_64"
        fi
    else
        TARGET="linux-x86_64"
    fi
fi

case "$TARGET" in
    macos-aarch64) LINK=(clang -arch arm64) ;;
    macos-x86_64) LINK=(clang -arch x86_64 -Wl,-w) ;;
    linux-x86_64) LINK=(cc) ;;
    *) die "unknown target '$TARGET'" ;;
esac

command -v "${LINK[0]}" >/dev/null 2>&1 || die "${LINK[0]} not found"

STEM="$(basename "${INPUT%.tach}")"

if [[ "$MODE" == "build" ]]; then
    WORK="."
    BIN="${OUTPUT:-$STEM}"
else
    WORK="$(mktemp -d)"
    BIN="${WORK}/${STEM}.bin"
fi
OBJ="${WORK}/${STEM}.o"

echo -e "${CYAN}[1/2]${NC} tachyon  ${INPUT} → ${OBJ}  (${TARGET})" >&2
"$TACHYON" --target "$TARGET" ${OPT[@]+"${OPT[@]}"} \
    --input "$INPUT" --output "$OBJ" || die "compilation failed"

echo -e "${CYAN}[2/2]${NC} ${LINK[0]}  ${OBJ} → ${BIN}  (libc)" >&2
"${LINK[@]}" -o "$BIN" "$OBJ" -lm || die "linking failed"

# --- Run mode ---
if [[ "$MODE" == "run" ]]; then
    echo -e "${GREEN}running:${NC} ${INPUT}" >&2
    # ${a[@]+...}: bash 3.2 (macOS) treats an empty array as unbound under -u.
    STATUS=0
    "$BIN" ${PROGRAM_ARGS[@]+"${PROGRAM_ARGS[@]}"} || STATUS=$?
    rm -rf "$WORK"
    exit $STATUS
fi

# --- Cleanup (build mode only) ---
if [[ $KEEP -eq 0 ]]; then
    rm -f "$OBJ"
fi

echo -e "${GREEN}done:${NC} ${BIN}" >&2
