# Rewrites a tachyon program's `extern "C" { ... }` blocks of function
# declarations into the form the seed knows (0.2's `extern fn f(...);`,
# removed from the language in 0.4), one declaration per line:
#
#   extern "C" {                       extern fn printf(f: *u8, ...) -> i32;
#       fn printf(f: *u8, ...) -> i32; extern fn puts(s: *u8) -> i32;
#       fn puts(s: *u8) -> i32;
#   }
#   extern "C" { fn exit(c: i32) -> !; }    extern fn exit(c: i32) -> !;
#
# Used to give the seed the benchmarks and the random programs. Unsafe
# blocks (0.9) become plain blocks, `unsafe fn` plain functions.
{ gsub(/unsafe \{/, "{"); gsub(/unsafe fn /, "fn ") }
# (0.20) The seed reads 0.19's spelling: `var x` is `let mut x`, `static
# var` `static mut`, a `p: sink T` parameter `mut p: T`.
{
    gsub(/static var /, "static mut ")
    gsub(/(^|[^A-Za-z0-9_])var /, "&@@VAR@@"); gsub(/var @@VAR@@/, "let mut ")
    while (match($0, /[A-Za-z_][A-Za-z0-9_]*: sink /)) {
        name = substr($0, RSTART, RLENGTH - 7)
        $0 = substr($0, 1, RSTART - 1) "mut " name ": " substr($0, RSTART + RLENGTH)
    }
}
/^extern "C" \{ *fn .*; *\}$/ {
    sub(/^extern "C" \{ */, "extern ")
    sub(/ *\}$/, "")
    print
    next
}
/^extern "C" \{$/ { inblock = 1; next }
inblock && /^\}$/ { inblock = 0; next }
inblock { sub(/^ */, "extern "); print; next }
{ print }
