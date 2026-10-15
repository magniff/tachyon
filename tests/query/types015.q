## The checked syntax of 0.15 asked about (tests/query/types015/): the
## type of a `?` (its value's), of a widened value (as written, and what
## it is widened to), of a hole's expression; refs of a derived type
## leave out what #[derive] makes; a derived method is the attribute's.
## (Predicted from docs/design/errors-formatting.md before T1-T4 merged:
## check it once they have.)
$ type types015/main.tach:10:20
i64	half(v)?
$ type types015/main.tach:15:18 types015/main.tach:16:9
i32 (widened to i64)	n
i32 (widened to i64)	n
$ type types015/main.tach:23:20 types015/main.tach:23:37 types015/main.tach:23:53
P	p
i64	p.x + q.y
i32	n
$ refs P --in types015/main.tach
# types015/main.tach
3:8	def	struct P { x: i64, y: i64 }
20:13	init	main	let p = P { x: 1, y: 2 };
$ def P::clone P::cmp
note query.derived: 'P::clone' is derived, at types015/main.tach:2:26: #[derive] makes it; it has no source of its own
try: tachyonc query show crate::P
note query.derived: 'P::cmp' is derived, at types015/main.tach:2:14: #[derive] makes it; it has no source of its own
try: tachyonc query show crate::P
[exit 1]
$ refs quarter
# types015/main.tach
9:4	def	fn quarter(v: i64) -> Option<i64> {
24:11	call	main	match quarter(8) { Some(2) => (wide(n) - 14) as i32, _ => 1 }
