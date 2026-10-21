## tachyonc rewrite (tests/refactor/rewrites/).
$ check
ok: 0 errors in main.tach
## A typed hole: only the calls whose $v the checker typed *IntVec.
$ rewrite 'grow($v, $n)' '$v.reserve($n)' --where '$v: &mut IntVec' --dry-run
note rewrite.none: nothing matches 'grow($v, $n)'
note rewrite.types: 5 sites match but for --where; first: $v is inout IntVec at main.tach:10:10
try: tachyonc rewrite 'grow($v, $n)' '$v.reserve($n)' --where '$v: inout IntVec' --dry-run
## No site has that type: what the sites have, and the command for it.
$ rewrite 'grow($v, $n)' '$v.reserve($n)' --where '$v: IntVec'
note rewrite.none: nothing matches 'grow($v, $n)'
note rewrite.types: 5 sites match but for --where; first: $v is inout IntVec at main.tach:10:10
try: tachyonc rewrite 'grow($v, $n)' '$v.reserve($n)' --where '$v: inout IntVec' --dry-run
## Casts and comparisons (`x as i64 < y` compares, 0.11).
$ rewrite '$a as i64 < $b.len' '$a < $b.len as i64' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -14 +14 @@
-    if n as i64 < v.len {
+    if n < v.len as i64 {
## A hole written twice matches the same code only.
$ rewrite 'twice($x) * twice($x)' 'square(twice($x))' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -17 +17 @@
-    let total = twice(n + 1) * twice(n + 1) + twice(n) * twice(n + 1);
+    let total = square(twice(n + 1)) + twice(n) * twice(n + 1);
## Parentheses where the operators around need them; a site inside a
## rewritten one is left for the next run.
$ rewrite 'double($x)' '$x + $x' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -18 +18 @@
-    let k = 3 * double(n + 1) + double(double(n));
+    let k = 3 * (n + 1 + (n + 1)) + (double(n) + double(n));
note rewrite.nested: 1 site inside a rewritten one is left; run the rewrite again
## Arguments: $rest... matches any number of them (none: its comma goes).
$ rewrite 'log($first, $rest...)' 'trace(0, $rest..., $first)' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -3,0 +4 @@
+use crate::util::{double, square, trace, twice};
@@ -5 +5,0 @@
-use crate::util::{double, log, square, trace, twice};
@@ -19 +19 @@
-    log(1, 2);
+    trace(0, 2, 1);
note rewrite.imports: removed 1 import the rewrite left unused
$ rewrite 'double($x, $rest...)' 'twice($x, $rest...)' --in util.tach --dry-run
note rewrite.none: nothing matches 'double($x, $rest...)'
$ rewrite 'double($x, $rest...)' 'twice($x, $rest...)' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -18 +18 @@
-    let k = 3 * double(n + 1) + double(double(n));
+    let k = 3 * twice(n + 1) + twice(double(n));
note rewrite.nested: 1 site inside a rewritten one is left; run the rewrite again
## Statements.
$ rewrite 'grow($v, $n);' 'grow($v, $n + 1);' --in main.tach --dry-run
--- a/main.tach
+++ b/main.tach
@@ -10 +10 @@
-    grow(&v, 10);
+    grow(&v, 10 + 1);
@@ -25,2 +25,2 @@
-    grow(&p, n);
-    grow(&p, n * 2);
+    grow(&p, n + 1);
+    grow(&p, n * 2 + 1);
@@ -31,2 +31,2 @@
-    grow(&v, 2);
-    grow(&v, 2);
+    grow(&v, 2 + 1);
+    grow(&v, 2 + 1);
## Written, then undone.
$ rewrite 'twice($x) * twice($x)' 'square(twice($x))'
rewrote 1 site in 1 file	main.tach	+1 -1 lines
% git diff
diff --git a/main.tach b/main.tach
index 0528a7e..065d912 100644
--- a/main.tach
+++ b/main.tach
@@ -14,7 +14,7 @@ fn main() -> i32 {
     if n as i64 < v.len {
         v.len = 1;
     }
-    let total = twice(n + 1) * twice(n + 1) + twice(n) * twice(n + 1);
+    let total = square(twice(n + 1)) + twice(n) * twice(n + 1);
     let k = 3 * double(n + 1) + double(double(n));
     log(1, 2);
     grow_twice(&v, 7);
$ undo
undid rewrote 1 site in 1 file	main.tach	+1 -1 lines
## A rewrite that breaks the program: nothing written.
$ rewrite 'grow($v, $n)' 'grow($n, $v)'
main.tach:10:10: error[type error] expected 'inout IntVec', got 'i64'  [edited: crate::main]
main.tach:25:10: error[type error] expected 'inout IntVec', got 'i64'  [edited: crate::more]
main.tach:26:10: error[type error] expected 'inout IntVec', got 'i64'  [edited: crate::more]
main.tach:31:10: error[type error] expected 'inout IntVec', got 'i64' | note: in instantiation of 'grow_twice<i64>' at main.tach:20:5  [edited: crate::grow_twice]
main.tach:32:10: error[type error] expected 'inout IntVec', got 'i64' | note: in instantiation of 'grow_twice<i64>' at main.tach:20:5  [edited: crate::grow_twice]
error edit.breaks: 5 new errors; nothing written
try: tachyonc rewrite 'grow($v, $n)' 'grow($n, $v)' --no-check
[exit 1]
% git status --short
## Patterns that are no pattern.
$ rewrite '$x' 'f($x)'
error rewrite.pattern: the pattern is a hole alone: it would match every expression
[exit 2]
$ rewrite 'grow($v, $n' '$v'
error rewrite.pattern: the pattern is no tachyon expression: expected ')', got 'EOF'
[exit 2]
$ rewrite 'grow($v, $n)' 'f($w)'
error rewrite.unbound: the replacement's $w is not in the pattern, and the replacement binds no name with it (`for $x in`, `let $x =`)
[exit 2]
$ rewrite 'grow($v...) + 1' 'f()'
note rewrite.none: nothing matches 'grow($v...) + 1'
$ rewrite 'x + $rest...' 'x'
error rewrite.pattern: $x... stands for arguments or statements: write it in the arguments of a call, a tuple or an array, or among a block's statements
[exit 2]
$ rewrite 'grow($v, $n)' '$v' --where '$w: i64'
error rewrite.usage: --where names $w, which the pattern has not (or has as '$w...')
[exit 2]
$ rewrite 'nothing($x)' '$x'
note rewrite.none: nothing matches 'nothing($x)'
## Holes for types and for a let's binding (a hole's type name takes no
## `<`: parentheses).
$ rewrite '($a as $T) < $b' '$b > ($a as $T)' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -14 +14 @@
-    if n as i64 < v.len {
+    if v.len > (n as i64) {
$ rewrite 'let $v = 3;' 'let $v = 4;' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -13 +13 @@
-    let n = 3;
+    let n = 4;
