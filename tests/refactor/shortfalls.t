## 0.14: the tools' shortfalls recorded in 0.13 (tests/refactor/shortfalls/).
$ check
ok: 0 errors in main.vl
## --- refactor variant --add --arm-in: an arm per match ---
## Without arms: the matches, and the commands that give them one (one
## --arm for all, or an --arm-in per match).
$ refactor variant Shape --add 'Ring(i64)'
shapes.vl:9:5	shapes::area
shapes.vl:16:5	shapes::round
error refactor.non-exhaustive: 2 matches on crate::shapes::Shape would not cover Ring; nothing written
try: volec query show shapes.vl:9 shapes.vl:16
try: volec refactor variant crate::shapes::Shape --add 'Ring(i64)' --arm 'EXPR' --dry-run
try: volec refactor variant crate::shapes::Shape --add 'Ring(i64)' --arm-in shapes::area 'EXPR' --arm-in shapes::round 'EXPR' --dry-run
[exit 1]
## Matches of different result types: an arm each, by function or
## FILE:LINE (a line of the match).
$ refactor variant Shape --add 'Ring(i64)' --arm-in area 0 --arm-in shapes.vl:17 false --dry-run
--- a/shapes.vl
+++ b/shapes.vl
@@ -5,0 +6 @@
+    Ring(i64),
@@ -11,0 +13 @@
+        Shape::Ring(_) => 0,
@@ -18,0 +21 @@
+        Shape::Ring(_) => false,
## --arm for the rest.
$ refactor variant Shape --add 'Ring(i64)' --arm-in round true --arm 7 --dry-run
--- a/shapes.vl
+++ b/shapes.vl
@@ -5,0 +6 @@
+    Ring(i64),
@@ -11,0 +13 @@
+        Shape::Ring(_) => 7,
@@ -18,0 +21 @@
+        Shape::Ring(_) => true,
## A match left without one: the command given, with an --arm-in for it.
$ refactor variant Shape --add 'Ring(i64)' --arm-in area 0
shapes.vl:16:5	shapes::round
error refactor.non-exhaustive: 1 match on crate::shapes::Shape would not cover Ring; nothing written
try: volec query show shapes.vl:16
try: volec refactor variant crate::shapes::Shape --add 'Ring(i64)' --arm-in area 0 --arm-in shapes::round 'EXPR' --dry-run
[exit 1]
## A site that holds no match needing an arm.
$ refactor variant Shape --add 'Ring(i64)' --arm-in price 0
shapes.vl:9:5	shapes::area
shapes.vl:16:5	shapes::round
error refactor.no-site: --arm-in price names no match on crate::shapes::Shape that needs an arm; nothing written
[exit 1]
## --- edit patch FILE:LINE on lines no item holds ---
## A banner between items; the header.
$ edit patch catalog.vl:11 --old 'Reports' --new 'Summaries' --dry-run
--- a/catalog.vl
+++ b/catalog.vl
@@ -11 +11 @@
-// ---- Reports ----
+// ---- Summaries ----
$ edit patch catalog.vl:1 --old 'Items' --new 'Things' --dry-run
--- a/catalog.vl
+++ b/catalog.vl
@@ -1 +1 @@
-// Items and their prices.
+// Things and their prices.
## --- edit insert, replace, patch: the imports the new text needs ---
$ edit insert --after catalog::price < square.vl
inserted after crate::catalog::price	catalog.vl	+7 -0 lines
note edit.imports: added the imports the new text needs (fix --only imports)
% git diff catalog.vl
diff --git a/catalog.vl b/catalog.vl
index b98312a..5b15531 100644
--- a/catalog.vl
+++ b/catalog.vl
@@ -1,5 +1,7 @@
 // Items and their prices.
 
+use crate::shapes::{Shape, area};
+
 pub struct Item {
     pub cost: i64,
 }
@@ -8,6 +10,11 @@ pub fn price(i: Item) -> i64 {
     i.cost * 2
 }
 
