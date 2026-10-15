## query callees (0.16): what a function calls, and names as a value; with
## --transitive, all it reaches, each with its depth and the caller it was
## reached from; --writes TABLE, the places in them that write or borrow
## TABLE, each with the chain of calls (calls016/).
$ callees add_and_sum
1	call	sum	calls016/main.tach:11
1	call	table::grow	calls016/table.tach:6
$ callees add_and_sum --transitive
1	call	sum	calls016/main.tach:11
1	call	table::grow	calls016/table.tach:6
2	call	table::peek	calls016/table.tach:19	via sum
2	call	table::put	calls016/table.tach:12	via table::grow
$ callees main --transitive --limit 3
1	call	add_and_sum	calls016/main.tach:6
1	call	apply	calls016/main.tach:21
1	call	sum	calls016/main.tach:11
note query.truncated: showing 3 of 19 callees
try: tachyonc query callees main --transitive --all
$ callees main
1	call	add_and_sum	calls016/main.tach:6
1	call	apply	calls016/main.tach:21
1	call	sum	calls016/main.tach:11
1	ref	twice	calls016/main.tach:25
1	call	std::print_int	<std>:2444
## main reaches a borrow of TABLE (put takes it by pointer) and a write of
## a field of it; sum reaches neither.
$ callees main --writes TABLE
# calls016/table.tach
8:14	borrow	main > add_and_sum > table::grow	put(&TABLE, x);
$ callees main --writes table::Table.count
# calls016/table.tach
15:14	write	main > add_and_sum > table::grow > table::put	(*t).count += 1;
$ callees sum --writes TABLE
note query.empty: sum reaches no write or borrow of table::TABLE (3 functions reached by calls and functions named as values)
$ callees sum --writes TABLE --count
0
## query refs of a local (0.16): FN::local, or FILE:LINE:COL at its
## declaration or a use; a shadowed local and the one shadowing it.
$ refs sum::total
# calls016/main.tach
12:13	def	let mut total = 0;
15:9	write	sum	total += i;
17:5	write	sum	total = total * 2;
17:13	read	sum	total = total * 2;
18:5	read	sum	total
$ refs sum::total --kind write
# calls016/main.tach
15:9	write	sum	total += i;
17:5	write	sum	total = total * 2;
$ refs calls016/main.tach:15:18
# calls016/main.tach
14:9	def	for i in 0..n {
15:18	read	sum	total += i;
$ refs main::total --count
5
$ refs main::nothing
error query.no-match: no definition 'main::nothing'
try: tachyonc query items
[exit 1]
