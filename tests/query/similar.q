## `query similar NAME` (0.17): the items of NAME's kind nearest to it,
## its file first; a method: its type's methods.
$ similar area_circle
// 1 of 1 fns like crate::shapes::area_circle, nearest first; a new one beside it: tachyonc edit insert --after crate::shapes::area_circle < new.tach
// crate::shapes::area_square	similar/shapes.tach:34-37	effects: none
// side^2.
pub fn area_square(s: Square) -> i64 {
    s.side * s.side
}
$ similar twice --limit 1
// 1 of 3 fns like crate::twice, nearest first; a new one beside it: tachyonc edit insert --after crate::twice < new.tach
// crate::thrice	similar/main.tach:10-12	effects: none
fn thrice(x: i64) -> i64 {
    x * 3
}
$ similar Circle::diameter
// 1 of 1 methods like crate::shapes::Circle::diameter, nearest first; a new one beside it: tachyonc edit insert --after crate::shapes::Circle::diameter < new.tach
// crate::shapes::Circle::double_diameter	similar/shapes.tach:17-20	effects: none
    // Four times the radius.
    pub fn double_diameter(self: Circle) -> i64 {
        4 * self.r
    }
$ similar Square::perimeter Square
// 2 of 2 methods like crate::shapes::Square::perimeter, nearest first; a new one beside it: tachyonc edit insert --after crate::shapes::Square::perimeter < new.tach
// crate::shapes::Circle::double_diameter	similar/shapes.tach:17-20	effects: none
    // Four times the radius.
    pub fn double_diameter(self: Circle) -> i64 {
        4 * self.r
    }
// crate::shapes::Circle::diameter	similar/shapes.tach:12-15	effects: none
    // Twice the radius.
    pub fn diameter(self: Circle) -> i64 {
        2 * self.r
    }
// 1 of 1 structs like crate::shapes::Square, nearest first; a new one beside it: tachyonc edit insert --after crate::shapes::Square < new.tach
// crate::shapes::Circle	similar/shapes.tach:3-5
pub struct Circle {
    pub r: i64,
}
$ similar nothing_like_it
error query.no-match: no definition 'nothing_like_it'
try: tachyonc query items
[exit 1]
## `query examples` lists the kinds (they name the compiler's items).
$ examples
std-fn	a std function: compiler/std/*.tach, by its section (guide how add-std-fn)
std-method	a method of a std type: its impl in compiler/std/*.tach (guide how add-std-fn)
peephole	an instruction-combining rule: compiler/src/middle/fold/mod.tach, called from combine (guide how add-peephole)
egraph-rule	a rewrite rule of the e-graph: a line of rule_text, middle/egraph.tach (guide how add-peephole)
pass	an optimization pass: fn(fi: i64) -> bool, called from middle/opt.tach (guide how add-pass)
diagnostic	a front-end error: err_begin .. err_help .. err_end (guide how add-diagnostic)
tool-diagnostic	a tool diagnostic with a code and try: lines, and its explain entry (guide how add-diagnostic)
subcommand	a tachyonc subcommand: run_command's chain, its --help row (guide how add-subcommand)
query-command	a query command: command_name, answer, put_usage (guide how add-subcommand)
test	a test case: tests/run/NAME.tach with EXPECT, ERROR or CHECK lines (guide how add-test)
$ examples rules
error query.no-kind: no kind of example 'rules' (query examples lists them)
try: tachyonc query examples
[exit 2]
