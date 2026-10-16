#!/bin/sh
# The shader compiler's tests (lib/wgsl, docs/design/gpu.md §4): every
# tests/wgsl/cases/*.wgsl is translated by wgslc and checked:
#
#   // ERROR: text     the translation fails with an error containing text
#                      (one directive per line of the expected message)
#   // JOB: line       a line of the compute job (`wgslc run`'s format):
#                      the interpreter runs it, and on macOS so does Metal
#                      (tests/wgsl/metalrun); the outputs must agree
#   // ULP: n          float words may differ by n units in the last place
#   // EXPECT: line    a line of the interpreter's expected output
#
# Every case without ERROR also has its MSL compiled by Metal (macOS),
# and its SPIR-V validated by spirv-val where it is installed (the gpu
# container image). A case whose need is missing is skipped, never passed.
#
# usage: tests/wgsl/run.sh [-c COMPILER] [FILTER]
#
# Prints `pass NAME`, `skip NAME (why)` or `FAIL NAME` (and why) for each;
# exits 1 if one failed.
set -u
LC_ALL=C
export LC_ALL
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/tachyonc"
FILTER=""
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        *) FILTER=$1; shift ;;
    esac
done
WORK=$(mktemp -d "${TMPDIR:-/tmp}/wgsl.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

fail=0
# The compiler: wgslc, from lib/wgsl.
if ! "$COMPILER" "$ROOT/lib/wgsl/main.tach" -o "$WORK/wgslc" >"$WORK/build.out" 2>&1; then
    echo "FAIL wgsl_build:"
    sed 's/^/    /' "$WORK/build.out"
    exit 1
fi
W="$WORK/wgslc"

# Metal: metalrun, linked with the frameworks by hand (no -framework in
# tachyonc before C4).
METAL=""
if [ "$(uname -s)" = Darwin ] && command -v cc >/dev/null 2>&1; then
    if "$COMPILER" "$HERE/metalrun/main.tach" -c -o "$WORK/metalrun.o" >"$WORK/mbuild.out" 2>&1 \
        && cc "$WORK/metalrun.o" -framework Metal -framework Foundation -lobjc -o "$WORK/metalrun" >>"$WORK/mbuild.out" 2>&1; then
        METAL="$WORK/metalrun"
    else
        echo "FAIL wgsl_metalrun_build:"
        sed 's/^/    /' "$WORK/mbuild.out"
        fail=1
    fi
fi
SPIRV_VAL=""
if command -v spirv-val >/dev/null 2>&1; then
    SPIRV_VAL=spirv-val
fi

# directive NAME FILE: the values of `// NAME: value` lines, one a line
directive() {
    awk -v key="$1" '
        {
            line = $0
            sub(/^[ \t]+/, "", line)
            if (substr(line, 1, 3) != "// ") next
            line = substr(line, 4)
            k = index(line, ": ")
            if (k == 0 || substr(line, 1, k - 1) != key) next
            print substr(line, k + 2)
        }' "$2"
}

for f in "$HERE"/cases/*.wgsl; do
    name=$(basename "$f" .wgsl)
    case "$name" in *"$FILTER"*) ;; *) continue ;; esac
    d="$WORK/$name"
    mkdir -p "$d"
    why=""
    directive ERROR "$f" >"$d/errors"
    if [ -s "$d/errors" ]; then
        if "$W" check "$f" >"$d/out" 2>&1; then
            why="it translates, but an error was expected"
        else
            while IFS= read -r want; do
                grep -qF -- "$want" "$d/out" || why="${why}no error containing '$want'; "
            done <"$d/errors"
        fi
        if [ -n "$why" ]; then
            echo "FAIL wgsl_$name:"
            echo "    $why"
            sed 's/^/    /' "$d/out"
            fail=1
        else
            echo "pass wgsl_$name"
        fi
        continue
    fi
    if ! "$W" msl "$f" -o "$d/out.metal" >"$d/msl.err" 2>&1; then
        echo "FAIL wgsl_$name: wgslc msl"
        sed 's/^/    /' "$d/msl.err"
        fail=1
        continue
    fi
    directive JOB "$f" >"$d/job"
    ulp=$(directive ULP "$f")
    [ -n "$ulp" ] || ulp=0
    if [ -s "$d/job" ]; then
        if ! "$W" run "$f" "$d/job" >"$d/interp" 2>"$d/interp.err"; then
            why="the interpreter failed: $(cat "$d/interp.err")"
        fi
        directive EXPECT "$f" >"$d/expect"
        if [ -z "$why" ] && [ -s "$d/expect" ] && ! "$W" compare "$d/interp" "$d/expect" >"$d/cmp" 2>&1; then
            why="the interpreter's output is not the expected one: $(cat "$d/cmp")"
        fi
        if [ -z "$why" ] && [ -n "$METAL" ]; then
            "$W" metal-job "$f" "$d/job" >"$d/mjob" 2>"$d/mjob.err" && echo end >>"$d/mjob"
            if [ ! -s "$d/mjob" ]; then
                why="wgslc metal-job: $(cat "$d/mjob.err")"
            elif ! "$METAL" <"$d/mjob" >"$d/metal" 2>&1; then
                why="Metal: $(head -5 "$d/metal")"
            else
                grep -v '^end$' "$d/metal" >"$d/metal.out"
                if ! "$W" compare "$d/interp" "$d/metal.out" --ulp "$ulp" >"$d/cmp" 2>&1; then
                    why="Metal and the interpreter differ: $(cat "$d/cmp")"
                fi
            fi
        fi
    elif [ -n "$METAL" ]; then
        # no job: Metal compiles the MSL and finds every entry point
        "$W" metal-job "$f" - >"$d/mjob" 2>"$d/mjob.err" && echo end >>"$d/mjob"
        if [ ! -s "$d/mjob" ]; then
            why="wgslc metal-job: $(cat "$d/mjob.err")"
        elif ! "$METAL" <"$d/mjob" >"$d/metal" 2>&1; then
            why="Metal: $(head -5 "$d/metal")"
        fi
    fi
    if [ -z "$why" ] && [ -n "$SPIRV_VAL" ]; then
        if ! "$W" spv "$f" -o "$d/out.spv" >"$d/spv.err" 2>&1; then
            why="wgslc spv: $(cat "$d/spv.err")"
        elif ! spirv-val --target-env vulkan1.3 "$d/out.spv" >"$d/val" 2>&1; then
            why="spirv-val: $(head -5 "$d/val")"
        fi
    fi
    if [ -n "$why" ]; then
        echo "FAIL wgsl_$name:"
        echo "    $why" | head -20
        fail=1
    else
        echo "pass wgsl_$name"
    fi
done
[ -n "$METAL" ] || echo "skip wgsl_metal (no Metal on this host)"
[ -n "$SPIRV_VAL" ] || echo "skip wgsl_spirv_val (no spirv-val on this host)"
exit $fail
