## (0.17) The prelude's new names load std only where a program uses
## them: declared by the program (a struct Buf, fn trim, let split), a
## field or a member, they do not.
$ items
crate	prelude017/main.tach	4
$ def trim
crate::trim	prelude017/main.tach:6:4	fn	fn trim(x: i64) -> i64	effects: none
$ items prelude017/uses.tach
crate	prelude017/uses.tach	1
std	<std>	564
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
$ def trim prelude017/uses.tach
std::trim	../../compiler/std/flat/io.tach:28:8	fn	pub fn trim(s: [u8]) -> [u8]	effects: panic	views: views(s) declared
