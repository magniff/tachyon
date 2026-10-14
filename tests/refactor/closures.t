## rewrite and fmt with closures (0.14; tests/refactor/closures/): a
## pattern matches inside a closure's body, and a closure's parameters
## and body are matched as written; a closure put where an operand or a
## callee is needs parentheses (its body takes all that follows).
## (They work on the program as parsed; tests/refactor/closures014.t has
## the refactorings that need it checked.)
$ fmt --check
$ rewrite 'double($x)' '($x * 2)' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -19 +19 @@
-    let add = |x: i64| double(x) + k;
+    let add = |x: i64| (x * 2) + k;
@@ -23 +23 @@
-        double(z)
+        (z * 2)
$ rewrite 'apply($f, $x)' '$f($x)' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -13 +13 @@
-    apply(by, x)
+    by(x)
@@ -20,2 +20,2 @@
-    total += apply(add, 1);
-    total += apply(|y| {
+    total += add(1);
+    total += (|y| {
@@ -24 +24 @@
-    }, 2);
+    })(2);
$ rewrite 'apply(|y| $b, $x)' 'apply(|y| $b + 0, $x)' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -24 +24 @@
-    }, 2);
+    } + 0, 2);
## A pattern with other parameters matches nothing.
$ rewrite 'apply(|z| $b, $x)' 'apply(|z| $b + 0, $x)' --dry-run
note rewrite.none: nothing matches 'apply(|z| $b, $x)'
$ rewrite 'double($x)' '($x * 2)'
rewrote 2 sites in 1 file	main.tach	+2 -2 lines
% git diff | sed -n '/^@@/,$p'
@@ -16,11 +16,11 @@ fn scaled(k: i64, x: i64) -> i64 {
 fn main() -> i32 {
     let k = 3;
     let mut total = 0;
-    let add = |x: i64| double(x) + k;
+    let add = |x: i64| (x * 2) + k;
     total += apply(add, 1);
     total += apply(|y| {
         let z = y + k;
-        double(z)
+        (z * 2)
     }, 2);
     total += scaled(2, 5);
     std::print_int(total);
