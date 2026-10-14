## What the new text has, it replaces: comments, attributes
## (tests/refactor/attrs/).
## No comment, no attribute: both stay.
$ edit replace f --dry-run < $T/inputs/f_plain.tach
--- a/main.tach
+++ b/main.tach
@@ -5 +5 @@
-pub fn f(x: i64) -> i64 {
+fn f(x: i64) -> i64 {
## An attribute: the attributes are replaced, the comment stays.
$ edit replace f --dry-run < $T/inputs/f_attr.tach
--- a/main.tach
+++ b/main.tach
@@ -4 +4 @@
-#[inline]
+#[cold]
## A comment: both are replaced.
$ edit replace f --dry-run < $T/inputs/f_doc.tach
--- a/main.tach
+++ b/main.tach
@@ -3,2 +3 @@
-// Doc of f.
-#[inline]
+// A new doc.
## Delete takes the comment and the attributes along.
$ edit delete f --dry-run --no-check
--- a/main.tach
+++ b/main.tach
@@ -3,6 +2,0 @@
-// Doc of f.
-#[inline]
-pub fn f(x: i64) -> i64 {
-    x + 1
-}
-
main.tach:6:6: error[type error] undefined variable 'f' | help: did you mean 'K'?
warning edit.breaks: 1 new error (dry run)
[exit 1]
## A comment after the item on its line is the item's.
$ edit delete K --dry-run
--- a/main.tach
+++ b/main.tach
@@ -9,2 +8,0 @@
-const K: i64 = 3; // trailing
-
main.tach:10:8: error[type error] undefined variable 'K' | help: did you mean 'f'?
warning edit.breaks: 1 new error (dry run)
[exit 1]
