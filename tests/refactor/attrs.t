## What the new text has, it replaces: comments, attributes
## (tests/refactor/attrs/).
## No comment, no attribute: both stay.
$ edit replace f --dry-run < $T/inputs/f_plain.vl
--- a/main.vl
+++ b/main.vl
@@ -5 +5 @@
-pub fn f(x: i64) -> i64 {
+fn f(x: i64) -> i64 {
## An attribute: the attributes are replaced, the comment stays.
$ edit replace f --dry-run < $T/inputs/f_attr.vl
--- a/main.vl
+++ b/main.vl
@@ -4 +4 @@
-#[inline]
+#[cold]
## A comment: both are replaced.
$ edit replace f --dry-run < $T/inputs/f_doc.vl
--- a/main.vl
+++ b/main.vl
@@ -3,2 +3 @@
-// Doc of f.
-#[inline]
+// A new doc.
## Delete takes the comment and the attributes along.
$ edit delete f --dry-run --no-check
--- a/main.vl
+++ b/main.vl
@@ -3,6 +2,0 @@
-// Doc of f.
-#[inline]
-pub fn f(x: i64) -> i64 {
-    x + 1
-}
-
main.vl:6:6: error[type error] undefined variable 'f'  [in crate::main]
warning edit.breaks: 1 new error (1 in crate::main, which the edit does not change) (dry run)
[exit 1]
## A comment after the item on its line is the item's.
$ edit delete K --dry-run
--- a/main.vl
+++ b/main.vl
@@ -9,2 +8,0 @@
-const K: i64 = 3; // trailing
-
main.vl:10:8: error[type error] undefined variable 'K'  [in crate::main]
warning edit.breaks: 1 new error (1 in crate::main, which the edit does not change) (dry run)
[exit 1]
