## volec fmt on the syntax of 0.14 (tests/refactor/fmtclosures/): no
## space inside a closure's bars (`|x| x + k`, `||`, `move |x| -> T {`),
## `|` and `||` as operators spaced as before, a long chain of method
## calls a line each, a long closure's block opened on lines of its own;
## `type Item;`, `Fn(i64) -> i64` and `Iterator<Item = i64>` bounds as
## written. fmt needs no checking: the program has 0.14's stub errors.
$ fmt --check
main.vl
error fmt.unformatted: 1 of 1 file is not formatted
try: volec fmt --dry-run main.vl
try: volec fmt main.vl
[exit 1]
$ fmt --dry-run main.vl
--- a/main.vl
+++ b/main.vl
@@ -15,2 +15,2 @@
-    let a = apply(| x | x + k, 1);
-    let b = apply(|x : i64| x * 2, a);
+    let a = apply(|x| x + k, 1);
+    let b = apply(|x: i64| x * 2, a);
@@ -18 +18 @@
-    let d = apply(| (p, q): (i64, i64) | p + q, c);
+    let d = apply(|(p, q): (i64, i64)| p + q, c);
@@ -20 +20 @@
-    each(4, | i | { total += i; });
+    each(4, |i| { total += i; });
@@ -23 +23,7 @@
-    let v = numbers.iter().map(|x| x * 3).filter(|x| x % 2 == 0).enumerate().map(|(i, x)| i * x).sum();
+    let v = numbers
+        .iter()
+        .map(|x| x * 3)
+        .filter(|x| x % 2 == 0)
+        .enumerate()
+        .map(|(i, x)| i * x)
+        .sum();
@@ -25 +31,3 @@
-    let f = sink |left: i64, right: i64| -> i64 { let m = left * right; m + total + some_long_name_here + 1 };
+    let f = sink |left: i64, right: i64| -> i64 {
+        let m = left * right; m + total + some_long_name_here + 1
+    };
$ fmt
formatted	main.vl	+14 -6 lines
% cat main.vl
// Closures and iterator chains laid out by hand, for `volec fmt` (0.14).
fn apply<F: Fn(i64) -> i64>(f: F, x: i64) -> i64 { f(x) }

fn each<F: FnMut(i64)>(n: i64, f: sink F) { for i in 0..n { f(i); } }

fn sum_of<I: Iterator<Item = i64>>(it: sink I) -> I::Item { it.sum() }

trait Source {
    type Item;
    fn get(self: *Self) -> Self::Item;
}

fn main() -> i32 {
    let k = 3;
    let a = apply(|x| x + k, 1);
    let b = apply(|x: i64| x * 2, a);
    let c = apply(sink |x| -> i64 { x | k }, b);
    let d = apply(|(p, q): (i64, i64)| p + q, c);
    var total = 0;
    each(4, |i| { total += i; });
    each(2, || -> () {});
    let all = a || b > 0 || c | d > 0;
    let v = numbers
        .iter()
        .map(|x| x * 3)
        .filter(|x| x % 2 == 0)
        .enumerate()
        .map(|(i, x)| i * x)
        .sum();
    let w = numbers.iter().map(|x| x + 1).sum();
    let f = sink |left: i64, right: i64| -> i64 {
        let m = left * right; m + total + some_long_name_here + 1
    };
    let neg = |&x| -x;
    0
}
## A second time: nothing to do (the layout is a fixpoint).
$ fmt --check
