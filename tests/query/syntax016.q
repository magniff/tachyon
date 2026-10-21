## The syntax of 0.16 parses and checks (phase 0: declarations are
## accepted, effects not inferred yet): items, the parts shown, the
## minimal `query effects`.
$ items
crate	syntax016/main.tach	10
std	<std>	579
std::ops	<std>	5
std::iter	<std>	67
std::slice	<std>	37
std::slice::unstable	<std>	16
std::slice::stable	<std>	22
std::slice::search	<std>	4
std::slice::algo	<std>	12
std::collections	<std>	12
std::collections::hash_map	<std>	27
std::collections::hash_set	<std>	18
std::collections::raw_table	<std>	46
std::collections::btree_node	<std>	56
std::collections::btree_map	<std>	45
std::collections::group	<std>	20
std::io	<std>	12
std::io::error	<std>	17
std::io::buffered	<std>	37
std::fmt	<std>	82
std::num	<std>	83
std::num::tables	<std>	4
std::convert	<std>	2
std::clone	<std>	1
std::random	<std>	17
std::sys	<std>	191
std::time	<std>	40
std::hash	<std>	6
std::hash::fold	<std>	26
std::hash::sip	<std>	14
std::hash::state	<std>	18
std::str	<std>	67
std::unicode	<std>	74
std::unicode::tables	<std>	27
std::objc	<std>	50
std::objc::foundation	<std>	67
std::gpu	<std>	140
std::gpu::hal	<std>	7
std::gpu::hal::metal	<std>	109
std::gpu::hal::metal::bindings	<std>	776
std::gpu::shader	<std>	25
std::gpu::types	<std>	51
std::gpu::types::BufferUsage	<std>	9
std::gpu::types::TextureUsage	<std>	5
std::gpu::types::ShaderStage	<std>	3
std::gpu::wgsl	<std>	30
std::gpu::wgsl::ir	<std>	267
std::gpu::wgsl::names	<std>	238
std::gpu::wgsl::lex	<std>	61
std::gpu::wgsl::front	<std>	95
std::gpu::wgsl::expr	<std>	39
std::gpu::wgsl::builtins	<std>	35
std::gpu::wgsl::entry	<std>	8
std::gpu::wgsl::bounds	<std>	10
std::gpu::wgsl::uniformity	<std>	1
std::gpu::wgsl::msl	<std>	81
std::gpu::wgsl::spirv	<std>	1
std::gpu::wgsl::interp	<std>	89
std::gpu::wgsl::dump	<std>	12
std::gpu::wgsl::job	<std>	13
std::gpu::wgsl::api	<std>	26
std::string	<std>	153
std::path	<std>	34
std::fs	<std>	59
std::env	<std>	21
std::process	<std>	36
std::arch	<std::arch>	3
std::arch::aarch64	<std::arch::aarch64>	138
std::arch::x86_64	<std::arch::x86_64>	6
std::arch::aarch64::raw	<std::arch::aarch64::raw>	110
std::arch::x86_64::raw	<std::arch::x86_64::raw>	6
$ show apply grow
// crate::apply	syntax016/main.tach:31-35
#[no_alloc]
#[no_io]
fn apply<F: Fn(i64) -> i64 + effects(panic)>(f: F, x: i64) -> i64 {
    f(x)
}
// crate::grow	syntax016/main.tach:37-40	effects: alloc(Gpa) panic
#[effects(alloc(Gpa), panic)]
fn grow(v: inout Vec<i64>) {
    v.push(1);
}
$ show crate::Pair
// crate::Pair	syntax016/main.tach:29-29
struct Pair<T, U = i64> { a: T, b: U }
$ refs Pair
# syntax016/main.tach
29:8	def	struct Pair<T, U = i64> { a: T, b: U }
44:12	type	main	let p: Pair<i64> = Pair { a: s.area(), b: unsafe { labs(-2) } };
44:24	init	main	let p: Pair<i64> = Pair { a: s.area(), b: unsafe { labs(-2) } };
$ effects apply grow main
apply<closure(i64) -> i64 at syntax016/main.tach:47:32>	none
crate::grow	alloc(Gpa) panic
crate::main	alloc(Gpa) io global panic unsafe
$ def Vec::new_in
std::Vec::new_in	../../compiler/std/std.tach:189:12	method	pub fn new_in(a: sink A) -> Vec<T, A>
