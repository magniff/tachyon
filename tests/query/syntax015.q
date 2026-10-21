## The syntax of 0.15 parses (phase 0: the checking is to come, and the
## program has errors): items, the function using it shown, its parts
## found.
## A method #[derive] makes: the attribute answers (0.15).
$ items
crate	syntax015/main.tach	6
std	<std>	577
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
std::sys	<std>	192
std::time	<std>	40
std::hash	<std>	6
std::hash::fold	<std>	26
std::hash::sip	<std>	14
std::hash::state	<std>	18
std::str	<std>	67
std::unicode	<std>	74
std::unicode::tables	<std>	27
std::gpu	<std>	2
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
$ show main
// crate::main	syntax015/main.tach:25-31	effects: io global panic
fn main() -> Option<i64> {
    let x = half(8)?;
    let y = area(x, h: 2);
    let p = P { x, y };
    println(f"p = {p:?}, x = {x:>4}, {{y}} = {y:08x}");
    Some(p.x)
}
$ grep 'f"' --code
# syntax015/main.tach
29:13	code	main	println(f"p = {p:?}, x = {x:>4}, {{y}} = {y:08x}");
$ refs area
# syntax015/main.tach
13:4	def	fn area(w: i64, h: i64 = 1) -> i64 {
27:13	call	main	let y = area(x, h: 2);
$ type syntax015/main.tach:22:26
i64	x
$ def P::cmp
note query.derived: 'P::cmp' is derived, at syntax015/main.tach:6:14: #[derive] makes it; it has no source of its own
try: tachyonc query show crate::P
[exit 1]
