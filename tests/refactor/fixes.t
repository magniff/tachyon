## tachyonc fix (tests/refactor/fixes/): missing imports (the second
## of a statement found by a second round), unused imports, pub, unsafe.
$ check
main.tach:15:25: error[type error] undefined variable 'twice' | help: add `use crate::util::twice;`
main.tach:17:13: error[unsafe] calling a C function is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (`tachyonc --fix-unsafe` does the former)
main.tach:18:13: error[type error] 'hidden' is private
[exit 1]
$ fix --dry-run
--- a/main.tach
+++ b/main.tach
@@ -7 +7 @@
-use util::{square, unused_one};
+use util::{square, twice, cube};
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
@@ -3,2 +2,0 @@
-    twice,
-    cube,
$ fix --only unused --dry-run
--- a/main.tach
+++ b/main.tach
@@ -7 +7 @@
-use util::{square, unused_one};
+use util::square;
--- a/shapes.tach
+++ b/shapes.tach
@@ -3,2 +2,0 @@
-    twice,
-    cube,
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
@@ -3,2 +2,0 @@
-    twice,
-    cube,
$ fix --in nowhere
error fix.bad-in: no file or module 'nowhere' in the program
[exit 1]
$ fix
fixed 2 missing imports, 3 unused imports, 1 pub, 1 unsafe block	3 files	+3 -5 lines
$ check
## Nothing left to fix.
$ fix
note fix.none: nothing to fix
% git diff --stat
 main.tach   | 4 ++--
 shapes.tach | 2 --
 util.tach   | 2 +-
 3 files changed, 3 insertions(+), 5 deletions(-)
$ undo
undid fixed 2 missing imports, 3 unused imports, 1 pub, 1 unsafe block	3 files	+3 -5 lines
% git status --short
$ fix --only nonsense
error fix.usage: --only takes imports, unused, pub, unsafe, tidy-imports or reexports, not 'nonsense'
[exit 2]
