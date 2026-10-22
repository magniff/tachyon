## volec edit patch and edit insert --in (tests/refactor/patch/).
## One pair: OLD occurs once in the item; the diff, then the edit.
$ edit patch clamp --old 'v < lo' --new 'v <= lo' --dry-run
--- a/calc.vl
+++ b/calc.vl
@@ -5 +5 @@
-    if v < lo {
+    if v <= lo {
$ edit patch clamp --old 'v > hi' --new 'v >= hi'
patched crate::calc::clamp	calc.vl	+1 -1 lines
% git diff
diff --git a/calc.vl b/calc.vl
index 92630d6..fc2d91b 100644
--- a/calc.vl
+++ b/calc.vl
@@ -5,7 +5,7 @@ pub fn clamp(v: i64, lo: i64, hi: i64) -> i64 {
     if v < lo {
         return lo;
     }
-    if v > hi {
+    if v >= hi {
         return hi;
     }
     v
## OLD several times: their lines, and the command with more context.
$ edit patch clamp --old 'return' --new 'return 0 +'
error patch.ambiguous: OLD 1 occurs 2 times in crate::calc::clamp, lines 6, 9; give more of the text around it, or --nth N (--all: every one)
try: volec edit patch clamp --old 'return lo;' --new 'return 0 + lo;'
try: volec edit patch clamp --old 'return hi;' --new 'return 0 + hi;'
[exit 1]
$ edit patch sum_to --old ' += ' --new ' -= '
error patch.ambiguous: OLD 1 occurs 2 times in crate::calc::sum_to, lines 19, 20; give more of the text around it, or --nth N (--all: every one)
try: volec edit patch sum_to --old 'total += i;' --new 'total -= i;'
try: volec edit patch sum_to --old 'i += 1;' --new 'i -= 1;'
[exit 1]
$ edit patch clamp --old '}' --new '} '
error patch.ambiguous: OLD 1 occurs 3 times in crate::calc::clamp, lines 7, 10, 12; give more of the text around it, or --nth N (--all: every one)
try: volec edit patch clamp --pairs .git/vole-edits/try-1.pairs
try: volec edit patch clamp --pairs .git/vole-edits/try-2.pairs
try: volec edit patch clamp --pairs .git/vole-edits/try-3.pairs
[exit 1]
## OLD nowhere: the nearest line, and the command with its text.
$ edit patch clamp --old 'v < low' --new 'v <= lo'
error patch.no-match: OLD 1 is not in crate::calc::clamp; nearest, line 5: if v < lo {
try: volec edit patch clamp --old 'v < lo' --new 'v <= lo'
[exit 1]
$ edit patch clamp --old 'v  <  lo' --new 'v <= lo'
error patch.no-match: OLD 1 is not in crate::calc::clamp as written; with other blanks, at line 5
try: volec edit patch clamp --old 'v  <  lo' --new 'v <= lo' --loose
[exit 1]
$ edit patch clamp --old 'nothing like it at all, really' --new 'x'
error patch.no-match: OLD 1 is not in crate::calc::clamp; no line is near it
try: volec query show clamp
[exit 1]
## Several pairs: one edit; when one fails nothing is written.
$ edit patch sum_to --old 'var total = 0;' --new 'var total = n * 0;' --old 'total += i;' --new 'total = total + i;'
patched crate::calc::sum_to	calc.vl	+2 -2 lines
% git diff --stat
 calc.vl | 6 +++---
 1 file changed, 3 insertions(+), 3 deletions(-)
$ edit patch sum_to --old 'var i = 1;' --new 'var i = 2;' --old 'no such text' --new 'x'
error patch.no-match: OLD 2 is not in crate::calc::sum_to; no line is near it
try: volec query show sum_to
[exit 1]
$ edit patch clamp --old 'return lo;' --new 'return true;'
calc.vl:6:16: error[type error] expected 'i64', got 'bool'  [edited: crate::calc::clamp]
error edit.breaks: 1 new error; nothing written
try: volec edit patch clamp --old 'return lo;' --new 'return true;' --no-check
[exit 1]
$ edit patch sum_to --old 'var' --new 'let' --old 'var total' --new 'let total'
error patch.ambiguous: OLD 1 occurs 2 times in crate::calc::sum_to, lines 16, 17; give more of the text around it, or --nth N (--all: every one)
try: volec edit patch sum_to --old 'var total = n * 0;' --new 'let total = n * 0;' --old 'var total' --new 'let total'
try: volec edit patch sum_to --old 'var i = 1;' --new 'let i = 1;' --old 'var total' --new 'let total'
[exit 1]
% git diff --stat
 calc.vl | 6 +++---
 1 file changed, 3 insertions(+), 3 deletions(-)
## Undo, edit by edit.
$ undo
undid patched crate::calc::sum_to	calc.vl	+2 -2 lines
% git diff --stat
 calc.vl | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
$ undo
undid patched crate::calc::clamp	calc.vl	+1 -1 lines
% git status --short
## The pairs from stdin; whole lines replaced by nothing go.
$ edit patch calc.vl:15 --dry-run < $T/inputs/sum_to.patch
--- a/calc.vl
+++ b/calc.vl
@@ -18,0 +19 @@
+        // (one term)
@@ -22 +23 @@
-    total
+    total + 0
$ edit patch sum_to --dry-run < $T/inputs/delete_line.patch
--- a/calc.vl
+++ b/calc.vl
@@ -20 +19,0 @@
-        i += 1;
$ edit patch sum_to < $T/inputs/unterminated.patch
error patch.format: stdin line 4: a block without its end; pairs are blocks of lines: <<<<<<< OLD, the old lines, =======, the new lines, >>>>>>> NEW
try: volec edit patch NAME --old OLD --new NEW
[exit 2]
$ edit patch sum_to
error edit.no-text: no --old/--new pairs, and none on stdin
try: volec edit patch sum_to --old OLD --new NEW
[exit 2]
## --loose: other indentation; NEW indented like the text it replaces.
$ edit patch clamp < $T/inputs/clamp_loose.patch
error patch.no-match: OLD 1 is not in crate::calc::clamp as written; with other blanks, at line 8
try: volec edit patch clamp --pairs .git/vole-edits/try-1.pairs --loose
[exit 1]
$ edit patch clamp --loose < $T/inputs/clamp_loose.patch
patched crate::calc::clamp	calc.vl	+1 -0 lines
% git diff
diff --git a/calc.vl b/calc.vl
index 92630d6..768545e 100644
--- a/calc.vl
+++ b/calc.vl
@@ -6,6 +6,7 @@ pub fn clamp(v: i64, lo: i64, hi: i64) -> i64 {
         return lo;
     }
     if v > hi {
+        // too big
         return hi;
     }
     v
$ undo
undid patched crate::calc::clamp	calc.vl	+1 -0 lines
## FILE:LINE (the innermost item holding it), a file, a module.
$ edit patch calc.vl:6 --old 'return lo;' --new 'return lo + 0;' --dry-run
--- a/calc.vl
+++ b/calc.vl
@@ -6 +6 @@
-        return lo;
+        return lo + 0;
$ edit patch calc.vl --old '// Small functions to patch.' --new '// Small functions, patched.' --dry-run
--- a/calc.vl
+++ b/calc.vl
@@ -1 +1 @@
-// Small functions to patch.
+// Small functions, patched.
$ edit patch crate::calc --old '// Small functions to patch.' --new '// Small functions, patched.'
patched crate::calc	calc.vl	+1 -1 lines
$ undo
undid patched crate::calc	calc.vl	+1 -1 lines
$ edit replace calc.vl:15 --dry-run < $T/inputs/sum_to_short.vl
--- a/calc.vl
+++ b/calc.vl
@@ -16,7 +16 @@
-    var total = 0;
-    var i = 1;
-    while i <= n {
-        total += i;
-        i += 1;
-    }
-    total
+    n * (n + 1) / 2
$ edit delete calc.vl:4 --dry-run
--- a/calc.vl
+++ b/calc.vl
@@ -3,11 +2,0 @@
-// v, kept within [lo, hi].
-pub fn clamp(v: i64, lo: i64, hi: i64) -> i64 {
-    if v < lo {
-        return lo;
-    }
-    if v > hi {
-        return hi;
-    }
-    v
-}
-
main.vl:4:12: error[type error] unresolved import 'calc::clamp'
warning edit.breaks: 1 new error (dry run)
[exit 1]
$ edit patch calc.vl:13 --old 'v' --new 'w'
error patch.no-match: OLD 1 is not in calc.vl:13; no line is near it
try: volec query show calc.vl:13
[exit 1]
## insert --in: at a text anchor, indented like its line (inside a block
## after a `{`).
$ edit insert --in sum_to --after 'while i <= n {' --dry-run < $T/inputs/stmt.vl
--- a/calc.vl
+++ b/calc.vl
@@ -18,0 +19,3 @@
+        if i == 3 {
+            total += 0;
+        }
$ edit insert --in sum_to --before 'i += 1;' < $T/inputs/stmt.vl
inserted in crate::calc::sum_to	calc.vl	+3 -0 lines
% git diff
diff --git a/calc.vl b/calc.vl
index 92630d6..5ce629b 100644
--- a/calc.vl
+++ b/calc.vl
@@ -17,6 +17,9 @@ pub fn sum_to(n: i64) -> i64 {
     var i = 1;
     while i <= n {
         total += i;
+        if i == 3 {
+            total += 0;
+        }
         i += 1;
     }
     total
$ undo
undid inserted in crate::calc::sum_to	calc.vl	+3 -0 lines
$ edit insert --in sum_to --before 'var' < $T/inputs/stmt.vl
error patch.ambiguous: ANCHOR occurs 2 times in crate::calc::sum_to, lines 16, 17; give more of the text around it, or --nth N
try: volec edit insert --in sum_to --before 'var total = 0;' < text.vl
try: volec edit insert --in sum_to --before 'var i = 1;' < text.vl
[exit 1]
## (0.13: an anchor that is a whole line somewhere names that line)
$ edit insert --in sum_to --before 'total' --dry-run < $T/inputs/stmt.vl
--- a/calc.vl
+++ b/calc.vl
@@ -21,0 +22,3 @@
+    if i == 3 {
+        total += 0;
+    }
$ edit insert --in sum_to --after 'i = 1;' < $T/inputs/stmt.vl
inserted in crate::calc::sum_to	calc.vl	+3 -0 lines
$ edit insert --in sum_to --after 'i += 1;'
error edit.no-text: the text to insert is read from stdin; none was given
try: volec edit insert --in sum_to --after 'i += 1;' < text.vl
[exit 2]
## Usage.
$ edit patch clamp --old 'v'
error edit.usage: each --old needs its --new
try: volec edit patch NAME --old OLD --new NEW
[exit 2]
$ edit patch --old 'v' --new 'w'
error edit.usage: a TARGET is needed
try: volec edit patch NAME --old OLD --new NEW
[exit 2]
## 0.12: a module's use lines (MODULE::use) and header comment
## (MODULE::header) as TARGET: patch, replace, insert, delete.
$ edit patch crate::use --old 'clamp, sum_to' --new 'sum_to, clamp'
note edit.unchanged: nothing to change
$ edit patch main::header --old 'to patch' --new 'to edit' --show
patched main::header	main.vl	+1 -1 lines
// main.vl:1
1	// A program to edit (tests/refactor/patch.t).
$ edit patch calc::use --old a --new b
error patch.no-region: no use lines in crate::calc; edit replace adds them
try: volec edit replace calc::use < uses.vl
[exit 1]
$ edit replace calc::header < $T/inputs/header.txt
replaced crate::calc::header	calc.vl	+2 -1 lines
$ edit insert --after crate::use < $T/inputs/use_alias.vl
inserted after crate::use	main.vl	+1 -0 lines
$ edit insert --before calc::header < $T/inputs/header.txt
error edit.layout: a header comment is replaced, not inserted next to
try: volec edit replace crate::calc::header < header.txt
[exit 1]
$ edit replace crate::use --dry-run < $T/inputs/use_alias.vl
--- a/main.vl
+++ b/main.vl
@@ -4 +3,0 @@
-use calc::{clamp, sum_to};
main.vl:7:13: error[type error] undefined variable 'clamp' | help: add `use crate::calc::clamp;` | try: volec fix --suggested main.vl  [in crate::main]
main.vl:8:13: error[type error] undefined variable 'sum_to' | help: add `use crate::calc::sum_to;` | try: volec fix --suggested main.vl  [in crate::main]
warning edit.breaks: 2 new errors (2 in crate::main, which the edit does not change) (dry run)
[exit 1]
$ edit delete crate::header
deleted crate::header	main.vl	+0 -1 lines
% cat main.vl
mod calc;

use calc::{clamp, sum_to};
use calc::clamp as clip;

fn main() -> i32 {
    let a = clamp(15, 0, 10);
    let b = sum_to(4);
    if a + b == 20 { 0 } else { 1 }
}
% cat calc.vl
// Arithmetic helpers: clamp and sum_to,
// patched by tests/refactor/patch.t.

// v, kept within [lo, hi].
pub fn clamp(v: i64, lo: i64, hi: i64) -> i64 {
    if v < lo {
        return lo;
    }
    if v > hi {
        return hi;
    }
    v
}

// 1 + 2 + ... + n.
pub fn sum_to(n: i64) -> i64 {
    var total = 0;
    var i = 1;
    if i == 3 {
        total += 0;
    }
    while i <= n {
        total += i;
        i += 1;
    }
    total
}
