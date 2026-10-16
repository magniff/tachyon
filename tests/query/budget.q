## The output budget and the diagnostics (budget/): 70 calls of `bump`
## in two files, six `size` functions, a line longer than 100 bytes; and
## every usage error.
$ refs bump
budget/main.tach	47
budget/util.tach	24
note query.truncated: 71 refs in 2 files
try: tachyonc query refs bump --in budget/main.tach
try: tachyonc query refs bump --limit 60
try: tachyonc query refs bump --all
$ refs bump --count
71
$ callers bump --all --in main.tach
# budget/main.tach
15:16	call	many	t += util::bump(0);
16:16	call	many	t += util::bump(1);
17:16	call	many	t += util::bump(2);
18:16	call	many	t += util::bump(3);
19:16	call	many	t += util::bump(4);
20:16	call	many	t += util::bump(5);
21:16	call	many	t += util::bump(6);
22:16	call	many	t += util::bump(7);
23:16	call	many	t += util::bump(8);
24:16	call	many	t += util::bump(9);
25:16	call	many	t += util::bump(10);
26:16	call	many	t += util::bump(11);
27:16	call	many	t += util::bump(12);
28:16	call	many	t += util::bump(13);
29:16	call	many	t += util::bump(14);
30:16	call	many	t += util::bump(15);
31:16	call	many	t += util::bump(16);
32:16	call	many	t += util::bump(17);
33:16	call	many	t += util::bump(18);
34:16	call	many	t += util::bump(19);
35:16	call	many	t += util::bump(20);
36:16	call	many	t += util::bump(21);
37:16	call	many	t += util::bump(22);
38:16	call	many	t += util::bump(23);
39:16	call	many	t += util::bump(24);
40:16	call	many	t += util::bump(25);
41:16	call	many	t += util::bump(26);
42:16	call	many	t += util::bump(27);
43:16	call	many	t += util::bump(28);
44:16	call	many	t += util::bump(29);
45:16	call	many	t += util::bump(30);
46:16	call	many	t += util::bump(31);
47:16	call	many	t += util::bump(32);
48:16	call	many	t += util::bump(33);
49:16	call	many	t += util::bump(34);
50:16	call	many	t += util::bump(35);
51:16	call	many	t += util::bump(36);
52:16	call	many	t += util::bump(37);
53:16	call	many	t += util::bump(38);
54:16	call	many	t += util::bump(39);
59:11	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:27	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:43	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:59	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:75	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:91	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:107	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
$ refs bump --in util.tach
# budget/util.tach
1:8	def	pub fn bump(x: i64) -> i64 {
7:10	call	util::more	t += bump(0);
8:10	call	util::more	t += bump(1);
9:10	call	util::more	t += bump(2);
10:10	call	util::more	t += bump(3);
11:10	call	util::more	t += bump(4);
12:10	call	util::more	t += bump(5);
13:10	call	util::more	t += bump(6);
14:10	call	util::more	t += bump(7);
15:10	call	util::more	t += bump(8);
16:10	call	util::more	t += bump(9);
17:10	call	util::more	t += bump(10);
18:10	call	util::more	t += bump(11);
19:10	call	util::more	t += bump(12);
20:10	call	util::more	t += bump(13);
21:10	call	util::more	t += bump(14);
22:10	call	util::more	t += bump(15);
23:10	call	util::more	t += bump(16);
24:10	call	util::more	t += bump(17);
25:10	call	util::more	t += bump(18);
26:10	call	util::more	t += bump(19);
27:10	call	util::more	t += bump(20);
28:10	call	util::more	t += bump(21);
29:10	call	util::more	t += bump(22);
$ refs bump --in crate --limit 3
# budget/main.tach
15:16	call	many	t += util::bump(0);
16:16	call	many	t += util::bump(1);
17:16	call	many	t += util::bump(2);
note query.truncated: showing 3 of 71 refs
try: tachyonc query refs bump --in budget/main.tach
try: tachyonc query refs bump --in crate --all
$ refs bump --limit 2
# budget/main.tach
15:16	call	many	t += util::bump(0);
16:16	call	many	t += util::bump(1);
note query.truncated: showing 2 of 71 refs
try: tachyonc query refs bump --in budget/main.tach
try: tachyonc query refs bump --all
$ refs bump --in nosuch
error query.bad-in: no file, module or item 'nosuch' in the program
try: tachyonc query refs bump
[exit 1]
$ callers m2::size
note query.empty: 0 calls
$ callers m2::size --count
0
$ refs size --count
2	crate::m1::size
1	crate::m2::size
1	crate::m3::size
1	crate::m4::size
1	crate::m5::size
1	crate::m6::size
$ show size
crate::m1::size
crate::m2::size
crate::m3::size
crate::m4::size
crate::m5::size
crate::m6::size
error query.ambiguous: 6 definitions match 'size'; showing paths only
try: tachyonc query show crate::m1::size
[exit 1]
$ show m2::size
// crate::m2::size	budget/main.tach:7-7	effects: none
mod m2 { pub fn size() -> i64 { 2 } }
$ callers long_line
# budget/main.tach
63:15	call	main	(many() + long_line() + m1::size()) as i32
$ refs bump --in long_line
# budget/main.tach
59:11	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:27	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:43	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:59	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:75	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:91	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:107	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
$ refs bump --bogus
error query.usage: unknown option '--bogus'
try: tachyonc query refs bump
[exit 2]
$ refs bump --limit
error query.usage: --limit needs a number
try: tachyonc query refs bump --limit 60
[exit 2]
$ refs bump --limit x
error query.usage: --limit needs a number
try: tachyonc query refs bump --limit 60
[exit 2]
$ refs bump --in
error query.usage: --in needs a FILE or MODULE
try: tachyonc query refs bump
[exit 2]
$ refs bump budget/main.tach extra
error query.usage: unexpected argument 'extra'
try: tachyonc query refs bump budget/main.tach
[exit 2]
$ refs bump nosuch.tach
error query.bad-root: cannot read 'nosuch.tach'
try: tachyonc query refs bump
[exit 2]
$ defs bump
error query.usage: unknown command 'defs'
try: tachyonc query def bump
[exit 2]
$ items mm1
error query.no-match: no module 'mm1'
try: tachyonc query items crate::m1
[exit 1]
$ def util::bumpp
error query.no-match: no definition 'util::bumpp'
try: tachyonc query def crate::util::bump
[exit 1]
$ def utill::bump
error query.no-match: no definition 'utill::bump'
try: tachyonc query def crate::util::bump
[exit 1]
$ 
error query.usage: no command
try: tachyonc query items
[exit 2]
$ --help
usage: tachyonc query def|show NAME... [--root ROOT] [--exact] [--with-comments]
       tachyonc query show FILE.tach | MODULE::use | MODULE::header | MODULE::extern
       tachyonc query context NAME...|MODULE [--budget TOKENS]   (source, calls, types, callers)
       tachyonc query text FILE[:A[-B]]...
       tachyonc query diff
       tachyonc query refs|callers NAME... [--exact] [--count] [--in FILE|MODULE|ITEM] [--limit N] [--all]
       tachyonc query callees FN... [--transitive] [--writes TABLE] [--count] [--limit N] [--all]
       tachyonc query items [MODULE...] [--comments]
       tachyonc query show MODULE::section TITLE
       tachyonc query grep PATTERN... [--in FILE|MODULE|ITEM] [--code] [--comments] [--strings] [--word] [--count] [--limit N] [--all]
       tachyonc query type FILE:LINE[:COL]...
       tachyonc query stats [MODULE|FILE] [--over N] [--all]
       tachyonc query deps MODULE [--max-lines N]
       tachyonc query unused [MODULE] [--all]
       tachyonc query impact NAME
       tachyonc query effects NAME...|MODULE [--has EFFECT] [--why EFFECT]   (alloc(Gpa) io global panic diverge unsafe)
       tachyonc query views NAME...|MODULE [--why]   (what results and `&mut` parameters view: views(self), views(*self), stores(word))
       tachyonc query conflicts [FILE|DIR|FILE:LINE...] [--show]
       tachyonc query similar NAME... [--limit N]   (items like NAME to copy, nearest first)
       tachyonc query examples [KIND...]   (items to start from for an "add an X" change; tachyonc guide how)
NAME: a path or its end (f, m::f, T::f, T.field), or FILE:LINE; std's too (std::f, Vec::push)
--budget TOKENS: any answer cut to about TOKENS (default 8000; 0: no limit; context: 2000)
ROOT: --root ROOT, a last argument ending in .tach, $TACHYON_ROOT, ./main.tach, ./compiler/src/main.tach
see docs/query.md and docs/refactor.md
