#!/bin/sh
# Debug information against a real debugger (0.11): tests/debug/crash.vl
# (two files) is compiled with -g at -O0 and -O2 and run under lldb
# (macOS) or gdb (Linux). Breakpoints on source lines of both files must
# stop there, and the backtrace of the crash that follows must give every
# frame's function, file and line.
#
# usage: tests/debug.sh [-c COMPILER] [-t TARGET]
#
#   -c COMPILER   the volec to test (default: target/volec)
#   -t TARGET     the target (default: the host); its programs must run here

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/volec"
TARGET=""
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -t) TARGET=$2; shift 2 ;;
        *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
if [ -z "$TARGET" ]; then
    TARGET=$("$COMPILER" --version | sed 's/.*host: \([a-z0-9_-]*\).*/\1/')
fi
case "$TARGET" in
    *-macos) DEBUGGER=lldb ;;
    *) DEBUGGER=gdb ;;
esac
command -v "$DEBUGGER" >/dev/null 2>&1 || { echo "debug: no $DEBUGGER here: not checked"; exit 0; }
if [ "$TARGET" = x86_64-macos ] && [ "$(uname -m)" = arm64 ]; then
    # (lldb does not debug programs run by Rosetta)
    echo "debug: x86_64-macos programs run under Rosetta here, which lldb cannot debug: not checked"
    exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-debug.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM

# What the debugger must print, one pattern per line, in order: a
# breakpoint in each file (with its frame), then the frames of the crash.
cat >"$WORK/expect" <<'EOF'
total.* at .*helper.vl:10
poke.* at .*crash.vl:13
poke.* at .*crash.vl:13
outer.* at .*crash.vl:20
main.* at .*crash.vl:26
EOF

failed=0
for o in 0 2; do
    exe="$WORK/crash$o"
    if ! (cd "$ROOT" && "$COMPILER" --target "$TARGET" -g "-O$o" tests/debug/crash.vl -o "$exe") >"$WORK/out" 2>&1; then
        echo "FAIL -O$o: compilation: $(head -c 300 "$WORK/out")"
        failed=$((failed + 1))
        continue
    fi
    # Three runs: stopped at each breakpoint, then the crash.
    : >"$WORK/log$o"
    for stop in helper.vl:10 crash.vl:13 crash; do
        if [ "$DEBUGGER" = lldb ]; then
            if [ "$stop" = crash ]; then
                printf 'run\nbt\nquit\n' >"$WORK/cmds"
            else
                printf 'breakpoint set --file %s --line %s\nrun\nbt 1\nkill\nquit\n' \
                    "${stop%:*}" "${stop#*:}" >"$WORK/cmds"
            fi
            # (at most 2 minutes: an lldb waiting for the system to let it
            # attach, as after a reboot under load, would hang the gate)
            (cd "$ROOT" && perl -e 'alarm 120; exec @ARGV' lldb -b -s "$WORK/cmds" "$exe") \
                >>"$WORK/log$o" 2>&1 || echo "(lldb: exit $?)" >>"$WORK/log$o"
        elif [ "$stop" = crash ]; then
            (cd "$ROOT" && gdb -q -batch -ex 'set pagination off' -ex run -ex bt -ex kill "$exe") \
                >>"$WORK/log$o" 2>&1
        else
            (cd "$ROOT" && gdb -q -batch -ex 'set pagination off' -ex "break $stop" -ex run \
                -ex 'bt 1' -ex kill "$exe") >>"$WORK/log$o" 2>&1
        fi
    done
    if grep -q "Couldn't get registers" "$WORK/log$o"; then
        # (gdb under an emulator without ptrace, as Rosetta runs x86-64
        # Linux on Apple silicon)
        echo "debug: $DEBUGGER cannot control programs here (an emulated machine?): not checked"
        exit 0
    fi
    # The patterns, in order, each on a later line than the one before.
    if ! awk -v logfile="$WORK/log$o" '
        { want[++n] = $0 }
        END {
            k = 1
            while (k <= n && (getline line < logfile) > 0)
                if (line ~ want[k]) k++
            if (k <= n) { print "missing: " want[k]; exit 1 }
        }' "$WORK/expect" >"$WORK/why"; then
        echo "FAIL -O$o: $(cat "$WORK/why") (with $DEBUGGER)"
        if grep -q 'Not allowed to attach\|lldb: exit 142' "$WORK/log$o"; then
            echo "    (lldb could not run the program: the system did not let it attach, or it waited; DevToolsSecurity -status, and rerun: gate.sh --only debug)"
        fi
        sed 's/^/    /' "$WORK/log$o" | tail -30
        failed=$((failed + 1))
        continue
    fi
    echo "ok -O$o"
done
echo "debug: tests/debug/crash.vl at -O0 and -O2 under $DEBUGGER for $TARGET, $failed failing"
[ "$failed" -eq 0 ]
