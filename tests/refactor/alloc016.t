## tachyonc fix --only alloc016 (0.16) where it cannot pass an allocator
## (tests/refactor/alloc016/): an impl of std's Display, a function used as
## a value, a parameter's default, a write of a sealed std type's field;
## each is an error naming where it is, and the rest of the program is
## threaded (count, main; the reads of `v.len` stay: 0.17 reads them as
## `v.len()`).
$ fix --only alloc016 --dry-run
--- a/main.tach
+++ b/main.tach
@@ -28,2 +28,2 @@
-fn count(n: i64) -> i64 {
-    let v: Vec<i64> = Vec::filled(n, 0);
+fn count(n: i64, gpa: Gpa) -> i64 {
+    let v: Vec<i64> = Vec::filled_in(n, 0, gpa);
@@ -43 +43 @@
-fn main() {
+fn main(gpa: Gpa) {
@@ -47 +47 @@
-    println(count(2));
+    println(count(2, gpa));
error fix.alloc016-manual: a write of field 'len' at main.tach:40:7: std's Vec is #[sealed] (0.16): its fields change only through its methods (push, clear, truncate, reserve, ...)
try: tachyonc query show main.tach:40
error fix.alloc016-manual: the default of parameter 'v' of crate::with allocates at main.tach:34:31, and a default has no allocator: take an Option and make the value in the body
try: tachyonc query show main.tach:34
error fix.alloc016-manual: <crate::Name as Display>::fmt needs an allocator (it allocates at main.tach:12:22), but it implements a trait of std, whose signature is fixed: keep a 'gpa: Gpa' in the value it works on, or pass what it allocates in
try: tachyonc query show main.tach:11
error fix.alloc016-manual: crate::make needs an allocator (it allocates at main.tach:19:23), but it is used as a value (its type would change): keep a 'gpa: Gpa' in the value it works on, or pass what it allocates in
try: tachyonc query show main.tach:18
[exit 1]
$ fix --only nonsense
error fix.usage: --only takes imports, unused, pub, unsafe, suggested, tidy-imports, reexports, std015, alloc016, values, conventions or conventions-spelling, not 'nonsense'
[exit 2]
