## Several NAMEs in one call, ROOT by --root, FILE:LINE (0.11).
$ def --root clash/main.vl a::helper b::helper
crate::a::helper	clash/a.vl:2:8	fn	pub fn helper() -> i64	effects: none
crate::b::helper	clash/b.vl:1:8	fn	pub fn helper() -> i64	effects: none
$ show a::helper geom::V2::len --root clash/main.vl
// crate::a::helper	clash/a.vl:1-4	effects: none
// `helper` here and in b; a struct named like geom's function.
pub fn helper() -> i64 {
    1
}
// crate::geom::V2::len	clash/geom.vl:14-17	effects: none
    /// Its squared length.
    pub fn len(self) -> i64 {
        self.x * self.x + self.y * self.y
    }
$ show clash/geom.vl:16 --root clash/main.vl
// crate::geom::V2::len	clash/geom.vl:14-17	effects: none
    /// Its squared length.
    pub fn len(self) -> i64 {
        self.x * self.x + self.y * self.y
    }
$ show geom.vl:16:9 clash/main.vl:33 --root clash/main.vl
// crate::geom::V2::len	clash/geom.vl:14-17	effects: none
    /// Its squared length.
    pub fn len(self) -> i64 {
        self.x * self.x + self.y * self.y
    }
// crate::main	clash/main.vl:30-52	effects: alloc(Gpa) io panic unsafe
fn main(gpa: Gpa) -> i32 {
    let helper = 3;
    let n = a_helper() + b::helper() + helper;
    let p = a::Point { x: Point(n) };
    let s = sys::SockaddrIn { port: p.x };
    let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
    let sq = Square { side: 2 };
    var std_vec: Vec<i64> = Vec::new_in(gpa);
    std_vec.push(s.port);
    var mine = MyVec { n: 0 };
    mine.push(v.len());
    mine.add(1);
    let shape = Shape::Circle(2);
    let r = match shape {
        Shape::Circle(k) => k,
        Shape::Dot => 0,
    };
    let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
    unsafe {
        c::printf(c"%d\n", total as i32);
    }
    0
}
$ def clash/geom.vl:2 --root clash/main.vl
error query.no-match: no item at clash/geom.vl:2
try: volec query items crate::geom clash/main.vl
[exit 1]
$ def nowhere.vl:3 --root clash/main.vl
error query.no-match: no file 'nowhere.vl' in the program
try: volec query items clash/main.vl
[exit 1]
$ refs a::helper b::helper --root clash/main.vl
# clash/a.vl
2:8	def	->a::helper	pub fn helper() -> i64 {
# clash/b.vl
1:8	def	->b::helper	pub fn helper() -> i64 {
# clash/main.vl
15:8	use	crate	->a::helper	use a::helper as a_helper;
32:13	call	main	->a::helper	let n = a_helper() + b::helper() + helper;
32:29	call	main	->b::helper	let n = a_helper() + b::helper() + helper;
$ def a::helper nothing_here b::helper --root clash/main.vl
crate::a::helper	clash/a.vl:2:8	fn	pub fn helper() -> i64	effects: none
crate::b::helper	clash/b.vl:1:8	fn	pub fn helper() -> i64	effects: none
error query.no-match: no definition 'nothing_here'
try: volec query items clash/main.vl
[exit 1]
