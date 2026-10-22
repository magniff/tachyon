#!/bin/sh
# The link (0.25, back::objfile::output): a program of vole objects only
# is linked by the system's linker run directly, with the command `cc -###`
# gave (the link template, kept in $VOLE_LINK_CACHE). POSIX sh only.
#
# usage: tests/link/run.sh [-c COMPILER]
#
# Checks, each printed `pass NAME` or `FAIL NAME` (and why); exits 1 if
# one failed:
#   same        the executable is the one `--linker=cc` makes, byte for byte
#   template    the first link writes a template; the next reads it
#   stale       a template naming a file that is gone is made again
#   fallback    a template whose linker fails: the link goes through cc,
#               and the template is dropped
#   off         $VOLE_LINK_CACHE=off: no template kept, the link works
#   errors      a link that fails says so as cc does, once
#   linker      $VOLE_LINKER=cc is --linker=cc; an unknown one is an error

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/volec"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        *) echo "usage: tests/link/run.sh [-c COMPILER]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "link/run.sh: no compiler at $COMPILER" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-link.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
unset VOLE_LINKER VOLE_CC
VOLE_CODE_CACHE=off
export VOLE_CODE_CACHE
VOLE_LINK_CACHE="$WORK/cache"
export VOLE_LINK_CACHE
mkdir "$VOLE_LINK_CACHE"
STATUS=0
cd "$WORK" || exit 2

pass() { echo "pass $1"; }
fail() {
    echo "FAIL $1"
    echo "    $2"
    STATUS=1
}

cat >hello.vl <<'EOF'
fn main() {
    println("hello");
}
EOF
cat >missing.vl <<'EOF'
extern "C" {
    fn vole_link_test_missing() -> i32;
}

fn main() {
    let x = unsafe { vole_link_test_missing() };
    println(f"{x}");
}
EOF

# build ARGS...: the compiler, its output into build.out; its status.
build() {
    "$COMPILER" "$@" >build.out 2>&1
}

templates() {
    ls "$VOLE_LINK_CACHE" | grep -c '^vole-link-[0-9a-f]*$'
}

# same
if build hello.vl -o prog && [ "$(./prog)" = hello ] && cp prog prog.direct \
    && build --linker=cc hello.vl -o prog && cmp -s prog prog.direct; then
    pass same
else
    fail same "the direct link and cc's differ (or one failed): $(cat build.out)"
fi

# template
T=$(ls "$VOLE_LINK_CACHE"/vole-link-* 2>/dev/null | head -1)
if [ "$(templates)" = 1 ] && grep -qx '@vole-obj' "$T" && grep -qx '@vole-out' "$T" \
    && build hello.vl -o prog && [ "$(./prog)" = hello ] && [ "$(templates)" = 1 ]; then
    pass template
else
    fail template "no template, or not one: $(ls "$VOLE_LINK_CACHE")"
fi

# stale: a template whose stamp no longer holds (a path it names is gone)
if [ -n "$T" ]; then
    { head -1 "$T"; echo "$WORK/gone/ld"; tail -n +3 "$T"; } >"$T.new" && mv "$T.new" "$T"
    if build hello.vl -o prog && [ "$(./prog)" = hello ] && ! grep -q "$WORK/gone" "$T" \
        && cmp -s prog prog.direct; then
        pass stale
    else
        fail stale "a stale template was used: $(cat build.out)"
    fi
fi

# fallback: a template whose linker fails (an option it does not know,
# which the stamp does not cover)
if [ -n "$T" ]; then
    build hello.vl -o prog
    { head -2 "$T"; echo "--vole-no-such-option"; tail -n +3 "$T"; } >"$T.new" && mv "$T.new" "$T"
    if build hello.vl -o prog && [ "$(./prog)" = hello ] && [ "$(templates)" = 0 ] \
        && cmp -s prog prog.direct && ! grep -q 'vole-no-such-option' build.out; then
        pass fallback
    else
        fail fallback "after a failing linker: $(cat build.out); templates: $(ls "$VOLE_LINK_CACHE")"
    fi
fi

# off
rm -f "$VOLE_LINK_CACHE"/*
if env VOLE_LINK_CACHE=off "$COMPILER" hello.vl -o prog >build.out 2>&1 && [ "$(./prog)" = hello ] \
    && [ "$(templates)" = 0 ] && cmp -s prog prog.direct; then
    pass off
else
    fail off "with VOLE_LINK_CACHE=off: $(cat build.out)"
fi

# errors: the undefined symbol, named once, then the compiler's line
if build missing.vl -o prog; then
    fail errors "linked a program with an undefined symbol"
elif [ "$(grep -c 'vole_link_test_missing' build.out)" -lt 1 ] \
    || ! grep -q 'error: linking failed' build.out \
    || [ "$(grep -c 'linking failed' build.out)" != 1 ]; then
    fail errors "not cc's message: $(cat build.out)"
else
    pass errors
fi

# linker
if env VOLE_LINKER=cc "$COMPILER" hello.vl -o prog >build.out 2>&1 && cmp -s prog prog.direct \
    && ! env VOLE_LINKER=nonesuch "$COMPILER" hello.vl -o prog >build.out 2>&1 && grep -q 'not a linker' build.out; then
    pass linker
else
    fail linker "VOLE_LINKER: $(cat build.out)"
fi

exit $STATUS
