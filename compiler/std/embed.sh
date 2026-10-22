#!/bin/sh
# Makes compiler/src/front/stdsrc.vl from std's files: the standard
# library's source, built into the compiler as a function that writes it
# to a buffer (string literals cannot span lines: a call for each few
# lines, 0.21).
#
# std is a crate of its own (0.20): its root module is compiler/std/std.vl
# and the files appended to it, in this order (ROOT_FILES, those of them
# that exist): flat/iter.vl (0.14), flat/io.vl, flat/fmt.vl,
# flat/convert.vl and flat/clone.vl (0.15), flat/alloc.vl (0.16),
# flat/values.vl (0.17), flat/test.vl, flat/nonnull.vl, flat/fuzz.vl
# (0.18), flat/collections.vl (0.18.1), flat/arch.vl (0.19): the files
# of the one module std was before 0.20, in flat/ so that std's modules
# can have their names. A `mod NAME;` line of the root's files is the module std::NAME,
# in compiler/std/NAME.vl or NAME/mod.vl, and so on down (a module in
# a.vl has its children in a/, as in any program). The built-in text is
# the root's files, then each module as `mod NAME { ... }` after its
# parent's text (its `mod NAME;` line stays, and the compiler reads the
# braces instead: front/modules: load_modules), each between banners
# `// ---- mod std::NAME ----` and `// ---- end mod std::NAME ----`, so
# that index.awk keeps their lines in sections always read.
#
# Its end is front/stdalloc.vl's std_alloc_tail (0.16): Gpa's
# implementation, gpa.vl (std_gpa_source here), and std::CHECK_ALLOC;
# with --check-alloc, the checking Gpa, alloc_check.vl
# (std_check_gpa_source), and its index (std_check_index).
# (0.20) After them, the target's system: sys/macos.vl or sys/linux.vl
# (std_sys_source), the same length to the byte so that one index holds
# for both (checked here): std::TARGET_OS and what differs between the C
# libraries, for std::sys.
# Run it after changing any of them; tests/run.sh checks they agree.
# (0.17: `volec edit` of a std item, or of one of these files, runs it.)
# (0.15) It also writes std_index, the sections' index (index.awk), and
# (0.20) std_files, where each file's text starts in std's text.
#
# usage: compiler/std/embed.sh [-c | --core]   (-c: only check, exit 1 if
# stale; --core: the sections every program reads, and why)
set -eu
cd "$(dirname "$0")/../.."
out=compiler/src/front/stdsrc.vl
# (next to the output: writable in a sandbox that only allows the tree, and mv is a rename)
tmp=$(mktemp "$out.XXXXXX")
work=$(mktemp -d "${TMPDIR:-/tmp}/vole-embed.XXXXXX")
trap 'rm -rf "$work"' EXIT
# std's root module: these files (front/stdtree.vl: std_tree_file).
ROOT_FILES="std flat/iter flat/io flat/fmt flat/convert flat/clone flat/alloc flat/values flat/test flat/nonnull flat/fuzz flat/collections flat/arch"
dir=compiler/std
# (0.20) The two systems' tails are one index's text: the same length.
if [ "$(wc -c <compiler/std/sys/macos.vl)" != "$(wc -c <compiler/std/sys/linux.vl)" ]; then
    rm -f "$tmp"
    echo "compiler/std/sys/macos.vl and sys/linux.vl differ in length: pad a comment" >&2
    exit 1
fi
text=$work/text
map=$work/map
: >"$text"
: >"$map"

# The text of module PATH (std, std::a): its files (FILES, relative to $dir,
# without `.vl`), then its modules; NESTED: the directory (relative, with
# its `/`, or empty) where its `mod NAME;` lines find their files. A
# subshell: its variables are its own.
walk() (
    path=$1
    nested=$2
    shift 2
    files=""
    for f in "$@"; do
        [ -f "$dir/$f.vl" ] || continue
        files="$files $dir/$f.vl"
        echo "$(wc -c <"$text" | tr -d ' ') $f.vl" >>"$map"
        cat "$dir/$f.vl" >>"$text"
    done
    mods=$work/mods.$(echo "$path" | tr ':' '_')
    # shellcheck disable=SC2086
    cat $files |
        sed -n 's/^\(pub \)\{0,1\}mod \([A-Za-z_][A-Za-z0-9_]*\);.*$/\1\2/p' >"$mods"
    while read -r m; do
        vis=""
        name=$m
        case "$m" in "pub "*) vis="pub "; name=${m#pub } ;; esac
        if [ -f "$dir/$nested$name.vl" ]; then
            file=$nested$name
        elif [ -f "$dir/$nested$name/mod.vl" ]; then
            file=$nested$name/mod
        else
            echo "embed.sh: no file for module $path::$name ($dir/$nested$name.vl)" >&2
            exit 1
        fi
        printf '// ---- mod %s::%s ----\n%smod %s {\n' "$path" "$name" "$vis" "$name" >>"$text"
        walk "$path::$name" "$nested$name/" "$file"
        printf '// ---- end mod %s::%s ----\n}\n' "$path" "$name" >>"$text"
    done <"$mods"
)
# shellcheck disable=SC2086
walk std "" $ROOT_FILES
wc -c <"$text" | tr -d ' ' >>"$map"

