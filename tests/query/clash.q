## Names that clash (clash/): two modules with `helper`; a struct a::Point
## and a function geom::Point; `len` on two types (and std's); a trait's
## `add` and an inherent `add`; a local named `helper`; an alias import;
## std's Vec::push and a user Vec's push; c::printf and a user printf.
## (Nothing here prints a position in <C import>, whose line numbers
## depend on the host's headers.)
$ def helper
crate::a::helper	clash/a.tach:2:8	fn	pub fn helper() -> i64
crate::b::helper	clash/b.tach:1:8	fn	pub fn helper() -> i64
$ refs helper
# clash/a.tach
2:8	def	->a::helper	pub fn helper() -> i64 {
# clash/b.tach
1:8	def	->b::helper	pub fn helper() -> i64 {
# clash/main.tach
15:8	use	crate	->a::helper	use a::helper as a_helper;
32:13	call	main	->a::helper	let n = a_helper() + b::helper() + helper;
32:29	call	main	->b::helper	let n = a_helper() + b::helper() + helper;
$ refs a::helper
# clash/a.tach
2:8	def	pub fn helper() -> i64 {
# clash/main.tach
15:8	use	crate	use a::helper as a_helper;
32:13	call	main	let n = a_helper() + b::helper() + helper;
$ refs crate::b::helper --count
2
$ callers helper
# clash/main.tach
32:13	call	main	->a::helper	let n = a_helper() + b::helper() + helper;
32:29	call	main	->b::helper	let n = a_helper() + b::helper() + helper;
$ def --exact helper
error query.no-match: no definition 'helper'
try: tachyonc query def crate::a::helper
try: tachyonc query def crate::b::helper
[exit 1]
$ def --exact crate::a::helper
crate::a::helper	clash/a.tach:2:8	fn	pub fn helper() -> i64
$ def Point
crate::a::Point	clash/a.tach:6:12	struct	pub struct Point
crate::geom::Point	clash/geom.tach:4:8	fn	pub fn Point(x: i64) -> i64
$ refs Point
# clash/a.tach
6:12	def	->a::Point	pub struct Point {
# clash/geom.tach
4:8	def	->geom::Point	pub fn Point(x: i64) -> i64 {
# clash/main.tach
16:12	use	crate	->geom::Point	use geom::{Point, V2};
33:16	init	main	->a::Point	let p = a::Point { x: Point(n) };
33:27	call	main	->geom::Point	let p = a::Point { x: Point(n) };
$ show a::Point
// crate::a::Point	clash/a.tach:6-8
pub struct Point {
    pub x: i64,
}
$ def len
crate::geom::V2::len	clash/geom.tach:15:12	method	pub fn len(self: *V2) -> i64
crate::myvec::Vec::len	clash/myvec.tach:11:12	method	pub fn len(self: *Vec) -> i64
std::Vec::len	<std>:155:12	method	pub fn len(self: *Vec<T, A>) -> i64
std::Buf::len	<std>:393:12	method	pub fn len(self: *Buf<A>) -> i64
std::HashMap::len	<std>:999:12	method	pub fn len(self: *HashMap<K, V, A>) -> i64
$ refs V2::len
# clash/geom.tach
15:12	def	pub fn len(self: *V2) -> i64 {
# clash/main.tach
40:17	call	main	mine.push(v.len());
$ refs myvec::Vec::len
# clash/main.tach
47:76	call	main	let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
# clash/myvec.tach
11:12	def	pub fn len(self: *Vec) -> i64 {
$ def V2::add
<crate::geom::V2 as Add>::add	clash/geom.tach:21:8	method	fn add(self: V2, o: V2) -> V2
$ def Vec::add
crate::myvec::Vec::add	clash/myvec.tach:15:12	method	pub fn add(self: *Vec, k: i64)
$ refs '<V2 as Add>::add'
# clash/geom.tach
21:8	def	fn add(self: V2, o: V2) -> V2 {
# clash/main.tach
35:13	call	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs '<crate::geom::V2 as Add>::add' --exact
# clash/geom.tach
21:8	def	fn add(self: V2, o: V2) -> V2 {
# clash/main.tach
35:13	call	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs V2::add
# clash/geom.tach
21:8	def	fn add(self: V2, o: V2) -> V2 {
# clash/main.tach
35:13	call	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs crate::myvec::Vec::add
# clash/main.tach
41:10	call	main	mine.add(1);
# clash/myvec.tach
15:12	def	pub fn add(self: *Vec, k: i64) {
$ refs Area::area
# clash/geom.tach
27:8	def	-><geom::V2 as Area>::area	fn area(self: *V2) -> i64 {
# clash/main.tach
27:7	call	twice_generic	-><geom::V2 as Area>::area	x.area() + x.area()
27:7	call	twice_generic	-><shapes::Square as Area>::area	x.area() + x.area()
27:18	call	twice_generic	-><geom::V2 as Area>::area	x.area() + x.area()
27:18	call	twice_generic	-><shapes::Square as Area>::area	x.area() + x.area()
# clash/shapes.tach
2:8	def	->shapes::Area::area	fn area(self: *Self) -> i64;
5:14	call	shapes::Area::twice	-><geom::V2 as Area>::area	self.area() * 2
5:14	call	shapes::Area::twice	-><shapes::Square as Area>::area	self.area() * 2
14:8	def	-><shapes::Square as Area>::area	fn area(self: *Square) -> i64 {
$ refs Area::twice
# clash/main.tach
47:61	call	main	let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
# clash/shapes.tach
4:8	def	fn twice(self: *Self) -> i64 {
$ show '<Square as Area>::area'
// <crate::shapes::Square as Area>::area	clash/shapes.tach:14-16
    fn area(self: *Square) -> i64 {
        self.side * self.side
    }
$ refs crate::shapes::Area
# clash/geom.tach
1:20	use	geom	use crate::shapes::Area;
26:6	type	geom	impl Area for V2 {
# clash/main.tach
17:14	use	crate	use shapes::{Area, Shape, Square};
26:21	type	twice_generic	fn twice_generic<T: Area>(x: *T) -> i64 {
# clash/shapes.tach
1:11	def	pub trait Area {
13:6	type	shapes	impl Area for Square {
$ def push
crate::myvec::Vec::push	clash/myvec.tach:7:12	method	pub fn push(self: *Vec, x: i64)
std::Vec::push	<std>:234:12	method	pub fn push(self: *Vec<T, A>, x: T)
std::Buf::push	<std>:397:12	method	pub fn push(self: *Buf<A>, b: u8)
$ refs Vec::push --count
2	crate::myvec::Vec::push
10	std::Vec::push
$ callers crate::myvec::Vec::push
# clash/main.tach
40:10	call	main	mine.push(v.len());
$ refs crate::myvec::Vec::push
# clash/main.tach
40:10	call	main	mine.push(v.len());
# clash/myvec.tach
7:12	def	pub fn push(self: *Vec, x: i64) {
$ refs geom::V2
# clash/geom.tach
8:12	def	pub struct V2 {
13:6	type	geom	impl V2 {
15:23	type	geom::V2::len	pub fn len(self: *V2) -> i64 {
20:14	type	geom	impl Add for V2 {
21:18	type	<geom::V2 as Add>::add	fn add(self: V2, o: V2) -> V2 {
21:25	type	<geom::V2 as Add>::add	fn add(self: V2, o: V2) -> V2 {
21:32	type	<geom::V2 as Add>::add	fn add(self: V2, o: V2) -> V2 {
22:9	init	<geom::V2 as Add>::add	V2 { x: self.x + o.x, y: self.y + o.y }
26:15	type	geom	impl Area for V2 {
27:20	type	<geom::V2 as Area>::area	fn area(self: *V2) -> i64 {
# clash/main.tach
16:19	use	crate	use geom::{Point, V2};
35:13	init	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
35:33	init	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ callers printf
# clash/main.tach
47:84	call	main	->printf	let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
49:12	call	main	->c::printf	c::printf(c"%d\n", total as i32);
$ refs crate::printf
# clash/main.tach
21:4	def	fn printf(x: i64) -> i64 {
47:84	call	main	let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
$ show crate::printf
// crate::printf	clash/main.tach:20-23
/// The user's own printf (the C one is c::printf).
fn printf(x: i64) -> i64 {
    x + 1
}
$ callers c::printf --count
1
$ refs Point.x
# clash/a.tach
7:9	def	pub x: i64,
# clash/main.tach
33:24	init	main	let p = a::Point { x: Point(n) };
34:39	read	main	let s = sys::SockaddrIn { port: p.x };
$ refs .x --count
3	crate::a::Point.x
9	crate::geom::V2.x
$ refs SockaddrIn.port
# clash/main.tach
10:33	def	pub struct SockaddrIn { pub port: i64 }
34:31	init	main	let s = sys::SockaddrIn { port: p.x };
38:20	read	main	std_vec.push(s.port);
$ show sys::SockaddrIn
// crate::sys::SockaddrIn	clash/main.tach:10-10
    pub struct SockaddrIn { pub port: i64 }
$ def Shape::Circle
crate::shapes::Shape::Circle	clash/shapes.tach:20:5	variant	Circle(i64)
$ refs Shape::Circle
# clash/main.tach
42:24	init	main	let shape = Shape::Circle(2);
44:16	pat	main	Shape::Circle(k) => k,
# clash/shapes.tach
20:5	def	Circle(i64),
$ refs Shape::Dot
# clash/main.tach
45:16	pat	main	Shape::Dot => 0,
# clash/shapes.tach
21:5	def	Dot,
$ refs crate::shapes::Shape
# clash/main.tach
17:20	use	crate	use shapes::{Area, Shape, Square};
42:17	type	main	let shape = Shape::Circle(2);
44:9	type	main	Shape::Circle(k) => k,
45:9	type	main	Shape::Dot => 0,
# clash/shapes.tach
19:10	def	pub enum Shape {
$ refs a
# clash/main.tach
3:5	def	mod a;
15:5	mod	crate	use a::helper as a_helper;
33:13	mod	main	let p = a::Point { x: Point(n) };
$ def twice_generic
crate::twice_generic	clash/main.tach:26:4	fn	fn twice_generic<T: Area>(x: *T) -> i64
$ callers twice_generic
# clash/main.tach
47:17	call	main	let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
47:38	call	main	let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
$ def UNIT
crate::shapes::UNIT	clash/shapes.tach:24:11	const	pub const UNIT: i64 = 1
$ def COUNT
crate::shapes::COUNT	clash/shapes.tach:25:16	static	pub static mut COUNT: i64 = 0
$ def Side
crate::shapes::Side	clash/shapes.tach:26:10	type	pub type Side = i64
$ def Area
crate::shapes::Area	clash/shapes.tach:1:11	trait	pub trait Area
$ items geom
# crate::geom	clash/geom.tach
4	fn	pub fn Point(x: i64) -> i64
8	struct	pub struct V2
13	impl	impl V2
15	method	pub fn len(self: *V2) -> i64
20	impl	impl Add for V2
21	method	fn add(self: V2, o: V2) -> V2
26	impl	impl Area for V2
27	method	fn area(self: *V2) -> i64
$ items crate
# crate	clash/main.tach
3	mod	mod a
4	mod	mod b
5	mod	mod geom
6	mod	mod shapes
7	mod	mod myvec
9	mod	mod sys
21	fn	fn printf(x: i64) -> i64
26	fn	fn twice_generic<T: Area>(x: *T) -> i64
30	fn	fn main() -> i32
$ items sys
# crate::sys	clash/main.tach
10	struct	pub struct SockaddrIn
$ def helpr
error query.no-match: no definition 'helpr'
try: tachyonc query def crate::a::helper
try: tachyonc query def crate::b::helper
[exit 1]
$ refs MyVec
# clash/main.tach
18:12	use	crate	use myvec::Vec as MyVec;
39:20	init	main	let mut mine = MyVec { n: 0 };
# clash/myvec.tach
2:12	def	pub struct Vec {
6:6	type	myvec	impl Vec {
7:24	type	myvec::Vec::push	pub fn push(self: *Vec, x: i64) {
11:23	type	myvec::Vec::len	pub fn len(self: *Vec) -> i64 {
15:23	type	myvec::Vec::add	pub fn add(self: *Vec, k: i64) {
note query.alias: 'MyVec' is an import alias in crate, for crate::myvec::Vec
$ refs a_helper
# clash/a.tach
2:8	def	pub fn helper() -> i64 {
# clash/main.tach
15:8	use	crate	use a::helper as a_helper;
32:13	call	main	let n = a_helper() + b::helper() + helper;
note query.alias: 'a_helper' is an import alias in crate, for crate::a::helper
$ items nosuch
error query.no-match: no module 'nosuch'
try: tachyonc query items
[exit 1]
