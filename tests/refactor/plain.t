## A program in a directory that is no git checkout, its root ./main.tach
## (0.14): every tool works with no flags; the journal for undo and query
## diff is .tachyonc/edits next to the root.
$ check
ok: 0 errors in main.tach
$ query def area
crate::geom::area	geom.tach:8:8	fn	pub fn area(p: Point) -> i64	effects: none
## ---- renaming a local ----
## By FN::local: every use, nothing else (the function's own name is
## also total).
$ refactor rename total::i j
renamed local i to j in crate::total, 4 uses	main.tach	+4 -4 lines
$ query diff
# renamed local i to j in crate::total, 4 uses	main.tach	+4 -4 lines
--- a/main.tach
+++ b/main.tach
@@ -10,3 +10,3 @@
-    var i = 0;
-    while i < points.len() {
-        let p = points.get(i);
+    var j = 0;
+    while j < points.len() {
+        let p = points.get(j);
@@ -14 +14 @@
-        i = i + 1;
+        j = j + 1;
% ls -A
.tachyonc
catalog.tach
geom.tach
main.tach
$ undo
undid renamed local i to j in crate::total, 4 uses	main.tach	+4 -4 lines
$ undo
error undo.empty: no edit to undo
[exit 1]
## A local shadowed by another of its name: the FN::local form is
## ambiguous; by position, the declaration or any use.
$ refactor rename main::x y
error refactor.ambiguous-local: main::x is several locals (shadowing); name one by its position
try: tachyonc refactor rename main.tach:28:9 y
try: tachyonc refactor rename main.tach:30:13 y
[exit 1]
$ refactor rename main.tach:30:13 inner --dry-run
--- a/main.tach
+++ b/main.tach
@@ -30,2 +30,2 @@
-        let x = x + 1;
-        std::print_int(x);
+        let inner = x + 1;
+        std::print_int(inner);
$ refactor rename main.tach:31:24 inner --dry-run
--- a/main.tach
+++ b/main.tach
@@ -30,2 +30,2 @@
-        let x = x + 1;
-        std::print_int(x);
+        let inner = x + 1;
+        std::print_int(inner);
$ refactor rename main.tach:28:9 n --dry-run
--- a/main.tach
+++ b/main.tach
@@ -28 +28 @@
-    let x = total(v);
+    let n = total(v);
@@ -30 +30 @@
-        let x = x + 1;
+        let x = n + 1;
@@ -33 +33 @@
-    std::print_int(twice(x));
+    std::print_int(twice(n));
## The new name is taken in its scope.
$ refactor rename main.tach:28:9 c
error refactor.collision: 'c' is already a name in the scope of local x (at main.tach:34:9); nothing written
try: tachyonc query show main.tach:28:9
[exit 1]
## (its own value is not in its scope)
$ refactor rename main.tach:28:9 total --dry-run
--- a/main.tach
+++ b/main.tach
@@ -28 +28 @@
-    let x = total(v);
+    let total = total(v);
@@ -30 +30 @@
-        let x = x + 1;
+        let x = total + 1;
@@ -33 +33 @@
-    std::print_int(twice(x));
+    std::print_int(twice(total));
$ refactor rename total::total p
error refactor.collision: 'p' is already a name in the scope of local total (at main.tach:12:13); nothing written
try: tachyonc query show main.tach:9:9
[exit 1]
## A local of a generic function (and its instances).
$ refactor rename twice::s sum --dry-run
--- a/main.tach
+++ b/main.tach
@@ -21,2 +21,2 @@
-    let s = a + a;
-    s
+    let sum = a + a;
+    sum
## A parameter: its uses, and the backquoted mentions in its function and
## the comment above it; the field of that name keeps its name.
$ refactor rename Catalog::add::qty copies --dry-run
--- a/catalog.tach
+++ b/catalog.tach
@@ -12,2 +12,2 @@
-    // Adds `qty` copies of the book `id`; see `Catalog::total`.
-    pub fn add(inout self, id: i64, qty: i64) -> i64 {
+    // Adds `copies` copies of the book `id`; see `Catalog::total`.
+    pub fn add(inout self, id: i64, copies: i64) -> i64 {
@@ -18,2 +18,2 @@
-                // `qty` more; `Item::qty` is the count.
-                it.qty += qty;
+                // `copies` more; `Item::qty` is the count.
+                it.qty += copies;
@@ -25,2 +25,2 @@
-        self.items.push(Item { id: id, qty: qty });
-        qty
+        self.items.push(Item { id: id, qty: copies });
+        copies
## A column at a reference renames what it refers to, not the function
## holding it.
$ refactor rename main.tach:13:26 surface --dry-run
--- a/main.tach
+++ b/main.tach
@@ -5 +5 @@
-use geom::{Point, area};
+use geom::{Point, surface};
@@ -13 +13 @@
-        total = total + area(p);
+        total = total + surface(p);
--- a/geom.tach
+++ b/geom.tach
@@ -1 +1 @@
-// Points; `area` is the one function.
+// Points; `surface` is the one function.
@@ -7,2 +7,2 @@
-// The `area` of p: x times y.
-pub fn area(p: Point) -> i64 {
+// The `surface` of p: x times y.
+pub fn surface(p: Point) -> i64 {
$ refactor rename main.tach:31:14 show
error edit.not-source: std::fmt::print_int is not in a file of the program
[exit 1]
## ---- the mentions in comments ----
## A field: only `Item.qty`, `Item::qty` mentions, not the parameter's
## `qty`.
$ refactor rename Item.qty copies --dry-run
--- a/catalog.tach
+++ b/catalog.tach
@@ -1 +1 @@
-// A title: `Item.qty` copies owned.
+// A title: `Item.copies` copies owned.
@@ -4 +4 @@
-    pub qty: i64,
+    pub copies: i64,
@@ -18,2 +18,2 @@
-                // `qty` more; `Item::qty` is the count.
-                it.qty += qty;
+                // `qty` more; `Item::copies` is the count.
+                it.copies += qty;
@@ -21 +21 @@
-                return it.qty;
+                return it.copies;
@@ -25 +25 @@
-        self.items.push(Item { id: id, qty: qty });
+        self.items.push(Item { id: id, copies: qty });
@@ -29 +29 @@
-    // The sum of `Item.qty`.
+    // The sum of `Item.copies`.
@@ -33 +33 @@
-            n += self.items.get(k).qty;
+            n += self.items.get(k).copies;
$ refactor field Item --rename qty copies --dry-run
--- a/catalog.tach
+++ b/catalog.tach
@@ -1 +1 @@
-// A title: `Item.qty` copies owned.
+// A title: `Item.copies` copies owned.
@@ -4 +4 @@
-    pub qty: i64,
+    pub copies: i64,
@@ -18,2 +18,2 @@
-                // `qty` more; `Item::qty` is the count.
-                it.qty += qty;
+                // `qty` more; `Item::copies` is the count.
+                it.copies += qty;
@@ -21 +21 @@
-                return it.qty;
+                return it.copies;
@@ -25 +25 @@
-        self.items.push(Item { id: id, qty: qty });
+        self.items.push(Item { id: id, copies: qty });
@@ -29 +29 @@
-    // The sum of `Item.qty`.
+    // The sum of `Item.copies`.
@@ -33 +33 @@
-            n += self.items.get(k).qty;
+            n += self.items.get(k).copies;
## An item: a bare `area` is left alone in a function with a parameter
## named area (and its comment); `total` above fn total too (a local).
$ refactor rename geom::area surface --dry-run
--- a/main.tach
+++ b/main.tach
@@ -5 +5 @@
-use geom::{Point, area};
+use geom::{Point, surface};
@@ -13 +13 @@
-        total = total + area(p);
+        total = total + surface(p);
--- a/geom.tach
+++ b/geom.tach
@@ -1 +1 @@
-// Points; `area` is the one function.
+// Points; `surface` is the one function.
@@ -7,2 +7,2 @@
-// The `area` of p: x times y.
-pub fn area(p: Point) -> i64 {
+// The `surface` of p: x times y.
+pub fn surface(p: Point) -> i64 {
$ refactor rename crate::total sum --dry-run
--- a/main.tach
+++ b/main.tach
@@ -8 +8 @@
-fn total(points: Vec<Point>) -> i64 {
+fn sum(points: Vec<Point>) -> i64 {
@@ -28 +28 @@
-    let x = total(v);
+    let x = sum(v);
