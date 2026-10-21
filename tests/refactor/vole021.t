## (0.21) `.vl`, the extension from 0.24 (vole), wherever `.tach` goes: the
## root main.vl, a module `geo/` with mod.vl and shapes.vl, next to a
## `.tach` module (util.tach): a mixed tree builds, runs, and is queried
## and edited by FILE:LINE; `edit new-file` makes a `.vl` file with its
## `mod` line; `x.tach` and `x.vl` both are an error; VOLE_ROOT is read as
## TACHYON_ROOT, and wins.
% "$COMPILER" main.vl -o prog && ./prog
12 10
ok: built prog
$ query refs area
# geo/mod.vl
2:8	def	pub fn area(w: i64, h: i64) -> i64 { shapes::rect(w, h) }
# main.vl
3:17	use	crate	use crate::geo::area;
5:16	call	main	println(f"{area(3, 4)} {crate::util::twice(5)}");
$ query show geo/mod.vl:2
// crate::geo::area	geo/mod.vl:2-2	effects: none
pub fn area(w: i64, h: i64) -> i64 { shapes::rect(w, h) }
% printf 'pub fn circle(r: i64) -> i64 { 3 * r * r }\n' | "$COMPILER" edit new-file geo/circle.vl
made crate::geo::circle	2 files	+2 -0 lines
$ edit patch geo/circle.vl:1 --old '3 * r * r' --new '314 * r * r / 100'
patched crate::geo::circle::circle	geo/circle.vl	+1 -1 lines
$ query show geo/circle.vl geo/mod.vl
// geo/circle.vl:1-1
pub fn circle(r: i64) -> i64 { 314 * r * r / 100 }
// geo/mod.vl:1-3
pub mod shapes;
mod circle;
pub fn area(w: i64, h: i64) -> i64 { shapes::rect(w, h) }
% cd geo && VOLE_ROOT=../main.vl TACHYON_ROOT=nowhere.tach "$COMPILER" query def twice
crate::util::twice	../util.tach:1:8	fn	pub fn twice(x: i64) -> i64	effects: none
% cp util.tach util.vl && "$COMPILER" check main.vl
main.vl:2:5: error[module error] module 'util' has two files, ./util.tach and ./util.vl | help: a module is one file: delete or rename one of them (`.vl` is the extension from 0.24)
[exit 1]
