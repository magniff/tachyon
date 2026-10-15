#!/bin/sh
# The release gate (docs/roadmap.md) in one command, as parallel as the
# machine allows: the chain builds the compiler from the working tree
# (bootstrap.sh --dev), then the test suite at every level, the random
# programs in every mode, the C interop fuzzer in every mode, the object
# and layout checks and the debugger check all run at once, next to the
# two Linux containers (x86_64-linux, from its own chain; aarch64-linux,
# cross-built here). Ends with one table (step, result, time) and the
# failures' details; exits 1 when a step failed.
#
# usage: bootstrap/gate.sh [--quick | --release] [options]
#
#   --quick          a developer's smoke test (a few minutes): the chain,
#                    the suite at -O2, a short fuzz; no containers
#   (default)        every step, with modest fuzz counts
#   --release        every step, with the release's fuzz counts
#   --no-linux       without the containers
#   --no-x86         without x86_64 (the x86_64-linux container); the
#                    default since 0.15, set in bootstrap/gate.conf (X86=0)
#                    or by $TACHYON_GATE_X86 (0 or 1)
#   --with-x86       with x86_64, whatever the default
#   --only STEPS     only these steps (comma-separated; `fuzz-*` patterns;
#                    the chain is added when they need the compiler)
#   --bench          then the benchmarks (bench/run.sh), alone, at the end
#                    (they need an idle machine); `--only bench` for just
#                    them
#   -j N             slots for the macOS (or host) steps, shared by all of
#                    them through $TACHYON_JOBSERVER (default: the number
#                    of CPUs)
#   --cpus N         CPUs of each container (default 8, at most docker's)
#   --fuzz N         random programs per fuzz mode (overrides the mode's)
#   --abi N          C interop programs per ABI mode (the same)
#   --history MODE   fast (the default) or full: bootstrap.sh's --history,
#                    here and in the x86_64-linux container
#   --fresh          the x86_64-linux chain without its cache (a docker
#                    volume): from nothing, as on a new machine
#   -c COMPILER      test this compiler instead of building one (no chain)
#   --list           print the steps and exit
#
# Steps: chain; suite-O0, suite-O1, suite-O2; fuzz-plain, fuzz-loops,
# fuzz-generics, fuzz-pressure, fuzz-calls, fuzz-lang06, fuzz-vector,
# fuzz-div, fuzz-range, fuzz-seed (against the Rust seed); abi-plain,
# abi-import, abi-header; objcheck; layout (tests/cimport/layout.sh); debug (tests/debug.sh);
# stress-grow (the compiler with every table growth moving, 0.14);
# linux-x86_64 (bootstrap/linux-check.sh); linux-aarch64
# (bootstrap/aarch64-linux-check.sh); bench.
#
# Logs: target/gate/<date>/ (target/gate/last), one STEP.log per step;
# failing random programs are kept in failures/STEP/ there.
#
# Inside the Linux containers the check scripts run the host's steps with
# `gate.sh --inside -c COMPILER --only ...`, which prints the rows for the
# outer table too.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=default
LINUX=1
# (0.15) x86_64: bootstrap/gate.conf's X86, then $TACHYON_GATE_X86, then
# --no-x86/--with-x86
X86=1
[ ! -f "$ROOT/bootstrap/gate.conf" ] || X86=$(sed -n 's/^X86=\([01]\)$/\1/p' "$ROOT/bootstrap/gate.conf" | tail -1)
[ -n "$X86" ] || X86=1
[ -z "${TACHYON_GATE_X86:-}" ] || X86=$TACHYON_GATE_X86
ONLY=""
BENCH=0
JOBS=""
CPUS=8
FUZZ_N=""
ABI_N=""
HISTORY=fast
FRESH=0
COMPILER=""
INSIDE=0
SEED_BIN=""
LIST=0

