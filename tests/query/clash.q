# Names that clash (clash/): two modules with `helper`; a struct a::Point
# and a function geom::Point; `len` on two types (and std's); a trait's
# `add` and an inherent `add`; a local named `helper`; an alias import;
# std's Vec::push and a user Vec's push; c::printf and a user printf.
# (Nothing here prints a position in <C import>, whose line numbers
# depend on the host's headers.)
$ def helper
crate::a::helper  clash/a.tach:2:8  fn  pub fn helper() -> i64
crate::b::helper  clash/b.tach:1:8  fn  pub fn helper() -> i64
$ refs helper
// crate::a::helper
clash/a.tach:2:8  def  -> crate::a::helper  |  pub fn helper() -> i64 {
clash/main.tach:15:8  in crate  -> crate::a::helper  |  use a::helper as a_helper;
clash/main.tach:32:13  in crate::main  -> crate::a::helper  |  let n = a_helper() + b::helper() + helper;
// crate::b::helper
clash/b.tach:1:8  def  -> crate::b::helper  |  pub fn helper() -> i64 {
clash/main.tach:32:29  in crate::main  -> crate::b::helper  |  let n = a_helper() + b::helper() + helper;
$ refs a::helper
clash/a.tach:2:8  def  |  pub fn helper() -> i64 {
clash/main.tach:15:8  in crate  |  use a::helper as a_helper;
clash/main.tach:32:13  in crate::main  |  let n = a_helper() + b::helper() + helper;
$ refs crate::b::helper --count
2
$ callers helper
// crate::a::helper
clash/main.tach:32:13  in crate::main  -> crate::a::helper  |  let n = a_helper() + b::helper() + helper;
// crate::b::helper
clash/main.tach:32:29  in crate::main  -> crate::b::helper  |  let n = a_helper() + b::helper() + helper;
$ def --exact helper
tachyonc query: no definition named 'helper'
did you mean:
  crate::a::helper
  crate::b::helper
[exit 1]
$ def --exact crate::a::helper
crate::a::helper  clash/a.tach:2:8  fn  pub fn helper() -> i64
$ def Point
crate::a::Point  clash/a.tach:6:12  struct  pub struct Point
crate::geom::Point  clash/geom.tach:4:8  fn  pub fn Point(x: i64) -> i64
$ refs Point
// crate::a::Point
clash/a.tach:6:12  def  -> crate::a::Point  |  pub struct Point {
clash/main.tach:33:16  in crate::main  -> crate::a::Point  |  let p = a::Point { x: Point(n) };
// crate::geom::Point
clash/geom.tach:4:8  def  -> crate::geom::Point  |  pub fn Point(x: i64) -> i64 {
clash/main.tach:16:12  in crate  -> crate::geom::Point  |  use geom::{Point, V2};
clash/main.tach:33:27  in crate::main  -> crate::geom::Point  |  let p = a::Point { x: Point(n) };
$ show a::Point
// crate::a::Point  clash/a.tach:6-8
pub struct Point {
    pub x: i64,
}
$ def len
crate::geom::V2::len  clash/geom.tach:15:12  impl method  pub fn len(self: *V2) -> i64
crate::myvec::Vec::len  clash/myvec.tach:11:12  impl method  pub fn len(self: *Vec) -> i64
std::Vec::len  <std>:117:12  impl method  pub fn len(self: *Vec<T>) -> i64
std::Buf::len  <std>:193:12  impl method  pub fn len(self: *Buf) -> i64
std::HashMap::len  <std>:496:12  impl method  pub fn len(self: *HashMap<K, V>) -> i64
$ refs V2::len
clash/geom.tach:15:12  def  |  pub fn len(self: *V2) -> i64 {
clash/main.tach:40:17  in crate::main  |  mine.push(v.len());
$ refs myvec::Vec::len
clash/main.tach:47:76  in crate::main  |  let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
clash/myvec.tach:11:12  def  |  pub fn len(self: *Vec) -> i64 {
$ def V2::add
<crate::geom::V2 as Add>::add  clash/geom.tach:21:8  impl method  fn add(self: V2, o: V2) -> V2
$ def Vec::add
crate::myvec::Vec::add  clash/myvec.tach:15:12  impl method  pub fn add(self: *Vec, k: i64)
$ refs '<V2 as Add>::add'
clash/geom.tach:21:8  def  |  fn add(self: V2, o: V2) -> V2 {
clash/main.tach:35:13  in crate::main  |  let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs '<crate::geom::V2 as Add>::add' --exact
clash/geom.tach:21:8  def  |  fn add(self: V2, o: V2) -> V2 {
clash/main.tach:35:13  in crate::main  |  let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs V2::add
clash/geom.tach:21:8  def  |  fn add(self: V2, o: V2) -> V2 {
clash/main.tach:35:13  in crate::main  |  let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs crate::myvec::Vec::add
clash/main.tach:41:10  in crate::main  |  mine.add(1);
clash/myvec.tach:15:12  def  |  pub fn add(self: *Vec, k: i64) {
$ refs Area::area
clash/geom.tach:27:8  def  -> <crate::geom::V2 as Area>::area  |  fn area(self: *V2) -> i64 {
clash/main.tach:27:7  in crate::twice_generic  -> <crate::geom::V2 as Area>::area  |  x.area() + x.area()
clash/main.tach:27:7  in crate::twice_generic  -> <crate::shapes::Square as Area>::area  |  x.area() + x.area()
clash/main.tach:27:18  in crate::twice_generic  -> <crate::geom::V2 as Area>::area  |  x.area() + x.area()
clash/main.tach:27:18  in crate::twice_generic  -> <crate::shapes::Square as Area>::area  |  x.area() + x.area()
clash/shapes.tach:2:8  def  |  fn area(self: *Self) -> i64;
clash/shapes.tach:5:14  in crate::shapes::Area::twice  -> <crate::geom::V2 as Area>::area  |  self.area() * 2
clash/shapes.tach:5:14  in crate::shapes::Area::twice  -> <crate::shapes::Square as Area>::area  |  self.area() * 2
clash/shapes.tach:14:8  def  -> <crate::shapes::Square as Area>::area  |  fn area(self: *Square) -> i64 {
$ refs Area::twice
clash/main.tach:47:61  in crate::main  |  let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
clash/shapes.tach:4:8  def  |  fn twice(self: *Self) -> i64 {
$ show '<Square as Area>::area'
// <crate::shapes::Square as Area>::area  clash/shapes.tach:14-16
    fn area(self: *Square) -> i64 {
        self.side * self.side
    }
$ refs crate::shapes::Area
clash/geom.tach:1:20  in crate::geom  |  use crate::shapes::Area;
clash/geom.tach:26:6  in crate::geom  |  impl Area for V2 {
clash/main.tach:17:14  in crate  |  use shapes::{Area, Shape, Square};
clash/main.tach:26:21  in crate::twice_generic  |  fn twice_generic<T: Area>(x: *T) -> i64 {
clash/shapes.tach:1:11  def  |  pub trait Area {
clash/shapes.tach:13:6  in crate::shapes  |  impl Area for Square {
$ def push
crate::myvec::Vec::push  clash/myvec.tach:7:12  impl method  pub fn push(self: *Vec, x: i64)
std::Vec::push  <std>:138:12  impl method  pub fn push(self: *Vec<T>, x: T)
std::Buf::push  <std>:197:12  impl method  pub fn push(self: *Buf, b: u8)
$ refs Vec::push --count
2  crate::myvec::Vec::push
5  std::Vec::push
$ callers crate::myvec::Vec::push
clash/main.tach:40:10  in crate::main  |  mine.push(v.len());
$ refs crate::myvec::Vec::push
clash/main.tach:40:10  in crate::main  |  mine.push(v.len());
clash/myvec.tach:7:12  def  |  pub fn push(self: *Vec, x: i64) {
$ refs geom::V2
clash/geom.tach:8:12  def  |  pub struct V2 {
clash/geom.tach:13:6  in crate::geom  |  impl V2 {
clash/geom.tach:15:23  in crate::geom::V2::len  |  pub fn len(self: *V2) -> i64 {
clash/geom.tach:20:14  in crate::geom  |  impl Add for V2 {
clash/geom.tach:21:18  in <crate::geom::V2 as Add>::add  |  fn add(self: V2, o: V2) -> V2 {
clash/geom.tach:21:25  in <crate::geom::V2 as Add>::add  |  fn add(self: V2, o: V2) -> V2 {
clash/geom.tach:21:32  in <crate::geom::V2 as Add>::add  |  fn add(self: V2, o: V2) -> V2 {
clash/geom.tach:22:9  in <crate::geom::V2 as Add>::add  |  V2 { x: self.x + o.x, y: self.y + o.y }
clash/geom.tach:26:15  in crate::geom  |  impl Area for V2 {
clash/geom.tach:27:20  in <crate::geom::V2 as Area>::area  |  fn area(self: *V2) -> i64 {
clash/main.tach:16:19  in crate  |  use geom::{Point, V2};
clash/main.tach:35:13  in crate::main  |  let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
clash/main.tach:35:33  in crate::main  |  let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ callers printf
// crate::printf
clash/main.tach:47:84  in crate::main  -> crate::printf  |  let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
// crate::c::printf
clash/main.tach:49:12  in crate::main  -> crate::c::printf  |  c::printf(c"%d\n", total as i32);
$ refs crate::printf
clash/main.tach:21:4  def  |  fn printf(x: i64) -> i64 {
clash/main.tach:47:84  in crate::main  |  let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
$ show crate::printf
// crate::printf  clash/main.tach:20-23
/// The user's own printf (the C one is c::printf).
fn printf(x: i64) -> i64 {
    x + 1
}
$ callers c::printf --count
1
$ refs Point.x
clash/a.tach:7:9  def  |  pub x: i64,
clash/main.tach:33:24  in crate::main  |  let p = a::Point { x: Point(n) };
clash/main.tach:34:39  in crate::main  |  let s = sys::SockaddrIn { port: p.x };
$ refs .x --count
3  crate::a::Point.x
9  crate::geom::V2.x
$ refs SockaddrIn.port
clash/main.tach:10:33  def  |  pub struct SockaddrIn { pub port: i64 }
clash/main.tach:34:31  in crate::main  |  let s = sys::SockaddrIn { port: p.x };
clash/main.tach:38:20  in crate::main  |  std_vec.push(s.port);
$ show sys::SockaddrIn
// crate::sys::SockaddrIn  clash/main.tach:10-10
    pub struct SockaddrIn { pub port: i64 }
$ def Shape::Circle
crate::shapes::Shape::Circle  clash/shapes.tach:20:5  variant  Circle(i64)
$ refs Shape::Circle
clash/main.tach:42:24  in crate::main  |  let shape = Shape::Circle(2);
clash/main.tach:44:16  in crate::main  |  Shape::Circle(k) => k,
clash/shapes.tach:20:5  def  |  Circle(i64),
$ refs Shape::Dot
clash/main.tach:45:16  in crate::main  |  Shape::Dot => 0,
clash/shapes.tach:21:5  def  |  Dot,
$ refs crate::shapes::Shape
clash/main.tach:17:20  in crate  |  use shapes::{Area, Shape, Square};
clash/main.tach:42:17  in crate::main  |  let shape = Shape::Circle(2);
clash/main.tach:44:9  in crate::main  |  Shape::Circle(k) => k,
clash/main.tach:45:9  in crate::main  |  Shape::Dot => 0,
clash/shapes.tach:19:10  def  |  pub enum Shape {
$ refs a
clash/main.tach:3:5  def  |  mod a;
clash/main.tach:15:5  in crate  |  use a::helper as a_helper;
clash/main.tach:33:13  in crate::main  |  let p = a::Point { x: Point(n) };
$ def twice_generic
crate::twice_generic  clash/main.tach:26:4  fn  fn twice_generic<T: Area>(x: *T) -> i64
$ callers twice_generic
clash/main.tach:47:17  in crate::main  |  let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
clash/main.tach:47:38  in crate::main  |  let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
$ def UNIT
crate::shapes::UNIT  clash/shapes.tach:24:11  const  pub const UNIT: i64 = 1
$ def COUNT
crate::shapes::COUNT  clash/shapes.tach:25:16  static  pub static mut COUNT: i64 = 0
$ def Side
crate::shapes::Side  clash/shapes.tach:26:10  type alias  pub type Side = i64
$ def Area
crate::shapes::Area  clash/shapes.tach:1:11  trait  pub trait Area
$ items geom
// crate::geom  clash/geom.tach
4  fn  pub fn Point(x: i64) -> i64
8  struct  pub struct V2
13  impl  impl V2
15  impl method  pub fn len(self: *V2) -> i64
20  impl  impl Add for V2
21  impl method  fn add(self: V2, o: V2) -> V2
26  impl  impl Area for V2
27  impl method  fn area(self: *V2) -> i64
$ items crate
// crate  clash/main.tach
3  mod  mod a
4  mod  mod b
5  mod  mod geom
6  mod  mod shapes
7  mod  mod myvec
9  mod  mod sys
21  fn  fn printf(x: i64) -> i64
26  fn  fn twice_generic<T: Area>(x: *T) -> i64
30  fn  fn main() -> i32
$ items sys
// crate::sys  clash/main.tach
10  struct  pub struct SockaddrIn
$ def helpr
tachyonc query: no definition named 'helpr'
did you mean:
  crate::a::helper
  crate::b::helper
[exit 1]
$ refs MyVec
tachyonc query: no definition named 'MyVec'
'MyVec' is the name an import gives (clash/main.tach:18:12) to:
  crate::myvec::Vec
[exit 1]
$ refs a_helper
tachyonc query: no definition named 'a_helper'
'a_helper' is the name an import gives (clash/main.tach:15:8) to:
  crate::a::helper
did you mean:
  crate::a::helper
  crate::b::helper
[exit 1]
$ items nosuch
tachyonc query: no module named 'nosuch'
[exit 1]
