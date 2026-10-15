## tachyonc fix --only alloc016 (0.16) where it cannot pass an allocator
## (tests/refactor/alloc016/): an impl of std's Display, a function used as
## a value, a parameter's default; each is an error naming where it
## allocates, and the rest of the program is threaded (count, main).
$ fix --only alloc016 --dry-run
--- a/main.tach
+++ b/main.tach
@@ -28,2 +28,2 @@
-fn count(n: i64) -> i64 {
-    let v: Vec<i64> = Vec::filled(n, 0);
+fn count(n: i64, gpa: Gpa) -> i64 {
+    let v: Vec<i64> = Vec::filled_in(n, 0, gpa);
@@ -38 +38 @@
-fn main() {
+fn main(gpa: Gpa) {
@@ -42 +42 @@
-    println(count(2));
+    println(count(2, gpa));
error fix.alloc016-manual: the default of parameter 'v' of crate::with allocates at main.tach:34:31, and a default has no allocator: take an Option and make the value in the body
try: tachyonc query show main.tach:34
error fix.alloc016-manual: <crate::Name as Display>::fmt needs an allocator (it allocates at main.tach:12:22), but it implements a trait of std, whose signature is fixed: keep a 'gpa: Gpa' in the value it works on, or pass what it allocates in
try: tachyonc query show main.tach:11
error fix.alloc016-manual: crate::make needs an allocator (it allocates at main.tach:19:23), but it is used as a value (its type would change): keep a 'gpa: Gpa' in the value it works on, or pass what it allocates in
try: tachyonc query show main.tach:18
[exit 1]
$ fix --only nonsense
error fix.usage: --only takes imports, unused, pub, unsafe, tidy-imports, reexports, std015 or alloc016, not 'nonsense'
[exit 2]
