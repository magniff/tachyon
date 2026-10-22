## volec fix (tests/refactor/fixes/): missing imports (the second
## of a statement found by a second round), unused imports, pub, unsafe.
$ check
main.vl:15:25: error[type error] undefined variable 'twice' | help: add `use crate::util::twice;` | try: volec fix --suggested main.vl
main.vl:17:13: error[unsafe] calling a C function is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place) | try: volec fix --only unsafe main.vl
main.vl:18:13: error[type error] 'hidden' is private | help: make it public: `pub fn hidden` at util.vl:19:1 | try: volec fix --suggested main.vl
[exit 1]
$ fix --dry-run
--- a/main.vl
+++ b/main.vl
@@ -7 +6,0 @@
-use util::{square, unused_one};
@@ -8,0 +8 @@
+use util::{cube, square, twice};
@@ -17 +17 @@
-    let b = abs(-1) as i64;
+    let b = unsafe { abs(-1) as i64 };
--- a/util.vl
+++ b/util.vl
@@ -19 +19 @@
-fn hidden() -> i64 {
+pub fn hidden() -> i64 {
--- a/shapes.vl
+++ b/shapes.vl
@@ -1,5 +1 @@
-use crate::util::{
-    square,
-    twice,
-    cube,
-};
+use crate::util::square;
$ fix --only unused --dry-run
--- a/main.vl
+++ b/main.vl
@@ -7 +6,0 @@
-use util::{square, unused_one};
@@ -8,0 +8 @@
+use util::square;
--- a/shapes.vl
+++ b/shapes.vl
@@ -1,5 +1 @@
-use crate::util::{
-    square,
-    twice,
-    cube,
-};
+use crate::util::square;
$ fix --only pub,unsafe --dry-run
--- a/main.vl
+++ b/main.vl
@@ -17 +17 @@
-    let b = abs(-1) as i64;
+    let b = unsafe { abs(-1) as i64 };
--- a/util.vl
+++ b/util.vl
@@ -19 +19 @@
-fn hidden() -> i64 {
+pub fn hidden() -> i64 {
## One file's fixes.
$ fix --only unused --in shapes.vl --dry-run
--- a/shapes.vl
+++ b/shapes.vl
@@ -1,5 +1 @@
-use crate::util::{
-    square,
-    twice,
-    cube,
-};
+use crate::util::square;
$ fix --in nowhere
error fix.bad-in: no file, module or item 'nowhere' in the program
[exit 1]
$ fix
fixed 2 missing imports, 3 unused imports, 1 pub, 1 unsafe block	3 files	+4 -8 lines
$ check
ok: 0 errors in main.vl
## Nothing left to fix.
$ fix
note fix.none: nothing to fix
% git diff --stat
 main.vl   | 4 ++--
 shapes.vl | 6 +-----
 util.vl   | 2 +-
 3 files changed, 4 insertions(+), 8 deletions(-)
$ undo
undid fixed 2 missing imports, 3 unused imports, 1 pub, 1 unsafe block	3 files	+4 -8 lines
% git status --short
$ fix --only nonsense
error fix.usage: --only takes imports, unused, pub, unsafe, suggested, tidy-imports, reexports, std015, alloc016, values, conventions or conventions-spelling, not 'nonsense'
[exit 2]
