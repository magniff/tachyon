## tachyonc edit replace|insert|delete and undo (tests/refactor/edits/).
$ check
## Replacing an item replaces its lines; the comment above it stays when
## the new text has none.
$ edit replace geom::area --dry-run < $T/inputs/area_plain.tach
--- a/geom.tach
+++ b/geom.tach
@@ -10 +10,2 @@
-    p.x * p.y
+    let w = p.x;
+    w * p.y
$ edit replace geom::area < $T/inputs/area_plain.tach
replaced crate::geom::area	geom.tach	+2 -1 lines
% cat geom.tach
// Points.

pub struct Point {
    pub x: i64,
    pub y: i64,
}

// The area of the rectangle from the origin to p.
pub fn area(p: Point) -> i64 {
    let w = p.x;
    w * p.y
}

pub fn scale(p: Point, k: i64) -> Point {
    Point { x: p.x * k, y: p.y * k }
}

impl Point {
    // x + y.
    pub fn sum(self: *Point) -> i64 {
        self.x + self.y
    }
}

pub enum Corner { Low, High }
## The new text starts with a comment: the comment is replaced too.
$ edit replace geom::area < $T/inputs/area_doc.tach
replaced crate::geom::area	geom.tach	+2 -3 lines
% git diff
diff --git a/geom.tach b/geom.tach
index 9d87d0e..3cd33d0 100644
--- a/geom.tach
+++ b/geom.tach
@@ -5,7 +5,7 @@ pub struct Point {
     pub y: i64,
 }
 
-// The area of the rectangle from the origin to p.
+// The area of the rectangle from the origin to p (0.11).
 pub fn area(p: Point) -> i64 {
     p.x * p.y
 }
## A method: text that is not indented is indented like the method.
$ edit replace Point::sum --dry-run < $T/inputs/sum_unindented.tach
--- a/geom.tach
+++ b/geom.tach
@@ -20 +20 @@
-        self.x + self.y
+        self.y + self.x
## The text as `query show` prints it: its header line is dropped.
$ edit replace geom::scale --dry-run < $T/inputs/scale_shown.tach
--- a/geom.tach
+++ b/geom.tach
@@ -14 +14 @@
-    Point { x: p.x * k, y: p.y * k }
+    Point { x: p.x * k, y: p.y * (k + 0) }
## Inserting after an item, before a method.
$ edit insert --after geom::area --dry-run < $T/inputs/perimeter.tach
--- a/geom.tach
+++ b/geom.tach
@@ -12,0 +13,5 @@
+// Twice the sum of its sides.
+pub fn perimeter(p: Point) -> i64 {
+    2 * (p.x + p.y)
+}
+
$ edit insert --before Point::sum --dry-run < $T/inputs/diag.tach
--- a/geom.tach
+++ b/geom.tach
@@ -17,0 +18,4 @@
+    pub fn diag(self: *Point) -> i64 {
+        self.x - self.y
+    }
+
## Deleting: an item with one blank line; a variant of a one-line enum;
## a field (the struct literals need it: refused).
$ edit delete geom::Corner --dry-run
--- a/geom.tach
+++ b/geom.tach
@@ -23,2 +22,0 @@
-
-pub enum Corner { Low, High }
$ edit delete Corner::High --dry-run
--- a/geom.tach
+++ b/geom.tach
@@ -24 +24 @@
-pub enum Corner { Low, High }
+pub enum Corner { Low }
$ edit delete Point.y
main.tach:13:27: error[type error] unknown field 'y' in struct 'Point'
main.tach:14:33: error[type error] unknown field 'y' in struct 'Point'
./geom.tach:9:11: error[type error] struct 'Point' has no field 'y'
./geom.tach:13:25: error[type error] unknown field 'y' in struct 'Point'
./geom.tach:19:18: error[type error] struct 'Point' has no field 'y'
error edit.breaks: 5 new errors; nothing written
try: tachyonc edit delete Point.y --no-check
[exit 1]
## An edit that adds an error writes nothing (--dry-run says so too).
$ edit replace geom::area < $T/inputs/area_bool.tach
main.tach:9:5: error[type error] expected 'i64', got 'bool'
error edit.breaks: 1 new error; nothing written
try: tachyonc edit replace geom::area --no-check
[exit 1]
% git status --short
 M geom.tach
$ edit replace geom::area --dry-run < $T/inputs/area_bool.tach
--- a/geom.tach
+++ b/geom.tach
@@ -9,2 +9,2 @@
-pub fn area(p: Point) -> i64 {
-    p.x * p.y
+pub fn area(p: Point) -> bool {
+    p.x > p.y
main.tach:9:5: error[type error] expected 'i64', got 'bool'
warning edit.breaks: 1 new error (dry run)
[exit 1]
## NAME must name one definition; replace needs its text on stdin.
$ edit delete area
error query.ambiguous: 2 definitions match 'area'; name one
try: tachyonc edit delete crate::geom::area
try: tachyonc edit delete crate::shapes::area
[exit 1]
$ edit delete nowhere
error query.no-match: no definition 'nowhere'
try: tachyonc query items
[exit 1]
$ edit replace geom::area
error edit.no-text: the new text is read from stdin; none was given
try: tachyonc edit replace geom::area < new.tach
[exit 2]
$ edit move geom::area
error edit.usage: unknown command 'move' (patch, replace, insert, delete)
[exit 2]
## Undo, edit by edit; a file changed since is not undone (--force does).
$ undo
undid replaced crate::geom::area	geom.tach	+2 -3 lines
% git diff --stat
 geom.tach | 3 ++-
 1 file changed, 2 insertions(+), 1 deletion(-)
$ undo
undid replaced crate::geom::area	geom.tach	+2 -1 lines
% git status --short
$ undo
error undo.empty: no edit to undo
[exit 1]
$ edit delete shapes::area --no-check
main.tach:15:27: error[type error] no 'area' in module 'shapes'
deleted crate::shapes::area	shapes.tach	+0 -4 lines
warning edit.breaks: 1 new error; written anyway (--no-check)
try: tachyonc check
$ check
main.tach:15:27: error[type error] no 'area' in module 'shapes'
[exit 1]
% printf '// changed\n' >>shapes.tach
$ undo
error undo.changed: 'WORK/shapes.tach' changed since the edit; nothing undone
try: tachyonc undo --force
[exit 1]
$ undo --force
undid deleted crate::shapes::area	shapes.tach	+0 -4 lines
% git status --short