die() {
    echo "gate: error: $*" >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --quick) MODE=quick ;;
        --release) MODE=release ;;
        --no-linux) LINUX=0 ;;
        --no-x86) X86=0 ;;
        --with-x86) X86=1 ;;
        --only) [ $# -ge 2 ] || die "--only needs steps"; ONLY=$2; shift ;;
        --only=*) ONLY=${1#--only=} ;;
        --bench) BENCH=1 ;;
        -j) [ $# -ge 2 ] || die "-j needs a number"; JOBS=$2; shift ;;
        -j*) JOBS=${1#-j} ;;
        --cpus) [ $# -ge 2 ] || die "--cpus needs a number"; CPUS=$2; shift ;;
        --cpus=*) CPUS=${1#--cpus=} ;;
        --fuzz) [ $# -ge 2 ] || die "--fuzz needs a number"; FUZZ_N=$2; shift ;;
        --fuzz=*) FUZZ_N=${1#--fuzz=} ;;
        --abi) [ $# -ge 2 ] || die "--abi needs a number"; ABI_N=$2; shift ;;
        --abi=*) ABI_N=${1#--abi=} ;;
        --history) [ $# -ge 2 ] || die "--history needs fast or full"; HISTORY=$2; shift ;;
        --history=*) HISTORY=${1#--history=} ;;
        --fresh) FRESH=1 ;;
        -c) [ $# -ge 2 ] || die "-c needs a compiler"; COMPILER=$2; shift ;;
        --seed) [ $# -ge 2 ] || die "--seed needs a binary"; SEED_BIN=$2; shift ;;
        --inside) INSIDE=1; LINUX=0 ;;
        --list) LIST=1 ;;
        -h|--help) sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option '$1' (see --help)" ;;
    esac
    shift
done
case "$HISTORY" in fast|full) ;; *) die "--history is fast or full" ;; esac
case "$X86" in 0|1) ;; *) die "X86 (bootstrap/gate.conf, \$TACHYON_GATE_X86) is 0 or 1, not '$X86'" ;; esac
for n in "$CPUS" ${JOBS:+"$JOBS"} ${FUZZ_N:+"$FUZZ_N"} ${ABI_N:+"$ABI_N"}; do
    case "$n" in ''|*[!0-9]*) die "'$n' is not a number" ;; esac
done

# ---- The host ----

case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) HOST=aarch64-macos ;;
    Darwin-x86_64) HOST=x86_64-macos ;;
    Linux-x86_64) HOST=x86_64-linux ;;
    Linux-aarch64) HOST=aarch64-linux ;;
    *) die "unsupported host $(uname -s) $(uname -m)" ;;
esac
NCPU=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 4)
case "$NCPU" in ''|*[!0-9]*) NCPU=4 ;; esac
# (On macOS more slots than CPUs do not help: a new program's first launch
# waits for the system's check of it, and those checks are taken about
# one at a time; more programs waiting made the gate slower. See
# docs/releases.md, "The gate".)
[ -n "$JOBS" ] || JOBS=$NCPU

# ---- The steps ----

# The counts of each mode: this host's fuzz and ABI programs per mode,
# then x86_64-linux's (emulated on Apple silicon) and aarch64-linux's.
# On macOS every program costs a launch check (docs/releases.md, "The
# gate"), so the volume of random programs is in aarch64-linux, the same
# code generator, natively; tests/fuzz/forever.sh adds more between
# releases.
case "$MODE" in
    quick) FZ=10; AB=20; XFZ=0; XAB=0; AFZ=0; AAB=0 ;;
    default) FZ=30; AB=30; XFZ=25; XAB=20; AFZ=100; AAB=60 ;;
    release) FZ=60; AB=100; XFZ=50; XAB=40; AFZ=300; AAB=150 ;;
esac
[ -z "$FUZZ_N" ] || { FZ=$FUZZ_N; XFZ=$FUZZ_N; AFZ=$FUZZ_N; }
[ -z "$ABI_N" ] || { AB=$ABI_N; XAB=$ABI_N; AAB=$ABI_N; }

FUZZ_STEPS="fuzz-plain fuzz-loops fuzz-generics fuzz-pressure fuzz-calls fuzz-lang06 fuzz-vector fuzz-div fuzz-range fuzz-seed"
ABI_STEPS="abi-plain abi-import abi-header"
HOST_STEPS="suite-O0 suite-O1 suite-O2 $FUZZ_STEPS $ABI_STEPS objcheck layout debug stress-grow"
LINUX_STEPS="linux-x86_64 linux-aarch64"
[ "$X86" = 1 ] || LINUX_STEPS="linux-aarch64"
case "$MODE" in
    quick) STEPS="suite-O2 $FUZZ_STEPS abi-plain" ;;
    *) STEPS="$HOST_STEPS"; [ $LINUX -eq 1 ] && STEPS="$STEPS $LINUX_STEPS" ;;
