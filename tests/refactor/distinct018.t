## Distinct types (0.18, tests/refactor/distinct018/): distinct.mix for a
## distinct type where its underlying type goes (or the reverse), the
## operand that is not distinct converted in an operation, and
## distinct.method for a method of the underlying type: each `try:` is
## the conversion, made by `fix --suggested`; the program then runs.
$ check
main.vl:19:21: error[distinct.mix] 'd + x' mixes 'Meters' and 'f64' | help: a distinct type's operators take two of it (or one and a literal): convert the other operand with 'as' (free) | try: d + x as Meters | try: volec fix --suggested main.vl
main.vl:20:20: error[distinct.mix] 'x * d' mixes 'f64' and 'Meters' | help: a distinct type's operators take two of it (or one and a literal): convert the other operand with 'as' (free) | try: x as Meters * d | try: volec fix --suggested main.vl
main.vl:21:22: error[distinct.mix] 'd' is 'Meters' where 'f64' goes | help: a distinct type and its underlying type do not mix: convert with 'as' (free) | try: d as f64 | try: volec fix --suggested main.vl
main.vl:22:23: error[distinct.mix] 'd' is 'Meters' where 'f64' goes | help: a distinct type and its underlying type do not mix: convert with 'as' (free) | try: d as f64 | try: volec fix --suggested main.vl
main.vl:24:13: error[distinct.method] 'sum' is a method of 'Pos', not of 'Point' | help: a distinct type has only the methods its own impl gives it: convert to call the underlying type's | try: (p as Pos).sum(..) | try: volec fix --suggested main.vl
[exit 1]
$ fix --suggested --dry-run
--- a/main.vl
+++ b/main.vl
@@ -19,4 +19,4 @@
-    let total = d + x;
-    let back = x * d;
-    let plain: f64 = d;
-    let twice = scale(d);
+    let total = d + x as Meters;
+    let back = x as Meters * d;
+    let plain: f64 = d as f64;
+    let twice = scale(d as f64);
@@ -24 +24 @@
-    let s = p.sum();
+    let s = (p as Pos).sum();
$ fix --suggested
fixed 5 suggested fixes	main.vl	+5 -5 lines
$ check
ok: 0 errors in main.vl
$ main.vl -o prog
ok: built prog
% ./prog
4 3.75 2.5 5 3
