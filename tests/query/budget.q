## The output budget and the diagnostics (budget/): 70 calls of `bump`
## in two files, six `size` functions, a line longer than 100 bytes; and
## every usage error.
$ refs bump
budget/main.vl	47
budget/util.vl	24
note query.truncated: 71 refs in 2 files
try: volec query refs bump --in budget/main.vl
try: volec query refs bump --limit 60
try: volec query refs bump --all
$ refs bump --count
71
$ callers bump --all --in main.vl
# budget/main.vl
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
$ refs bump --in util.vl
# budget/util.vl
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
# budget/main.vl
15:16	call	many	t += util::bump(0);
16:16	call	many	t += util::bump(1);
17:16	call	many	t += util::bump(2);
note query.truncated: showing 3 of 71 refs
try: volec query refs bump --in budget/main.vl
try: volec query refs bump --in crate --all
$ refs bump --limit 2
# budget/main.vl
15:16	call	many	t += util::bump(0);
16:16	call	many	t += util::bump(1);
note query.truncated: showing 2 of 71 refs
try: volec query refs bump --in budget/main.vl
try: volec query refs bump --all
$ refs bump --in nosuch
error query.bad-in: no file, module or item 'nosuch' in the program
try: volec query refs bump
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
try: volec query show crate::m1::size
[exit 1]
$ show m2::size
// crate::m2::size	budget/main.vl:7-7	effects: none
mod m2 { pub fn size() -> i64 { 2 } }
$ callers long_line
# budget/main.vl
63:15	call	main	(many() + long_line() + m1::size()) as i32
$ refs bump --in long_line
# budget/main.vl
59:11	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:27	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:43	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:59	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:75	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:91	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
59:107	call	long_line	util::bump(1) + util::bump(2) + util::bump(3) + util::bump(4) + util::bump(5) + util::bump(6) + uti…
$ refs bump --bogus
error query.usage: unknown option '--bogus'
try: volec query refs bump
[exit 2]
$ refs bump --limit
error query.usage: --limit needs a number
try: volec query refs bump --limit 60
[exit 2]
$ refs bump --limit x
error query.usage: --limit needs a number
try: volec query refs bump --limit 60
[exit 2]
$ refs bump --in
error query.usage: --in needs a FILE or MODULE
try: volec query refs bump
[exit 2]
$ refs bump budget/main.vl extra
error query.usage: unexpected argument 'extra'
try: volec query refs bump budget/main.vl
[exit 2]
$ refs bump nosuch.vl
error query.bad-root: cannot read 'nosuch.vl'
try: volec query refs bump
[exit 2]
$ defs bump
error query.usage: unknown command 'defs'
try: volec query def bump
[exit 2]
$ items mm1
error query.no-match: no module 'mm1'
try: volec query items crate::m1
[exit 1]
$ def util::bumpp
error query.no-match: no definition 'util::bumpp'
try: volec query def crate::util::bump
[exit 1]
$ def utill::bump
error query.no-match: no definition 'utill::bump'
try: volec query def crate::util::bump
[exit 1]
$ 
error query.usage: no command
try: volec query items
[exit 2]
$ --help
usage: volec query def|show NAME... [--root ROOT] [--exact] [--with-comments]
       volec query show FILE.vl | MODULE::use | MODULE::header | MODULE::extern
       volec query context NAME...|MODULE [--budget TOKENS]   (source, calls, types, callers)
       volec query text FILE[:A[-B]]...
       volec query diff
       volec query refs|callers NAME... [--exact] [--count] [--in FILE|MODULE|ITEM] [--limit N] [--all]
       volec query callees FN... [--transitive] [--writes TABLE] [--count] [--limit N] [--all]
       volec query items [MODULE...] [--comments]
       volec query show MODULE::section TITLE
       volec query grep PATTERN... [--in FILE|MODULE|ITEM] [--code] [--comments] [--strings] [--word] [--count] [--limit N] [--all]
       volec query type FILE:LINE[:COL]...
       volec query own FILE:LINE:COL...   (0.17: each local's kind, moves and views there)
       volec query stats [MODULE|FILE] [--over N] [--all]
       volec query deps MODULE [--max-lines N]
       volec query unused [MODULE] [--all]
       volec query impact NAME
       volec query effects NAME...|MODULE [--has EFFECT] [--why EFFECT]   (alloc(Gpa) io global panic diverge unsafe)
       volec query features NAME... [--why FEATURE] [-C target-cpu=CPU] [-C target-feature=+x,-y]   (std::arch: what a function needs beyond the build's features)
       volec query arch WORDS... [--feature F] [--arch aarch64|x86_64|portable] [--equiv NAME]   (std::arch: the intrinsics by name, instruction, feature or doc; also query intrinsics)
       volec query views NAME...|MODULE [--why]   (what results and `&mut` parameters view: views(self), views(*self), stores(word))
       volec query conflicts [FILE|DIR|FILE:LINE...] [--show]
       volec query similar NAME... [--limit N]   (items like NAME to copy, nearest first)
       volec query examples [KIND...]   (items to start from for an "add an X" change; volec guide how)
NAME: a path or its end (f, m::f, T::f, T.field), or FILE:LINE; std's too (std::f, Vec::push)
--budget TOKENS: any answer cut to about TOKENS (default 8000; 0: no limit; context: 2000)
ROOT: --root ROOT, a last argument ending in .vl, $VOLE_ROOT, ./main.vl, ./compiler/src/main.vl
see docs/query.md and docs/refactor.md
