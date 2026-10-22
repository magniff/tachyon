## volec query conflicts and edit resolve (tests/refactor/conflicts/):
## merge conflicts, read as text; the program does not parse until the
## last one is resolved.
$ query conflicts
main.vl:4-8	use	ours 1 line (HEAD)	theirs 1 line (feature)
shapes.vl:10-17	Shape::grow	ours 1 line (HEAD)	base 1 line (base)	theirs 2 lines (feature)
shapes.vl:22-27	area	ours 1 line (HEAD)	theirs 2 lines (feature)
shapes.vl:30-39	perimeter, scale	ours 4 lines (HEAD)	theirs 3 lines (feature)
$ query conflicts shapes.vl:12 --show
// shapes.vl:10-17	Shape::grow
// ours (HEAD), line 11:
        self.w += by;
// base (base), line 13:
        self.w = self.w + 1;
// theirs (feature), lines 15-16:
        self.w += by;
        self.h += by;
$ query conflicts main.vl shapes.vl:25
main.vl:4-8	use	ours 1 line (HEAD)	theirs 1 line (feature)
shapes.vl:22-27	area	ours 1 line (HEAD)	theirs 2 lines (feature)
## A line no region holds; a region without its end.
$ query conflicts shapes.vl:3
error conflict.none: no conflict region holds shapes.vl:3
try: volec query conflicts shapes.vl
[exit 1]
% printf 'fn f() {\n<<<<<<< HEAD\n}\n' > broken.vl
$ query conflicts broken.vl
error conflict.format: broken.vl:2: a region without its >>>>>>> line; fix the markers by hand
try: volec query text broken.vl:1-7
[exit 1]
% rm broken.vl
## By name: the diff, then the text from stdin.
$ edit resolve area --theirs --dry-run
--- a/shapes.vl
+++ b/shapes.vl
@@ -22,3 +21,0 @@
-<<<<<<< HEAD
-    s.w * s.h
-=======
@@ -27 +23,0 @@
->>>>>>> feature
$ edit resolve area --show < $T/inputs/conflict_area.vl
resolved shapes.vl:22-27 (text)	shapes.vl	+1 -6 lines
// shapes.vl:22
22	    s.h * s.w
note conflict.left: 3 conflict regions left in 2 files
try: volec query conflicts
## Several regions match: each one's command.
$ edit resolve shapes.vl --ours
error conflict.ambiguous: 2 conflict regions match 'shapes.vl': shapes.vl:10, shapes.vl:25; give FILE:LINE, or --all for every one
try: volec edit resolve shapes.vl:10 --ours
try: volec edit resolve shapes.vl:25 --ours
[exit 1]
## The base side: only diff3's regions have one.
$ edit resolve main.vl:5 --base
error conflict.no-base: main.vl:4 has no base side (git writes it with merge.conflictStyle diff3)
try: volec query conflicts main.vl:4 --show
[exit 1]
$ edit resolve Shape::grow --base --show
resolved shapes.vl:10-17 (base)	shapes.vl	+0 -7 lines
// shapes.vl:10
10	        self.w = self.w + 1;
note conflict.left: 2 conflict regions left in 2 files
try: volec query conflicts
$ edit resolve nosuch --ours
error conflict.none: no conflict region in an item 'nosuch'
try: volec query conflicts
[exit 1]
$ edit resolve perimeter --both
resolved shapes.vl:18-27 (both)	shapes.vl	+1 -3 lines
note conflict.left: 1 conflict region left in 1 file
try: volec query conflicts
## The last one: the program is checked.
$ edit resolve main.vl:5 --both
resolved main.vl:4-8 (both)	main.vl	+0 -3 lines
main.vl:5:14: error[type error] 'Shape' is imported twice
main.vl:5:21: error[type error] 'area' is imported twice
warning conflict.check: the resolved program has errors (written; the merge may need more than one side)
try: volec check
$ undo
undid resolved main.vl:4-8 (both)	main.vl	+0 -3 lines
$ edit resolve main.vl:4 < $T/inputs/conflict_use.vl
resolved main.vl:4-8 (text)	main.vl	+1 -5 lines
$ query conflicts
note conflict.none: no conflict markers in the .vl files under .
% cat shapes.vl
// Shapes, merged from two branches.

pub struct Shape {
    pub w: i64,
    pub h: i64,
}

impl Shape {
    pub fn grow(inout self, by: i64) {
        self.w = self.w + 1;
    }
}

pub fn area(s: Shape) -> i64 {
    s.h * s.w
}

// The length around it.
pub fn perimeter(s: Shape) -> i64 {
    2 * (s.w + s.h)
}

pub fn scale(s: Shape, k: i64) -> Shape {
    Shape { w: s.w * k, h: s.h * k }
}
$ check
ok: 0 errors in main.vl
## Undo, resolve by resolve.
$ undo
undid resolved main.vl:4-8 (text)	main.vl	+1 -5 lines
$ undo
undid resolved shapes.vl:18-27 (both)	shapes.vl	+1 -3 lines
% grep -c '^<<<<<<<' main.vl shapes.vl
main.vl:1
shapes.vl:1
