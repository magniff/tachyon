## The syntax of 0.15 parses (phase 0: the checking is to come, and the
## program has errors): items, the function using it shown, its parts
## found.
## A method #[derive] makes: the attribute answers (0.15).
$ items
crate	syntax015/main.tach	6
std	<std>	488
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
