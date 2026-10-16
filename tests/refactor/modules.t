## The module refactorings (tests/refactor/modules/): rename, move,
## new-module, move-module, split; each atomic, journaled for undo, with
## --dry-run.
$ check
ok: 0 errors in main.tach
$ main.tach -o prog
ok: built prog
% ./prog; echo "exit $?"
exit 0
## ---- rename ----
## An item: its definition, its imports, its uses, and its backquoted
## mention in a comment.
$ refactor rename twice repeat --dry-run
--- a/main.tach
+++ b/main.tach
@@ -7 +7 @@
-use util::twice;
+use util::repeat;
@@ -11 +11 @@
-    let n = twice(area(p)) + shapes::perimeter(p) + util::LIMIT + p.sum();
+    let n = repeat(area(p)) + shapes::perimeter(p) + util::LIMIT + p.sum();
--- a/geom.tach
+++ b/geom.tach
@@ -3 +3 @@
-use crate::util::twice;
+use crate::util::repeat;
@@ -35 +35 @@
-    scale(p, half(twice(2)))
+    scale(p, half(repeat(2)))
--- a/util.tach
+++ b/util.tach
@@ -3 +3 @@
-// How many times `twice` ran.
+// How many times `repeat` ran.
@@ -6 +6 @@
-pub fn twice(x: i64) -> i64 {
+pub fn repeat(x: i64) -> i64 {
$ refactor rename geom::area surface
renamed crate::geom::area to surface	3 files	+5 -5 lines
% git diff --stat
 geom.tach   | 2 +-
 main.tach   | 4 ++--
 shapes.tach | 4 ++--
 3 files changed, 5 insertions(+), 5 deletions(-)
$ undo
undid renamed crate::geom::area to surface	3 files	+5 -5 lines
## A field, a method.
$ refactor rename Point.x left --dry-run
--- a/main.tach
+++ b/main.tach
@@ -10 +10 @@
-    let p = Point { x: 2, y: 3 };
+    let p = Point { left: 2, y: 3 };
--- a/geom.tach
+++ b/geom.tach
@@ -6 +6 @@
-    pub x: i64,
+    pub left: i64,
@@ -13 +13 @@
-        self.x + self.y
+        self.left + self.y
@@ -19 +19 @@
-    p.x * p.y
+    p.left * p.y
@@ -26 +26 @@
-    Point { x: p.x * k, y: p.y * k }
+    Point { left: p.left * k, y: p.y * k }
--- a/shapes.tach
+++ b/shapes.tach
@@ -7 +7 @@
-    scale() * (p.x + p.y) + area(q) - area(q)
+    scale() * (p.left + p.y) + area(q) - area(q)
$ refactor rename Point::sum total --dry-run
--- a/main.tach
+++ b/main.tach
@@ -11 +11 @@
-    let n = twice(area(p)) + shapes::perimeter(p) + util::LIMIT + p.sum();
+    let n = twice(area(p)) + shapes::perimeter(p) + util::LIMIT + p.total();
--- a/geom.tach
+++ b/geom.tach
@@ -12 +12 @@
-    pub fn sum(self: *Point) -> i64 {
+    pub fn total(self: *Point) -> i64 {
## A module: its file is renamed too.
$ refactor rename crate::util tools
renamed crate::util to tools	3 files	+4 -4 lines
% git status --short
 M geom.tach
 M main.tach
 D util.tach
?? prog
?? tools.tach
$ undo
undid renamed crate::util to tools	3 files	+4 -4 lines
% git status --short
?? prog
## Collisions: the new name is taken where the item is named (geom
## imports twice, and has a double).
$ refactor rename twice double
error refactor.collision: 'double' is already a name in crate::geom (fn crate::geom::double); nothing written
try: tachyonc query def crate::geom::double
[exit 1]
$ refactor rename geom::area scale
error refactor.collision: 'scale' is already a name in crate::geom (fn crate::geom::scale); nothing written
try: tachyonc query def crate::geom::scale
[exit 1]
## An edit that breaks the program is refused, nothing written (the
## local p would be called).
$ refactor rename geom::area p
main.tach:11:19: error[type error] cannot call non-function type 'Point'  [edited: crate::main]
shapes.tach:7:29: error[type error] cannot call non-function type 'Point'  [edited: crate::shapes::perimeter]
error edit.breaks: 2 new errors; nothing written
try: tachyonc refactor rename geom::area p --no-check
[exit 1]
% git status --short
?? prog
$ refactor rename geom::area 2x
error refactor.usage: the new name must be an identifier (not a keyword)
[exit 2]
## ---- move ----
## One item: the imports of the modules naming it are fixed, the private
## helper it uses becomes pub, the banner of its group stays.
$ refactor move geom::double --to crate::util --dry-run
--- a/geom.tach
+++ b/geom.tach
@@ -3,2 +2,0 @@
-use crate::util::twice;
-
@@ -30 +28 @@
-fn half(x: i64) -> i64 {
+pub fn half(x: i64) -> i64 {
@@ -32,4 +29,0 @@
-}
-
-pub fn double(p: Point) -> Point {
-    scale(p, half(twice(2)))
--- a/shapes.tach
+++ b/shapes.tach
@@ -3 +3,2 @@
-use crate::geom::{Point, area, double};
+use crate::geom::{Point, area};
+use crate::util::double;
--- a/util.tach
+++ b/util.tach
@@ -0,0 +1,2 @@
+use crate::geom::{Point, half, scale};
+
@@ -8,0 +11,4 @@
+}
+
+pub fn double(p: Point) -> Point {
+    scale(p, half(twice(2)))
$ refactor move geom::double crate::util
moved crate::geom::double to crate::util	3 files	+9 -8 lines
% cat util.tach
use crate::geom::{Point, half, scale};

pub const LIMIT: i64 = 100;

// How many times `twice` ran.
pub static mut COUNTER: i64 = 0;

pub fn twice(x: i64) -> i64 {
    unsafe { COUNTER += 1; }
    x * 2
}

pub fn double(p: Point) -> Point {
    scale(p, half(twice(2)))
}
$ main.tach -o prog
ok: built prog
% ./prog; echo "exit $?"
exit 0
$ undo
undid moved crate::geom::double to crate::util	3 files	+9 -8 lines
## A group of items with its banner; geom's import of twice is no longer
## needed there.
$ refactor move geom::scale geom::half geom::double --to crate::util
moved 3 items to crate::util	3 files	+20 -19 lines
% cat geom.tach
// Points and their areas.

pub struct Point {
    pub x: i64,
    pub y: i64,
}

impl Point {
    // x + y.
    pub fn sum(self: *Point) -> i64 {
        self.x + self.y
    }
}

// The area of the rectangle from the origin to p.
pub fn area(p: Point) -> i64 {
    p.x * p.y
}
% cat util.tach
use crate::geom::Point;

pub const LIMIT: i64 = 100;

// How many times `twice` ran.
pub static mut COUNTER: i64 = 0;

pub fn twice(x: i64) -> i64 {
    unsafe { COUNTER += 1; }
    x * 2
}

// ---- Scaling ----

// p, k times larger.
pub fn scale(p: Point, k: i64) -> Point {
    Point { x: p.x * k, y: p.y * k }
}

// Half of x.
fn half(x: i64) -> i64 {
    x / 2
}

pub fn double(p: Point) -> Point {
    scale(p, half(twice(2)))
}
$ undo
undid moved 3 items to crate::util	3 files	+20 -19 lines
## An item used in three modules, with its impl block: main's and shapes'
## imports, geom's new import.
$ refactor move geom::Point --to crate::shapes
moved crate::geom::Point to crate::shapes	3 files	+16 -14 lines
% git diff
diff --git a/geom.tach b/geom.tach
index bf000c1..872f916 100644
--- a/geom.tach
+++ b/geom.tach
@@ -1,19 +1,8 @@
 // Points and their areas.
 
+use crate::shapes::Point;
 use crate::util::twice;
 
-pub struct Point {
-    pub x: i64,
-    pub y: i64,
-}
-
-impl Point {
-    // x + y.
-    pub fn sum(self: *Point) -> i64 {
-        self.x + self.y
-    }
-}
-
 // The area of the rectangle from the origin to p.
 pub fn area(p: Point) -> i64 {
     p.x * p.y
diff --git a/main.tach b/main.tach
index 620be80..2ddb6f5 100644
--- a/main.tach
+++ b/main.tach
@@ -3,7 +3,8 @@ mod geom;
 mod shapes;
 mod util;
 
-use geom::{Point, area};
+use geom::area;
+use shapes::Point;
 use util::twice;
 
 fn main() -> i32 {
diff --git a/shapes.tach b/shapes.tach
index 0c40caf..2869d54 100644
--- a/shapes.tach
+++ b/shapes.tach
@@ -1,6 +1,6 @@
 // Shapes made of points.
 
-use crate::geom::{Point, area, double};
+use crate::geom::{area, double};
 
 pub fn perimeter(p: Point) -> i64 {
     let q = double(p);
@@ -11,3 +11,15 @@ pub fn perimeter(p: Point) -> i64 {
 fn scale() -> i64 {
     2
 }
+
+pub struct Point {
+    pub x: i64,
+    pub y: i64,
+}
+
+impl Point {
+    // x + y.
+    pub fn sum(self: *Point) -> i64 {
+        self.x + self.y
+    }
+}
$ main.tach -o prog
ok: built prog
% ./prog; echo "exit $?"
exit 0
$ undo
undid moved crate::geom::Point to crate::shapes	3 files	+16 -14 lines
## A static (and its mention).
$ refactor move util::COUNTER --to crate::geom --dry-run
--- a/geom.tach
+++ b/geom.tach
@@ -36,0 +37,3 @@
+
+// How many times `twice` ran.
+pub static mut COUNTER: i64 = 0;
--- a/util.tach
+++ b/util.tach
@@ -1 +1 @@
-pub const LIMIT: i64 = 100;
+use crate::geom::COUNTER;
@@ -3,2 +3 @@
-// How many times `twice` ran.
-pub static mut COUNTER: i64 = 0;
+pub const LIMIT: i64 = 100;
## An item imported alone (`use p::twice;`): the `use` lines get its new
## path.
$ refactor move util::twice --to crate::shapes --dry-run
--- a/main.tach
+++ b/main.tach
@@ -7 +7 @@
-use util::twice;
+use shapes::twice;
--- a/geom.tach
+++ b/geom.tach
@@ -3 +3 @@
-use crate::util::twice;
+use crate::shapes::twice;
--- a/shapes.tach
+++ b/shapes.tach
@@ -3,0 +4 @@
+use crate::util::COUNTER;
@@ -12,0 +14,5 @@
+}
+
+pub fn twice(x: i64) -> i64 {
+    unsafe { COUNTER += 1; }
+    x * 2
--- a/util.tach
+++ b/util.tach
@@ -5,5 +4,0 @@
-
-pub fn twice(x: i64) -> i64 {
-    unsafe { COUNTER += 1; }
-    x * 2
-}
## Refused: the name is taken there; a method; no such module.
$ refactor move geom::scale --to crate::shapes
error refactor.collision: 'scale' is already a name in crate::shapes (fn crate::shapes::scale); nothing written
try: tachyonc query def crate::shapes::scale
[exit 1]
$ refactor move Point::sum --to crate::util
error refactor.not-movable: crate::geom::Point::sum is a method: it moves with its type's impl block
[exit 1]
## (0.17) A module that does not exist is made for the move, in the same
## edit.
$ refactor move geom::area --to crate::nowhere --dry-run
made module crate::nowhere	2 files	+1 -0 lines
moved crate::geom::area to crate::nowhere	4 files	+10 -7 lines
--- a/main.tach
+++ b/main.tach
@@ -4,0 +5 @@
+mod nowhere;
@@ -6 +7,2 @@
-use geom::{Point, area};
+use geom::Point;
+use nowhere::area;
--- a/geom.tach
+++ b/geom.tach
@@ -17,5 +16,0 @@
-// The area of the rectangle from the origin to p.
-pub fn area(p: Point) -> i64 {
-    p.x * p.y
-}
-
--- a/shapes.tach
+++ b/shapes.tach
@@ -3 +3,2 @@
-use crate::geom::{Point, area, double};
+use crate::geom::{Point, double};
+use crate::nowhere::area;
--- a/nowhere.tach
+++ b/nowhere.tach
@@ -0,0 +1,6 @@
+use crate::geom::Point;
+
+// The area of the rectangle from the origin to p.
+pub fn area(p: Point) -> i64 {
+    p.x * p.y
+}
note refactor.made-module: there was no module crate::nowhere; it was made for the move (refactor new-module)
$ refactor move geom::area
error refactor.usage: move takes PATH... and the MODULE (`--to MODULE`)
try: tachyonc refactor move crate::m::item --to crate::other
[exit 2]
% git status --short
?? prog
## ---- new-module, move-module ----
## A module of its parent's directory; a file module that gains a child
## becomes a dir module.
$ refactor new-module crate::geom::solid --dry-run
--- a/geom/solid.tach
+++ b/geom/solid.tach
diff --git a/geom.tach b/geom/mod.tach
rename from geom.tach
rename to geom/mod.tach
--- a/geom.tach
+++ b/geom/mod.tach
@@ -2,0 +3,2 @@
+mod solid;
+
$ refactor new-module crate::geom::solid --dir
made module crate::geom::solid	2 files	+2 -0 lines
% find . -name '*.tach' | sort
./geom/mod.tach
./geom/solid/mod.tach
./main.tach
./shapes.tach
./util.tach
$ refactor new-module crate::geom::area
error refactor.collision: 'area' is already a name in crate::geom (fn crate::geom::area); nothing written
try: tachyonc query def crate::geom::area
[exit 1]
$ refactor new-module crate::geom::solid
error refactor.exists: module crate::geom::solid exists
try: tachyonc query items crate::geom::solid
[exit 1]
$ undo
undid made module crate::geom::solid	2 files	+2 -0 lines
## A module moved under another (made on the way), and back.
$ refactor move-module crate::shapes crate::figures::shapes
moved module crate::shapes to crate::figures::shapes	3 files	+3 -2 lines
% find . -name '*.tach' | sort
./figures/mod.tach
./figures/shapes.tach
./geom.tach
./main.tach
./util.tach
% cat figures/mod.tach
pub mod shapes;
% git diff main.tach
diff --git a/main.tach b/main.tach
index 620be80..b915abc 100644
--- a/main.tach
+++ b/main.tach
@@ -1,13 +1,13 @@
 // A program of four modules to reorganize (tests/refactor/modules.t).
 mod geom;
-mod shapes;
 mod util;
+mod figures;
 
 use geom::{Point, area};
 use util::twice;
 
 fn main() -> i32 {
     let p = Point { x: 2, y: 3 };
-    let n = twice(area(p)) + shapes::perimeter(p) + util::LIMIT + p.sum();
+    let n = twice(area(p)) + crate::figures::shapes::perimeter(p) + util::LIMIT + p.sum();
     if n == 127 { 0 } else { 1 }
 }
$ main.tach -o prog
ok: built prog
% ./prog; echo "exit $?"
exit 0
$ refactor move-module crate::figures::shapes crate::shapes
moved module crate::figures::shapes to crate::shapes	3 files	+2 -2 lines
% find . -name '*.tach' | sort
./figures/mod.tach
./geom.tach
./main.tach
./shapes.tach
./util.tach
$ undo
undid moved module crate::figures::shapes to crate::shapes	3 files	+2 -2 lines
$ undo
undid moved module crate::shapes to crate::figures::shapes	3 files	+3 -2 lines
% git status --short
?? prog
## ---- split ----
## Into a child module: the module becomes a dir module.
$ refactor split crate::geom --into crate::geom::scaling --items scale,half,double
split crate::geom: 3 items into crate::geom::scaling	3 files	+21 -18 lines
% find . -name '*.tach' | sort
./geom/mod.tach
./geom/scaling.tach
./main.tach
./shapes.tach
./util.tach
% cat geom/mod.tach
// Points and their areas.

pub mod scaling;

pub struct Point {
    pub x: i64,
    pub y: i64,
}

impl Point {
    // x + y.
    pub fn sum(self: *Point) -> i64 {
        self.x + self.y
    }
}

// The area of the rectangle from the origin to p.
pub fn area(p: Point) -> i64 {
    p.x * p.y
}
% cat geom/scaling.tach
// Scaling

use crate::geom::Point;
use crate::util::twice;

// p, k times larger.
pub fn scale(p: Point, k: i64) -> Point {
    Point { x: p.x * k, y: p.y * k }
}

// Half of x.
fn half(x: i64) -> i64 {
    x / 2
}

pub fn double(p: Point) -> Point {
    scale(p, half(twice(2)))
}
% git diff shapes.tach
diff --git a/shapes.tach b/shapes.tach
index 0c40caf..df89998 100644
--- a/shapes.tach
+++ b/shapes.tach
@@ -1,6 +1,7 @@
 // Shapes made of points.
 
-use crate::geom::{Point, area, double};
+use crate::geom::{Point, area};
+use crate::geom::scaling::double;
 
 pub fn perimeter(p: Point) -> i64 {
     let q = double(p);
$ main.tach -o prog
ok: built prog
% ./prog; echo "exit $?"
exit 0
$ undo
undid split crate::geom: 3 items into crate::geom::scaling	3 files	+21 -18 lines
% git status --short
?? prog
## The plan of a split into parts of at most 20 lines, and the same made
## in one edit.
$ refactor split crate::geom --plan --max-lines 20
# crate::geom	36 lines	3 parts of at most 20 lines
# stays in crate::geom: the part most used from other modules
# point: type Point: 1 of 2 items, 4 of 8 lines
tachyonc refactor split crate::geom --into crate::geom::point --items area,half
# scaling: banner '// ---- Scaling ----': 2 of 2 items, 7 of 7 lines
tachyonc refactor split crate::geom --into crate::geom::scaling --items scale,double
note refactor.plan: the same in one edit: --auto (other names: --names a,b)
try: tachyonc refactor split crate::geom --auto --max-lines 20
$ refactor split crate::geom --auto --max-lines 20
split crate::geom into 2 modules	5 files	+32 -24 lines
% find . -name '*.tach' | sort
./geom/mod.tach
./geom/point.tach
./geom/scaling.tach
./main.tach
./shapes.tach
./util.tach
$ main.tach -o prog
ok: built prog
% ./prog; echo "exit $?"
exit 0
$ undo
undid split crate::geom into 2 modules	5 files	+32 -24 lines
% git status --short
?? prog
$ refactor split crate::util --plan
note refactor.fits: crate::util has 9 lines (at most 1000); nothing to split
$ refactor split crate::geom
error refactor.usage: split takes MODULE and --into NEWMOD --items a,b,c, or --plan, or --auto
try: tachyonc refactor split crate::m --plan
[exit 2]
## ---- in a script ----
## File moves and other edits, checked once, written as one edit; one
## undo takes all back.
$ refactor --script steps.txt --dry-run
moved module crate::shapes to crate::figures::shapes	3 files	+3 -2 lines
rewrote 1 site in 1 file	figures/shapes.tach	+1 -1 lines
split crate::geom: 3 items into crate::geom::scaling	3 files	+21 -18 lines
--- a/main.tach
+++ b/main.tach
@@ -3 +2,0 @@
-mod shapes;
@@ -4,0 +4 @@
+mod figures;
@@ -11 +11 @@
-    let n = twice(area(p)) + shapes::perimeter(p) + util::LIMIT + p.sum();
+    let n = twice(area(p)) + crate::figures::shapes::perimeter(p) + util::LIMIT + p.sum();
--- a/figures/mod.tach
+++ b/figures/mod.tach
@@ -0,0 +1 @@
+pub mod shapes;
--- a/figures/shapes.tach
+++ b/figures/shapes.tach
@@ -0,0 +1,14 @@
+// Shapes made of points.
+
+use crate::geom::{Point, area};
+use crate::geom::scaling::double;
+
+pub fn perimeter(p: Point) -> i64 {
+    let q = double(p);
+    (p.x + p.y) * scale() + area(q) - area(q)
+}
+
+// How many times a side counts.
+fn scale() -> i64 {
+    2
+}
--- a/geom/scaling.tach
+++ b/geom/scaling.tach
@@ -0,0 +1,18 @@
+// Scaling
+
+use crate::geom::Point;
+use crate::util::twice;
+
+// p, k times larger.
+pub fn scale(p: Point, k: i64) -> Point {
+    Point { x: p.x * k, y: p.y * k }
+}
+
+// Half of x.
+fn half(x: i64) -> i64 {
+    x / 2
+}
+
+pub fn double(p: Point) -> Point {
+    scale(p, half(twice(2)))
+}
--- a/geom/mod.tach
+++ b/geom/mod.tach
@@ -0,0 +1,20 @@
+// Points and their areas.
+
+pub mod scaling;
+
+pub struct Point {
+    pub x: i64,
+    pub y: i64,
+}
+
+impl Point {
+    // x + y.
+    pub fn sum(self: *Point) -> i64 {
+        self.x + self.y
+    }
+}
+
+// The area of the rectangle from the origin to p.
+pub fn area(p: Point) -> i64 {
+    p.x * p.y
+}
--- a/shapes.tach
+++ b/shapes.tach
@@ -1,13 +0,0 @@
-// Shapes made of points.
-
-use crate::geom::{Point, area, double};
-
-pub fn perimeter(p: Point) -> i64 {
-    let q = double(p);
-    scale() * (p.x + p.y) + area(q) - area(q)
-}
-
-// How many times a side counts.
-fn scale() -> i64 {
-    2
-}
--- a/geom.tach
+++ b/geom.tach
@@ -1,36 +0,0 @@
-// Points and their areas.
-
-use crate::util::twice;
-
-pub struct Point {
-    pub x: i64,
-    pub y: i64,
-}
-
-impl Point {
-    // x + y.
-    pub fn sum(self: *Point) -> i64 {
-        self.x + self.y
-    }
-}
-
-// The area of the rectangle from the origin to p.
-pub fn area(p: Point) -> i64 {
-    p.x * p.y
-}
-
-// ---- Scaling ----
-
-// p, k times larger.
-pub fn scale(p: Point, k: i64) -> Point {
-    Point { x: p.x * k, y: p.y * k }
-}
-
-// Half of x.
-fn half(x: i64) -> i64 {
-    x / 2
-}
-
-pub fn double(p: Point) -> Point {
-    scale(p, half(twice(2)))
-}
$ refactor --script steps.txt
moved module crate::shapes to crate::figures::shapes	3 files	+3 -2 lines
rewrote 1 site in 1 file	figures/shapes.tach	+1 -1 lines
split crate::geom: 3 items into crate::geom::scaling	3 files	+21 -18 lines
script steps.txt: 3 commands	7 files	+55 -51 lines
% find . -name '*.tach' | sort
./figures/mod.tach
./figures/shapes.tach
./geom/mod.tach
./geom/scaling.tach
./main.tach
./util.tach
% git diff main.tach
diff --git a/main.tach b/main.tach
index 620be80..b915abc 100644
--- a/main.tach
+++ b/main.tach
@@ -1,13 +1,13 @@
 // A program of four modules to reorganize (tests/refactor/modules.t).
 mod geom;
-mod shapes;
 mod util;
+mod figures;
 
 use geom::{Point, area};
 use util::twice;
 
 fn main() -> i32 {
     let p = Point { x: 2, y: 3 };
-    let n = twice(area(p)) + shapes::perimeter(p) + util::LIMIT + p.sum();
+    let n = twice(area(p)) + crate::figures::shapes::perimeter(p) + util::LIMIT + p.sum();
     if n == 127 { 0 } else { 1 }
 }
% cat figures/shapes.tach
// Shapes made of points.

use crate::geom::{Point, area};
use crate::geom::scaling::double;

pub fn perimeter(p: Point) -> i64 {
    let q = double(p);
    (p.x + p.y) * scale() + area(q) - area(q)
}

// How many times a side counts.
fn scale() -> i64 {
    2
}
$ main.tach -o prog
ok: built prog
% ./prog; echo "exit $?"
exit 0
$ undo
undid script steps.txt: 3 commands	7 files	+55 -51 lines
% git status --short
?? prog
% find . -name '*.tach' | sort
./geom.tach
./main.tach
./shapes.tach
./util.tach
