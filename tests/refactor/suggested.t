## tachyonc fix --suggested (0.18; tests/refactor/suggested/): an error
## whose fix the compiler knows exactly prints `try: tachyonc fix
## --suggested ROOT`; the command makes every such fix as one checked
## edit, the imports and pubs too, then prints the errors left. One of
## each kind: a did-you-mean (a variable, a method) with one name that
## near, a conversion (`as`, `!= 0`, `[..]`), std's function for a method,
## the `_in` form with this function's `gpa`, a missing `gpa` argument, a
## missing `use` (std's, the crate's), a missing `pub`, a module path from
## `crate::` (a value, a type, a `use` line), Rust's types (`&str`,
## `String`, `char`); a tie (`cut`: `cat` and `cot`) is left.
$ check
main.tach:22:13: error[type error] undefined variable 'totl' | help: did you mean 'total'? | try: tachyonc fix --suggested main.tach
main.tach:24:19: error[type error] expected '[i64]', got '[i64; 3]' | help: an array is not a slice: take one of all of it | try: [1, 2, 3][..] | try: tachyonc fix --suggested main.tach
main.tach:28:13: error[type error] no method 'trim' on type '[u8]' | help: 'trim' is no method: std's function `trim` takes the value as its first argument | try: trim("  x ") | try: tachyonc fix --suggested main.tach
main.tach:29:13: error[type error] allocation is explicit: pass an allocator (try: format_in(x, gpa)) | help: this function's `gpa` is the allocator to pass | try: tachyonc fix --only alloc016 main.tach | try: tachyonc fix --suggested main.tach
main.tach:30:15: error[type error] undefined variable 'I64_MIN' | help: add `use std::num::I64_MIN;` | try: tachyonc fix --suggested main.tach
main.tach:31:13: error[type error] 'describe' is private | help: make it public: `pub fn describe` at text.tach:3:1 | try: tachyonc fix --suggested main.tach
main.tach:32:13: error[type error] function 'table::make' expects 2 arguments, got 1 | help: its signature: `fn make(width: i64, gpa: Gpa) -> Table` (table.tach:3) | try: table::make(3, gpa) | try: tachyonc fix --suggested main.tach
main.tach:34:5: error[type error] no method 'push_string' on type 'Buf' | help: did you mean 'push_str'? | try: tachyonc query items Buf main.tach | try: tachyonc fix --suggested main.tach
main.tach:37:16: error[type error] undefined variable 'cut' | help: did you mean 'cat'?
<std>:10090:33: error[type error] expected '*[u8; 256]', got '[u8; 256]' | help: a pointer to it: its address | try: &tmp | note: in instantiation of 'format_in<{error}, Gpa>' at <std>:10153:5 | note: in instantiation of 'format<{error}>' at main.tach:29:13
text.tach:1:5: error[type error] unknown module 'inner' | help: 'inner' is the module crate::lib::inner; a path starts in this module, beside it or at the root: write `crate::lib::inner::...` | try: use crate::lib::inner::width; | try: tachyonc fix --suggested main.tach
text.tach:4:12: error[type error] unknown module 'shapes' | help: 'shapes' is the module crate::lib::shapes; a path starts in this module, beside it or at the root: write `crate::lib::shapes::...` | try: use crate::lib::shapes; | try: tachyonc fix --suggested main.tach
text.tach:5:5: error[type error] unknown module 'shapes' | help: 'shapes' is the module crate::lib::shapes; a path starts in this module, beside it or at the root: write `crate::lib::shapes::...` | try: use crate::lib::shapes; | try: tachyonc fix --suggested main.tach
text.tach:8:16: error[parser error] expected type, got '&' | help: `&str` is `[u8]` in tachyon: a slice of bytes, as string literals are | try: tachyonc fix --suggested main.tach
[exit 1]
## The diff first; one line's fixes; one file's.
$ fix --suggested --dry-run
--- a/main.tach
+++ b/main.tach
@@ -0,0 +1,3 @@
+use std::num::I64_MIN;
+use text::wrap;
+
@@ -22,4 +25,4 @@
-    let t = totl(&v);
-    let small: u8 = t;
-    let n = count([1, 2, 3]);
-    if n {
+    let t = total(v);
+    let small: u8 = t as u8;
+    let n = count([1, 2, 3][..]);
+    if n != 0 {
@@ -28,2 +31,2 @@
-    let s = "  x ".trim();
-    let w = format(f"{t}");
+    let s = trim("  x ");
+    let w = format_in(f"{t}", gpa);
@@ -32 +35 @@
-    let r = table::make(3);
+    let r = table::make(3, gpa);
@@ -34 +37 @@
-    b.push_string(wrap(s));
+    b.push_str(wrap(s));
--- a/text.tach
+++ b/text.tach
@@ -1 +1 @@
-use inner::width;
+use crate::lib::inner::width;
@@ -3,3 +3,3 @@
-fn describe(n: i64) -> i64 {
-    let r: shapes::Rect = shapes::Rect { w: n, h: 2 };
-    shapes::area(&r)
+pub fn describe(n: i64) -> i64 {
+    let r: crate::lib::shapes::Rect = crate::lib::shapes::Rect { w: n, h: 2 };
+    crate::lib::shapes::area(r)
@@ -8,2 +8,2 @@
-pub fn wrap(s: &str) -> String {
-    let c: char = 'x';
+pub fn wrap(s: [u8]) -> [u8] {
+    let c: u8 = 'x';
$ fix --suggested --at main.tach:23 --dry-run
note fix.none: nothing to fix
$ fix --suggested --in text.tach --dry-run
--- a/text.tach
+++ b/text.tach
@@ -1 +1 @@
-use inner::width;
+use crate::lib::inner::width;
@@ -3,3 +3,3 @@
-fn describe(n: i64) -> i64 {
-    let r: shapes::Rect = shapes::Rect { w: n, h: 2 };
-    shapes::area(&r)
+pub fn describe(n: i64) -> i64 {
+    let r: crate::lib::shapes::Rect = crate::lib::shapes::Rect { w: n, h: 2 };
+    crate::lib::shapes::area(r)
@@ -8,2 +8,2 @@
-pub fn wrap(s: &str) -> String {
-    let c: char = 'x';
+pub fn wrap(s: [u8]) -> [u8] {
+    let c: u8 = 'x';
$ fix --suggested --show
fixed 2 missing imports, 1 pub, 17 suggested fixes	2 files	+17 -14 lines
// main.tach:1-3
1	use std::num::I64_MIN;
2	use text::wrap;
3	
// main.tach:25-28
25	    let t = total(v);
26	    let small: u8 = t as u8;
27	    let n = count([1, 2, 3][..]);
28	    if n != 0 {
// main.tach:31-32
31	    let s = trim("  x ");
32	    let w = format_in(f"{t}", gpa);
// main.tach:35
35	    let r = table::make(3, gpa);
// main.tach:37
37	    b.push_str(wrap(s));
// text.tach:1
1	use crate::lib::inner::width;
// text.tach:3-5
3	pub fn describe(n: i64) -> i64 {
4	    let r: crate::lib::shapes::Rect = crate::lib::shapes::Rect { w: n, h: 2 };
5	    crate::lib::shapes::area(r)
// text.tach:8-9
8	pub fn wrap(s: [u8]) -> [u8] {
9	    let c: u8 = 'x';
main.tach:40:16: error[type error] undefined variable 'cut' | help: did you mean 'cat'?
note fix.left: 1 error left (above)
$ check
main.tach:40:16: error[type error] undefined variable 'cut' | help: did you mean 'cat'?
[exit 1]
$ undo
undid fixed 2 missing imports, 1 pub, 17 suggested fixes	2 files	+17 -14 lines
## A Rust label: the program does not lex; the fix respells each line.
$ fix --suggested labels.tach --show
fixed 3 suggested fixes	labels.tach	+3 -3 lines
// labels.tach:3-4
3	    var n = 0;
4	    outer: for i in 0..3 {
// labels.tach:7
7	                break :outer;
## A fix that makes an error on its own line refuses the edit.
$ fix --suggested refuse.tach
refuse.tach:5:18: error[type error] expected 'i64', got '[u8]'  [edited: crate::main]
error edit.breaks: 1 new error; nothing written
try: tachyonc fix --suggested refuse.tach --no-check
[exit 1]
## --at is for --suggested.
$ fix --at main.tach:24
error fix.usage: --at is for --suggested: the fixes of the errors at a line
[exit 2]
$ fix --suggested --at main.tach
error fix.usage: --at takes FILE:LINE, the line of an error
[exit 2]
