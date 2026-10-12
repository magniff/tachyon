#!/bin/sh
# Layout conformance of `import`: for every struct and union imported from
# the given C headers, C (compiled by cc) and tachyon must agree on its
# size, its alignment and the offset of every field.
#
# usage: tests/cimport/layout.sh [-c COMPILER] [-t TARGET] [-I DIR] HEADER...
#
#   -c COMPILER   the tachyonc to test (default: target/tachyonc)
#   -t TARGET     the target (default: the host)
#   -I DIR        an include directory (for both compilers)
#
# Prints "layout: N records, M fields agree" or the differences.
set -eu

compiler=target/tachyonc
target=
incs=
while [ $# -gt 0 ]; do
    case $1 in
        -c) compiler=$2; shift 2 ;;
        -t) target=$2; shift 2 ;;
        -I) incs="$incs -I $2"; shift 2 ;;
        *) break ;;
    esac
done
[ $# -gt 0 ] || { echo "usage: $0 [-c COMPILER] [-t TARGET] [-I DIR] HEADER..." >&2; exit 2; }

tflag=
arch=
case $target in
    aarch64-macos) tflag="--target $target"; arch="-arch arm64" ;;
    x86_64-macos) tflag="--target $target"; arch="-arch x86_64" ;;
    x86_64-linux) tflag="--target $target" ;;
esac

dir=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-layout.XXXXXX")
trap 'rm -rf "$dir"' EXIT

{
    for h in "$@"; do echo "import \"$h\" as c;"; done
    echo 'import "stdio.h" as c;'
} > "$dir/imp.tach"
# shellcheck disable=SC2086
"$compiler" $tflag $incs --emit-imports "$dir/imp.tach" -o "$dir/imp.out"

# The records with a C spelling, and their fields (not padding).
awk -v cfile="$dir/check.c" -v tfile="$dir/check.tach" -v headers="$*" '
BEGIN {
    n = split(headers, hs, " ")
    for (i = 1; i <= n; i++) print "#include <" hs[i] ">" > cfile
    print "#include <stdio.h>\n#include <stddef.h>\nint main(void) {" > cfile
    for (i = 1; i <= n; i++) print "import \"" hs[i] "\" as c;" > tfile
    print "import \"stdio.h\" as c;\nfn main() -> i32 {" > tfile
}
/^\/\/ C: / { pending = substr($0, 7); next }
/^#\[repr/ { next }
/^(struct|union) [^ ]+ \{$/ {
    if (pending != "") { tname = $2; rec_c = pending; active = 1; nf = 0 }
    pending = ""
    next
}
active && /^    [^ ]+: / {
    f = $1; sub(/:$/, "", f)
    if (f ~ /^(r#)?_(pad|bitfield|anon)[0-9]+_*$/) next
    fields[++nf] = f
    next
}
active && /^\}$/ {
    printf "    printf(\"%s %%zu %%zu\", sizeof(%s), _Alignof(%s));\n", tname, rec_c, rec_c > cfile
    printf "    let p%d = 4096 as *c::%s;\n", ++k, tname > tfile
    printf "    c::printf(c\"%s %%zu %%zu\", size_of(c::%s), align_of(c::%s));\n", tname, tname, tname > tfile
    for (i = 1; i <= nf; i++) {
        cf = fields[i]; sub(/^r#/, "", cf)
        printf "    printf(\" %%zu\", offsetof(%s, %s));\n", rec_c, cf > cfile
        printf "    c::printf(c\" %%zu\", (&(*p%d).%s) as u64 - 4096);\n", k, fields[i] > tfile
        nfields++
    }
    print "    printf(\"\\n\");" > cfile
    print "    c::printf(c\"\\n\");" > tfile
    active = 0; records++
    next
}
{ if (!active) pending = "" }
END {
    print "    return 0;\n}" > cfile
    print "    0\n}" > tfile
    print records + 0, nfields + 0 > "/dev/stderr"
}
' "$dir/imp.out" 2> "$dir/counts"

# shellcheck disable=SC2086
cc $arch $incs -o "$dir/c" "$dir/check.c"
# shellcheck disable=SC2086
"$compiler" $tflag $incs "$dir/check.tach" -o "$dir/t.o"
# shellcheck disable=SC2086
cc $arch -o "$dir/t" "$dir/t.o" -lm
"$dir/c" > "$dir/c.out"
"$dir/t" > "$dir/t.out"
read -r records fields < "$dir/counts"
if cmp -s "$dir/c.out" "$dir/t.out"; then
    echo "layout: $records records, $fields fields agree"
else
    echo "layout: differences (name size align offsets...; < C, > tachyon):"
    diff "$dir/c.out" "$dir/t.out" | head -40
    exit 1
fi
