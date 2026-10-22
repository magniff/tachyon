## (0.17) `query own FILE:LINE:COL`: the locals in scope there, each with
## its type and kind (plain, owned, view); the own pass's state (moves,
## views, what invalidated them) when front/own/observe.vl has it.
$ own own017/main.vl:14:5
own017/main.vl:14:5 in crate::main
gpa    Gpa       plain
v      Vec<i64>  owned
first  [i64]     view  views v
t      Tok       view  views nothing (static data)
$ own own017/main.vl:16:17
own017/main.vl:16:17 in crate::main
gpa    Gpa       plain
v      Vec<i64>  owned
first  [i64]     view  views v
t      Tok       view  views nothing (static data)
n      i64       plain
$ own own017/main.vl:5:23
own017/main.vl:5:23 in crate::total
v  let Vec<i64>  view
s  i64           plain
x  i64           plain
$ own own017/main.vl:1
error query.no-match: own017/main.vl:1 is in no function the checker saw
try: volec query show own017/main.vl:1
[exit 1]
$ own own017/main.vl
error query.usage: own needs a position, FILE:LINE:COL (not 'own017/main.vl')
[exit 1]