esac
if [ -n "$ONLY" ]; then
    # (every known step that one of the patterns matches; the patterns are
    # not file names)
    set -f
    selected=""
    for s in $HOST_STEPS $LINUX_STEPS bench; do
        for p in $(echo "$ONLY" | tr ',' ' '); do
            # shellcheck disable=SC2254
            case "$s" in $p) selected="$selected $s"; break ;; esac
        done
    done
    for p in $(echo "$ONLY" | tr ',' ' '); do
        [ "$p" = chain ] && continue
        found=0
        for s in $HOST_STEPS $LINUX_STEPS bench; do
            # shellcheck disable=SC2254
            case "$s" in $p) found=1 ;; esac
        done
        [ $found -eq 1 ] || die "no step matches '$p' (see --list$([ "$X86" = 1 ] || echo '; x86_64 is off: --with-x86'))"
    done
    set +f
    STEPS=""
    for s in $selected; do
        if [ "$s" = bench ]; then BENCH=1; else STEPS="$STEPS $s"; fi
    done
fi
# The chain, when a step needs the compiler and none was given.
CHAIN=0
if [ -z "$COMPILER" ]; then
    for s in $STEPS; do
        [ "$s" = linux-x86_64 ] || CHAIN=1
    done
    [ $BENCH -eq 1 ] && CHAIN=1
    case ",$ONLY," in *,chain,*) CHAIN=1 ;; esac
fi
if [ $LIST -eq 1 ]; then
    [ $CHAIN -eq 1 ] && echo chain
    for s in $STEPS; do echo "$s"; done
    [ $BENCH -eq 1 ] && echo bench
    exit 0
fi

# ---- The run's directory, the slots ----

if [ $INSIDE -eq 1 ]; then
    RUN="$ROOT/target/gate/inside"
    rm -rf "$RUN"
else
    RUN="$ROOT/target/gate/$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$RUN"
[ $INSIDE -eq 1 ] || ln -sfn "$(basename "$RUN")" "$ROOT/target/gate/last"
rm -f "$RUN/jobs"
mkfifo "$RUN/jobs"
exec 9<>"$RUN/jobs"
i=0
while [ $i -lt "$JOBS" ]; do
    echo >&9
    i=$((i + 1))
done
TACHYON_JOBSERVER="$RUN/jobs"
export TACHYON_JOBSERVER

if [ -n "$COMPILER" ]; then
    case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
    [ -x "$COMPILER" ] || die "no compiler at $COMPILER"
    cp "$COMPILER" "$RUN/tachyonc"
fi
C="$RUN/tachyonc"

# The bootstrap caches: this checkout's, then the shared one (bootstrap.sh:
# $TACHYON_BOOTSTRAP_CACHE, or the main checkout's in a linked worktree).
BOOT_CACHES="$ROOT/target/bootstrap"
if [ -n "${TACHYON_BOOTSTRAP_CACHE:-}" ]; then
    BOOT_CACHES="$BOOT_CACHES $TACHYON_BOOTSTRAP_CACHE"
