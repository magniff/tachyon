## The syntax of 0.16 parses and checks (phase 0: declarations are
## accepted, effects not inferred yet): items, the parts shown, the
## minimal `query effects` (0.16 T1: the effects are inferred).
$ items
crate	syntax016/main.tach	10
std	<std>	420
$ show apply grow
// crate::apply	syntax016/main.tach:31-35
#[no_alloc]
#[no_io]
fn apply<F: Fn(i64) -> i64 + effects(panic)>(f: F, x: i64) -> i64 {
    f(x)
}
// crate::grow	syntax016/main.tach:37-40	effects: alloc(Gpa) panic diverge
#[effects(alloc(Gpa), panic, diverge)]
fn grow(v: *Vec<i64>) {
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
crate::grow	alloc(Gpa) panic diverge
crate::main	alloc(Gpa) io global panic diverge unsafe
$ def Vec::new_in
std::Vec::new_in	<std>:126:12	method	pub fn new_in(a: A) -> Vec<T, A>
