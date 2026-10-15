## Edit precision (0.13, tests/refactor/precision/).
## edit patch: OLD's lines may end (or start) inside a line, in a block too.
$ edit patch sum_to --dry-run < $T/inputs/partial.patch
--- a/calc.tach
+++ b/calc.tach
@@ -16 +16 @@
-    let mut total = 0;
+    let mut total = 0 * n;
@@ -18,0 +19 @@
+        // (a term)
## --pairs FILE: the blocks from a file, no stdin, no shell quoting.
$ edit patch sum_to --dry-run --pairs $T/inputs/partial.patch
--- a/calc.tach
+++ b/calc.tach
@@ -16 +16 @@
-    let mut total = 0;
+    let mut total = 0 * n;
@@ -18,0 +19 @@
+        // (a term)
$ edit patch sum_to --pairs nothing.patch
error edit.no-text: cannot read --pairs nothing.patch
[exit 2]
## A miss after OLD's first lines: where they match, how the next differs.
$ edit patch sum_to --pairs $T/inputs/stops.patch
error patch.no-match: OLD 1 is not in crate::calc::sum_to; its lines 1-2 match lines 18-19, then its line 3 'i += 2;' is not line 20 'i += 1;'
try: tachyonc query text calc.tach:18-20
[exit 1]
## Several matches in the block form: widened pairs, written to a file.
$ edit patch clamp --pairs $T/inputs/twice.patch
error patch.ambiguous: OLD 1 occurs 2 times in crate::calc::clamp, lines 6, 9; give more of the text around it, or --nth N (--all: every one)
try: tachyonc edit patch clamp --pairs .git/tachyon-edits/try-1.pairs
try: tachyonc edit patch clamp --pairs .git/tachyon-edits/try-2.pairs
[exit 1]
% cat .git/tachyon-edits/try-1.pairs
<<<<<<< OLD
return lo;
=======
return 0 + lo;
>>>>>>> NEW
## Widened OLDs of several lines on the command line: a file, not $'...'.
$ edit patch clamp --old '}' --new '} '
error patch.ambiguous: OLD 1 occurs 3 times in crate::calc::clamp, lines 7, 10, 12; give more of the text around it, or --nth N (--all: every one)
try: tachyonc edit patch clamp --pairs .git/tachyon-edits/try-1.pairs
try: tachyonc edit patch clamp --pairs .git/tachyon-edits/try-2.pairs
try: tachyonc edit patch clamp --pairs .git/tachyon-edits/try-3.pairs
[exit 1]
% cat .git/tachyon-edits/try-3.pairs
<<<<<<< OLD
v
}
=======
v
} 
>>>>>>> NEW
## edit wrap: a body, or lines, in a block, one level deeper.
$ edit wrap first --in unsafe --show
wrapped the body of crate::calc::first in unsafe	calc.tach	+4 -2 lines
// calc.tach:32-35
32	    unsafe {
33	        let a = p[0];
34	        a + 0
35	    }
$ edit wrap sum_to --in '' --lines 17-21 --dry-run
--- a/calc.tach
+++ b/calc.tach
@@ -17,4 +17,6 @@
-    let mut i = 1;
-    while i <= n {
-        total += i;
-        i += 1;
+    {
+        let mut i = 1;
+        while i <= n {
+            total += i;
+            i += 1;
+        }
$ edit wrap sum_to --in '' --lines 16
calc.tach:21:9: error[type error] undefined variable 'total'  [edited: crate::calc::sum_to]
calc.tach:24:5: error[type error] undefined variable 'total'  [edited: crate::calc::sum_to]
error edit.breaks: 2 new errors; nothing written
try: tachyonc edit wrap sum_to --in '' --lines 16 --no-check
[exit 1]
$ edit wrap sum_to --in loop --lines 30-31
error edit.wrap: lines 30-31 are not all in crate::calc::sum_to (lines 14-23)
try: tachyonc query show crate::calc::sum_to
[exit 1]
$ edit wrap clamp --in unsafe --lines 5-6
wrapped lines 5-6 of crate::calc::clamp in unsafe	calc.tach	+4 -2 lines
$ edit wrap calc.tach:19 --in unsafe --dry-run
--- a/calc.tach
+++ b/calc.tach
@@ -18,5 +18,8 @@
-    let mut total = 0;
-    let mut i = 1;
-    while i <= n {
-        total += i;
-        i += 1;
+    unsafe {
+        let mut total = 0;
+        let mut i = 1;
+        while i <= n {
+            total += i;
+            i += 1;
+        }
+        total
@@ -24 +26,0 @@
-    total
## edit new-file: the file and its mod line, one checked edit.
$ edit new-file lib/extra.tach --pub --show < $T/inputs/newmod.tach
made crate::lib::extra	2 files	+6 -0 lines
// lib/mod.tach:3
3	pub mod extra;
// lib/extra.tach:1-5
1	// lib's second child.
2	
3	pub fn triple(x: i64) -> i64 {
4	    x * 3
5	}
$ edit patch lib::extra::triple --old 'x * 3' --new 'x + x + x'
patched crate::lib::extra::triple	lib/extra.tach	+1 -1 lines
$ edit new-file lib/extra.tach < $T/inputs/newmod.tach
error edit.exists: 'lib/extra.tach' exists already; nothing written
[exit 1]
$ edit new-file nowhere/deep/x.tach < $T/inputs/newmod.tach
error edit.no-parent: no file of the program has nowhere/deep/x.tach as a child's file (a mod.tach or the root next to it, or the file its directory is named after)
try: tachyonc query items
[exit 1]
## refactor signature --type with --default: a new argument at each call.
$ refactor signature scale --type k i16 --default '$k as i16' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -11 +11 @@
-    let c = scale(a, 2) + scale(b, n + 1);
+    let c = scale(a, 2 as i16) + scale(b, (n + 1) as i16);
--- a/calc.tach
+++ b/calc.tach
@@ -28 +28 @@
-pub fn scale(v: i64, k: i32) -> i64 {
+pub fn scale(v: i64, k: i16) -> i64 {
$ refactor signature scale --type k i16
main.tach:11:36: error[type error] expected 'i16', got 'i32' | help: only widening is implicit: convert explicitly | try: n as i16  [in crate::main]
error edit.breaks: 1 new error (1 in crate::main, which the edit does not change); nothing written
note edit.refactor: the uses of crate::calc::scale no longer fit its new shape: a refactoring changes them with it, then the rest of the edit
try: tachyonc refactor signature crate::calc::scale --type k i16 --default '$k as i16'
note edit.together: change crate::main in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: tachyonc query show crate::main
try: tachyonc refactor signature scale --type k i16 --no-check
[exit 1]
$ refactor signature clamp --add 'x: i64 = 0' --default 0
error refactor.usage: --default goes with --type (the calls' new argument)
try: tachyonc refactor signature NAME --type x T --default EXPR
[exit 2]
## fix --in MODULE: its child modules too.
$ edit patch lib/inner.tach --old 'use crate::calc::clamp;' --new '' --no-check
lib/inner.tach:4:5: error[type error] undefined variable 'clamp' | help: add `use crate::calc::clamp;` | try: tachyonc fix --only imports main.tach  [in crate::lib::inner::double]
patched crate::lib::inner	lib/inner.tach	+0 -1 lines
warning edit.breaks: 1 new error (1 in crate::lib::inner::double, which the edit does not change); written anyway (--no-check)
try: tachyonc check
$ fix --in crate::lib --dry-run
--- a/lib/inner.tach
+++ b/lib/inner.tach
@@ -2,0 +3,2 @@
+use crate::calc::clamp;
+
$ fix --in crate::lib
fixed 1 missing import	lib/inner.tach	+2 -0 lines