else
    common=$(cd "$ROOT" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    [ -z "$common" ] || [ "$(dirname "$common")" = "$ROOT" ] \
        || BOOT_CACHES="$BOOT_CACHES $(dirname "$common")/target/bootstrap"
fi

# The seed (the third oracle of fuzz-seed): given, or the bootstrap's.
find_seed() {
    [ -n "$SEED_BIN" ] && { echo "$SEED_BIN"; return; }
    for s in $(for b in $BOOT_CACHES; do echo "$b"/"$HOST"/seed-*/target/release/tachyon; done); do
        [ -x "$s" ] && { echo "$s"; return; }
    done
}

# The newest release built here (for bench/run.sh -p), in the order of
# releases.toml.
find_previous() {
    fp=""
    for tag in $(sh "$ROOT/bootstrap/release-tags.sh"); do
        for b in $BOOT_CACHES; do
            for p in "$b"/"$HOST"/"$tag"-*/tachyonc; do
                [ -x "$p" ] && { fp=$p; break 2; }
            done
        done
    done
    echo "$fp"
}

# Runs step $1 (its output is its log). Exit 77: skipped, the reason on the
# last line.
run_step() {
    k="$RUN/failures/$1"
    case "$1" in
        chain)
            sh "$ROOT/bootstrap/bootstrap.sh" --dev --no-head-tests --history "$HISTORY" </dev/null \
                && cp "$ROOT/target/tachyonc" "$C" ;;
        suite-O*) sh "$ROOT/tests/run.sh" -c "$C" -O "${1#suite-O}" ;;
        fuzz-plain) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" ;;
        fuzz-loops) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -l ;;
        fuzz-generics) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -g ;;
        fuzz-pressure) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -p ;;
        fuzz-calls) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -C ;;
        fuzz-lang06) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -N ;;
        fuzz-vector) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -V ;;
        fuzz-div) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -D ;;
        fuzz-range) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -R ;;
        fuzz-seed)
            seed=$(find_seed)
            if [ -z "$seed" ]; then
                echo "no seed binary for $HOST"
                return 77
            fi
            sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -s "$seed" ;;
        abi-plain) sh "$ROOT/tests/abi/run.sh" -c "$C" -n "$AB" -k "$k" ;;
        abi-import) sh "$ROOT/tests/abi/run.sh" -c "$C" -n "$AB" -k "$k" -i ;;
        abi-header) sh "$ROOT/tests/abi/run.sh" -c "$C" -n "$AB" -k "$k" -H ;;
        objcheck) sh "$ROOT/tests/objcheck.sh" -c "$C" ;;
        layout)
            (cd "$ROOT" && sh tests/cimport/layout.sh -c "$C" stdio.h stdlib.h string.h math.h \
                time.h fcntl.h unistd.h signal.h sys/stat.h sys/time.h sys/socket.h \
                netinet/in.h dirent.h pthread.h) ;;
        debug) sh "$ROOT/tests/debug.sh" -c "$C" ;;
        stress-grow)
            # (0.14) The compiler with TACHYON_STRESS_GROW=1 (base::grow):
            # every growth of its tables moves them and poisons the old
            # block, so a read through a stale table pointer shows. Its
            # self-compile gives the same object as without, and the suite
            # passes at -O0 and -O2.
            o="$RUN/stress-grow"
            mkdir -p "$o"
            "$C" "$ROOT/compiler/src/main.tach" -o "$o/plain.o" || return 1
            TACHYON_STRESS_GROW=1 "$C" "$ROOT/compiler/src/main.tach" -o "$o/stress.o" || return 1
            cmp -s "$o/plain.o" "$o/stress.o" \
                || { echo "stress-grow: the self-compile differs: $o/plain.o $o/stress.o"; return 1; }
            for level in 0 2; do
                TACHYON_STRESS_GROW=1 sh "$ROOT/tests/run.sh" -c "$C" -O $level || return 1
            done
            echo "stress-grow: the self-compile is the same; the suite passes at -O0 and -O2" ;;
        linux-x86_64)
            command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
                || { echo "docker is not running (start it, e.g. colima start; or --no-linux)"; return 1; }
            sh "$ROOT/bootstrap/linux-check.sh" --worktree --dev --cpus "$CPUS" \
                --history "$HISTORY" $([ $FRESH -eq 1 ] && echo --fresh) \
                --all-levels --fuzz="$XFZ" --abi="$XAB" --objcheck </dev/null ;;
        linux-aarch64)
            command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
                || { echo "docker is not running (start it, e.g. colima start; or --no-linux)"; return 1; }
            sh "$ROOT/bootstrap/aarch64-linux-check.sh" --worktree --dev --compiler "$C" --cpus "$CPUS" \
                --all-levels --fuzz="$AFZ" --abi="$AAB" --objcheck --debugger </dev/null ;;
        bench)
            previous=$(find_previous)
            seed=$(find_seed)
            echo "load average before: $(uptime | sed 's/.*load averages*: //')"
            sh "$ROOT/bench/run.sh" -c "$C" ${previous:+-p "$previous"} ${seed:+-s "$seed"} -r 5 ;;
        *) echo "unknown step $1"; return 1 ;;
    esac
}

