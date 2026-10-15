## The tools' fixes of 0.17 (tests/refactor/tools017/).
$ check
## edit delete MODULE: its `mod` line and its file; undo brings both back.
$ edit delete report
deleted crate::report	2 files	+0 -5 lines
% git status --short
 M main.tach
 D report.tach
$ undo
undid deleted crate::report	2 files	+0 -5 lines
% git status --short
## edit patch FILE:LINE on a `mod x;` line patches that line, not x's file.
$ edit patch main.tach:3 --old 'mod report;' --new 'pub mod report;' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -3 +3 @@
-mod report;
+pub mod report;
$ edit patch geo/mod.tach:1 --old 'mod util;' --new 'pub mod util;' --dry-run
--- a/geo/mod.tach
+++ b/geo/mod.tach
@@ -1 +1 @@
-mod util;
+pub mod util;
## MODULE::extern is an edit target (crate::extern, main::extern: the root's).
$ edit patch crate::extern --old 'i32' --new 'i64' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -15 +15 @@
-    fn puts(s: *u8) -> i32;
+    fn puts(s: *u8) -> i64;
$ edit patch main::extern --old 'puts' --new 'fputs' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -15 +15 @@
-    fn puts(s: *u8) -> i32;
+    fn fputs(s: *u8) -> i32;
main.tach:23:9: error[type error] undefined variable 'puts' | help: did you mean 'fputs'?  [in crate::main]
warning edit.breaks: 1 new error (1 in crate::main, which the edit does not change) (dry run)
[exit 1]
$ edit patch calc::extern --old 'a' --new 'b'
error patch.no-region: no extern block in crate::calc; edit replace adds one
try: tachyonc edit replace calc::extern < extern.tach
[exit 1]
$ edit replace calc::extern --dry-run < $T/inputs/tools017_extern.tach
--- a/calc.tach
+++ b/calc.tach
@@ -6,0 +7,4 @@
+extern "C" {
+    fn abs(x: i32) -> i32;
+}
+
$ edit insert --after crate::extern --dry-run < $T/inputs/tools017_extern.tach
--- a/main.tach
+++ b/main.tach
@@ -17,0 +18,4 @@
+extern "C" {
+    fn abs(x: i32) -> i32;
+}
+
## edit replace FILE.tach: the whole file.
$ edit replace geo/util.tach --show < $T/inputs/tools017_util.tach
replaced geo/util.tach	geo/util.tach	+0 -4 lines
// geo/util.tach:3: 4 lines removed after line 3
$ undo
undid replaced geo/util.tach	geo/util.tach	+0 -4 lines
## edit new-file: the imports its text needs are added.
$ edit new-file extra.tach --dry-run < $T/inputs/tools017_newfile.tach
--- a/main.tach
+++ b/main.tach
@@ -4,0 +5 @@
+mod extra;
--- a/extra.tach
+++ b/extra.tach
@@ -0,0 +1,5 @@
+use crate::calc::twice;
+
+pub fn quad(x: i64) -> i64 {
+    twice(twice(x))
+}
note edit.imports: added the imports the new text needs (fix --only imports)
## A one-line static inserted next to one joins its run.
$ edit insert --after B --dry-run < $T/inputs/tools017_static.tach
--- a/main.tach
+++ b/main.tach
@@ -12,0 +13 @@
+static C: i64 = 3;
## edit apply: `@@ new after X` where an earlier block adds X.
$ edit apply $T/inputs/tools017_chain.items --dry-run
--- a/geo/mod.tach
+++ b/geo/mod.tach
@@ -6,0 +7,13 @@
+
+pub fn half(x: i64) -> i64 {
+    x / 2
+}
+
+// The perimeter of a square of side x.
+pub fn perimeter(x: i64) -> i64 {
+    x * 4
+}
+
+pub fn diagonal2(x: i64) -> i64 {
+    2 * x * x
+}
## query.ambiguous: each try: is the command as run, the name replaced.
$ edit patch header --old '1' --new '3'
error query.ambiguous: 2 definitions match 'header'; name one
try: tachyonc edit patch crate::calc::header --old 1 --new 3
try: tachyonc edit patch crate::report::header --old 1 --new 3
[exit 1]
## refactor inline into an f-string hole: the body on one line.
$ refactor inline percent --dry-run
--- a/main.tach
+++ b/main.tach
@@ -6 +6 @@
-use calc::{empties, percent, twice};
+use calc::{empties, twice};
@@ -21 +21 @@
-    println(f"{TITLE}: share {percent(a, b)}%, twice {twice(a)}");
+    println(f"{TITLE}: share {if b == 0 { 0 } else { a * 100 / b }}%, twice {twice(a)}");
--- a/calc.tach
+++ b/calc.tach
@@ -7,8 +6,0 @@
-pub fn percent(part: i64, whole: i64) -> i64 {
-    if whole == 0 {
-        0
-    } else {
-        part * 100 / whole
-    }
-}
-
## rewrite: the imports it leaves unused go; --in an item, repeated.
$ rewrite 'twice($x)' '$x + $x' --in main --dry-run
--- a/main.tach
+++ b/main.tach
@@ -6 +6 @@
-use calc::{empties, percent, twice};
+use calc::{empties, percent};
@@ -21 +21 @@
-    println(f"{TITLE}: share {percent(a, b)}%, twice {twice(a)}");
+    println(f"{TITLE}: share {percent(a, b)}%, twice {a + a}");
@@ -25 +25 @@
-    println(f"{geo::area(2)} {A + B} {twice(b)} {calc::header()}");
+    println(f"{geo::area(2)} {A + B} {b + b} {calc::header()}");
note rewrite.imports: removed 1 import the rewrite left unused
$ rewrite 'twice($x)' '$x + $x' --in main --in crate::nowhere
error rewrite.bad-in: no file, module or item 'crate::nowhere' in the program
[exit 1]
$ rewrite 'twice($x)' '$x + $x'
rewrote 2 sites in 1 file	main.tach	+3 -3 lines
note rewrite.imports: removed 1 import the rewrite left unused
% git diff --stat
 main.tach | 6 +++---
 1 file changed, 3 insertions(+), 3 deletions(-)
