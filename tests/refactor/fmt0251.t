## volec fmt's style of 0.25.1 (tests/refactor/fmt0251/, docs/style.md):
## `use` items in groups, std, then crate, then the rest (super, self, a
## child module), a blank line between two, a run going on across blank
## lines; a trailing comma in a list whose closing bracket starts a line
## (a call of one argument too), none in a list on one line (but a tuple
## of one, `(x,)`); idempotent: a second fmt changes nothing.
$ fmt
formatted	2 files	+14 -11 lines
% cat main.vl
mod shapes;
use std::{Vec, print, println};

use crate::shapes::Point;

use shapes::area;
pub fn twice(x: i64) -> i64 { x * 2 }
fn pair(a: i64, b: i64) -> (i64, i64) { (a, b) }

fn main(gpa: Gpa) {
    let p = Point { x: 1, y: 2 };
    let q = Point {
        x: 3,
        y: 4,
    };
    let one = (p.x,);
    let t = pair(
        p.x,
        p.y,
    );
    let v = [
        1, 2,
        3,
    ];
    let w = area(
        q,
    );
    let r = match t.0 {
        1 => 10,
        _ => 20,
    };
    var xs: Vec<i64, Gpa> = Vec::new_in(gpa);
    xs.push(one.0 + r + w + v[0]);
    print(f"{t.1} ");
    println(xs.len());
}
% cat shapes/mod.vl
use std::println;

use super::twice;

pub struct Point {
    pub x: i64,
    pub y: i64,
}

pub fn area(p: Point) -> i64 { println(twice(p.x)); p.x * p.y }
$ fmt --check
$ fmt
note fmt.none: 2 files formatted already
