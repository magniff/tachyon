## The syntax of 0.15 parses (phase 0: the checking is to come, and the
## program has errors): items, the function using it shown, its parts
## found.
$ items
crate	syntax015/main.tach	6
std	<std>	285
warning query.program-errors: 5 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short syntax015/main.tach -c -o /dev/null
$ show main
// crate::main	syntax015/main.tach:25-31
fn main() -> Option<i64> {
    let x = half(8)?;
    let y = area(x, h: 2);
    let p = P { x, y };
    println(f"p = {p:?}, x = {x:>4}, {{y}} = {y:08x}");
    Some(p.x)
}
warning query.program-errors: 5 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short syntax015/main.tach -c -o /dev/null
$ grep 'f"' --code
# syntax015/main.tach
29:13	code	main	println(f"p = {p:?}, x = {x:>4}, {{y}} = {y:08x}");
warning query.program-errors: 5 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short syntax015/main.tach -c -o /dev/null
$ refs area
# syntax015/main.tach
13:4	def	fn area(w: i64, h: i64 = 1) -> i64 {
warning query.program-errors: 5 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short syntax015/main.tach -c -o /dev/null
$ type syntax015/main.tach:22:26
i64	x
warning query.program-errors: 5 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short syntax015/main.tach -c -o /dev/null
