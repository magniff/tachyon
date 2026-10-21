## (0.20) fix --only conventions (docs/design/conventions.md §9.2): the
## 0.19 spelling rewritten in 0.20's, by types. First the part the checker
## of Phase 0 means as 0.19 did (conventions-spelling: `x: &T` becomes `x:
## let T`, `&e` given to it stays, no `*r` goes): the program checks and
## prints what it printed (7 5 1 1 6 1 3 10 3 10). Then the rest, which
## needs T1's checking (accesses used as their values: `out += a`), so it
## is refused without --no-check. `let shared = &v;` is left to hand.
$ fix --only conventions-spelling --list-left
fixed 2 parameters to let, 4 parameters to inout, 2 parameters to sink, 4 receivers, 5 '&mut e's to '&e', 7 'let mut's / 'mut x's to var, 1 inout local, 1 static var, 1 sink closure, 1 access type	main.tach	+25 -25 lines
main.tach:62:5: a shared reference local ('let r = &e;'): use 'e' itself, or a let parameter
note fix.conv_left: 1 left to hand: a shared reference local ('let r = &e;'): use 'e' itself, or a let parameter
$ main.tach -o prog
ok: built prog
% ./prog
7
5
1
1
6
1
3
10
3
10
## The rest: `x: let T` is `x: T`, `&e` to a let goes, `*out` is `out`,
## an inout binding or parameter passed on is lent again (`fill(&r, 2)`).
## Until T1 the result does not check (`out += a` writes through an access).
$ fix --only conventions
main.tach:26:37: error[type error] cannot assign to immutable variable 'out' | help: make the parameter mutable: `mut out: &mut i64`  [edited: crate::report]
note fix.conv_left: 1 left to hand: a shared reference local ('let r = &e;'): use 'e' itself, or a let parameter
error edit.breaks: 1 new error; nothing written
try: tachyonc fix --only conventions --no-check
[exit 1]
$ fix --only conventions --no-check --show
main.tach:26:37: error[type error] cannot assign to immutable variable 'out' | help: make the parameter mutable: `mut out: &mut i64`  [edited: crate::report]
fixed 2 parameters to let, 4 '&mut e's to '&e', 2 '&e's to a let, 2 '*r's of accesses	main.tach	+7 -7 lines
// main.tach:14
14	fn total(v: Vec<i64>) -> i64 {
// main.tach:24
24	fn fill_twice(v: inout Vec<i64>) { fill(&v, 1); fill(&v, 2); }
// main.tach:26
26	fn report(a: i64, out: inout i64) { out += a; }
// main.tach:33
33	    var p = Parser { toks: toks, pos: 0, out: &out };
// main.tach:43
43	    println(total(v));
// main.tach:45
45	    fill(&r, 2);
// main.tach:49
49	    report(k, &sum);
note fix.conv_left: 1 left to hand: a shared reference local ('let r = &e;'): use 'e' itself, or a let parameter
warning edit.breaks: 1 new error; written anyway (--no-check)
try: tachyonc check
