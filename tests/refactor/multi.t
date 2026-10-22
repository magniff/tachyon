## Several items in one edit (0.15): edit patch with targets, edit apply,
## and what edit.breaks says when an edit breaks other items.
## edit patch: --in NAME starts the pairs of another target.
$ edit patch area --old 'r.w * r.h' --new 'r.h * r.w' --in kind --old 'r.w == r.h' --new 'r.h == r.w' --dry-run
--- a/shapes.vl
+++ b/shapes.vl
@@ -15 +15 @@
-    r.w * r.h
+    r.h * r.w
@@ -19 +19 @@
-    if r.w == r.h { Kind::Square } else { Kind::Wide }
+    if r.h == r.w { Kind::Square } else { Kind::Wide }
## `@@ NAME` blocks in --pairs FILE: several items, several files, one edit.
$ edit patch --pairs $T/inputs/multi_targets.pairs --show
patched crate::shapes::area, crate::main	2 files	+2 -2 lines
// main.vl:16
16	    if area(r) + describe(kind(r)) == 26 + 0 { 0 } else { 1 }
// shapes.vl:15
15	    r.w * r.h + 0
$ undo
undid patched crate::shapes::area, crate::main	2 files	+2 -2 lines
## A pair that fails names its target; the try: file keeps the targets.
$ edit patch --in area --old 'r.w * r.x' --new 'x' --in main --old '== 26' --new '== 27'
error patch.no-match: OLD 1 is not in crate::shapes::area; nearest, line 15: r.w * r.h
try: volec edit patch --pairs .git/vole-edits/try-1.pairs
[exit 1]
% cat .git/vole-edits/try-1.pairs
@@ area
<<<<<<< OLD
r.w * r.
=======
x
>>>>>>> NEW
@@ main
<<<<<<< OLD
== 26
=======
== 27
>>>>>>> NEW
## Pairs with no target.
$ edit patch --old 'a' --new 'b'
error edit.usage: a TARGET is needed
try: volec edit patch NAME --old OLD --new NEW
[exit 2]
## A signature changed with its one caller: one edit, no error.
$ edit patch --pairs $T/inputs/multi_bool.pairs
patched crate::shapes::area, crate::main	2 files	+3 -3 lines
$ undo
undid patched crate::shapes::area, crate::main	2 files	+3 -3 lines
## edit apply: the blocks of query show, changed; a new item by its
## path; `new after NAME`.
$ edit apply $T/inputs/multi_apply.items --show
applied 4 blocks: replaced crate::shapes::area; added crate::shapes::perimeter; inserted after crate::describe; replaced crate::main	2 files	+13 -5 lines
// main.vl:4
4	use shapes::{Kind, Rect, area, kind, perimeter, scale};
// main.vl:13-16
13	fn twice(n: i64) -> i64 {
14	    n + n
15	}
16	
// main.vl:18-19
18	    let r = scale(Rect { w: 2, h: 3 }, 2);
19	    if area(r) + describe(kind(r)) + twice(perimeter(r)) == 66 { 0 } else { 1 }
// shapes.vl:13
13	// The area of r, in square units.
// shapes.vl:29-33
29	}
30	
31	// The perimeter of r.
32	pub fn perimeter(r: Rect) -> i64 {
33	    2 * (r.w + r.h)
note edit.imports: added the imports the new text needs (fix --only imports)
$ check
ok: 0 errors in main.vl
$ undo
undid applied 4 blocks: replaced crate::shapes::area; added crate::shapes::perimeter; inserted after crate::describe; replaced crate::main	2 files	+13 -5 lines
## `new in MODULE`, `new before NAME`, `delete NAME`; from stdin.
$ edit apply $T/inputs/multi_end.items --dry-run
--- a/shapes.vl
+++ b/shapes.vl
@@ -12,0 +13,5 @@
+// A square of side n.
+pub fn square(n: i64) -> Rect {
+    Rect { w: n, h: n }
+}
+
@@ -26,4 +31 @@
-// Not used.
-pub fn spare() -> i64 {
-    0
-}
+pub const UNIT: i64 = 1;
$ edit apply < $T/inputs/multi_end.items
applied 3 blocks: inserted in crate::shapes; inserted before crate::shapes::area; deleted crate::shapes::spare	shapes.vl	+6 -4 lines
$ undo
undid applied 3 blocks: inserted in crate::shapes; inserted before crate::shapes::area; deleted crate::shapes::spare	shapes.vl	+6 -4 lines
## Two blocks for one item; not blocks.
$ edit apply $T/inputs/multi_twice.items
error edit.overlap: crate::shapes::area is changed twice in one edit; give each item one block
[exit 1]
% cp $T/inputs/multi_format.items $T/inputs/multi_empty.items .
$ edit apply multi_format.items
error edit.format: multi_format.items line 1: text before the first header; a block starts with `@@ NAME`, `@@ new after NAME`, `@@ new in MODULE`, `@@ delete NAME` or a header of query show
try: volec query show NAME
[exit 2]
$ edit apply multi_empty.items
error edit.format: multi_empty.items line 1: the block has no text (`@@ delete NAME` deletes an item); a block starts with `@@ NAME`, `@@ new after NAME`, `@@ new in MODULE`, `@@ delete NAME` or a header of query show
try: volec query show NAME
[exit 2]
% rm multi_format.items multi_empty.items
## edit.breaks: the errors tagged with their items; the refactoring that
## fits a changed shape; the items to change in the same edit.
$ edit patch scale --old 'k: i64' --new 'k: i64, m: i64'
main.vl:15:13: error[type error] function 'shapes::scale' expects 3 arguments, got 2 | help: its signature: `fn scale(r: Rect, k: i64, m: i64) -> Rect` (shapes.vl:22) | try: scale(Rect { w: 2, h: 3 }, k, VALUE)  [in crate::main]
error edit.breaks: 1 new error (1 in crate::main, which the edit does not change); nothing written
note edit.refactor: the uses of crate::shapes::scale no longer fit its new shape: a refactoring changes them with it (VALUE, EXPR: to fill in), then the rest of the edit
try: volec refactor signature crate::shapes::scale --add 'm: i64 = VALUE'
note edit.together: change crate::main in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: volec query show crate::main
try: volec edit patch scale --old 'k: i64' --new 'k: i64, m: i64' --no-check
[exit 1]
$ edit patch Rect --old 'h: i64,' --new 'height: i64,'
main.vl:15:32: error[type error] unknown field 'h' in struct 'Rect'  [in crate::main]
shapes.vl:15:11: error[type error] struct 'Rect' has no field 'h'  [in crate::shapes::area]
shapes.vl:19:15: error[type error] struct 'Rect' has no field 'h'  [in crate::shapes::kind]
shapes.vl:23:24: error[type error] unknown field 'h' in struct 'Rect'  [in crate::shapes::scale]
error edit.breaks: 4 new errors (4 in crate::main, crate::shapes::area, crate::shapes::kind and 1 more, which the edit does not change); nothing written
note edit.refactor: the uses of crate::shapes::Rect no longer fit its new shape: a refactoring changes them with it, then the rest of the edit
try: volec refactor field crate::shapes::Rect --rename h height
note edit.together: change crate::main, crate::shapes::area, crate::shapes::kind and 1 more in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: volec query show crate::main crate::shapes::area crate::shapes::kind crate::shapes::scale
try: volec edit patch Rect --old 'h: i64,' --new 'height: i64,' --no-check
[exit 1]
$ edit patch Kind < $T/inputs/multi_tall.pairs
main.vl:7:5: error[type error] non-exhaustive match: 'Kind::Tall' is not covered | help: add an arm for it (try:), or a wildcard arm '_ =>' | try: Kind::Tall => VALUE,  [in crate::describe]
error edit.breaks: 1 new error (1 in crate::describe, which the edit does not change); nothing written
note edit.refactor: the uses of crate::shapes::Kind no longer fit its new shape: a refactoring changes them with it (VALUE, EXPR: to fill in), then the rest of the edit
try: volec refactor variant crate::shapes::Kind --add Tall --arm 'EXPR'
note edit.together: change crate::describe in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: volec query show crate::describe
try: volec edit patch Kind --no-check
[exit 1]
$ edit replace area < $T/inputs/multi_renamed.vl
main.vl:4:26: error[type error] unresolved import 'shapes::area'
error edit.breaks: 1 new error; nothing written
note edit.refactor: the uses of crate::shapes::area no longer fit its new shape: a refactoring changes them with it, then the rest of the edit
try: volec refactor rename crate::shapes::area surface
try: volec edit replace area --no-check
[exit 1]
$ edit patch area < $T/inputs/multi_area_bool.pairs
main.vl:16:18: error[type error] expected 'bool', got 'i64' | help: a condition is a bool: compare (`x != 0`); bitwise not is `~x` | try: describe(kind(r)) != 0 | try: volec fix --suggested main.vl  [in crate::main]
error edit.breaks: 1 new error (1 in crate::main, which the edit does not change); nothing written
note edit.together: change crate::main in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: volec query show crate::main
try: volec edit patch area --no-check
[exit 1]
$ edit patch scale --old 'scale(r: Rect, k: i64)' --new 'scale(r: Rect, f: i64)'
shapes.vl:23:21: error[type error] undefined variable 'k'  [edited: crate::shapes::scale]
error edit.breaks: 1 new error; nothing written
note edit.refactor: the uses of crate::shapes::scale no longer fit its new shape: a refactoring changes them with it, then the rest of the edit
try: volec refactor signature crate::shapes::scale --rename-param k f
try: volec edit patch scale --old 'scale(r: Rect, k: i64)' --new 'scale(r: Rect, f: i64)' --no-check
[exit 1]
$ edit patch scale --old 'scale(r: Rect, k: i64)' --new 'scale(k: i64, r: Rect)'
main.vl:15:19: error[type error] expected 'i64', got 'Rect'  [in crate::main]
error edit.breaks: 1 new error (1 in crate::main, which the edit does not change); nothing written
note edit.refactor: the uses of crate::shapes::scale no longer fit its new shape: a refactoring changes them with it, then the rest of the edit
try: volec refactor signature crate::shapes::scale --reorder k,r
note edit.together: change crate::main in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: volec query show crate::main
try: volec edit patch scale --old 'scale(r: Rect, k: i64)' --new 'scale(k: i64, r: Rect)' --no-check
[exit 1]
$ edit patch scale --old 'k: i64' --new 'k: i32'
main.vl:15:40: error[type error] expected 'i32', got 'i64' | help: only widening is implicit: convert explicitly | try: k as i32 | try: volec fix --suggested main.vl  [in crate::main]
error edit.breaks: 1 new error (1 in crate::main, which the edit does not change); nothing written
note edit.refactor: the uses of crate::shapes::scale no longer fit its new shape: a refactoring changes them with it, then the rest of the edit
try: volec refactor signature crate::shapes::scale --type k i32 --default '$k as i32'
note edit.together: change crate::main in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: volec query show crate::main
try: volec edit patch scale --old 'k: i64' --new 'k: i32' --no-check
[exit 1]
$ edit patch scale --old 'k: i64' --new 'k: i32' --old 'r.w * k, h: r.h * k' --new 'r.w * k as i64, h: r.h * k as i64'
main.vl:15:40: error[type error] expected 'i32', got 'i64' | help: only widening is implicit: convert explicitly | try: k as i32 | try: volec fix --suggested main.vl  [in crate::main]
error edit.breaks: 1 new error (1 in crate::main, which the edit does not change); nothing written
note edit.refactor: the uses of crate::shapes::scale no longer fit its new shape: a refactoring changes them with it, then the rest of the edit
try: volec refactor signature crate::shapes::scale --type k i32 --default '$k as i32'
note edit.together: change crate::main in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: volec query show crate::main
try: volec edit patch scale --old 'k: i64' --new 'k: i32' --old 'r.w * k, h: r.h * k' --new 'r.w * k as i64, h: r.h * k as i64' --no-check
[exit 1]
% git status --short
