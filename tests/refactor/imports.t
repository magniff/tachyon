## 0.12: fix --only tidy-imports and fix --only reexports
## (tests/refactor/imports/).
## The root's import of `third` is what shapes::calc imports through
## (`use crate::third`): not unused.
$ query unused
crate::shapes::calc::unused_one	shapes/calc.tach:12:8	fn
$ fix --only unused --dry-run
note fix.none: nothing to fix
$ fix --only tidy-imports --dry-run
--- a/main.tach
+++ b/main.tach
@@ -7,3 +7 @@
-use util::square;
-use shapes::area;
-use util::{twice, cube};
+use util::{cube, square, third, twice};
@@ -11,2 +9 @@
-use util::third;
-use shapes::volume;
+use shapes::{area, volume};
--- a/shapes/mod.tach
+++ b/shapes/mod.tach
@@ -5,2 +5 @@
-pub use calc::{area, perimeter, unused_one};
-pub use calc::helper;
+pub use calc::{area, helper, perimeter, unused_one};
--- a/shapes/calc.tach
+++ b/shapes/calc.tach
@@ -2 +2 @@
-use crate::{twice, third};
+use crate::{third, twice};
## Only util.tach's imports: the re-exports stay (main and calc use them).
$ fix --only reexports --in util.tach --dry-run
--- a/shapes/mod.tach
+++ b/shapes/mod.tach
@@ -2 +2 @@
-mod calc;
+pub mod calc;
--- a/util.tach
+++ b/util.tach
@@ -3 +3 @@
-use crate::shapes::{area, perimeter};
+use crate::shapes::calc::{area, perimeter};
## All of them, tidied: area, perimeter and unused_one go, helper stays
## as a private import (shapes::local uses it), volume is the interface.
$ fix --only reexports,tidy-imports
fixed 6 imports through re-exports, 4 unused re-exports, 4 untidy use lines	4 files	+7 -10 lines
% cat main.tach
// A program for `fix --only tidy-imports` and `fix --only reexports`
// (tests/refactor/imports.t): untidy use lines, imports through
// re-exports, re-exports to remove, one marked as the interface.
mod shapes;
mod util;

use util::{cube, square, third, twice};
use util::half as halve;
use crate::shapes::calc::area;
use shapes::volume;

fn main() -> i32 {
    let a = square(3) + twice(2) + cube(1) + halve(4) + area(2) + volume(1);
    let b = crate::shapes::calc::perimeter(1) + util::twice(1) + shapes::local();
    if a + b > 0 { 0 } else { 1 }
}
% cat shapes/mod.tach
// Shapes: what shapes::calc and shapes::extra define, re-exported.
pub mod calc;
mod extra;

use calc::helper;
// api: the volume of a shape is part of the interface
pub use extra::volume;

pub fn local() -> i64 {
    helper(1)
}
% cat shapes/calc.tach
// The shapes' arithmetic.
use crate::util::{third, twice};

pub fn area(x: i64) -> i64 {
    x * x
}

pub fn perimeter(x: i64) -> i64 {
    twice(2 * x)
}

pub fn unused_one() -> i64 {
    third(0)
}

pub fn helper(x: i64) -> i64 {
    x
}
$ fix --only unused
fixed 1 unused import	main.tach	+1 -1 lines
$ fix --only reexports,tidy-imports
note fix.none: nothing to fix
$ check
