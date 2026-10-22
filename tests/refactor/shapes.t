## volec refactor signature|field|variant (tests/refactor/shapes/).
$ check
ok: 0 errors in main.vl
## --- signature ---
## A parameter added: the definition, and each call with the value.
$ refactor signature area --add 'scale: i64 = 1' --fill-calls --dry-run
--- a/main.vl
+++ b/main.vl
@@ -16 +16 @@
-    let a = area(p) + area(q);
+    let a = area(p, 1) + area(q, 1);
--- a/geom.vl
+++ b/geom.vl
@@ -17 +17 @@
-pub fn area(p: Point) -> i64 {
+pub fn area(p: Point, scale: i64) -> i64 {
## A method: `p.scale(..)` and `Point::scale(&p, ..)`; --at counts self.
$ refactor signature Point::scale --add 'extra: i64 = 0' --at 1 --dry-run
--- a/main.vl
+++ b/main.vl
@@ -14,2 +14,2 @@
-    p.scale(2);
-    Point::scale(&p, 3);
+    p.scale(0, 2);
+    Point::scale(&p, 0, 3);
--- a/geom.vl
+++ b/geom.vl
@@ -46 +46 @@
-    pub fn scale(inout self, k: i64) {
+    pub fn scale(inout self, extra: i64, k: i64) {
note refactor.fill-calls: the calls get the value (a default is on trailing parameters only, and a later one has none)
## A trait's function: the trait, every impl, the calls (in a generic
## function's instances too).
$ refactor signature Shape::size --add 'bias: i64 = 0' --dry-run
--- a/main.vl
+++ b/main.vl
@@ -20 +20 @@
-    let s = total(p) + total(r) + p.size(3);
+    let s = total(p) + total(r) + p.size(3, 0);
--- a/geom.vl
+++ b/geom.vl
@@ -53 +53 @@
-    fn size(self, unit: i64) -> i64;
+    fn size(self, unit: i64, bias: i64) -> i64;
@@ -57 +57 @@
-    fn size(self, unit: i64) -> i64 {
+    fn size(self, unit: i64, bias: i64) -> i64 {
@@ -63 +63 @@
-    fn size(self, unit: i64) -> i64 {
+    fn size(self, unit: i64, bias: i64) -> i64 {
@@ -69 +69 @@
-    s.size(1) + s.size(2)
+    s.size(1, 0) + s.size(2, 0)
note refactor.fill-calls: the calls get the value (a trait's function has no defaults)
## Named by an impl's function: the same.
$ refactor signature Pair::size --remove unit --dry-run
error refactor.used: parameter unit is used in <crate::geom::Pair as Shape>::size at geom.vl:64:36
try: volec query show geom.vl:64
[exit 1]
## Removed: the argument too (a warning: it called a function).
$ refactor signature offset --remove pad --dry-run
--- a/main.vl
+++ b/main.vl
@@ -21 +21 @@
-    let o = offset(label().text, twice(1));
+    let o = offset(label().text);
--- a/geom.vl
+++ b/geom.vl
@@ -25 +25 @@
-pub fn offset(base: i64, pad: i64) -> i64 {
+pub fn offset(base: i64) -> i64 {
warning refactor.effects: a removed argument calls a function (first: main.vl:21:34); its calls are gone
$ refactor signature Point::size --rename-param unit u --dry-run
--- a/geom.vl
+++ b/geom.vl
@@ -53 +53 @@
-    fn size(self, unit: i64) -> i64;
+    fn size(self, u: i64) -> i64;
@@ -57,2 +57,2 @@
-    fn size(self, unit: i64) -> i64 {
-        (self.x + self.y) * unit
+    fn size(self, u: i64) -> i64 {
+        (self.x + self.y) * u
@@ -63,2 +63,2 @@
-    fn size(self, unit: i64) -> i64 {
-        (self.a + self.b) as i64 * unit
+    fn size(self, u: i64) -> i64 {
+        (self.a + self.b) as i64 * u
$ refactor signature apply --reorder x,f --dry-run
--- a/main.vl
+++ b/main.vl
@@ -7 +7 @@
-fn apply(f: fn(i64) -> i64, x: i64) -> i64 {
+fn apply(x: i64, f: fn(i64) -> i64) -> i64 {
@@ -22 +22 @@
-    let t = apply(twice, w + s + o);
+    let t = apply(w + s + o, twice);
$ refactor signature area --type p '*Point' --dry-run
--- a/geom.vl
+++ b/geom.vl
@@ -17 +17 @@
-pub fn area(p: Point) -> i64 {
+pub fn area(p: *Point) -> i64 {
main.vl:16:18: error[type error] expected '*Point', got 'Point' | help: a pointer to it: its address | try: &p | try: volec fix --suggested main.vl  [in crate::main]
geom.vl:18:5: error[unsafe] access to a field through a raw pointer is unsafe: `p` is a `*T` parameter | help: a `*T` parameter is a raw pointer (0.18.1); a borrow is `&T`, or `&mut T` when written through: make `p` one (the first try: changes such parameters, with their calls), or put this in an `unsafe { ... }` block (the second: what the first keeps raw, a pointer indexed, compared, cast, stored or given to C) | try: volec fix --values main.vl | try: volec fix --only unsafe main.vl  [edited: crate::geom::area]
geom.vl:18:11: error[unsafe] access to a field through a raw pointer is unsafe: `p` is a `*T` parameter | help: a `*T` parameter is a raw pointer (0.18.1); a borrow is `&T`, or `&mut T` when written through: make `p` one (the first try: changes such parameters, with their calls), or put this in an `unsafe { ... }` block (the second: what the first keeps raw, a pointer indexed, compared, cast, stored or given to C) | try: volec fix --values main.vl | try: volec fix --only unsafe main.vl  [edited: crate::geom::area]
warning edit.breaks: 3 new errors (2 in the edited text, 1 in crate::main, which the edit does not change) (dry run)
[exit 1]
## Refused: a function used as a value, a missing default, an unknown
## parameter, a parameter still used, a name taken.
$ refactor signature twice --add 'y: i64 = 0' --fill-calls
error refactor.fn-value: crate::geom::twice is used as a value at main.vl:22:19: its type would change; change that use first
try: volec query refs crate::geom::twice
[exit 1]
$ refactor signature area --add 'scale: i64'
error refactor.no-default: the calls need a value for scale: --add 'NAME: TYPE = VALUE'
try: volec refactor signature crate::geom::area --add 'scale: i64 = 0' --dry-run
[exit 2]
$ refactor signature area --remove q
error refactor.no-param: crate::geom::area has no parameter 'q': (p)
try: volec query def crate::geom::area
[exit 1]
$ refactor signature area --remove p
error refactor.used: parameter p is used in crate::geom::area at geom.vl:18:5
try: volec query show geom.vl:18
[exit 1]
$ refactor signature Point::scale --rename-param k self
error refactor.usage: self keeps its name (a method's first parameter is self)
try: volec refactor signature NAME --add 'x: i64 = 0' --dry-run
[exit 2]
## Renaming a parameter changes no type: a function used as a value is fine.
$ refactor signature twice --rename-param x n --dry-run
--- a/geom.vl
+++ b/geom.vl
@@ -21,2 +21,2 @@
-pub fn twice(x: i64) -> i64 {
-    x + x
+pub fn twice(n: i64) -> i64 {
+    n + n
## Ambiguous, and not a function.
$ refactor signature size --remove unit
error query.ambiguous: 3 definitions match 'size'; name one
try: volec refactor signature crate::geom::Shape::size --remove unit
try: volec refactor signature '<crate::geom::Point as Shape>::size' --remove unit
try: volec refactor signature '<crate::geom::Pair as Shape>::size' --remove unit
[exit 1]
$ refactor signature Point --remove x
error refactor.kind: crate::geom::Point is a struct, not a function
try: volec query def Point
[exit 1]
## A change that breaks the program: nothing written.
$ refactor signature area --type p i32
main.vl:16:18: error[type error] expected 'i32', got 'Point'  [in crate::main]
geom.vl:18:5: error[type error] cannot access field 'x' on type 'i32'  [edited: crate::geom::area]
error edit.breaks: 2 new errors (1 in the edited text, 1 in crate::main, which the edit does not change); nothing written
note edit.refactor: the uses of crate::geom::area no longer fit its new shape: a refactoring changes them with it (VALUE, EXPR: to fill in), then the rest of the edit
try: volec refactor signature crate::geom::area --type p i32 --default EXPR
note edit.together: change crate::main in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: volec query show crate::main
try: volec refactor signature area --type p i32 --no-check
[exit 1]
% git status --short
## Written, then undone.
$ refactor signature area --add 'scale: i64 = 1' --fill-calls
added parameter scale: i64 to crate::geom::area, 2 calls	2 files	+2 -2 lines
% git diff --stat
 geom.vl | 2 +-
 main.vl | 2 +-
 2 files changed, 2 insertions(+), 2 deletions(-)
$ undo
undid added parameter scale: i64 to crate::geom::area, 2 calls	2 files	+2 -2 lines
% git status --short
## --- field ---
$ refactor field Point --add 'z: i64 = 0' --dry-run
--- a/main.vl
+++ b/main.vl
@@ -12 +12 @@
-    var p = Point { x: 2, y: 3 };
+    var p = Point { x: 2, y: 3, z: 0 };
--- a/geom.vl
+++ b/geom.vl
@@ -6,0 +7 @@
+    z: i64,
@@ -13 +14 @@
-    Point { x: 0, y: 0 }
+    Point { x: 0, y: 0, z: 0 }
$ refactor field Point --rename y height --dry-run
--- a/main.vl
+++ b/main.vl
@@ -12 +12 @@
-    var p = Point { x: 2, y: 3 };
+    var p = Point { x: 2, height: 3 };
--- a/geom.vl
+++ b/geom.vl
@@ -6 +6 @@
-    pub y: i64,
+    pub height: i64,
@@ -13 +13 @@
-    Point { x: 0, y: 0 }
+    Point { x: 0, height: 0 }
@@ -18 +18 @@
-    p.x * p.y
+    p.x * p.height
@@ -48 +48 @@
-        self.y = self.y * k;
+        self.height = self.height * k;
@@ -58 +58 @@
-        (self.x + self.y) * unit
+        (self.x + self.height) * unit
$ refactor field Point --type x i32
geom.vl:47:27: error[type error] expected 'i32', got 'i64' | help: only widening is implicit: convert explicitly | try: k as i32 | try: volec fix --suggested main.vl  [in crate::geom::Point::scale]
error edit.breaks: 1 new error (1 in crate::geom::Point::scale, which the edit does not change); nothing written
note edit.refactor: the uses of crate::geom::Point no longer fit its new shape: a refactoring changes them with it, then the rest of the edit
try: volec refactor field crate::geom::Point --type x i32
note edit.together: change crate::geom::Point::scale in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: volec query show crate::geom::Point::scale
try: volec refactor field Point --type x i32 --no-check
[exit 1]
$ refactor field Point --remove y
error refactor.used: crate::geom::Point.y is used: 4 references (first: geom.vl:18:13)
try: volec query refs crate::geom::Point.y
[exit 1]
$ refactor field Pair --add 'c: i32 = 0' --dry-run
--- a/geom.vl
+++ b/geom.vl
@@ -10 +10 @@
-pub struct Pair { pub a: i32, pub b: i32 }
+pub struct Pair { pub a: i32, pub b: i32, c: i32 }
@@ -42 +42 @@
-    Pair { a: 1, b: 2 }
+    Pair { a: 1, b: 2, c: 0 }
warning refactor.layout: crate::geom::Pair is #[repr(C)]: its layout changes (C code sharing it must change too)
$ refactor field Pair --remove b --dry-run
error refactor.used: crate::geom::Pair.b is used: 1 reference (first: geom.vl:64:24)
try: volec query refs crate::geom::Pair.b
[exit 1]
## A field only the literals set: removed from them (one on lines of its own).
$ refactor field Label --remove hint --dry-run
--- a/geom.vl
+++ b/geom.vl
@@ -31 +30,0 @@
-    pub hint: i64,
@@ -37 +35,0 @@
-        hint: 2,
$ refactor field Label --add 'size: i64 = 4' --dry-run
--- a/geom.vl
+++ b/geom.vl
@@ -31,0 +32 @@
+    size: i64,
@@ -37,0 +39 @@
+        size: 4,
## --- variant ---
## An arm that does not check: nothing written.
$ refactor variant Kind --add 'Ring(i64, i64)' --arm 'oops'
kinds.vl:16:29: error[type error] undefined variable 'oops'  [edited: crate::kinds::weight]
kinds.vl:39:29: error[type error] undefined variable 'oops'  [edited: crate::kinds::sides]
error edit.breaks: 2 new errors; nothing written
try: volec refactor variant Kind --add 'Ring(i64, i64)' --arm oops --no-check
[exit 1]
## A match without `_` gets an arm (on a line of its own when the arms
## have theirs); one with `_` does not.
$ refactor variant Kind --add 'Ring(i64, i64)' --arm 0 --dry-run
--- a/kinds.vl
+++ b/kinds.vl
@@ -5,0 +6 @@
+    Ring(i64, i64),
@@ -14,0 +16 @@
+        Kind::Ring(_, _) => 0,
@@ -33 +35,6 @@
-    match k { Kind::Circle(_) => 0, Kind::Dot | Kind::Square(_) => 4, Kind::Empty => 0 }
+    match k {
+        Kind::Circle(_) => 0,
+        Kind::Dot | Kind::Square(_) => 4,
+        Kind::Empty => 0,
+        Kind::Ring(_, _) => 0,
+    }
## Without --arm: the matches that need one.
$ refactor variant Kind --add 'Ring(i64, i64)'
kinds.vl:9:5	kinds::weight
kinds.vl:33:5	kinds::sides
error refactor.non-exhaustive: 2 matches on crate::kinds::Kind would not cover Ring; nothing written
try: volec query show kinds.vl:9 kinds.vl:33
try: volec refactor variant crate::kinds::Kind --add 'Ring(i64, i64)' --arm 'EXPR' --dry-run
try: volec refactor variant crate::kinds::Kind --add 'Ring(i64, i64)' --arm-in kinds::weight 'EXPR' --arm-in kinds::sides 'EXPR' --dry-run
[exit 1]
$ refactor variant Kind --rename Empty Nothing --dry-run
--- a/main.vl
+++ b/main.vl
@@ -18 +18 @@
-    let w = weight(k) + describe(Kind::Empty);
+    let w = weight(k) + describe(Kind::Nothing);
--- a/kinds.vl
+++ b/kinds.vl
@@ -5 +5 @@
-    Empty,
+    Nothing,
@@ -14 +14 @@
-        Kind::Empty => 0,
+        Kind::Nothing => 0,
@@ -20 +20 @@
-        Kind::Empty => 0,
+        Kind::Nothing => 0,
@@ -33 +33 @@
-    match k { Kind::Circle(_) => 0, Kind::Dot | Kind::Square(_) => 4, Kind::Empty => 0 }
+    match k { Kind::Circle(_) => 0, Kind::Dot | Kind::Square(_) => 4, Kind::Nothing => 0 }
$ refactor variant Kind --remove Square
removed variant Square of crate::kinds::Kind, 2 arms	kinds.vl	+1 -4 lines
% git diff
diff --git a/kinds.vl b/kinds.vl
index f6e1340..c1bfa03 100644
--- a/kinds.vl
+++ b/kinds.vl
@@ -1,6 +1,5 @@
 pub enum Kind {
     Circle(i64),
-    Square(i64),
     Dot,
     Empty,
 }
@@ -8,8 +7,6 @@ pub enum Kind {
 pub fn weight(k: Kind) -> i64 {
     match k {
         Kind::Circle(r) => 3 * r * r,
-        // (a square of side s)
-        Kind::Square(s) => s * s,
         Kind::Dot => 1,
         Kind::Empty => 0,
     }
@@ -30,5 +27,5 @@ pub fn is_dot(k: Kind) -> bool {
 }
 
 pub fn sides(k: Kind) -> i64 {
-    match k { Kind::Circle(_) => 0, Kind::Dot | Kind::Square(_) => 4, Kind::Empty => 0 }
+    match k { Kind::Circle(_) => 0, Kind::Dot => 4, Kind::Empty => 0 }
 }
% git checkout -q .
$ refactor variant Kind --remove Empty
error refactor.constructed: crate::kinds::Kind::Empty is constructed at main.vl:18:34; change those first
try: volec query refs crate::kinds::Kind::Empty
[exit 1]
## Matched by an if let: refused.
$ refactor variant Kind --remove Dot
error refactor.if-let: crate::kinds::Kind::Dot is matched by an `if let` or `while let` at kinds.vl:26:12; change it first
try: volec query show kinds.vl:26
[exit 1]
## --- script ---
## Each command on the program the ones before left; one check, at the
## end; a summary line per command, then the total.
$ refactor --script steps.txt --dry-run
renamed field y to height of crate::geom::Point, 6 uses	2 files	+6 -6 lines
added parameter scale: i64 to crate::geom::area, 2 calls	2 files	+2 -2 lines
rewrote 2 sites in 1 file	main.vl	+1 -1 lines
replaced crate::geom::twice	geom.vl	+1 -1 lines
--- a/main.vl
+++ b/main.vl
@@ -12 +12 @@
-    var p = Point { x: 2, y: 3 };
+    var p = Point { x: 2, height: 3 };
@@ -16 +16 @@
-    let a = area(p) + area(q);
+    let a = area(p, 2) + area(q, 2);
--- a/geom.vl
+++ b/geom.vl
@@ -6 +6 @@
-    pub y: i64,
+    pub height: i64,
@@ -13 +13 @@
-    Point { x: 0, y: 0 }
+    Point { x: 0, height: 0 }
@@ -17,2 +17,2 @@
-pub fn area(p: Point) -> i64 {
-    p.x * p.y
+pub fn area(p: Point, scale: i64) -> i64 {
+    p.x * p.height
@@ -22 +22 @@
-    x + x
+    2 * x
@@ -48 +48 @@
-        self.y = self.y * k;
+        self.height = self.height * k;
@@ -58 +58 @@
-        (self.x + self.y) * unit
+        (self.x + self.height) * unit
% git status --short
$ refactor --script steps.txt
renamed field y to height of crate::geom::Point, 6 uses	2 files	+6 -6 lines
added parameter scale: i64 to crate::geom::area, 2 calls	2 files	+2 -2 lines
rewrote 2 sites in 1 file	main.vl	+1 -1 lines
replaced crate::geom::twice	geom.vl	+1 -1 lines
script steps.txt: 4 commands	2 files	+9 -9 lines
% git diff --stat
 geom.vl | 14 +++++++-------
 main.vl |  4 ++--
 2 files changed, 9 insertions(+), 9 deletions(-)
## One edit: one undo.
$ undo
undid script steps.txt: 4 commands	2 files	+9 -9 lines
% git status --short
## A command refused: nothing written.
$ refactor --script refused.txt
renamed field y to height of crate::geom::Point, 6 uses	2 files	+6 -6 lines
error refactor.used: crate::geom::Point.x is used: 4 references (first: geom.vl:18:7)
try: volec query refs crate::geom::Point.x main.vl
error refactor.script: refused.txt:2: the command failed (exit 1): refactor field Point --remove x; nothing written
[exit 1]
% git status --short
## Each command fine, the whole broken: nothing written.
$ refactor --script broken.txt
renamed parameter x to n of crate::geom::twice	geom.vl	+2 -2 lines
changed parameter p to i32 in crate::geom::area	geom.vl	+1 -1 lines
main.vl:16:18: error[type error] expected 'i32', got 'Point'  [in crate::main]
geom.vl:18:5: error[type error] cannot access field 'x' on type 'i32'  [edited: crate::geom::area]
error edit.breaks: 2 new errors (1 in the edited text, 1 in crate::main, which the edit does not change); nothing written
note edit.refactor: the uses of crate::geom::area no longer fit its new shape: a refactoring changes them with it (VALUE, EXPR: to fill in), then the rest of the edit
try: volec refactor signature crate::geom::area --type p i32 --default EXPR
try: volec refactor signature crate::geom::twice --rename-param x n
note edit.together: change crate::main in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: volec query show crate::main
try: volec refactor --script broken.txt --no-check
[exit 1]
% git status --short
## Not a script's command.
% printf 'query refs area\n' > q.txt
$ refactor --script q.txt
error refactor.script: q.txt:1: not a command a script runs (refactor, rewrite, edit, fix); nothing run
[exit 2]
% rm q.txt
