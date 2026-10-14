#!/bin/sh
# The fuzzers, forever (0.11): every mode of the random program generator
# (tests/fuzz/run.sh, the seed as a third oracle in one of them) and of the
# C interop fuzzer (tests/abi/run.sh), in turn, a batch of each, each batch
# on new seeds; at the lowest priority (nice 19), so it can run whenever
# the machine is otherwise idle and the gate's own fuzz counts stay modest.
#
# Everything is in target/fuzz-forever/:
#   log             one line per batch: time, mode, seeds, result, compiler
#   failures/MODE/  the failing programs (FAIL lines in the log say which)
#   next/MODE       the next seed of each mode (a restart goes on from there)
#   tachyonc        the compiler under test, copied when it starts
#   stop            create this file to stop after the current batch
#
# usage: tests/fuzz/forever.sh [-c COMPILER] [-n BATCH] [-j JOBS] [--follow]
#
#   -c COMPILER   the compiler to test (default: target/tachyonc)
#   -n BATCH      programs per batch (default 50)
#   -j JOBS       programs at once (default: the number of CPUs)
#   --follow      take the compiler again whenever COMPILER changes (else
#                 the copy made at the start is tested throughout)
#
# Seeds start at 1000000 in every mode, away from the gate's (1 to a few
# hundred). A failure reproduces with the batch's runner and the seed:
# tests/fuzz/run.sh -f SEED -n 1 [mode flag], tests/abi/run.sh likewise.

set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DIR="$ROOT/target/fuzz-forever"
COMPILER="$ROOT/target/tachyonc"
BATCH=50
JOBS=""
FOLLOW=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -n) BATCH=$2; shift 2 ;;
        -j) JOBS=$2; shift 2 ;;
        --follow) FOLLOW=1; shift ;;
        *) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
[ -x "$COMPILER" ] || { echo "forever: no compiler at $COMPILER (use -c)" >&2; exit 2; }
# (not a gate's runner: its own slots)
unset TACHYON_JOBSERVER

mkdir -p "$DIR/next" "$DIR/failures"
if [ -f "$DIR/pid" ] && kill -0 "$(cat "$DIR/pid")" 2>/dev/null; then
    echo "forever: already running (pid $(cat "$DIR/pid")); touch $DIR/stop to stop it" >&2
    exit 1
fi
echo $$ >"$DIR/pid"
rm -f "$DIR/stop"
trap 'rm -f "$DIR/pid"' EXIT
trap 'exit 130' INT TERM

C="$DIR/tachyonc"
take_compiler() {
    cp "$COMPILER" "$C.new" && mv "$C.new" "$C"
    COMPILER_ID="$("$C" --version 2>/dev/null | cut -d' ' -f2) $(cksum <"$C" | cut -d' ' -f1)"
    log "compiler $COMPILER ($COMPILER_ID)"
}
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$DIR/log"
}

# The seed binary, for the seed mode.
HOSTDIR=""
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) HOSTDIR=aarch64-macos ;;
    Darwin-x86_64) HOSTDIR=x86_64-macos ;;
    Linux-x86_64) HOSTDIR=x86_64-linux ;;
esac
SEED=""
for s in "$ROOT"/target/bootstrap/"$HOSTDIR"/seed-*/target/release/tachyon; do
    [ -x "$s" ] && { SEED=$s; break; }
done

MODES="plain loops generics pressure calls lang06 vector div range seed abi-plain abi-import abi-header"
[ -n "$SEED" ] || MODES=$(echo "$MODES" | sed 's/ seed//')

take_compiler
log "started: modes $MODES, $BATCH programs a batch"
echo "forever: fuzzing in $DIR (log: $DIR/log); touch $DIR/stop to stop"
while :; do
    for mode in $MODES; do
        [ -f "$DIR/stop" ] && { log "stopped"; rm -f "$DIR/stop"; echo "forever: stopped"; exit 0; }
        if [ $FOLLOW -eq 1 ] && ! cmp -s "$COMPILER" "$C"; then
            take_compiler
        fi
        first=1000000
        [ -f "$DIR/next/$mode" ] && first=$(cat "$DIR/next/$mode")
        case "$mode" in
            plain) set -- fuzz ;;
            loops) set -- fuzz -l ;;
            generics) set -- fuzz -g ;;
            pressure) set -- fuzz -p ;;
            calls) set -- fuzz -C ;;
            lang06) set -- fuzz -N ;;
            vector) set -- fuzz -V ;;
            div) set -- fuzz -D ;;
            range) set -- fuzz -R ;;
            seed) set -- fuzz -s "$SEED" ;;
            abi-plain) set -- abi ;;
            abi-import) set -- abi -i ;;
            abi-header) set -- abi -H ;;
        esac
        runner=$1
        shift
        nice -n 19 sh "$ROOT/tests/$runner/run.sh" -c "$C" -n "$BATCH" -f "$first" \
            -k "$DIR/failures/$mode" ${JOBS:+-j "$JOBS"} "$@" >"$DIR/batch.out" 2>&1
        rc=$?
        echo $((first + BATCH)) >"$DIR/next/$mode"
        if [ $rc -eq 0 ]; then
            log "$mode seeds $first-$((first + BATCH - 1)): ok"
        else
            log "$mode seeds $first-$((first + BATCH - 1)): FAIL ($COMPILER_ID)"
            grep '^FAIL' "$DIR/batch.out" | sed 's/^/    /' >>"$DIR/log"
            echo "forever: $mode: failures (see $DIR/log)"
        fi
    done
done
