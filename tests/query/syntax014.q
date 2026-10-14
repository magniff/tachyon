## The syntax of 0.14 parses (phase 0: the checking is to come, and the
## program has errors): items, a closure-holding function shown.
$ items
crate	syntax014/main.tach	5
warning query.program-errors: 5 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short syntax014/main.tach -c -o /dev/null
$ show main
// crate::main	syntax014/main.tach:23-29
fn main() -> i64 {
    let k = 3;
    let add = |x: i64| x + k;
    let pair = move |(a, b): (i64, i64), _, mut c| -> i64 { a + b + c };
    let none = || k;
    apply(|x| x + 1, C { n: k })
}
warning query.program-errors: 5 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short syntax014/main.tach -c -o /dev/null
$ grep 'move' --code
# syntax014/main.tach
26:16	code	main	let pair = move |(a, b): (i64, i64), _, mut c| -> i64 { a + b + c };
warning query.program-errors: 5 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short syntax014/main.tach -c -o /dev/null
