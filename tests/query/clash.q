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
crate::geom::V2::len	clash/geom.tach:15:12	method	pub fn len(self: &V2) -> i64	effects: none
crate::myvec::Vec::len	clash/myvec.tach:11:12	method	pub fn len(self: &Vec) -> i64	effects: none
std::Vec::len	../../compiler/std/std.tach:192:12	method	pub fn len(self: &Vec<T, A>) -> i64
std::Buf::len	../../compiler/std/std.tach:494:12	method	pub fn len(self: &Buf<A>) -> i64
std::BinaryHeap::len	../../compiler/std/flat/collections.tach:192:12	method	pub fn len(self: &BinaryHeap<T, A>) -> i64
std::MinHeap::len	../../compiler/std/flat/collections.tach:288:12	method	pub fn len(self: &MinHeap<T, A>) -> i64
std::collections::hash_map::HashMap::len	../../compiler/std/collections/hash_map.tach:37:12	method	pub fn len(self: &HashMap<K, V, A>) -> i64
std::collections::hash_set::HashSet::len	../../compiler/std/collections/hash_set.tach:35:12	method	pub fn len(self: &HashSet<T, A>) -> i64
std::collections::raw_table::RawTable::len	../../compiler/std/collections/raw_table.tach:136:12	method	pub fn len(self: &Self) -> i64
$ refs V2::len
# clash/geom.tach
15:12	def	pub fn len(self: &V2) -> i64 {
# clash/main.tach
40:17	call	main	mine.push(v.len());
$ refs myvec::Vec::len
# clash/main.tach
47:76	call	main	let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
# clash/myvec.tach
11:12	def	pub fn len(self: &Vec) -> i64 {
$ def V2::add
<crate::geom::V2 as Add>::add	clash/geom.tach:21:8	method	fn add(self: V2, o: V2) -> V2	effects: none
$ def Vec::add
crate::myvec::Vec::add	clash/myvec.tach:15:12	method	pub fn add(self: &mut Vec, k: i64)	effects: none
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
15:12	def	pub fn add(self: &mut Vec, k: i64) {
$ refs Area::area
# clash/geom.tach
27:8	def	-><geom::V2 as Area>::area	fn area(self: &V2) -> i64 {
# clash/main.tach
27:7	call	twice_generic	-><geom::V2 as Area>::area	x.area() + x.area()
27:7	call	twice_generic	-><shapes::Square as Area>::area	x.area() + x.area()
27:18	call	twice_generic	-><geom::V2 as Area>::area	x.area() + x.area()
27:18	call	twice_generic	-><shapes::Square as Area>::area	x.area() + x.area()
# clash/shapes.tach
2:8	def	->shapes::Area::area	fn area(self: &Self) -> i64;
5:14	call	shapes::Area::twice	-><geom::V2 as Area>::area	self.area() * 2
5:14	call	shapes::Area::twice	-><shapes::Square as Area>::area	self.area() * 2
14:8	def	-><shapes::Square as Area>::area	fn area(self: &Square) -> i64 {
$ refs Area::twice
# clash/main.tach
47:61	call	main	let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
# clash/shapes.tach
4:8	def	fn twice(self: &Self) -> i64 {
$ show '<Square as Area>::area'
// <crate::shapes::Square as Area>::area	clash/shapes.tach:14-16	effects: none
    fn area(self: &Square) -> i64 {
        self.side * self.side
    }
$ refs crate::shapes::Area
# clash/geom.tach
1:20	use	geom	use crate::shapes::Area;
26:6	type	geom	impl Area for V2 {
# clash/main.tach
17:14	use	crate	use shapes::{Area, Shape, Square};
26:21	type	twice_generic	fn twice_generic<T: Area>(x: &T) -> i64 {
# clash/shapes.tach
1:11	def	pub trait Area {
13:6	type	shapes	impl Area for Square {
$ def push
crate::myvec::Vec::push	clash/myvec.tach:7:12	method	pub fn push(self: &mut Vec, x: i64)	effects: none
std::Vec::push	../../compiler/std/std.tach:273:12	method	pub fn push(self: &mut Vec<T, A>, x: T)
std::Buf::push	../../compiler/std/std.tach:498:12	method	pub fn push(self: &mut Buf<A>, b: u8)
std::BinaryHeap::push	../../compiler/std/flat/collections.tach:202:12	method	pub fn push(self: &mut BinaryHeap<T, A>, x: T)
std::MinHeap::push	../../compiler/std/flat/collections.tach:298:12	method	pub fn push(self: &mut MinHeap<T, A>, x: T)
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
7:12	def	pub fn push(self: &mut Vec, x: i64) {
$ refs geom::V2
# clash/geom.tach
8:12	def	pub struct V2 {
13:6	type	geom	impl V2 {
15:23	type	geom::V2::len	pub fn len(self: &V2) -> i64 {
20:14	type	geom	impl Add for V2 {
21:18	type	<geom::V2 as Add>::add	fn add(self: V2, o: V2) -> V2 {
21:25	type	<geom::V2 as Add>::add	fn add(self: V2, o: V2) -> V2 {
21:32	type	<geom::V2 as Add>::add	fn add(self: V2, o: V2) -> V2 {
22:9	init	<geom::V2 as Add>::add	V2 { x: self.x + o.x, y: self.y + o.y }
26:15	type	geom	impl Area for V2 {
27:20	type	<geom::V2 as Area>::area	fn area(self: &V2) -> i64 {
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
crate::twice_generic	clash/main.tach:26:4	fn	fn twice_generic<T: Area>(x: &T) -> i64
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
15	method	pub fn len(self: &V2) -> i64
20	impl	impl Add for V2
21	method	fn add(self: V2, o: V2) -> V2
26	impl	impl Area for V2
27	method	fn area(self: &V2) -> i64
$ items crate
# crate	clash/main.tach
3	mod	mod a
4	mod	mod b
5	mod	mod geom
6	mod	mod shapes
7	mod	mod myvec
9	mod	mod sys
21	fn	fn printf(x: i64) -> i64
26	fn	fn twice_generic<T: Area>(x: &T) -> i64
30	fn	fn main(gpa: Gpa) -> i32
$ items sys
# crate::sys	clash/main.tach
10	struct	pub struct SockaddrIn
# std::sys	<std>
12031	const	pub const SYS_EPERM: i32 = 1
12032	const	pub const SYS_ENOENT: i32 = 2
12033	const	pub const SYS_ESRCH: i32 = 3
12034	const	pub const SYS_EINTR: i32 = 4
12035	const	pub const SYS_EIO: i32 = 5
12036	const	pub const SYS_EBADF: i32 = 9
12037	const	pub const SYS_ECHILD: i32 = 10
12038	const	pub const SYS_ENOMEM: i32 = 12
12039	const	pub const SYS_EACCES: i32 = 13
12040	const	pub const SYS_EEXIST: i32 = 17
12041	const	pub const SYS_EXDEV: i32 = 18
12042	const	pub const SYS_ENOTDIR: i32 = 20
12043	const	pub const SYS_EISDIR: i32 = 21
12044	const	pub const SYS_EINVAL: i32 = 22
12045	const	pub const SYS_ENOSPC: i32 = 28
12046	const	pub const SYS_EROFS: i32 = 30
12047	const	pub const SYS_EPIPE: i32 = 32
12052	enum	pub enum SysErrorKind
12073	fn	pub fn sys_errno() -> i32
12079	fn	pub fn sys_set_errno(e: i32)
12085	fn	pub fn sys_errno_kind(e: i32) -> SysErrorKind
12119	fn	pub fn sys_strerror_into(e: i32, out: &mut [u8]) -> i64
12132	fn	pub unsafe fn sys_cstr_view(p: *u8) -> [u8]
12159	struct	pub struct SysPath
12166	fn	pub fn sys_cpath(path: [u8]) -> Result<SysPath, i32>
12181	impl	impl SysPath
12183	method	pub fn ptr(self: &SysPath) -> *u8
12256	const	pub const SYS_O_RDONLY: i32 = 0
12257	const	pub const SYS_O_WRONLY: i32 = 1
12258	const	pub const SYS_O_RDWR: i32 = 2
12259	const	pub const SYS_SEEK_SET: i32 = 0
12260	const	pub const SYS_SEEK_CUR: i32 = 1
12261	const	pub const SYS_SEEK_END: i32 = 2
12271	fn	pub fn sys_open(path: [u8], flags: i32, mode: i32) -> Result<i32, i32>
12278	fn	pub fn sys_close(fd: i32) -> Result<(), i32>
12283	fn	pub fn sys_read(fd: i32, buf: &mut [u8]) -> Result<i64, i32>
12289	fn	pub fn sys_write(fd: i32, buf: [u8]) -> Result<i64, i32>
12295	fn	pub fn sys_pread(fd: i32, buf: &mut [u8], off: i64) -> Result<i64, i32>
12301	fn	pub fn sys_pwrite(fd: i32, buf: [u8], off: i64) -> Result<i64, i32>
12307	fn	pub fn sys_lseek(fd: i32, off: i64, whence: i32) -> Result<i64, i32>
12311	fn	pub fn sys_ftruncate(fd: i32, len: i64) -> Result<(), i32>
12315	fn	pub fn sys_fsync(fd: i32) -> Result<(), i32>
12319	fn	pub fn sys_mkdir(path: [u8], mode: i32) -> Result<(), i32>
12324	fn	pub fn sys_rmdir(path: [u8]) -> Result<(), i32>
12329	fn	pub fn sys_unlink(path: [u8]) -> Result<(), i32>
12334	fn	pub fn sys_rename(from: [u8], to: [u8]) -> Result<(), i32>
12340	fn	pub fn sys_dup(fd: i32) -> Result<i32, i32>
12346	fn	pub fn sys_dup2(fd: i32, to: i32) -> Result<i32, i32>
12351	fn	pub fn sys_pipe() -> Result<(i32, i32), i32>
12361	fn	pub fn sys_set_nonblocking(fd: i32, on: bool) -> Result<(), i32>
12371	fn	pub fn sys_set_cloexec(fd: i32, on: bool) -> Result<(), i32>
12381	fn	pub fn sys_isatty(fd: i32) -> bool
12389	struct	pub struct FileStat
12408	const	pub const SYS_S_IFMT: u32 = 0xf000
12409	const	pub const SYS_S_IFDIR: u32 = 0x4000
12410	const	pub const SYS_S_IFREG: u32 = 0x8000
12411	const	pub const SYS_S_IFLNK: u32 = 0xa000
12413	impl	impl FileStat
12414	method	pub fn is_dir(self: &FileStat) -> bool
12418	method	pub fn is_file(self: &FileStat) -> bool
12422	method	pub fn is_symlink(self: &FileStat) -> bool
12427	method	pub fn permissions(self: &FileStat) -> u32
12434	struct	pub struct StatMacos
12461	struct	pub struct StatLinux
12535	fn	pub fn sys_fstat(fd: i32) -> Result<FileStat, i32>
12543	fn	pub fn sys_stat(path: [u8]) -> Result<FileStat, i32>
12552	fn	pub fn sys_lstat(path: [u8]) -> Result<FileStat, i32>
12582	struct	pub struct DirentMacos
12593	struct	pub struct DirentLinux
12602	struct	pub struct SysDir
12610	struct	pub struct SysDirEntry
12616	const	pub const SYS_DT_UNKNOWN: u8 = 0
12617	const	pub const SYS_DT_FIFO: u8 = 1
12618	const	pub const SYS_DT_CHR: u8 = 2
12619	const	pub const SYS_DT_DIR: u8 = 4
12620	const	pub const SYS_DT_BLK: u8 = 6
12621	const	pub const SYS_DT_REG: u8 = 8
12622	const	pub const SYS_DT_LNK: u8 = 10
12623	const	pub const SYS_DT_SOCK: u8 = 12
12625	fn	pub fn sys_opendir(path: [u8]) -> Result<SysDir, i32>
12636	fn	pub fn sys_readdir_into(dir: &mut SysDir, name: &mut [u8; 256]) -> Result<Option<SysDirEntry>, i32>
12676	fn	pub fn sys_closedir(dir: &mut SysDir) -> Result<(), i32>
12688	fn	pub fn sys_getcwd_into(buf: &mut [u8]) -> Result<i64, i32>
12704	fn	pub fn sys_chdir(path: [u8]) -> Result<(), i32>
12725	fn	pub fn sys_environ() -> **u8
12730	fn	pub fn sys_env_count() -> i64
12745	fn	pub fn sys_env_at(i: i64) -> [u8]
12755	fn	pub fn sys_getenv(name: [u8]) -> Option<[u8]>
12772	fn	pub unsafe fn sys_setenv(name: [u8], value: [u8]) -> Result<(), i32>
12779	fn	pub unsafe fn sys_unsetenv(name: [u8]) -> Result<(), i32>
12813	const	pub const SYS_SIGHUP: i32 = 1
12814	const	pub const SYS_SIGINT: i32 = 2
12815	const	pub const SYS_SIGKILL: i32 = 9
12816	const	pub const SYS_SIGTERM: i32 = 15
12821	struct	pub struct SysSpawnActions
12827	fn	pub fn sys_spawn_actions() -> Result<SysSpawnActions, i32>
12838	impl	impl SysSpawnActions
12840	method	pub fn dup2(self: &mut SysSpawnActions, fd: i32, to: i32) -> Result<(), i32>
12850	method	pub fn close(self: &mut SysSpawnActions, fd: i32) -> Result<(), i32>
12859	method	pub fn free(self: &mut SysSpawnActions)
12875	fn	pub unsafe fn sys_spawn(prog: *u8, argv: [*u8], envp: [*u8], actions: *SysSpawnActions) -> Result<i32, i32>
12899	fn	pub fn sys_waitpid(pid: i32, nohang: bool) -> Result<(i32, i32), i32>
12909	fn	pub fn sys_exit_code(status: i32) -> Option<i32>
12914	fn	pub fn sys_exit_signal(status: i32) -> Option<i32>
12919	fn	pub fn sys_kill(pid: i32, sig: i32) -> Result<(), i32>
12923	fn	pub fn sys_getpid() -> i32
12974	struct	pub struct SysWinsize
12983	struct	pub struct SysTermios
12990	struct	pub struct SysPollFd
12996	const	pub const SYS_POLLIN: i16 = 1
12997	const	pub const SYS_POLLPRI: i16 = 2
12998	const	pub const SYS_POLLOUT: i16 = 4
12999	const	pub const SYS_POLLERR: i16 = 8
13000	const	pub const SYS_POLLHUP: i16 = 16
13001	const	pub const SYS_POLLNVAL: i16 = 32
13007	fn	pub fn sys_openpty(size: SysWinsize) -> Result<(i32, i32), i32>
13047	fn	pub unsafe fn sys_fork_exec_pty(tty: i32, path: *u8, argv: [*u8], envp: [*u8]) -> Result<i32, i32>
13078	fn	pub fn sys_set_winsize(fd: i32, size: SysWinsize) -> Result<(), i32>
13085	fn	pub fn sys_get_winsize(fd: i32) -> Result<SysWinsize, i32>
13093	fn	pub fn sys_tcgetattr(fd: i32) -> Result<SysTermios, i32>
13101	fn	pub fn sys_tcsetattr(fd: i32, t: &SysTermios) -> Result<(), i32>
13108	fn	pub fn sys_make_raw(t: &mut SysTermios)
13115	fn	pub fn sys_poll(fds: [SysPollFd], timeout_ms: i32) -> Result<i64, i32>
13137	struct	pub struct SysTimespec
13142	const	pub const SYS_CLOCK_REALTIME: i32 = 0
13146	fn	pub fn sys_clock_gettime(clock: i32) -> (i64, i64)
13156	fn	pub fn sys_nanosleep(secs: i64, nanos: i64, left: &mut SysTimespec) -> Result<(), i32>
13163	fn	pub fn sys_getentropy(buf: &mut [u8]) -> Result<(), i32>
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
7:28	type	myvec::Vec::push	pub fn push(self: &mut Vec, x: i64) {
11:23	type	myvec::Vec::len	pub fn len(self: &Vec) -> i64 {
15:27	type	myvec::Vec::add	pub fn add(self: &mut Vec, k: i64) {
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
