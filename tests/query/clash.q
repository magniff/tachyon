## Names that clash (clash/): two modules with `helper`; a struct a::Point
## and a function geom::Point; `len` on two types (and std's); a trait's
## `add` and an inherent `add`; a local named `helper`; an alias import;
## std's Vec::push and a user Vec's push; c::printf and a user printf.
## (Nothing here prints a position in <C import>, whose line numbers
## depend on the host's headers.)
$ def helper
crate::a::helper	clash/a.tach:2:8	fn	pub fn helper() -> i64	effects: none
crate::b::helper	clash/b.tach:1:8	fn	pub fn helper() -> i64	effects: none
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
crate::a::helper	clash/a.tach:2:8	fn	pub fn helper() -> i64	effects: none
$ def Point
crate::a::Point	clash/a.tach:6:12	struct	pub struct Point
crate::geom::Point	clash/geom.tach:4:8	fn	pub fn Point(x: i64) -> i64	effects: none
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
crate::geom::V2::len	clash/geom.tach:15:12	method	pub fn len(self) -> i64	effects: none
crate::myvec::Vec::len	clash/myvec.tach:11:12	method	pub fn len(self) -> i64	effects: none
std::Vec::len	../../compiler/std/std.tach:194:12	method	pub fn len(self) -> i64
std::Buf::len	../../compiler/std/std.tach:496:12	method	pub fn len(self) -> i64
std::BinaryHeap::len	../../compiler/std/flat/collections.tach:192:12	method	pub fn len(self) -> i64
std::MinHeap::len	../../compiler/std/flat/collections.tach:288:12	method	pub fn len(self) -> i64
std::collections::hash_map::HashMap::len	../../compiler/std/collections/hash_map.tach:37:12	method	pub fn len(self) -> i64
std::collections::hash_set::HashSet::len	../../compiler/std/collections/hash_set.tach:35:12	method	pub fn len(self) -> i64
std::collections::raw_table::RawTable::len	../../compiler/std/collections/raw_table.tach:136:12	method	pub fn len(self) -> i64
std::collections::btree_node::BTreeRaw::len	../../compiler/std/collections/btree_node.tach:236:12	method	pub fn len(self) -> i64
std::collections::btree_map::BTreeMap::len	../../compiler/std/collections/btree_map.tach:25:12	method	pub fn len(self) -> i64
std::collections::btree_map::BTreeSet::len	../../compiler/std/collections/btree_map.tach:215:12	method	pub fn len(self) -> i64
$ refs V2::len
# clash/geom.tach
15:12	def	pub fn len(self) -> i64 {
# clash/main.tach
40:17	call	main	mine.push(v.len());
$ refs myvec::Vec::len
# clash/main.tach
47:74	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
# clash/myvec.tach
11:12	def	pub fn len(self) -> i64 {
$ def V2::add
<crate::geom::V2 as Add>::add	clash/geom.tach:21:8	method	fn add(self, o: V2) -> V2	effects: none
$ def Vec::add
crate::myvec::Vec::add	clash/myvec.tach:15:12	method	pub fn add(inout self, k: i64)	effects: none
$ refs '<V2 as Add>::add'
# clash/geom.tach
21:8	def	fn add(self, o: V2) -> V2 {
# clash/main.tach
35:13	call	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs '<crate::geom::V2 as Add>::add' --exact
# clash/geom.tach
21:8	def	fn add(self, o: V2) -> V2 {
# clash/main.tach
35:13	call	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs V2::add
# clash/geom.tach
21:8	def	fn add(self, o: V2) -> V2 {
# clash/main.tach
35:13	call	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs crate::myvec::Vec::add
# clash/main.tach
41:10	call	main	mine.add(1);
# clash/myvec.tach
15:12	def	pub fn add(inout self, k: i64) {
$ refs Area::area
# clash/geom.tach
27:8	def	-><geom::V2 as Area>::area	fn area(self) -> i64 {
# clash/main.tach
27:7	call	twice_generic	-><geom::V2 as Area>::area	x.area() + x.area()
27:7	call	twice_generic	-><shapes::Square as Area>::area	x.area() + x.area()
27:18	call	twice_generic	-><geom::V2 as Area>::area	x.area() + x.area()
27:18	call	twice_generic	-><shapes::Square as Area>::area	x.area() + x.area()
# clash/shapes.tach
2:8	def	->shapes::Area::area	fn area(self) -> i64;
5:14	call	shapes::Area::twice	-><geom::V2 as Area>::area	self.area() * 2
5:14	call	shapes::Area::twice	-><shapes::Square as Area>::area	self.area() * 2
14:8	def	-><shapes::Square as Area>::area	fn area(self) -> i64 {
$ refs Area::twice
# clash/main.tach
47:59	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
# clash/shapes.tach
4:8	def	fn twice(self) -> i64 {
$ show '<Square as Area>::area'
// <crate::shapes::Square as Area>::area	clash/shapes.tach:14-16	effects: none
    fn area(self) -> i64 {
        self.side * self.side
    }
$ refs crate::shapes::Area
# clash/geom.tach
1:20	use	geom	use crate::shapes::Area;
26:6	type	geom	impl Area for V2 {
# clash/main.tach
17:14	use	crate	use shapes::{Area, Shape, Square};
26:21	type	twice_generic	fn twice_generic<T: Area>(x: T) -> i64 {
# clash/shapes.tach
1:11	def	pub trait Area {
13:6	type	shapes	impl Area for Square {
$ def push
crate::myvec::Vec::push	clash/myvec.tach:7:12	method	pub fn push(inout self, x: i64)	effects: none
std::Vec::push	../../compiler/std/std.tach:275:12	method	pub fn push(inout self, x: sink T)
std::Buf::push	../../compiler/std/std.tach:500:12	method	pub fn push(inout self, b: u8)
std::BinaryHeap::push	../../compiler/std/flat/collections.tach:202:12	method	pub fn push(inout self, x: sink T)
std::MinHeap::push	../../compiler/std/flat/collections.tach:298:12	method	pub fn push(inout self, x: sink T)
std::unicode::GraphemeState::push	../../compiler/std/unicode/mod.tach:167:12	method	pub fn push(inout self, cp: u32) -> bool	effects: panic
std::unicode::ClusterWidth::push	../../compiler/std/unicode/mod.tach:396:12	method	pub fn push(inout self, cp: u32, p: u16)	effects: none
$ refs Vec::push --count
2	crate::myvec::Vec::push
25	std::Vec::push
$ callers crate::myvec::Vec::push
# clash/main.tach
40:10	call	main	mine.push(v.len());
$ refs crate::myvec::Vec::push
# clash/main.tach
40:10	call	main	mine.push(v.len());
# clash/myvec.tach
7:12	def	pub fn push(inout self, x: i64) {
$ refs geom::V2
# clash/geom.tach
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
# clash/main.tach
16:19	use	crate	use geom::{Point, V2};
35:13	init	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
35:33	init	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ callers printf
# clash/main.tach
47:82	call	main	->printf	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
49:12	call	main	->c::printf	c::printf(c"%d\n", total as i32);
$ refs crate::printf
# clash/main.tach
21:4	def	fn printf(x: i64) -> i64 {
47:82	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
$ show crate::printf
// crate::printf	clash/main.tach:20-23	effects: none
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
crate::twice_generic	clash/main.tach:26:4	fn	fn twice_generic<T: Area>(x: T) -> i64
$ callers twice_generic
# clash/main.tach
47:17	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
47:37	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
$ def UNIT
crate::shapes::UNIT	clash/shapes.tach:24:11	const	pub const UNIT: i64 = 1
$ def COUNT
crate::shapes::COUNT	clash/shapes.tach:25:16	static	pub static var COUNT: i64 = 0
$ def Side
crate::shapes::Side	clash/shapes.tach:26:10	type	pub type Side = i64
$ def Area
crate::shapes::Area	clash/shapes.tach:1:11	trait	pub trait Area
$ items geom
# crate::geom	clash/geom.tach
4	fn	pub fn Point(x: i64) -> i64
8	struct	pub struct V2
13	impl	impl V2
15	method	pub fn len(self) -> i64
20	impl	impl Add for V2
21	method	fn add(self, o: V2) -> V2
26	impl	impl Area for V2
27	method	fn area(self) -> i64
$ items crate
# crate	clash/main.tach
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
# crate::sys	clash/main.tach
10	struct	pub struct SockaddrIn
# std::sys	<std>
13313	const	pub const SYS_EPERM: i32 = 1
13314	const	pub const SYS_ENOENT: i32 = 2
13315	const	pub const SYS_ESRCH: i32 = 3
13316	const	pub const SYS_EINTR: i32 = 4
13317	const	pub const SYS_EIO: i32 = 5
13318	const	pub const SYS_EBADF: i32 = 9
13319	const	pub const SYS_ECHILD: i32 = 10
13320	const	pub const SYS_ENOMEM: i32 = 12
13321	const	pub const SYS_EACCES: i32 = 13
13322	const	pub const SYS_EEXIST: i32 = 17
13323	const	pub const SYS_EXDEV: i32 = 18
13324	const	pub const SYS_ENOTDIR: i32 = 20
13325	const	pub const SYS_EISDIR: i32 = 21
13326	const	pub const SYS_EINVAL: i32 = 22
13327	const	pub const SYS_ENOSPC: i32 = 28
13328	const	pub const SYS_EROFS: i32 = 30
13329	const	pub const SYS_EPIPE: i32 = 32
13334	enum	pub enum SysErrorKind
13355	fn	pub fn sys_errno() -> i32
13361	fn	pub fn sys_set_errno(e: i32)
13367	fn	pub fn sys_errno_kind(e: i32) -> SysErrorKind
13401	fn	pub fn sys_strerror_into(e: i32, out: inout [u8]) -> i64
13414	fn	pub unsafe fn sys_cstr_view(p: *u8) -> [u8]
13441	struct	pub struct SysPath
13448	fn	pub fn sys_cpath(path: [u8]) -> Result<SysPath, i32>
13463	impl	impl SysPath
13465	method	pub fn ptr(self) -> *u8
13538	const	pub const SYS_O_RDONLY: i32 = 0
13539	const	pub const SYS_O_WRONLY: i32 = 1
13540	const	pub const SYS_O_RDWR: i32 = 2
13541	const	pub const SYS_SEEK_SET: i32 = 0
13542	const	pub const SYS_SEEK_CUR: i32 = 1
13543	const	pub const SYS_SEEK_END: i32 = 2
13553	fn	pub fn sys_open(path: [u8], flags: i32, mode: i32) -> Result<i32, i32>
13560	fn	pub fn sys_close(fd: i32) -> Result<(), i32>
13565	fn	pub fn sys_read(fd: i32, buf: inout [u8]) -> Result<i64, i32>
13571	fn	pub fn sys_write(fd: i32, buf: [u8]) -> Result<i64, i32>
13577	fn	pub fn sys_pread(fd: i32, buf: inout [u8], off: i64) -> Result<i64, i32>
13583	fn	pub fn sys_pwrite(fd: i32, buf: [u8], off: i64) -> Result<i64, i32>
13589	fn	pub fn sys_lseek(fd: i32, off: i64, whence: i32) -> Result<i64, i32>
13593	fn	pub fn sys_ftruncate(fd: i32, len: i64) -> Result<(), i32>
13597	fn	pub fn sys_fsync(fd: i32) -> Result<(), i32>
13601	fn	pub fn sys_mkdir(path: [u8], mode: i32) -> Result<(), i32>
13606	fn	pub fn sys_rmdir(path: [u8]) -> Result<(), i32>
13611	fn	pub fn sys_unlink(path: [u8]) -> Result<(), i32>
13616	fn	pub fn sys_rename(from: [u8], to: [u8]) -> Result<(), i32>
13622	fn	pub fn sys_dup(fd: i32) -> Result<i32, i32>
13628	fn	pub fn sys_dup2(fd: i32, to: i32) -> Result<i32, i32>
13633	fn	pub fn sys_pipe() -> Result<(i32, i32), i32>
13643	fn	pub fn sys_set_nonblocking(fd: i32, on: bool) -> Result<(), i32>
13653	fn	pub fn sys_set_cloexec(fd: i32, on: bool) -> Result<(), i32>
13663	fn	pub fn sys_isatty(fd: i32) -> bool
13671	struct	pub struct FileStat
13690	const	pub const SYS_S_IFMT: u32 = 0xf000
13691	const	pub const SYS_S_IFDIR: u32 = 0x4000
13692	const	pub const SYS_S_IFREG: u32 = 0x8000
13693	const	pub const SYS_S_IFLNK: u32 = 0xa000
13695	impl	impl FileStat
13696	method	pub fn is_dir(self) -> bool
13700	method	pub fn is_file(self) -> bool
13704	method	pub fn is_symlink(self) -> bool
13709	method	pub fn permissions(self) -> u32
13716	struct	pub struct StatMacos
13743	struct	pub struct StatLinux
13817	fn	pub fn sys_fstat(fd: i32) -> Result<FileStat, i32>
13825	fn	pub fn sys_stat(path: [u8]) -> Result<FileStat, i32>
13834	fn	pub fn sys_lstat(path: [u8]) -> Result<FileStat, i32>
13864	struct	pub struct DirentMacos
13875	struct	pub struct DirentLinux
13884	struct	pub struct SysDir
13892	struct	pub struct SysDirEntry
13898	const	pub const SYS_DT_UNKNOWN: u8 = 0
13899	const	pub const SYS_DT_FIFO: u8 = 1
13900	const	pub const SYS_DT_CHR: u8 = 2
13901	const	pub const SYS_DT_DIR: u8 = 4
13902	const	pub const SYS_DT_BLK: u8 = 6
13903	const	pub const SYS_DT_REG: u8 = 8
13904	const	pub const SYS_DT_LNK: u8 = 10
13905	const	pub const SYS_DT_SOCK: u8 = 12
13907	fn	pub fn sys_opendir(path: [u8]) -> Result<SysDir, i32>
13918	fn	pub fn sys_readdir_into(dir: inout SysDir, name: inout [u8; 256]) -> Result<Option<SysDirEntry>, i32>
13958	fn	pub fn sys_closedir(dir: inout SysDir) -> Result<(), i32>
13970	fn	pub fn sys_getcwd_into(buf: inout [u8]) -> Result<i64, i32>
13986	fn	pub fn sys_chdir(path: [u8]) -> Result<(), i32>
14007	fn	pub fn sys_environ() -> **u8
14012	fn	pub fn sys_env_count() -> i64
14027	fn	pub fn sys_env_at(i: i64) -> [u8]
14037	fn	pub fn sys_getenv(name: [u8]) -> Option<[u8]>
14054	fn	pub unsafe fn sys_setenv(name: [u8], value: [u8]) -> Result<(), i32>
14061	fn	pub unsafe fn sys_unsetenv(name: [u8]) -> Result<(), i32>
14095	const	pub const SYS_SIGHUP: i32 = 1
14096	const	pub const SYS_SIGINT: i32 = 2
14097	const	pub const SYS_SIGKILL: i32 = 9
14098	const	pub const SYS_SIGTERM: i32 = 15
14103	struct	pub struct SysSpawnActions
14109	fn	pub fn sys_spawn_actions() -> Result<SysSpawnActions, i32>
14120	impl	impl SysSpawnActions
14122	method	pub fn dup2(inout self, fd: i32, to: i32) -> Result<(), i32>
14132	method	pub fn close(inout self, fd: i32) -> Result<(), i32>
14141	method	pub fn free(inout self)
14157	fn	pub unsafe fn sys_spawn(prog: *u8, argv: [*u8], envp: [*u8], actions: *SysSpawnActions) -> Result<i32, i32>
14181	fn	pub fn sys_waitpid(pid: i32, nohang: bool) -> Result<(i32, i32), i32>
14191	fn	pub fn sys_exit_code(status: i32) -> Option<i32>
14196	fn	pub fn sys_exit_signal(status: i32) -> Option<i32>
14201	fn	pub fn sys_kill(pid: i32, sig: i32) -> Result<(), i32>
14205	fn	pub fn sys_getpid() -> i32
14256	struct	pub struct SysWinsize
14265	struct	pub struct SysTermios
14272	struct	pub struct SysPollFd
14278	const	pub const SYS_POLLIN: i16 = 1
14279	const	pub const SYS_POLLPRI: i16 = 2
14280	const	pub const SYS_POLLOUT: i16 = 4
14281	const	pub const SYS_POLLERR: i16 = 8
14282	const	pub const SYS_POLLHUP: i16 = 16
14283	const	pub const SYS_POLLNVAL: i16 = 32
14289	fn	pub fn sys_openpty(size: SysWinsize) -> Result<(i32, i32), i32>
14329	fn	pub unsafe fn sys_fork_exec_pty(tty: i32, path: *u8, argv: [*u8], envp: [*u8]) -> Result<i32, i32>
14360	fn	pub fn sys_set_winsize(fd: i32, size: SysWinsize) -> Result<(), i32>
14367	fn	pub fn sys_get_winsize(fd: i32) -> Result<SysWinsize, i32>
14375	fn	pub fn sys_tcgetattr(fd: i32) -> Result<SysTermios, i32>
14383	fn	pub fn sys_tcsetattr(fd: i32, t: SysTermios) -> Result<(), i32>
14390	fn	pub fn sys_make_raw(t: inout SysTermios)
14397	fn	pub fn sys_poll(fds: [SysPollFd], timeout_ms: i32) -> Result<i64, i32>
14419	struct	pub struct SysTimespec
14424	const	pub const SYS_CLOCK_REALTIME: i32 = 0
14428	fn	pub fn sys_clock_gettime(clock: i32) -> (i64, i64)
14438	fn	pub fn sys_nanosleep(secs: i64, nanos: i64, left: inout SysTimespec) -> Result<(), i32>
14445	fn	pub fn sys_getentropy(buf: inout [u8]) -> Result<(), i32>
$ def helpr
error query.no-match: no definition 'helpr'
try: tachyonc query def crate::a::helper
try: tachyonc query def crate::b::helper
[exit 1]
$ refs MyVec
# clash/main.tach
18:12	use	crate	use myvec::Vec as MyVec;
39:16	init	main	var mine = MyVec { n: 0 };
# clash/myvec.tach
2:12	def	pub struct Vec {
6:6	type	myvec	impl Vec {
7:23	type	myvec::Vec::push	pub fn push(inout self, x: i64) {
11:16	type	myvec::Vec::len	pub fn len(self) -> i64 {
15:22	type	myvec::Vec::add	pub fn add(inout self, k: i64) {
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
