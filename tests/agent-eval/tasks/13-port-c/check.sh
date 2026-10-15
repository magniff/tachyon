#!/bin/sh
# Structural check for 13-port-c, run in the finished workspace with
# EVAL_LANG=tach|rust. The hidden tests check the output; this checks that
# the program is a port: it does not use reference.c, and it still builds
# and works with reference.c gone.

case "$EVAL_LANG" in
    tach) ext=tach ;;
    rust) ext=rs ;;
    *) echo "check: EVAL_LANG must be tach or rust, got '$EVAL_LANG'" >&2; exit 2 ;;
esac

fail() {
    echo "check: $*" >&2
    exit 1
}

[ -f "main.$ext" ] || fail "main.$ext is missing"

files=$(find . -name "*.$ext" -not -path './.git/*' | sort)

# No C source pulled in: no "x.c" file names, no link attributes, no
# compile-time inclusion of other files.
hit=$(grep -nE '\.c"|\.o"|#\[link|link_name|include!|include_str!|include_bytes!' $files | head -n 1 | cut -c1-100)
[ -z "$hit" ] || fail "the sources refer to C code or link attributes: $hit"

# Rebuild in a scratch copy without reference.c and run two small inputs.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/check13.XXXXXX") || fail "mktemp failed"
trap 'rm -rf "$tmp"' EXIT
# (0.16) The whole workspace, its directories kept: `cp $files` flattened
# them, so a copy such as scratch/main.tach replaced main.tach.
tar cf - --exclude ./.git --exclude ./prog . | (cd "$tmp" && tar xf -) ||
    fail "copying the sources failed"
cd "$tmp" || fail "cd failed"
rm -f reference.c prog
case "$EVAL_LANG" in
    tach) tachyonc main.tach -o prog >build.log 2>&1 ;;
    rust) rustc -O --edition 2021 main.rs -o prog >build.log 2>&1 ;;
esac
[ -x prog ] || fail "does not build without reference.c"

printf 'compress\nto be or not to be, that is the question; to be, or not to be\n' >in1
cat >want1 <<'EOF'
compressed 62 -> 58 bytes (34 literals, 4 matches), crc32 132fedde
4c5a013e000000deed2f1300746f206265206f7220206e6f74200c022c208074
6861742069730700006520717565737469186f6e3b1c052a090a
EOF
./prog <in1 >got1 2>/dev/null || fail "the rebuilt program fails on a compress input"
cmp -s got1 want1 || fail "the rebuilt program gives the wrong output on a compress input"

printf 'decompress\n4c5a013e000000deed2f1300746f206265206f7220206e6f74200c022c208074\n6861742069730700006520717565737469186f6e3b1c052a090a\n' >in2
cat >want2 <<'EOF'
decompressed 58 -> 62 bytes, crc32 132fedde
to be or not to be, that is the question; to be, or not to be
EOF
./prog <in2 >got2 2>/dev/null || fail "the rebuilt program fails on a decompress input"
cmp -s got2 want2 || fail "the rebuilt program gives the wrong output on a decompress input"
exit 0
