## Several NAMEs in one call, ROOT by --root, FILE:LINE (0.11).
$ def --root clash/main.tach a::helper b::helper
crate::a::helper	clash/a.tach:2:8	fn	pub fn helper() -> i64
crate::b::helper	clash/b.tach:1:8	fn	pub fn helper() -> i64
$ show a::helper geom::V2::len --root clash/main.tach
// crate::a::helper	clash/a.tach:1-4
// `helper` here and in b; a struct named like geom's function.
pub fn helper() -> i64 {
    1
}
// crate::geom::V2::len	clash/geom.tach:14-17
    /// Its squared length.
    pub fn len(self: *V2) -> i64 {
        self.x * self.x + self.y * self.y
    }
$ show clash/geom.tach:16 --root clash/main.tach
// crate::geom::V2::len	clash/geom.tach:14-17
    /// Its squared length.
    pub fn len(self: *V2) -> i64 {
        self.x * self.x + self.y * self.y
    }
$ show geom.tach:16:9 clash/main.tach:33 --root clash/main.tach
// crate::geom::V2::len	clash/geom.tach:14-17
    /// Its squared length.
    pub fn len(self: *V2) -> i64 {
        self.x * self.x + self.y * self.y
    }
// crate::main	clash/main.tach:30-52
fn main(gpa: Gpa) -> i32 {
    let helper = 3;
    let n = a_helper() + b::helper() + helper;
    let p = a::Point { x: Point(n) };
    let s = sys::SockaddrIn { port: p.x };
    let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
    let sq = Square { side: 2 };
    let mut std_vec: Vec<i64> = Vec::new_in(gpa);
    std_vec.push(s.port);
    let mut mine = MyVec { n: 0 };
    mine.push(v.len());
    mine.add(1);
    let shape = Shape::Circle(2);
    let r = match shape {
        Shape::Circle(k) => k,
        Shape::Dot => 0,
    };
    let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
    unsafe {
        c::printf(c"%d\n", total as i32);
    }
    0
}
$ def clash/geom.tach:2 --root clash/main.tach
error query.no-match: no item at clash/geom.tach:2
try: tachyonc query items crate::geom clash/main.tach
[exit 1]
$ def nowhere.tach:3 --root clash/main.tach
error query.no-match: no file 'nowhere.tach' in the program
try: tachyonc query items clash/main.tach
[exit 1]
$ refs a::helper b::helper --root clash/main.tach
# clash/a.tach
2:8	def	->a::helper	pub fn helper() -> i64 {
# clash/b.tach
1:8	def	->b::helper	pub fn helper() -> i64 {
# clash/main.tach
15:8	use	crate	->a::helper	use a::helper as a_helper;
32:13	call	main	->a::helper	let n = a_helper() + b::helper() + helper;
32:29	call	main	->b::helper	let n = a_helper() + b::helper() + helper;
$ def a::helper nothing_here b::helper --root clash/main.tach
crate::a::helper	clash/a.tach:2:8	fn	pub fn helper() -> i64
crate::b::helper	clash/b.tach:1:8	fn	pub fn helper() -> i64
error query.no-match: no definition 'nothing_here'
try: tachyonc query items clash/main.tach
[exit 1]
