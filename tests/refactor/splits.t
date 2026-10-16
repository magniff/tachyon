## 0.12: refactor split keeps runs of items together, gives each part a
## header (its banner, or --header), moves a banner with most of its
## group, keeps the interface with --reexport, and tidies the imports
## of the files it edits (tests/refactor/splits/).
$ main.tach -o prog
ok: built prog
% ./prog; echo "exit $?"
exit 0
## --reexport: code outside the module (main.tach) is left as it is.
$ refactor split crate::table --into crate::table::weights --items W_LOW,W_MID,W_HIGH,weight --reexport
split crate::table: 4 items into crate::table::weights	2 files	+13 -10 lines
% git status --short
 D table.tach
?? prog
?? table/
% cat table/mod.tach
// A table of kinds.

mod weights;

pub use weights::weight;

pub const KINDS: i64 = 3;

// ---- Names ----

pub fn describe(k: i64) -> i64 {
    k + weight(k) + spare()
}

fn spare() -> i64 {
    0
}
% cat table/weights.tach
// Weights

const W_LOW: i64 = 1;
const W_MID: i64 = 2;
const W_HIGH: i64 = 4;

// The weight of kind k.
pub fn weight(k: i64) -> i64 {
    if k == 0 { W_LOW } else if k == 1 { W_MID } else { W_HIGH }
}
$ main.tach -o prog
ok: built prog
% ./prog; echo "exit $?"
exit 0
$ undo
undid split crate::table: 4 items into crate::table::weights	2 files	+13 -10 lines
## --header; the importers' use lines, tidied.
$ refactor split crate::table --into crate::table::names --items describe,spare --header 'Describing kinds.'
split crate::table: 2 items into crate::table::names	3 files	+17 -11 lines
% cat table/names.tach
// Describing kinds.

use crate::table::weight;

// ---- Names ----

pub fn describe(k: i64) -> i64 {
    k + weight(k) + spare()
}

fn spare() -> i64 {
    0
}
% cat main.tach
// A program to split (tests/refactor/splits.t).
mod table;

use table::{KINDS, weight};
use table::names::describe;

fn main() -> i32 {
    if describe(1) + weight(2) + KINDS == 10 { 0 } else { 1 }
}
$ undo
undid split crate::table: 2 items into crate::table::names	3 files	+17 -11 lines
## A banner goes with its group (0.13: all of it, or its first item and
## most of it into a new module): Names with describe and spare; Weights
## stays over its constants, and the new file gets a copy as its header.
$ refactor split crate::table --into crate::table::names --items describe,spare,weight
split crate::table: 3 items into crate::table::names	3 files	+22 -16 lines
% cat table/names.tach
// Weights

use crate::table::{W_HIGH, W_LOW, W_MID};

// The weight of kind k.
pub fn weight(k: i64) -> i64 {
    if k == 0 { W_LOW } else if k == 1 { W_MID } else { W_HIGH }
}

// ---- Names ----

pub fn describe(k: i64) -> i64 {
    k + weight(k) + spare()
}

fn spare() -> i64 {
    0
}
% cat table/mod.tach
// A table of kinds.

pub mod names;

pub const KINDS: i64 = 3;

// ---- Weights ----

const W_LOW: i64 = 1;
const W_MID: i64 = 2;
const W_HIGH: i64 = 4;
$ undo
undid split crate::table: 3 items into crate::table::names	3 files	+22 -16 lines
$ refactor split crate::table --into crate::table::names --items spare --no-tidy --dry-run
--- a/table/names.tach
+++ b/table/names.tach
@@ -0,0 +1,5 @@
+// Names
+
+pub fn spare() -> i64 {
+    0
+}
diff --git a/table.tach b/table/mod.tach
rename from table.tach
rename to table/mod.tach
--- a/table.tach
+++ b/table/mod.tach
@@ -2,0 +3,4 @@
+mod names;
+
+use crate::table::names::spare;
+
@@ -20,4 +23,0 @@
-}
-
-fn spare() -> i64 {
-    0
% git status --short
?? prog
