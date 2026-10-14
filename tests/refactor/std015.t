## tachyonc fix --only std015 (tests/refactor/std015/): the calls of
## std's parse_int, Scanner::next_int, read_line and read_stdin, whose
## results are a Result in 0.15, get .ok(), .unwrap_or(false), .unwrap();
## a call in a generic function's instance and through a path too. Left
## as they are: calls already handled as a Result (`.unwrap_or(0)`, `.ok()`,
## a `let` typed Result, a match on Ok/Err) and mine::parse_int, the
## program's own. Only the diff: the errors after the edit depend on
## which std the compiler has (0.14's: the new methods are unknown).
% "$COMPILER" fix --only std015 --dry-run 2>/dev/null | grep -E '^(---|[+][+][+]|@@|[-+])'
--- a/main.tach
+++ b/main.tach
@@ -7 +7 @@
-    parse_int(text)
+    parse_int(text).ok()
@@ -11 +11 @@
-    match parse_int(s) {
+    match parse_int(s).ok() {
@@ -18 +18 @@
-    let input = read_stdin();
+    let input = read_stdin().unwrap();
@@ -21 +21 @@
-    while let Some(v) = sc.next_int() {
+    while let Some(v) = sc.next_int().ok() {
@@ -25 +25 @@
-    while read_line(&line) {
+    while read_line(&line).unwrap_or(false) {
@@ -29 +29 @@
-    let b = parse_int("x").is_none();
+    let b = parse_int("x").ok().is_none();
@@ -35,2 +35,2 @@
-    let h = std::parse_int("8");
-    let k = Scanner::next_int(&sc);
+    let h = std::parse_int("8").ok();
+    let k = Scanner::next_int(&sc).ok();
% "$COMPILER" fix --only std015 --dry-run --in mine.tach
note fix.none: nothing to fix
$ fix --only nonsense
error fix.usage: --only takes imports, unused, pub, unsafe, tidy-imports, reexports or std015, not 'nonsense'
[exit 2]
