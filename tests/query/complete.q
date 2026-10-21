## The queries of 0.13 (complete/): banners and comments as items, text
## search, the type at a position, the kind of each reference, and the
## references refs used to miss: in a generic function nobody
## instantiates, through `Self`, through an import alias.
$ items crate shapes --comments
# crate	complete/main.tach
6	mod	mod shapes
10-28	section	State
12	static	static var COUNT: i64 = 0
15	struct	pub struct Counter
19	impl	impl Counter
20	method	pub fn new() -> Self
24	method	pub fn bump(inout self) -> i64
30-56	section	Shapes
32-32	comment	(the shapes come from shapes.tach)
34	fn	fn make(k: i64) -> Shape
42	fn	fn twice_area<T>(x: sink T, s: Shape) -> i64
47	fn	fn main() -> i32
# crate::shapes	complete/shapes.tach
3	enum	pub enum Shape
8-16	section	Areas
10	fn	pub fn area_of(s: Shape) -> i64
$ show main::section State
// crate::section State	complete/main.tach:10-28
// ---- State ----

static var COUNT: i64 = 0;

// A counter: how many shapes were made.
pub struct Counter {
    n: i64,
}

impl Counter {
    pub fn new() -> Self {
        Self { n: 0 }
    }

    pub fn bump(inout self) -> i64 {
        self.n += 1;
        self.n
    }
}
$ show shapes::section areas crate::section shapes
// crate::shapes::section Areas	complete/shapes.tach:8-16
// ==== Areas ====

pub fn area_of(s: Shape) -> i64 {
    match s {
        Shape::Square(n) => n * n,
        // (pi is 3 here)
        Shape::Circle(r) => 3 * r * r,
    }
}
// crate::section Shapes	complete/main.tach:30-56
// ---- Shapes ----

// (the shapes come from shapes.tach)

fn make(k: i64) -> Shape {
    unsafe {
        COUNT = COUNT + 1;
    }
    if k == 0 { Shape::Square(2) } else { Shape::Circle(1) }
}

// Never instantiated: its references are found all the same.
fn twice_area<T>(x: sink T, s: Shape) -> i64 {
    let c = Counter::new();
    area(s) + area(s) + unsafe { COUNT }
}

fn main() -> i32 {
    var c = Counter::new();
    let s = make(0);
    let label = "area of the shape";
    let r = match s {
        Shape::Square(n) => c.bump() + n,
        Shape::Circle(_) => area(s),
    };
    r as i32
}
$ show crate::section Nope
error query.no-match: no section 'Nope' in crate
try: tachyonc query items crate --comments
[exit 1]
$ show crate::section
error query.usage: show MODULE::section needs a TITLE
try: tachyonc query items crate --comments
[exit 2]
$ grep area
# complete/main.tach
8:21	code	crate	use shapes::{Shape, area_of as area};
8:32	code	crate	use shapes::{Shape, area_of as area};
42:10	code	twice_area	fn twice_area<T>(x: sink T, s: Shape) -> i64 {
44:5	code	twice_area	area(s) + area(s) + unsafe { COUNT }
44:15	code	twice_area	area(s) + area(s) + unsafe { COUNT }
50:18	string	main	let label = "area of the shape";
53:29	code	main	Shape::Circle(_) => area(s),
# complete/shapes.tach
1:22	comment	shapes	// Shapes, and their areas.
10:8	code	shapes::area_of	pub fn area_of(s: Shape) -> i64 {
$ grep area --strings --comments
# complete/main.tach
50:18	string	main	let label = "area of the shape";
# complete/shapes.tach
1:22	comment	shapes	// Shapes, and their areas.
$ grep area --code --word
# complete/main.tach
8:32	code	crate	use shapes::{Shape, area_of as area};
44:5	code	twice_area	area(s) + area(s) + unsafe { COUNT }
44:15	code	twice_area	area(s) + area(s) + unsafe { COUNT }
53:29	code	main	Shape::Circle(_) => area(s),
$ grep COUNT --in shapes
note query.empty: 0 hits in shapes
$ grep shape --count
6
$ type main.tach:44 complete/main.tach:44:5 main.tach:49 main.tach:52:30 main.tach:42:28 main.tach:999
i64	area(s) + area(s) + unsafe { COUNT }
i64	area(s)
Shape	make(0)
i64	c.bump()
error query.no-match: no checked expression at main.tach:42:28
try: tachyonc query show complete/main.tach:42
error query.no-match: complete/main.tach has no line 999
[exit 1]
$ refs Counter COUNT
# complete/main.tach
12:12	def	->COUNT	static var COUNT: i64 = 0;
15:12	def	->Counter	pub struct Counter {
19:6	type	crate	->Counter	impl Counter {
20:21	type	Counter::new	->Counter	pub fn new() -> Self {
21:9	init	Counter::new	->Counter	Self { n: 0 }
24:23	type	Counter::bump	->Counter	pub fn bump(inout self) -> i64 {
36:9	write	make	->COUNT	COUNT = COUNT + 1;
36:17	read	make	->COUNT	COUNT = COUNT + 1;
43:13	type	twice_area	->Counter	let c = Counter::new();
44:34	read	twice_area	->COUNT	area(s) + area(s) + unsafe { COUNT }
48:13	type	main	->Counter	var c = Counter::new();
$ refs Counter.n Shape::Square
# complete/main.tach
16:5	def	->Counter.n	n: i64,
21:16	init	Counter::new	->Counter.n	Self { n: 0 }
25:14	write	Counter::bump	->Counter.n	self.n += 1;
26:14	read	Counter::bump	->Counter.n	self.n
38:24	init	make	->shapes::Shape::Square	if k == 0 { Shape::Square(2) } else { Shape::Circle(1) }
52:16	pat	main	->shapes::Shape::Square	Shape::Square(n) => c.bump() + n,
# complete/shapes.tach
4:5	def	->shapes::Shape::Square	Square(i64),
12:16	pat	shapes::area_of	->shapes::Shape::Square	Shape::Square(n) => n * n,
$ refs area
# complete/main.tach
8:21	use	crate	use shapes::{Shape, area_of as area};
44:5	call	twice_area	area(s) + area(s) + unsafe { COUNT }
44:15	call	twice_area	area(s) + area(s) + unsafe { COUNT }
53:29	call	main	Shape::Circle(_) => area(s),
# complete/shapes.tach
10:8	def	pub fn area_of(s: Shape) -> i64 {
note query.alias: 'area' is an import alias in crate, for crate::shapes::area_of
$ def area
crate::shapes::area_of	complete/shapes.tach:10:8	fn	pub fn area_of(s: Shape) -> i64	effects: none
note query.alias: 'area' is an import alias in crate, for crate::shapes::area_of
$ def --exact area
error query.no-match: no definition 'area'
try: tachyonc query items
[exit 1]
$ callers area_of
# complete/main.tach
44:5	call	twice_area	area(s) + area(s) + unsafe { COUNT }
44:15	call	twice_area	area(s) + area(s) + unsafe { COUNT }
53:29	call	main	Shape::Circle(_) => area(s),
