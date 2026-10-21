## The syntax of 0.14 parses (phase 0: the checking is to come, and the
## program has errors): items, a closure-holding function shown.
$ items
crate	syntax014/main.tach	5
warning query.program-errors: 1 error in the program; results may be incomplete
try: tachyonc --diagnostics=short syntax014/main.tach -c -o /dev/null
$ show main
// crate::main	syntax014/main.tach:24-30
fn main() -> i64 {
    let k = 3;
    let add = |x: i64| x + k;
    let pair = sink |(a, b): (i64, i64), _, var c| -> i64 { a + b + c };
    let none = || k;
    apply(|x| x + 1, C { n: k })
}
warning query.program-errors: 1 error in the program; results may be incomplete
try: tachyonc --diagnostics=short syntax014/main.tach -c -o /dev/null
$ grep 'sink' --code
# syntax014/main.tach
20:62	code	apply	fn apply<F: Fn(i64) -> i64, I: Source<Item = i64>>(f: F, it: sink I) -> I::Item {
27:16	code	main	let pair = sink |(a, b): (i64, i64), _, var c| -> i64 { a + b + c };
warning query.program-errors: 1 error in the program; results may be incomplete
try: tachyonc --diagnostics=short syntax014/main.tach -c -o /dev/null
