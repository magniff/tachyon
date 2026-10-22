## volec fix --suggested (0.18; tests/refactor/suggested/): an error
## whose fix the compiler knows exactly prints `try: volec fix
## --suggested ROOT`; the command makes every such fix as one checked
## edit, the imports and pubs too, then prints the errors left. One of
## each kind: a did-you-mean (a variable, a method) with one name that
## near, a conversion (`as`, `!= 0`, `[..]`), std's function for a method,
## the `_in` form with this function's `gpa`, a missing `gpa` argument, a
## missing `use` (std's, the crate's), a missing `pub`, a module path from
## `crate::` (a value, a type, a `use` line), Rust's types (`&str`,
## `String`, `char`); a tie (`cut`: `cat` and `cot`) is left.
$ check
main.vl:22:13: error[type error] undefined variable 'totl' | help: did you mean 'total'? | try: volec fix --suggested main.vl
main.vl:24:19: error[type error] expected '[i64]', got '[i64; 3]' | help: an array is not a slice: take one of all of it | try: [1, 2, 3][..] | try: volec fix --suggested main.vl
main.vl:29:13: error[type error] allocation is explicit: pass an allocator (try: format_in(x, gpa)) | help: this function's `gpa` is the allocator to pass | try: volec fix --only alloc016 main.vl | try: volec fix --suggested main.vl
main.vl:30:15: error[type error] undefined variable 'I64_MIN' | help: add `use std::I64_MIN;` | try: volec fix --suggested main.vl
main.vl:31:13: error[type error] 'describe' is private | help: make it public: `pub fn describe` at text.vl:3:1 | try: volec fix --suggested main.vl
main.vl:32:13: error[type error] function 'table::make' expects 2 arguments, got 1 | help: its signature: `fn make(width: i64, gpa: Gpa) -> Table` (table.vl:3) | try: table::make(3, gpa) | try: volec fix --suggested main.vl
main.vl:34:5: error[type error] no method 'push_string' on type 'Buf' | help: did you mean 'push_str'? | try: volec query items Buf main.vl | try: volec fix --suggested main.vl
main.vl:37:16: error[type error] undefined variable 'cut' | help: did you mean 'cat'?
text.vl:1:5: error[type error] unknown module 'inner' | help: 'inner' is the module crate::lib::inner; a path starts in this module, beside it or at the root: write `crate::lib::inner::...` | try: use crate::lib::inner::width; | try: volec fix --suggested main.vl
text.vl:4:12: error[type error] unknown module 'shapes' | help: 'shapes' is the module crate::lib::shapes; a path starts in this module, beside it or at the root: write `crate::lib::shapes::...` | try: use crate::lib::shapes; | try: volec fix --suggested main.vl
text.vl:5:5: error[type error] unknown module 'shapes' | help: 'shapes' is the module crate::lib::shapes; a path starts in this module, beside it or at the root: write `crate::lib::shapes::...` | try: use crate::lib::shapes; | try: volec fix --suggested main.vl
text.vl:9:12: error[type error] unknown type 'char' | help: `u8`: text is bytes, and 'a' is a u8 | try: u8 | try: volec fix --suggested main.vl
[exit 1]
## The diff first; one line's fixes; one file's.
$ fix --suggested --dry-run
--- a/main.vl
+++ b/main.vl
@@ -0,0 +1,3 @@
+use std::I64_MIN;
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
@@ -29 +32 @@
-    let w = format(f"{t}");
+    let w = format_in(f"{t}", gpa);
@@ -32 +35 @@
-    let r = table::make(3);
+    let r = table::make(3, gpa);
@@ -34 +37 @@
-    b.push_string(wrap(s));
+    b.push_str(wrap(s));
--- a/text.vl
+++ b/text.vl
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
@@ -9 +9 @@
-    let c: char = 'x';
+    let c: u8 = 'x';
$ fix --suggested --at main.vl:23 --dry-run
note fix.none: nothing to fix
$ fix --suggested --in text.vl --dry-run
--- a/text.vl
+++ b/text.vl
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
@@ -9 +9 @@
-    let c: char = 'x';
+    let c: u8 = 'x';
$ fix --suggested --show
fixed 2 missing imports, 1 pub, 14 suggested fixes	2 files	+15 -12 lines
// main.vl:1-3
1	use std::I64_MIN;
2	use text::wrap;
3	
// main.vl:25-28
25	    let t = total(v);
26	    let small: u8 = t as u8;
27	    let n = count([1, 2, 3][..]);
28	    if n != 0 {
// main.vl:32
32	    let w = format_in(f"{t}", gpa);
// main.vl:35
35	    let r = table::make(3, gpa);
// main.vl:37
37	    b.push_str(wrap(s));
// text.vl:1
1	use crate::lib::inner::width;
// text.vl:3-5
3	pub fn describe(n: i64) -> i64 {
4	    let r: crate::lib::shapes::Rect = crate::lib::shapes::Rect { w: n, h: 2 };
5	    crate::lib::shapes::area(r)
// text.vl:9
9	    let c: u8 = 'x';
main.vl:40:16: error[type error] undefined variable 'cut' | help: did you mean 'cat'?
note fix.left: 1 error left (above)
$ check
main.vl:40:16: error[type error] undefined variable 'cut' | help: did you mean 'cat'?
[exit 1]
$ undo
undid fixed 2 missing imports, 1 pub, 14 suggested fixes	2 files	+15 -12 lines
## A Rust label: the program does not lex; the fix respells each line.
$ fix --suggested labels.vl --show
fixed 3 suggested fixes	labels.vl	+3 -3 lines
// labels.vl:3-4
3	    var n = 0;
4	    outer: for i in 0..3 {
// labels.vl:7
7	                break :outer;
## A fix that makes an error on its own line refuses the edit.
$ fix --suggested refuse.vl
refuse.vl:5:18: error[type error] expected 'i64', got '[u8]'  [edited: crate::main]
error edit.breaks: 1 new error; nothing written
try: volec fix --suggested refuse.vl --no-check
[exit 1]
## --at is for --suggested.
$ fix --at main.vl:24
error fix.usage: --at is for --suggested: the fixes of the errors at a line
[exit 2]
$ fix --suggested --at main.vl
error fix.usage: --at takes FILE:LINE, the line of an error
[exit 2]
