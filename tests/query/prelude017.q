## (0.17) The prelude's new names load std only where a program uses
## them: declared by the program (a struct Buf, fn trim, let split), a
## field or a member, they do not.
$ items
crate	prelude017/main.tach	4
$ def trim
crate::trim	prelude017/main.tach:6:4	fn	fn trim(x: i64) -> i64	effects: none
$ items prelude017/uses.tach
crate	prelude017/uses.tach	1
std	<std>	533
std::ops	<std>	5
std::iter	<std>	67
std::slice	<std>	37
std::slice::unstable	<std>	16
std::slice::stable	<std>	22
std::slice::search	<std>	4
std::slice::algo	<std>	12
std::collections	<std>	2
std::collections::hash_map	<std>	26
std::io	<std>	7
std::fmt	<std>	73
std::num	<std>	15
std::convert	<std>	2
std::clone	<std>	1
$ def trim prelude017/uses.tach
std::trim	../../compiler/std/flat/io.tach:28:8	fn	pub fn trim(s: [u8]) -> [u8]	effects: panic	views: views(s) declared
