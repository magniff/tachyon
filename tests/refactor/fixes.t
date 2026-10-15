## tachyonc fix (tests/refactor/fixes/): missing imports (the second
## of a statement found by a second round), unused imports, pub, unsafe.
$ check
main.tach:15:25: error[type error] undefined variable 'twice' | help: add `use crate::util::twice;`
main.tach:17:13: error[unsafe] calling a C function is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (`tachyonc fix --only unsafe` does the former)
main.tach:18:13: error[type error] 'hidden' is private | help: make it public: `pub fn hidden` at util.tach:19:1
[exit 1]
$ fix --dry-run
--- a/main.tach
+++ b/main.tach
@@ -7 +6,0 @@
-use util::{square, unused_one};
@@ -8,0 +8 @@
+use util::{cube, square, twice};
@@ -17 +17 @@
-    let b = abs(-1) as i64;
+    let b = unsafe { abs(-1) as i64 };
--- a/util.tach
+++ b/util.tach
@@ -19 +19 @@
-fn hidden() -> i64 {
+pub fn hidden() -> i64 {
--- a/shapes.tach
+++ b/shapes.tach
@@ -1,5 +1 @@
-use crate::util::{
-    square,
-    twice,
-    cube,
-};
+use crate::util::square;
$ fix --only unused --dry-run
--- a/main.tach
+++ b/main.tach
@@ -7 +6,0 @@
-use util::{square, unused_one};
@@ -8,0 +8 @@
+use util::square;
--- a/shapes.tach
+++ b/shapes.tach
@@ -1,5 +1 @@
-use crate::util::{
-    square,
-    twice,
-    cube,
-};
+use crate::util::square;
$ fix --only pub,unsafe --dry-run
--- a/main.tach
+++ b/main.tach
@@ -17 +17 @@
-    let b = abs(-1) as i64;
+    let b = unsafe { abs(-1) as i64 };
--- a/util.tach
+++ b/util.tach
@@ -19 +19 @@
-fn hidden() -> i64 {
+pub fn hidden() -> i64 {
## One file's fixes.
$ fix --only unused --in shapes.tach --dry-run
--- a/shapes.tach
+++ b/shapes.tach
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
## Nothing left to fix.
$ fix
note fix.none: nothing to fix
% git diff --stat
 main.tach   | 4 ++--
 shapes.tach | 6 +-----
 util.tach   | 2 +-
 3 files changed, 4 insertions(+), 8 deletions(-)
$ undo
undid fixed 2 missing imports, 3 unused imports, 1 pub, 1 unsafe block	3 files	+4 -8 lines
% git status --short
$ fix --only nonsense
error fix.usage: --only takes imports, unused, pub, unsafe, tidy-imports, reexports, std015 or alloc016, not 'nonsense'
[exit 2]
