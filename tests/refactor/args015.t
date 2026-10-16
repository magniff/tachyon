## The refactorings on calls with named and default arguments (0.15,
## tests/refactor/args015/): `--add 'x: T = V'` declares a default and
## leaves the calls; --fill-calls writes V, by label after a parameter
## left to its default; before a parameter without a default the calls
## get V, with a note; --rename-param renames the labels; --remove takes
## the argument by label or position, none when it is left out; --reorder
## writes a call with labels in the new order; inline puts in labelled
## arguments and defaults by parameter.
$ check
ok: 0 errors in main.tach
$ refactor signature area --add 'scale: i64 = 2' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -2 +2 @@
-fn area(w: i64, h: i64 = 1, depth: i64 = 1) -> i64 {
+fn area(w: i64, h: i64 = 1, depth: i64 = 1, scale: i64 = 2) -> i64 {
$ refactor signature area --add 'scale: i64 = 2' --fill-calls --dry-run
--- a/main.tach
+++ b/main.tach
@@ -2 +2 @@
-fn area(w: i64, h: i64 = 1, depth: i64 = 1) -> i64 {
+fn area(w: i64, h: i64 = 1, depth: i64 = 1, scale: i64 = 2) -> i64 {
@@ -23,4 +23,4 @@
-    let a = area(2);
-    let b = area(2, h: 3);
-    let c = area(2, 3, depth: 4);
-    let d = area(2, depth: 5);
+    let a = area(2, scale: 2);
+    let b = area(2, h: 3, scale: 2);
+    let c = area(2, 3, depth: 4, scale: 2);
+    let d = area(2, depth: 5, scale: 2);
$ refactor signature area --add 'first: i64 = 0' --at 0 --dry-run
--- a/main.tach
+++ b/main.tach
@@ -2 +2 @@
-fn area(w: i64, h: i64 = 1, depth: i64 = 1) -> i64 {
+fn area(first: i64, w: i64, h: i64 = 1, depth: i64 = 1) -> i64 {
@@ -23,4 +23,4 @@
-    let a = area(2);
-    let b = area(2, h: 3);
-    let c = area(2, 3, depth: 4);
-    let d = area(2, depth: 5);
+    let a = area(0, 2);
+    let b = area(0, 2, h: 3);
+    let c = area(0, 2, 3, depth: 4);
+    let d = area(0, 2, depth: 5);
note refactor.fill-calls: the calls get the value (a default is on trailing parameters only, and a later one has none)
$ refactor signature area --rename-param h height --dry-run
--- a/main.tach
+++ b/main.tach
@@ -2,2 +2,2 @@
-fn area(w: i64, h: i64 = 1, depth: i64 = 1) -> i64 {
-    w * h * depth
+fn area(w: i64, height: i64 = 1, depth: i64 = 1) -> i64 {
+    w * height * depth
@@ -24 +24 @@
-    let b = area(2, h: 3);
+    let b = area(2, height: 3);
$ refactor signature label --remove unused --dry-run
--- a/main.tach
+++ b/main.tach
@@ -6 +6 @@
-fn label(n: i64, unused: i64 = 0, wide: bool = false) -> i64 {
+fn label(n: i64, wide: bool = false) -> i64 {
@@ -28 +28 @@
-    let f = label(1, wide: true) + label(2, 0) + label(3);
+    let f = label(1, wide: true) + label(2) + label(3);
$ refactor signature area --reorder w,depth,h --dry-run
--- a/main.tach
+++ b/main.tach
@@ -2 +2 @@
-fn area(w: i64, h: i64 = 1, depth: i64 = 1) -> i64 {
+fn area(w: i64, depth: i64 = 1, h: i64 = 1) -> i64 {
@@ -25 +25 @@
-    let c = area(2, 3, depth: 4);
+    let c = area(2, depth: 4, h: 3);
$ refactor signature Box::grow --rename-param times n --dry-run
--- a/main.tach
+++ b/main.tach
@@ -17,2 +17,2 @@
-    fn grow(self: *Box, by: i64, times: i64 = 1) {
-        self.w += by * times;
+    fn grow(self: *Box, by: i64, n: i64 = 1) {
+        self.w += by * n;
@@ -30 +30 @@
-    x.grow(2, times: 3);
+    x.grow(2, n: 3);
$ refactor inline twice --dry-run
--- a/main.tach
+++ b/main.tach
@@ -10,4 +9,0 @@
-fn twice(x: i64, k: i64 = 2) -> i64 {
-    x * k
-}
-
@@ -27 +23 @@
-    let e = twice(3) + twice(4, k: 5);
+    let e = 3 * 2 + 4 * 5;
## Written: the program still runs.
$ refactor signature area --reorder w,depth,h
reordered the parameters of crate::area, 4 calls	main.tach	+2 -2 lines
% "$COMPILER" main.tach -o prog && ./prog && echo ran
ran
ok: built prog
