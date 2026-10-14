## Queries with closures (0.14; tests/query/closures/): references and
## calls inside a closure's body are the enclosing function's; a closure's
## type; a captured use typed as the local; a closure's function and
## environment are no items.
$ refs double
# closures/main.tach
5:4	def	fn double(x: i64) -> i64 {
15:24	call	main	let add = |x: i64| double(x) + k;
16:39	call	main	let n = apply(add, 1) + apply(|y| double(y), 2);
$ callers double --count
2
$ type closures/main.tach:15:15
closure(i64) -> i64 at closures/main.tach:15:15	|x: i64| double(x) + k
$ type closures/main.tach:15:36
i64	k
$ type closures/main.tach:16:46
i64	y
$ items
crate	closures/main.tach	3
$ unused
note query.empty: nothing unused
