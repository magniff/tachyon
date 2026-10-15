## The planning queries and lint (tests/refactor/plan/).
$ query stats
37	8	lang.tach
28	6	util.tach
16	1	main.tach
81	15	total
$ query stats --over 30
37	8	lang.tach	over
28	6	util.tach
16	1	main.tach
81	15	total
note query.over: 1 file over 30 lines
try: tachyonc query deps crate::lang --max-lines 30
$ query stats util
# crate::util	util.tach	28 lines	6 items
5	enum	Shape
4	struct	Pair
3	fn	square
3	fn	times
3	fn	cube
3	fn	unused_helper
$ query stats lang.tach
# lang.tach	37 lines	8 items
5	fn	parse
4	struct	Token
3	fn	lex_digit
3	fn	lex
3	fn	check
3	fn	report
3	fn	describe
3	fn	summary
## lang has two parts that share nothing: two groups of at most 12 lines.
$ query deps lang --max-lines 12
# crate::lang	lang.tach	27 lines	8 items
Token	4	-	lex_digit lex parse check report describe summary	2
lex_digit	3	Token	lex	0
lex	3	Token lex_digit	parse	0
parse	5	Token lex check	-	2
check	3	Token	parse	0
report	3	Token describe	summary	0
describe	3	Token	report summary	0
summary	3	Token report describe	-	0
groups	3	at most 12 lines	8 references between them
group 1	10	Token lex_digit check
group 2	9	report describe summary
group 3	8	lex parse
## 3 groups of at most 12 lines, 8 references between them
$ query deps util
# crate::util	util.tach	21 lines	6 items
square	3	times	cube	2
times	3	-	square cube	0
cube	3	square times	-	1
unused_helper	3	-	-	0
Shape	5	-	-	5
Pair	4	-	-	0
groups	1	at most 1000 lines	0 references between them
group 1	21	square times cube unused_helper Shape Pair
## 1 group of at most 1000 lines, 0 references between them
$ query unused
lang::Token	main.tach:6:19	import
crate::util::cube	lang.tach:2:18	import
crate::lang::summary	lang.tach:35:4	fn
crate::util::cube	util.tach:11:8	fn
crate::util::unused_helper	util.tach:15:8	fn
crate::util::Shape::Dot	util.tach:21:5	variant
crate::util::Shape::Line	util.tach:22:5	variant
crate::util::Pair	util.tach:25:12	struct
$ query unused lang
crate::util::cube	lang.tach:2:18	import
crate::lang::summary	lang.tach:35:4	fn
$ query impact square
crate::util::square	util.tach:3:8	fn	pub fn square(x: i64) -> i64	effects: none
util.tach	1	0	util::cube
main.tach	1	1	crate main
total	2	1	2 files
$ query impact lang::Token
crate::lang::Token	lang.tach:4:12	struct	pub struct Token
lang.tach	0	10	lang::lex_digit lang::lex lang::parse lang::check lang::report lang::describe lang::summary
main.tach	0	1	crate
total	0	11	2 files
$ lint --max-lines 30
error lint.max-lines: lang.tach: 37 lines (at most 30)
try: tachyonc query deps crate::lang --max-lines 30
[exit 1]
$ lint --max-lines 1000
$ lint
error lint.usage: lint needs --max-lines N
try: tachyonc lint --max-lines 1000
[exit 2]