$ undo
undid rewrote 2 sites in 1 file	main.tach	+3 -3 lines
## rewrite refused (edit.breaks): a hole of several types gets --where per type.
$ rewrite '$v.len() == 0' '$v.is_empty()'
calc.tach:29:8: error[type error] no method 'is_empty' on type '*Buf' | help: no `is_empty`: `x.len() == 0` | try: tachyonc query items Buf main.tach  [edited: crate::calc::empties]
error edit.breaks: 1 new error; nothing written
note rewrite.where: $v has 2 types at the sites: *Vec<[u8]> (1 site), *Buf (1 site); --where takes the ones the replacement fits
try: tachyonc rewrite '$v.len() == 0' '$v.is_empty()' --where '$v: *Vec<[u8]>'
try: tachyonc rewrite '$v.len() == 0' '$v.is_empty()' --where '$v: *Buf'
try: tachyonc rewrite '$v.len() == 0' '$v.is_empty()' --no-check
[exit 1]
## refactor rename: a path mention must name the item's module.
$ refactor rename crate::calc::header top --dry-run
--- a/main.tach
+++ b/main.tach
@@ -25 +25 @@
-    println(f"{geo::area(2)} {A + B} {twice(b)} {calc::header()}");
+    println(f"{geo::area(2)} {A + B} {twice(b)} {calc::top()}");
--- a/calc.tach
+++ b/calc.tach
@@ -1 +1 @@
-// Arithmetic. `calc::header` is the function below; `MODULE::header`
+// Arithmetic. `calc::top` is the function below; `MODULE::header`
@@ -19 +19 @@
-pub fn header() -> i64 {
+pub fn top() -> i64 {
## query refs: the uses of string and C-string constants.
$ query refs GREETING TITLE
# main.tach
9:7	def	->GREETING	const GREETING: *u8 = c"hello";
10:7	def	->TITLE	const TITLE: [u8] = "totals";
21:16	read	main	->TITLE	println(f"{TITLE}: share {percent(a, b)}%, twice {twice(a)}");
23:14	read	main	->GREETING	puts(GREETING);
## query grep --comments: a doc comment is its item's.
$ query grep 'area of a square' --comments
# geo/mod.tach
3:8	comment	geo::area	// The area of a square of side x.
## query unused MODULE: its children too.
$ query unused crate::geo
crate::geo::util::unused_one	geo/util.tach:5:4	fn
## fix --in ./FILE, as the errors print paths.
$ fix --only unused --in ./calc.tach --dry-run
--- a/calc.tach
+++ b/calc.tach
@@ -4 +3,0 @@
-use crate::geo::area;
