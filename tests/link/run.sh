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
#   declared    an extern block's #[link(...)] and -framework reach the
#               link (macOS: the executable loads them; Linux leaves a
#               framework out), a hello world links nothing more, and an
#               unknown key is an error
# and, on aarch64 macOS, the compiler's own linker (--linker=internal,
# back::objfile::link_macho):
#   internal    the executable runs, its signature verifies, and the same
#               input gives the same bytes
#   default     it is the default
#   internal-ld a program it does not take (an import libSystem lacks) is
#               linked by ld, which says why it fails
#   libsystem   libSystem has every name of link_macho's LIBSYSTEM

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
unset VOLE_CC
# (the system's linker, run directly, unless a check says otherwise: on
# aarch64 macOS the default is the compiler's own)
VOLE_LINKER=system
export VOLE_LINKER
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

# declared
cat >declared.vl <<'EOF'
#[link(lib = "m")]
#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn ilogb(x: f64) -> i32;
}

fn main() {
    println(f"{unsafe { ilogb(8.0) }}");
}
EOF
cat >badkey.vl <<'EOF'
#[link(library = "m")]
extern "C" {
    fn ilogb(x: f64) -> i32;
}

fn main() {}
EOF
if ! build declared.vl -framework CoreGraphics -o prog || [ "$(./prog)" != 3 ]; then
    fail declared "#[link]: $(cat build.out)"
elif [ "$(uname -s)" = Darwin ] && ! { otool -L prog | grep -q CoreFoundation.framework \
    && otool -L prog | grep -q CoreGraphics.framework; }; then
    fail declared "the frameworks are not loaded: $(otool -L prog)"
elif ! build hello.vl -o prog || { [ "$(uname -s)" = Darwin ] && [ "$(otool -L prog | grep -c dylib)" != 1 ]; }; then
    fail declared "hello world links more: $(otool -L prog 2>&1)"
elif build badkey.vl -o prog || ! grep -q "unknown key 'library' in #\[link\]" build.out; then
    fail declared "an unknown key: $(cat build.out)"
else
    pass declared
fi

if [ "$(uname -s)-$(uname -m)" = Darwin-arm64 ]; then
    # internal
    if build --linker=internal hello.vl -o prog && [ "$(./prog)" = hello ] \
        && codesign -v prog 2>/dev/null && cp prog prog.internal \
        && build --linker=internal hello.vl -o prog && cmp -s prog prog.internal \
        && ! cmp -s prog prog.direct; then
        pass internal
    else
        fail internal "--linker=internal: $(cat build.out); $(codesign -v prog 2>&1)"
    fi

    # default: the compiler's own linker, without --linker
    if env -u VOLE_LINKER "$COMPILER" hello.vl -o prog >build.out 2>&1 && cmp -s prog prog.internal; then
        pass default
    else
        fail default "without --linker, not the internal linker's bytes: $(cat build.out)"
    fi

    # internal-ld
    if build --linker=internal missing.vl -o prog; then
        fail internal-ld "linked a program with an undefined symbol"
    elif ! grep -q 'vole_link_test_missing' build.out || ! grep -q 'error: linking failed' build.out; then
        fail internal-ld "not ld's message: $(cat build.out)"
    else
        pass internal-ld
    fi

    # libsystem
    awk '/^const LIBSYSTEM:/ { p = 1; next } p && /^\];/ { p = 0 } p' \
        "$ROOT/compiler/src/back/objfile/link_macho.vl" | tr ',' '\n' \
        | sed -n 's/.*c"\([A-Za-z0-9_]*\)".*/\1/p' >names.txt
    cat >has.c <<'EOF'
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    void *h = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY);
    char line[256];
    int bad = 0;
    while (h && fgets(line, sizeof line, stdin)) {
        line[strcspn(line, "\n")] = 0;
        if (!dlsym(h, line)) {
            printf("%s\n", line);
            bad = 1;
        }
    }
    return h ? bad : 2;
}
EOF
    if [ "$(wc -l <names.txt)" -lt 200 ]; then
        fail libsystem "LIBSYSTEM not found in link_macho.vl ($(wc -l <names.txt) names)"
    elif ! cc has.c -o has >has.out 2>&1; then
        fail libsystem "cc has.c: $(cat has.out)"
    elif ! ./has <names.txt >has.out; then
        fail libsystem "libSystem lacks: $(tr '\n' ' ' <has.out)"
    else
        pass libsystem
    fi
fi

exit $STATUS
