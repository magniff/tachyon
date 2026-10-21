## The syntax of 0.18 parses (phase 0: clauses, invariants, distinct
## types and test attributes are read and kept, not checked): the items,
## an item shown with its clauses, a distinct type, test functions.
$ items
crate	syntax018/main.tach	14
std	<std>	564
crate::tests	syntax018/main.tach	1
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
std::io	<std>	7
std::fmt	<std>	80
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
std::gpu::shader	<std>	30
std::gpu::shader::ir	<std>	267
std::gpu::shader::names	<std>	238
std::gpu::shader::lex	<std>	61
std::gpu::shader::front	<std>	95
std::gpu::shader::expr	<std>	38
std::gpu::shader::builtins	<std>	35
std::gpu::shader::entry	<std>	8
std::gpu::shader::bounds	<std>	10
std::gpu::shader::uniformity	<std>	1
std::gpu::shader::msl	<std>	81
std::gpu::shader::spirv	<std>	1
std::gpu::shader::interp	<std>	89
std::gpu::shader::dump	<std>	12
std::gpu::shader::job	<std>	13
std::gpu::shader::translate	<std>	25
std::arch	<std::arch>	3
std::arch::aarch64	<std::arch::aarch64>	138
std::arch::x86_64	<std::arch::x86_64>	6
std::arch::aarch64::raw	<std::arch::aarch64::raw>	110
std::arch::x86_64::raw	<std::arch::x86_64::raw>	6
$ show crate::push Stack Percent
// crate::push	syntax018/main.tach:19-27	effects: panic
fn push(s: &mut Stack, x: i64)
    requires s.len < s.max else "push on a full stack"
    ensures s.len == old(s.len) + 1
{
    unsafe {
        (*s).items[(*s).len] = x;
        (*s).len += 1;
    }
}
// crate::Stack	syntax018/main.tach:10-11
struct Stack { items: [i64; 8], len: i64, max: i64 }
invariant self.len <= self.max else "a stack holds at most max items"
// crate::Percent	syntax018/main.tach:17-17
type Percent = distinct i64 invariant 0 <= self && self <= 100;
$ def NodeId any_id tests::two
crate::NodeId	syntax018/main.tach:16:6	type	type NodeId = distinct i64
crate::any_id	syntax018/main.tach:58:4	fn	fn any_id(n: i64)	effects: none
crate::tests::two	syntax018/main.tach:66:8	fn	fn two()	effects: none
$ refs NodeId
# syntax018/main.tach
16:6	def	type NodeId = distinct i64;
47:15	type	next_id	fn next_id(n: NodeId) -> NodeId requires n >= 0 {
47:26	type	next_id	fn next_id(n: NodeId) -> NodeId requires n >= 0 {
78:13	type	main	let id: NodeId = 11;