# ---- The scheduler ----

now() { date +%s; }
GATE_START=$(now)
STARTED=""
REPORTED=""

start() { # <step>
    (
        s=$(now)
        run_step "$1" </dev/null >"$RUN/$1.log" 2>&1
        rc=$?
        echo "$rc $(( $(now) - s ))" >"$RUN/$1.status"
    ) &
    STARTED="$STARTED $1"
}

mmss() { printf '%d:%02d' $(( $1 / 60 )) $(( $1 % 60 )); }

result_of() { # <step>: pass, FAIL, skip or "not run"
    if [ -f "$RUN/$1.status" ]; then
        read -r rc _ <"$RUN/$1.status"
        case "$rc" in
            0) echo pass ;;
            77) echo skip ;;
            *) echo FAIL ;;
        esac
    else
        echo "not run"
    fi
}

# Reports the steps that finished since the last call; sets RUNNING to
# the number still running.
poll() {
    RUNNING=0
    for s in $STARTED; do
        case " $REPORTED " in *" $s "*) continue ;; esac
        if [ -f "$RUN/$s.status" ]; then
            read -r _ secs <"$RUN/$s.status"
            REPORTED="$REPORTED $s"
            [ $INSIDE -eq 1 ] || printf '  %-16s %-5s %6s   (at %s)\n' "$s" "$(result_of "$s")" "$(mmss "$secs")" "$(mmss $(( $(now) - GATE_START )))"
        else
            RUNNING=$((RUNNING + 1))
        fi
    done
}

wait_all() {
    poll
    while [ $RUNNING -gt 0 ]; do
        sleep 1
        poll
    done
}

cleanup() {
    trap - INT TERM
    echo "gate: interrupted; logs in $RUN" >&2
    # Every process below this one (the containers are stopped by their
    # scripts' traps); without ps, the process group.
    if command -v ps >/dev/null 2>&1; then
        # shellcheck disable=SC2046
        kill $(ps -A -o pid= -o ppid= | awk -v root=$$ '
            { parent[$1] = $2 }
            END {
                for (p in parent) {
                    q = p
                    while ((q in parent) && q != root && q > 1) q = parent[q]
                    if (q == root && p != root) print p
                }
            }') 2>/dev/null
    else
        kill 0 2>/dev/null
    fi
    exit 130
}
trap cleanup INT TERM

[ $INSIDE -eq 1 ] || {
    echo "gate: $MODE on $HOST, $JOBS slots${COMPILER:+, compiler $COMPILER}; logs in $RUN"
    echo "  steps: $(echo $([ $CHAIN -eq 1 ] && echo chain) $STEPS $([ $BENCH -eq 1 ] && echo bench))"
}

# On macOS, the first launch of every new executable waits for the
# system's check of it (syspolicyd and XProtect), unless the program that
# runs the gate (the terminal) is a developer tool. Every test program is
# new: measured here, on a new program.
LAUNCH_NOTE=""
case "$HOST" in
    *-macos)
        if command -v perl >/dev/null 2>&1 && printf 'int main(void) { return 0; }\n' >"$RUN/probe.c" \
            && ${CC:-cc} -o "$RUN/probe" "$RUN/probe.c" 2>/dev/null; then
            ms=$(perl -MTime::HiRes=time -e '$t = time; system($ARGV[0]); printf "%d", (time - $t) * 1000' "$RUN/probe")
            if [ "${ms:-0}" -ge 50 ]; then
                LAUNCH_NOTE="a new program's first launch took ${ms} ms here (macOS checks it: about one per test); adding the terminal to System Settings > Privacy & Security > Developer Tools removes that wait (docs/releases.md, \"The gate\")"
                [ $INSIDE -eq 1 ] || echo "  note: $LAUNCH_NOTE"
            fi
        fi ;;
esac

# The x86_64-linux container builds its own chain: it starts at once.
case " $STEPS " in *" linux-x86_64 "*) start linux-x86_64 ;; esac
if [ $CHAIN -eq 1 ]; then
    start chain
    while [ ! -f "$RUN/chain.status" ]; do
        sleep 1
    done
    poll