+// A square's price: its area.
+pub fn square_price(k: i64) -> i64 {
+    area(Shape::Square(k))
+}
+
 // ---- Reports ----
 
 pub fn summary(n: i64) -> i64 {
$ undo
undid inserted after crate::catalog::price	catalog.vl	+7 -0 lines
## In a module that imports its children relative: the same style.
$ edit patch main --old 'area(s)' --new 'area(s) + round(Shape::Dot) as i64' --dry-run
--- a/main.vl
+++ b/main.vl
@@ -6 +5,0 @@
-use catalog::{price, summary};
@@ -8 +6,0 @@
-use shapes::{Shape, area};
@@ -9,0 +8,3 @@
+use catalog::{price, summary};
+use shapes::{Shape, area, round};
+
@@ -12 +13 @@
-    let total = price(Item { cost: 3 }) + area(s) + summary(1) + table::fourth();
+    let total = price(Item { cost: 3 }) + area(s) + round(Shape::Dot) as i64 + summary(1) + table::fourth();
note edit.imports: added the imports the new text needs (fix --only imports)
## --- refactor --script: a command's stdin in the script (<<WORD) ---
$ refactor --script steps.txt
patched crate::catalog::price	catalog.vl	+2 -1 lines
inserted after crate::catalog::price	catalog.vl	+4 -0 lines
script steps.txt: 2 commands	catalog.vl	+6 -1 lines
% git diff catalog.vl
diff --git a/catalog.vl b/catalog.vl
index b98312a..c126827 100644
--- a/catalog.vl
+++ b/catalog.vl
@@ -5,7 +5,12 @@ pub struct Item {
 }
 
 pub fn price(i: Item) -> i64 {
-    i.cost * 2
+    // (twice the cost)
+    i.cost + i.cost
+}
+
+pub fn free(i: Item) -> bool {
+    price(i) == 0
 }
 
 // ---- Reports ----
$ undo
undid script steps.txt: 2 commands	catalog.vl	+6 -1 lines
## --- the style of the use lines: relative where the file is ---
## fix --only tidy-imports: one style per module (most of its use lines').
$ fix --only tidy-imports --dry-run
--- a/main.vl
+++ b/main.vl
@@ -6,2 +6 @@
-use catalog::{price, summary};
-use crate::catalog::Item;
+use catalog::{Item, price, summary};
## refactor move: the new import as the file's others.
$ refactor new-module crate::report
made module crate::report	2 files	+1 -0 lines
$ refactor move catalog::summary --to crate::report --dry-run
--- a/main.vl
+++ b/main.vl
@@ -7,2 +7,2 @@
-use catalog::{price, summary};
-use crate::catalog::Item;
+use catalog::{Item, price};
+use report::summary;
--- a/catalog.vl
+++ b/catalog.vl
@@ -10,6 +9,0 @@
-
-// ---- Reports ----
-
-pub fn summary(n: i64) -> i64 {
-    n + 1
-}
--- a/report.vl
+++ b/report.vl
@@ -0,0 +1,5 @@
+// ---- Reports ----
+
+pub fn summary(n: i64) -> i64 {
+    n + 1
+}
$ undo
undid made module crate::report	2 files	+1 -0 lines
## --- refactor split: a banner goes with most of its group ---
$ refactor split crate::table --into crate::table::lookups --items second,third,fourth
split crate::table: 3 items into crate::table::lookups	3 files	+19 -17 lines
% cat table/mod.vl
// A table of numbers.

pub mod lookups;

pub const SIZE: i64 = 4;

pub fn first() -> i64 {
    1
}
% cat table/lookups.vl
// Lookups

use crate::table::first;

pub fn second() -> i64 {
    2
}

pub fn third() -> i64 {
    3
}

pub fn fourth() -> i64 {
    first() + third()
}
$ main.vl -o prog
ok: built prog
% ./prog; echo "exit $?"
exit 0
