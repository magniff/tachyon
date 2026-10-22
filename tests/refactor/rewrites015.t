## volec rewrite (0.15): `$s...` over a block's statements, the sites
## left when the replacement drops a binding they use, loops and matches
## (tests/refactor/rewrites015/).
$ check
ok: 0 errors in main.vl
## A loop's body: its first statement, then the others in $s...; their
## comments go with them, their lines as they were. weighted's loop uses
## i, which the replacement drops: left.
$ rewrite 'for $i in 0..$v.len { let $x = $v[$i]; $s... }' 'for $x in $v.iter() { $s... }' --dry-run
--- a/main.vl
+++ b/main.vl
@@ -4,2 +4 @@
-    for i in 0..s.len {
-        let x = s[i];
+    for x in s.iter() {
@@ -26,2 +25 @@
-    for k in 0..s.len {
-        let x = s[k];
+    for x in s.iter() {
@@ -30,4 +28,2 @@
-    for k in 0..s.len {
-        let x = s[k];
-    }
-    for k in 0..s.len { let x = s[k]; t -= x; }
+    for x in s.iter() {}
+    for x in s.iter() { t -= x; }
note rewrite.dropped: 1 site is left: the replacement drops $i, which the code it keeps uses; first: main.vl:19:18
try: volec query show main.vl:19
## `$s...;` written as a statement of the replacement.
$ rewrite 'for $i in 0..$v.len { let $x = $v[$i]; $s... }' 'for $x in $v.iter() { $s...; t += 0; }' --in main.vl --dry-run
--- a/main.vl
+++ b/main.vl
@@ -4,2 +4 @@
-    for i in 0..s.len {
-        let x = s[i];
+    for x in s.iter() {
@@ -10,0 +10 @@
+        t += 0;
@@ -26,3 +26,3 @@
-    for k in 0..s.len {
-        let x = s[k];
-        t = t + x
+    for x in s.iter() {
+        t = t + x;
+        t += 0;
@@ -30,2 +30,2 @@
-    for k in 0..s.len {
-        let x = s[k];
+    for x in s.iter() {
+        t += 0;
@@ -33 +33 @@
-    for k in 0..s.len { let x = s[k]; t -= x; }
+    for x in s.iter() { t -= x; t += 0; }
note rewrite.dropped: 1 site is left: the replacement drops $i, which the code it keeps uses; first: main.vl:19:18
try: volec query show main.vl:19
## Statements before $s... (and none after).
$ rewrite '{ var $t = 0; $s... }' '{ var $t = 1; $s... }' --dry-run
--- a/main.vl
+++ b/main.vl
@@ -3 +3 @@
-    var t = 0;
+    var t = 1;
@@ -16 +16 @@
-    var t = 0;
+    var t = 1;
@@ -25 +25 @@
-    var t = 0;
+    var t = 1;
## A match, its arms' patterns with holes.
$ rewrite 'match $o { Option::Some($y) => $a, Option::None => $b }' 'if let Option::Some($y) = $o { $a } else { $b }' --dry-run
--- a/main.vl
+++ b/main.vl
@@ -38,3 +38,4 @@
-    match o {
-        Option::Some(v) => v + 1,
-        Option::None => 0,
+    if let Option::Some(v) = o {
+        v + 1
+    } else {
+        0
## Written, then checked: the program still runs.
$ rewrite 'for $i in 0..$v.len { let $x = $v[$i]; $s... }' 'for $x in $v.iter() { $s... }'
rewrote 4 sites in 1 file	main.vl	+4 -8 lines
note rewrite.dropped: 1 site is left: the replacement drops $i, which the code it keeps uses; first: main.vl:19:18
try: volec query show main.vl:19
$ check
ok: 0 errors in main.vl
## Errors.
$ rewrite 'for $i in 0..$v.len { $a...; $b... }' '0'
error rewrite.pattern: one $x... per list of arguments or block
[exit 2]
$ rewrite 'if $s... { 1 } else { 2 }' '0'
error rewrite.pattern: $x... stands for arguments or statements: write it in the arguments of a call, a tuple or an array, or among a block's statements
[exit 2]
