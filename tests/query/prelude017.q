## (0.17) The prelude's new names load std only where a program uses
## them: declared by the program (a struct Buf, fn trim, let split), a
## field or a member, they do not.
$ items
crate	prelude017/main.tach	4
$ def trim
crate::trim	prelude017/main.tach:6:4	fn	fn trim(x: i64) -> i64	effects: none
$ items prelude017/uses.tach
crate	prelude017/uses.tach	1
std	<std>	486
$ def trim prelude017/uses.tach
std::trim	../../compiler/std/io.tach:102:8	fn	pub fn trim(s: [u8]) -> [u8]	effects: panic
