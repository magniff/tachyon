## The refactorings on 0.15's syntax that need no 0.15 checking
## (tests/refactor/shorthand015/): a field shorthand `S { x }` is both
## the field and the value, so a renamed field writes `S { y: x }` and a
## renamed local, parameter or const `S { x: y }`; inline puts `x: ARG`;
## --add with --fill-calls (or before a parameter without a default)
## writes the value into the calls, with a note; extract-function and
## inline refuse `?`, which may return from the function (the program has
## the `?` stub's error).
$ refactor field P --rename x px --dry-run
--- a/main.tach
+++ b/main.tach
@@ -4 +4 @@
-struct P { x: i64, y: i64 }
+struct P { px: i64, y: i64 }
@@ -10 +10 @@
-    P { x, y }
+    P { px: x, y }
@@ -18 +18 @@
-    P { x, y: p.y }
+    P { px: x, y: p.y }
@@ -25 +25 @@
-    (q.x + q.y + c.LIMIT - 17) as i32
+    (q.px + q.y + c.LIMIT - 17) as i32
$ refactor rename main.tach:9:9 yy --dry-run
--- a/main.tach
+++ b/main.tach
@@ -9,2 +9,2 @@
-    let y = k * 2;
-    P { x, y }
+    let yy = k * 2;
+    P { x, y: yy }
$ refactor signature make --rename-param x xx --dry-run
--- a/main.tach
+++ b/main.tach
@@ -8 +8 @@
-fn make(x: i64, k: i64) -> P {
+fn make(xx: i64, k: i64) -> P {
@@ -10 +10 @@
-    P { x, y }
+    P { x: xx, y }
$ refactor rename LIMIT MAXV --dry-run
--- a/main.tach
+++ b/main.tach
@@ -2 +2 @@
-const LIMIT: i64 = 10;
+const MAXV: i64 = 10;
@@ -14 +14 @@
-    Cap { LIMIT }
+    Cap { LIMIT: MAXV }
$ refactor inline shift --dry-run
--- a/main.tach
+++ b/main.tach
@@ -17,4 +16,0 @@
-fn shift(p: P, x: i64) -> P {
-    P { x, y: p.y }
-}
-
@@ -23 +19 @@
-    let q = shift(p, 3);
+    let q = P { x: 3, y: p.y };
$ refactor signature make --add 'z: i64 = 5' --fill-calls --dry-run
--- a/main.tach
+++ b/main.tach
@@ -8 +8 @@
-fn make(x: i64, k: i64) -> P {
+fn make(x: i64, k: i64, z: i64) -> P {
@@ -22 +22 @@
-    let p = make(1, 2);
+    let p = make(1, 2, 5);
$ refactor signature make --add 'z: i64 = 5' --at 0 --dry-run
--- a/main.tach
+++ b/main.tach
@@ -8 +8 @@
-fn make(x: i64, k: i64) -> P {
+fn make(z: i64, x: i64, k: i64) -> P {
@@ -22 +22 @@
-    let p = make(1, 2);
+    let p = make(5, 1, 2);
note refactor.fill-calls: the calls get the value (a default is on trailing parameters only, and a later one has none)
$ refactor extract-function half --lines 30-31 --to part --dry-run
error refactor.escapes: line 30 may return (`?`) from crate::half: out of lines 30-31, which NEW cannot do for its caller
try: tachyonc query show main.tach:30
[exit 1]
$ refactor inline half --dry-run
error refactor.escapes: crate::half may return early (`?`), on line 30: inline takes a function that ends with its value
try: tachyonc query show main.tach:30
[exit 1]
$ explain refactor.fill-calls
refactor.fill-calls: note, exit 0
`refactor signature FN --add 'x: T = V'` (0.15) declares V as x's default and leaves the calls as they are; but with --fill-calls, for a trait's function (which has no defaults) or before a parameter without one (defaults are on trailing parameters only), every call gets V, as in 0.14: by position, or `x: V` when a parameter before x is left to its default.
fix: Nothing to fix; leave out --fill-calls, or add x after the parameters without a default (--at), to declare a default instead.
example:
    note refactor.fill-calls: the calls get the value (a trait's function has no defaults)
## (0.16) A tool's name with its `-` lists its codes; a subcommand's own
## help.
$ explain same-output
same-output.differs	error, exit 1
same-output.no-compiler	error, exit 2
same-output.no-corpus	error, exit 2
same-output.not-run	warning
same-output.target	note
same-output.usage	error, exit 2
same-output.work	error, exit 2
$ edit apply --help
tachyonc edit apply [FILE]   several items' new text in one checked edit (stdin without FILE)
blocks: @@ NAME (its new text), @@ new after|before NAME, @@ new in MODULE, @@ delete NAME,
@@ MODULE::use, @@ MODULE::header; or query show's output, changed
--show: the diff after; --dry-run: the diff only; --no-check: write despite new errors
