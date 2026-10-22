## Names that clash (clash/): two modules with `helper`; a struct a::Point
## and a function geom::Point; `len` on two types (and std's); a trait's
## `add` and an inherent `add`; a local named `helper`; an alias import;
## std's Vec::push and a user Vec's push; c::printf and a user printf.
## (Nothing here prints a position in <C import>, whose line numbers
## depend on the host's headers.)
$ def helper
crate::a::helper	clash/a.vl:2:8	fn	pub fn helper() -> i64	effects: none
crate::b::helper	clash/b.vl:1:8	fn	pub fn helper() -> i64	effects: none
$ refs helper
# clash/a.vl
2:8	def	->a::helper	pub fn helper() -> i64 {
# clash/b.vl
1:8	def	->b::helper	pub fn helper() -> i64 {
# clash/main.vl
15:8	use	crate	->a::helper	use a::helper as a_helper;
32:13	call	main	->a::helper	let n = a_helper() + b::helper() + helper;
32:29	call	main	->b::helper	let n = a_helper() + b::helper() + helper;
$ refs a::helper
# clash/a.vl
2:8	def	pub fn helper() -> i64 {
# clash/main.vl
15:8	use	crate	use a::helper as a_helper;
32:13	call	main	let n = a_helper() + b::helper() + helper;
$ refs crate::b::helper --count
2
$ callers helper
# clash/main.vl
32:13	call	main	->a::helper	let n = a_helper() + b::helper() + helper;
32:29	call	main	->b::helper	let n = a_helper() + b::helper() + helper;
$ def --exact helper
error query.no-match: no definition 'helper'
try: volec query def crate::a::helper
try: volec query def crate::b::helper
try: volec query def std::gpu::wgsl::msl::helpers
[exit 1]
$ def --exact crate::a::helper
crate::a::helper	clash/a.vl:2:8	fn	pub fn helper() -> i64	effects: none
$ def Point
crate::a::Point	clash/a.vl:6:12	struct	pub struct Point
crate::geom::Point	clash/geom.vl:4:8	fn	pub fn Point(x: i64) -> i64	effects: none
std::window::objc::Point	../../compiler/std/window/objc.vl:25:12	struct	pub struct Point
$ refs Point
# clash/a.vl
6:12	def	->a::Point	pub struct Point {
# clash/geom.vl
4:8	def	->geom::Point	pub fn Point(x: i64) -> i64 {
# clash/main.vl
16:12	use	crate	->geom::Point	use geom::{Point, V2};
33:16	init	main	->a::Point	let p = a::Point { x: Point(n) };
33:27	call	main	->geom::Point	let p = a::Point { x: Point(n) };
# <std>
44092:16	use	std::window::cocoa	->std::window::objc::Point	NOT_FOUND, Point, Range, Rect, class, class_addIvar, class_addProtocol,
44147:61	type	std::window::cocoa::add_u_t	->std::window::objc::Point	fn add_u_t(c: *u8, s: *u8, imp: extern "C" fn(*u8, *u8, Point) -> u64, t: *u8) -> bool;
44257:25	init	std::window::cocoa::post_wake	->std::window::objc::Point	EV_APP_DEFINED, Point { x: 0.0, y: 0.0 }, 0, 0.0, 0, 0 as *u8, 0, WAKE, 0);
44618:54	type	std::window::cocoa::imp_char_index	->std::window::objc::Point	extern "C" fn imp_char_index(this: *u8, cmd: *u8, p: Point) -> u64 {
45774:12	def	->std::window::objc::Point	pub struct Point {
45860:53	type	std::window::objc::msg_p_utudipsii	->std::window::objc::Point	fn msg_p_utudipsii(o: *u8, s: *u8, ty: u64, at: Point, flags: u64, time: f64, win: i64,
45865:54	type	std::window::objc::msg_p_utudipppbh	->std::window::objc::Point	fn msg_p_utudipppbh(o: *u8, s: *u8, ty: u64, at: Point, flags: u64, time: f64, win: i64,
45870:53	type	std::window::objc::msg_p_utudipiif	->std::window::objc::Point	fn msg_p_utudipiif(o: *u8, s: *u8, ty: u64, at: Point, flags: u64, time: f64, win: i64,
45929:33	type	std::window::objc::msg_t	->std::window::objc::Point	fn msg_t(o: *u8, s: *u8) -> Point;
45941:36	type	std::window::objc::msg_t_tp	->std::window::objc::Point	fn msg_t_tp(o: *u8, s: *u8, a: Point, b: *u8) -> Point;
45941:54	type	std::window::objc::msg_t_tp	->std::window::objc::Point	fn msg_t_tp(o: *u8, s: *u8, a: Point, b: *u8) -> Point;
$ show a::Point
// crate::a::Point	clash/a.vl:6-8
pub struct Point {
    pub x: i64,
}
$ def len
crate::geom::V2::len	clash/geom.vl:15:12	method	pub fn len(self) -> i64	effects: none
crate::myvec::Vec::len	clash/myvec.vl:11:12	method	pub fn len(self) -> i64	effects: none
std::Vec::len	../../compiler/std/std.vl:204:12	method	pub fn len(self) -> i64
std::Buf::len	../../compiler/std/std.vl:506:12	method	pub fn len(self) -> i64
std::BinaryHeap::len	../../compiler/std/flat/collections.vl:192:12	method	pub fn len(self) -> i64
std::MinHeap::len	../../compiler/std/flat/collections.vl:288:12	method	pub fn len(self) -> i64
std::collections::hash_map::HashMap::len	../../compiler/std/collections/hash_map.vl:37:12	method	pub fn len(self) -> i64
std::collections::hash_set::HashSet::len	../../compiler/std/collections/hash_set.vl:35:12	method	pub fn len(self) -> i64
std::collections::raw_table::RawTable::len	../../compiler/std/collections/raw_table.vl:136:12	method	pub fn len(self) -> i64
std::collections::btree_node::BTreeRaw::len	../../compiler/std/collections/btree_node.vl:236:12	method	pub fn len(self) -> i64
std::collections::btree_map::BTreeMap::len	../../compiler/std/collections/btree_map.vl:25:12	method	pub fn len(self) -> i64
std::collections::btree_map::BTreeSet::len	../../compiler/std/collections/btree_map.vl:215:12	method	pub fn len(self) -> i64
str::len	../../compiler/std/string.vl:287:12	method	pub fn len(self) -> i64	effects: none
std::string::String::len	../../compiler/std/string.vl:1165:12	method	pub fn len(self) -> i64
Path::len	../../compiler/std/path.vl:50:12	method	pub fn len(self) -> i64	effects: none
std::fs::Metadata::len	../../compiler/std/fs.vl:206:12	method	pub fn len(self) -> i64	effects: none
std::env::Args::len	../../compiler/std/env.vl:70:12	method	pub fn len(self) -> i64	effects: none
$ refs V2::len
# clash/geom.vl
15:12	def	pub fn len(self) -> i64 {
# clash/main.vl
40:17	call	main	mine.push(v.len());
$ refs myvec::Vec::len
# clash/main.vl
47:74	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
# clash/myvec.vl
11:12	def	pub fn len(self) -> i64 {
$ def V2::add
<crate::geom::V2 as Add>::add	clash/geom.vl:21:8	method	fn add(self, o: V2) -> V2	effects: none
$ def Vec::add
crate::myvec::Vec::add	clash/myvec.vl:15:12	method	pub fn add(inout self, k: i64)	effects: none
$ refs '<V2 as Add>::add'
# clash/geom.vl
21:8	def	fn add(self, o: V2) -> V2 {
# clash/main.vl
35:13	call	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs '<crate::geom::V2 as Add>::add' --exact
# clash/geom.vl
21:8	def	fn add(self, o: V2) -> V2 {
# clash/main.vl
35:13	call	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs V2::add
# clash/geom.vl
21:8	def	fn add(self, o: V2) -> V2 {
# clash/main.vl
35:13	call	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs crate::myvec::Vec::add
# clash/main.vl
41:10	call	main	mine.add(1);
# clash/myvec.vl
15:12	def	pub fn add(inout self, k: i64) {
$ refs Area::area
# clash/geom.vl
27:8	def	-><geom::V2 as Area>::area	fn area(self) -> i64 {
# clash/main.vl
27:7	call	twice_generic	-><geom::V2 as Area>::area	x.area() + x.area()
27:7	call	twice_generic	-><shapes::Square as Area>::area	x.area() + x.area()
27:18	call	twice_generic	-><geom::V2 as Area>::area	x.area() + x.area()
27:18	call	twice_generic	-><shapes::Square as Area>::area	x.area() + x.area()
# clash/shapes.vl
2:8	def	->shapes::Area::area	fn area(self) -> i64;
5:14	call	shapes::Area::twice	-><geom::V2 as Area>::area	self.area() * 2
5:14	call	shapes::Area::twice	-><shapes::Square as Area>::area	self.area() * 2
14:8	def	-><shapes::Square as Area>::area	fn area(self) -> i64 {
$ refs Area::twice
# clash/main.vl
47:59	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
# clash/shapes.vl
4:8	def	fn twice(self) -> i64 {
$ show '<Square as Area>::area'
// <crate::shapes::Square as Area>::area	clash/shapes.vl:14-16	effects: none
    fn area(self) -> i64 {
        self.side * self.side
    }
$ refs crate::shapes::Area
# clash/geom.vl
1:20	use	geom	use crate::shapes::Area;
26:6	type	geom	impl Area for V2 {
# clash/main.vl
17:14	use	crate	use shapes::{Area, Shape, Square};
26:21	type	twice_generic	fn twice_generic<T: Area>(x: T) -> i64 {
# clash/shapes.vl
1:11	def	pub trait Area {
13:6	type	shapes	impl Area for Square {
$ def push
crate::myvec::Vec::push	clash/myvec.vl:7:12	method	pub fn push(inout self, x: i64)	effects: none
std::Vec::push	../../compiler/std/std.vl:285:12	method	pub fn push(inout self, x: sink T)
std::Buf::push	../../compiler/std/std.vl:510:12	method	pub fn push(inout self, b: u8)
std::BinaryHeap::push	../../compiler/std/flat/collections.vl:202:12	method	pub fn push(inout self, x: sink T)
std::MinHeap::push	../../compiler/std/flat/collections.vl:298:12	method	pub fn push(inout self, x: sink T)
std::unicode::GraphemeState::push	../../compiler/std/unicode/mod.vl:167:12	method	pub fn push(inout self, cp: u32) -> bool	effects: panic
std::unicode::ClusterWidth::push	../../compiler/std/unicode/mod.vl:396:12	method	pub fn push(inout self, cp: u32, p: u16)	effects: none
std::objc::Pool::push	../../compiler/std/objc/mod.vl:218:12	method	pub fn push() -> Pool	effects: alloc(Gpa, extern) io global panic diverge unsafe
std::string::String::push	../../compiler/std/string.vl:1204:12	method	pub fn push(inout self, cp: u32)
std::path::PathBuf::push	../../compiler/std/path.vl:250:12	method	pub fn push(inout self, p: [u8])
std::window::cocoa::push	../../compiler/std/window/cocoa.vl:202:4	fn	fn push(e: Event)	effects: alloc(Gpa, extern) io global panic diverge unsafe
std::cli::Matches::push	../../compiler/std/cli.vl:766:8	method	fn push(inout self, s: i64, text: str)
$ refs Vec::push --count
2	crate::myvec::Vec::push
179	std::Vec::push
$ callers crate::myvec::Vec::push
# clash/main.vl
40:10	call	main	mine.push(v.len());
$ refs crate::myvec::Vec::push
# clash/main.vl
40:10	call	main	mine.push(v.len());
# clash/myvec.vl
7:12	def	pub fn push(inout self, x: i64) {
$ refs geom::V2
# clash/geom.vl
8:12	def	pub struct V2 {
13:6	type	geom	impl V2 {
15:16	type	geom::V2::len	pub fn len(self) -> i64 {
20:14	type	geom	impl Add for V2 {
21:12	type	<geom::V2 as Add>::add	fn add(self, o: V2) -> V2 {
21:21	type	<geom::V2 as Add>::add	fn add(self, o: V2) -> V2 {
21:28	type	<geom::V2 as Add>::add	fn add(self, o: V2) -> V2 {
22:9	init	<geom::V2 as Add>::add	V2 { x: self.x + o.x, y: self.y + o.y }
26:15	type	geom	impl Area for V2 {
27:13	type	<geom::V2 as Area>::area	fn area(self) -> i64 {
# clash/main.vl
16:19	use	crate	use geom::{Point, V2};
35:13	init	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
35:33	init	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ callers printf
# clash/main.vl
47:82	call	main	->printf	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
49:12	call	main	->c::printf	c::printf(c"%d\n", total as i32);
$ refs crate::printf
# clash/main.vl
21:4	def	fn printf(x: i64) -> i64 {
47:82	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
$ show crate::printf
// crate::printf	clash/main.vl:20-23	effects: none
/// The user's own printf (the C one is c::printf).
fn printf(x: i64) -> i64 {
    x + 1
}
$ callers c::printf --count
1
$ refs Point.x
# clash/a.vl
7:9	def	->a::Point.x	pub x: i64,
# clash/main.vl
33:24	init	main	->a::Point.x	let p = a::Point { x: Point(n) };
34:39	read	main	->a::Point.x	let s = sys::SockaddrIn { port: p.x };
# <std>
44257:33	init	std::window::cocoa::post_wake	->std::window::objc::Point.x	EV_APP_DEFINED, Point { x: 0.0, y: 0.0 }, 0, 0.0, 0, 0 as *u8, 0, WAKE, 0);
44442:18	read	std::window::cocoa::imp_mouse	->std::window::objc::Point.x	x: p.x * s,
45775:9	def	->std::window::objc::Point.x	pub x: f64,
$ refs .x --count
3	crate::a::Point.x
9	crate::geom::V2.x
3	std::gpu::hal::metal::bindings::MTLOrigin.x
3	std::gpu::hal::metal::bindings::MTLScissorRect.x
2	std::window::Mouse.x
3	std::window::objc::Point.x
5	std::window::objc::Rect.x
1	std::window::objc::MtlRegion.x
$ refs SockaddrIn.port
# clash/main.vl
10:33	def	pub struct SockaddrIn { pub port: i64 }
34:31	init	main	let s = sys::SockaddrIn { port: p.x };
38:20	read	main	std_vec.push(s.port);
$ show sys::SockaddrIn
// crate::sys::SockaddrIn	clash/main.vl:10-10
    pub struct SockaddrIn { pub port: i64 }
$ def Shape::Circle
crate::shapes::Shape::Circle	clash/shapes.vl:20:5	variant	Circle(i64)
$ refs Shape::Circle
# clash/main.vl
42:24	init	main	let shape = Shape::Circle(2);
44:16	pat	main	Shape::Circle(k) => k,
# clash/shapes.vl
20:5	def	Circle(i64),
$ refs Shape::Dot
# clash/main.vl
45:16	pat	main	Shape::Dot => 0,
# clash/shapes.vl
21:5	def	Dot,
$ refs crate::shapes::Shape
# clash/main.vl
17:20	use	crate	use shapes::{Area, Shape, Square};
42:17	type	main	let shape = Shape::Circle(2);
44:9	type	main	Shape::Circle(k) => k,
45:9	type	main	Shape::Dot => 0,
# clash/shapes.vl
19:10	def	pub enum Shape {
$ refs a
# clash/main.vl
3:5	def	mod a;
15:5	mod	crate	use a::helper as a_helper;
33:13	mod	main	let p = a::Point { x: Point(n) };
$ def twice_generic
crate::twice_generic	clash/main.vl:26:4	fn	fn twice_generic<T: Area>(x: T) -> i64
$ callers twice_generic
# clash/main.vl
47:17	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
47:37	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
$ def UNIT
crate::shapes::UNIT	clash/shapes.vl:24:11	const	pub const UNIT: i64 = 1
$ def COUNT
crate::shapes::COUNT	clash/shapes.vl:25:16	static	pub static var COUNT: i64 = 0
$ def Side
crate::shapes::Side	clash/shapes.vl:26:10	type	pub type Side = i64
$ def Area
crate::shapes::Area	clash/shapes.vl:1:11	trait	pub trait Area
$ items geom
# crate::geom	clash/geom.vl
4	fn	pub fn Point(x: i64) -> i64
8	struct	pub struct V2
13	impl	impl V2
15	method	pub fn len(self) -> i64
20	impl	impl Add for V2
21	method	fn add(self, o: V2) -> V2
26	impl	impl Area for V2
27	method	fn area(self) -> i64
$ items crate
# crate	clash/main.vl
3	mod	mod a
4	mod	mod b
5	mod	mod geom
6	mod	mod shapes
7	mod	mod myvec
9	mod	mod sys
21	fn	fn printf(x: i64) -> i64
26	fn	fn twice_generic<T: Area>(x: T) -> i64
30	fn	fn main(gpa: Gpa) -> i32
$ items sys
# crate::sys	clash/main.vl
10	struct	pub struct SockaddrIn
# std::sys	<std>
14177	const	pub const SYS_EPERM: i32 = 1
14178	const	pub const SYS_ENOENT: i32 = 2
14179	const	pub const SYS_ESRCH: i32 = 3
14180	const	pub const SYS_EINTR: i32 = 4
14181	const	pub const SYS_EIO: i32 = 5
14182	const	pub const SYS_EBADF: i32 = 9
14183	const	pub const SYS_ECHILD: i32 = 10
14184	const	pub const SYS_ENOMEM: i32 = 12
14185	const	pub const SYS_EACCES: i32 = 13
14186	const	pub const SYS_EEXIST: i32 = 17
14187	const	pub const SYS_EXDEV: i32 = 18
14188	const	pub const SYS_ENOTDIR: i32 = 20
14189	const	pub const SYS_EISDIR: i32 = 21
14190	const	pub const SYS_EINVAL: i32 = 22
14191	const	pub const SYS_ENOSPC: i32 = 28
14192	const	pub const SYS_EROFS: i32 = 30
14193	const	pub const SYS_EPIPE: i32 = 32
14198	enum	pub enum SysErrorKind
14219	fn	pub fn sys_errno() -> i32
14225	fn	pub fn sys_set_errno(e: i32)
14231	fn	pub fn sys_errno_kind(e: i32) -> SysErrorKind
14265	fn	pub fn sys_strerror_into(e: i32, out: inout [u8]) -> i64
14278	fn	pub unsafe fn sys_cstr_view(p: *u8) -> [u8]
14305	struct	pub struct SysPath
14313	fn	pub fn sys_cpath(path: [u8]) -> Result<SysPath, i32>
14399	const	pub const SYS_O_RDONLY: i32 = 0
14400	const	pub const SYS_O_WRONLY: i32 = 1
14401	const	pub const SYS_O_RDWR: i32 = 2
14402	const	pub const SYS_SEEK_SET: i32 = 0
14403	const	pub const SYS_SEEK_CUR: i32 = 1
14404	const	pub const SYS_SEEK_END: i32 = 2
14414	fn	pub fn sys_open(path: [u8], flags: i32, mode: i32) -> Result<i32, i32>
14421	fn	pub fn sys_close(fd: i32) -> Result<(), i32>
14426	fn	pub fn sys_read(fd: i32, buf: inout [u8]) -> Result<i64, i32>
14432	fn	pub fn sys_write(fd: i32, buf: [u8]) -> Result<i64, i32>
14438	fn	pub fn sys_pread(fd: i32, buf: inout [u8], off: i64) -> Result<i64, i32>
14444	fn	pub fn sys_pwrite(fd: i32, buf: [u8], off: i64) -> Result<i64, i32>
14450	fn	pub fn sys_lseek(fd: i32, off: i64, whence: i32) -> Result<i64, i32>
14454	fn	pub fn sys_ftruncate(fd: i32, len: i64) -> Result<(), i32>
14458	fn	pub fn sys_fsync(fd: i32) -> Result<(), i32>
14462	fn	pub fn sys_mkdir(path: [u8], mode: i32) -> Result<(), i32>
14467	fn	pub fn sys_rmdir(path: [u8]) -> Result<(), i32>
14472	fn	pub fn sys_unlink(path: [u8]) -> Result<(), i32>
14477	fn	pub fn sys_rename(from: [u8], to: [u8]) -> Result<(), i32>
14483	fn	pub fn sys_dup(fd: i32) -> Result<i32, i32>
14489	fn	pub fn sys_dup2(fd: i32, to: i32) -> Result<i32, i32>
14494	fn	pub fn sys_pipe() -> Result<(i32, i32), i32>
14504	fn	pub fn sys_set_nonblocking(fd: i32, on: bool) -> Result<(), i32>
14514	fn	pub fn sys_set_cloexec(fd: i32, on: bool) -> Result<(), i32>
14524	fn	pub fn sys_isatty(fd: i32) -> bool
14532	struct	pub struct FileStat
14551	const	pub const SYS_S_IFMT: u32 = 0xf000
14552	const	pub const SYS_S_IFDIR: u32 = 0x4000
14553	const	pub const SYS_S_IFREG: u32 = 0x8000
14554	const	pub const SYS_S_IFLNK: u32 = 0xa000
14556	impl	impl FileStat
14557	method	pub fn is_dir(self) -> bool
14561	method	pub fn is_file(self) -> bool
14565	method	pub fn is_symlink(self) -> bool
14570	method	pub fn permissions(self) -> u32
14577	struct	pub struct StatMacos
14604	struct	pub struct StatLinux
14678	fn	pub fn sys_fstat(fd: i32) -> Result<FileStat, i32>
14686	fn	pub fn sys_stat(path: [u8]) -> Result<FileStat, i32>
14695	fn	pub fn sys_lstat(path: [u8]) -> Result<FileStat, i32>
14725	struct	pub struct DirentMacos
14736	struct	pub struct DirentLinux
14745	struct	pub struct SysDir
14753	struct	pub struct SysDirEntry
14759	const	pub const SYS_DT_UNKNOWN: u8 = 0
14760	const	pub const SYS_DT_FIFO: u8 = 1
14761	const	pub const SYS_DT_CHR: u8 = 2
14762	const	pub const SYS_DT_DIR: u8 = 4
14763	const	pub const SYS_DT_BLK: u8 = 6
14764	const	pub const SYS_DT_REG: u8 = 8
14765	const	pub const SYS_DT_LNK: u8 = 10
14766	const	pub const SYS_DT_SOCK: u8 = 12
14768	fn	pub fn sys_opendir(path: [u8]) -> Result<SysDir, i32>
14779	fn	pub fn sys_readdir_into(dir: inout SysDir, name: inout [u8; 256]) -> Result<Option<SysDirEntry>, i32>
14819	fn	pub fn sys_closedir(dir: inout SysDir) -> Result<(), i32>
14831	fn	pub fn sys_getcwd_into(buf: inout [u8]) -> Result<i64, i32>
14847	fn	pub fn sys_chdir(path: [u8]) -> Result<(), i32>
14868	fn	pub fn sys_environ() -> **u8
14873	fn	pub fn sys_env_count() -> i64
14888	fn	pub fn sys_env_at(i: i64) -> [u8]
14898	fn	pub fn sys_getenv(name: [u8]) -> Option<[u8]>
14915	fn	pub unsafe fn sys_setenv(name: [u8], value: [u8]) -> Result<(), i32>
14922	fn	pub unsafe fn sys_unsetenv(name: [u8]) -> Result<(), i32>
14956	const	pub const SYS_SIGHUP: i32 = 1
14957	const	pub const SYS_SIGINT: i32 = 2
14958	const	pub const SYS_SIGKILL: i32 = 9
14959	const	pub const SYS_SIGTERM: i32 = 15
14964	struct	pub struct SysSpawnActions
14970	fn	pub fn sys_spawn_actions() -> Result<SysSpawnActions, i32>
14981	impl	impl SysSpawnActions
14983	method	pub fn dup2(inout self, fd: i32, to: i32) -> Result<(), i32>
14993	method	pub fn close(inout self, fd: i32) -> Result<(), i32>
15002	method	pub fn free(inout self)
15018	fn	pub unsafe fn sys_spawn(prog: *u8, argv: [*u8], envp: [*u8], actions: *SysSpawnActions) -> Result<i32, i32>
15042	fn	pub fn sys_waitpid(pid: i32, nohang: bool) -> Result<(i32, i32), i32>
15052	fn	pub fn sys_exit_code(status: i32) -> Option<i32>
15057	fn	pub fn sys_exit_signal(status: i32) -> Option<i32>
15062	fn	pub fn sys_kill(pid: i32, sig: i32) -> Result<(), i32>
15066	fn	pub fn sys_getpid() -> i32
15117	struct	pub struct SysWinsize
15126	struct	pub struct SysTermios
15133	struct	pub struct SysPollFd
15139	const	pub const SYS_POLLIN: i16 = 1
15140	const	pub const SYS_POLLPRI: i16 = 2
15141	const	pub const SYS_POLLOUT: i16 = 4
15142	const	pub const SYS_POLLERR: i16 = 8
15143	const	pub const SYS_POLLHUP: i16 = 16
15144	const	pub const SYS_POLLNVAL: i16 = 32
15150	fn	pub fn sys_openpty(size: SysWinsize) -> Result<(i32, i32), i32>
15190	fn	pub unsafe fn sys_fork_exec_pty(tty: i32, path: *u8, argv: [*u8], envp: [*u8]) -> Result<i32, i32>
15221	fn	pub fn sys_set_winsize(fd: i32, size: SysWinsize) -> Result<(), i32>
15228	fn	pub fn sys_get_winsize(fd: i32) -> Result<SysWinsize, i32>
15236	fn	pub fn sys_tcgetattr(fd: i32) -> Result<SysTermios, i32>
15244	fn	pub fn sys_tcsetattr(fd: i32, t: SysTermios) -> Result<(), i32>
15251	fn	pub fn sys_make_raw(t: inout SysTermios)
15258	fn	pub fn sys_poll(fds: [SysPollFd], timeout_ms: i32) -> Result<i64, i32>
15280	struct	pub struct SysTimespec
15285	const	pub const SYS_CLOCK_REALTIME: i32 = 0
15289	fn	pub fn sys_clock_gettime(clock: i32) -> (i64, i64)
15299	fn	pub fn sys_nanosleep(secs: i64, nanos: i64, left: inout SysTimespec) -> Result<(), i32>
15306	fn	pub fn sys_getentropy(buf: inout [u8]) -> Result<(), i32>
$ def helpr
error query.no-match: no definition 'helpr'
try: volec query def crate::a::helper
try: volec query def crate::b::helper
try: volec query def std::cli::Arg.help
[exit 1]
$ refs MyVec
# clash/main.vl
18:12	use	crate	use myvec::Vec as MyVec;
39:16	init	main	var mine = MyVec { n: 0 };
# clash/myvec.vl
2:12	def	pub struct Vec {
6:6	type	myvec	impl Vec {
7:23	type	myvec::Vec::push	pub fn push(inout self, x: i64) {
11:16	type	myvec::Vec::len	pub fn len(self) -> i64 {
15:22	type	myvec::Vec::add	pub fn add(inout self, k: i64) {
note query.alias: 'MyVec' is an import alias in crate, for crate::myvec::Vec
$ refs a_helper
# clash/a.vl
2:8	def	pub fn helper() -> i64 {
# clash/main.vl
15:8	use	crate	use a::helper as a_helper;
32:13	call	main	let n = a_helper() + b::helper() + helper;
note query.alias: 'a_helper' is an import alias in crate, for crate::a::helper
$ items nosuch
error query.no-match: no module 'nosuch'
try: volec query items
[exit 1]
