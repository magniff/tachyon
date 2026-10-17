## The syntax of 0.16 parses and checks (phase 0: declarations are
## accepted, effects not inferred yet): items, the parts shown, the
## minimal `query effects`.
$ items
crate	syntax016/main.tach	10
std	<std>	529
std::ops	<std>	5
std::iter	<std>	67
std::slice	<std>	15
std::collections	<std>	2
std::collections::hash_map	<std>	26
std::io	<std>	7
std::fmt	<std>	80
std::num	<std>	83
std::num::tables	<std>	4
std::convert	<std>	2
std::clone	<std>	1
$ show apply grow
// crate::apply	syntax016/main.tach:31-35
#[no_alloc]
#[no_io]
fn apply<F: Fn(i64) -> i64 + effects(panic)>(f: F, x: i64) -> i64 {
    f(x)
}
// crate::grow	syntax016/main.tach:37-40	effects: alloc(Gpa) panic
#[effects(alloc(Gpa), panic)]
fn grow(v: &mut Vec<i64>) {
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
std::Vec::new_in	../../compiler/std/std.tach:177:12	method	pub fn new_in(a: A) -> Vec<T, A>
