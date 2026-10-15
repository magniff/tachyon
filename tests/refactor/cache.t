## The tools' cache (0.13; run.sh runs every transcript with a cache and
## without): what changes under it, by the tools or not, is seen.
$ query def f
crate::a::f	a/mod.tach:1:8	fn	pub fn f() -> i64	effects: none
$ query refs f
# a/mod.tach
1:8	def	pub fn f() -> i64 {
# main.tach
4:8	call	twice	a::f() + x
8:14	call	main	twice(a::f()) as i32
$ check
## A module's file appears where it is looked for first: another program.
% printf '\npub fn f() -> i64 {\n    2\n}\n' > a.tach
$ query def f
crate::a::f	a.tach:2:8	fn	pub fn f() -> i64	effects: none
$ query refs f
# a.tach
2:8	def	pub fn f() -> i64 {
# main.tach
4:8	call	twice	a::f() + x
8:14	call	main	twice(a::f()) as i32
## The same size, another text.
% printf '\npub fn f() -> i64 {\n    3\n}\n' > a.tach
$ query show f
// crate::a::f	a.tach:2-4	effects: none
pub fn f() -> i64 {
    3
}
## An error: check and the queries count it.
% printf '\npub fn f() -> i64 {\n    true\n}\n' > a.tach
$ check
./a.tach:3:5: error[type error] expected 'i64', got 'bool'
[exit 1]
$ query def f
crate::a::f	a.tach:2:8	fn	pub fn f() -> i64
warning query.program-errors: 1 error in the program; results may be incomplete
try: tachyonc --diagnostics=short main.tach -c -o /dev/null
$ check
./a.tach:3:5: error[type error] expected 'i64', got 'bool'
[exit 1]
% rm a.tach
$ check
$ query show f
// crate::a::f	a/mod.tach:1-3	effects: none
pub fn f() -> i64 {
    1
}
## An edit, then the questions about the edited program.
$ edit patch twice --old 'a::f() + x' --new 'a::f() * x'
patched crate::twice	main.tach	+1 -1 lines
$ query show twice
// crate::twice	main.tach:3-5	effects: none
fn twice(x: i64) -> i64 {
    a::f() * x
}
$ query refs twice
# main.tach
3:4	def	fn twice(x: i64) -> i64 {
8:5	call	main	twice(a::f()) as i32
$ check
$ undo
undid patched crate::twice	main.tach	+1 -1 lines
$ query show twice
// crate::twice	main.tach:3-5	effects: none
fn twice(x: i64) -> i64 {
    a::f() + x
}
$ edit replace twice --dry-run < $T/inputs/twice.tach
--- a/main.tach
+++ b/main.tach
@@ -4 +4 @@
-    a::f() + x
+    x + x
$ query callers f
# main.tach
4:8	call	twice	a::f() + x
8:14	call	main	twice(a::f()) as i32