# (0.21.1) --core: the sections every program reads (index.awk's core),
# each with why (the section and the name that need it), and their total.
if [ "${1:-}" = "--core" ]; then
    rm -f "$tmp"
    { cat "$text"; cat compiler/std/gpa.vl
        echo "pub const CHECK_ALLOC: bool = false;"; cat compiler/std/sys/macos.vl; } |
        LC_ALL=C awk -v why=1 -f compiler/std/index.awk
    exit 0
fi

# (sed, not awk: awks differ on backslashes in replacements.)
# (0.21) Up to about 2000 bytes of lines in one call: a program's std is
# 20 thousand lines, and a call for each cost more than reading it.
lines() {
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' |
        LC_ALL=C awk '{
            if (n > 0 && n + length($0) > 2000) { print "        buf_str(out, c\"" acc "\");"; acc = ""; n = 0 }
            acc = acc $0 "\\n"
            n += length($0) + 2
        }
        END { if (n > 0) print "        buf_str(out, c\"" acc "\");" }'
}
# The index of std's text on stdin (index.awk), as lines of code.
index() {
    LC_ALL=C awk -f compiler/std/index.awk | grep -v '^#' | lines
}
{
    echo "// Generated by compiler/std/embed.sh from compiler/std/ (std.vl, the"
    echo "// files appended to it and std's modules), gpa.vl and alloc_check.vl"
    echo "// (do not edit): the standard library's source (0.5), read when a"
    echo "// program names \`std\` (modules.vl)."
    echo ""
    echo "use crate::base::buf_str;"
    echo "use crate::front::stdalloc::std_alloc_tail;"
    echo ""
    echo "pub fn std_source(out: i64) {"
    echo "    unsafe {"
    lines <"$text"
    echo "    }"
    echo "    std_alloc_tail(out);"
    echo "}"
    echo ""
    echo "// Gpa's implementation (0.16), the end of std's source unless"
    echo "// --check-alloc (front/stdalloc.vl)."
    echo "pub fn std_gpa_source(out: i64) {"
    echo "    unsafe {"
    lines <compiler/std/gpa.vl
    echo "    }"
    echo "}"
    echo ""
    echo "// The checking Gpa (0.16), the end of std's source with --check-alloc"
    echo "// (front/stdalloc.vl)."
    echo "pub fn std_check_gpa_source(out: i64) {"
    echo "    unsafe {"
    lines <compiler/std/alloc_check.vl
    echo "    }"
    echo "}"
    echo ""
    echo "// (0.20) The end of std's text, after std::CHECK_ALLOC: the target's"
    echo "// system, sys/linux.vl or sys/macos.vl (front/stdalloc.vl), the"
    echo "// same length, std_sys_len bytes, so that one index holds for both."
    echo "pub fn std_sys_source(out: i64, linux: bool) {"
    echo "    unsafe {"
    echo "        if linux {"
    lines <compiler/std/sys/linux.vl | sed 's/^/    /'
    echo "        } else {"
    lines <compiler/std/sys/macos.vl | sed 's/^/    /'
    echo "        }"
    echo "    }"
    echo "}"
    echo ""
    echo "pub fn std_sys_len() -> i64 {"
    echo "    $(wc -c <compiler/std/sys/macos.vl | tr -d ' ')"
    echo "}"
    echo ""
    echo "// (0.15) The index of std's sections (compiler/std/index.awk): what"
    echo "// each defines and needs, so that a program's loader lexes only the"
    echo "// sections it can reach (front/modules: load_std_sections)."
    echo "pub fn std_index(out: i64) {"
    echo "    unsafe {"
    # (0.16: over std_source's whole text, std_alloc_tail's included: Gpa's
    # implementation and CHECK_ALLOC as without --check-alloc)
    { cat "$text"; cat compiler/std/gpa.vl
        echo "pub const CHECK_ALLOC: bool = false;"; cat compiler/std/sys/macos.vl; } | index
    echo "    }"
    echo "}"
    echo ""
    echo "// (0.16) The index with --check-alloc: std's source ends with the"
    echo "// checking Gpa (alloc_check.vl), CHECK_ALLOC and CHECK_ALLOC_OS (one"
    echo "// digit, so that the index holds for every target)."
    echo "pub fn std_check_index(out: i64) {"
    echo "    unsafe {"
    { cat "$text"; cat compiler/std/alloc_check.vl
        echo "pub const CHECK_ALLOC: bool = true;"
        echo "const CHECK_ALLOC_OS: i64 = 0;"; cat compiler/std/sys/macos.vl; } | index
    echo "    }"
    echo "}"
    echo ""
    echo "// (0.20) std's files in std_source's text: a line \`START PATH\` for each"
    echo "// (PATH under compiler/std), in the text's order, then a line with the"
    echo "// end of the last module's text (std_alloc_tail's follows; front/stdtree)."
    echo "pub fn std_files(out: i64) {"
    echo "    unsafe {"
    lines <"$map"
    echo "    }"
    echo "}"
} >"$tmp"
if [ "${1:-}" = "-c" ]; then
    if cmp -s "$tmp" "$out"; then rm -f "$tmp"; exit 0; fi
    rm -f "$tmp"
    echo "$out is stale: run compiler/std/embed.sh" >&2
    exit 1
fi
mv "$tmp" "$out"
