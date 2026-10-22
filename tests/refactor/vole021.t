## (0.21, renamed in 0.24) A tree of `.vl` sources: the root main.vl, a
## module `geo/` with mod.vl and shapes.vl, a module util.vl: it builds,
## runs, and is queried and edited by FILE:LINE; `edit new-file` makes a
## `.vl` file with its `mod` line; a VOLE_ROOT that cannot be read is an
## error. (0.21's `x.tach` beside `x.vl` went with the aliases in 0.24.)
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
% cd geo && VOLE_ROOT=nowhere.vl "$COMPILER" query def twice
error query.bad-root: cannot read 'nowhere.vl'
try: volec query def twice
[exit 2]
