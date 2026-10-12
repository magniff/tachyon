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
