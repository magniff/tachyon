## The tools' cache (0.13; run.sh runs every transcript with a cache and
## without): what changes under it, by the tools or not, is seen.
$ query def f
crate::a::f	a/mod.vl:1:8	fn	pub fn f() -> i64	effects: none
$ query refs f
# a/mod.vl
1:8	def	pub fn f() -> i64 {
# main.vl
4:8	call	twice	a::f() + x
8:14	call	main	twice(a::f()) as i32
$ check
ok: 0 errors in main.vl
## A module's file appears where it is looked for first: another program.
% printf '\npub fn f() -> i64 {\n    2\n}\n' > a.vl
$ query def f
crate::a::f	a.vl:2:8	fn	pub fn f() -> i64	effects: none
$ query refs f
# a.vl
2:8	def	pub fn f() -> i64 {
# main.vl
4:8	call	twice	a::f() + x
8:14	call	main	twice(a::f()) as i32
## The same size, another text.
% printf '\npub fn f() -> i64 {\n    3\n}\n' > a.vl
$ query show f
// crate::a::f	a.vl:2-4	effects: none
pub fn f() -> i64 {
    3
}
## An error: check and the queries count it.
% printf '\npub fn f() -> i64 {\n    true\n}\n' > a.vl
$ check
a.vl:3:5: error[type error] expected 'i64', got 'bool'
[exit 1]
$ query def f
crate::a::f	a.vl:2:8	fn	pub fn f() -> i64
warning query.program-errors: 1 error in the program; results may be incomplete
try: volec --diagnostics=short main.vl -c -o /dev/null
$ check
a.vl:3:5: error[type error] expected 'i64', got 'bool'
[exit 1]
% rm a.vl
$ check
ok: 0 errors in main.vl
$ query show f
// crate::a::f	a/mod.vl:1-3	effects: none
pub fn f() -> i64 {
    1
}
## An edit, then the questions about the edited program.
$ edit patch twice --old 'a::f() + x' --new 'a::f() * x'
patched crate::twice	main.vl	+1 -1 lines
$ query show twice
// crate::twice	main.vl:3-5	effects: none
fn twice(x: i64) -> i64 {
    a::f() * x
}
$ query refs twice
# main.vl
3:4	def	fn twice(x: i64) -> i64 {
8:5	call	main	twice(a::f()) as i32
$ check
ok: 0 errors in main.vl
$ undo
undid patched crate::twice	main.vl	+1 -1 lines
$ query show twice
// crate::twice	main.vl:3-5	effects: none
fn twice(x: i64) -> i64 {
    a::f() + x
}
$ edit replace twice --dry-run < $T/inputs/twice.vl
--- a/main.vl
+++ b/main.vl
@@ -4 +4 @@
-    a::f() + x
+    x + x
$ query callers f
# main.vl
4:8	call	twice	a::f() + x
8:14	call	main	twice(a::f()) as i32
