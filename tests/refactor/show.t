## fix --only unsafe: a function with several unsafe operations gets its
## whole body in one block; edit --show prints the changed lines; query
## diff the last edit (tests/refactor/show/).
$ fix --only unsafe --dry-run
--- a/main.tach
+++ b/main.tach
@@ -10,2 +10,3 @@
-    let x = abs(a) as i64;
-    let y = abs(b) as i64;
+    unsafe {
+        let x = abs(a) as i64;
+        let y = abs(b) as i64;
@@ -13 +14,2 @@
-    x + y
+        x + y
+    }
@@ -19 +21 @@
-    k * abs(a) as i64
+    unsafe { k * abs(a) as i64 }
$ fix --only unsafe --show
fixed 2 unsafe blocks	main.tach	+6 -4 lines
// main.tach:10-12
10	    unsafe {
11	        let x = abs(a) as i64;
12	        let y = abs(b) as i64;
// main.tach:14-15
14	        x + y
15	    }
// main.tach:21
21	    unsafe { k * abs(a) as i64 }
$ query diff
# fixed 2 unsafe blocks	main.tach	+6 -4 lines
--- a/main.tach
+++ b/main.tach
@@ -10,2 +10,3 @@
-    let x = abs(a) as i64;
-    let y = abs(b) as i64;
+    unsafe {
+        let x = abs(a) as i64;
+        let y = abs(b) as i64;
@@ -13 +14,2 @@
-    x + y
+        x + y
+    }
@@ -19 +21 @@
-    k * abs(a) as i64
+    unsafe { k * abs(a) as i64 }
$ check
$ edit patch one --show < $T/inputs/show_add.patch
patched crate::one	main.tach	+2 -1 lines
// main.tach:21-22
21	    let twice = k + k;
22	    unsafe { twice * abs(a) as i64 / 2 }
$ edit patch spread --old '        let y = abs(b) as i64;' --new '' --no-check --show
main.tach:13:13: error[type error] undefined variable 'y'  [edited: crate::spread]
patched crate::spread	main.tach	+0 -1 lines
// main.tach:11: 1 line removed after line 11
warning edit.breaks: 1 new error; written anyway (--no-check)
try: tachyonc check
$ query diff
# patched crate::spread	main.tach	+0 -1 lines
--- a/main.tach
+++ b/main.tach
@@ -12 +11,0 @@
-        let y = abs(b) as i64;
$ undo
undid patched crate::spread	main.tach	+0 -1 lines
$ undo
undid patched crate::one	main.tach	+2 -1 lines
$ query diff
# fixed 2 unsafe blocks	main.tach	+6 -4 lines
--- a/main.tach
+++ b/main.tach
@@ -10,2 +10,3 @@
-    let x = abs(a) as i64;
-    let y = abs(b) as i64;
+    unsafe {
+        let x = abs(a) as i64;
+        let y = abs(b) as i64;
@@ -13 +14,2 @@
-    x + y
+        x + y
+    }
@@ -19 +21 @@
-    k * abs(a) as i64
+    unsafe { k * abs(a) as i64 }
$ undo
undid fixed 2 unsafe blocks	main.tach	+6 -4 lines
$ query diff
error undo.empty: no edit in the journal
[exit 1]