fi
if [ $CHAIN -eq 0 ] || [ "$(result_of chain)" = pass ]; then
    for s in $STEPS; do
        [ "$s" = linux-x86_64 ] || start "$s"
    done
fi
wait_all
if [ $BENCH -eq 1 ] && { [ $CHAIN -eq 0 ] || [ "$(result_of chain)" = pass ]; }; then
    [ $INSIDE -eq 1 ] || echo "  (the benchmarks, alone)"
    start bench
    wait_all
fi
GATE_SECS=$(( $(now) - GATE_START ))

# ---- The summary ----

# One line about step $1's outcome, from its log.
note_of() {
    l="$RUN/$1.log"
    [ -f "$l" ] || return
    case "$1" in
        chain) awk '/^  head / { sub(/^  head +/, ""); print; exit }' "$l" ;;
        suite-*) awk '$1 == "total" { printf "%d passed, %d xfail, %d failed\n", $2, $3, $4 }' "$l" ;;
        fuzz-*|abi-*|objcheck|layout|debug|stress-grow)
            grep -E '^(fuzz|abi|objcheck|layout|debug|stress-grow):' "$l" | tail -1 ;;
        linux-*) grep '^gate-row' "$l" | awk -F'\t' '$3 != "pass" && $3 != "skip" { bad = bad " " $2 } END { n = NR; print n " steps in the container" (bad == "" ? "" : "; failed:" bad) }' ;;
        bench) grep '^geomean' "$l" | tail -1 ;;
    esac
    [ "$(result_of "$1")" = skip ] && tail -1 "$l"
}

ROWS="$RUN/rows"
: >"$ROWS"
FAILED=0
for s in $([ $CHAIN -eq 1 ] && echo chain) $STEPS $([ $BENCH -eq 1 ] && echo bench); do
    r=$(result_of "$s")
    secs=0
    [ -f "$RUN/$s.status" ] && read -r _ secs <"$RUN/$s.status"
    case "$r" in pass|skip) ;; *) FAILED=$((FAILED + 1)) ;; esac
    printf '%s\t%s\t%s\t%s\n' "$s" "$r" "$secs" "$(note_of "$s" | head -1)" >>"$ROWS"
    # The containers' own steps, under theirs.
    case "$s" in
        linux-*) grep '^gate-row' "$RUN/$s.log" 2>/dev/null | cut -f2- | sed "s|^|$s/|" >>"$ROWS" ;;
    esac
done

if [ $INSIDE -eq 1 ]; then
    sed 's/^/gate-row	/' "$ROWS"
fi
echo
echo "gate: $MODE on $HOST$([ $INSIDE -eq 1 ] && echo " (inside a container)")"
awk -F'\t' '{ printf "  %-28s %-7s %7s  %s\n", $1, $2, sprintf("%d:%02d", $3 / 60, $3 % 60), $4 }' "$ROWS"
printf '  %-28s %-7s %7s\n' "total (wall)" "$([ $FAILED -eq 0 ] && echo pass || echo FAIL)" "$(mmss "$GATE_SECS")"
[ -z "$LAUNCH_NOTE" ] || echo "  note: $LAUNCH_NOTE"

# The failures' details.
for s in $([ $CHAIN -eq 1 ] && echo chain) $STEPS $([ $BENCH -eq 1 ] && echo bench); do
    case "$(result_of "$s")" in pass|skip) continue ;; esac
    echo
    echo "--- $s: $(result_of "$s") (log: $RUN/$s.log)"
    l="$RUN/$s.log"
    [ -f "$l" ] || { echo "    not run (the chain failed)"; continue; }
    case "$s" in
        suite-*) awk '/^tests for / { exit } { print }' "$l" | head -60 ;;
        fuzz-*|abi-*|objcheck) grep -E '^FAIL' "$l" | head -20; [ -d "$RUN/failures/$s" ] && echo "    kept in $RUN/failures/$s" ;;
        linux-*) awk '/^--- / { p = 1 } p' "$l" | head -80; grep -q '^--- ' "$l" || tail -30 "$l" ;;
        *) tail -30 "$l" ;;
    esac
done
[ $INSIDE -eq 1 ] || [ $FAILED -eq 0 ] || echo
[ $FAILED -eq 0 ]
