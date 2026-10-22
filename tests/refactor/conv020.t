## (0.20) fix --only conventions (docs/design/conventions.md §9.2): the
## 0.19 spelling rewritten in 0.20's, by types, with T1's checking:
## `x: &T` is `x: T`, `&e` to it goes, `*out` is `out` (an access is used
## as its value), an inout binding or parameter passed on is lent again
## (`fill(&r, 2)`). The result checks and prints what it printed (7 5 1 1 6
## 1 3 10 3 10). `let shared = &v;` is left to hand. (The spelling stage
## alone, `conventions-spelling`, wrote 0.20's words with 0.19's meaning:
## since T1 it is only the first half of this one.)
$ fix --only conventions --list-left
fixed 2 parameters to let, 4 parameters to inout, 2 parameters to sink, 4 receivers, 9 '&mut e's to '&e', 2 '&e's to a let, 2 '*r's of accesses, 7 'let mut's / 'mut x's to var, 1 inout local, 1 static var, 1 sink closure, 1 access type	main.vl	+27 -27 lines
main.vl:62:5: a shared reference local ('let r = &e;'): use 'e' itself, or a let parameter
note fix.conv_left: 1 left to hand: a shared reference local ('let r = &e;'): use 'e' itself, or a let parameter
$ --syntax=0.20 main.vl -o prog
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
