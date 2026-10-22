#!/bin/sh
# The window library's tests (0.23, terminal.md §4.1), std::window on
# Cocoa: the key tables and text helpers (headless), then, when a window
# server is there (NEEDS: display; VOLE_NO_DISPLAY_TESTS=1 skips),
# a real window driven by synthesized events: its first size, frames on
# request and none without, the CAMetalLayer presenting the renderer's
# grid, keys and text through interpretKeyEvents, an input method's
# composition and commit, the mouse, the wheel, a resize, the clipboard
# (restored), a watched pipe, close, Quit, and no CPU while idle.
# main.vl is built at -O2 (std links its frameworks) and run from the
# root. macOS only (the Wayland and X11 backends are 0.23.1).
#
# usage: tests/window/run.sh [-c COMPILER] [-v]
#   -v   print the bench lines too
#
# Prints `pass NAME` or `FAIL NAME` (and why) for each check; exits 1 if
# one failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/volec"
VERBOSE=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        -v) VERBOSE=1; shift ;;
        *) echo "usage: tests/window/run.sh [-c COMPILER] [-v]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac

if [ "$(uname -s)" != Darwin ]; then
    echo "pass window (skipped: macOS only)"
    exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-window.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM

if ! (cd "$ROOT" && "$COMPILER" -O2 tests/window/main.vl -o "$WORK/prog") \
        >"$WORK/build.out" 2>&1; then
    echo "FAIL window_build:"
    head -20 "$WORK/build.out" | sed 's/^/    /'
    exit 1
fi
(cd "$ROOT" && "$WORK/prog" test) >"$WORK/run.out" 2>&1
status=$?
[ "$VERBOSE" = 1 ] && grep '^bench' "$WORK/run.out"
awk '
    /^ok / { print "pass window_" $2; next }
    /^FAIL / { sub(/^FAIL /, ""); print "FAIL window_" $0; bad = 1; next }
    /^skip / { print "pass window (" $0 ")"; next }
' "$WORK/run.out"
if [ $status -ne 0 ] && ! grep -q '^FAIL' "$WORK/run.out"; then
    echo "FAIL window_run: exit $status"
    tail -5 "$WORK/run.out" | sed 's/^/    /'
    exit 1
fi

# voltty assembled (examples/voltty/app): a window, a program on a pty,
# its output drawn through std::gpu; the last frame, written as a PPM,
# has ink (bytes other than the background's 0x18). With a display only.
app_status=0
if grep -q '^skip display' "$WORK/run.out"; then
    echo "pass window (voltty_app skipped: no display)"
elif ! (cd "$ROOT" && "$COMPILER" -O2 examples/voltty/app/main.vl -o "$WORK/voltty") \
        >"$WORK/app-build.out" 2>&1; then
    echo "FAIL window_voltty_app_build:"
    head -20 "$WORK/app-build.out" | sed 's/^/    /'
    app_status=1
else
    "$WORK/voltty" -o "$WORK/app.ppm" -- /bin/sh -c 'echo voltty draws text; ls /; sleep 1' \
        >"$WORK/app.out" 2>&1 &
    pid=$!
    n=0
    while kill -0 $pid 2>/dev/null && [ $n -lt 200 ]; do
        sleep 0.1
        n=$((n + 1))
    done
    kill $pid 2>/dev/null
    wait $pid
    ink=0
    [ -f "$WORK/app.ppm" ] && ink=$(tr -d '\030' <"$WORK/app.ppm" | wc -c | tr -d ' ')
    if [ "$ink" -gt 2000 ]; then
        echo "pass window_voltty_app"
    else
        echo "FAIL window_voltty_app: no text drawn ($ink bytes of ink)"
        sed 's/^/    /' "$WORK/app.out" | head -5
        app_status=1
    fi
fi
[ $status -eq 0 ] && [ $app_status -eq 0 ]
