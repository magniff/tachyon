## The tools' fixes of 0.16 (tests/refactor/tools016/).
## fix --only imports, when several modules have the name: the nearest
## (the innermost module holding both, then the fewest segments) when it
## is the only one so near; else fix.ambiguous, one try: per candidate,
## and nothing imported for it.
$ fix --only imports --dry-run
--- a/tools/query/show.tach
+++ b/tools/query/show.tach
@@ -0,0 +1,2 @@
+use crate::tools::query::positions::is_blank;
+
error fix.ambiguous: crate::back uses 'is_blank', which 2 modules as near have: crate::back::asm, crate::back::obj; nothing is imported for it: name one with --use
try: tachyonc fix --only imports --use crate::back::asm::is_blank
try: tachyonc fix --only imports --use crate::back::obj::is_blank
[exit 1]
$ fix --only imports --use crate::back::obj::is_blank
fixed 2 missing imports	2 files	+4 -0 lines
$ check
ok: 0 errors in main.tach
## edit patch: OLD occurs several times: the error names --nth and --all;
## --nth N patches the Nth, --all every one; --nth past the last.
$ edit patch clamp --old 'r = ' --new 'r = 0 + '
error patch.ambiguous: OLD 1 occurs 3 times in crate::calc::clamp, lines 2, 4, 7; give more of the text around it, or --nth N (--all: every one)
try: tachyonc edit patch clamp --old 'var r = v;' --new 'var r = 0 + v;'
try: tachyonc edit patch clamp --old 'r = lo;' --new 'r = 0 + lo;'
try: tachyonc edit patch clamp --old 'r = hi;' --new 'r = 0 + hi;'
[exit 1]
$ edit patch clamp --old 'r = ' --new 'r = 0 + ' --nth 3 --dry-run
--- a/calc.tach
+++ b/calc.tach
@@ -7 +7 @@
-        r = hi;
+        r = 0 + hi;
$ edit patch clamp --old 'hi' --new 'top' --all --dry-run
--- a/calc.tach
+++ b/calc.tach
@@ -1 +1 @@
-pub fn clamp(v: i64, lo: i64, hi: i64) -> i64 {
+pub fn clamp(v: i64, lo: i64, top: i64) -> i64 {
@@ -6,2 +6,2 @@
-    if r > hi {
-        r = hi;
+    if r > top {
+        r = top;
$ edit patch clamp --old 'r = ' --new 'r = 0 + ' --nth 4
error patch.nth: OLD 1 occurs 3 times in crate::calc::clamp; --nth 4 is past the last
[exit 1]
$ edit insert --in clamp --after 'r = ' --nth 2 --dry-run < $T/inputs/tools016_line.tach
--- a/calc.tach
+++ b/calc.tach
@@ -4,0 +5 @@
+        r += 0;
$ edit insert --in clamp --after 'r = ' --all < $T/inputs/tools016_line.tach
error edit.usage: --all is for patch; insert --in takes --nth N
try: tachyonc edit insert --in NAME --after ANCHOR < text.tach
[exit 2]
## Two steps of a script that each add an import: the note once.
$ refactor --script $T/inputs/tools016_steps.txt --dry-run
patched crate::calc::clamp	calc.tach	+3 -1 lines
patched crate::back::f	back/mod.tach	+2 -1 lines
--- a/calc.tach
+++ b/calc.tach
@@ -0,0 +1,2 @@
+use crate::loops::total;
+
@@ -7 +9 @@
-        r = hi;
+        r = hi + total() * 0;
--- a/back/mod.tach
+++ b/back/mod.tach
@@ -1,0 +2 @@
+use crate::calc::clamp;
@@ -7 +8 @@
-    is_blank(c)
+    is_blank(c) && clamp(1, 0, 2) > 0
note edit.imports: added the imports the new text needs (fix --only imports)
## rewrite --list: a line per site, what each hole matched.
$ rewrite 'for $i in 0..$v.count { $s... }' --list
loops.tach:8:5	$i=i	$v=w	$s...=t += w.data[i] * 2; if w.data[i] > 2 { t += w.data[i]; }
loops.tach:15:5	$i=i	$v=w	$s...=t += w.data[i] + x + i;
loops.tach:18:5	$i=j	$v=w	$s...=t -= w.data[j];
## Name holes: `$x~/re/`, `--where '$x: name'` (any name or path, not
## another expression), `--where '$x: name ~ RE'`.
$ rewrite 'for $i~/^j$/ in 0..$v.count { $s... }' --list
loops.tach:18:5	$i=j	$v=w	$s...=t -= w.data[j];
$ rewrite '$v.data[$i]' --where '$v: name ~ ^w$, $i: name' --list
loops.tach:9:14	$v=w	$i=i
loops.tach:10:12	$v=w	$i=i
loops.tach:11:18	$v=w	$i=i
loops.tach:16:14	$v=w	$i=i
loops.tach:18:32	$v=w	$i=j
$ rewrite 'let $x = $e;' --where '$x: name ~ ^v_' --list
loops.tach:19:5	$x=v_two	$e=2
$ rewrite 'let $x = $e;' --where '$x: name ~ [a' --list
error rewrite.usage: --where '$x: name ~ RE' takes a regular expression (^ $ . * + ? [a-z] \d \w)
try: tachyonc rewrite 'grow($v, $n)' '$v.reserve($n)' --where '$v: IntVec' --dry-run
[exit 2]
## --subst inside the statements a $s... keeps, with a new name ($x: x,
## or x2 where x is taken): a site still using $i is left.
$ rewrite 'for $i in 0..$v.count { $s... }' 'for $x in $v.data.iter() { $s... }' --subst '$v.data[$i]' '$x' --dry-run
--- a/loops.tach
+++ b/loops.tach
@@ -8,4 +8,4 @@
-    for i in 0..w.count {
-        t += w.data[i] * 2;
-        if w.data[i] > 2 {
-            t += w.data[i];
+    for x2 in w.data.iter() {
+        t += x2 * 2;
+        if x2 > 2 {
+            t += x2;
@@ -18 +18 @@
-    for j in 0..w.count { t -= w.data[j]; }
+    for x2 in w.data.iter() { t -= x2; }
note rewrite.dropped: 1 site is left: the replacement drops $i, which the code it keeps uses; first: loops.tach:16:30
try: tachyonc query show loops.tach:16
$ rewrite 'for $i in 0..$v.count { $s... }' 'for $x in $v.data.iter() { $s... }' --subst '$v.data[$i]' '$x' --list
loops.tach:8:5	$i=i	$v=w	$s...=t += w.data[i] * 2; if w.data[i] > 2 { t += w.data[i]; }
loops.tach:18:5	$i=j	$v=w	$s...=t -= w.data[j];
note rewrite.dropped: 1 site is left: the replacement drops $i, which the code it keeps uses; first: loops.tach:16:30
try: tachyonc query show loops.tach:16
## Layout: a replacement block on one line takes the site's lines; one
## written on lines keeps them, indented as the site.
$ rewrite 'if $c { t += $e; }' 'if $c { t += $e + 0; t -= 0; }' --dry-run
--- a/loops.tach
+++ b/loops.tach
@@ -11 +11,2 @@
-            t += w.data[i];
+            t += w.data[i] + 0;
+            t -= 0;
$ rewrite 'for $i in 0..$v.count { t -= $v.data[$i]; }' "$(cat $T/inputs/tools016_repl.txt)" --dry-run
--- a/loops.tach
+++ b/loops.tach
@@ -18 +18,4 @@
-    for j in 0..w.count { t -= w.data[j]; }
+    for j in 0..w.count {
+        t -= w.data[j];
+        t += 0;
+    }
## Written, then checked; a new name the replacement binds nowhere.
$ rewrite 'for $i in 0..$v.count { $s... }' 'for $x in $v.data.iter() { $s... }' --subst '$v.data[$i]' '$x'
rewrote 2 sites in 1 file	loops.tach	+5 -5 lines
note rewrite.dropped: 1 site is left: the replacement drops $i, which the code it keeps uses; first: loops.tach:16:30
try: tachyonc query show loops.tach:16
$ query show total
// crate::loops::total	loops.tach:5-22	effects: global panic
pub fn total() -> i64 {
    let w = unsafe { V };
    var t = 0;
    for x2 in w.data.iter() {
        t += x2 * 2;
        if x2 > 2 {
            t += x2;
        }
    }
    let x = 1;
    for i in 0..w.count {
        t += w.data[i] + x + i;
    }
    for x2 in w.data.iter() { t -= x2; }
    let v_two = 2;
    let other = 3;
    t + v_two * other
}
$ check
ok: 0 errors in main.tach
$ rewrite 'clamp($a, $b, $c)' 'clamp($a, $b, $d)'
error rewrite.unbound: the replacement's $d is not in the pattern, and the replacement binds no name with it (`for $x in`, `let $x =`)
[exit 2]
