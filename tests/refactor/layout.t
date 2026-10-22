## 0.13: move --after/--before, blank lines kept as written, a banner
## with its whole group; split --plan's names and --names
## (tests/refactor/layout/; tests/refactor/roundtrip.sh moves random
## items there and back).
$ main.vl -o prog
ok: built prog
% ./prog; echo "exit $?"
exit 0
## Into a run of constants: joined to it, as written there.
$ refactor move crate::tables::LIMIT --to crate::shapes --after CORNERS
moved crate::tables::LIMIT to crate::shapes	3 files	+3 -4 lines
% sed -n '3,12p' shapes.vl
use crate::util::{clamp, twice};

pub const SIDES: i64 = 4;
pub const CORNERS: i64 = 4;
pub const LIMIT: i64 = 9;
pub const EDGES: i64 = SIDES;

// A point of the plane.
pub struct Point {
    pub x: i64,
$ refactor move crate::shapes::LIMIT --to crate::tables --before HITS
moved crate::shapes::LIMIT to crate::tables	3 files	+4 -3 lines
% git status --short
?? prog
## The statics written apart stay apart; the whole Points group goes with
## its banner, to where a group ends.
$ refactor move crate::tables::MISSES --to crate::util
moved crate::tables::MISSES to crate::util	2 files	+2 -2 lines
$ refactor move crate::util::MISSES --to crate::tables --after HITS
moved crate::util::MISSES to crate::tables	2 files	+2 -2 lines
$ refactor move crate::shapes::origin crate::shapes::unit --to crate::util
moved 2 items to crate::util	3 files	+14 -12 lines
% sed -n '/Points/,$p' util.vl
// ---- Points ----

pub fn origin() -> Point {
    Point { x: 0, y: 0 }
}

pub fn unit() -> Point {
    Point { x: 1, y: 1 }
}
$ refactor move crate::util::origin crate::util::unit --to crate::shapes --after diagonal
moved 2 items to crate::shapes	3 files	+12 -14 lines
% git status --short
?? prog
## --after an item that is not one of the module the items go to.
$ refactor move crate::shapes::area --to crate::tables --after area
error refactor.anchor: --after area: not an item of crate::tables with lines of its own (a function, type, constant, static)
try: volec query items crate::tables
[exit 1]
$ refactor move crate::shapes::area --to crate::tables --after Point
error refactor.anchor: --after Point: not an item of crate::tables with lines of its own (a function, type, constant, static)
try: volec query items crate::tables
[exit 1]
## split --plan: each part named from what its items share, the reason
## printed; --names names them.
$ refactor split crate::shapes --plan --max-lines 25
# crate::shapes	47 lines	3 parts of at most 25 lines
# stays in crate::shapes: the part most used from other modules
# points: banner '// ---- Points ----': 2 of 3 items, 6 of 11 lines
volec refactor split crate::shapes --into crate::shapes::points --items area,origin,unit
# measures: banner '// ---- Measures ----': 2 of 5 items, 7 of 10 lines
volec refactor split crate::shapes --into crate::shapes::measures --items SIDES,CORNERS,EDGES,perimeter,diagonal
note refactor.plan: the same in one edit: --auto (other names: --names a,b)
try: volec refactor split crate::shapes --auto --max-lines 25
$ refactor split crate::shapes --plan --max-lines 25 --names geometry
# crate::shapes	47 lines	3 parts of at most 25 lines
# stays in crate::shapes: the part most used from other modules
# geometry: --names
volec refactor split crate::shapes --into crate::shapes::geometry --items area,origin,unit
# measures: banner '// ---- Measures ----': 2 of 5 items, 7 of 10 lines
volec refactor split crate::shapes --into crate::shapes::measures --items SIDES,CORNERS,EDGES,perimeter,diagonal
note refactor.plan: the same in one edit: --auto (other names: --names a,b)
try: volec refactor split crate::shapes --auto --max-lines 25
$ refactor split crate::shapes --auto --max-lines 25 --names geometry,a,b
error refactor.usage: --names gives 3 names for 2 parts
try: volec refactor split crate::shapes --plan --max-lines 25
[exit 2]
$ refactor split crate::shapes --auto --max-lines 25 --names measures
split crate::shapes into 2 modules	4 files	+41 -33 lines
% ls shapes
measures.vl
mod.vl
point.vl
$ main.vl -o prog
ok: built prog
% ./prog; echo "exit $?"
exit 0
