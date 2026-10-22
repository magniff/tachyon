## volec fmt on the syntax of 0.15 (tests/refactor/fmt015/): `?` after
## its operand, `name: value` arguments, `= default` parameters, field
## shorthand and `#[derive(A, B)]` spaced as Rust does; an f-string's text
## as written, its holes laid out as expressions (no space inside the
## braces, none before a spec), and no line broken inside one; `>>>`
## closing type arguments as written. fmt needs no checking: the program
## has 0.15's stub errors.
$ fmt --dry-run main.vl
--- a/main.vl
+++ b/main.vl
@@ -2 +2 @@
-#[derive(Eq,Ord ,Debug)]
+#[derive(Eq, Ord, Debug)]
@@ -5 +5 @@
-#[derive( Clone )]
+#[derive(Clone)]
@@ -11 +11 @@
-fn scale(a: i64, b: i64=2, c: i64 =  3) -> i64 { a*b+c }
+fn scale(a: i64, b: i64 = 2, c: i64 = 3) -> i64 { a * b + c }
@@ -14,2 +14,2 @@
-    let v = o ?;
-    Some(v/2)
+    let v = o?;
+    Some(v / 2)
@@ -23,4 +23,5 @@
-    let p = P{x,y};
-    let n = scale(1, b:5, c : 6) + scale(1,c: 4);
-    println(f"x = {x}, y = { y } {p.x:>5} {{text}} {p:?} {n+1:08.3}");
-    println(f"the first value is {x} and the second is {scale(x, b: y, c: x * y + 1000000)} at last");
+    let p = P { x, y };
+    let n = scale(1, b: 5, c: 6) + scale(1, c: 4);
+    println(f"x = {x}, y = {y} {p.x:>5} {{text}} {p:?} {n + 1:08.3}");
+    println(
+        f"the first value is {x} and the second is {scale(x, b: y, c: x * y + 1000000)} at last");
$ fmt
formatted	main.vl	+10 -9 lines
% cat main.vl
// The syntax of 0.15 laid out by hand, for `volec fmt`.
#[derive(Eq, Ord, Debug)]
struct P { x: i64, y: i64 }

#[derive(Clone)]
#[repr(C)]
enum E { A, B(i64) }

trait Conv<T> { fn conv(x: T) -> Self; }

fn scale(a: i64, b: i64 = 2, c: i64 = 3) -> i64 { a * b + c }

fn half(o: Option<i64>) -> Option<i64> {
    let v = o?;
    Some(v / 2)
}

fn nested<T: Conv<Vec<i64>>>(x: sink T) -> i64 { 0 }

fn main() {
    let x = 1;
    let y = 2;
    let p = P { x, y };
    let n = scale(1, b: 5, c: 6) + scale(1, c: 4);
    println(f"x = {x}, y = {y} {p.x:>5} {{text}} {p:?} {n + 1:08.3}");
    println(
        f"the first value is {x} and the second is {scale(x, b: y, c: x * y + 1000000)} at last");
}
$ fmt --check
